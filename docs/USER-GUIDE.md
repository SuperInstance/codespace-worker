# codespace-worker — User Guide

For anyone who wants to run a command on a fresh GitHub-hosted machine and throw the
machine away — cross-arch builds, agent offloads, batch jobs — without learning Codespaces.

## What you get

One command, `codespace-worker.sh`, that does the whole ephemeral-Codespace lifecycle for
you:

1. creates a Codespace for a repository you name (32 GB Linux machine, 10-minute idle
   timeout),
2. waits until it is ready,
3. runs your command inside it over SSH,
4. prints the output (or saves it to a file you name), and
5. force-deletes the Codespace.

You bring nothing but the `gh` CLI, logged in. No tokens to manage (gh owns auth), no
containers to build, no cleanup to remember on the happy path.

## Install

```bash
git clone https://github.com/SuperInstance/codespace-worker
cd codespace-worker
# Requirements (verify with):
gh --version        # GitHub CLI installed
gh auth status      # logged in, token has the 'codespace' scope
bash --version      # any modern bash (the script uses set -euo pipefail)
```

There is nothing else to install — no dependencies, no build step. Keep
`codespace-worker.sh` anywhere on your PATH (or invoke it by path).

## First success in 5 minutes

The first real run creates a billable (free-tier-eligible) Codespace and takes minutes —
provisioning was measured at ~11 minutes on the free tier:

```bash
bash codespace-worker.sh SuperInstance/codespace-worker "uname -a && cat /etc/os-release | head -2"
# Expected shape:
#   🚀 Starting codespace for SuperInstance/codespace-worker...
#   ✅ Created codespace: cs-worker-codespace-worker-<pid>
#   ⏱️ Waiting for codespace to be ready...        ← appears while provisioning
#   💻 Executing command: uname -a && cat /etc/os-release | head -2
#      Linux <host> ... x86_64 / aarch64
#   ✅ Command complete (exit code: 0)
#   🧹 Cleaning up codespace...
```

Verify nothing was left behind:

```bash
gh codespace list    # should not contain cs-worker-* (give slow deletions a moment)
```

If you only want to inspect before spending a provisioning cycle:
`bash -n codespace-worker.sh` (syntax) and `gh codespace list` (current state).

## Everyday usage

### Run a build in the repo's own Codespace image

```bash
bash codespace-worker.sh SuperInstance/some-repo "npm ci && npm test"
```

The command runs in the repo's default devcontainer (or GitHub's default image if the
repo has none), from the branch the script selects — see the branch caveat in
ONBOARDING/troubleshooting before your first run on a repo you do not control.

### Save output to a file

```bash
bash codespace-worker.sh SuperInstance/some-repo "make cross-arch-build" build.log
# stdout → build.log ; stderr → your terminal (that is what `2>&1 > file` ordering does)
```

### Offload an agent's heavy step

```bash
bash codespace-worker.sh SuperInstance/agent-repo \
  "python3 -m heavy_battery --suite full --json > /tmp/result.json && cat /tmp/result.json" results.json
```

The pattern: run the expensive thing remotely, print the small artifact, keep the Codespace
ephemeral. State you need to keep must come out via stdout (the machine is deleted).

### Clean up after a failed run

Because a failing remote command skips the script's cleanup step:

```bash
gh codespace list --json name,state --jq '.[] | select(.name | startswith("cs-worker-"))'
gh codespace delete --codespace <name> --force
```

### Sweep for idle leftovers

The script's `--idle-timeout 10m` means abandoned Codespaces stop billing after ten idle
minutes, but explicit hygiene is better:

```bash
gh codespace list && gh codespace delete --codespace <name> --force
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Create fails immediately with a branch error | The script passes `--branch codespace-worker-<epoch>`, a branch it never creates | Pre-create that branch on the remote, or edit the `BRANCH=` line to an existing branch (e.g. `main`). Known defect — see ONBOARDING |
| `gh: command not found` | gh CLI not installed | Install gh (https://cli.github.com) and `gh auth login` |
| `error: --codespace <name>: not found` mid-run | The `tail -1` name capture missed (gh output format changed, or create emitted a warning last) | `gh codespace list` to find the real name; delete it; consider pinning the name manually |
| Script exits non-zero right after "Executing command" | Your remote command failed; `set -e` aborts before cleanup/echo | The exit code is your command's. Delete the leftover Codespace (see cleanup recipes) |
| Output file empty but the command clearly printed | Your command wrote to stderr | `2>&1 > file` sends stdout to the file, stderr to the terminal; redirect inside the command if you need both: `"cmd 2>&1"` |
| "Codespace failed to start" after long wait | Provisioning exceeded the wait budget (~10+ min of failed polls) | Delete any partial Codespace (`gh codespace delete --force`) and retry; free-tier provisioning was receipted at ~11 min |
| Codespace keeps running after the script died | Failure path skips cleanup | Delete by hand; the `--idle-timeout 10m` backstop stops billing on idle |
| Command needs sudo/packages | Default image limits | Do setup inside the command string (`sudo apt-get ...`), or add a devcontainer to the target repo |

## FAQ

**Q: Where does the tool store my GitHub token?**
Nowhere. Authentication is the `gh` CLI's own stored credential (`gh auth login`); the
script only calls `gh`. No token material exists in the repo, and none is passed around.

**Q: What machine am I billed for?**
`basicLinux32gb` (4-core/8GB-RAM/32GB-disk class), created per run, deleted at the end
(or idle-stopped after 10 minutes if a failure path stranded it). On a free-plan account
this falls under the GitHub Codespaces free monthly allowance; on a paid plan it bills
per core-hour — the runbook is: keep jobs short, always confirm deletion.

**Q: Which branch/commit does my command see?**
The branch the script passes to `gh codespace create` — currently the invented
`codespace-worker-<epoch>` name, which is the known defect: it must exist on the remote
for create to succeed, so today the practical path is editing `BRANCH=` or pre-creating
it. There is no commit-pin option yet.

**Q: Can I keep the Codespace to iterate inside?**
Not with this script — it is one-shot by design. Its fork,
`quilt-codespace/driver/oracle-worker.sh`, adds exactly that (`create` + `ssh` +
`delete` as separate verbs, plus a refs watch mode). Use that when you need persistence.

**Q: Can I run GUI or long-lived services?**
The script ssh-executes one command and then deletes the machine; anything long-lived
dies with it. For a persistent runtime tier, use quilt-codespace instead — that is the
division of labor between the two repos.

**Q: Does it work for private repos?**
Yes, as long as the authenticated gh user can access the repo and create Codespaces for
it. The tool adds no permissions of its own.
