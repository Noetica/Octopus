<#
.SYNOPSIS
    Configures the NATS tenant name in synthesys.inf as part of an Octopus deployment.

.DESCRIPTION
    Calls Write-NatsTenantConfig.ps1 to write the NatsTenant value into the
    [SynthesysSwitch] section of synthesys.inf using the Octopus variable
    'Noetica.NatsTenantName'.

    The INF file path is read from the Octopus variable 'Noetica.Inf' unless
    overridden with -InfPath.

.PARAMETER TenantName
    The tenant name to write. If omitted, the value is read from the Octopus
    variable 'Noetica.NatsTenantName'. In Octopus, set this to '#{Tenant.Tenant}'.

.PARAMETER InfPath
    Path to synthesys.inf. Defaults to the Octopus variable 'Noetica.Inf'.

.PARAMETER WhatIf
    Shows what would be written without making any changes.

.EXAMPLE
    .\setup-tenant.ps1 -TenantName 'my-tenant'
    Writes NatsTenant into synthesys.inf using the supplied tenant name.

.EXAMPLE
    .\setup-tenant.ps1 -InfPath "C:\Synthesys\synthesys.inf" -WhatIf
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

$writeNatsTenantScript = Join-Path $PSScriptRoot 'Runbooks\Write-TenantConfig.ps1'

if (-not (Test-Path $writeNatsTenantScript)) {
    Write-Error "Could not find Write-TenantConfig.ps1 at: $writeNatsTenantScript"
    exit 1
}

$params = @{}

if (-not [string]::IsNullOrWhiteSpace($TenantName)) {
    $params['TenantName'] = $TenantName
}

if (-not [string]::IsNullOrWhiteSpace($InfPath)) {
    $params['InfPath'] = $InfPath
}

if ($WhatIfPreference) {
    $params['WhatIf'] = $true
}

if ($PSCmdlet.ShouldProcess('synthesys.inf', 'Write NatsTenant')) {
    Write-Host "Configuring NATS tenant name in synthesys.inf..."
    & $writeNatsTenantScript @params
}
