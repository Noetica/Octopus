$parentKey = "HKLM:\Software\Noetica\Voice Platform"
$pattern = "Group*"
$valueName = "ExtraParameters"
$newValue = "sipProxy=talkdeskkamailio2"

$subKeys = Get-ChildItem -Path $parentKey -Name | Where-Object { $_ -like $pattern }

foreach ($subKey in $subKeys) {
    $fullPath = "$parentKey\$subKey"
    try {
        $currentValue = Get-ItemProperty -Path $fullPath -Name $valueName -ErrorAction Stop
        Set-ItemProperty -Path $fullPath -Name $valueName -Value $newValue
        Write-Output "Updated $valueName in $fullPath"
    } catch {
        Write-Output "$valueName does not exist in $fullPath"
    }
}

$trigger = New-ScheduledTaskTrigger -AtStartup
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-NoProfile -NonInteractive -WindowStyle Hidden -File "C:\install\UpdateSIPdotINI.ps1"'
$splat = @{
    TaskName = 'Update NVP sip.ini with local IP'
    Trigger = $trigger
    Action = $action
#    Settings = $settings
#    Principal = $principal
#    TaskPath = 'c:\Install'
	User = 'System'
}
Register-ScheduledTask @splat

