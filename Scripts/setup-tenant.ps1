<#
.SYNOPSIS
    Configures the NATS tenant name in synthesys.inf.

.DESCRIPTION
    Calls Write-TenantConfig.ps1 to write the TenantName value into the
    [System] section of synthesys.inf.
    When run inside Octopus the value is read from the variable 'TenantName'.
    When run standalone, supply -TenantName directly.

    The INF file path defaults to the Octopus variable 'Noetica.Inf' or can be
    supplied via -InfPath.

.PARAMETER TenantName
    The tenant name to write (e.g. 'contoso').
    If omitted, the value is read from the Octopus variable 'TenantName'.

.PARAMETER InfPath
    Path to synthesys.inf. Defaults to the Octopus variable 'Noetica.Inf'.

.PARAMETER WhatIf
    Shows what would be written without making any changes.

.EXAMPLE
    .\setup-tenant.ps1 -TenantName 'my-tenant' -InfPath 'C:\Synthesys\synthesys.inf'
    Writes TenantName into synthesys.inf [System]::TenantName using the supplied tenant name.

.EXAMPLE
    .\setup-tenant.ps1 -InfPath 'C:\Synthesys\synthesys.inf' -WhatIf
    Shows what would be written without making any changes.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantName,

    [Parameter(Mandatory = $false)]
    [string]$InfPath
)

Write-Output "The script is running from: $PSScriptRoot"

$writeTenantConfigScript = Join-Path $PSScriptRoot 'Runbooks\Write-TenantConfig.ps1'

if (-not (Test-Path $writeTenantConfigScript)) {
    Write-Error "Could not find Write-TenantConfig.ps1 at: $writeTenantConfigScript"
    exit 1
}

# Resolve InfPath: prefer explicit param, fall back to Octopus variable.
if ([string]::IsNullOrWhiteSpace($InfPath)) {
    $InfPath = $OctopusParameters['Noetica.Inf']
}

if ([string]::IsNullOrWhiteSpace($InfPath)) {
    Write-Error 'InfPath was not supplied and Octopus variable Noetica.Inf is not set.'
    exit 1
}

# Resolve TenantName: prefer explicit param, fall back to Octopus variable.
if ([string]::IsNullOrWhiteSpace($TenantName)) {
    $TenantName = $OctopusParameters['TenantName']
}

if ([string]::IsNullOrWhiteSpace($TenantName)) {
    Write-Error 'TenantName was not supplied and Octopus variable TenantName is not set.'
    exit 1
}

$params = @{
    TenantName = $TenantName
    InfPath    = $InfPath
}

Write-Host "Configuring tenant name in synthesys.inf..."
& $writeTenantConfigScript @params
