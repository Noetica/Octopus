<#
.SYNOPSIS
    Configures Windows Update Active Hours to prevent automatic restarts during working hours.

.DESCRIPTION
    Sets the Windows Update Active Hours window so that Windows will not automatically
    restart the machine to apply updates between the specified start and end times.
    Updates will still download and install in the background; only the forced restart
    is deferred until outside the active hours window.

    Must be run as Administrator.

.PARAMETER StartHour
    The hour (0-23) at which Active Hours begin. Default is 8 (8 AM).

.PARAMETER EndHour
    The hour (0-23) at which Active Hours end. Default is 17 (5 PM).

.PARAMETER DisableSmartActiveHours
    If set, disables Smart Active Hours, which would otherwise let Windows automatically
    adjust the active hours window based on usage patterns (and potentially override your settings).
    Defaults to $true.

.EXAMPLE
    .\Set-WindowsUpdateActiveHours.ps1
    Sets active hours to 8 AM - 5 PM (default).

.EXAMPLE
    .\Set-WindowsUpdateActiveHours.ps1 -StartHour 7 -EndHour 19
    Sets active hours to 7 AM - 7 PM.

.NOTES
    - Requires Administrator privileges.
    - No reboot required for the change to take effect.
    - Windows Update Active Hours supports a maximum window of 18 hours.
    - This sets the local machine setting. If your machine is domain-joined and
      Group Policy manages Windows Update, a GPO may override this setting.
#>

[CmdletBinding()]
param (
    [ValidateRange(0, 23)]
    [int]$StartHour = 8,

    [ValidateRange(0, 23)]
    [int]$EndHour = 17,

    [bool]$DisableSmartActiveHours = $true
)

# --- Validate window size (max 18 hours) ---
$windowSize = if ($EndHour -gt $StartHour) { $EndHour - $StartHour } else { (24 - $StartHour) + $EndHour }
if ($windowSize -gt 18) {
    Write-Error "Active Hours window cannot exceed 18 hours. Specified window is $windowSize hours ($StartHour to $EndHour)."
    exit 1
}

# --- Require Administrator ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

$regPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

# --- Ensure the registry key exists (create it if absent, e.g. on a fresh OS install) ---
if (-not (Test-Path $regPath)) {
    Write-Host "Registry key not found - creating: $regPath"
    try {
        New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "Failed to create registry key '$regPath': $($_.Exception.Message)"
        exit 1
    }
}

Write-Host "Setting Windows Update Active Hours..."
Write-Host "  Start : $StartHour:00 ($([datetime]::Today.AddHours($StartHour).ToString('h tt')))"
Write-Host "  End   : $EndHour:00 ($([datetime]::Today.AddHours($EndHour).ToString('h tt')))"
Write-Host "  Window: $windowSize hours"

try {
    Set-ItemProperty -Path $regPath -Name "ActiveHoursStart" -Value $StartHour -Type DWord -ErrorAction Stop
    Set-ItemProperty -Path $regPath -Name "ActiveHoursEnd"   -Value $EndHour   -Type DWord -ErrorAction Stop

    if ($DisableSmartActiveHours) {
        Write-Host "  Smart Active Hours: Disabled (Windows will not auto-adjust the window)"
        Set-ItemProperty -Path $regPath -Name "SmartActiveHoursSuggestionState" -Value 0 -Type DWord -ErrorAction Stop
    }
}
catch {
    Write-Error "Failed to write registry values to '$regPath': $($_.Exception.Message)"
    Write-Error "Ensure the script is running as Administrator and the key is not protected by policy."
    exit 1
}

Write-Host ""
Write-Host "Done. Windows will not auto-restart for updates between $([datetime]::Today.AddHours($StartHour).ToString('h tt')) and $([datetime]::Today.AddHours($EndHour).ToString('h tt'))." -ForegroundColor Green
Write-Host "No reboot required for this change to take effect." -ForegroundColor Green

Write-Host ""
Write-Host "--- Current Registry Values ---"
Get-ItemProperty -Path $regPath | Select-Object ActiveHoursStart, ActiveHoursEnd, SmartActiveHoursSuggestionState | Format-List
