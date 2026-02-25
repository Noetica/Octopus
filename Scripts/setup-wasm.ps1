param (
	[Parameter(Mandatory = $true)] [string]$AppName,
	[Parameter(Mandatory = $true)] [string]$SourceDir,
	[Parameter(Mandatory = $true)] [string]$TargetDir,
	[Parameter(Mandatory = $false)] [string]$SiteRoot = 'Synthesys_General',
	[Parameter(Mandatory = $false)] [string[]]$BackupFiles
)

<#
	Lightweight deployment script for Blazor WebAssembly (static file) applications.

	Unlike setup-webapp.ps1 (which manages app pools with .NET CLR v4.0), this script
	creates app pools with "No Managed Code" since WASM apps are purely static files
	served by IIS. File deployment uses robocopy /MIR for efficiency.

	Parameters:
		AppName     - IIS application name and app pool suffix, e.g. AmdQaToolWasm
		SourceDir   - Octopus-extracted package directory
		TargetDir   - IIS physical path for the web application
		SiteRoot    - IIS site name (default: Synthesys_General)
		BackupFiles - Files to preserve across deployments, e.g. appsettings.Production.json
#>

Write-Output "The script is running from: $PSScriptRoot"
. "$PSScriptRoot\utils\file-logger.ps1"

$script:appPoolName = "$($SiteRoot)_$($AppName)"
$script:backupDir = "$env:TentacleHome\Backups\$($AppName)_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"

<#==================================================#>

function EnsureIISPrerequisites() {
	if (-not (Get-Module -Name WebAdministration)) {
		Import-Module WebAdministration -ErrorAction Stop
		$logger.Log('Debug', 'Imported WebAdministration module.')
	}
}

<#
	Ensure the IIS app pool exists with "No Managed Code" (empty managedRuntimeVersion).
	Blazor WASM apps are static files and do not need the .NET CLR loaded.
	Creates the pool if missing; corrects managedRuntimeVersion if wrong (e.g. v4.0).
#>
function EnsureAppPool() {
	$poolPath = "IIS:\AppPools\$script:appPoolName"

	if (-not (Test-Path $poolPath)) {
		$logger.Log('Warn', "App pool missing. Creating '$script:appPoolName' with No Managed Code...")
		New-WebAppPool -Name $script:appPoolName | Out-Null
		Set-ItemProperty $poolPath -Name managedRuntimeVersion -Value ''
		Set-ItemProperty $poolPath -Name autoStart -Value $true
		$logger.Log('Info', "App pool created. ($script:appPoolName)")
	}
	else {
		$currentRuntime = (Get-ItemProperty $poolPath).managedRuntimeVersion
		if ($currentRuntime -ne '') {
			$logger.Log('Warn', "App pool has managedRuntimeVersion='$currentRuntime'. Changing to No Managed Code...")
			Set-ItemProperty $poolPath -Name managedRuntimeVersion -Value ''
			$logger.Log('Info', 'App pool corrected to No Managed Code.')
		}
		else {
			$logger.Log('Info', "App pool exists with No Managed Code. ($script:appPoolName)")
		}
	}
}

<#
	Ensure the IIS web application exists under the target site.
	Creates it if missing.
#>
function EnsureWebApplication() {
	$existingApp = Get-WebApplication -Site $SiteRoot -Name $AppName -ErrorAction SilentlyContinue

	if ($null -eq $existingApp) {
		$logger.Log('Warn', "Web application missing. Creating '/$AppName' on site '$SiteRoot'...")
		if (-not (Test-Path $TargetDir)) {
			New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
		}
		New-WebApplication -Site $SiteRoot -Name $AppName -PhysicalPath $TargetDir -ApplicationPool $script:appPoolName | Out-Null
		$logger.Log('Info', "Web application created. (/$AppName -> $TargetDir)")
	}
	else {
		$logger.Log('Info', "Web application exists. (/$AppName)")
	}
}

<#
	Backup specified files from the current deployment before overwriting.
