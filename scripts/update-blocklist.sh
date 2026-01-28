#!/bin/bash
set -euo pipefail

# StevenBlack hosts blocklist updater
# Downloads and prepares the StevenBlack unified hosts file for CoreDNS blocker plugin

BLOCKLIST_URL="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
BLOCKLIST_PATH="${BLOCKLIST_PATH:-/var/lib/coredns/blocklist.txt}"
TMP_FILE="/tmp/blocklist.txt.tmp"

echo "[$(date -Iseconds)] Starting blocklist update..."

# Download blocklist
if curl -sSL -f -o "$TMP_FILE" "$BLOCKLIST_URL"; then
    echo "[$(date -Iseconds)] Successfully downloaded blocklist from $BLOCKLIST_URL"
    
    # Count entries (excluding comments and localhost)
    ENTRY_COUNT=$(grep -E "^0\.0\.0\.0 " "$TMP_FILE" | grep -v "0.0.0.0 0.0.0.0" | wc -l)
    echo "[$(date -Iseconds)] Blocklist contains $ENTRY_COUNT entries"
    
    # Atomic move to target location
    mv "$TMP_FILE" "$BLOCKLIST_PATH"
    echo "[$(date -Iseconds)] Blocklist updated successfully at $BLOCKLIST_PATH"
else
    echo "[$(date -Iseconds)] ERROR: Failed to download blocklist from $BLOCKLIST_URL" >&2
    exit 1
fi

# Optional: Trigger CoreDNS reload if running
# The blocker plugin automatically detects file changes based on the configured interval
# so no manual reload is needed, but you can force it with:
# pkill -SIGUSR1 coredns
