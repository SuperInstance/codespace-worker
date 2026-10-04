# codespace-worker — CTO Brief

## One-paragraph value statement

codespace-worker is a 67-line bash tool that rents a disposable GitHub Codespace, runs
one command on it, returns the output, and deletes the machine — the fleet's minimal
answer to "this job does not fit my sandbox" (cross-arch builds, heavy test batteries,
agent offloads) at zero infrastructure and zero token-handling cost. Its strategic value
is mostly as a proven pattern: it chartered the fleet's Codespace channel (journal
receipts, waves 49–50) and its one-shot shape is the fork-parent of quilt-codespace's
persistent runtime driver.

## What it does & for whom

For agent lanes and developers: `bash codespace-worker.sh <repo> '<command>' [output]`
gives you a 32 GB Linux machine, your command's result, and no cleanup responsibility on
the happy path. Auth is the gh CLI's own credential; the tool stores and transmits no
secrets. Consumers today are fleet lanes needing offload capacity; the downstream fork
(quilt-codespace `driver/oracle-worker.sh`) serves the iterate-inside use-case.

## Maturity assessment

**Prototype — working pattern, defective default path.** The lifecycle it orchestrates
(create → wait → exec → delete) is receipted working against this GitHub account
(wave-50: a Codespace reached Available in ~11 minutes; zero-extraction deletion
verified). The script itself has one real defect — it requests a timestamped branch it
never creates, so out-of-the-box `gh codespace create` fails on repos lacking that
branch — and one operational sharp edge — a failing remote command aborts before cleanup
and strands a Codespace until the 10-minute idle backstop. Both are two-line fixes,
sketched in the developer guide. No CI, no tests, no usage ledger exist.

## Risks

| Risk | Severity | Mitigation status |
|---|---|---|
| Invented-but-uncreated branch breaks first runs | High (usability) | Documented with workarounds (explicit branch / pre-create); patch queued; unverified against live gh in the doc pass (no gh auth in sandbox) — flagged honestly |
| Stranded Codespace on remote-command failure (leak until idle-timeout) | Medium (cost, hygiene) | Contained by `--idle-timeout 10m` + sweep runbook; `trap cleanup EXIT` fix sketched |
| Name capture via `tail -1` of gh output | Low | Breaks loudly ("not found"); sweep by `cs-worker-` prefix; pinning the name is trivial |
| gh output/CLI drift | Low | Same mitigation; the tool is small enough to re-verify in minutes |
| Sandbox lacks ssh binary | Medium in lane contexts | External to the tool (gh codespace ssh shells out); receipted in wave-50; workaround: run from a lane with ssh |
| Secrets | None found | No token handling anywhere in the script; auth delegated entirely to gh; `.gitignore` excludes `.env*` |

## Cost profile

Per run: one `basicLinux32gb` Codespace for the job's duration (free-tier eligible within
GitHub's included allowance; per core-hour on paid plans) plus trivial gh API usage.
No other services, no storage, no model calls. The economic story is the point: a
cross-arch build costs core-minutes instead of a laptop afternoon or a build-server
subscription. All figures are estimates; the repo keeps no usage receipts.

## Strategic options

- **Invest (small, bounded)**: land the two queued fixes (explicit branch argument;
  `trap cleanup EXIT`) and add a self-referential CI run
  (`bash codespace-worker.sh SuperInstance/codespace-worker "true"`) as the standing
  liveness receipt. Half a day of lane time makes this tool trustworthy-by-default.
- **Maintain**: as-is, the tool remains useful for callers who read its docs (the
  workarounds are one-liners); zero ongoing cost.
- **Harvest-learnings**: the pattern is already harvested — quilt-codespace's driver is
  the extended fork; further investment belongs there (keep/watch semantics), with this
  repo kept deliberately minimal as the reference one-shot.
- **Retire**: not indicated while any lane lacks local compute headroom; if Codespace
  offload moves entirely to the fork's richer driver, retiring this repo in favor of it
  is a reasonable consolidation — its value then lives on as the fork's ancestor.

## Integration surface

Depends on: `gh` CLI (authenticated, codespace scope), ssh on the caller, GitHub
Codespaces availability for the target repo. Consumed by: fleet agent lanes as a shell
out; the fork imports the pattern, not the code. Sibling relationship: quilt-codespace
is the persistent-tier counterpart (its README maps the tier model and credits this repo
as a pattern source); the journal (superinstance-lab → worklog.md, lines ~652/657/660)
is the receipt trail for the channel this tool was built to use. Nothing in the fleet
hard-depends on this script — removing it regresses a convenience, not a capability.
