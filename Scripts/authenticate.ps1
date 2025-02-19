$tenant = "822ef784-771f-4257-9898-e94f265e7eb6"
$clientId = "39040e89-a91c-42e3-ac10-67d8669ff1b9"
$clientS = "Zfw8Q~wxFHdeH6~YMuAsDDpv8X7HHePP8-5WIdoX"

$securePassword = ConvertTo-SecureString -String $clientS -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $securePassword

Connect-AzAccount -ServicePrincipal -TenantId $tenant -Credential $credential
