# codespace-worker — Engineering Notes

For engineers operating or reviewing the tool. The system is one bash script; the notes
below trace every behavior to its lines.

## Architecture

```
 caller (agent lane / human shell)
   │  bash codespace-worker.sh <repo> '<command>' [output-file]
   ▼
 codespace-worker.sh                       (set -euo pipefail)
   │
   ├─ gh codespace create --repo R --branch codespace-worker-<epoch>
   │      --machine basicLinux32gb --idle-timeout 10m --display-name cs-worker-<repo>-<pid>
   │      └─ CODESPACE = last line of output
   │
   ├─ wait_for_ready: loop { gh codespace wait --codespace C --timeout 10
   │                         │ ok → return 0
   │                         └ fail → sleep 10; progress line every 30th round;
   │                                  > 60 rounds → return 1 }
   │        └ on failure: gh codespace delete --force; exit 1
   │
   ├─ gh codespace ssh --codespace C -- "<CMD>"    (stdout → $OUTPUT if given)
   │
   ├─ EXIT=$? ; echo status
   └─ gh codespace delete --codespace C --force || true ; exit $EXIT

 credentials: gh CLI's own stored token only (codespace scope). Nothing else.
```

The tool is a pure orchestrator over the `gh codespace` API surface: it owns no state,
no files (beyond the optional output file), no credentials, and no post-run artifacts.
The target repo's own devcontainer defines the environment the command runs in.

## Invariants

1. **One-shot, no residue (happy path)** — create → exec → delete in one process; the
   only persistent artifact is the optional output file the caller named. Enforced by
   the linear script flow; violated only on the failure paths listed below.
2. **Auth stays in gh** — no token is read, written, or echoed by the script; the only
   secret material ever involved is gh's own stored credential. Enforced by absence of
   any token handling in the 67 lines (verified by reading all of them).
3. **Non-interactive everything** — every gh call must succeed headless; there are no
   prompts, no TTY assumptions beyond ssh's own.
4. **Fail-fast semantics** — `set -euo pipefail` means any gh failure aborts the run with
   that status; errors are never swallowed (the two `|| true`s are on cleanup paths
   only).
5. **Caller owns retention** — the tool never decides what to keep; output is streamed or
   file-redirected verbatim.

## Failure modes & blast radius

| Failure | Behavior | Blast radius |
|---|---|---|
| Missing/branchless `--branch` target (today's default path) | `gh codespace create` fails; `set -e` aborts | No Codespace (create failed); clean failure, but the tool is unusable out-of-the-box — the repo's one real defect (fix sketched in DEVELOPER-GUIDE) |
| Remote command exits non-zero | `set -e` aborts before echo/cleanup; script exits with the command's code | **Leaked Codespace** until `--idle-timeout 10m` stops it; caller must sweep `gh codespace list` |
| Provisioning slower than the wait budget | `wait_for_ready` returns 1 → delete --force → exit 1 | Codespace deleted; job lost; retry is the runbook (free-tier ~11 min was the wave-50 measurement) |
| gh output format change | `CODESPACE` captures a warning line instead of the name | Downstream `gh codespace wait/ssh/delete` fail "not found"; create's machine still exists → leak; sweep by display-name prefix `cs-worker-` |
| Caller sandbox lacks ssh binary | `gh codespace ssh` fails | Same abort-on-exec path as a failing command (wave-50 receipted exactly this in another lane's sandbox) |
| gh not authenticated | First gh call fails | Clean abort before any resource is created |
| Output file unwritable | Shell redirect fails before ssh runs | Clean abort; no Codespace created yet (redirect is evaluated when the command runs — after create; so actually a leak is possible: create already happened) |

Correction on the last row, for precision: the `> "$OUTPUT"` redirect is evaluated when
the ssh command runs, i.e. after create and wait — so an unwritable output path lands in
the leak path, not the clean-abort path. Blast-radius reasoning for this tool therefore
reduces to one rule: *anything that goes wrong after create strands a Codespace*; the
`--idle-timeout 10m` flag is the only automatic containment, and a manual sweep
(`gh codespace list` / `delete --force`) is the operational answer.

## Performance & cost envelope

- **Wall-clock per run** = provisioning (measured ~11 min free-tier in the wave-50
  journal; faster on warm repos/machines, unverified here) + seconds for exec + deletion.
  The tool's cost is dominated by Codespace boot, which it does not control; its own
  overhead is negligible (a handful of gh calls).
- **Money**: one `basicLinux32gb` Codespace per run, deleted at completion (or
  idle-stopped after 10 min). Free-tier eligible within GitHub's monthly included
  storage/hours; on paid plans, per core-hour. Estimates, not receipts — this repo keeps
  no usage ledger.
- **API budget**: ~4–8 gh calls per run (create, repeated wait/list polls, ssh, delete).
  Trivial against any rate limit.

## Operations

- **Runbook (happy path)**: `bash codespace-worker.sh <repo> '<cmd>' [out]`, then
  `gh codespace list` to confirm zero residue.
- **Runbook (stranded machine)**: `gh codespace list --json name,state,repository`,
  delete anything matching `cs-worker-*` with `--force`.
- **Runbook (stuck provisioning)**: wave-49/50 established the pattern — patience to
  ~11 min first; delete only after that window; retry once; escalate to the fork
  (`driver/oracle-worker.sh`) which polls up to 5 minutes in 5-second intervals.
- **Credentials model**: gh CLI's stored token, user-scoped, codespace capability
  required. Nothing env-var-based, nothing stored by the tool; a lane needs
  `gh auth login` (or an exported GH_TOKEN that gh honors) before this tool works.
- **CI**: none. The tool is its own CI target when a lane runs it (see ONBOARDING
  frontier: a self-build workflow would be the standing liveness receipt).

## Design decisions & why

1. **One fused command, not subcommands** — the primary caller is an agent lane that
   wants "run this there, give me output" in one line; subcommands (create/ssh/delete)
   exist in the fork for the iterative use-case, and the split between the two repos is
   deliberate: one-shot here, persistent there. Tradeoff: no keep-mode here, accepted.
2. **`gh` as the only API surface** — zero token handling, zero REST code, free
   auth/rotation/ssh transport. Tradeoff: coupling to gh's human-readable output (the
   `tail -1` name capture) and to gh's presence; both are receipted gotchas.
3. **`basicLinux32gb` + `--idle-timeout 10m` as hard-coded defaults** — the largest
   free-tier-adjacent machine for build headroom, with a billing backstop that contains
   any stranded machine. Tradeoff: no size knob; add one only with a cost note.
4. **set -euo pipefail** — lanes calling this tool need honest non-zero exits more than
   best-effort completion. Tradeoff: the leak-on-failure behavior documented above; the
   trap fix (DEVELOPER-GUIDE) reconciles the two without dropping fail-fast.
5. **Timestamped invented branch** — intended to give every run a pristine workspace
   without touching the caller's branches. Tradeoff: it never creates the branch, which
   converts the intended convenience into the tool's one real defect; the explicit-branch
   patch is the queued remedy.
