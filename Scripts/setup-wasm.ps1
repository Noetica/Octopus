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

	# Build the exclusion list up front so it applies to both deletion and copy.
	$excludedNames = @()
	if ($null -ne $FileExclusions) {
		$excludedNames += $FileExclusions
	}
	$excludedNames += ($script:backupTargets | ForEach-Object { $_.filename })
	$excludedNames = @($excludedNames | Select-Object -Unique)

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

		$errorList = @()
		# Build full excluded paths from relative exclusions so the match is path-based
		# (consistent with setup-api.ps1) rather than filename-only. Exclusions may be
		# simple filenames (e.g. "appsettings.json") or relative paths (e.g. "config\local.json").
		$excludedPaths = @($excludedNames | ForEach-Object { Join-Path $script:targetDir $_ })
		# Enumerate only top-level items and remove each non-excluded subtree in one shot,
		# avoiding ordering issues that arise from recursive enumeration + individual deletes.
		$targets = @(Get-ChildItem -Path $script:targetDir -Force)
		foreach ($item in $targets) {
			if ($excludedPaths -contains $item.FullName) {
				$logger.Log('Debug', "Skipping excluded item. ($($item.FullName))")
				continue
			}

			try {
				Remove-Item -LiteralPath $item.FullName -Force -Recurse -ErrorAction Stop
				$logger.Log('Debug', "Deleted successfully. ($($item.FullName))")
			}
			catch {
				$errorList += "Failed to delete: $($item.FullName) | Error: $($_.Exception.Message)"
				$logger.Log('Error', "Failed to delete. ($($item.FullName))")
			}
		}

		if ($errorList.Count -gt 0) {
			$logger.Log('Error', 'Error(s) occurred during target clean-up:')
			$errorList | ForEach-Object { $logger.Log('Error', $_) }
			exit 1
		}
	}

	$logger.Log('Info', 'Deploying latest WASM artifact...')
	$itemsToCopy = Get-ChildItem -Path $script:sourceDir -Recurse -Force |
		Where-Object { $excludedNames -notcontains $_.Name }
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

			try {
				Copy-Item -Path $source -Destination $destination -Force -ErrorAction Stop
				$logger.Log('Info', "Restored successfully. ($relativePath)")
			}
			catch {
				$logger.Log('Critical', "Failed to restore backup. ($relativePath): $_")
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

