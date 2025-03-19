<#
.SYNOPSIS
    Verifies that services have reached the expected status in parallel.
.DESCRIPTION
    Checks each service (using Get-Service) until its status matches the expected state,
    or times out after a set number of attempts.
#>
function Assert-ServiceStatus {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Services,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedStatus
    )

    $Services | ForEach-Object -Parallel {
        $service = $_
        $maxAttempts = 30
        $attempt = 0
        do {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq $using:ExpectedStatus) {
                Write-Output "$service is $using:ExpectedStatus"
                break
            }
            Start-Sleep -Seconds 1
            $attempt++
        } while ($attempt -lt $maxAttempts)
        if ($attempt -ge $maxAttempts) {
            Write-Output "Timeout waiting for $service to be $using:ExpectedStatus"
        }
    } -ThrottleLimit 5
}
