# This script installs a startup script used to configure the VM
# It creates a scheduled task to run c:\Install\UpdateSIPdotINI.ps1 script at startup
# The script should have been deployed first by Octopus Deploy.
$trigger = New-ScheduledTaskTrigger -AtStartup
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-NoProfile -NonInteractive -WindowStyle Hidden -File "C:\install\UpdateSIPdotINI.ps1"'
$taskName = 'Update NVP sip.ini with local IP'

# Check if the task already exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($null -eq $existingTask) {
    $splat = @{
        TaskName = $taskName
        Trigger = $trigger
        Action = $action
        User = 'System'
    }
    Register-ScheduledTask @splat
    Write-Output "Scheduled task '$taskName' created successfully"
} else {
    Write-Output "Scheduled task '$taskName' already exists"
}

