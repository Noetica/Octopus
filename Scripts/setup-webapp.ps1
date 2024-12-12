param (
    [Parameter(Mandatory = $true)] [string]$ApplicationName, # Name of the artifact (versionless) or display name, e.g. ReportsAPI
    [Parameter(Mandatory = $true)] [string]$SourceDir, # Location of the source artifact to be deployed
    [Parameter(Mandatory = $false)] [string]$SiteRoot = 'Synthesys_General', # Location of the site deployment
    [Parameter(Mandatory = $true)] [string]$TargetDir # Location of the target deployment directory
)

<#==================================================#>

# Map params to script-scoped variables
$script:timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
$script:sourceDir = $SourceDir
$script:targetDir = $TargetDir
$script:appName = $ApplicationName
$script:appPath = "/$script:appName"

# Prerequisites to check before deployment
$script:requiredFeatures = @('Web-Scripting-Tools')
$script:requiredModules = @('IISAdministration', 'WebAdministration')

# App & App Pool variables
$script:appPool = $null
$script:siteName = $SiteRoot
$script:appPoolName = "$($script:siteName)_$($script:appName)"
$script:retryCount = 0
$script:maxRetries = 5
$script:retryDelay = 5 # seconds

# Backup/Restore variables
$script:backupDir = "$env:TEMP\$($script:appName)_$($script:timestamp)"
$script:appSettings = 'appsettings.json'
$script:configRelativeBackup = $null
$script:restoreAppSettings = $false

# Deployment appsettings path
$script:configRelativeTarget = $null

<#==================================================#>

<#
    Install/Import prerequisite features and modules used by the deployment script
#>
function SetupHostPrerequisites() {
    Write-Host 'Checking feature requirements...'
    foreach ($name in $script:requiredFeatures) {
        $feature = Get-WindowsFeature -Name $name
        if ($null -eq $feature) {
            Write-Host " [X] Feature '$name' is not available on this system." -ForegroundColor Red
        }
        elseif ($name.Installed) {
            Write-Host " [✓] Feature '$name' is installed." -ForegroundColor Green
        }
        else {
            Write-Host " [!] Feature '$name' is available but not installed. Installing..." -ForegroundColor Yellow
            Install-WindowsFeature -Name $name -IncludeManagementTools
            Write-Host " [✓] Feature '$name' installed successfully." -ForegroundColor Green
        }
    }

    Write-Host 'Checking module requirements...'
    foreach ($name in $script:requiredModules) {
        if (-not (Get-Module -Name $name)) {
            Write-Host " [!] Module '$name' is not imported. Importing..." -ForegroundColor Yellow
            try {
                Import-Module $name -ErrorAction Stop
                Write-Host " [✓] Module '$name' imported successfully." -ForegroundColor Green
            }
            catch {
                Write-Host " [X] Module '$name' failed to import." -ForegroundColor Red
                Write-Error $_
            }
        }
        else {
            Write-Host " [✓] Module '$name' is imported." -ForegroundColor Green
        }
    }
}

<#
    Lookup App Pool and:
    - If exists: Stop App Pool
    - Not exists: Create App Pool
#>
function CheckAndCreateAppPool() {
    Write-Host "Checking '$script:appName' App Pool..."
    # Use Get-IISServerManager to retrieve the Application Pool
    $script:appPool = $script:serverManager.ApplicationPools[$script:appPoolName]
    if ($null -eq $script:appPool) {
        Write-Host ' [!] App Pool missing. Creating...' -ForegroundColor Yellow
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

            Write-Host " [✓] App Pool created. ($script:appPoolName)" -ForegroundColor Green
            $script:appPool = $script:serverManager.ApplicationPools[$script:appPoolName]
        }
        catch {
            Write-Error $_
        }
    }
    else {
        Write-Host " [✓] App Pool exists. ($script:appPoolName)" -ForegroundColor Green
    }
    
    if ($null -ne $script:appPool) {
        do {
            if ($script:appPool.State -eq 'Started') {
                Write-Host ' [!] App Pool running. Stopping...' -ForegroundColor Yellow
                Stop-WebAppPool -Name $script:appPoolName
        
                # Wait until the app pool is stopped
                for ($script:retryCount = 0; $script:retryCount -lt $script:maxRetries; $script:retryCount++) {
                    Start-Sleep -Seconds $script:retryDelay
                    $appPoolState = Get-WebAppPoolState $script:appPoolName
        
                    if ($script:appPool.State -eq 'Stopped') {
                        Write-Host ' [✓] App Pool stopped.' -ForegroundColor Green
                        break
                    }
                    else {
                        Write-Host "Waiting for App Pool to stop. Current state: $($appPoolState.Value)"
                    }
                }
        
                if ($script:retryCount -eq $script:maxRetries) {
                    Write-Host " [X] Failed to stop App Pool after $script:maxRetries attempts." -ForegroundColor Red
                }
                break
            }
            elseif ($script:appPool.State -eq 'Stopped') {
                Write-Host ' [✓] App Pool stopped.' -ForegroundColor Green
                break
            }
            else {
                Write-Host " [!] App Pool transitioning. Retry in $script:retryDelay seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds $script:retryDelay
                $script:retryCount++
            }
        
        } while ($script:retryCount -lt $script:maxRetries)
        
        if ($script:retryCount -eq $script:maxRetries) {
            Write-Host " [X] Failed to transition App Pool out of the transitional state after $script:maxRetries attempts." -ForegroundColor Red
        }
    }
}

