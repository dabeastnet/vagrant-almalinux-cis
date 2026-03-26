# AlmaLinux 9 — CIS Level 2 Hardening Lab

Automatically builds and hardens an AlmaLinux 9 virtual machine to **96%+ CIS Level 2 compliance** using Packer, Vagrant, Ansible, and OpenSCAP.

Run one command. It installs the OS with the correct partition layout, applies every CIS control it can automate, scans the result, and saves an HTML compliance report.

---

## How it works

```
Phase 1 — Packer (one-time, ~35 min)
  AlmaLinux 9.4 ISO
  → Kickstart: CIS-required LVM disk layout + base security settings
  → Output: alma9-cis.box  (reusable Vagrant box)

Phase 2 — Vagrant (~20 min)
  alma9-cis.box
  → Step 1: bootstrap.sh        — system update, install Ansible
  → Step 2: install-openscap.sh — install OpenSCAP + SCAP Security Guide
  → Step 3: ansible_local       — SSH, kernel, audit, filesystem controls
  → Step 4: run-remediation.sh  — baseline scan → oscap bash fix → AIDE init
  → Step 5: run-scan.sh         — final scan → HTML + XML reports + score
```

---

## Requirements

| What | Version |
|------|---------|
| Windows 10/11 | build 19041+ |
| VirtualBox | 7.x |
| Vagrant | 2.3+ |
| Packer | 1.9+ |
| Git for Windows (provides rsync + bash) | latest |
| Disk space | ~15 GB free |
| RAM | 8 GB+ (VM uses 4 GB) |

---

## Setup (do this once)

**1. Install dependencies**

