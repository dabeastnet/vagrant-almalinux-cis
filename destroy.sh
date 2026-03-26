#!/usr/bin/env bash
# =============================================================================
# destroy.sh — Tear down the VM and optionally remove the Vagrant box
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BOX_NAME="alma9-cis-local"

echo "=== Destroying Vagrant VM ==="
vagrant destroy -f 2>/dev/null || echo "  (VM was not running)"

read -rp "Remove Vagrant box '${BOX_NAME}' as well? [y/N] " REMOVE_BOX
if [[ "${REMOVE_BOX,,}" == "y" ]]; then
    vagrant box remove --force "${BOX_NAME}" 2>/dev/null || echo "  (Box not registered)"
    echo "Box removed."
fi

read -rp "Remove built box file (alma9-cis.box)? [y/N] " REMOVE_FILE
if [[ "${REMOVE_FILE,,}" == "y" ]]; then
    rm -f alma9-cis.box
    echo "Box file removed."
fi

read -rp "Remove packer output directory? [y/N] " REMOVE_OUTPUT
if [[ "${REMOVE_OUTPUT,,}" == "y" ]]; then
    rm -rf packer/output-alma9-cis
    echo "Packer output removed."
fi

echo ""
echo "Cleanup complete."
echo "To rebuild from scratch: ./build.sh"
