<#
.SYNOPSIS
    Sets up the standard SIP trunk registry groups required on NUB development machines.

.DESCRIPTION
    NUB-1893: Ensures that each of the required SIP trunk groups exist under
    HKEY_LOCAL_MACHINE\SOFTWARE\Noetica\Voice Platform.

    Three trunks are required on every dev machine:
        1. GroupNexbridgeCall    - Default (no prefix) Nexbridge outbound trunk.
        2. Group00321Teft        - TEFT calls trunk (dial prefix 321).
        3. GroupInternal         - NVP loopback / internal routing.

    The script checks which of these registry subkeys are already present on the
    target machine. Any that are absent are created directly via PowerShell registry
    cmdlets. All registry values are defined inline in this script - no external
    .reg files are required, so the script can be run standalone.

    Existing keys are NEVER overwritten - the script is additive only.

    The VoicePlatform service is stopped before applying changes and restarted
    afterwards. If the service is not installed (e.g. on a fresh machine) the
    service control step is skipped automatically.

.PARAMETER WhatIf
    Reports which groups are missing and what would be imported without making
    any changes.

.EXAMPLE
    .\setup-devmachinesiptrunks.ps1
    Checks and applies any missing SIP trunk groups, restarting VoicePlatform.

.EXAMPLE
    .\setup-devmachinesiptrunks.ps1 -WhatIf
    Shows which groups are missing without making changes.

.NOTES
    Requires administrative privileges (writes to HKEY_LOCAL_MACHINE).
    Run PowerShell as Administrator.
    Source of truth: exported from the reference dev machine on 2026-03-16 (NUB-1893).
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# ---------------------------------------------------------------------------
# SIP trunk group definitions
# All registry values are defined inline - no external .reg files required.
# Source of truth: exported from the reference dev machine on 2026-03-16 (NUB-1893).
# ---------------------------------------------------------------------------
$sipTrunks = @(
    [PSCustomObject]@{
        Name        = 'GroupNexbridgeCall'
        Description = 'Default Nexbridge outbound trunk (no prefix, pattern .*)'
        Values      = @(
            @{ Name = 'Pattern';           Value = '.*';                                Type = 'String'      }
            @{ Name = 'DestinationFormat'; Value = 'sip:{0}@195.35.112.77';             Type = 'String'      }
            @{ Name = 'TotalChannels';     Value = 30;                                  Type = 'DWord'       }
            @{ Name = 'ExtraParameters';   Value = @('sipProxy=sip:10.200.8.5');        Type = 'MultiString' }
            @{ Name = 'OriginatingFormat'; Value = 'sip:+442079406700@195.35.112.77';   Type = 'String'      }
        )
    },
    [PSCustomObject]@{
        Name        = 'Group00321Teft'
        Description = 'TEFT calls trunk (dial prefix 321)'
        Values      = @(
            @{ Name = 'Pattern';           Value = '^321';                                                                                                       Type = 'String'      }
            @{ Name = 'DestinationFormat'; Value = 'sip:{0}@pip-kamailio-telephony-testing-swedencentral.swedencentral.cloudapp.azure.com:5061;transport=tls';  Type = 'String'      }
            @{ Name = 'TotalChannels';     Value = 30;                                                                                                           Type = 'DWord'       }
            @{ Name = 'StripPrefixes';     Value = @('321');                                                                                                     Type = 'MultiString' }
            @{ Name = 'ExtraParameters';   Value = @('sipProxy=sip:10.200.8.5');                                                                                 Type = 'MultiString' }
            @{ Name = 'OriginatingFormat'; Value = 'sip:+442079406700@195.35.112.77';                                                                            Type = 'String'      }
            @{ Name = 'CLIToPresent';      Value = '442079406700';                                                                                               Type = 'String'      }
            @{ Name = 'CustomSIPHeaders';  Value = @('X-Noetica-Teft=letmein', 'X-Noetica-Convert-SRTP=1');                                                     Type = 'MultiString' }
        )
    },
    [PSCustomObject]@{
        Name        = 'GroupInternal'
        Description = 'NVP loopback / internal routing (Enhanced SIP Port, inbound)'
        Values      = @(
            @{ Name = 'Pattern';           Value = '^2';                                          Type = 'String'      }
            @{ Name = 'DestinationFormat'; Value = 'sip:{0}@10.200.0.8';                          Type = 'String'      }
            @{ Name = 'OriginatingFormat'; Value = '"Anonymous" <sip:anonymous@anonymous.invalid>'; Type = 'String'   }
            @{ Name = 'TotalChannels';     Value = 5000;                                          Type = 'DWord'       }
            @{ Name = 'Ports';             Value = @('Enhanced SIP Port');                        Type = 'MultiString' }
            @{ Name = 'StripPrefixes';     Value = @('2');                                        Type = 'MultiString' }
            @{ Name = 'CLIToPresent';      Value = '';                                            Type = 'String'      }
        )
    }
)

$baseKeyPath  = 'HKLM:\SOFTWARE\Noetica\Voice Platform'
$newline      = [System.Environment]::NewLine

# ---------------------------------------------------------------------------
# Validate that the base Voice Platform key exists
# ---------------------------------------------------------------------------
if (-not (Test-Path $baseKeyPath)) {
    Write-Error "Base registry key not found: $baseKeyPath"
    Write-Error "Is the Noetica Voice Platform installed on this machine?"
    exit 1
}

# ---------------------------------------------------------------------------
# Check presence of each group
# ---------------------------------------------------------------------------
Write-Output "${newline}=== NUB-1893: Dev Machine SIP Trunk Setup ==="
Write-Output "Checking SIP trunk registry groups under:"
Write-Output "  $($baseKeyPath -replace 'HKLM:\\', 'HKEY_LOCAL_MACHINE\')$newline"

