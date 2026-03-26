#!/usr/bin/env bash
# =============================================================================
# run-remediation.sh — Step 4 provisioner
#
# 1. Reads SCAP content path written by install-openscap.sh
# 2. Runs a BASELINE scan (pre-remediation) and saves the report
# 3. Generates an oscap bash remediation script from the CIS L2 profile
# 4. Executes the remediation script (tolerates non-fatal errors)
# 5. Restores Vagrant usability (SSH key + sudo) after hardening
# 6. Reloads sysctl / auditd / firewalld
# =============================================================================
set -uo pipefail   # Note: NOT -e here; remediation script exits non-zero intentionally

echo "============================================================"
echo " STEP 4: oscap Remediation"
echo "============================================================"

REPORTS_DIR="/reports"
mkdir -p "$REPORTS_DIR"

# ── Resolve SCAP content and profile ──────────────────────────────────────
SCAP_CONTENT=$(cat /etc/cis-scap-content-path 2>/dev/null || echo "")
if [[ -z "$SCAP_CONTENT" || ! -f "$SCAP_CONTENT" ]]; then
    echo "ERROR: SCAP content path not set. Did install-openscap.sh run?" >&2
    exit 1
fi

# Select the best available CIS profile
PROFILE=""
for p in \
    xccdf_org.ssgproject.content_profile_cis_server_l2 \
    xccdf_org.ssgproject.content_profile_cis; do
    if oscap info "$SCAP_CONTENT" | grep -q "$p"; then
        PROFILE="$p"
        break
    fi
done

if [[ -z "$PROFILE" ]]; then
    echo "ERROR: No suitable CIS profile found in $SCAP_CONTENT" >&2
    exit 1
fi

echo "Using profile : $PROFILE"
echo "SCAP content  : $SCAP_CONTENT"
echo ""

# ── Pre-remediation (baseline) scan ──────────────────────────────────────
echo "--- Running baseline scan (pre-remediation) ---"
oscap xccdf eval \
    --profile          "$PROFILE" \
    --results          "$REPORTS_DIR/scan-before-results.xml" \
    --report           "$REPORTS_DIR/scan-before-report.html" \
    --oval-results \
    "$SCAP_CONTENT" \
    2>&1 | tee "$REPORTS_DIR/scan-before.log" || true

echo ""
echo "--- Baseline scan complete. Report: $REPORTS_DIR/scan-before-report.html ---"
echo ""

# ── Generate bash remediation script ──────────────────────────────────────
echo "--- Generating oscap bash remediation script ---"
oscap xccdf generate fix \
    --profile  "$PROFILE" \
    --fix-type bash \
    --output   "$REPORTS_DIR/remediation-generated.sh" \
    "$SCAP_CONTENT" 2>&1 || true

if [[ ! -f "$REPORTS_DIR/remediation-generated.sh" ]]; then
    echo "ERROR: oscap failed to generate remediation script" >&2
    exit 1
fi
chmod +x "$REPORTS_DIR/remediation-generated.sh"
echo "Remediation script: $REPORTS_DIR/remediation-generated.sh"

# ── Execute the remediation ────────────────────────────────────────────────
echo ""
echo "--- Executing remediation (errors are tolerated) ---"
bash "$REPORTS_DIR/remediation-generated.sh" 2>&1 \
    | tee "$REPORTS_DIR/remediation.log" \
    | grep -E '^(ERROR|WARNING|FAIL|oscap|Remediating|#)' || true

echo ""
echo "--- Remediation script execution finished ---"

# ── Restore Vagrant usability ─────────────────────────────────────────────
# oscap remediation may have tightened SSH or PAM. Restore the minimum
# required for Vagrant to keep working.

echo ""
echo "--- Restoring Vagrant compatibility post-remediation ---"

# 1. SSH: keep PubkeyAuthentication, allow PasswordAuthentication only from
#    127.0.0.1 (Vagrant sometimes uses password for provisioning fallback).
#    The final SSH configuration is further set by Ansible (vagrant-compat.yml).
sshd_config=/etc/ssh/sshd_config
grep -q "^PubkeyAuthentication yes" "$sshd_config" || \
    sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"

# 2. Ensure vagrant user key is present
if [[ ! -f /home/vagrant/.ssh/authorized_keys ]]; then
    mkdir -pm 700 /home/vagrant/.ssh
    cat > /home/vagrant/.ssh/authorized_keys << 'SSHEOF'
ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key
SSHEOF
    chmod 0600 /home/vagrant/.ssh/authorized_keys
    chown -R vagrant:vagrant /home/vagrant/.ssh
fi

# 3. Ensure vagrant sudoers intact
if [[ ! -f /etc/sudoers.d/vagrant ]]; then
    echo "vagrant ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/vagrant
    chmod 0440 /etc/sudoers.d/vagrant
fi

# ── Reload services ───────────────────────────────────────────────────────
echo ""
echo "--- Reloading services ---"
sysctl --system              2>&1 | tail -3  || true
systemctl daemon-reload                       || true
systemctl restart sshd                        || true
systemctl restart auditd                      || true
systemctl restart firewalld                   || true
systemctl restart rsyslog                     || true

# ── Initialize AIDE database ──────────────────────────────────────────────
# Run after all changes are done so the baseline is accurate.
echo ""
echo "--- Initialising AIDE database (this takes ~2 min) ---"
aide --init 2>&1 | tail -5 || true
if [[ -f /var/lib/aide/aide.db.new.gz ]]; then
    mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
    echo "AIDE database initialised: /var/lib/aide/aide.db.gz"
fi

echo ""
echo "=== Remediation step complete ==="
