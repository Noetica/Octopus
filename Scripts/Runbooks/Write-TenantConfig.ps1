<#
.SYNOPSIS
    Writes the TenantName value to synthesys.inf.

.DESCRIPTION
    Updates the TenantName key in the [System] section of synthesys.inf.
    The [System] section will be created automatically if it does not already exist.

    This script delegates INF file writing to Write-OctopusVariablesToInf.ps1.

.PARAMETER TenantName
    The tenant name to write (e.g. 'contoso').

.PARAMETER InfPath
    Path to synthesys.inf.

.EXAMPLE
    .\Write-TenantConfig.ps1 -TenantName 'my-tenant' -InfPath 'C:\Synthesys\synthesys.inf'
    Writes TenantName into synthesys.inf [System]::TenantName.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InfPath
)

$scriptRoot     = Split-Path -Parent $MyInvocation.MyCommand.Path
$writeInfScript = Join-Path $scriptRoot 'Write-OctopusVariablesToInf.ps1'

if (-not (Test-Path $writeInfScript)) {
    Write-Error "Could not find Write-OctopusVariablesToInf.ps1 at: $writeInfScript"
    exit 1
}

# The helper resolves values via $OctopusParameters. Inject the supplied value
# under the key used in the mapping so the helper works without an Octopus context.
$OctopusParameters = @{ 'TenantName' = $TenantName }

$params = @{
    Mappings              = @('System|TenantName|TenantName')
    InfPath               = $InfPath
    CreateMissingSections = $true
}

& $writeInfScript @params
