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
        try {
            $service = $Services[$i]
            Write-Output "Stopping service: $service"
            net stop "$service" 2>$null
        }
        catch {
            # Don't want to Write-Error to avoid stopping the script.
            # Instead, Write-Host to display the error message.
            Write-Host $_ 
        }
    }
}