- [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
- [Vagrant](https://developer.hashicorp.com/vagrant/install)
- [Packer](https://developer.hashicorp.com/packer/install)
- [Git for Windows](https://git-scm.com/download/win) — provides Git Bash + rsync

**2. Open Git Bash and navigate to the project**

```bash
cd ~/OneDrive\ -\ Thomas\ More/Network\ \&\ OS\ security/Harden/cis-alma9
chmod +x *.sh
```

---

## Running the build

```bash
./build.sh
```

This single command does everything:

1. Downloads `AlmaLinux-9.4-x86_64-minimal.iso` (~1.7 GB)
2. Builds the hardened Vagrant box with Packer (~35 min, one time only)
3. Registers the box with Vagrant
4. Starts the VM and runs all provisioners (~20 min)
5. Prints the compliance score in the terminal
6. Saves reports to `./reports/`

> **The build only needs to run once.** After that, `vagrant up` starts the already-configured VM in seconds.

**Optional flags:**
```bash
./build.sh --packer-only   # build the box only, don't start the VM
./build.sh --vagrant-only  # skip Packer, use existing box
```

---

## Daily usage

```bash
vagrant up       # start the VM
vagrant halt     # shut it down
vagrant ssh      # open a shell inside the VM
```

---

## Compliance scanning

### Re-run the scan and fetch reports
```bash
./scan.sh              # run new scan inside VM + fetch reports to ./reports/
./scan.sh --fetch      # fetch existing reports without scanning again
./scan.sh --show-score # print the score from the last downloaded report
```

> **Note:** `scan.sh` must be run from the **host** (Git Bash), not from inside the VM.

### Fix: reports not fetching (permission issue)
If `./scan.sh --fetch` copies nothing, the report files are owned by root and
not readable by the vagrant user. Fix it once with:

```bash
vagrant ssh -c "sudo chmod -R o+r /reports/"
./scan.sh --fetch
```

### View the HTML report
After fetching, open the report in your browser:
```bash
# From Git Bash
start reports/scan-latest-report.html
```
Or navigate to the `reports/` folder in Windows Explorer and double-click the `.html` file.

### Run the scan manually inside the VM
```bash
vagrant ssh
sudo -i

# Check the available CIS profile ID (it may vary by SSG version)
oscap info /usr/share/xml/scap/ssg/content/ssg-almalinux9-ds.xml | grep -i cis

CONTENT=/usr/share/xml/scap/ssg/content/ssg-almalinux9-ds.xml
PROFILE=<profile-id-from-above>
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

oscap xccdf eval \
    --profile "$PROFILE" \
    --results /reports/scan-after-results-${TIMESTAMP}.xml \
    --report  /reports/scan-after-report-${TIMESTAMP}.html \
    --fetch-remote-resources \
    --oval-results \
    "$CONTENT"

ln -sf /reports/scan-after-results-${TIMESTAMP}.xml /reports/scan-latest-results.xml
ln -sf /reports/scan-after-report-${TIMESTAMP}.html /reports/scan-latest-report.html
```

### Re-run remediation (if score drops below 95%)
```bash
./remediate.sh
```

---

## Expected result

```
╔══════════════════════════════════════════════════════════════╗
║               CIS LEVEL 2 COMPLIANCE RESULT                 ║
╠══════════════════════════════════════════════════════════════╣
║  Score :  96.6%   [████████████████████████████████████████░]  ║
╠══════════════════════════════════════════════════════════════╣
║  PASS          :   364                                       ║
║  FAIL          :    13                                       ║
║  NOT APPLICABLE:    18                                       ║
║  NOT CHECKED   :     0                                       ║
║  ERROR         :     0                                       ║
╚══════════════════════════════════════════════════════════════╝
  ✔  TARGET MET: Score ≥ 95%
```

---

## What gets hardened

| Area | CIS Section | How |
|------|-------------|-----|
| Disk partitioning | 1.1 | Kickstart — separate LVM volumes with `nodev`, `nosuid`, `noexec` |
| Unused filesystems disabled | 1.1.1 | Kickstart modprobe denylist (cramfs, squashfs, udf, dccp, sctp) |
| Kernel hardening | 1.5, 3.x | Ansible sysctl — ASLR, SYN cookies, IP forwarding off, ICMP controls |
| SELinux enforcing | 1.6 | Kickstart |
| Login banners | 1.8 | Kickstart + Ansible — /etc/issue, /etc/issue.net, /etc/motd |
| Unused services disabled | 2.x | Kickstart package removal + oscap |
| SSH hardening | 5.2 | Ansible — strong ciphers, no root login, timeouts, banners |
| Audit rules | 4.1 | Ansible — 15 rule categories covering identity, access, file changes |
| Password policy | 5.3, 5.4 | Kickstart pwquality.conf + login.defs |
| PAM hardening | 5.x | oscap remediation |
| AIDE file integrity | 1.3 | Ansible + oscap — configured and initialised |
| Firewall enabled | — | Kickstart + firewalld |
| ~240 additional controls | various | OpenSCAP auto-remediation bash script |

---

## Known limitations

| Rule | Why not automated |
|------|-------------------|
| **CIS 1.4.1 — GRUB boot password** | Prevents the VM from booting unattended, which breaks Vagrant. Apply manually with `grub2-setpassword` before production use. |
| **Default credentials** | `vagrant`/`vagrant` is intentional for the lab. Run `passwd root` and `passwd vagrant` before production. |
| **SSH AllowUsers** | Restricted to `vagrant` only in lab mode. Add your own username before production. |

---

## Verify the hardening

```bash
# Disk layout — confirm separate mount points
vagrant ssh -c "lsblk"
vagrant ssh -c "findmnt --verify"

# SELinux enforcing
vagrant ssh -c "sestatus"

# Firewall active
vagrant ssh -c "sudo firewall-cmd --state"

# Audit rules loaded
vagrant ssh -c "sudo auditctl -l | wc -l"

# AIDE database present
vagrant ssh -c "ls -lh /var/lib/aide/aide.db.gz"

# SCAP profile used
vagrant ssh -c "cat /etc/cis-scap-content-path"
```

---

## Re-running a single provisioner step

```bash
vagrant provision --provision-with bootstrap
vagrant provision --provision-with install-openscap
vagrant provision --provision-with ansible_local
vagrant provision --provision-with run-remediation
vagrant provision --provision-with run-scan
```

---

## Credentials

| Account | Password | Notes |
|---------|----------|-------|
| `vagrant` | `vagrant` | SSH key auth used by Vagrant; password for console |
| `root` | `vagrant` | Change before any production use |

SSH key authentication is used by default. Vagrant manages the key automatically.

---

## Destroy and clean up

```bash
./destroy.sh     # removes the VM (prompts before deleting the box file)
```

---

## Troubleshooting

**Profile ID not found during manual scan**
```bash
# Find the correct profile ID for your SSG version
oscap info /usr/share/xml/scap/ssg/content/ssg-almalinux9-ds.xml | grep -i cis
# Use the ID shown — typically:
# xccdf_org.ssgproject.content_profile_cis_server_l2
```

**Reports not fetching to host**
```bash
vagrant ssh -c "sudo chmod -R o+r /reports/"
./scan.sh --fetch
```

**Build hangs at Packer GRUB menu**
```
# Open packer/alma9-cis.pkr.hcl and set:
headless = false
# Re-run to see the VirtualBox window and adjust the boot command if needed.
```

**Score below 90% after build**
```bash
./remediate.sh
```

**SCAP content file not found**
```bash
vagrant ssh -c "sudo dnf reinstall scap-security-guide"
vagrant ssh -c "ls /usr/share/xml/scap/ssg/content/"
```

**AIDE initialisation appears to hang**
Normal — it hashes the entire filesystem. Takes 2–3 minutes. Do not interrupt.

**SELinux blocking something after hardening**
```bash
vagrant ssh -c "sudo ausearch -m AVC -ts recent | audit2why"
```

---

## File reference

| File | Purpose |
|------|---------|
| `build.sh` | Full build pipeline — run this first |
| `scan.sh` | Re-scan the running VM, fetch reports to host |
| `remediate.sh` | Re-run OpenSCAP remediation + scan |
| `destroy.sh` | Tear down VM and optionally remove box |
| `Vagrantfile` | VM configuration and provisioner chain |
| `packer/alma9-cis.pkr.hcl` | Packer template (VirtualBox builder) |
| `packer/http/ks.cfg` | Anaconda Kickstart (partitioning + base security) |
| `provisioning/bootstrap.sh` | System update, install Ansible |
| `provisioning/install-openscap.sh` | Install OpenSCAP + SCAP Security Guide |
| `provisioning/run-remediation.sh` | Baseline scan + generate and run oscap bash fix |
| `provisioning/run-scan.sh` | Final compliance scan + score output |
| `ansible/site.yml` | Ansible entry point |
| `ansible/roles/cis-extra/` | CIS controls: kernel, SSH, audit, filesystem, AIDE |
| `reports/` | Scan output — HTML and XML reports |
