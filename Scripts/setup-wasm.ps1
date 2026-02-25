param (
	[Parameter(Mandatory = $true)] [string]$AppName,
	[Parameter(Mandatory = $true)] [string]$SourceDir,
	[Parameter(Mandatory = $true)] [string]$TargetDir,
	[Parameter(Mandatory = $false)] [string[]]$BackupFiles,
	[Parameter(Mandatory = $false)] [string[]]$FileExclusions
)

Write-Output "The script is running from: $PSScriptRoot"

# Initialize script-scoped variables from parameters
$script:appName = $AppName
$script:sourceDir = $SourceDir
$script:targetDir = $TargetDir
$script:backupDir = "$env:TentacleHome\Logs\$($script:appName)_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
$script:backupTargets = New-Object System.Collections.Generic.List[Hashtable]

. "$PSScriptRoot\utils\file-logger.ps1"

<#==================================================#>

function ConfigureBackupRestore() {
	if ($null -eq $BackupFiles -or $BackupFiles.Count -eq 0) {
		$logger.Log('Debug', 'No backup files configured.')
		return
	}

	foreach ($filename in $BackupFiles) {
		$logger.Log('Debug', "Adding backup/restore target. ($filename)")
		$script:backupTargets.Add(
			[Hashtable]@{
				filename      = $filename
				relativePaths = @()
			}
		) | Out-Null
	}
}

function CheckExistingDeployment() {
	$logger.Log('Info', 'Checking existing WASM deployment...')
	if (-not (Test-Path $script:targetDir)) {
		$logger.Log('Info', 'No existing deployment found.')
		return
	}

	foreach ($target in $script:backupTargets) {
		$matches = @(Get-ChildItem -Path $script:targetDir -Recurse -File -Filter $target.filename -ErrorAction SilentlyContinue)
		if ($matches.Count -eq 0) {
			continue
		}

		foreach ($file in $matches) {
			$relativePath = $file.FullName.Substring($script:targetDir.Length).TrimStart('\\')
			$target.relativePaths += $relativePath

			$destinationDir = Join-Path -Path $script:backupDir -ChildPath (Split-Path -Path $relativePath -Parent)
			if (-not (Test-Path $destinationDir)) {
				New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
			}

			$destinationFile = Join-Path -Path $script:backupDir -ChildPath $relativePath
			Copy-Item -Path $file.FullName -Destination $destinationFile -Force

			if (Test-Path $destinationFile) {
				$logger.Log('Info', "Backed up successfully. ($destinationFile)")
			}
			else {
				$logger.Log('Critical', "Failed to backup file. ($($file.FullName))")
				exit 1
			}
		}
	}
}

function DeployLatestArtifact() {
	if (-not (Test-Path -Path $script:sourceDir)) {
		$logger.Log('Critical', "Source directory does not exist. ($($script:sourceDir))")
		exit 1
	}

	if (-not (Test-Path -Path $script:targetDir)) {
		$logger.Log('Debug', 'Creating target directory...')
		New-Item -ItemType Directory -Path $script:targetDir -Force | Out-Null
		if (Test-Path $script:targetDir) {
			$logger.Log('Debug', "Directory created successfully. ($($script:targetDir))")
		}
		else {
			$logger.Log('Critical', "Directory not created. ($($script:targetDir))")
			exit 1
		}
	}
	else {
		$logger.Log('Debug', 'Clearing deployment target directory contents...')

		$excludedNames = @()
		if ($null -ne $FileExclusions) {
			$excludedNames += $FileExclusions
		}
		$excludedNames += ($script:backupTargets | ForEach-Object { $_.filename })
		$excludedNames = @($excludedNames | Select-Object -Unique)

		$errorList = @()
		$targets = @(Get-ChildItem -Path $script:targetDir -Force)
		foreach ($item in $targets) {
			if ($excludedNames -contains $item.Name) {
				$logger.Log('Debug', "Skipping excluded item. ($($item.FullName))")
				continue
			}

			try {
				Remove-Item -LiteralPath $item.FullName -Force -Recurse -ErrorAction Stop
				$logger.Log('Debug', "Deleted successfully. ($($item.FullName))")
			}
			catch {
				$errorList += "Failed to delete: $($item.FullName) | Error: $($_.Exception.Message)"
				# Use 'Continue' to prevent Write-Error inside the logger from throwing
				# when Octopus sets $ErrorActionPreference = 'Stop'
				$previousEAP = $ErrorActionPreference
				$ErrorActionPreference = 'Continue'
				$logger.Log('Error', "Failed to delete. ($($item.FullName))")
				$ErrorActionPreference = $previousEAP
			}
		}

		if ($errorList.Count -gt 0) {
			$previousEAP = $ErrorActionPreference
			$ErrorActionPreference = 'Continue'
			$logger.Log('Error', 'Error(s) occurred during target clean-up:')
			$errorList | ForEach-Object { $logger.Log('Error', $_) }
			$ErrorActionPreference = $previousEAP
			exit 1
		}
	}

	$logger.Log('Info', 'Deploying latest WASM artifact...')
	$itemsToCopy = Get-ChildItem -Path $script:sourceDir -Recurse -Force
	foreach ($item in $itemsToCopy) {
		$relativePath = $item.FullName.Substring($script:sourceDir.Length).TrimStart('\\')
		$destinationPath = Join-Path -Path $script:targetDir -ChildPath $relativePath

		if ($item.PSIsContainer) {
			New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
			continue
		}

		$destinationParent = Split-Path -Path $destinationPath -Parent
		if (-not (Test-Path $destinationParent)) {
			New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
		}

		try {
			Copy-Item -Path $item.FullName -Destination $destinationPath -Force -ErrorAction Stop
			if (Test-Path $destinationPath) {
				$logger.Log('Info', "Copied successfully. ($relativePath)")
			}
			else {
				$logger.Log('Critical', "File not copied. ($($item.FullName))")
				exit 1
			}
		}
		catch {
			$logger.Log('Critical', "Failed to copy file. ($($item.FullName)) - $($_.Exception.Message)")
			exit 1
		}
	}
}

function RestoreBackups() {
	$targetsWithBackups = @($script:backupTargets | Where-Object { $_.relativePaths.Count -gt 0 })
	if ($targetsWithBackups.Count -eq 0) {
		$logger.Log('Debug', 'No backups to restore.')
		return
	}

	$logger.Log('Info', 'Restoring backups...')
	foreach ($target in $targetsWithBackups) {
		foreach ($relativePath in $target.relativePaths) {
			$source = Join-Path -Path $script:backupDir -ChildPath $relativePath
			$destination = Join-Path -Path $script:targetDir -ChildPath $relativePath
			$destinationDir = Split-Path -Path $destination -Parent

			if (-not (Test-Path $destinationDir)) {
				New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
			}

			Copy-Item -Path $source -Destination $destination -Force
			if (Test-Path $destination) {
				$logger.Log('Info', "Restored successfully. ($relativePath)")
			}
			else {
				$logger.Log('Critical', "Failed to restore backup. ($relativePath)")
				exit 1
			}
		}
	}
}

<#==================================================#>

$logger = File-Logger
ConfigureBackupRestore
CheckExistingDeployment
DeployLatestArtifact
RestoreBackups
$logFileLocation = File-Logger-Location
Write-Host "WASM deployment completed. Full log file can be found at $logFileLocation."

