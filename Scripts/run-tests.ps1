Param (
    [string]$AppName, # Name of the artifact (versionless) or display name, e.g. ReportsAPI
    [string]$TargetDir # Location of the target deployment directory
)

$testPath = $TargetDir + "\" + $AppName + ".Tests"
$dll = $AppName + ".Tests.dll"
Write-Output "Changing path to  file path is: $testPath"
Set-Location -Path $testPath
$currentPath = Get-Location
Write-Output "Current file path is: $currentPath"
dotnet vstest $dll 


