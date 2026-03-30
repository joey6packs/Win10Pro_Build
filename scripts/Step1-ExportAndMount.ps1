#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Exports the Windows 10 Pro index from install.esd to a writable WIM,
    then mounts it ready for update integration.

.NOTES
    - Run from an elevated (Administrator) PowerShell prompt.
    - Run this BEFORE Invoke-UpdateIntegration.ps1.
    - The exported WIM is written to V:\Lab\ISOs\Win10\install.wim
    - The image is mounted to V:\Lab\Mount\
#>

# -- Paths --------------------------------------------------------------------
$EsdFile    = "E:\x64\sources\install.esd"
$WimFile    = "V:\Lab\ISOs\Win10\install_pro.wim"
$MountDir   = "V:\Lab\Mount"
$ScratchDir = "V:\Lab\Scratch"
$LogFile    = "V:\Lab\GitHub\Win10Pro_Build\logs\update-integration.log"

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null
New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null
New-Item -ItemType Directory -Force -Path $MountDir | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

# -- List available indexes ---------------------------------------------------
Write-Log "Reading image indexes from $EsdFile ..."
dism /Get-WimInfo /WimFile:"$EsdFile"

# -- Find the Windows 10 Pro index --------------------------------------------
Write-Log "Detecting Windows 10 Pro index..."
$wimInfo = dism /Get-WimInfo /WimFile:"$EsdFile"
$proIndex = $null
$currentIndex = $null
foreach ($line in $wimInfo) {
    if ($line -match "Index\s*:\s*(\d+)") {
        $currentIndex = [int]$Matches[1]
    }
    if ($line -match "^Name\s*:\s*Windows 10 Pro$" -and $currentIndex) {
        $proIndex = $currentIndex
        break
    }
}

if (-not $proIndex) {
    Write-Log "Could not auto-detect Windows 10 Pro index. Check the index list above and set manually." "ERROR"
    exit 1
}
Write-Log "Windows 10 Pro found at index $proIndex."

# -- Export ESD index to WIM --------------------------------------------------
if (Test-Path $WimFile) {
    Write-Log "Existing install.wim found at $WimFile - removing before export."
    Remove-Item $WimFile -Force
}

Write-Log "Exporting index $proIndex from ESD to WIM (this takes several minutes)..."
dism /Export-Image /SourceImageFile:"$EsdFile" /SourceIndex:$proIndex `
     /DestinationImageFile:"$WimFile" /Compress:max /CheckIntegrity

if ($LASTEXITCODE -ne 0) {
    Write-Log "Export failed with exit code $LASTEXITCODE." "ERROR"
    exit $LASTEXITCODE
}
Write-Log "Export complete: $WimFile"

# -- Mount the WIM ------------------------------------------------------------
Write-Log "Cleaning up any stale mount tracking before mounting..."
dism /Cleanup-Mountpoints | Out-Null

Write-Log "Mounting $WimFile at $MountDir ..."
dism /Mount-Image /ImageFile:"$WimFile" /Index:1 /MountDir:"$MountDir"

if ($LASTEXITCODE -ne 0) {
    Write-Log "Mount failed with exit code $LASTEXITCODE." "ERROR"
    exit $LASTEXITCODE
}
Write-Log "Image mounted successfully at $MountDir."
Write-Log "Next step: run Invoke-UpdateIntegration.ps1"