#>
function BackupFiles() {
	if ($null -eq $BackupFiles -or $BackupFiles.Count -eq 0) {
		$logger.Log('Debug', 'No backup files configured.')
		return
	}
	if (-not (Test-Path $TargetDir)) {
		$logger.Log('Debug', 'Target directory does not exist yet. Nothing to backup.')
		return
	}

	foreach ($filename in $BackupFiles) {
		$matches = @(Get-ChildItem -Path $TargetDir -Recurse -File -Filter $filename -ErrorAction SilentlyContinue)
		foreach ($file in $matches) {
			$relativePath = $file.FullName.Substring($TargetDir.Length).TrimStart('\')
			$backupPath = Join-Path $script:backupDir $relativePath
			$backupParent = Split-Path $backupPath -Parent
			if (-not (Test-Path $backupParent)) {
				New-Item -Path $backupParent -ItemType Directory -Force | Out-Null
			}
			Copy-Item -Path $file.FullName -Destination $backupPath -Force
			if (Test-Path $backupPath) {
				$logger.Log('Info', "Backed up: $relativePath")
			}
			else {
				$logger.Log('Critical', "Failed to backup: $relativePath")
				exit 1
			}
		}
	}
}

<#
	Deploy files from source to target using robocopy /MIR for fast, efficient mirroring.
	This replaces the file-by-file copy approach — one robocopy call handles the lot.
	Robocopy exit codes 0-7 are success; 8+ are errors.
#>
function DeployFiles() {
	if (-not (Test-Path -Path $SourceDir)) {
		$logger.Log('Critical', "Source directory does not exist. ($SourceDir)")
		exit 1
	}

	if (-not (Test-Path -Path $TargetDir)) {
		New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
		$logger.Log('Debug', "Created target directory. ($TargetDir)")
	}

	$logger.Log('Info', "Deploying WASM files: $SourceDir -> $TargetDir")

	$robocopyArgs = @($SourceDir, $TargetDir, '/MIR', '/R:3', '/W:5', '/NP', '/NFL', '/NDL')
	$logger.Log('Debug', "robocopy $($robocopyArgs -join ' ')")

	$output = & robocopy @robocopyArgs 2>&1
	$exitCode = $LASTEXITCODE

	# Log the summary lines from robocopy output
	$inSummary = $false
	foreach ($line in $output) {
		$trimmed = "$line".Trim()
		if ($trimmed -match '^-+$') { $inSummary = $true; continue }
		if ($inSummary -and $trimmed -ne '') {
			$logger.Log('Info', $trimmed)
		}
	}

	if ($exitCode -ge 8) {
		$logger.Log('Critical', "robocopy failed with exit code $exitCode")
		foreach ($line in $output) {
			$previousEAP = $ErrorActionPreference
			$ErrorActionPreference = 'Continue'
			$logger.Log('Error', "$line")
			$ErrorActionPreference = $previousEAP
		}
		exit 1
	}

	$logger.Log('Info', "Deployment complete. (robocopy exit code: $exitCode)")
}

<#
	Restore backed-up files over the freshly deployed versions.
#>
function RestoreFiles() {
	if (-not (Test-Path $script:backupDir)) { return }

	$backedUp = @(Get-ChildItem -Path $script:backupDir -Recurse -File -ErrorAction SilentlyContinue)
	if ($backedUp.Count -eq 0) {
		$logger.Log('Debug', 'No backups to restore.')
		return
	}

	$logger.Log('Info', 'Restoring backed-up files...')
	foreach ($file in $backedUp) {
		$relativePath = $file.FullName.Substring($script:backupDir.Length).TrimStart('\')
		$destination = Join-Path $TargetDir $relativePath
		$destParent = Split-Path $destination -Parent
		if (-not (Test-Path $destParent)) {
			New-Item -Path $destParent -ItemType Directory -Force | Out-Null
		}
		Copy-Item -Path $file.FullName -Destination $destination -Force
		if (Test-Path $destination) {
			$logger.Log('Info', "Restored: $relativePath")
		}
		else {
			$logger.Log('Critical', "Failed to restore: $relativePath")
			exit 1
		}
	}
}

<#==================================================#>

$logger = File-Logger
EnsureIISPrerequisites
EnsureAppPool
EnsureWebApplication
BackupFiles
DeployFiles
RestoreFiles

$logFileLocation = File-Logger-Location
Write-Host "WASM deployment completed. Full log file can be found at $logFileLocation."

