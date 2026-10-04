# codespace-worker — Developer Guide

For developers extending or fixing `codespace-worker.sh`. The entire codebase is one
67-line bash script; this guide walks it top to bottom and then covers the honest defects.

## Code layout

```
codespace-worker/
├── codespace-worker.sh   # everything: arg parsing, create, wait, exec, cleanup
├── README.md             # quick start + fleet tool index pointer
├── LICENSE               # MIT, Copyright (c) 2026 SuperInstance
├── .gitignore            # .env*, OS junk, IDE dirs, build/, dist/
└── docs/                 # this wave-69 documentation package
```

No `.github/` directory exists — no CI, no workflows, no issue templates. No package
manifest of any kind. That absence is part of the design (and part of the frontier: see
ONBOARDING's "Current frontier").

## Core concepts (named as the code names them)

- **Positional contract**: `$1` = `REPO` (`owner/name`, required, no default),
  `$2` = `CMD` (the remote command string, required), `$3` = `OUTPUT` (optional file;
  when set, remote stdout goes to the file, stderr stays on the terminal).
- **`NAME` / `BRANCH`**: the Codespace's human display name is
  `cs-worker-$(basename "$REPO" .git)-$$` (PID-suffixed); the branch requested is
  `codespace-worker-$(date +%s)` — epoch-suffixed, and (the defect) never created.
- **`CODESPACE`**: the machine-readable Codespace name, captured as the last line of
  `gh codespace create` output. Every later `gh` call addresses the machine by this name.
- **`wait_for_ready`**: the readiness loop — `gh codespace wait --codespace "$CODESPACE"
  --timeout 10` (output suppressed); on failure, sleep 10 and retry; a progress line
  prints every 30th failed round; ~60 failed rounds (`waits > 60`) → give up, caller
  deletes and exits 1.
- **Lifecycle**: `create → wait_for_ready → ssh exec → echo → delete --force → exit`.
  Every `gh` call is non-interactive; the only auth is gh's stored credential.
- **`set -euo pipefail`**: fail-fast posture — which is exactly what makes the two known
  defects (cleanup skip, unreachable `EXIT=$?`) behave the way they do.

## How to extend

### Fix the branch defect (the first patch this repo wants)

Replace the invented branch with an explicit optional 4th argument, falling back to the
repo default:

```bash
BRANCH="${4:-}"    # was: BRANCH="codespace-worker-$(date +%s)"
CREATE_ARGS=(--repo "$REPO" --machine basicLinux32gb --idle-timeout 10m --display-name "$NAME")
[ -n "$BRANCH" ] && CREATE_ARGS+=(--branch "$BRANCH")
CODESPACE=$(gh codespace create "${CREATE_ARGS[@]}" 2>&1 | tail -1)
```

Tradeoff to respect: the epoch branch name was presumably meant to give each run a clean
workspace; an explicit-branch model moves that burden to the caller, so document it in
the usage line (`?Usage: codespace-worker <repo> '<command>' [output-file] [branch]`).

### Make cleanup unconditional

Guard the tail with a trap so the Codespace dies no matter how the script exits:

```bash
cleanup() { gh codespace delete --codespace "$CODESPACE" --force >/dev/null 2>&1 || true; }
trap cleanup EXIT
```

and drop the manual delete before `exit $EXIT`. With `set -e`, the trap fires on the
failing remote command too — which fixes the leaked-Codespace failure mode outright.

### Capture the real exit code

The current `EXIT=$?` is unreachable on failure because `set -e` aborts first. The
idiomatic fix:

```bash
set +e
if [ -n "$OUTPUT" ]; then
  gh codespace ssh --codespace "$CODESPACE" -- "$CMD" > "$OUTPUT" 2>&1
else
  gh codespace ssh --codespace "$CODESPACE" -- "$CMD"
fi
EXIT=$?
set -e
```

Note the also-corrected redirection: `> "$OUTPUT" 2>&1` (both streams to the file) —
decide which behavior you actually want; the original `2>&1 > "$OUTPUT"` sends stderr to
the terminal, which some callers may prefer; pick one and document it.

### Add a "keep" mode (parity with the fork)

`driver/oracle-worker.sh` in quilt-codespace already demonstrates the shape: separate
`create` / `ssh` / `delete` verbs instead of one fused run. Minimal version here: if
`$1` is a verb, dispatch; else keep the current positional contract. Keep the one-shot
path default — it is this tool's identity.

## Testing

There is no test suite and no CI. The verification ladder, cheapest first:

```bash
bash -n codespace-worker.sh                       # 1. syntax (no credentials)
SHELL=sh shellcheck -s bash codespace-worker.sh   # 2. static analysis (if shellcheck exists)
gh auth status && gh codespace list               # 3. prerequisites live
# 4. cheapest true end-to-end (a real billable cycle, ~minutes):
bash codespace-worker.sh SuperInstance/codespace-worker "true"
# 5. failure-path drill (expect non-zero exit AND a leftover Codespace today):
bash codespace-worker.sh SuperInstance/codespace-worker "exit 3"
gh codespace list                                  # → clean it up manually (known defect)
```

What green means: run 4 exits 0, prints the four emoji milestones, and leaves
`gh codespace list` clean; run 5 exits 3 — and, until the trap fix lands, strands a
Codespace, which is precisely the behavior a regression pin should encode then forbid.

## Conventions

- **No dependencies beyond gh and bash** — any extension that wants `jq`, `python`, or
  non-gh network calls should justify itself in ORACLE-style notes or be rejected; the
  tool's value is its zero-surface.
- **Stdout discipline**: the script's own narration goes to stdout/stderr with emoji
  prefixes (🚀 ✅ ⏱️ 💻 📦 🧹); the remote command's stdout is the payload. Keep narration
  on the script side and payload on the remote side, or output files become mixed.
- **Non-interactive gh only**: every gh invocation must work headless in a lane sandbox
  (that is the whole point — agents are the primary callers).
- **Zero-extraction discipline** (fleet norm): the Codespace is deleted after each run;
  nothing is "kept" from it without an explicit design decision (see the fork's `--keep`).
- **Commit style**: small, imperative, one concern per commit; there is no git history
  convention to inherit yet beyond the fleet norm of task-ID references in messages.

## Gotchas for editors

- `CODESPACE=$(... 2>&1 | tail -1)` captures *any* last line — warnings included. If you
  touch the create call, test what its output's last line actually is for both success
  and failure; the failure path currently feeds garbage into `wait_for_ready`, which then
  fails honestly but confusingly.
- The `waits`/`sleeps` counters in `wait_for_ready` are interdependent (`sleeps=$((waits
  % 30))` drives the progress message); simplifying one line changes when users see
  progress. Read the loop as a whole before editing it.
- `wait` is a shell builtin name — the function is `wait_for_ready`, and gh's subcommand
  is `gh codespace wait`; do not collapse them.
- `--idle-timeout 10m` is a GitHub-side backstop, not a script timeout; do not remove it
  thinking it duplicates `wait_for_ready`.
- The script assumes `ssh` exists on the caller (gh codespace ssh shells out to ssh). In
  minimal sandboxes (the wave-50 receipt hit exactly this: "no ssh binary, no sudo") the
  exec leg fails regardless of this script's correctness.
