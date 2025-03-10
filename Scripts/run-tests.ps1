[Parameter(Mandatory = $true)] [string]$AppName, # Name of the artifact (versionless) or display name, e.g. ReportsAPI
[Parameter(Mandatory = $true)] [string]$TargetDir # Location of the target deployment directory

$testPath = "$TargetDir\$AppName.Tests"
cd "$testPath"
dotnet test --no-build


