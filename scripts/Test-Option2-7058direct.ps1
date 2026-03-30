#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Option 2 test: apply KB5078885 directly after 6216, no KB5075912 SSU pre-step.

.DESCRIPTION
    Uses the existing wim_6216.wim as the starting point and applies KB5078885
    MSU directly, skipping KB5075912 entirely.

    If KB5078885 applies cleanly (exit 0, no 14099), mount E:\ with the source
    ISO and run with -BuildISO to produce the final ISO.

.PARAMETER BuildISO
    After a clean apply, stage and build the ISO. Requires E:\ mounted.
#>

param(
    [switch]$BuildISO
)

# -- Paths (current V:\RWJBH-Lab structure) -----------------------------------
$WorkWim      = 'V:\RWJBH-Lab\ISOs\Win10\incremental_work.wim'
$Source6216   = 'V:\RWJBH-Lab\ISOs\Win10\wim_6216.wim'
$Clean7058d   = 'V:\RWJBH-Lab\ISOs\Win10\wim_7058direct.wim'
$MountDir     = 'V:\RWJBH-Lab\Mount'
$ScratchDir   = 'V:\RWJBH-Lab\Scratch'
$Msu          = 'V:\RWJBH-Lab\ISOs\Win10\Updates\windows10.0-kb5078885-x64.msu'
$SourceX64    = 'E:\x64'
$StageDir     = 'V:\RWJBH-Lab\ISOs\Win10\ISO_Stage'
$BootWim      = 'V:\RWJBH-Lab\ISOs\Win10\boot_work.wim'
$Autounattend = 'V:\RWJBH-Lab\GitHub\Win10Pro_Build\autounattend\autounattend.xml'
$OutputISO    = 'V:\RWJBH-Lab\ISOs\Win10Pro_22H2_19045.7058_direct.iso'
$Oscdimg      = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
$LogFile      = 'V:\RWJBH-Lab\GitHub\Win10Pro_Build\logs\option2-7058direct.log'

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null
New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

Write-Log '=== Option 2: KB5078885 directly after 6216 (no SSU pre-step) ==='

# -- Preflight ----------------------------------------------------------------
if (-not (Test-Path $Source6216)) {
    Write-Log "wim_6216.wim not found at $Source6216" 'ERROR'; exit 1
}
if (-not (Test-Path $Msu)) {
    Write-Log "KB5078885 MSU not found at $Msu" 'ERROR'; exit 1
}
if (Test-Path "$MountDir\Windows\System32\ntoskrnl.exe") {
    Write-Log "Image already mounted at $MountDir - unmount first." 'ERROR'; exit 1
}

# -- Copy 6216 WIM as working copy --------------------------------------------
Write-Log "Copying wim_6216.wim to working WIM..."
Copy-Item $Source6216 $WorkWim -Force
Write-Log "Copy complete - $([math]::Round((Get-Item $WorkWim).Length/1GB,2)) GB"

# -- Mount --------------------------------------------------------------------
Write-Log "Mounting working WIM..."
dism /Mount-Image /ImageFile:"$WorkWim" /Index:1 /MountDir:"$MountDir"
if ($LASTEXITCODE -ne 0) { Write-Log "Mount failed: $LASTEXITCODE" 'ERROR'; exit 1 }
Write-Log 'Mount complete.'

# -- Apply KB5078885 pass 1 ---------------------------------------------------
# KB5078885 bundles its own SSU (KB5081263/SSU-7052). On the first apply DISM
# installs the embedded SSU but leaves it pending, causing 14099 on the CU.
# Committing and remounting promotes the SSU to committed state. The second
# apply then installs the CU cleanly against the committed SSU.
Write-Log 'Pass 1: applying KB5078885 MSU (expected to install embedded SSU, may exit 14099)...'
dism /Image:"$MountDir" /Add-Package /PackagePath:"$Msu" /ScratchDir:"$ScratchDir"
$rc1 = $LASTEXITCODE

$SkipCodes = @(-2146498529, -2146498512)

