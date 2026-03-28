#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Cleans up the mounted image and commits changes.

.DESCRIPTION
    Runs DISM component cleanup to reduce WIM size, then unmounts and commits
    the image. Run this AFTER Invoke-UpdateIntegration.ps1 completes successfully.
    All updates including KB5078885 are applied fully offline - no first-boot
    wusa.exe required.

.NOTES
    - Run from an elevated (Administrator) PowerShell prompt.
    - After this script, the image is no longer mounted. The next step is
      repackaging the ISO - see docs/build-process.md Steps 9-10.
#>

# -- Paths --------------------------------------------------------------------
$MountDir = 'V:\RWJBH-Lab\Mount'
$LogFile  = 'V:\RWJBH-Lab\GitHub\Win10Pro_Build\logs\update-integration.log'

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

# -- Remove legacy C:\Updates\ staging folder if present ---------------------
$legacyUpdates = Join-Path $MountDir 'Updates'
if (Test-Path $legacyUpdates) {
    Write-Log 'Removing legacy C:\Updates\ staging folder from image...'
    Remove-Item $legacyUpdates -Recurse -Force
    Write-Log 'Legacy staging folder removed.'
}

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
