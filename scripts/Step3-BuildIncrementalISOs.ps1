#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Builds incremental ISOs from the base ESD, one per KB update level.

.PARAMETER TargetBuild
    Build level to stop at. Use tab-completion to see valid values.

        3803        Base image only (no updates applied)
        4598        Through KB5039299 (2024-06)
        5440        Through KB5050081 (2025-01)
        6216        Through KB5063709 (2025-08)
        6935        KB5075912 SSU only; CU intentionally skipped (causes CBS 14099 offline)
        7058        SSU-6935 path: KB5075912 SSU -> KB5078885 MSU (prior approach; 14099 during apply)
        7058direct  Option 2: KB5078885 applied directly after 6216; skips KB5075912 entirely

    Default: 7058direct

.DESCRIPTION
    Starts from E:\x64\sources\install.esd (19045.3803 Pro, index 6) and applies
    each update in the chain, exporting a clean WIM and building a bootable ISO
    after each build level. Useful for verifying which update level causes setup
    failures.

    Update chain:
        19045.3803  base ESD
        19045.4598  KB5039299  2024-06
        19045.5440  KB5050081  2025-01
        19045.6216  KB5063709  2025-08
        19045.6935  KB5075912  SSU-only (CU skipped)
        19045.7058  KB5078885  (two paths - see TargetBuild)

    Build paths for 7058:
        '7058'       SSU-6935 pre-applied, then KB5078885 MSU (previous approach).
                     Known issue: 14099 during apply leaves CBS inconsistent.
        '7058direct' KB5078885 applied directly after 6216 with no KB5075912 step.
                     Testing whether skipping the SSU pre-step avoids 14099.

.NOTES
    - Source ISO must be mounted at E:\
    - Run from an elevated (Administrator) PowerShell prompt.
    - Each ISO takes 10-30 minutes depending on update size.
#>

param(
    [Parameter(HelpMessage = 'Build level to target. Tab-complete for options.')]
    [ValidateSet('3803', '4598', '5440', '6216', '6935', '7058', '7058direct')]
    [string]$TargetBuild = '7058direct'
)

# -- Paths --------------------------------------------------------------------
$EsdFile      = 'E:\x64\sources\install.esd'
$WorkWim      = 'V:\RWJBH-Lab\ISOs\Win10\incremental_work.wim'
$MountDir     = 'V:\RWJBH-Lab\Mount'
$ScratchDir   = 'V:\RWJBH-Lab\Scratch'
$UpdatesDir   = 'V:\RWJBH-Lab\ISOs\Win10\Updates'
$ExtractDir   = 'V:\RWJBH-Lab\Scratch\MSU_Extracted'
$ISOOutDir    = 'V:\RWJBH-Lab\ISOs'
$StageDir     = 'V:\RWJBH-Lab\ISOs\Win10\ISO_Stage'
$SourceX64    = 'E:\x64'
$BootWim      = 'V:\RWJBH-Lab\ISOs\Win10\boot_work.wim'
$Autounattend = 'V:\RWJBH-Lab\GitHub\Win10Pro_Build\autounattend\autounattend.xml'
$Oscdimg      = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
$ExpandExe    = 'C:\Windows\System32\expand.exe'
$LogFile      = 'V:\RWJBH-Lab\GitHub\Win10Pro_Build\logs\incremental-build.log'

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null
New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null
New-Item -ItemType Directory -Force -Path $MountDir   | Out-Null

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
    Write-Log 'Unmounting and committing...'
    dism /Unmount-Image /MountDir:"$MountDir" /Commit
    if ($LASTEXITCODE -ne 0) { Write-Log "Unmount failed: $LASTEXITCODE" 'ERROR'; exit 1 }
    Write-Log 'Unmount complete.'
}

$SkipCodes = @(-2146498529, -2146498512)

function Apply-Package {
    param([string]$PackagePath, [string]$Label)
    Write-Log "Applying $Label..."
    dism /Image:"$MountDir" /Add-Package /PackagePath:"$PackagePath" /ScratchDir:"$ScratchDir"
    if ($SkipCodes -contains $LASTEXITCODE) {
        Write-Log "$Label already applied - skipping." 'INFO'
    } elseif ($LASTEXITCODE -ne 0) {
        Write-Log "$Label failed: $LASTEXITCODE" 'ERROR'; exit 1
    } else {
        Write-Log "$Label applied successfully."
    }
}

