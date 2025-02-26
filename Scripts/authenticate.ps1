#Check if the az components are installed, and install as required
$getCommand = Get-Command -Name New-AzApiManagementContext -ErrorAction SilentlyContinue

if ($getCommand -eq $null) {
    Install-Module -Name Az -AllowClobber -Force
}

if ($debug -ne $null)
{
    Connect-AzAccount -Identity
}
else {
    Connect-AzAccount
}


