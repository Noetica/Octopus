#"args": [
#"-environment", "dev"
#"-location", "uksouth"
#"-partner", "noetica" 
#"-subscriptionId", "NoeticaCloudDev" 
#"-apiName", "agent"
#"-apiVersion", "2.0"
param (
    [Parameter(Mandatory = $true)] [ValidateSet("dev", "uat", "prod")][string]$environment,
    [Parameter(Mandatory = $true)] [ValidateSet("eastus2", "germanywestcentral", "uksouth")][string]$location,
    [Parameter(Mandatory = $false)] [string]$tenant,
    [Parameter(Mandatory = $true)] [string]$partner,
    [Parameter(Mandatory = $true)] [string]$subscriptionId,
    [Parameter(Mandatory = $true)] [string]$apiName,
    [Parameter(Mandatory = $false)] [string]$apiVersion
)

$resourceGroupName = "rg-$($partner)-$($environment)-$($location)"
if ($tenant -eq "")
{
    $apimServiceName = "apim-$($partner)-$($environment)-$($location)"
}
else {
    $apimServiceName = "apim-$($tenant)-$($partner)-$($environment)-$($location)"    
}


$apimContext = New-AzApiManagementContext -ResourceGroupName $resourceGroupName -ServiceName $apimServiceName
$subscription = Get-AzApiManagementSubscription -Context $apimContext -ProductId "subscribers"
$subscriptionKey = Get-AzApiManagementSubscriptionKey -Context $apimContext -SubscriptionId "$($subscription.SubscriptionId)"

if ($tenant -eq "")
{
    $url = "http://apim-$($partner)-$($environment)-$($location).azure-api.net/$($apiName)/noetica/api/$($apiName)/ping"
}
else 
{
    $url = "http://apim-$($tenant)-$($partner)-$($environment)-$($location).azure-api.net/$($apiName)/noetica/api/$($apiName)/ping"<# Action when all if and elseif conditions are false #>
}
    
if ($apiVersion -ne $null)
{
    $headers = @{
        "Ocp-Apim-Subscription-Key" = $subscriptionKey.PrimaryKey
        "X-Api-Version" = "$($apiVersion)"
    }
}
else 
{
    $headers = @{
        "Ocp-Apim-Subscription-Key" = $subscriptionKey.PrimaryKey
    }
}

try {
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    if ($response.StatusCode -eq 0 -or $response.StatusCode -eq 200) {
        Write-Output "Success: The URL returned a status code $($response.StatusCode)."
        exit 0  # Indicate success
    } else {
        Write-Output "Fail: The URL returned a status code $($response.StatusCode)."
        exit 1  # Indicate failure
    }
} catch {
    Write-Output "Fail: Unable to reach the URL. Error: $_"
    exit 1  # Indicate failure
}