function Export-CleanWim {
    param([string]$DestPath)
    Write-Log "Exporting clean WIM to $DestPath..."
    if (Test-Path $DestPath) { Remove-Item $DestPath -Force }
    dism /Export-Image /SourceImageFile:"$WorkWim" /SourceIndex:1 /DestinationImageFile:"$DestPath" /Compress:max
    if ($LASTEXITCODE -ne 0) { Write-Log "Export failed: $LASTEXITCODE" 'ERROR'; exit 1 }
    Write-Log 'Export complete.'
}

function Build-ISO {
    param([string]$WimPath, [string]$ISOPath)
    Write-Log "Building ISO: $ISOPath"

    if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
    robocopy $SourceX64 $StageDir /E /NFL /NDL /NJH /NJS | Out-Null

    if (Test-Path $BootWim) {
        Copy-Item $BootWim (Join-Path $StageDir 'sources\boot.wim') -Force
    }

    $stagedEsd = Join-Path $StageDir 'sources\install.esd'
    if (Test-Path $stagedEsd) { Remove-Item $stagedEsd -Force }
    Copy-Item $WimPath (Join-Path $StageDir 'sources\install.wim') -Force

    Copy-Item $Autounattend (Join-Path $StageDir 'autounattend.xml') -Force

    $etfsboot = Join-Path $StageDir 'boot\etfsboot.com'
    $efisys   = Join-Path $StageDir 'efi\microsoft\boot\efisys.bin'
    $bootdata = '2#p0,e,b"{0}"#pEF,e,b"{1}"' -f $etfsboot, $efisys
    & $Oscdimg -m -o -u2 -udfver102 "-bootdata:$bootdata" $StageDir $ISOPath
    if ($LASTEXITCODE -ne 0) { Write-Log "oscdimg failed: $LASTEXITCODE" 'ERROR'; exit 1 }
    $size = [math]::Round((Get-Item $ISOPath).Length / 1GB, 2)
    Write-Log "ISO built: $ISOPath - $size GB"
}

Write-Log "=== Incremental build started. TargetBuild: $TargetBuild ==="

# =============================================================================
# STEP 0: Export base WIM from ESD (19045.3803, Pro = index 6)
# =============================================================================
Write-Log '=== STEP 0: Exporting base WIM from ESD (19045.3803) ==='
if (Test-Path $WorkWim) { Remove-Item $WorkWim -Force }
dism /Export-Image /SourceImageFile:"$EsdFile" /SourceIndex:6 /DestinationImageFile:"$WorkWim" /Compress:max /CheckIntegrity
if ($LASTEXITCODE -ne 0) { Write-Log "Base export failed: $LASTEXITCODE" 'ERROR'; exit 1 }
Write-Log 'Base WIM exported.'

$BaseISO = Join-Path $ISOOutDir 'Win10Pro_22H2_19045.3803.iso'
Build-ISO -WimPath $WorkWim -ISOPath $BaseISO
Write-Log '=== STEP 0 COMPLETE: 19045.3803 ISO built ==='
if ($TargetBuild -eq '3803') { Write-Log 'Target reached. Done.'; exit 0 }

# =============================================================================
# STEP 1: KB5039299 -> 19045.4598
# =============================================================================
Write-Log '=== STEP 1: KB5039299 (3803 -> 4598) ==='
$msu = Join-Path $UpdatesDir 'windows10.0-kb5039299-x64.msu'
$ext = Join-Path $ExtractDir 'KB5039299'
if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
New-Item -ItemType Directory -Force -Path $ext | Out-Null
& $ExpandExe -f:* $msu $ext | Out-Null
$ssu = Get-ChildItem $ext -Filter '*.cab' | Where-Object { $_.Name -match 'SSU|ServicingStack' } | Select-Object -First 1
$cu  = Get-ChildItem $ext -Filter '*.cab' | Where-Object { $_.Name -notmatch 'SSU|ServicingStack' } | Sort-Object Length -Descending | Select-Object -First 1

Mount-Wim
if ($ssu) { Apply-Package -PackagePath $ssu.FullName -Label "KB5039299 SSU"; Dismount-Commit; Mount-Wim }
Apply-Package -PackagePath $cu.FullName -Label "KB5039299 CU"
Dismount-Commit

