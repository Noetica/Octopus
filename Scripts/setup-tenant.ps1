<#
.SYNOPSIS
    Configures the NATS tenant name in synthesys.inf as part of an Octopus deployment.

.DESCRIPTION
    Calls Write-NatsTenantConfig.ps1 to write the NatsTenant value into the
    [SynthesysSwitch] section of synthesys.inf using the Octopus variable
    'Noetica.NatsTenantName'.

    The INF file path is read from the Octopus variable 'Noetica.Inf' unless
    overridden with -InfPath.

.PARAMETER InfPath
    Path to synthesys.inf. Defaults to the Octopus variable 'Noetica.Inf'.

.PARAMETER WhatIf
    Shows what would be written without making any changes.

.EXAMPLE
    .\setup-nats-tenant.ps1
    Writes NatsTenant into synthesys.inf using Octopus variable values.

.EXAMPLE
    .\setup-nats-tenant.ps1 -InfPath "C:\Synthesys\synthesys.inf" -WhatIf
    Shows what would be written without making any changes.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    # Standard Octopus deployment step parameters - accepted but not used by this script
    [Parameter(Mandatory = $false)] [string]$AppName,
    [Parameter(Mandatory = $false)] [string]$SourceDir,
    [Parameter(Mandatory = $false)] [string]$TargetDir,
    [Parameter(Mandatory = $false)] [string[]]$FileExclusions,

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
