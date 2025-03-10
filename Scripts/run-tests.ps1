Param (
    [string]$AppName, # Name of the artifact (versionless) or display name, e.g. ReportsAPI
    [string]$TargetDir # Location of the target deployment directory
)

$testPath = $TargetDir + "\" + $AppName + ".Tests"

cd "${$testPath}"
$currentPath = Get-Location
Write-Output "Current file path is: $currentPath"
dotnet test --no-build


