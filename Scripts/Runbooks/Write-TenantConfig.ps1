<#
.SYNOPSIS
    Writes the NatsTenant value to synthesys.inf from an Octopus variable.

.DESCRIPTION
    Updates the NatsTenant key in the [SynthesysSwitch] section of synthesys.inf
    using the value from the Octopus variable 'Noetica.NatsTenantName'.

    The INF file path is read from the Octopus variable 'Noetica.Inf'.

    This script is a thin wrapper around Write-OctopusVariablesToInf.ps1.

.PARAMETER TenantName
    The tenant name to write. If omitted, the value is read from the Octopus
    variable 'Noetica.NatsTenantName'.

.PARAMETER InfPath
    Path to synthesys.inf. Defaults to the Octopus variable 'Noetica.Inf'.

.PARAMETER WhatIf
    Shows what would be written without making any changes.

.EXAMPLE
    .\Write-TenantConfig.ps1 -TenantName 'my-tenant'
    Writes NatsTenant using the supplied value into the INF file specified by Noetica.Inf.

.EXAMPLE
    .\Write-TenantConfig.ps1 -InfPath "C:\Synthesys\synthesys.inf" -WhatIf
    Shows what would be written without making any changes.

.NOTES
    If TenantName is not supplied, requires the Octopus variable 'Noetica.NatsTenantName'.
    The [SynthesysSwitch] section will be created automatically if it does not
    already exist in the INF file.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantName,

    [Parameter(Mandatory = $false)]
    [string]$InfPath
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$writeInfScript = Join-Path $scriptRoot 'Write-OctopusVariablesToInf.ps1'

if (-not (Test-Path $writeInfScript)) {
    Write-Error "Could not find Write-OctopusVariablesToInf.ps1 at: $writeInfScript"
    exit 1
}

# If TenantName was passed directly (e.g. via #{Tenant.Tenant} in Octopus), inject it
# into $OctopusParameters so the core engine picks it up via the standard mapping.
if (-not [string]::IsNullOrWhiteSpace($TenantName)) {
    $OctopusParameters['Noetica.NatsTenantName'] = $TenantName
}

$mappings = @(
    'SynthesysSwitch|NatsTenant|Noetica.NatsTenantName'
)

$params = @{
    Mappings               = $mappings
    CreateMissingSections  = $true
}

if (-not [string]::IsNullOrWhiteSpace($InfPath)) {
    $params['InfPath'] = $InfPath
}

if ($WhatIfPreference) {
    $params['WhatIf'] = $true
}

Write-Host "Writing NatsTenant to synthesys.inf from Octopus variable 'Noetica.NatsTenantName'..."

& $writeInfScript @params
