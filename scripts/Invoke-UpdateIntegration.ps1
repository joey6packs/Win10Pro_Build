#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Integrates cumulative updates into a Windows image using DISM.

.DESCRIPTION
    Applies each update with full session isolation: SSU CAB and CU CAB are
    applied in separate DISM sessions (unmount/commit/remount between each)
    to prevent component store corruption errors (14099, 0x800f0830).

    Update chain (base 19045.3803 -> target 19045.7058):
      KB5039299  2024-06  3803 -> 4598   (bridge 1)
      KB5050081  2025-01  4598 -> 5440   (bridge 2)
      KB5063709  2025-08  5440 -> 6216   (bridge 3)
      KB5075912  2026-02  SSU-6935 only  (CU omitted - causes CBS damage via 14099)
      KB5078885  2026-03  6216 -> 7058   (target, cumulative over KB5075912)

.NOTES
    - Run Step1-ExportAndMount.ps1 first to export and mount the WIM.
    - Run from an elevated (Administrator) PowerShell prompt.
    - DISM offline does not enforce ESU enrollment - post-EOL CUs apply normally.
    - Image is left mounted at the end - run Invoke-CleanupAndUnmount.ps1 next.
#>

# -- Paths --------------------------------------------------------------------
$WimFile    = 'V:\RWJBH-Lab\ISOs\Win10\install_pro.wim'
$WimIndex   = 1
$MountDir   = 'V:\RWJBH-Lab\Mount'
$ScratchDir = 'V:\RWJBH-Lab\Scratch'
$UpdatesDir = 'V:\RWJBH-Lab\ISOs\Win10\Updates'
$ExtractDir = 'V:\RWJBH-Lab\Scratch\MSU_Extracted'
$LogFile    = 'V:\RWJBH-Lab\GitHub\Win10Pro_Build\logs\update-integration.log'
$ExpandExe  = 'C:\Windows\System32\expand.exe'

# -- Updates to integrate (in order) -----------------------------------------
$Updates = @(
    @{ KB = 'KB5039299'; File = 'windows10.0-kb5039299-x64.msu'; Desc = '2024-06 bridge 1 -> 19045.4598' },
    @{ KB = 'KB5050081'; File = 'windows10.0-kb5050081-x64.msu'; Desc = '2025-01 bridge 2 -> 19045.5440' },
    @{ KB = 'KB5063709'; File = 'windows10.0-kb5063709-x64.msu'; Desc = '2025-08 bridge 3 -> 19045.6216' },
    # KB5075912 CU intentionally omitted: applying it offline causes a 14099 SXS transaction error
    # that permanently damages the CBS component store (0x800f0830 on all subsequent packages).
    # Its SSU (SSU-19041.6935) is applied here; the CU content is superseded by KB5078885.
    @{ KB = 'KB5075912'; File = 'windows10.0-kb5075912-x64.msu'; Desc = '2026-02 SSU-6935 only (CU skipped)'; SkipCU = $true },
    # KB5078885: apply MSU directly - CAB extraction causes CBS to re-process the embedded SSU (KB5081263/7052)
    # which conflicts with the separately applied SSU CAB, triggering 0x80073713 ERROR_ADVANCED_INSTALLER_FAILED.
    @{ KB = 'KB5078885'; File = 'windows10.0-kb5078885-x64.msu'; Desc = '2026-03 target  -> 19045.7058'; UseMSU = $true }
)

# Exit codes meaning "already applied or superseded" - skip, do not fail
# 0x800f081f = source files not found (superseded)
# 0x800f0830 = image not serviceable (package not applicable at this build)
$SkipCodes = @(-2146498529, -2146498512)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null
New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$ts] [$Level] $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

function Dismount-Commit {
    Write-Log 'Unmounting and committing image...'
    dism /Unmount-Image /MountDir:"$MountDir" /Commit
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Unmount/Commit failed with exit code $LASTEXITCODE." 'ERROR'
        exit $LASTEXITCODE
    }
    Write-Log 'Unmount complete.'
}

function Mount-Wim {
    Write-Log "Mounting $WimFile index $WimIndex..."
    dism /Mount-Image /ImageFile:"$WimFile" /Index:$WimIndex /MountDir:"$MountDir"
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Mount failed with exit code $LASTEXITCODE." 'ERROR'
        exit $LASTEXITCODE
    }
    Write-Log 'Mount complete.'
}

function Invoke-DismPackage {
    param([string]$PackagePath, [string]$Label)
    Write-Log "Applying $Label ..."
    dism /Image:"$MountDir" /Add-Package /PackagePath:"$PackagePath" /ScratchDir:"$ScratchDir"
    if ($SkipCodes -contains $LASTEXITCODE) {
        Write-Log "$Label already applied or superseded - skipping." 'INFO'
    } elseif ($LASTEXITCODE -ne 0) {
        Write-Log "$Label failed with exit code $LASTEXITCODE." 'ERROR'
        exit $LASTEXITCODE
    } else {
        Write-Log "$Label applied successfully."
    }
}

