# =============================================================================
# build.ps1 -- Full build pipeline (Windows / VirtualBox)
#
# Usage:
#   .\build.ps1               # full build (packer + vagrant up)
#   .\build.ps1 -PackerOnly   # only build the box, don't start VM
#   .\build.ps1 -VagrantOnly  # skip packer, use existing box
#
# Requirements:
#   Packer       https://developer.hashicorp.com/packer/downloads
#   VirtualBox   https://www.virtualbox.org/
#   Vagrant      https://developer.hashicorp.com/vagrant/downloads
#   Git for Windows (provides rsync)  https://git-scm.com/download/win
# =============================================================================

param(
    [switch]$PackerOnly,
    [switch]$VagrantOnly
)

$ErrorActionPreference = "Stop"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

$BoxName    = "alma9-cis-local"
$BoxFile    = "alma9-cis.box"
$IsoVersion = "9.4"
$IsoName    = "AlmaLinux-$IsoVersion-x86_64-minimal.iso"
$IsoUrl     = "https://vault.almalinux.org/$IsoVersion/isos/x86_64/$IsoName"
$IsoPath    = "packer\$IsoName"

function Write-Info { param($m) Write-Host "[INFO]  $m" -ForegroundColor Cyan }
function Write-OK   { param($m) Write-Host "[OK]    $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "[WARN]  $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red; exit 1 }

# -- Prerequisites ------------------------------------------------------------
Write-Info "Checking prerequisites..."
foreach ($cmd in @("packer", "vagrant", "VBoxManage")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Err "Required command not found: $cmd -- ensure it is installed and in PATH."
    }
}
Write-OK "Prerequisites satisfied."

# =============================================================================
# PHASE 1: Packer build
# =============================================================================
if (-not $VagrantOnly) {

    # -- Download ISO ---------------------------------------------------------
    $isoExists = (Test-Path $IsoPath) -and ((Get-Item $IsoPath).Length -gt 1MB)
    if (-not $isoExists) {
        Write-Info "Downloading AlmaLinux $IsoVersion minimal ISO (~2.1 GB)..."
        New-Item -ItemType Directory -Force -Path "packer" | Out-Null
        Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoPath -UseBasicParsing
        Write-OK "ISO downloaded: $IsoPath"
    } else {
        Write-OK "ISO already present: $IsoPath"
    }

    # -- Compute checksum -----------------------------------------------------
    Write-Info "Computing SHA-256 checksum..."
    $hash        = (Get-FileHash -Algorithm SHA256 $IsoPath).Hash.ToLower()
    $IsoChecksum = "sha256:$hash"
    Write-OK "Checksum: $IsoChecksum"

    # -- Packer init (download plugins) ---------------------------------------
    Write-Info "Running packer init..."
    Push-Location packer
    packer init .
    if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Err "packer init failed." }
    Pop-Location

    # -- Build the box --------------------------------------------------------
    if (Test-Path $BoxFile) {
        Write-Warn "Box file $BoxFile already exists. Skipping packer build."
        Write-Warn "Delete $BoxFile and re-run to rebuild."
    } else {
        Write-Info "Starting Packer build (this takes ~30-45 min)..."
        Write-Info "To watch progress: set env:PACKER_LOG=1 before running."
        Write-Info "For a GUI window: edit packer\alma9-cis.pkr.hcl and set headless = false"
        Write-Host ""
        $AbsIsoPath = (Resolve-Path $IsoPath).Path.Replace('\', '/')
        Push-Location packer
        packer build `
            -var "iso_url=file:///$AbsIsoPath" `
            -var "iso_checksum=$IsoChecksum" `
            alma9-cis.pkr.hcl
        if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Err "packer build failed." }
        Pop-Location
        Write-OK "Packer build complete. Box: $BoxFile"
    }

    if ($PackerOnly) { Write-OK "Packer-only mode. Done."; exit 0 }
}

# =============================================================================
# PHASE 2: Register box with Vagrant
# =============================================================================
$boxList = (vagrant box list 2>&1) | Out-String
if ($boxList -match [regex]::Escape($BoxName)) {
    Write-OK "Vagrant box '$BoxName' already registered."
} else {
    if (-not (Test-Path $BoxFile)) {
        Write-Err "Box file $BoxFile not found. Run without -VagrantOnly first."
    }
    Write-Info "Adding box to Vagrant: $BoxName"
    vagrant box add --force --name $BoxName $BoxFile
    Write-OK "Box registered."
}

# =============================================================================
# PHASE 3: Vagrant up
# =============================================================================
Write-Info "Starting Vagrant VM and running provisioners..."
Write-Info "Expected duration: ~15-25 min (package install + AIDE init + scan)"
Write-Host ""
vagrant up --provider=virtualbox

Write-Host ""
Write-OK "================================================================"
Write-OK "  Build complete!"
Write-OK "  VM status   : vagrant status"
Write-OK "  SSH into VM : vagrant ssh"
Write-OK "  Re-scan VM  : bash scan.sh"
Write-OK "  Destroy VM  : vagrant destroy"
Write-OK "================================================================"