$clean4598 = 'V:\RWJBH-Lab\ISOs\Win10\wim_4598.wim'
Export-CleanWim -DestPath $clean4598
Build-ISO -WimPath $clean4598 -ISOPath (Join-Path $ISOOutDir 'Win10Pro_22H2_19045.4598.iso')
Write-Log '=== STEP 1 COMPLETE: 19045.4598 ISO built ==='
if ($TargetBuild -eq '4598') { Write-Log 'Target reached. Done.'; exit 0 }

# =============================================================================
# STEP 2: KB5050081 -> 19045.5440
# =============================================================================
Write-Log '=== STEP 2: KB5050081 (4598 -> 5440) ==='
Copy-Item $clean4598 $WorkWim -Force
$msu = Join-Path $UpdatesDir 'windows10.0-kb5050081-x64.msu'
$ext = Join-Path $ExtractDir 'KB5050081'
if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
New-Item -ItemType Directory -Force -Path $ext | Out-Null
& $ExpandExe -f:* $msu $ext | Out-Null
$ssu = Get-ChildItem $ext -Filter '*.cab' | Where-Object { $_.Name -match 'SSU|ServicingStack' } | Select-Object -First 1
$cu  = Get-ChildItem $ext -Filter '*.cab' | Where-Object { $_.Name -notmatch 'SSU|ServicingStack' } | Sort-Object Length -Descending | Select-Object -First 1

Mount-Wim
if ($ssu) { Apply-Package -PackagePath $ssu.FullName -Label "KB5050081 SSU"; Dismount-Commit; Mount-Wim }
Apply-Package -PackagePath $cu.FullName -Label "KB5050081 CU"
Dismount-Commit

$clean5440 = 'V:\RWJBH-Lab\ISOs\Win10\wim_5440.wim'
Export-CleanWim -DestPath $clean5440
Build-ISO -WimPath $clean5440 -ISOPath (Join-Path $ISOOutDir 'Win10Pro_22H2_19045.5440.iso')
Write-Log '=== STEP 2 COMPLETE: 19045.5440 ISO built ==='
if ($TargetBuild -eq '5440') { Write-Log 'Target reached. Done.'; exit 0 }

# =============================================================================
# STEP 3: KB5063709 -> 19045.6216
# =============================================================================
Write-Log '=== STEP 3: KB5063709 (5440 -> 6216) ==='
Copy-Item $clean5440 $WorkWim -Force
$msu = Join-Path $UpdatesDir 'windows10.0-kb5063709-x64.msu'
$ext = Join-Path $ExtractDir 'KB5063709'
if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
New-Item -ItemType Directory -Force -Path $ext | Out-Null
& $ExpandExe -f:* $msu $ext | Out-Null
$ssu = Get-ChildItem $ext -Filter '*.cab' | Where-Object { $_.Name -match 'SSU|ServicingStack' } | Select-Object -First 1
$cu  = Get-ChildItem $ext -Filter '*.cab' | Where-Object { $_.Name -notmatch 'SSU|ServicingStack' } | Sort-Object Length -Descending | Select-Object -First 1

Mount-Wim
if ($ssu) { Apply-Package -PackagePath $ssu.FullName -Label "KB5063709 SSU"; Dismount-Commit; Mount-Wim }
Apply-Package -PackagePath $cu.FullName -Label "KB5063709 CU"
Dismount-Commit

$clean6216 = 'V:\RWJBH-Lab\ISOs\Win10\wim_6216.wim'
Export-CleanWim -DestPath $clean6216
Build-ISO -WimPath $clean6216 -ISOPath (Join-Path $ISOOutDir 'Win10Pro_22H2_19045.6216.iso')
Write-Log '=== STEP 3 COMPLETE: 19045.6216 ISO built ==='
if ($TargetBuild -eq '6216') { Write-Log 'Target reached. Done.'; exit 0 }

