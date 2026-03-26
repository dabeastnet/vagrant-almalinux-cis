#!/usr/bin/env bash
# =============================================================================
# install-openscap.sh — Step 2 provisioner
# Installs and verifies the full OpenSCAP toolchain.
# =============================================================================
set -euo pipefail

echo "============================================================"
echo " STEP 2: Install OpenSCAP + SCAP Security Guide"
echo "============================================================"

# ── Install packages ──────────────────────────────────────────────────────
dnf -y install \
    openscap \
    openscap-scanner \
    openscap-utils \
    scap-security-guide \
    scap-workbench \
    aide \
    audit \
    audit-libs \
    libselinux-utils \
    policycoreutils \
    policycoreutils-python-utils

# ── Locate SCAP content ────────────────────────────────────────────────────
SCAP_CONTENT=""
for f in \
    /usr/share/xml/scap/ssg/content/ssg-almalinux9-ds.xml \
    /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml \
    /usr/share/xml/scap/ssg/content/ssg-centos9-ds.xml; do
    if [[ -f "$f" ]]; then
        SCAP_CONTENT="$f"
        break
    fi
done

if [[ -z "$SCAP_CONTENT" ]]; then
    echo "ERROR: No SCAP content file found after installing scap-security-guide!" >&2
    exit 1
fi

echo "Found SCAP content: $SCAP_CONTENT"

# ── List available profiles ────────────────────────────────────────────────
echo ""
echo "--- Available SCAP profiles ---"
oscap info "$SCAP_CONTENT" | grep -A 200 "Profiles:" | head -40
echo ""

# ── Confirm CIS L2 profile presence ───────────────────────────────────────
if oscap info "$SCAP_CONTENT" | grep -q "cis_server_l2"; then
    echo "OK: CIS Server Level 2 profile found."
elif oscap info "$SCAP_CONTENT" | grep -q "cis"; then
    echo "WARNING: cis_server_l2 not found; will fall back to closest CIS profile."
else
    echo "WARNING: No CIS profile found in $SCAP_CONTENT."
    echo "  You may need a newer scap-security-guide package."
    echo "  See README.md for manual profile selection."
fi

# ── Save content path for other scripts ───────────────────────────────────
echo "$SCAP_CONTENT" > /etc/cis-scap-content-path

echo ""
echo "=== OpenSCAP install complete ==="
echo "    oscap version: $(oscap --version | head -1)"
