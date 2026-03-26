#!/usr/bin/env bash
# =============================================================================
# build.sh — Full build pipeline
#
# Usage:
#   ./build.sh             # full build (packer + vagrant up)
#   ./build.sh --vagrant-only  # skip packer, use existing box
#   ./build.sh --packer-only   # only build the box, don't start VM
#
# Requirements (Linux host):
#   packer              >= 1.9   (https://developer.hashicorp.com/packer)
#   qemu-kvm            + libvirt + virt-manager (or just qemu-system-x86_64)
#   vagrant             >= 2.3   (https://developer.vagrantup.com)
#   vagrant-libvirt     plugin   (vagrant plugin install vagrant-libvirt)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BOX_NAME="alma9-cis-local"
BOX_FILE="alma9-cis.box"
ISO_VERSION="9.4"
ISO_NAME="AlmaLinux-${ISO_VERSION}-x86_64-minimal.iso"
ISO_URL="https://repo.almalinux.org/almalinux/${ISO_VERSION}/isos/x86_64/${ISO_NAME}"
ISO_PATH="packer/${ISO_NAME}"

PACKER_ONLY=false
VAGRANT_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --packer-only)   PACKER_ONLY=true  ;;
        --vagrant-only)  VAGRANT_ONLY=true ;;
        --help|-h)
            echo "Usage: $0 [--packer-only | --vagrant-only]"
            exit 0 ;;
    esac
done

# ── Colour helpers ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Check prerequisites ───────────────────────────────────────────────────
check_cmd() {
    command -v "$1" &>/dev/null || { error "Required command not found: $1"; exit 1; }
}

info "Checking prerequisites..."
check_cmd vagrant

if ! $VAGRANT_ONLY; then
    check_cmd packer
    check_cmd qemu-system-x86_64
fi

# Check vagrant-libvirt plugin
if ! vagrant plugin list | grep -q vagrant-libvirt; then
    warn "vagrant-libvirt plugin not installed. Installing..."
    vagrant plugin install vagrant-libvirt
fi

ok "Prerequisites satisfied."

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1: Packer build
# ════════════════════════════════════════════════════════════════════════════
if ! $VAGRANT_ONLY; then

    # ── Download ISO ──────────────────────────────────────────────────────
    if [[ ! -f "$ISO_PATH" ]]; then
        info "Downloading AlmaLinux ${ISO_VERSION} minimal ISO (~1.7 GB)..."
        mkdir -p packer
        curl -L --progress-bar "$ISO_URL" -o "$ISO_PATH"
        ok "ISO downloaded: $ISO_PATH"
    else
        ok "ISO already present: $ISO_PATH"
    fi

    # ── Compute checksum ──────────────────────────────────────────────────
    info "Computing SHA-256 checksum..."
    ISO_CHECKSUM="sha256:$(sha256sum "$ISO_PATH" | awk '{print $1}')"
    ok "Checksum: $ISO_CHECKSUM"

    # ── Packer init (download plugins) ────────────────────────────────────
    if [[ ! -d packer/.packer.d ]]; then
        info "Running packer init..."
        (cd packer && packer init .)
    fi

    # ── Build the box ─────────────────────────────────────────────────────
    if [[ -f "$BOX_FILE" ]]; then
        warn "Box file $BOX_FILE already exists. Skipping packer build."
        warn "Delete $BOX_FILE and re-run to rebuild."
    else
        info "Starting Packer build (this takes ~30–45 min)..."
        info "To watch progress: export PACKER_LOG=1 before running this script."
        info "For a VNC window: edit packer/alma9-cis.pkr.hcl and set headless = false"
        echo ""
        (cd packer && packer build \
            -var "iso_url=file://${SCRIPT_DIR}/${ISO_PATH}" \
            -var "iso_checksum=${ISO_CHECKSUM}" \
            alma9-cis.pkr.hcl)
        ok "Packer build complete. Box: ${BOX_FILE}"
    fi

    $PACKER_ONLY && { ok "Packer-only mode. Done."; exit 0; }

fi  # end PACKER phase

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2: Register box with Vagrant
# ════════════════════════════════════════════════════════════════════════════
if vagrant box list | grep -q "^${BOX_NAME}"; then
    ok "Vagrant box '${BOX_NAME}' already registered."
else
    if [[ ! -f "$BOX_FILE" ]]; then
        error "Box file $BOX_FILE not found. Run without --vagrant-only first."
        exit 1
    fi
    info "Adding box to Vagrant: ${BOX_NAME}"
    vagrant box add --force --name "${BOX_NAME}" "${BOX_FILE}"
    ok "Box registered."
fi

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3: Vagrant up (provisions + hardens + scans)
# ════════════════════════════════════════════════════════════════════════════
info "Starting Vagrant VM and running provisioners..."
info "Expected duration: ~15–25 min (package install + AIDE init + scan)"
echo ""
vagrant up --provider=libvirt

echo ""
ok "================================================================"
ok "  Build complete!"
ok "  VM status      : vagrant status"
ok "  SSH into VM    : vagrant ssh"
ok "  Fetch reports  : ./scan.sh --fetch"
ok "  Re-scan VM     : ./scan.sh"
ok "  Destroy VM     : ./destroy.sh"
ok "================================================================"