$missingTrunks  = [System.Collections.Generic.List[PSCustomObject]]::new()
$presentTrunks  = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($trunk in $sipTrunks) {
    $keyPath = Join-Path $baseKeyPath $trunk.Name
    if (Test-Path $keyPath) {
        Write-Output "  [OK]      $($trunk.Name)"
        Write-Output "            $($trunk.Description)"
        $presentTrunks.Add($trunk)
    }
    else {
        Write-Output "  [MISSING] $($trunk.Name)"
        Write-Output "            $($trunk.Description)"
        $missingTrunks.Add($trunk)
    }
}

Write-Output ""
Write-Output "Present : $($presentTrunks.Count) / $($sipTrunks.Count)"
Write-Output "Missing : $($missingTrunks.Count) / $($sipTrunks.Count)"

if ($missingTrunks.Count -eq 0) {
    Write-Output "${newline}All SIP trunk groups are already configured. No changes needed."
    exit 0
}

# ---------------------------------------------------------------------------
# Service control helpers
# ---------------------------------------------------------------------------
$utilsPath     = Join-Path $PSScriptRoot '..\..\utils'
$scmScriptPath = Join-Path $utilsPath 'control-scm.ps1'
$hasScm        = Test-Path $scmScriptPath

function Stop-VoicePlatformIfRunning {
    $svc = Get-Service -Name 'VoicePlatform' -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Output "VoicePlatform service not found - skipping stop."
        return
    }
    if ($svc.Status -eq 'Stopped') {
        Write-Output "VoicePlatform service is already stopped."
        return
    }
    if ($hasScm) {
        . $scmScriptPath
        Write-Output "Stopping VoicePlatform service..."
        Use-SCM -target 'VoicePlatform' -operation 'Stop'
    }
    else {
        Write-Output "Stopping VoicePlatform service (direct)..."
        Stop-Service -Name 'VoicePlatform' -Force -ErrorAction Stop
        Write-Output "VoicePlatform service stopped."
    }
}

function Start-VoicePlatformIfStopped {
    $svc = Get-Service -Name 'VoicePlatform' -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Output "VoicePlatform service not found - skipping start."
        return
    }
    if ($svc.Status -eq 'Running') {
        Write-Output "VoicePlatform service is already running."
        return
    }
    if ($hasScm) {
        . $scmScriptPath
        Write-Output "Starting VoicePlatform service..."
        Use-SCM -target 'VoicePlatform' -operation 'Start'
    }
    else {
        Write-Output "Starting VoicePlatform service (direct)..."
        Start-Service -Name 'VoicePlatform' -ErrorAction Stop
        Write-Output "VoicePlatform service started."
    }
}

# ---------------------------------------------------------------------------
# Apply missing groups
# ---------------------------------------------------------------------------

# Capture initial service state BEFORE stopping so we can restore it faithfully.
# If the service was already stopped before this script ran, we must not start it
# on the way out - that would silently change the machine's prior state.
$vpSvc = Get-Service -Name 'VoicePlatform' -ErrorAction SilentlyContinue
$vpInitialStatus = if ($vpSvc) { $vpSvc.Status } else { $null }

if ($PSCmdlet.ShouldProcess('VoicePlatform', 'Stop service')) {
    Write-Output "${newline}Stopping VoicePlatform before applying registry changes..."
    Stop-VoicePlatformIfRunning
}

Write-Output "${newline}Creating $($missingTrunks.Count) missing trunk group(s)..."

$succeeded = 0
$failed    = 0

foreach ($trunk in $missingTrunks) {
    $keyPath = Join-Path $baseKeyPath $trunk.Name
    Write-Output "${newline}  Creating: $($trunk.Name)"
    Write-Output "            $($trunk.Description)"

    # Re-check: another process may have created the key between our earlier
    # check and now (rare, but safe to guard against)
    if (Test-Path $keyPath) {
        Write-Output "    Result : Key appeared since initial check - skipping (no overwrite)."
        continue
    }

    try {
        if ($PSCmdlet.ShouldProcess($trunk.Name, 'Create registry key and values')) {
            New-Item -Path $keyPath -Force -ErrorAction Stop | Out-Null
            foreach ($val in $trunk.Values) {
                New-ItemProperty -Path $keyPath -Name $val.Name -Value $val.Value `
                    -PropertyType $val.Type -Force -ErrorAction Stop | Out-Null
            }
            Write-Output "    Result : SUCCESS ($($trunk.Values.Count) values written)"
            $succeeded++
        }
    }
    catch {
        Write-Error "    Result : FAILED - $($_.Exception.Message)"
        $failed++
    }
}

# ---------------------------------------------------------------------------
# Restart service and report
# ---------------------------------------------------------------------------
if ($vpInitialStatus -eq 'Running') {
    if ($PSCmdlet.ShouldProcess('VoicePlatform', 'Start service')) {
        Write-Output "${newline}Restarting VoicePlatform service (it was running before this script ran)..."
        Start-VoicePlatformIfStopped
    }
}
else {
    Write-Output "${newline}VoicePlatform service was not running before this script ran - leaving it stopped."
}

Write-Output "${newline}=== Summary ==="
Write-Output "  Already present : $($presentTrunks.Count)"
Write-Output "  Newly created   : $succeeded"
if ($failed -gt 0) {
    Write-Output "  Failed          : $failed"
    Write-Output "============================================"
    Write-Error "Script completed with $failed error(s). Review output above."
    exit 1
}
Write-Output "============================================"
Write-Output "Script completed successfully."
exit 0
