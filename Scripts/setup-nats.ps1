<#
.SYNOPSIS
    Configures the NATS server URL in synthesys.inf as part of an Octopus deployment.

.DESCRIPTION
    Calls Write-NatsConfig.ps1 to write the NatsUrl value into the
    [SynthesysSwitch] section of synthesys.inf using the Octopus variable
    'Noetica.NatsServerUrl'.

    The INF file path is read from the Octopus variable 'Noetica.Inf' unless
    overridden with -InfPath.

.PARAMETER InfPath
    Path to synthesys.inf. Defaults to the Octopus variable 'Noetica.Inf'.

.PARAMETER WhatIf
    Shows what would be written without making any changes.

.EXAMPLE
    .\setup-nats.ps1
    Writes NatsUrl into synthesys.inf using Octopus variable values.

.EXAMPLE
    .\setup-nats.ps1 -InfPath "C:\Synthesys\synthesys.inf" -WhatIf
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

$writeNatsScript = Join-Path $PSScriptRoot 'Runbooks\Write-NatsConfig.ps1'

if (-not (Test-Path $writeNatsScript)) {
    Write-Error "Could not find Write-NatsConfig.ps1 at: $writeNatsScript"
    exit 1
}

$params = @{}

if (-not [string]::IsNullOrWhiteSpace($InfPath)) {
    $params['InfPath'] = $InfPath
}

if ($WhatIfPreference) {
    $params['WhatIf'] = $true
}

if ($PSCmdlet.ShouldProcess('synthesys.inf', 'Write NatsUrl')) {
    Write-Host "Configuring NATS settings in synthesys.inf..."
    & $writeNatsScript @params
}