# -- Verify initial mount -----------------------------------------------------
Write-Log 'Verifying mounted image...'
if (-not (Test-Path "$MountDir\Windows\System32\ntoskrnl.exe")) {
    Write-Log "No Windows image at $MountDir - run Step1-ExportAndMount.ps1 first." 'ERROR'
    exit 1
}
Write-Log 'Mount confirmed.'

# -- Apply updates with full session isolation --------------------------------
# Flow per KB:
#   Session A: apply SSU CAB -> unmount/commit -> remount
#   Session B: apply CU CAB  -> unmount/commit -> remount  (skip remount after last KB)

for ($i = 0; $i -lt $Updates.Count; $i++) {
    $update = $Updates[$i]
    $isLast = ($i -eq $Updates.Count - 1)

    $packagePath = Join-Path $UpdatesDir $update.File
    if (-not (Test-Path $packagePath)) {
        Write-Log "Package not found: $packagePath" 'ERROR'
        exit 1
    }

    Write-Log "=== $($update.KB): $($update.Desc) ==="

    # UseMSU: apply the .msu directly - bypasses CAB extraction to avoid CBS re-processing
    # the embedded SSU as a dependency inside the CU, which triggers 0x80073713.
    if ($update.UseMSU) {
        Write-Log "Applying $($update.KB) MSU directly (bypassing CAB extraction)..."
        dism /Image:"$MountDir" /Add-Package /PackagePath:"$packagePath" /ScratchDir:"$ScratchDir"
        if ($SkipCodes -contains $LASTEXITCODE) {
            Write-Log "$($update.KB) already applied or superseded - skipping." 'INFO'
        } elseif ($LASTEXITCODE -ne 0) {
            Write-Log "$($update.KB) MSU apply failed with exit code $LASTEXITCODE." 'ERROR'
            exit $LASTEXITCODE
        } else {
            Write-Log "$($update.KB) MSU applied successfully."
        }
        if (-not $isLast) {
            Dismount-Commit
            Mount-Wim
        }
        Write-Log "$($update.KB) complete."
        continue
    }

    # Extract MSU
    $kbExtractDir = Join-Path $ExtractDir $update.KB
    if (Test-Path $kbExtractDir) { Remove-Item $kbExtractDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $kbExtractDir | Out-Null
    Write-Log "Extracting $($update.KB) MSU..."
    & $ExpandExe -f:* "$packagePath" "$kbExtractDir" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "MSU extraction failed for $($update.KB)." 'ERROR'
        exit 1
    }

    # Find SSU and CU CABs
    $ssuCab = Get-ChildItem $kbExtractDir -Filter '*.cab' |
              Where-Object { $_.Name -match 'SSU|ServicingStack' } |
              Select-Object -First 1
    $cuCab  = Get-ChildItem $kbExtractDir -Filter '*.cab' |
              Where-Object { $_.Name -notmatch 'SSU|ServicingStack' } |
              Sort-Object Length -Descending |
              Select-Object -First 1

    # Session A: apply SSU CAB in its own session
    if ($ssuCab) {
        Invoke-DismPackage -PackagePath $ssuCab.FullName -Label "$($update.KB) SSU ($($ssuCab.Name))"
        Dismount-Commit
        Mount-Wim
    } else {
        Write-Log "No SSU CAB in $($update.KB) - skipping SSU session." 'INFO'
    }

    # Session B: apply CU CAB in its own session (unless SkipCU is set)
    if ($update.SkipCU) {
        Write-Log "$($update.KB) CU intentionally skipped - SSU-only update." 'INFO'
    } elseif ($cuCab) {
        Invoke-DismPackage -PackagePath $cuCab.FullName -Label "$($update.KB) CU ($($cuCab.Name))"
    } else {
        Write-Log "No CU CAB in $($update.KB) - skipping CU." 'WARN'
    }

    # Between KBs: unmount/commit/remount for clean state
    # After last KB: leave mounted for Invoke-CleanupAndUnmount.ps1
    if (-not $isLast) {
        Dismount-Commit
        Mount-Wim
    }

    Write-Log "$($update.KB) complete."
}

# -- Verify UBR ---------------------------------------------------------------
Write-Log 'Verifying UBR from offline registry...'
try {
    reg load 'HKLM\OFFLINE' "$MountDir\Windows\System32\config\SOFTWARE" | Out-Null
    $ubr   = (Get-ItemProperty 'HKLM:\OFFLINE\Microsoft\Windows NT\CurrentVersion').UBR
    $build = (Get-ItemProperty 'HKLM:\OFFLINE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
    reg unload 'HKLM\OFFLINE' | Out-Null
    Write-Log "OS Build after updates: $build.$ubr"
    if ($ubr -eq 7058) {
        Write-Log 'SUCCESS - target build 19045.7058 reached. Run Invoke-CleanupAndUnmount.ps1 next.'
    } else {
        Write-Log "UBR is $ubr - expected 7058. Review log for errors." 'WARN'
    }
} catch {
    Write-Log "Could not read UBR from offline registry: $_" 'WARN'
    reg unload 'HKLM\OFFLINE' 2>$null
}

Write-Log 'Update integration complete. Image is still mounted.'
Write-Log 'Next step: run Invoke-CleanupAndUnmount.ps1'