if ($rc1 -eq 0) {
    Write-Log 'Pass 1: KB5078885 applied cleanly on first attempt - no retry needed.' 'INFO'
    $rc = 0
} elseif ($rc1 -eq 14099) {
    Write-Log 'Pass 1: exit 14099 - embedded SSU now pending. Committing and retrying...' 'INFO'

    # Commit pass 1 (promotes the pending SSU)
    dism /Unmount-Image /MountDir:"$MountDir" /Commit
    if ($LASTEXITCODE -ne 0) { Write-Log "Pass 1 commit failed: $LASTEXITCODE" 'ERROR'; exit 1 }
    Write-Log 'Pass 1 committed.'

    # Remount for pass 2
    Write-Log 'Remounting for pass 2...'
    dism /Mount-Image /ImageFile:"$WorkWim" /Index:1 /MountDir:"$MountDir"
    if ($LASTEXITCODE -ne 0) { Write-Log "Pass 2 mount failed: $LASTEXITCODE" 'ERROR'; exit 1 }
    Write-Log 'Remounted.'

    # Pass 2: apply KB5078885 again — SSU now committed, CU should succeed
    Write-Log 'Pass 2: applying KB5078885 MSU again against committed SSU...'
    dism /Image:"$MountDir" /Add-Package /PackagePath:"$Msu" /ScratchDir:"$ScratchDir"
    $rc = $LASTEXITCODE

    if ($rc -eq 0) {
        Write-Log 'Pass 2: KB5078885 applied CLEANLY - exit 0. Two-pass method SUCCESS.' 'INFO'
    } elseif ($SkipCodes -contains $rc) {
        Write-Log 'Pass 2: KB5078885 already applied (SSU was the only missing piece).' 'INFO'
        $rc = 0
    } elseif ($rc -eq 14099) {
        Write-Log 'Pass 2: still 14099 - two-pass method did not resolve the issue.' 'WARN'
    } else {
        Write-Log "Pass 2: failed with $rc" 'ERROR'
        dism /Unmount-Image /MountDir:"$MountDir" /Discard
        exit 1
    }
} elseif ($SkipCodes -contains $rc1) {
    Write-Log 'Pass 1: KB5078885 already applied or superseded.' 'INFO'
    $rc = 0
} else {
    Write-Log "Pass 1: failed with $rc1" 'ERROR'
    dism /Unmount-Image /MountDir:"$MountDir" /Discard
    exit 1
}

# -- Check UBR from offline registry -----------------------------------------
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

# -- Dismount and commit ------------------------------------------------------
Write-Log 'Unmounting and committing...'
dism /Unmount-Image /MountDir:"$MountDir" /Commit
if ($LASTEXITCODE -ne 0) { Write-Log "Unmount failed: $LASTEXITCODE" 'ERROR'; exit 1 }
Write-Log 'Unmount complete.'

# -- Export clean WIM ---------------------------------------------------------
Write-Log "Exporting clean WIM to $Clean7058d..."
if (Test-Path $Clean7058d) { Remove-Item $Clean7058d -Force }
dism /Export-Image /SourceImageFile:"$WorkWim" /SourceIndex:1 /DestinationImageFile:"$Clean7058d" /Compress:max
if ($LASTEXITCODE -ne 0) { Write-Log "Export failed: $LASTEXITCODE" 'ERROR'; exit 1 }
Write-Log "Export complete - $([math]::Round((Get-Item $Clean7058d).Length/1GB,2)) GB"

if ($rc -eq 14099) {
    Write-Log '14099 was returned - ISO build skipped. Option 2 did not resolve the root cause.' 'WARN'
    Write-Log 'Next step: Option 1 (online install + sysprep + capture) or investigate ESU bypass.'
    exit 0
}

# -- Build ISO (requires -BuildISO and E:\ mounted) ---------------------------
if (-not $BuildISO) {
    Write-Log 'Apply was clean. Run with -BuildISO (and E:\ mounted) to build the ISO.'
    exit 0
}

if (-not (Test-Path $SourceX64)) {
    Write-Log 'E:\x64 not found - mount the source ISO at E:\ first, then re-run with -BuildISO.' 'ERROR'
    exit 1
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
Copy-Item $Clean7058d (Join-Path $StageDir 'sources\install.wim') -Force
Copy-Item $Autounattend (Join-Path $StageDir 'autounattend.xml') -Force

$etfsboot = Join-Path $StageDir 'boot\etfsboot.com'
$efisys   = Join-Path $StageDir 'efi\microsoft\boot\efisys.bin'
$bootdata = '2#p0,e,b"{0}"#pEF,e,b"{1}"' -f $etfsboot, $efisys
& $Oscdimg -m -o -u2 -udfver102 "-bootdata:$bootdata" $StageDir $OutputISO
if ($LASTEXITCODE -ne 0) { Write-Log "oscdimg failed: $LASTEXITCODE" 'ERROR'; exit 1 }

$size = [math]::Round((Get-Item $OutputISO).Length / 1GB, 2)
Write-Log "ISO built: $OutputISO - $size GB"
Write-Log '=== Option 2 COMPLETE ==='
