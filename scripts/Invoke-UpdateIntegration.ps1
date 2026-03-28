#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Integrates cumulative updates into a mounted Windows image using DISM.

.DESCRIPTION
    Applies each update by extracting the MSU, applying the SSU CAB first,
    then the CU CAB. All updates are applied fully offline via DISM.
    No first-boot wusa.exe required.

    Update chain (base 19045.3803 -> target 19045.7058):
      KB5039299  2024-06  3803 -> 4598   (bridge 1)
      KB5050081  2025-01  4598 -> 5440   (bridge 2)
      KB5063709  2025-08  5440 -> ~5960  (bridge 3, ESU prereq)
      KB5075912  2026-02  ~5960 -> 6937  (bridge 4)
      KB5078885  2026-03  6937 -> 7058   (target)

.NOTES
    - The image must already be mounted. Run Step1-ExportAndMount.ps1 first.
    - Run from an elevated (Administrator) PowerShell prompt.
    - DISM offline does not enforce ESU enrollment - all post-EOL CUs apply normally.
#>

# -- Paths --------------------------------------------------------------------
$MountDir   = "V:\RWJBH-Lab\Mount"
$ScratchDir = "V:\RWJBH-Lab\Scratch"
$UpdatesDir = 'V:\RWJBH-Lab\ISOs\Win10\Updates'
$ExtractDir = "V:\RWJBH-Lab\Scratch\MSU_Extracted"
$LogFile    = "V:\RWJBH-Lab\GitHub\Win10Pro_Build\logs\update-integration.log"

# -- Updates to integrate (in order) -----------------------------------------
$Updates = @(
    @{
        KB      = 'KB5039299'
        File    = 'windows10.0-kb5039299-x64.msu'
        Desc    = '2024-06 Cumulative Update for Windows 10 22H2 x64 (bridge 1)'
        FullMsu = $false
        SsuOnly = $false
    },
    @{
        KB      = 'KB5050081'
        File    = 'windows10.0-kb5050081-x64.msu'
        Desc    = '2025-01 Cumulative Update for Windows 10 22H2 x64 (bridge 2)'
        FullMsu = $false
        SsuOnly = $false
    },
    @{
        KB      = 'KB5063709'
        File    = 'windows10.0-kb5063709-x64.msu'
        Desc    = '2025-08 Cumulative Update for Windows 10 22H2 x64 (bridge 3)'
        FullMsu = $false
        SsuOnly = $false
    },
    @{
        KB      = 'KB5075912'
        File    = 'windows10.0-kb5075912-x64.msu'
        Desc    = '2026-02 Cumulative Update for Windows 10 22H2 x64 (bridge 4)'
        FullMsu = $false
        SsuOnly = $false
    },
    @{
        KB      = 'KB5078885'
        File    = 'windows10.0-kb5078885-x64.msu'
        Desc    = '2026-03 Cumulative Update for Windows 10 22H2 x64 (target - 19045.7058)'
        FullMsu = $false
        SsuOnly = $false
    }
)

# -- Setup --------------------------------------------------------------------
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null
New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

# -- Verify mount -------------------------------------------------------------
Write-Log "Verifying mounted image at $MountDir"
if (-not (Test-Path (Join-Path $MountDir "Windows\System32\ntoskrnl.exe"))) {
    Write-Log "No Windows image found at $MountDir - run Step1-ExportAndMount.ps1 first." "ERROR"
    exit 1
}
Write-Log "Mount confirmed."

