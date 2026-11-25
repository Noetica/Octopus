<#
.SYNOPSIS
    Writes the per-site "may speak" value for Live Person Detection to synthesys.inf (ENG-971).

.DESCRIPTION
    Sets [Campaign Manager] LivePersonDetectionPermitted in synthesys.inf from the Octopus tenant
    variable 'LivePersonDetectionPermitted'. The section is created if it does not exist.

    Campaign Manager reads this value to decide whether a site's lists are shown Live Person
    Detection and the settings that need it. Its read fails closed:
        "yes" (case-insensitive, trimmed)                     -> the site may speak; the settings show
        anything else / missing / blank / unreadable           -> the settings stay hidden
    This script therefore writes a single-line value verbatim and lets Campaign Manager interpret it.

    A missing or blank variable is NOT an error: it is logged and nothing is written, so the
    existing INF value remains in effect. To hide the settings again on a site that
    has the value, set the variable to "no"; this script never removes the key.

    Campaign Manager caches synthesys.inf, so restart it after this runbook for the change to apply.

    INF writing is delegated to Write-OctopusVariablesToInf.ps1.

.PARAMETER Permitted
    The value to write. Defaults to the Octopus variable $OctopusParameters['LivePersonDetectionPermitted'].

.PARAMETER InfPath
    Path to synthesys.inf. Defaults to the Octopus variable $OctopusParameters['Noetica.Inf'].

.PARAMETER WhatIf
    Shows what would be written without making any changes.

.EXAMPLE
    .\Write-LivePersonDetectionPermitted.ps1
    Writes the value of the Octopus tenant variable LivePersonDetectionPermitted into the INF named by Noetica.Inf.

.EXAMPLE
    .\Write-LivePersonDetectionPermitted.ps1 -Permitted yes -InfPath 'C:\Synthesys\etc\synthesys.inf'
    Writes [Campaign Manager] LivePersonDetectionPermitted=yes.

.NOTES
    See the ENG-971 spec (nub_specs specs/2026/eng-971-live-person-detection-as-lists-one-switch-covering),
    section 5, and its grill record (implementation question Q1).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$Permitted,

    [Parameter(Mandatory = $false)]
    [string]$InfPath
)

$Section      = 'Campaign Manager'
$Key          = 'LivePersonDetectionPermitted'
$VariableName = 'LivePersonDetectionPermitted'

# Get the value from the Octopus variable if not provided as a parameter.
if (-not $PSBoundParameters.ContainsKey('Permitted')) {
    if ($OctopusParameters -and $OctopusParameters[$VariableName]) {
        $Permitted = $OctopusParameters[$VariableName]
    }
}

# A missing or blank variable leaves the existing INF value in effect.
# Do not fail the deployment over it -- warn and write nothing.
if ([string]::IsNullOrWhiteSpace($Permitted)) {
    Write-Warning "$VariableName is not set (or blank). The existing INF value is unchanged. To disable Live Person Detection, run with 'no' and restart Campaign Manager."
    return
}

if ($Permitted -match '[\r\n]') {
    throw "$VariableName must fit on one INF line."
}

if ([string]::IsNullOrWhiteSpace($InfPath) -and $OctopusParameters -and $OctopusParameters['Noetica.Inf']) {
    $InfPath = $OctopusParameters['Noetica.Inf']
}

if ([string]::IsNullOrWhiteSpace($InfPath)) {
    Write-Error "INF file path not provided. Use -InfPath or set Octopus variable 'Noetica.Inf'."
    exit 1
}

$scriptRoot     = Split-Path -Parent $MyInvocation.MyCommand.Path
$writeInfScript = Join-Path $scriptRoot 'Write-OctopusVariablesToInf.ps1'

if (-not (Test-Path $writeInfScript)) {
    Write-Error "Could not find Write-OctopusVariablesToInf.ps1 at: $writeInfScript"
    exit 1
}

Write-Host "Writing INF value:"
Write-Host "  File:    $InfPath"
Write-Host "  Section: [$Section]"
Write-Host "  Key:     $Key"
Write-Host "  Value:   '$Permitted'"

# The helper resolves values via $OctopusParameters. Inject the value under the key used in the
# mapping so the helper works with or without an Octopus context. -WhatIf reaches the helper
# through $WhatIfPreference.
$OctopusParameters = @{ $VariableName = $Permitted }

$params = @{
    Mappings              = @("$Section|$Key|$VariableName")
    InfPath               = $InfPath
    CreateMissingSections = $true
}

& $writeInfScript @params

# Verify only when a write could have happened this run (not under -WhatIf, which would read back
# and report the old value as if it were just written).
if (-not $WhatIfPreference) {
    $inSection = $false
    $current = $null
    foreach ($line in [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $InfPath).Path)) {
        if ($line -match '^\s*\[(.+)\]\s*$') {
            $inSection = ($matches[1] -eq $Section)
            continue
        }
        if ($inSection -and $line -match ('^\s*' + [regex]::Escape($Key) + '\s*=(.*)$')) {
            $current = $matches[1]
            break
        }
    }
    Write-Host "Verified: [$Section] $Key = '$current'" -ForegroundColor Cyan
    Write-Host "Restart Campaign Manager for the change to apply (it caches synthesys.inf)."
}
