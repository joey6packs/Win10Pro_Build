#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Integrates cumulative updates into a mounted Windows image using DISM.

.DESCRIPTION
    Each update entry can use one of two modes:
    - FullMsu = $false  : Extracts the MSU, applies the SSU CAB first, then the CU CAB.
                          Used for bridge updates where the SSU needs to be staged before
                          the CU (e.g. KB5039299).
    - FullMsu = $true   : Applies the full MSU directly without extraction.
                          Used when splitting the MSU into CABs corrupts the image
                          (e.g. KB5078885 after the bridge SSU is already in place).

.NOTES
    - The image must already be mounted. Run Step1-ExportAndMount.ps1 first.
    - Run from an elevated (Administrator) PowerShell prompt.
#>

# -- Paths --------------------------------------------------------------------
$MountDir   = "V:\RWJBH-Lab\Mount"
$ScratchDir = "V:\RWJBH-Lab\Scratch"
$UpdatesDir = "V:\RWJBH-Lab\ISOs\Win10"
$ExtractDir = "V:\RWJBH-Lab\Scratch\MSU_Extracted"
$LogFile    = "V:\RWJBH-Lab\GitHub\Win10Pro_Build\logs\update-integration.log"

# -- Updates to integrate (in order) -----------------------------------------
# SSU ladder bridges from base (3803) to 19045.5440 offline.
#
#   KB5039299  CAB    19045.3803 -> 19045.4598  SSU: 3803-era -> 4585
#   KB5050081  CAB    19045.4598 -> 19045.5440  SSU: 4585 -> 2025-01
#
# KB5075912 and KB5078885 are NOT applied offline:
#   - KB5075912 CU CAB fails with error 14099 after its SSU CAB offline.
#   - KB5078885 SSU 7052 advanced installer requires full boot context;
#     ERROR_ADVANCED_INSTALLER_FAILED (0x80073713) every attempt offline.
#
# KB5078885 is instead staged into C:\Updates\ in the image by
# Invoke-CleanupAndUnmount.ps1 and installed on first logon via
# autounattend.xml FirstLogonCommands. Final installed build: 19045.7058.
$Updates = @(
    @{
        KB      = "KB5039299"
        File    = "windows10.0-kb5039299-x64.msu"
        Desc    = "2024-06 Cumulative Update Preview for Windows 10 22H2 x64 (bridge 1)"
        FullMsu = $false
        SsuOnly = $false
    },
    @{
        KB      = "KB5050081"
        File    = "windows10.0-kb5050081-x64.msu"
        Desc    = "2025-01 Cumulative Update Preview for Windows 10 22H2 x64 (bridge 2)"
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
    if ($ubr -eq 5440) {
        Write-Log "UBR matches expected value (5440) for KB5039299 + KB5050081. SUCCESS."
        Write-Log "KB5078885 will be installed on first logon via autounattend.xml FirstLogonCommands."
    } elseif ($ubr -eq 4598) {
        Write-Log "UBR is 4598 - only KB5039299 applied. KB5050081 may have failed." "WARN"
    } else {
        Write-Log "UBR is $ubr - expected 5440. Verify updates were applied correctly." "WARN"
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