# -- Apply updates ------------------------------------------------------------
foreach ($update in $Updates) {
    $packagePath = Join-Path $UpdatesDir $update.File

    if (-not (Test-Path $packagePath)) {
        Write-Log "Package not found: $packagePath" "ERROR"
        exit 1
    }

    if ($update.FullMsu) {
        # -- Full MSU mode: apply directly, no extraction ---------------------
        Write-Log "Applying $($update.KB) as full MSU - $($update.Desc)"
        dism /Image:"$MountDir" /Add-Package /PackagePath:"$packagePath" /ScratchDir:"$ScratchDir"
        if ($LASTEXITCODE -ne 0) {
            Write-Log "DISM returned exit code $LASTEXITCODE for $($update.KB)." "ERROR"
            exit $LASTEXITCODE
        }
    } else {
        # -- CAB extraction mode: extract MSU, apply SSU CAB, optionally CU --
        $kbExtractDir = Join-Path $ExtractDir $update.KB
        if (Test-Path $kbExtractDir) { Remove-Item $kbExtractDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $kbExtractDir | Out-Null

        Write-Log "Extracting $($update.KB) MSU to $kbExtractDir ..."
        $expandResult = & expand.exe -f:* "$packagePath" "$kbExtractDir" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "MSU extraction failed: $expandResult" "ERROR"
            exit 1
        }
        Write-Log "Extraction complete."

        # Apply SSU CAB first
        $ssuCab = Get-ChildItem $kbExtractDir -Filter "*.cab" |
                  Where-Object { $_.Name -match "SSU|ServicingStack|ssu" } |
                  Select-Object -First 1

        if ($ssuCab) {
            Write-Log "Applying SSU: $($ssuCab.Name)"
            dism /Image:"$MountDir" /Add-Package /PackagePath:"$($ssuCab.FullName)" /ScratchDir:"$ScratchDir"
            if ($LASTEXITCODE -ne 0) {
                Write-Log "SSU apply failed with exit code $LASTEXITCODE." "ERROR"
                exit $LASTEXITCODE
            }
            Write-Log "SSU applied successfully."
        } else {
            Write-Log "No SSU CAB found in MSU - skipping SSU step." "INFO"
        }

        # SSU-only mode: skip CU CAB intentionally
        if ($update.SsuOnly) {
            Write-Log "$($update.KB) SSU-only mode - CU CAB intentionally skipped."
            Write-Log "$($update.KB) SSU applied successfully."
            continue
        }

        # Apply main CU CAB (largest non-SSU cab)
        $cuCab = Get-ChildItem $kbExtractDir -Filter "*.cab" |
                 Where-Object { $_.Name -notmatch "SSU|ServicingStack|ssu" } |
                 Sort-Object Length -Descending |
                 Select-Object -First 1

        if ($cuCab) {
            Write-Log "Applying CU CAB: $($cuCab.Name)"
            dism /Image:"$MountDir" /Add-Package /PackagePath:"$($cuCab.FullName)" /ScratchDir:"$ScratchDir"
            if ($LASTEXITCODE -ne 0) {
                Write-Log "CU CAB apply failed with exit code $LASTEXITCODE." "ERROR"
                exit $LASTEXITCODE
            }
        } else {
            Write-Log "No CU CAB found - applying full MSU directly."
            dism /Image:"$MountDir" /Add-Package /PackagePath:"$packagePath" /ScratchDir:"$ScratchDir"
            if ($LASTEXITCODE -ne 0) {
                Write-Log "DISM returned exit code $LASTEXITCODE for $($update.KB)." "ERROR"
                exit $LASTEXITCODE
            }
        }
    }

    Write-Log "$($update.KB) applied successfully."
}

# -- Verify UBR from offline registry ----------------------------------------
Write-Log "Verifying Update Build Revision (UBR) from offline registry..."
try {
    reg load "HKLM\OFFLINE" "$MountDir\Windows\System32\config\SOFTWARE" | Out-Null
    $ubr   = (Get-ItemProperty "HKLM:\OFFLINE\Microsoft\Windows NT\CurrentVersion").UBR
    $build = (Get-ItemProperty "HKLM:\OFFLINE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
    reg unload "HKLM\OFFLINE" | Out-Null
    Write-Log "OS Build after update: $build.$ubr"
    if ($ubr -eq 7058) {
        Write-Log "UBR matches expected value (7058) - all updates applied. SUCCESS."
    } elseif ($ubr -eq 6937) {
        Write-Log "UBR is 6937 - KB5075912 applied but KB5078885 may have failed." "WARN"
    } elseif ($ubr -eq 5440) {
        Write-Log "UBR is 5440 - only KB5039299 + KB5050081 applied. KB5063709 and later may have failed." "WARN"
    } else {
        Write-Log "UBR is $ubr - expected 7058. Verify updates were applied correctly." "WARN"
    }
} catch {
    Write-Log "Could not read UBR from offline registry: $_" "WARN"
    reg unload "HKLM\OFFLINE" 2>$null
}

# -- List integrated packages -------------------------------------------------
Write-Log "Listing all integrated packages (appended to log)..."
dism /Image:"$MountDir" /Get-Packages >> $LogFile

Write-Log "Update integration complete. Review log at: $LogFile"
Write-Log "Next step: run Invoke-CleanupAndUnmount.ps1 - see docs/build-process.md Step 8."
