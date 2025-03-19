<#
.SYNOPSIS
    Main script to manage service operations.
.DESCRIPTION
    Depending on the provided parameters, this script will either start or stop a set
    of services (as defined in scm-servicesets.ps1) and verify in parallel that each service
    reaches the expected state.
    If using Use-SCM function directly, see the Target and Operation parameters below.
    Alternatively, Start-*, Stop-*, Enable-*, and Disable-* helper functions can be called.
    e.g. Start-All, Start-Synthesys, Start-VoicePlatform, etc.
.PARAMETER Target
    The service set to act upon. Valid options: "All", "Synthesys", "VoicePlatform".
    Default value if parameter is omitted: "All".
.PARAMETER Operation
    The operation to perform. Valid options: "Start", "Stop", "Enable", "Disable".
    Default value if parameter is omitted: "Start".
#>

function Use-SCM {
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("All", "Synthesys", "VoicePlatform")]
        [string]$Target = "All",

        [Parameter(Mandatory = $false)]
        [ValidateSet("Start", "Stop", "Enable", "Disable")]
        [string]$Operation = "Start"
    )

    # Import modules via dot sourcing.
    $script:scriptPath = $PSScriptRoot
    . "$script:scriptPath\scm-servicesets.ps1"   # ServiceSets: All, Synthesys, VoicePlatform
    . "$script:scriptPath\scm-servicestart.ps1"  # Function(s): Start-Services
    . "$script:scriptPath\scm-servicestop.ps1"   # Function(s): Stop-Services
    . "$script:scriptPath\scm-servicestatus.ps1" # Function(s): Assert-ServiceStatus
    . "$script:scriptPath\scm-serviceconfig.ps1" # Function(s): Set-ServiceEnabled, Set-ServiceDisabled

    # Get the list of services for the specified target.
    $services = $ServiceSets[$Target]

    if (-not $services -or $services.Count -eq 0) {
        Write-Error "No services defined for target '$Target'."
        exit 1
    }
    # Maximum number of retries if verification times out.
    $maxRetries = 3

    switch ($Operation) {
        "Start" {
            $retryCount = 0
            do {
                Write-Output "Starting services for target '$Target' (attempt $($retryCount+1))..."
                Start-Services -Services $services

                Write-Output "Verifying that services are running..."
                # Capture the output of the verification.
                $verifyOutput = Assert-ServiceStatus -Services $services -ExpectedStatus "Running"

                if ($verifyOutput -match "Timeout waiting for") {
                    Write-Output "One or more services did not reach 'Running' state. Retrying..."
                    $retryCount++
                } else {
                    Write-Output "All services are running."
                    break
                }
            } while ($retryCount -lt $maxRetries)

            if ($retryCount -eq $maxRetries) {
                Write-Error "Start operation failed after $maxRetries attempts."
            }
        }
        "Stop" {
            $retryCount = 0
            do {
                Write-Output "Stopping services for target '$Target' (attempt $($retryCount+1))..."
                Stop-Services -Services $services

                Write-Output "Verifying that services are stopped..."
                # Capture the output of the verification.
                $verifyOutput = Assert-ServiceStatus -Services $services -ExpectedStatus "Stopped"

                if ($verifyOutput -match "Timeout waiting for") {
                    Write-Output "One or more services did not reach 'Stopped' state. Retrying..."
                    $retryCount++
                } else {
                    Write-Output "All services are stopped."
                    break
                }
            } while ($retryCount -lt $maxRetries)

            if ($retryCount -eq $maxRetries) {
                Write-Error "Stop operation failed after $maxRetries attempts."
            }
        }
        "Enable" {
            Write-Output "Enabling services for target '$Target'..."
            Set-ServiceEnabled -Services $services
        }
        "Disable" {
            Write-Output "Disabling services for target '$Target'..."
            Set-ServiceDisabled -Services $services
        }
        default {
            Write-Error "Invalid operation: $Operation"
            exit 1
        }
    }
}

function Start-All {
    Use-SCM -target 'All' -operation 'Start'
}
function Start-Synthesys {
    Use-SCM -target 'Synthesys' -operation 'Start'
}
function Start-VoicePlatform {
    Use-SCM -target 'VoicePlatform' -operation 'Start'
}

function Stop-All {
    Use-SCM -target 'All' -operation 'Stop'
}
function Stop-Synthesys {
    Use-SCM -target 'Synthesys' -operation 'Stop'
}
function Stop-VoicePlatform {
    Use-SCM -target 'VoicePlatform' -operation 'Stop'
}

function Enable-All {
    Use-SCM -target 'All' -operation 'Enable'
}
function Enable-Synthesys {
    Use-SCM -target 'Synthesys' -operation 'Enable'
}
function Enable-VoicePlatform {
    Use-SCM -target 'VoicePlatform' -operation 'Enable'
}

function Disable-All {
    Use-SCM -target 'All' -operation 'Disable'
}
function Disable-Synthesys {
    Use-SCM -target 'Synthesys' -operation 'Disable'
}
function Disable-VoicePlatform {
    Use-SCM -target 'VoicePlatform' -operation 'Disable'
}
