#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Stages the updated WIM into an ISO layout and packages it as a bootable ISO.

.DESCRIPTION
    1. Copies the x64 setup layout from the source ISO (E:\x64\) to a staging directory.
    2. Removes the original install.esd and replaces it with the updated install_pro.wim.
    3. Copies autounattend.xml to the staging root.
    4. Runs oscdimg to produce a bootable UEFI+BIOS ISO.

.NOTES
    - Source ISO must be mounted at E:\
    - install_pro.wim must exist at V:\Lab\ISOs\Win10\install_pro.wim
    - Run from an elevated (Administrator) PowerShell prompt.
    - Output: V:\Lab\ISOs\Win10Pro_22H2_19045.7058.iso
#>

# -- Paths --------------------------------------------------------------------
$SourceX64    = 'E:\x64'
$WimFile      = 'V:\Lab\ISOs\Win10\install_pro.wim'
$BootWim      = 'V:\Lab\ISOs\Win10\boot_work.wim'
$StageDir     = 'V:\Lab\ISOs\Win10\ISO_Stage'
$Autounattend = 'V:\Lab\GitHub\Win10Pro_Build\autounattend\autounattend.xml'
$OutputISO    = 'V:\Lab\ISOs\Win10Pro_22H2_19045.7058.iso'
$Oscdimg      = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
$LogFile      = 'V:\Lab\GitHub\Win10Pro_Build\logs\build-iso.log'

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

# -- Preflight checks ---------------------------------------------------------
Write-Log 'Starting ISO build.'

if (-not (Test-Path $SourceX64)) {
    Write-Log 'Source ISO not found at E:\x64 - mount Windows10.iso first.' 'ERROR'
    exit 1
}
if (-not (Test-Path $WimFile)) {
    Write-Log 'WIM not found - run Steps 1 and update integration first.' 'ERROR'
    exit 1
}
if (-not (Test-Path $Oscdimg)) {
    Write-Log 'oscdimg not found - install Windows ADK Deployment Tools.' 'ERROR'
    exit 1
}

# -- Stage the x64 ISO layout -------------------------------------------------
Write-Log "Staging x64 setup layout from $SourceX64 to $StageDir ..."
Write-Log 'This copies the full source including install.esd - may take a few minutes.'

if (Test-Path $StageDir) {
    Write-Log 'Removing existing staging directory...'
    Remove-Item $StageDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

robocopy $SourceX64 $StageDir /E /NFL /NDL /NJH /NJS
Write-Log 'Staging copy complete.'

# -- Replace boot.wim with updated version (SSU-patched for compatibility) ----
if (Test-Path $BootWim) {
    Write-Log "Replacing boot.wim with updated version from $BootWim ..."
    Copy-Item $BootWim (Join-Path $StageDir 'sources\boot.wim') -Force
    Write-Log 'boot.wim replaced.'
} else {
    Write-Log 'No updated boot.wim found - using source boot.wim.' 'WARN'
}

# -- Replace install.esd with our updated WIM ---------------------------------
$stagedEsd = Join-Path $StageDir 'sources\install.esd'
if (Test-Path $stagedEsd) {
    $esdSize = [math]::Round((Get-Item $stagedEsd).Length / 1073741824, 2)
    Write-Log "Removing staged install.esd - $esdSize GB..."
    Remove-Item $stagedEsd -Force
}

$destWim = Join-Path $StageDir 'sources\install.wim'
$wimSize = [math]::Round((Get-Item $WimFile).Length / 1073741824, 2)
Write-Log "Copying updated WIM - $wimSize GB -> $destWim ..."
Copy-Item $WimFile $destWim -Force
Write-Log 'WIM copy complete.'

# -- Copy autounattend.xml to staging root ------------------------------------
Write-Log 'Copying autounattend.xml to staging root...'
Copy-Item $Autounattend (Join-Path $StageDir 'autounattend.xml') -Force
Write-Log 'autounattend.xml copied.'

# -- Build the ISO ------------------------------------------------------------
Write-Log "Running oscdimg to build $OutputISO ..."
Write-Log 'Boot: BIOS + UEFI'

$etfsboot = Join-Path $StageDir 'boot\etfsboot.com'
$efisys   = Join-Path $StageDir 'efi\microsoft\boot\efisys.bin'
$bootdata = '2#p0,e,b"{0}"#pEF,e,b"{1}"' -f $etfsboot, $efisys

& $Oscdimg -m -o -u2 -udfver102 "-bootdata:$bootdata" $StageDir $OutputISO

if ($LASTEXITCODE -ne 0) {
    Write-Log "oscdimg failed with exit code $LASTEXITCODE." 'ERROR'
    exit $LASTEXITCODE
}

$isoSize = [math]::Round((Get-Item $OutputISO).Length / 1073741824, 2)
Write-Log "ISO built successfully: $OutputISO - $isoSize GB"
Write-Log 'Next step: test ISO in a VM. See docs/build-process.md Step 11.'
