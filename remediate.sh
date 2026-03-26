#!/usr/bin/env bash
# =============================================================================
# remediate.sh — Re-run oscap remediation + scan on a running VM
#
# Use this when you want to apply remediation again after manual changes,
# or when the initial build scored below the 95% target.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Check VM is running ───────────────────────────────────────────────────
if ! vagrant status 2>/dev/null | grep -q "running"; then
    echo "ERROR: VM not running. Start it with: vagrant up" >&2
    exit 1
fi

echo "=== Step 1: Sync provisioning scripts to VM ==="
vagrant rsync

echo ""
echo "=== Step 2: Run remediation ==="
vagrant ssh -c "sudo bash /vagrant/provisioning/run-remediation.sh"

echo ""
echo "=== Step 3: Run post-remediation scan ==="
vagrant ssh -c "sudo bash /vagrant/provisioning/run-scan.sh"

echo ""
echo "=== Step 4: Fetch reports ==="
./scan.sh --fetch

echo ""
echo "Remediation complete. Check ./reports/ for results."
