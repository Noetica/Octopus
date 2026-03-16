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
    target machine. Any that are absent are created by importing the corresponding
    .reg file bundled alongside this script.

    Existing keys are NEVER overwritten - the script is additive only.

    The VoicePlatform service is stopped before applying changes and restarted
    afterwards. If the service is not installed (e.g. on a fresh machine) the
    service control step is skipped automatically.

.PARAMETER WhatIf
    Reports which groups are missing and what would be imported without making
    any changes.

.EXAMPLE
    .\Setup-DevMachineSipTrunks.ps1
    Checks and applies any missing SIP trunk groups, restarting VoicePlatform.

.EXAMPLE
    .\Setup-DevMachineSipTrunks.ps1 -WhatIf
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
# Each entry maps a registry subkey name to a .reg file in this folder and
# a human-readable description for reporting.
# ---------------------------------------------------------------------------
$sipTrunks = @(
    [PSCustomObject]@{
        Name        = 'GroupNexbridgeCall'
        RegFile     = Join-Path $PSScriptRoot 'GroupNexbridgeCall.reg'
        Description = 'Default Nexbridge outbound trunk (no prefix, pattern .*)'
    },
    [PSCustomObject]@{
        Name        = 'Group00321Teft'
        RegFile     = Join-Path $PSScriptRoot 'Group00321Teft.reg'
        Description = 'TEFT calls trunk (dial prefix 321)'
    },
    [PSCustomObject]@{
        Name        = 'GroupInternal'
        RegFile     = Join-Path $PSScriptRoot 'GroupInternal.reg'
        Description = 'NVP loopback / internal routing (Enhanced SIP Port, inbound)'
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
# WhatIf mode - report only, no changes
# ---------------------------------------------------------------------------
if ($WhatIfPreference) {
    Write-Output "${newline}========== WhatIf: No changes will be made =========="
    foreach ($trunk in $missingTrunks) {
        Write-Output "  WhatIf: Would import '$($trunk.Name)' from:"
        Write-Output "          $($trunk.RegFile)"
    }
    Write-Output "=========================================================="
    exit 0
}

# ---------------------------------------------------------------------------
# Validate that all required .reg files exist before touching the service
# ---------------------------------------------------------------------------
$missingFiles = $missingTrunks | Where-Object { -not (Test-Path $_.RegFile) }
if ($missingFiles) {
    Write-Error "The following .reg source files are missing from $PSScriptRoot :"
    $missingFiles | ForEach-Object { Write-Error "  $($_.RegFile)" }
    Write-Error "Cannot proceed. Please ensure all .reg files are present alongside this script."
    exit 1
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
Write-Output "${newline}Stopping VoicePlatform before applying registry changes..."
Stop-VoicePlatformIfRunning

Write-Output "${newline}Importing $($missingTrunks.Count) missing trunk group(s)..."

$succeeded = 0
$failed    = 0

foreach ($trunk in $missingTrunks) {
    Write-Output "${newline}  Importing: $($trunk.Name)"
    Write-Output "    File   : $($trunk.RegFile)"

    # Re-check: another process may have created the key between our earlier
    # check and now (rare, but safe to guard against)
    if (Test-Path (Join-Path $baseKeyPath $trunk.Name)) {
        Write-Output "    Result : Key appeared since initial check - skipping (no overwrite)."
        continue
    }

    try {
        $result = reg import $trunk.RegFile 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Output "    Result : SUCCESS"
            $succeeded++
        }
        else {
            Write-Error "    Result : FAILED (exit code $LASTEXITCODE) - $result"
            $failed++
        }
    }
    catch {
        Write-Error "    Result : EXCEPTION - $($_.Exception.Message)"
        $failed++
    }
}

# ---------------------------------------------------------------------------
# Restart service and report
# ---------------------------------------------------------------------------
Write-Output "${newline}Restarting VoicePlatform service..."
Start-VoicePlatformIfStopped

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
