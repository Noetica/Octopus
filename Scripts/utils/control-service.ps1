$scriptPath = $PSScriptRoot
. "$scriptPath\utils\file-logger.ps1"

$script:controlPanel = 'HKLM:\SOFTWARE\Noetica\Synthesys\Services\ControlPanel'
$script:serviceManager = 'HKLM:\SOFTWARE\Noetica\Synthesys\Services\ServicesManager'
$script:logger = File-Logger 

<#
    -- Usage examples --
    1. Start a service
    Start-Service -targets $script:appName -OR-
    Use-ControlService -targets $script:appName -operation 'Start'

    2. Stop a service
    Stop-Service -targets $script:appName -OR-
    Use-ControlService -targets $script:appName -operation 'Stop'

    3. Reload service configuration
    Update-ServiceConfig -OR-
    Use-ControlService -operation 'Reload'
#>

function Resolve-Targets {
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

function Update-TargetStatus {
    param (
        [Parameter(Mandatory = $true)] [PSCustomObject[]]$targets
    )

    $timeoutSeconds = 30
    $checkInterval = 3

    foreach ($target in $targets) {
        # Check status first, start operation if applicable
        # Retry every $checkInterval seconds until maximum of $timeoutSeconds
        # $checkInterval can be reduced, it will just log the same items multiple times
        while (-not (Assert-TargetStatus -target $target)) {
            $script:logger.Log('Info', ("{0} {1}...`n" -f $operation, $target.Name))
            $startTime = Get-Date
            $execute = '{0}:{1}' -f $operation, $target.UUID

            # Wait for the previous request key to be actioned, don't overwrite it
            while ($((Get-ItemProperty -Path $script:controlPanel).PSObject.Properties.Name -contains 'Request')) {
                $script:logger.Log('Debug', 'Waiting for previous request to clear...')
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

function Assert-TargetStatus {
    param (
        [Parameter(Mandatory = $true)] [PSCustomObject]$target
    )


    # Get the item from registry again to check the status
    $check = Get-ItemProperty -Path $script:serviceManager |
        ForEach-Object { $_.PSObject.Properties } |
            Where-Object { $_.Value -like "$($target.Name)*" }

            # Split the value string, select first and last items (name, status)
    $script:logger.Log('Info', "Checking target - $($check.Value.Split(',')[0..-1] | ConvertTo-Json -Compress)")

    if ($check) {
        # Dump the check
        $script:logger.Log('Info', "Checking target - $check")
        $status = $check.Value.Split(',')[-1]
        return ($operation -eq 'Start' -and $status -eq 'Running') -or ($operation -eq 'Stop' -and $status -eq 'Stopped')
    }
    return $false
}

<#
    Start/Stop application using Services Manager request mechanism
#>
function Use-ControlService {
    param (
        [ValidateSet('Start', 'Stop', 'Reload')]
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
        $matched = Resolve-Targets -targets $targets
        if ($matched) {
            Update-TargetStatus -targets $matched
            $result = Resolve-Targets -targets $targets
        }
        else {
            $script:logger.Log('Warn', 'No matching targets found.')
        }
    }
    $result | Format-Table Status, Name
}

function Start-Service {
    param (
        [Parameter(Mandatory = $false)] [string[]]$targets
    )
    Use-ControlService -targets $targets -operation 'Start'
}

function Stop-Service {
    param (
        [Parameter(Mandatory = $false)] [string[]]$targets
    )
    Use-ControlService -targets $targets -operation 'Stop'
}

function Update-ServiceConfig {
    Use-ControlService -operation 'Reload'
}
