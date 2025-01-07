param (
    [Parameter(Mandatory = $true)] [string]$AppName, # Name of the artifact (versionless) or display name, e.g. ReportsAPI
    [Parameter(Mandatory = $true)] [string]$SourceDir, # Location of the source artifact to be deployed
    [Parameter(Mandatory = $true)] [string]$TargetDir, # Location of the target deployment directory
    [Parameter(Mandatory = $true)] [string]$DefaultPort, # Port mapping for the project
    [Parameter(Mandatory = $false)] [string[]]$FileExclusions, # Files to ignore when deploying
    [Parameter(Mandatory = $false)] [string[]]$Output # Specify a custom location for the log output
)

<#==================================================#>

# Backup/Restore variables
$script:backupDir = "$env:TentacleHome" + '\Logs\' + "$($script:appName)_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
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
        Write-Host $message
        # Write to log file
        try {
            Add-Content -Path $this.LogFile -Value $logItem
        }
        catch {
            Write-Host "Failed to write to log file: $_" -ForegroundColor Red
        }
    }
}

<#==================================================#>

<#
    Start/Stop application using Services Manager request mechanism
#>
function ControlService {
    param (
        [string]$operation
    )
    $util.Log('Info', "Requesting $script:appName state: '$operation'...")
    if ([string]::IsNullOrEmpty($target)) {
        New-ItemProperty -Path 'HKLM:\Software\Noetica\Synthesys\Services\ControlPanel' -Name 'Request' -Value "${operation}" 
    }
    else {
        $applications = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Noetica\Synthesys\Services\ServicesManager'
        foreach ($object_properties in $applications.PsObject.Properties) {
            $matched = $object_properties.Value -Match $target
            if ($matched) {
                $name = $object_properties.Name
                New-ItemProperty -Path 'HKLM:\Software\Noetica\Synthesys\Services\ControlPanel' -Name 'Request' -Value "${operation}:${name}" 
            }
        }
    }
}

function DeployLatestArtifact() {
    param (
        [string]$exclusions
    )
    if (-not (Test-Path -Path $script:targetDir)) {
        $util.Log('Debug', 'Creating target directory...')
        New-Item -ItemType Directory -Path $script:targetDir
        if (Test-Path $script:targetDir) {
            $util.Log('Debug', "Directory created successfully. ($script:targetDir)")
        }
        else {
            $util.Log('Critical', "Directory not created. ($script:targetDir)")
            exit 1
        }
    }
    else {
        $util.Log('Debug', 'Clearing deployment target directory...')
        $totalToDeleteCount = 0
        $deletedFileCount = 0
        $errorList = @() # Initialize an array to collect errors

        Get-ChildItem -Path $script:targetDir -Recurse -Force | 
            Where-Object { $_.FullName -notin ($exclusions | ForEach-Object { Join-Path $script:targetDir $_ }) } |
                ForEach-Object {
                    $totalToDeleteCount++
                    try {
                        Remove-Item -Path $_.FullName -Force -Recurse
                        $util.Log('Debug', "Deleted successfully. ($($_.FullName))")
                        $deletedFileCount++
                    }
                    catch {
                        # Collect errors instead of exiting
                        $errorList += "Not deleted. $($_.FullName) - $_"
                        $util.Log('Critical', "Not deleted. ($($_.FullName))")
                    }
                }
        $util.Log('Debug', "Cleared $deletedFileCount of $totalToDeleteCount")

        # After the loop, if there are errors, output them and exit with code 1
        if ($errorList.Count -gt 0) {
            $util.Log('Debug', 'Error(s) occurred during deletion:')
            $errorList | ForEach-Object { $util.Log('Critical', $_) }
            exit 1
        }
    }

    $totalToCopyCount = 0
    $copiedFileCount = 0
    $util.Log('Info', 'Deploying latest artifact...')
    # Copy items from source directory, unless marked as exclusion
    $itemsToCopy = Get-ChildItem -Path $script:sourceDir -Recurse | Where-Object { $FileExclusions -notcontains $_.Name }
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
                $util.Log('Debug', 'Directory created successfully.')
            }
            else {
                $util.Log('Critical', "Directory not created. ($($destinationPath))")
                exit 1
            }
        }
        else {
            $totalToCopyCount++
            # If item is a file, copy it and check it was created
            $util.Log('Info', "Copying ($($item.Name))...")
            $util.Log('Debug', "Source: ($($item.FullName))")
            $util.Log('Debug', "Target: ($destinationPath)")
            Copy-Item -Path $item.FullName -Destination $destinationPath -Force
            if (Test-Path $destinationPath) {
                $util.Log('Info', 'Copied successfully.')
                $copiedFileCount++
            }
            else {
                $util.Log('Critical', "File not copied. ($(item.FullName))")
                exit 1
            }
        }
    }
    $util.Log('Debug', "Copied $copiedFileCount of $totalToCopyCount")
}

function CreateStartupScript() {
    param (
        [string]$target = $script:appName,
        [string]$port = $script:defaultPort
    )
    $util.Log('Info', 'Creating startup script...')
    $appRootFragment = $OctopusParameters['Noetica.AppRoot.Fragment']
    $serverBin = $OctopusParameters['Noetica.ServerBinRoot']
    $filename = "$serverBin\Start$target.bat"
    $content = @"
cd "\$appRootFragment\$target"
start "$target" dotnet $target.dll --urls "http://+:$port"
"@
    Set-Content -Path $filename -Value $content
    $util.Log('Debug', "Target: ($filename)")
    $util.Log('Debug', "Content:`n$content")
    if (Test-Path -Path $filename) {
        $util.Log('Info', 'Created successfully.')
    }
    else {
        $this.Log('Warn', "Script not created. ($filename)")
    }
}

$util = [Util]::new($script:logFile) # Create an instance of the Util class
ControlService -operation 'Stop'
DeployLatestArtifact -exclusions $FileExclusions
CreateStartupScript
ControlService -operation 'Start'
Write-Host "Deployment run completed. Full log file can be found at $script:logFile."
