#!/usr/bin/env bash
# SSH helper for exchange-rate cron scripts.
# Tries alias 'dokploy2' first (uses shared config), falls back to explicit key.
# This is needed because launchd cannot read ~/.ssh/shared/config under all contexts.

ssh_cmd() {
    local remote_cmd="$1"

    # Try with alias first (cleaner, uses shared config)
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=20 -o BatchMode=yes \
        dokploy2 "$remote_cmd" 2>/dev/null; then
        return 0
    fi

    # Fallback: explicit IP + key (no config)
    local DOKPLOY_HOST="${DOKPLOY_HOST:-178.156.168.27}"
    local DOKPLOY_USER="${DOKPLOY_USER:-root}"
    local DOKPLOY_SSH_KEY="${DOKPLOY_SSH_KEY:-/Users/wiseconnex/.hermes/diana/secure/dokploy2_root_id_ed25519}"

    ssh -F /dev/null -i "$DOKPLOY_SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=20 -o BatchMode=yes \
        "$DOKPLOY_USER@$DOKPLOY_HOST" "$remote_cmd"
}
