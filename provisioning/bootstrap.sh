#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — Step 1 provisioner
# Runs as root inside the VM.
# Purpose: system update, Ansible install, Vagrant usability safety net.
# =============================================================================
set -euo pipefail

echo "============================================================"
echo " STEP 1: Bootstrap"
echo "============================================================"

# ── System update ─────────────────────────────────────────────────────────
dnf -y update --nobest 2>&1 | tail -5

# ── Ensure EPEL is available (needed for some Ansible collections) ─────────
dnf -y install epel-release || true

# ── Install Ansible (system package, AlmaLinux 9 ships ansible-core) ──────
dnf -y install ansible-core python3-pip

# ── Install required Ansible collections ──────────────────────────────────
mkdir -p /usr/share/ansible/collections
ansible-galaxy collection install ansible.posix community.general \
    --collections-path /usr/share/ansible/collections \
    --force-with-deps 2>&1 | tail -5

# ── Ensure /reports directory exists with open write perms ────────────────
mkdir -p /reports
chmod 1777 /reports

# ── Vagrant SSH key safety net ────────────────────────────────────────────
# The hardening steps may tighten SSH config. Re-assert insecure key here
# so provisioning doesn't break. run-remediation.sh will tighten again.
mkdir -pm 700 /home/vagrant/.ssh
if [[ ! -f /home/vagrant/.ssh/authorized_keys ]]; then
    cat > /home/vagrant/.ssh/authorized_keys << 'SSHEOF'
ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key
SSHEOF
fi
chmod 0600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant:vagrant /home/vagrant/.ssh

# ── Ensure vagrant sudoers file is intact ────────────────────────────────
if [[ ! -f /etc/sudoers.d/vagrant ]]; then
    echo "vagrant ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/vagrant
    chmod 0440 /etc/sudoers.d/vagrant
fi

echo "=== Bootstrap complete ==="
