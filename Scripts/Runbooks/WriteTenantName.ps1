<#
.SYNOPSIS
    Writes the TenantName registry entry from an Octopus variable.

.DESCRIPTION
    Creates or updates the TenantName registry value at HKLM:\SOFTWARE\Noetica\Synthesys
    using the value from the Octopus variable 'Tenant.Tenant'.

.PARAMETER TenantName
    The tenant name value to write. Defaults to the Octopus variable $OctopusParameters['Tenant.Tenant'].

.PARAMETER WhatIf
    Shows what would be written without making any changes.

.EXAMPLE
    .\WriteTenantName.ps1
    Writes the TenantName from the Octopus Tenant.Tenant variable.

.EXAMPLE
    .\WriteTenantName.ps1 -TenantName "MyTenant"
    Writes "MyTenant" as the TenantName registry value.

.NOTES
    Requires administrative privileges for writing to HKEY_LOCAL_MACHINE.
    Run PowerShell as Administrator when modifying machine-level registry keys.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantName
)

$RegistryPath = "HKLM:\SOFTWARE\Noetica\Synthesys"
$RegistryName = "TenantName"

# Get the tenant name from Octopus variable if not provided as parameter
if (-not $TenantName) {
    if ($OctopusParameters -and $OctopusParameters['Tenant.Tenant']) {
        $TenantName = $OctopusParameters['Tenant.Tenant']
        Write-Host "Using Octopus variable Tenant.Tenant: $TenantName"
    }
    else {
        Write-Error "TenantName not provided and Octopus variable 'Tenant.Tenant' is not available."
        exit 1
    }
}

# Ensure the registry path exists
if (-not (Test-Path $RegistryPath)) {
    if ($PSCmdlet.ShouldProcess($RegistryPath, "Create registry key")) {
        Write-Host "Creating registry path: $RegistryPath"
        New-Item -Path $RegistryPath -Force | Out-Null
    }
}

# Write the registry value
if ($PSCmdlet.ShouldProcess("$RegistryPath\$RegistryName", "Set registry value to '$TenantName'")) {
    Write-Host "Writing registry value:"
    Write-Host "  Path:  $RegistryPath"
    Write-Host "  Name:  $RegistryName"
    Write-Host "  Value: $TenantName"
    
    Set-ItemProperty -Path $RegistryPath -Name $RegistryName -Value $TenantName -Type String
    
    Write-Host "Registry value written successfully." -ForegroundColor Green
}

# Verify the value was written
if (-not $WhatIfPreference) {
    $verifyValue = Get-ItemProperty -Path $RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue
    if ($verifyValue) {
        Write-Host "Verified: $RegistryName = $($verifyValue.$RegistryName)" -ForegroundColor Cyan
    }
}
