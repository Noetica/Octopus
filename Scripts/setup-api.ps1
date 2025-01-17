param (
    [Parameter(Mandatory = $true)] [string]$AppName, # Name of the artifact (versionless) or display name, e.g. ReportsAPI
    [Parameter(Mandatory = $true)] [string]$SourceDir, # Location of the source artifact to be deployed
    [Parameter(Mandatory = $true)] [string]$TargetDir, # Location of the target deployment directory
    [Parameter(Mandatory = $false)] [string]$DefaultPort, # Port mapping for the project
    [Parameter(Mandatory = $false)] [string]$StartupScript, # Override startup script for batch file
    [Parameter(Mandatory = $false)] [string[]]$FileExclusions, # Files to ignore when deploying
    [Parameter(Mandatory = $false)] [string[]]$Output # Specify a custom location for the log output
)

<#==================================================#>

# Backup/Restore variables
$script:backupDir = "$env:TentacleHome" + '\Logs\' + "$($script:appName)_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
# Logging: Use override if specified, or default value
$script:logFile = if ($null -ne $Output) { $Output } else { "$($script:backupDir).log" }
# Registry paths
$script:controlPanel = 'HKLM:\SOFTWARE\Noetica\Synthesys\Services\ControlPanel'
$script:serviceManager = 'HKLM:\SOFTWARE\Noetica\Synthesys\Services\ServicesManager'

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

function ValidateTargets() {
    param(
        [Parameter(Mandatory = $true)] [string[]]$targets
    )
    $values = Get-ItemProperty -Path $script:serviceManager | ForEach-Object { $_.PSObject.Properties }

    # Wildcard match targets to existing items, e.g. 'board' -> 'DashboardAPI'.
    $matched = foreach ($target in $targets) {
        $items = $values | Where-Object { $_.Value -like "*$target*" }
        foreach ($item in $items) {
            $props = $item.Value.Split(',')
            # Check item is in format:
            # [0] Name, [1] Description, [2] CommandLine, [3] Priority, [4] Status
            # Only interested in the registry key name, target name, and status
            if ($props.Count -eq 5) {
                [PSCustomObject]@{
                    UUID   = $item.Name
                    Name   = $props[0]
                    Status = $props[4]
                }
            }
        }
    }

    # Filter and sort returned values
    return $matched | Sort-Object -Property Name -Unique
}

function SetTargetStatus() {
    param (
        [Parameter(Mandatory = $true)] [PSCustomObject[]]$targets
    )

    $timeoutSeconds = 30
    $checkInterval = 3

    foreach ($target in $targets) {
        # Check status first, start operation if applicable
        # Retry every $checkInterval seconds until maximum of $timeoutSeconds
        # $checkInterval can be reduced, it will just log the same items multiple times
        while (-not (VerifyTargetStatus($target))) {
            $util.Log('Info', ("{0} {1}...`n" -f $operation, $target.Name))
            $startTime = Get-Date
            $execute = '{0}:{1}' -f $operation, $target.UUID

            # Wait for the previous request key to be actioned, don't overwrite it
            while ($((Get-ItemProperty -Path $script:controlPanel).PSObject.Properties.Name -contains 'Request')) {
                $util.Log('Debug', 'Waiting for previous request to clear...')
                if ((Get-Date) -gt $startTime.AddSeconds($timeoutSeconds)) {
                    throw "Timeout exceeded before request key cleared ($timeoutSeconds seconds)."
                }
                Start-Sleep -Seconds $checkInterval
            }

            # Add next request to registry
            New-ItemProperty -Path "$script:controlPanel" -Name 'Request' -Value "$execute" -Force | Out-Null
            Start-Sleep -Seconds $checkInterval
        }
    }
}

function VerifyTargetStatus() {
    param (
        [Parameter(Mandatory = $true)] [PSCustomObject]$target
    )

    # Get the item from registry again to check the status
    $check = Get-ItemProperty -Path $script:serviceManager |
        ForEach-Object { $_.PSObject.Properties } |
            Where-Object { $_.Value -like "$($target.Name)*" }

    # Split the value string, select first and last items (name, status)
    $util.Log('Info', "Checking target - $($check.Value.Split(',')[0..-1] | ConvertTo-Json -Compress)")

    if ($check) {
        $status = $check.Value.Split(',')[-1]
        return ($operation -eq 'Start' -and $status -eq 'Running') -or ($operation -eq 'Stop' -and $status -eq 'Stopped')
    }
    return $false
}

<#
    Start/Stop application using Services Manager request mechanism
#>
function ControlService {
    param (
        [ValidateSet('Start', 'Stop')]
        [Parameter(Mandatory = $false)] [string]$operation = 'Start', # Default
        [Parameter(Mandatory = $false)] [string[]]$targets
    )
    $result = $null
    # If no targets provided, Start/Stop All
    if ($null -eq $targets) {
        $execute = '{0}All' -f $operation
        New-ItemProperty -Path $script:controlPanel -Name 'Request' -Value $execute
    }
    else {
        # Validate targets (allows partial targets to be provided, e.g. *board* -> 'DasboardAPI')
        # This also allows matching on target Description strings
        # Correct names and current statuses will be returned into $matched
        $matched = ValidateTargets -targets $targets
        if ($matched) {
            SetTargetStatus($matched)
            $result = ValidateTargets -targets $targets
        }
        else {
            $util.Log('Warn', 'No matching targets found.')
        }
    }
    $result | Format-Table Status, Name
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
        $util.Log('Warn', "Script not created. ($filename)")
    }
}

function CreateStartupStartupScript() {
    param (
        [string]$target = $script:appName,
        [string]$startupScript = $script:startupScript
    )
    $util.Log('Info', 'Creating startup startup script...')
    $appRootFragment = $OctopusParameters['Noetica.AppRoot.Fragment']
    $serverBin = $OctopusParameters['Noetica.ServerBinRoot']
    $filename = "$serverBin\Start$target.bat"
    $commandLine = $ExecutionContext.InvokeCommand.ExpandString($startupScript) -f $target
    $content = @"
cd "\$appRootFragment\$target"
$commandline"
"@
 
    Set-Content -Path $filename -Value $content
    $util.Log('Debug', "Target: ($filename)")
    $util.Log('Debug', "Content:`n$content")
    if (Test-Path -Path $filename) {
        $util.Log('Info', 'Created successfully.')
    }
    else {
        $util.Log('Warn', "Script not created. ($filename)")
    }
}

$util = [Util]::new($script:logFile) # Create an instance of the Util class
ControlService -targets $script:appName -operation 'Stop'
DeployLatestArtifact -exclusions $FileExclusions
if (-not [string]::IsNullOrEmpty($DefaultPort)) { CreateStartupScript }
if (-not [string]::IsNullOrEmpty($StartupScript)) { CreateStartupStartupScript}
ControlService -targets $script:appName -operation 'Start'
Write-Host "Deployment run completed. Full log file can be found at $script:logFile."
