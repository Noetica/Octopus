<#
.SYNOPSIS
    Configures the startup type of services for a service set.
.DESCRIPTION
    This module defines two functions:
      - Set-ServiceEnabled: Sets each service's startup type to delayed-auto using:
            sc config "$service" start= delayed-auto
      - Set-ServiceDisabled: Sets each service's startup type to disabled using:
            sc config "$service" start= disabled
    After applying the change, each function verifies the configuration in parallel by calling
    "sc qc" repeatedly until the expected startup configuration is confirmed or a timeout occurs.
.NOTES
    These commands require administrative privileges.
#>

function Set-ServiceEnabled {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Services
    )

    foreach ($service in $Services) {
        Write-Output "Enabling configuration for service: $service"
        sc config "$service" start= delayed-auto
    }

    Write-Output "Verifying that services are configured for delayed-auto start..."
    $Services | ForEach-Object -Parallel {
        # Use $_ directly to capture the current service name.
        $svcName = $_
        $maxAttempts = 10
        $attempt = 0
        do {
            $output = sc qc $svcName | Out-String
            # Adjust the regex if necessary based on the actual output.
            if ($output -match "(?i)START_TYPE\s+:\s+\d+\s+.*delayed") {
                Write-Output "$svcName is configured for delayed-auto start."
                break
            }
            Start-Sleep -Seconds 1
            $attempt++
        } while ($attempt -lt $maxAttempts)
        if ($attempt -ge $maxAttempts) {
            Write-Output "Timeout waiting for $svcName to be configured as delayed-auto."
        }
    } -ThrottleLimit 5
}

function Set-ServiceDisabled {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Services
    )

    foreach ($service in $Services) {
        Write-Output "Disabling configuration for service: $service"
        sc config "$service" start= disabled
    }

    Write-Output "Verifying that services are configured as disabled..."
    $Services | ForEach-Object -Parallel {
        $svcName = $_
        $maxAttempts = 10
        $attempt = 0
        do {
            $output = sc qc $svcName | Out-String
            # Adjust the regex if the actual output uses a different keyword for disabled.
            if ($output -match "(?i)START_TYPE\s+:\s+\d+\s+DISABLED") {
                Write-Output "$svcName is configured as disabled."
                break
            }
            Start-Sleep -Seconds 1
            $attempt++
        } while ($attempt -lt $maxAttempts)
        if ($attempt -ge $maxAttempts) {
            Write-Output "Timeout waiting for $svcName to be configured as disabled."
        }
    } -ThrottleLimit 5
}
