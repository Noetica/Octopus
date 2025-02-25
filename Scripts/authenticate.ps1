$tenant = "#{ServicePrincipal.TenantId}"
$clientId = "#{ServicePrincipal.ClientId}"
$clientS = "#{ServicePrincipal.ClientSec}"

$securePassword = ConvertTo-SecureString -String $clientS -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $securePassword

#Check if the az components are installed, and install as required
$getCommand = Get-Command -Name New-AzApiManagementContext -ErrorAction SilentlyContinue

if ($getCommand -eq $null) {
    Install-Module -Name Az -AllowClobber -Force
}

Connect-AzAccount -ServicePrincipal -TenantId $tenant -Credential $credential
