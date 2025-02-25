$tenant = "#{ServicePrincipal.TenantId}"
$clientId = "#{ServicePrincipal.ClientId}"
$clientS = "#{ServicePrincipal.ClientSec}"

$securePassword = ConvertTo-SecureString -String $clientS -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $securePassword

Connect-AzAccount -ServicePrincipal -TenantId $tenant -Credential $credential
