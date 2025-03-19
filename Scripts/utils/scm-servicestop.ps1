<#
.SYNOPSIS
    Stops a list of services in reverse order.
.DESCRIPTION
    Iterates backwards through the provided list and stops each service with "net stop".
#>
function Stop-Services {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Services
    )

    # Stop services in reverse order.
    for ($i = $Services.Count - 1; $i -ge 0; $i--) {
        $service = $Services[$i]
        Write-Output "Stopping service: $service"
        net stop "$service"
    }
}
