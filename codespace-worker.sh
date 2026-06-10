#!/usr/bin/env bash
# Codespace Worker - Run commands in ephemeral GitHub Codespaces
# https://github.com/SuperInstance/codespace-worker

set -euo pipefail

REPO="${1:?Usage: codespace-worker <repo> '<command>' [output-file]}"
CMD="${2:?No command provided}"
OUTPUT="${3:-}"

NAME="cs-worker-$(basename "$REPO" .git)-$$"
BRANCH="codespace-worker-$(date +%s)"

echo "🚀 Starting codespace for $REPO..."

# Create codespace
CODESPACE=$(gh codespace create \
    --repo "$REPO" \
    --branch "$BRANCH" \
    --machine basicLinux32gb \
    --idle-timeout 10m \
    --display-name "$NAME" 2>&1 | tail -1)

echo "✅ Created codespace: $CODESPACE"

wait_for_ready() {
    local waits=0
    while true; do
        if gh codespace wait --codespace "$CODESPACE" --timeout 10 2>/dev/null; then
            return 0
        fi
        sleeps=$((waits % 30))
        if [ $sleeps -eq 0 ]; then
            echo "⏱️ Waiting for codespace to be ready..."
        fi
        sleeps=$((sleeps +1 ))
        waits=$((waits +1))
        if [ $waits -gt 60 ]; then
            echo "❌ Codespace failed to start"
            return 1
        fi
        sleep 10
    done
}

if ! wait_for_ready; then
    gh codespace delete --codespace "$CODESPACE" --force >/dev/null 2>&1
    exit 1
fi

# Run command
echo "💻 Executing command: $CMD"
if [ -n "$OUTPUT" ]; then
    gh codespace ssh --codespace "$CODESPACE" -- "$CMD" 2>&1 > "$OUTPUT"
    echo "📦 Output saved to $OUTPUT"
else
    gh codespace ssh --codespace "$CODESPACE" -- "$CMD" 2>&1
fi

EXIT=$?
echo "✅ Command complete (exit code: $EXIT)"

# Cleanup
echo "🧹 Cleaning up codespace..."
gh codespace delete --codespace "$CODESPACE" --force >/dev/null 2>&1 || true

exit $EXIT
