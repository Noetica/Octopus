<#
.SYNOPSIS
    Starts a list of services in order.
.DESCRIPTION
    Iterates through each service in the provided list and starts it with "net start".
#>
function Start-Services {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Services
    )

    foreach ($service in $Services) {
        Write-Output "Starting service: $service"
        net start "$service"
    }
}