# =============================================================================
# STEP 4 (Option 2 / 7058direct): KB5078885 applied directly after 6216
#   Skips KB5075912 entirely — tests whether the SSU pre-step causes the 14099
#   CBS_E_ARRAY_ELEMENT_MISSING error that corrupts the component store.
# =============================================================================
if ($TargetBuild -eq '7058direct') {
    Write-Log '=== STEP 4 (7058direct): KB5078885 directly after 6216 (no KB5075912 step) ==='
    Copy-Item $clean6216 $WorkWim -Force
    $msu = Join-Path $UpdatesDir 'windows10.0-kb5078885-x64.msu'

    Mount-Wim
    Write-Log 'Applying KB5078885 MSU directly (no prior SSU-6935)...'
    dism /Image:"$MountDir" /Add-Package /PackagePath:"$msu" /ScratchDir:"$ScratchDir"
    $rc = $LASTEXITCODE
    if ($SkipCodes -contains $rc) {
        Write-Log 'KB5078885 already applied - skipping.' 'INFO'
    } elseif ($rc -eq 14099) {
        Write-Log "KB5078885 exit 14099 (CBS_E_ARRAY_ELEMENT_MISSING) - same as prior approach. SSU conflict persists." 'WARN'
    } elseif ($rc -ne 0) {
        Write-Log "KB5078885 failed: $rc" 'ERROR'; exit 1
    } else {
        Write-Log 'KB5078885 applied cleanly - no 14099.'
    }
    Dismount-Commit

    $clean7058d = 'V:\RWJBH-Lab\ISOs\Win10\wim_7058direct.wim'
    Export-CleanWim -DestPath $clean7058d
    Build-ISO -WimPath $clean7058d -ISOPath (Join-Path $ISOOutDir 'Win10Pro_22H2_19045.7058_direct.iso')
    Write-Log '=== STEP 4 COMPLETE (7058direct): 19045.7058_direct ISO built ==='
    Write-Log 'Target reached. Done.'
    exit 0
}

# =============================================================================
# STEP 4: KB5075912 SSU only -> 19045.6935  (original path)
# =============================================================================
Write-Log '=== STEP 4: KB5075912 SSU-only (6216 -> 6935) ==='
Copy-Item $clean6216 $WorkWim -Force
$msu = Join-Path $UpdatesDir 'windows10.0-kb5075912-x64.msu'
$ext = Join-Path $ExtractDir 'KB5075912'
if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
New-Item -ItemType Directory -Force -Path $ext | Out-Null
& $ExpandExe -f:* $msu $ext | Out-Null
$ssu = Get-ChildItem $ext -Filter '*.cab' | Where-Object { $_.Name -match 'SSU|ServicingStack' } | Select-Object -First 1

Mount-Wim
Apply-Package -PackagePath $ssu.FullName -Label "KB5075912 SSU"
Dismount-Commit

$clean6935 = 'V:\RWJBH-Lab\ISOs\Win10\wim_6935.wim'
Export-CleanWim -DestPath $clean6935
Build-ISO -WimPath $clean6935 -ISOPath (Join-Path $ISOOutDir 'Win10Pro_22H2_19045.6935.iso')
Write-Log '=== STEP 4 COMPLETE: 19045.6935 ISO built ==='
if ($TargetBuild -eq '6935') { Write-Log 'Target reached. Done.'; exit 0 }

# =============================================================================
# STEP 5: KB5078885 MSU -> 19045.7058  (original path - SSU-6935 pre-applied)
# =============================================================================
Write-Log '=== STEP 5: KB5078885 MSU (6935 -> 7058) ==='
Copy-Item $clean6935 $WorkWim -Force
$msu = Join-Path $UpdatesDir 'windows10.0-kb5078885-x64.msu'

Mount-Wim
Write-Log 'Applying KB5078885 MSU directly...'
dism /Image:"$MountDir" /Add-Package /PackagePath:"$msu" /ScratchDir:"$ScratchDir"
$rc = $LASTEXITCODE
if ($SkipCodes -contains $rc) {
    Write-Log 'KB5078885 already applied - skipping.' 'INFO'
} elseif ($rc -eq 14099) {
    Write-Log "KB5078885 exit 14099 (CBS_E_ARRAY_ELEMENT_MISSING) - CBS state inconsistent, continuing to export." 'WARN'
} elseif ($rc -ne 0) {
    Write-Log "KB5078885 failed: $rc" 'ERROR'; exit 1
} else {
    Write-Log 'KB5078885 applied successfully.'
}
Dismount-Commit

$clean7058 = 'V:\RWJBH-Lab\ISOs\Win10\wim_7058.wim'
Export-CleanWim -DestPath $clean7058
Build-ISO -WimPath $clean7058 -ISOPath (Join-Path $ISOOutDir 'Win10Pro_22H2_19045.7058_fresh.iso')
Write-Log '=== STEP 5 COMPLETE: 19045.7058_fresh ISO built ==='

Write-Log '=== ALL STEPS COMPLETE ==='
Write-Log "ISOs saved to $ISOOutDir"
