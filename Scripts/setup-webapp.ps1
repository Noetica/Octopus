param (
    [Parameter(Mandatory = $true)] [string]$AppName, # Name of the artifact (versionless) or display name, e.g. ReportsAPI
    [Parameter(Mandatory = $true)] [string]$SourceDir, # Location of the source artifact to be deployed
    [Parameter(Mandatory = $false)] [string]$SiteRoot = 'Synthesys_General', # Location of the site deployment
    [Parameter(Mandatory = $true)] [string]$TargetDir, # Location of the target deployment directory
    [Parameter(Mandatory = $false)] [string[]]$BackupFiles, # Files to preserve when updating existing deployment
    [Parameter(Mandatory = $false)] [string[]]$Output # Specify a custom location for the log output
)

<#==================================================#>

# Prerequisites to check before deployment
$script:requiredFeatures = @('Web-Scripting-Tools')
$script:requiredModules = @('IISAdministration', 'WebAdministration')
# App & App Pool variables
$script:appPath = "/$script:appName"
$script:appPool = $null
$script:appPoolName = "$($script:siteRoot)_$($script:appName)"
$script:retryCount = 0
$script:maxRetries = 5
$script:retryDelay = 5 # seconds
# Backup/Restore variables
$script:backupDir = "$env:TentacleHome"+"\Logs\"+"$($script:appName)_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
$script:backupTargets = $null
# Logging: Use override if specified, or default value
$script:logFile = if ($null -ne $Output) { $Output } else { "$($script:backupDir).log" }

<#==================================================#>

class Util {
    # Property for log file path
    [string]$logFile
    # Constructor to initialize the log file path
    Util([string]$logFilePath) {
        $this.LogFile = $logFilePath
    }
    # Log method
    [void] Log([string]$level, [string]$message) {
        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $logItem = "[$timestamp] [$level] $message"
        # Output to console
        Write-Host $logItem
        # Write to log file
        try {
            Add-Content -Path $this.LogFile -Value $logItem
        }
        catch {
            Write-Host "Failed to write to log file: $_" -ForegroundColor Red
        }
    }

