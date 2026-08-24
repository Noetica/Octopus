<#
.SYNOPSIS
    Writes the Partner registry entry from an Octopus variable (deployment-type flag, ENG-317).

.DESCRIPTION
    Creates or updates the Partner registry value at HKLM\SOFTWARE\Noetica\Synthesys
    using the value from the Octopus variable 'Tenant.Branding'.

    Partner is the ENG-317 deployment-type flag consumed by User Management, Dashboard
    and Campaign Manager. Those surfaces normalise the value on read:
        raw?.Trim() equals "talkdesk" (case-insensitive)  -> Talkdesk deployment
        anything else / missing / blank / unreadable       -> standard (noetica) deployment
    This script therefore writes the branding value VERBATIM and lets the readers
    normalise. Normalisation deliberately lives on the read side only (ADR-027).

    The value is written to the NATIVE 64-bit registry view explicitly, because all
    three reader surfaces pin RegistryView.Registry64. Writing via the HKLM: PSDrive
    (as WriteTenantName.ps1 does) only lands in the 64-bit view if the Octopus
    tentacle happens to run as a 64-bit process; pinning removes that dependency.

.PARAMETER Branding
    The branding value to write. Defaults to the Octopus variable $OctopusParameters['Tenant.Branding'].

.PARAMETER WhatIf
    Shows what would be written without making any changes.

.EXAMPLE
    .\WritePartner.ps1
    Writes Partner from the Octopus Tenant.Branding variable.

.EXAMPLE
    .\WritePartner.ps1 -Branding "talkdesk"
    Writes "talkdesk" as the Partner registry value.

.NOTES
    Requires administrative privileges for writing to HKEY_LOCAL_MACHINE.
    A missing/blank branding variable is NOT an error: it is logged and skipped,
    because absence is the intentional fail-open default (readers -> noetica).
    See ENG-317 spec (nub_specs commit 6db4c32) and ADR-027.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$Branding
)

$RegistrySubKey = 'SOFTWARE\Noetica\Synthesys'
$RegistryName   = 'Partner'

# Get the branding value from the Octopus variable if not provided as a parameter.
if (-not $PSBoundParameters.ContainsKey('Branding')) {
    if ($OctopusParameters -and $OctopusParameters['Tenant.Branding']) {
        $Branding = $OctopusParameters['Tenant.Branding']
        Write-Host "Using Octopus variable Tenant.Branding: '$Branding'"
    }
}

# Missing / blank branding is by design safe: readers fail open to 'noetica'.
# Do not fail the deployment over it -- warn and skip so the tenant still deploys.
if ([string]::IsNullOrWhiteSpace($Branding)) {
    Write-Warning "Tenant.Branding is not set (or blank). Skipping Partner write; readers will default to 'noetica' (fail-open)."
    return
}

Write-Host "Writing registry value (native 64-bit view):"
Write-Host "  Key:   HKLM\$RegistrySubKey"
Write-Host "  Name:  $RegistryName"
Write-Host "  Value: '$Branding'"

if ($PSCmdlet.ShouldProcess("HKLM\$RegistrySubKey\$RegistryName", "Set registry value to '$Branding'")) {
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        # CreateSubKey opens the key if it already exists, or creates it if missing.
        $key = $baseKey.CreateSubKey($RegistrySubKey)
        try {
            $key.SetValue($RegistryName, $Branding, [Microsoft.Win32.RegistryValueKind]::String)
            Write-Host "Registry value written successfully." -ForegroundColor Green
        }
        finally { $key.Close() }
    }
    finally { $baseKey.Close() }
}

# Verify the value was written (read back from the same 64-bit view).
if (-not $WhatIfPreference) {
    $verifyBase = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $verifyKey = $verifyBase.OpenSubKey($RegistrySubKey)
        if ($verifyKey) {
            try {
                $written = $verifyKey.GetValue($RegistryName)
                Write-Host "Verified: $RegistryName = '$written'" -ForegroundColor Cyan
            }
            finally { $verifyKey.Close() }
        }
    }
    finally { $verifyBase.Close() }
}
