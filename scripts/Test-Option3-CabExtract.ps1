#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Option 3: apply KB5078885 via CAB extraction with exact SSU sequencing.

.DESCRIPTION
    Extracts SSU-19041.7052-x64.cab and the CU CAB from KB5078885 and applies
    them in two separate DISM sessions starting from wim_6216 (no pre-applied SSU).

    Why this differs from previous attempts:
    - MSU direct (Options 1/2): MSU Unattend.xml re-processes SSU on pass 2,
      CBS cannot read TOC.xml from the CAB, marks image CBS_E_IMAGE_UNSERVICEABLE.
    - CAB extraction with SSU-6935 pre-applied: CU CAB requires SSU-7052 but
      finds SSU-6935 instead, triggers 0x80073713 ERROR_ADVANCED_INSTALLER_FAILED.
    - This option: no pre-applied SSU, SSU-7052 applied in session 1, CU CAB
      in session 2 — dependency is satisfied exactly.

.PARAMETER BuildISO
    Build the ISO after a clean WIM export. Requires E:\ mounted.
#>

param(
    [switch]$BuildISO
)

# -- Paths --------------------------------------------------------------------
$WorkWim      = 'V:\RWJBH-Lab\ISOs\Win10\incremental_work.wim'
$Source6216   = 'V:\RWJBH-Lab\ISOs\Win10\wim_6216.wim'
$Clean7058o3  = 'V:\RWJBH-Lab\ISOs\Win10\wim_7058opt3.wim'
$MountDir     = 'V:\RWJBH-Lab\Mount'
$ScratchDir   = 'V:\RWJBH-Lab\Scratch'
$Msu          = 'V:\RWJBH-Lab\ISOs\Win10\Updates\windows10.0-kb5078885-x64.msu'
$ExtractDir   = 'V:\RWJBH-Lab\Scratch\MSU_Extracted\KB5078885_opt3'
$ExpandExe    = 'C:\Windows\System32\expand.exe'
$SourceX64    = 'E:\x64'
$StageDir     = 'V:\RWJBH-Lab\ISOs\Win10\ISO_Stage'
$BootWim      = 'V:\RWJBH-Lab\ISOs\Win10\boot_work.wim'
$Autounattend = 'V:\RWJBH-Lab\GitHub\Win10Pro_Build\autounattend\autounattend.xml'
$OutputISO    = 'V:\RWJBH-Lab\ISOs\Win10Pro_22H2_19045.7058_opt3.iso'
$Oscdimg      = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
$LogFile      = 'V:\RWJBH-Lab\GitHub\Win10Pro_Build\logs\option3-cabextract.log'

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null
New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

function Mount-Wim {
    Write-Log "Mounting $WorkWim..."
    dism /Mount-Image /ImageFile:"$WorkWim" /Index:1 /MountDir:"$MountDir"
    if ($LASTEXITCODE -ne 0) { Write-Log "Mount failed: $LASTEXITCODE" 'ERROR'; exit 1 }
    Write-Log 'Mount complete.'
}

function Dismount-Commit {
    Write-Log 'Committing and unmounting...'
    dism /Unmount-Image /MountDir:"$MountDir" /Commit
    if ($LASTEXITCODE -ne 0) { Write-Log "Unmount failed: $LASTEXITCODE" 'ERROR'; exit 1 }
    Write-Log 'Unmount complete.'
}

Write-Log '=== Option 3: KB5078885 CAB extraction, exact SSU-7052 sequencing ==='

# -- Preflight ----------------------------------------------------------------
if (-not (Test-Path $Source6216))  { Write-Log "wim_6216.wim not found."    'ERROR'; exit 1 }
if (-not (Test-Path $Msu))         { Write-Log "KB5078885 MSU not found."   'ERROR'; exit 1 }
if (-not (Test-Path $ExpandExe))   { Write-Log "expand.exe not found."      'ERROR'; exit 1 }
if (Test-Path "$MountDir\Windows\System32\ntoskrnl.exe") {
    Write-Log "Image already mounted at $MountDir - unmount first." 'ERROR'; exit 1
}

# -- Extract MSU --------------------------------------------------------------
Write-Log "Extracting KB5078885 MSU to $ExtractDir..."
if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
& $ExpandExe -f:* $Msu $ExtractDir | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Log "MSU extraction failed." 'ERROR'; exit 1 }

$allCabs = Get-ChildItem $ExtractDir -Filter '*.cab'
Write-Log "Extracted CABs:"
$allCabs | ForEach-Object { Write-Log "  $($_.Name) - $([math]::Round($_.Length/1MB,1)) MB" }

$ssuCab = $allCabs | Where-Object { $_.Name -match 'SSU' } | Select-Object -First 1
$cuCab  = $allCabs | Where-Object { $_.Name -notmatch 'SSU' } | Sort-Object Length -Descending | Select-Object -First 1

if (-not $ssuCab) { Write-Log "No SSU CAB found in MSU extract." 'ERROR'; exit 1 }
if (-not $cuCab)  { Write-Log "No CU CAB found in MSU extract."  'ERROR'; exit 1 }

Write-Log "SSU CAB: $($ssuCab.Name) ($([math]::Round($ssuCab.Length/1MB,1)) MB)"
Write-Log "CU CAB:  $($cuCab.Name) ($([math]::Round($cuCab.Length/1MB,1)) MB)"

# -- Copy 6216 as base (no pre-applied SSU) -----------------------------------
Write-Log "Copying wim_6216.wim as working base (no SSU pre-applied)..."
Copy-Item $Source6216 $WorkWim -Force
Write-Log "Copy complete - $([math]::Round((Get-Item $WorkWim).Length/1GB,2)) GB"

