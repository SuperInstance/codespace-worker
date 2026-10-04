# codespace-worker — Knowledge Map

The index of indexes for this repo. Small repo, complete map.

## In this repo

- `codespace-worker.sh` — the entire system (67 lines): positional contract
  `<repo> '<command>' [output-file]`; lifecycle `gh codespace create` (basicLinux32gb,
  idle-timeout 10m, display-name `cs-worker-<repo>-<pid>`, branch
  `codespace-worker-<epoch>`) → `wait_for_ready` (poll `gh codespace wait`, ~10-minute
  failure budget) → `gh codespace ssh -- <cmd>` (stdout to the optional file) →
  `gh codespace delete --force` → exit. Known defects (branch never created; cleanup
  skipped on remote-command failure) are documented, not hidden.
- `README.md` — the one-line quick start and the fleet-wide tool index pointer.
- `LICENSE` — MIT, Copyright (c) 2026 SuperInstance.
- `.gitignore` — `.env*`, OS junk, IDE dirs, `build/`, `dist/`.
- `docs/` — this wave-69 documentation package (6 files + this map; no pre-existing docs
  were replaced).
- Deliberately absent: `.github/` (no CI), any package manifest, any test suite, any
  receipt ledger. Each absence is called out in the docs rather than papered over.

## Pre-existing docs (before wave-69)

- `README.md` — the quick start ("Run commands remotely in ephemeral GitHub Codespaces",
  the one-liner example) and a pointer to the SuperInstance tool index. That is the
  complete pre-existing prose; there was no DESIGN, no CONTRIBUTING, no changelog.

## In the fleet

- `SuperInstance/quilt-codespace` — downstream fork: its `driver/oracle-worker.sh` header
  states "Fork of the codespace-worker one-shot pattern, extended for the oracle"
  (`--keep`, separate `ssh`/`delete` verbs, `watch` via `git ls-remote`). Sibling in the
  tier model: this repo is the one-shot offload CLI, quilt-codespace is the persistent
  runtime tier.
- `SuperInstance/agent-workspace-template` — the devcontainer/post-create pattern family
  the Codespace repos share (relationship: pattern sibling; no code dependency).
- `SuperInstance/git-agent` — named consumer of the offload pattern in the SEED DNA
  synergy notes (quilt-atlas `seed-dna.json`, git-agent entry: synergies include
  "codespace-worker (offload)").
- `SuperInstance/superinstance-lab` — the journal repo (worklog.md) holding the
  provisioning receipts this tool was built against.
- `SuperInstance/jev-garden` / `fleet-seeds` — adjacent lanes whose idle-compile /
  codespace-recurring ideas (journal lines ~680–689) are the future consumers of this
  channel.

## In the journal

Local journal copy: `/home/z/my-project/worklog.md` (canonical:
SuperInstance/superinstance-lab → worklog.md). Grep `codespace-worker`:

- Line ~652 (wave-49): the principal's directive that chartered both this repo and
  quilt-codespace ("quilt-codespace + codespace-worker, codespaces enabled...").
- Line ~657 (wave-49): the identity receipt — "codespace-worker = remote ephemeral
  offload CLI".
- Line ~660 (wave-49): the provisioning lesson that motivates the tool — "post-create
  duration needs a longer window or codespace-worker.sh path. Queued."
- Line ~1227: the meta+external family decomposition pass lists the codespace family
  (with quilt-codespace; codespace-worker belongs to the same family cluster).
- No dedicated build/fix entry for this repo was found by grep — its build history is
  unverified at journal level; the wave-49 directive plus the identity line are the
  journal's whole visible record.

## Receipts of record

- The journal's wave-49/50 entries (lines ~652–689) are the load-bearing receipts for
  the *channel*: token-can-provision, ~11-minute Available window, repo-scoped create
  endpoint working, exec-blocked-in-sandbox limitation, zero-extraction deletion.
- In-repo, there are no receipts (no CI runs, no ledgers, no logs committed) — an honest
  gap this documentation wave flags in ONBOARDING (frontier: a self-build CI run would be
  the standing receipt).
- `bash -n codespace-worker.sh` is the only credential-free verification available.

## How to search further

```bash
# Everything the script does with gh (the whole API surface):
grep -n "gh " codespace-worker.sh

# The failure/retry logic:
sed -n '26,49p' codespace-worker.sh          # wait_for_ready, verbatim

# Where the pattern went next (fork):
grep -n "codespace-worker" ../quilt-codespace/driver/oracle-worker.sh ../quilt-codespace/docs/*.md

# Channel receipts in the journal:
grep -n "codespace" /home/z/my-project/worklog.md | head -20

# Fleet-wide mentions (offload consumers):
grep -rn "codespace-worker" ../quilt-atlas/seed-dna/seed-dna.json
```
