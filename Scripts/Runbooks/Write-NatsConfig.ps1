<#
.SYNOPSIS
    Writes the NatsUrl value to synthesys.inf from an Octopus variable.

.DESCRIPTION
    Updates the NatsUrl key in the [SynthesysSwitch] section of synthesys.inf
    using the value from the Octopus variable 'Noetica.NatsServerUrl'.

    The INF file path is read from the Octopus variable 'Noetica.Inf'.

    This script is a thin wrapper around Write-OctopusVariablesToInf.ps1.

.PARAMETER InfPath
    Path to synthesys.inf. Defaults to the Octopus variable 'Noetica.Inf'.

.PARAMETER WhatIf
    Shows what would be written without making any changes.

.EXAMPLE
    .\Write-NatsConfig.ps1
    Writes NatsUrl from the Octopus Noetica.NatsServerUrl variable into
    the INF file specified by Noetica.Inf.

.EXAMPLE
    .\Write-NatsConfig.ps1 -InfPath "C:\Synthesys\synthesys.inf" -WhatIf
    Shows what would be written without making any changes.

.NOTES
    Requires the Octopus variable 'Noetica.NatsServerUrl' to be defined.
    The [SynthesysSwitch] section must exist in the INF file, or use
    -CreateMissingSections if it may be absent.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$InfPath
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$writeInfScript = Join-Path $scriptRoot 'Write-OctopusVariablesToInf.ps1'

if (-not (Test-Path $writeInfScript)) {
    Write-Error "Could not find Write-OctopusVariablesToInf.ps1 at: $writeInfScript"
    exit 1
}

$mappings = @(
    'SynthesysSwitch|NatsUrl|Noetica.NatsServerUrl'
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

Write-Host "Writing NatsUrl to synthesys.inf from Octopus variable 'Noetica.NatsServerUrl'..."

& $writeInfScript @params