<#
    Lookup previous deployment and:
    - If exists: Locate and Backup appsettings.json
#>
function CheckExistingDeployment() {
    Write-Host 'Checking existing deployments...'
    if (Test-Path $script:targetDir) {
        $targetAppSettings = UtilLocateAppsettings -lookupDir $script:targetDir
        if ($null -ne $targetAppSettings.file) {
            Write-Host " [!] Existing deployment found. Saving configuration ($($targetAppSettings.relativePath))..." -ForegroundColor Yellow
            if ($targetAppSettings.relativePath.Contains('\')) {
                $script:configRelativeBackup = Split-Path $targetAppSettings.relativePath -Parent
            }
            # Create directory
            (New-Item -Path $script:backupDir -ItemType Directory -Force) | Out-Null
            # Backup
            Copy-Item -Path $targetAppSettings.file.FullName -Destination "$script:backupDir\$script:appSettings" -Force
            if (Test-Path "$script:backupDir\$script:appSettings") {
                Write-Host " [✓] Saved successfully. ($script:backupDir\$script:appSettings)." -ForegroundColor Green
                $script:restoreAppSettings = $true
            }
        }
        else {
            Write-Host ' No configuration found.'
        }
    }
    else {
        Write-Host ' No deployments found.'
    }
}

<#
    Clear $script:targetDir
    Transfer files from $script:sourceDir to $script:targetDir
#>
function DeployLatestArtifact() {
    Write-Host 'Clearing deployment target directory...'
    Remove-Item -Recurse -Force $script:targetDir -ErrorAction SilentlyContinue
    Write-Host ' [✓] Cleared target directory.' -ForegroundColor Green
    Write-Host 'Deploying latest artifact...'
    Copy-Item -Path $script:sourceDir -Destination $script:targetDir -Recurse -Exclude 'appsettings.json'
    Write-Host ' [✓] Copied files from artifact.' -ForegroundColor Green
}

<#
    Copy/Restore appsettings
    - If appsettings was backed-up: Restore to original location
    - If appsettings was not backed-up: Transfer from $script:sourceDir
#>
function DeployConfiguration() {
    if ($script:restoreAppSettings) {
        Write-Host 'Restoring configuration from backup...'
        if ($script:configRelativeBackup) {
            (New-Item -Path "$script:targetDir\$script:configRelativeBackup" -ItemType Directory -Force) | Out-Null
            Copy-Item -Path "$script:backupDir\$script:appSettings" -Destination "$script:targetDir\$script:configRelativeBackup\$script:appSettings"
            Write-Host " [✓] Restored to relative path. ($script:targetDir\$script:configRelativeBackup\$script:appSettings)." -ForegroundColor Green
        }
        else {
            Copy-Item -Path "$script:backupDir\$script:appSettings" -Destination "$script:targetDir\$script:appSettings"
            Write-Host " [✓] Restored to root. ($script:targetDir\$script:appSettings)." -ForegroundColor Green
        }
    }
    else {
        Write-Host 'Copying configuration from artifact...'
        $sourceAppSettings = UtilLocateAppsettings -lookupDir $script:sourceDir
        if ($null -ne $sourceAppSettings.file) {
            if ($sourceAppSettings.relativePath.Contains('\')) {
                $script:configRelativeTarget = Split-Path $sourceAppSettings.relativePath -Parent
            }

            if ($script:configRelativeTarget) {
                (New-Item -Path "$script:targetDir\$script:configRelativeTarget" -ItemType Directory -Force) | Out-Null
                Copy-Item -Path "$script:sourceDir\$script:configRelativeTarget\$script:appSettings" -Destination "$script:targetDir\$script:configRelativeTarget\$script:appSettings"
                Write-Host " [✓] Copied to relative path. ($script:targetDir\$script:configRelativeTarget\$script:appSettings)." -ForegroundColor Green
            }
            else {
                Write-Host " [✓] Copied to root. ($script:targetDir\$script:appSettings)." -ForegroundColor Green
                Copy-Item -Path "$script:sourceDir\$script:appSettings" -Destination "$script:targetDir\$script:appSettings"
            }
        }
        else {
            Write-Host ' [X] No configuration found.' -ForegroundColor Red
        }
    }
}

<#
    Set-up the application on the default website, or website specified in $SiteRoot
#>
function SetupWebApplication() {
    Write-Host 'Checking applications...'
    $site = $script:serverManager.Sites[$script:siteName]
    Write-Host " [✓] Located target site. ($script:siteName)" -ForegroundColor Green
    
    $existingApp = $site.Applications | Where-Object { $_.Path -eq $script:appPath }
    if ($null -eq $existingApp) {
        Write-Host ' [!] Application missing. Creating...' -ForegroundColor Yellow

        # Add the new application to the site
        $newApp = $site.Applications.Add($script:appPath, $script:targetDir)

        # Set the application pool for the new app
        $newApp.ApplicationPoolName = $script:appPoolName

        # Commit the changes
        $script:serverManager.CommitChanges() | Out-Null

        # Check the app was created
        $createdApp = $site.Applications | Where-Object { $_.Path -eq $script:appPath }
        if ($null -eq $existingApp) {
            Write-Host " [✓] Application created. ($($createdApp.Path))." -ForegroundColor Green
        }
        else {
            Write-Host ' [X] Application not created.' -ForegroundColor Red
        }
    }
    else {
        Write-Host " [✓] Application already exists. ($($existingApp.Path))." -ForegroundColor Green
    }
}

<#
    Start the app pool, wait for it to start
#>
function StartAppPool() {
    Write-Host 'Starting App Pool...'
    do {
        if ($script:appPool.State -eq 'Stopped') {
            Start-WebAppPool -Name $script:appPoolName
        
            # Wait until the app pool is started
            for ($script:retryCount = 0; $script:retryCount -lt $script:maxRetries; $script:retryCount++) {
                Start-Sleep -Seconds $script:retryDelay
                $appPoolState = Get-WebAppPoolState $script:appPoolName
        
                if ($script:appPool.State -eq 'Started') {
                    Write-Host ' [✓] App Pool started.' -ForegroundColor Green
                    break
                }
                else {
                    Write-Host "Waiting for App Pool to start. Current state: $($appPoolState.Value)"
                }
            }
        
            if ($script:retryCount -eq $script:maxRetries) {
                Write-Host " [X] Failed to start App Pool after $script:maxRetries attempts." -ForegroundColor Red
            }
            break
        }
        elseif ($script:appPool.State -eq 'Started') {
            Write-Host ' [✓] App Pool started.' -ForegroundColor Green
            break
        }
        else {
            Write-Host " [!] App Pool transitioning. Retry in $script:retryDelay seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds $script:retryDelay
            $script:retryCount++
        }
    } while ($script:retryCount -lt $script:maxRetries)
        
    if ($script:retryCount -eq $script:maxRetries) {
        Write-Host " [X] Failed to transition App Pool out of the transitional state after $script:maxRetries attempts." -ForegroundColor Red
    }
}

<#
    [util] shared function
    Locate appsettings in a specified directory and output the file, and the relative path
#>
function UtilLocateAppsettings() {
    param ([string]$lookupDir)
    $match = @{
        file         = $null 
        relativePath = $null
    }
    Write-Host " Searching $lookupDir..."
    if (Test-Path $lookupDir) {
        $match.file = Get-ChildItem -Path $lookupDir -Recurse -File -Filter $script:appSettings
        if ($match.file) {
            # Check if the appsettings is nested
            $match.relativePath = $($match.file.FullName.Substring($lookupDir.Length).TrimStart('\'))
            Write-Host " [✓] Located configuration. ($($match.relativePath))" -ForegroundColor Green
        }
        else {
            Write-Host " Unable to locate file ($script:appSettings)."
        }
    }
    else {
        Write-Host " Unable to locate directory ($lookupDir)."
    }
    return $match
}

<#==================================================#>

<# Run the deployment step functions #>

SetupHostPrerequisites # Check required features and modules are available and install/import
$script:serverManager = Get-IISServerManager # Initialize script-scoped serverManager variable
CheckAndCreateAppPool # Create if missing, stop the app pool
CheckExistingDeployment # Lookup previous deployment and backup appsettings
DeployLatestArtifact # Copy latest artifact files from source
DeployConfiguration # Restore appsettings or copy from source
SetupWebApplication # Create web application and map paths
StartAppPool # Start up the app pool
