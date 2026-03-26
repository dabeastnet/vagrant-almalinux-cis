# =============================================================================
# Vagrantfile — AlmaLinux 9 CIS Level 2 lab VM
#
# Provider  : virtualbox
# Box       : alma9-cis-local  (built by packer/ — run .\build.ps1 first)
#
# Requirements (Windows host):
#   VirtualBox  https://www.virtualbox.org/
#   Vagrant     https://developer.hashicorp.com/vagrant/downloads
#   Git for Windows (provides rsync for synced folder)
#     https://git-scm.com/download/win
#
# Provisioning order:
#   1. bootstrap.sh       — system update, ansible install, vagrant compat
#   2. install-openscap.sh — openscap + scap-security-guide packages
#   3. ansible_local       — extra CIS controls not covered by oscap
#   4. run-remediation.sh  — oscap generate fix + execute bash remediation
#   5. run-scan.sh         — final compliance scan, HTML + XML reports
# =============================================================================

VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|

  # ── Box ───────────────────────────────────────────────────────────────────
  config.vm.box              = "alma9-cis-local"
  config.vm.box_check_update = false
  config.vm.hostname         = "alma9-cis"

  # ── Synced folder ─────────────────────────────────────────────────────────
  # Rsync project into VM so ansible_local can find the playbooks.
  # Requires rsync — included with Git for Windows (git-scm.com).
  config.vm.synced_folder ".", "/vagrant",
    type:           "rsync",
    rsync__args:    ["--archive", "--verbose", "--compress"],
    rsync__exclude: [
      ".git/",
      "packer/output-alma9-cis/",
      "packer/*.iso",
      "*.box",
      "*.log",
      "reports/"
    ]

  # Reports are written inside the VM under /reports.
  # Use scan.sh on the host to scp them back.

  # ── VirtualBox provider ───────────────────────────────────────────────────
  config.vm.provider "virtualbox" do |vb|
    vb.memory = 4096  # OpenSCAP needs >= 2 GB; 4 GB recommended
    vb.cpus   = 2
    vb.name   = "alma9-cis"
    vb.gui    = false
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Provisioning steps
  # ═══════════════════════════════════════════════════════════════════════════

  # Step 1 — bootstrap
  config.vm.provision "shell",
    name:        "bootstrap",
    path:        "provisioning/bootstrap.sh",
    upload_path: "/home/vagrant/bootstrap.sh",
    privileged:  true

  # Step 2 — install OpenSCAP toolchain
  config.vm.provision "shell",
    name:        "install-openscap",
    path:        "provisioning/install-openscap.sh",
    upload_path: "/home/vagrant/install-openscap.sh",
    privileged:  true

  # Step 3 — Ansible: extra CIS controls + Vagrant compatibility
  config.vm.provision "ansible_local" do |ansible|
    ansible.playbook           = "ansible/site.yml"
    ansible.install            = true
    ansible.install_mode       = :default  # uses dnf/yum
    ansible.become             = true
    ansible.compatibility_mode = "2.0"
    ansible.verbose            = false
    ansible.extra_vars         = {
      "vagrant_mode" => true
    }
  end

  # Step 4 — oscap remediation (generates bash fix, runs it, reboots)
  config.vm.provision "shell",
    name:        "run-remediation",
    path:        "provisioning/run-remediation.sh",
    upload_path: "/home/vagrant/run-remediation.sh",
    privileged:  true

  # Step 5 — final compliance scan
  config.vm.provision "shell",
    name:        "run-scan",
    path:        "provisioning/run-scan.sh",
    upload_path: "/home/vagrant/run-scan.sh",
    privileged:  true

end
