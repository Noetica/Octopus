<#
.SYNOPSIS
    Configures the NATS server URL in synthesys.inf.

.DESCRIPTION
    Calls Write-NatsConfig.ps1 to write the NatsUrl value into the
    [System] section of synthesys.inf.
    When run inside Octopus the value is read from the variable 'Noetica.NatsServerUrl'.
    When run standalone, supply -NatsUrl directly.

    The INF file path defaults to the Octopus variable 'Noetica.Inf' or can be
    supplied via -InfPath.

.PARAMETER NatsUrl
    The NATS server URL to write (e.g. 'nats://myserver:4222').
    If omitted, the value is read from the Octopus variable 'Noetica.NatsServerUrl'.

.PARAMETER InfPath
    Path to synthesys.inf. Defaults to the Octopus variable 'Noetica.Inf'.

.PARAMETER WhatIf
    Shows what would be written without making any changes.

.EXAMPLE
    .\setup-nats.ps1 -NatsUrl 'nats://myserver:4222' -InfPath 'C:\Synthesys\synthesys.inf'
    Writes NatsUrl into synthesys.inf [System]::NatsUrl using the supplied value.

.EXAMPLE
    .\setup-nats.ps1 -InfPath 'C:\Synthesys\synthesys.inf' -WhatIf
    Shows what would be written without making any changes.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$NatsUrl,

    [Parameter(Mandatory = $false)]
    [string]$InfPath
)

Write-Output "The script is running from: $PSScriptRoot"

$writeNatsScript = Join-Path $PSScriptRoot 'Runbooks\Write-NatsConfig.ps1'

if (-not (Test-Path $writeNatsScript)) {
    Write-Error "Could not find Write-NatsConfig.ps1 at: $writeNatsScript"
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

# Resolve NatsUrl: prefer explicit param, fall back to Octopus variable.
if ([string]::IsNullOrWhiteSpace($NatsUrl)) {
    $NatsUrl = $OctopusParameters['Noetica.NatsServerUrl']
}

if ([string]::IsNullOrWhiteSpace($NatsUrl)) {
    Write-Error 'NatsUrl was not supplied and Octopus variable Noetica.NatsServerUrl is not set.'
    exit 1
}

$params = @{
    NatsUrl = $NatsUrl
    InfPath = $InfPath
}

Write-Host "Configuring NATS settings in synthesys.inf..."
& $writeNatsScript @params