# -- Session 1: apply SSU-7052 CAB -------------------------------------------
Write-Log '--- Session 1: SSU-19041.7052 ---'
Mount-Wim
Write-Log "Applying $($ssuCab.Name)..."
dism /Image:"$MountDir" /Add-Package /PackagePath:"$($ssuCab.FullName)" /ScratchDir:"$ScratchDir"
$rcSSU = $LASTEXITCODE
if ($rcSSU -eq 0) {
    Write-Log 'SSU-7052 applied cleanly.'
} elseif (@(-2146498529, -2146498512) -contains $rcSSU) {
    Write-Log 'SSU-7052 already present - continuing.' 'INFO'
} else {
    Write-Log "SSU-7052 failed: $rcSSU" 'ERROR'
    dism /Unmount-Image /MountDir:"$MountDir" /Discard
    exit 1
}
Dismount-Commit

# -- Session 2: apply CU CAB -------------------------------------------------
Write-Log '--- Session 2: CU CAB ---'
Mount-Wim
Write-Log "Applying $($cuCab.Name)..."
dism /Image:"$MountDir" /Add-Package /PackagePath:"$($cuCab.FullName)" /ScratchDir:"$ScratchDir"
$rcCU = $LASTEXITCODE
if ($rcCU -eq 0) {
    Write-Log 'CU CAB applied cleanly - exit 0. Option 3 SUCCESS.' 'INFO'
} elseif (@(-2146498529, -2146498512) -contains $rcCU) {
    Write-Log 'CU CAB already applied.' 'INFO'
    $rcCU = 0
} elseif ($rcCU -eq 0x80073713 -or $rcCU -eq -2147009517) {
    Write-Log "CU CAB: 0x80073713 ERROR_ADVANCED_INSTALLER_FAILED - SSU version mismatch." 'ERROR'
    dism /Unmount-Image /MountDir:"$MountDir" /Discard; exit 1
} elseif ($rcCU -eq 14099) {
    Write-Log "CU CAB: 14099 - still pending after SSU commit. Unexpected." 'WARN'
} else {
    Write-Log "CU CAB failed: $rcCU" 'ERROR'
    dism /Unmount-Image /MountDir:"$MountDir" /Discard; exit 1
}

# -- Verify UBR ---------------------------------------------------------------
Write-Log 'Checking UBR from offline registry...'
try {
    reg load 'HKLM\OFFLINE' "$MountDir\Windows\System32\config\SOFTWARE" | Out-Null
    $ubr   = (Get-ItemProperty 'HKLM:\OFFLINE\Microsoft\Windows NT\CurrentVersion').UBR
    $build = (Get-ItemProperty 'HKLM:\OFFLINE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
    reg unload 'HKLM\OFFLINE' | Out-Null
    Write-Log "UBR: $build.$ubr"
    if ($ubr -eq 7058) { Write-Log 'UBR confirmed 7058.' }
    else { Write-Log "UBR is $ubr - expected 7058." 'WARN' }
} catch {
    reg unload 'HKLM\OFFLINE' 2>$null
    Write-Log "Could not read UBR: $_" 'WARN'
}

Dismount-Commit

# -- Export clean WIM ---------------------------------------------------------
Write-Log "Exporting clean WIM to $Clean7058o3..."
if (Test-Path $Clean7058o3) { Remove-Item $Clean7058o3 -Force }
dism /Export-Image /SourceImageFile:"$WorkWim" /SourceIndex:1 /DestinationImageFile:"$Clean7058o3" /Compress:max
if ($LASTEXITCODE -ne 0) { Write-Log "Export failed: $LASTEXITCODE" 'ERROR'; exit 1 }
Write-Log "Export complete - $([math]::Round((Get-Item $Clean7058o3).Length/1GB,2)) GB"

if ($rcCU -ne 0) {
    Write-Log "CU returned $rcCU - review log before building ISO." 'WARN'
    exit 0
}

# -- Build ISO ----------------------------------------------------------------
if (-not $BuildISO) {
    Write-Log 'CU applied cleanly. Run with -BuildISO (E:\ mounted) to build the ISO.'
    exit 0
}

if (-not (Test-Path $SourceX64)) {
    Write-Log 'E:\x64 not found - mount the source ISO first.' 'ERROR'; exit 1
}

Write-Log "Building ISO: $OutputISO"
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
robocopy $SourceX64 $StageDir /E /NFL /NDL /NJH /NJS | Out-Null

if (Test-Path $BootWim) {
    Copy-Item $BootWim (Join-Path $StageDir 'sources\boot.wim') -Force
    Write-Log 'boot.wim (SSU-6935) staged.'
}

$stagedEsd = Join-Path $StageDir 'sources\install.esd'
if (Test-Path $stagedEsd) { Remove-Item $stagedEsd -Force }
Copy-Item $Clean7058o3 (Join-Path $StageDir 'sources\install.wim') -Force
Copy-Item $Autounattend (Join-Path $StageDir 'autounattend.xml') -Force

$etfsboot = Join-Path $StageDir 'boot\etfsboot.com'
$efisys   = Join-Path $StageDir 'efi\microsoft\boot\efisys.bin'
$bootdata = '2#p0,e,b"{0}"#pEF,e,b"{1}"' -f $etfsboot, $efisys
& $Oscdimg -m -o -u2 -udfver102 "-bootdata:$bootdata" $StageDir $OutputISO
if ($LASTEXITCODE -ne 0) { Write-Log "oscdimg failed: $LASTEXITCODE" 'ERROR'; exit 1 }

$size = [math]::Round((Get-Item $OutputISO).Length / 1GB, 2)
Write-Log "ISO built: $OutputISO - $size GB"
Write-Log '=== Option 3 COMPLETE ==='
