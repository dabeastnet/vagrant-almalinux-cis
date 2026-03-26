# =============================================================================
# Packer template — AlmaLinux 9 CIS Level 2 base box
# Builder : VirtualBox (virtualbox-iso)
# Output  : alma9-cis.box  (Vagrant box)
#
# Prerequisites (Windows host):
#   packer init .    (run once from the packer/ directory)
#   .\build.ps1      (run from project root — do not run packer directly)
#
# VirtualBox and Vagrant must be installed on the Windows host.
# =============================================================================

packer {
  required_plugins {
    virtualbox = {
      version = ">= 1.0.5"
      source  = "github.com/hashicorp/virtualbox"
    }
    vagrant = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/vagrant"
    }
  }
}

# ── Variables ──────────────────────────────────────────────────────────────
variable "iso_url" {
  type        = string
  description = "Path or URL to the AlmaLinux 9.4 minimal ISO. build.ps1 downloads it locally."
  default     = "https://vault.almalinux.org/9.4/isos/x86_64/AlmaLinux-9.4-x86_64-minimal.iso"
}

variable "iso_checksum" {
  type        = string
  description = "SHA-256 checksum. build.ps1 computes this from the local file."
  default     = "none"
}

variable "disk_size_mb" {
  type    = number
  default = 40960 # 40 GB
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "cpus" {
  type    = number
  default = 2
}

variable "vm_name" {
  type    = string
  default = "alma9-cis"
}

variable "output_box" {
  type    = string
  default = "alma9-cis.box"
}

# ── Source ─────────────────────────────────────────────────────────────────
source "virtualbox-iso" "alma9_cis" {
  vm_name      = var.vm_name
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  # Disk — SATA interface so disk appears as /dev/sda inside the guest
  disk_size            = var.disk_size_mb
  hard_drive_interface = "sata"

  # CPU / RAM
  cpus   = var.cpus
  memory = var.memory_mb

  # Guest OS
  guest_os_type        = "RedHat_64"
  guest_additions_mode = "disable" # rsync synced folder — no Guest Additions needed

  # Run headless; set to false to open a VirtualBox window for debugging
  headless = true

  # HTTP server to serve the kickstart file
  http_directory = "http"
  http_port_min  = 8100
  http_port_max  = 8199

  # SSH communicator — Packer connects after install completes
  communicator = "ssh"
  ssh_username = "vagrant"
  ssh_password = "vagrant"
  ssh_timeout  = "90m"
  ssh_port     = 22

  # How long to wait after boot before sending keystrokes
  boot_wait = "10s"

  # ── Boot command ────────────────────────────────────────────────────────
  # AlmaLinux 9.4 minimal ISO uses ISOLINUX for BIOS boot.
  #   <up>   — select "Install AlmaLinux 9.4" (default is media-test entry)
  #   <tab>  — open ISOLINUX command-line editor
  #   append inst.ks= URL, press Enter to boot
  boot_command = [
    "<wait>",
    "<up>",
    "<tab>",
    " inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
    "<enter>",
    "<wait>"
  ]

  # Allow the VM's NAT adapter to reach Packer's HTTP server on the host
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--nat-localhostreachable1", "on"],
  ]

  # Shutdown command (vagrant user has passwordless sudo)
  shutdown_command = "echo vagrant | sudo -S /sbin/poweroff"
}

# ── Build ──────────────────────────────────────────────────────────────────
build {
  name    = "alma9-cis"
  sources = ["source.virtualbox-iso.alma9_cis"]

  provisioner "shell" {
    remote_folder = "/home/vagrant"
    inline = [
      "echo '>>> Packer shell provisioner — verifying build'",
      "cat /etc/almalinux-release",
      "lsblk",
      "df -hT",
      "sestatus",
      "echo '>>> OK'"
    ]
  }

  post-processor "vagrant" {
    output               = "../${var.output_box}"
    vagrantfile_template = null
    keep_input_artifact  = false
  }
}
