#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Cleans up the mounted image and commits changes.

.DESCRIPTION
    Stages KB5078885 into the image for first-logon installation, runs DISM
    component cleanup to reduce WIM size, then unmounts and commits the image.
    Run this AFTER Invoke-UpdateIntegration.ps1 completes successfully.

    KB5078885 cannot be applied offline (SSU 7052 advanced installer requires
    full boot context). It is staged to C:\Updates\ in the WIM and installed
    on first logon via autounattend.xml FirstLogonCommands.

.NOTES
    - Run from an elevated (Administrator) PowerShell prompt.
    - After this script, the image is no longer mounted. The next step is
      repackaging the ISO - see docs/build-process.md Steps 9-10.
#>

# -- Paths --------------------------------------------------------------------
$MountDir   = "V:\RWJBH-Lab\Mount"
$UpdatesDir = "V:\RWJBH-Lab\ISOs\Win10"
$LogFile    = "V:\RWJBH-Lab\GitHub\Win10Pro_Build\logs\update-integration.log"

# KB5078885 MSU — staged into the image for first-logon installation
$Kb5078885File = "windows10.0-kb5078885-x64_8013483b567f16e057931c30725c6c8723007a31.msu"

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

# -- Stage KB5078885 into the image for first-logon installation --------------
Write-Log "Staging KB5078885 MSU into image at C:\Updates\ ..."

$sourceMsu  = Join-Path $UpdatesDir $Kb5078885File
$stageDir   = Join-Path $MountDir "Updates"

if (-not (Test-Path $sourceMsu)) {
    Write-Log "KB5078885 MSU not found at $sourceMsu" "ERROR"
    exit 1
}

New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
Copy-Item $sourceMsu $stageDir -Force

Write-Log "KB5078885 staged to $stageDir\$Kb5078885File"

# -- Component cleanup --------------------------------------------------------
Write-Log "Starting component cleanup (StartComponentCleanup /ResetBase)..."
Write-Log "This may take several minutes."

dism /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup /ResetBase

if ($LASTEXITCODE -ne 0) {
    Write-Log "Cleanup failed with exit code $LASTEXITCODE." "ERROR"
    exit $LASTEXITCODE
}
Write-Log "Cleanup complete."

# -- Unmount and commit -------------------------------------------------------
Write-Log "Unmounting and committing image at $MountDir..."

dism /Unmount-Image /MountDir:"$MountDir" /Commit

if ($LASTEXITCODE -ne 0) {
    Write-Log "Unmount failed with exit code $LASTEXITCODE." "ERROR"
    exit $LASTEXITCODE
}

Write-Log "Image unmounted and committed successfully."
Write-Log "Next step: export image and repackage ISO - see docs/build-process.md Steps 9-10."
