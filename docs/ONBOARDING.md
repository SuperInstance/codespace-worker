# codespace-worker — Agent Onboarding
> Zero-shot entry point. Clone → competent in ~10 minutes.

## Identity (2 sentences)

codespace-worker is a single-file bash tool, `codespace-worker.sh`, that runs a command
inside a throwaway GitHub Codespace and hands you the output: it creates a Codespace for
a repo, waits for it to become ready, ssh-executes your command, streams/saves the
result, and force-deletes the Codespace. It exists for work that does not fit a laptop
or a lane — cross-arch builds, agent offloads, batch jobs — and it is deliberately the
minimal member of the fleet's Codespace family (one script, no dependencies beyond the
`gh` CLI).

## Why it exists (the fleet problem it solves)

Fleet agents run in sandboxes with limited CPU, no GPU, and no exotic architectures;
some jobs (big builds, cross-arch checks, long test batteries) need a disposable machine
with network and real resources. GitHub Codespaces are exactly that machine, and the
wave-49/50 journal receipts proved the channel: a token can provision one, provisioning
takes ~11 minutes on the free tier, and long post-create windows need either a longer
wait budget or "the codespace-worker.sh path" (the journal's own words, line ~660).
Wave-49's charter (journal line ~652) directed this repo alongside quilt-codespace:
codespace-worker is the one-shot offload CLI; quilt-codespace is the long-lived runtime
tier that later forked this pattern into its `driver/oracle-worker.sh`.

## Verify it works (exact commands)

```bash
# 0. Syntax check — no credentials needed:
bash -n codespace-worker.sh && echo "syntax ok"

# 1. Real verification REQUIRES the gh CLI, installed AND authenticated with the
#    codespace scope (this tool stores no tokens itself — auth is gh's own):
gh auth status          # must show a logged-in account; scopes include 'codespace'
gh --version

# 2. A dry look at the lifecycle it will drive (no side effects):
gh codespace list --json name,state,repository

# 3. The real thing — creates a codespace, runs the command, deletes it. This BILLS a
#    Codespace to the authenticated account for the job's duration:
bash codespace-worker.sh SuperInstance/codespace-worker "uname -a && node --version" out.txt
# Expected console shape:
#   🚀 Starting codespace for SuperInstance/codespace-worker...
#   ✅ Created codespace: <name>
#   ⏱️ Waiting for codespace to be ready...      (if provisioning is slow)
#   💻 Executing command: uname -a && node --version
#   📦 Output saved to out.txt
#   ✅ Command complete (exit code: 0)
#   🧹 Cleaning up codespace...
```

If you lack a gh-authenticated account, you cannot execute step 3 — there is no offline
mode and no receipt of a prior run inside this repo (it ships no ledger). The wave-49/50
journal entries (superinstance-lab → worklog.md, lines ~652–689) are the receipts that
the underlying channel (create → wait → exec → delete) works against this account.

## Reading order (paths, not vibes)

1. `codespace-worker.sh` — 67 lines; read it whole. Positional contract:
   `<repo> '<command>' [output-file]`; lifecycle create → wait → exec → cleanup.
2. `README.md` — the one-line quick start and the fleet tool index pointer.
3. `.github/` — absent: this repo has no CI, no workflows (verified; nothing to read).
4. In quilt-codespace: `driver/oracle-worker.sh` — the fork of this one-shot pattern with
   `--keep`, SSH exec, and a `watch` mode; read it to see where this design went next.
5. In the journal (`/home/z/my-project/worklog.md`, canonical
   SuperInstance/superinstance-lab → worklog.md): lines ~652, ~657, ~660 — the directive,
   the identity receipt, and the provisioning-window lesson this tool answers.

## The things that will bite you (gotchas)

- **The script invents a branch it never creates.** `BRANCH="codespace-worker-$(date +%s)"`
  is passed to `gh codespace create --branch`, but nothing pushes that branch to the
  remote. On repos where it does not exist, create fails. Unverified against a live `gh`
  in this doc pass (no authenticated gh in the sandbox), but it follows from gh's
  documented `--branch` behavior. Workaround until patched: pre-create/push the branch,
  or edit the `BRANCH=` line to an existing branch (e.g. `BRANCH="main"`).
- **A failing remote command skips cleanup.** `set -euo pipefail` aborts the script the
  moment `gh codespace ssh` exits non-zero, so the final `gh codespace delete` never
  runs — the exit code propagates, but the Codespace is left running until its
  `--idle-timeout 10m` backstop. Sweep with `gh codespace list` + `gh codespace delete`.
- **`EXIT=$?` is unreachable on failure** — for the same reason, the "Command complete
  (exit code: N)" line only ever prints for exit 0. A non-zero remote command still
  yields a non-zero script exit (via `set -e`), just without the echo or cleanup.
- **Output redirection order is `2>&1 > "$OUTPUT"`.** That sends stdout to the file and
  stderr to your terminal — usually what you want, but do not expect the file to contain
  stderr.
- **Provisioning time vs wait budget.** The wave-50 receipt measured ~11 minutes to
  Available on the free tier; the built-in loop polls `gh codespace wait --timeout 10`
  with 10-second sleeps and gives up after ~60 failed rounds. Slow provisions can still
  lose the race; deleting a half-made Codespace is handled (`--force`), but the job dies.
- **`CODESPACE` is captured as `tail -1` of create output.** If `gh` changes its create
  output format, the name capture breaks silently — check `gh codespace list` if anything
  downstream says "not found".
- **The ephemeral Codespace starts from the repo's default devcontainer.** Repos without
  one get GitHub's default image — the tool adds no environment of its own.

## Where deeper knowledge lives

- Knowledge map: [docs/KNOWLEDGE-MAP.md](./KNOWLEDGE-MAP.md)
- Fleet journal: SuperInstance/superinstance-lab → worklog.md (grep 'codespace-worker';
  local copy /home/z/my-project/worklog.md — lines ~652/657/660).
- Downstream fork: quilt-codespace `driver/oracle-worker.sh` + its docs (the same
  lifecycle, extended with keep/ssh/watch semantics).
- Sibling: quilt-codespace (the persistent runtime tier this repo is the one-shot
  counterpart of); `README.md` in that repo maps the tier model.
- `LICENSE` — MIT (Copyright (c) 2026 SuperInstance).

## Current frontier (what is open right now)

- **Branch handling** is the one open defect (see gotchas): either pre-create the
  timestamped branch or accept an explicit branch argument. A two-line fix, pending a
  lane with a live gh.
- **Cleanup on failure** wants a `trap ... EXIT` so deleted-then-exit is unconditional.
- **No CI and no receipts** in-repo: a workflow that runs the script against this very
  repo (`bash codespace-worker.sh SuperInstance/codespace-worker "true"`) would be the
  standing liveness receipt the repo currently lacks.
- **Keep/exec iteration modes** exist only in the fork (oracle-worker.sh `--keep`,
  `watch`); folding the useful ones back here is an open, unforced option.