    <#
        [util] Get relative path of a file in a target directory
        Output the file and the relative path, or null if not found
    #>
    [hashtable] GetRelativePath([string]$directory, [string]$filename) {
        $match = @{
            file         = $null
            filename     = $filename
            relativePath = $null
        }
        $this.Log('Info', "Searching $directory for $($filename)")
        $match.file = Get-ChildItem -Path $directory -Recurse -File -Filter $filename -ErrorAction SilentlyContinue
        if ($match.file) {
            # Check if the file is nested
            $match.relativePath = $($match.file.FullName.Substring($directory.Length).TrimStart('\'))
            if ($match.relativePath.Contains('\')) {
                $match.relativePath = Split-Path $match.relativePath -Parent
                $this.Log('Info', "File found. ($($match.relativePath)\$filename)")
            }
            else {
                $this.Log('Info', "File found. ($filename)")
            }
        }
        else {
            $this.Log('Warning', "File not found. ($($filename))")
        }
        if ($match.file) {
            return $match
        }
        else {
            return $null
        }
    }
}

<#==================================================#>

<#
    Install/Import prerequisite features and modules used by the deployment script
#>
function SetupHostPrerequisites() {
    $util.Log('Info', 'Checking feature requirements...')
    foreach ($name in $script:requiredFeatures) {
        $feature = Get-WindowsFeature -Name $name
        if ($null -eq $feature) {
            $util.Log('Critical', "Feature '$name' is not available on this system.")
        }
        elseif ($name.Installed) {
            $util.Log('Debug', "Feature '$name' is installed.")
        }
        else {
            $util.Log('Debug', "Feature '$name' is available but not installed. Installing...")

            try {
                Install-WindowsFeature -Name $name -IncludeManagementTools
                $util.Log('Debug', "Feature '$name' installed successfully.")
            }
            catch {
                $util.Log('Critical', "Feature '$name' failed to import.")
                $util.Log('Error', $_)
                exit 1
            }
        }
    }

    $util.Log('Info', 'Checking module requirements...')
    foreach ($name in $script:requiredModules) {
        if (-not (Get-Module -Name $name)) {
            $util.Log('Debug', "Module '$name' is not imported. Importing...")
            try {
                Import-Module $name -ErrorAction Stop
                $util.Log('Debug', "Module '$name' imported successfully.")
            }
            catch {
                $util.Log('Critical', "Module '$name' failed to import.")
                $util.Log('Error', $_)
                exit 1
            }
        }
        else {
            $util.Log('Debug', "Module '$name' is imported.")
        }
    }
}

<#
    Configure backup/restore targets from $BackupFiles list
#>
function ConfigureBackupRestore() {
    $script:backupTargets = New-Object System.Collections.Generic.List[Hashtable]
    foreach ($filename in $BackupFiles) {
        $util.Log('Debug', "Adding backup/restore target. ($filename)")
        $script:backupTargets.Add(
            [Hashtable]@{
                filename     = $filename
                relativePath = $null
            }
        )
    }
}

<#
    Lookup App Pool and:
    - If exists: Stop App Pool
    - Not exists: Create App Pool
#>
function CheckAndCreateAppPool() {
    $util.Log('Info', "Checking '$script:appName' App Pool...")
    # Use Get-IISServerManager to retrieve the Application Pool
    $script:appPool = $script:serverManager.ApplicationPools[$script:appPoolName]
    if ($null -eq $script:appPool) {
        $util.Log('Warning', 'App Pool missing. Creating...')
        try {
            # Create a new Application Pool
            $appPool = $script:serverManager.ApplicationPools.Add($script:appPoolName)

            # Set properties
            $appPool.ManagedRuntimeVersion = 'v4.0' # .NET Framework 4.x
            $appPool.AutoStart = $true

            # Configure recycling
            $appPool.Recycling.PeriodicRestart.Time = [TimeSpan]::Parse('00:00:00') # Time of day
            $appPool.Recycling.PeriodicRestart.Schedule.Clear() # Remove any default schedule
            $appPool.Recycling.PeriodicRestart.Schedule.Add([TimeSpan]::Parse('22:00:00')) # Schedule for recycling

            # Commit changes
            $script:serverManager.CommitChanges()

            $util.Log('Info', "App Pool created. ($script:appPoolName)")
            $script:appPool = $script:serverManager.ApplicationPools[$script:appPoolName]
        }
        catch {
            Write-Error $_
        }
    }
    else {
        $util.Log('Info', "App Pool exists. ($script:appPoolName)")
    }
    
    if ($null -ne $script:appPool) {
        do {
            if ($script:appPool.State -eq 'Started') {
                $util.Log('Warning', 'App Pool running. Stopping...')
                Stop-WebAppPool -Name $script:appPoolName
        
                # Wait until the app pool is stopped
                for ($script:retryCount = 0; $script:retryCount -lt $script:maxRetries; $script:retryCount++) {
                    Start-Sleep -Seconds $script:retryDelay
                    $appPoolState = Get-WebAppPoolState $script:appPoolName
        
                    if ($script:appPool.State -eq 'Stopped') {
                        $util.Log('Info', 'App Pool stopped.')
                        break
                    }
                    else {
                        $util.Log('Debug', "Waiting for App Pool to stop. Current state: $($appPoolState.Value)")
                    }
                }
        
                if ($script:retryCount -eq $script:maxRetries) {
                    $util.Log('Error', "Failed to stop App Pool after $script:maxRetries attempts.")
                }
                break
            }
            elseif ($script:appPool.State -eq 'Stopped') {
                $util.Log('Info', 'App Pool stopped.')
                break
            }
            else {
                $util.Log('Debug', "App Pool transitioning. Retry in $script:retryDelay seconds...")
                Start-Sleep -Seconds $script:retryDelay
                $script:retryCount++
            }
        
        } while ($script:retryCount -lt $script:maxRetries)
        
        if ($script:retryCount -eq $script:maxRetries) {
            $util.Log('Error', "Failed to transition App Pool out of the transitional state after $script:maxRetries attempts.")
        }
    }
}

<#
    Lookup previous deployment and:
    - If exists: Locate and Backup appsettings.json
#>
function CheckExistingDeployment() {
    $util.Log('Info', 'Checking existing deployments...')
    if (Test-Path $script:targetDir) {
        $util.Log('Debug', "Checking target path ($script:targetDir)")
        $targetsToRemove = @()
        foreach ($target in $script:backupTargets) {
            $result = $script:util.GetRelativePath($script:targetDir, $target.filename)
            if ($null -ne $result) {
                $util.Log('Info', "Backing up ($($target.filename))...")
                $target.file = $result.file
                $target.relativePath = $result.relativePath

                # Handle multiple relativePath values
                foreach ($relativePath in $result.relativePath) {
                    # Calculate the backup directory
                    $backupPath = $script:backupDir
                    if ($null -ne $relativePath) {
                        $backupPath = Join-Path -Path $script:backupDir -ChildPath (Split-Path -Path $relativePath -Parent)
                        New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
                    }
                    # Copy the file to the correct directory
                    $destinationFile = Join-Path -Path $backupPath -ChildPath $target.filename
                    Copy-Item -Path $result.file.FullName -Destination $destinationFile -Force
                    if (Test-Path $destinationFile) {
                        $util.Log('Info', "Saved successfully. ($destinationFile).")
                    }
                }
            }
            else {
                # Mark the target for removal
                $targetsToRemove += $target
            }
        }
        foreach ($target in $targetsToRemove) {
            $util.Log('Debug', "Removing backup/restore target. ($($target.filename))")
            $script:backupTargets.Remove($target) | Out-Null
        }
    }
    else {
        $util.Log('Info', 'No deployments found.')
    }
}

<#
    Clear $script:targetDir
    Transfer files from $script:sourceDir to $script:targetDir
#>
function DeployLatestArtifact() {
    $util.Log('Debug', 'Clearing deployment target directory...')
    Remove-Item -Recurse -Force $script:targetDir -ErrorAction SilentlyContinue
    $util.Log('Debug', 'Cleared target directory.')
    $util.Log('Info', 'Deploying latest artifact...')
    # Extract the filenames from backupTargets where a backup was successful
    $fileBackups = $script:backupTargets | Where-Object { $null -ne $_.file } | ForEach-Object { $_.filename }
    # If target directory doesn't exist, create and check it was created
    if (!(Test-Path $script:targetDir)) {
        $util.Log('Debug', 'Creating target directory...')
        New-Item -ItemType Directory -Path $script:targetDir -Force | Out-Null
        if (Test-Path $script:targetDir) {
            $util.Log('Debug', "Directory created successfully. ($($script:targetDir))")
        }
        else {
            $util.Log('Critical', "Directory not created. ($($script:targetDir))")
            exit 1
        }
    }
    # Copy items from source directory, excluding any files with backups
    $itemsToCopy = Get-ChildItem -Path $script:sourceDir -Recurse | Where-Object { $fileBackups -notcontains $_.Name }
    foreach ($item in $itemsToCopy) {
        $relativePath = $item.FullName.Substring($script:sourceDir.Length).TrimStart('\')
        $destinationPath = Join-Path -Path $script:targetDir -ChildPath $relativePath
        if ($item.PSIsContainer) {
            # If item is a directory, create it and check it was created
            $util.Log('Debug', "Creating directory ($($item.Name))...")
            $util.Log('Debug', "Source: ($($item.FullName))")
            $util.Log('Debug', "Target: ($($destinationPath))")
            New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
            if (Test-Path $destinationPath) {
                $util.Log('Debug', "Directory created successfully.")
            } else {
                $util.Log('Critical', "Directory not created. ($($destinationPath))")
                exit 1
            }
        } else {
            # If item is a file, copy it and check it was created
            $util.Log('Info', "Copying ($($item.Name))...")
            $util.Log('Debug', "Source: ($($item.FullName))")
            $util.Log('Debug', "Target: ($destinationPath)")
            Copy-Item -Path $item.FullName -Destination $destinationPath -Force
            if (Test-Path $destinationPath) {
                $util.Log('Info', "Copied successfully.")
            } else {
                $util.Log('Critical', "File not copied. ($(item.FullName))")
                exit 1
            }
        }
    }
    $util.Log('Info', 'Copied files from artifact.')
}

<#
    Restore backups
#>
function RestoreBackups() {
    $hasFileBackups = $script:backupTargets | Where-Object { $null -ne $_.file } | ForEach-Object { $true } | Select-Object -First 1
    $hasFileBackups = [bool]$hasFileBackups
    if ($hasFileBackups) {
        $util.Log('Info', 'Restoring backups...')
        foreach ($target in $script:backupTargets) {
            foreach ($path in $target.relativePath) {
                $util.Log('Info', "Restoring ($($path))...")
                $source = "$script:backupDir\$path"
                $util.Log('Debug', "Backup: ($source)")
                $target = "$script:targetDir\$path"
                Copy-Item -Path $source -Destination $target -Force
                if (Test-Path $target) {
                    $util.Log('Info', "Restored successfully. ($target).")
                }
            }
        }
    }
}

<#
    Set-up the application on the default website, or website specified in $SiteRoot
#>
function SetupWebApplication() {
    $util.Log('Info', 'Checking applications...')
    $site = $script:serverManager.Sites[$script:siteRoot]
    $util.Log('Debug', "Located target site. ($script:siteRoot)")
    
    $existingApp = $site.Applications | Where-Object { $_.Path -eq $script:appPath }
    if ($null -eq $existingApp) {
        $util.Log('Warning', 'Application missing. Creating...')

        # Add the new application to the site
        $newApp = $site.Applications.Add($script:appPath, $script:targetDir)

        # Set the application pool for the new app
        $newApp.ApplicationPoolName = $script:appPoolName

        # Commit the changes
        $script:serverManager.CommitChanges() | Out-Null

        # Check the app was created
        $createdApp = $site.Applications | Where-Object { $_.Path -eq $script:appPath }
        if ($null -eq $existingApp) {
            $util.Log('Info', "Application created. ($($createdApp.Path)).")
        }
        else {
            $util.Log('Critical', 'Application not created.')
            exit 1
        }
    }
    else {
        $util.Log('Info', "Application already exists. ($($existingApp.Path)).")
    }
}

<#
    Start the app pool, wait for it to start
#>
function StartAppPool() {
    $util.Log('Info', 'Starting App Pool...')
    do {
        if ($script:appPool.State -eq 'Stopped') {
            Start-WebAppPool -Name $script:appPoolName
        
            # Wait until the app pool is started
            for ($script:retryCount = 0; $script:retryCount -lt $script:maxRetries; $script:retryCount++) {
                Start-Sleep -Seconds $script:retryDelay
                $appPoolState = Get-WebAppPoolState $script:appPoolName
        
                if ($script:appPool.State -eq 'Started') {
                    $util.Log('Info', 'App Pool started.')
                    break
                }
                else {
                    $util.Log('Debug', "Waiting for App Pool to start. Current state: $($appPoolState.Value)")
                }
            }
        
            if ($script:retryCount -eq $script:maxRetries) {
                $util.Log('Error', "Failed to start App Pool after $script:maxRetries attempts.")
            }
            break
        }
        elseif ($script:appPool.State -eq 'Started') {
            $util.Log('Info', 'App Pool started.')
            break
        }
        else {
            $util.Log('Debug', "App Pool transitioning. Retry in $script:retryDelay seconds...")
            Start-Sleep -Seconds $script:retryDelay
            $script:retryCount++
        }
    } while ($script:retryCount -lt $script:maxRetries)
        
    if ($script:retryCount -eq $script:maxRetries) {
        $util.Log('Error', "Failed to transition App Pool out of the transitional state after $script:maxRetries attempts.")
    }
}

<#==================================================#>

$util = [Util]::new($script:logFile) # Create an instance of the Util class
SetupHostPrerequisites # Check required features and modules are available and install/import
ConfigureBackupRestore # Set the backup/restore targets for the deployment
$script:serverManager = Get-IISServerManager # Initialize script-scoped serverManager variable
CheckAndCreateAppPool # Create if missing, stop the app pool
CheckExistingDeployment # Lookup previous deployment and backup appsettings
DeployLatestArtifact # Copy latest artifact files from source
RestoreBackups # Restore any files that were backed up during deployment
SetupWebApplication # Create web application and map paths
StartAppPool # Start up the app pool
Write-Host "Deployment run completed. Full log file can be found at $script:logFile."
