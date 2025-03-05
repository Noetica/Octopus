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

#Include VM creation functions
. "$PSScriptRoot\authenticate.ps1"

$getCommand = Get-Command -Name New-AzApiManagementContext -ErrorAction SilentlyContinue
if ($getCommand -eq $null) {
    Install-Module -Name Az -AllowClobber -Force
}

Write-Output "Checking API [$apiName] in environment $environment, location $location, partner $partner, subscription $subscriptionId"

if ($apiName -eq "campaignmanager")
{
    exit 0
}

$resourceGroupName = "rg-$($partner)-$($environment)-$($location)"
if ($tenant -eq "" -or $partner -eq "noetica")
{
    $apimServiceName = "apim-$($partner)-$($environment)-$($location)"
}
else {
    $apimServiceName = "apim-$($tenant)-$($partner)-$($environment)-$($location)"    
}

Write-Output "apimServiceName: $apimServiceName"

$apimContext = New-AzApiManagementContext -ResourceGroupName $resourceGroupName -ServiceName $apimServiceName
$subscription = Get-AzApiManagementSubscription -Context $apimContext -ProductId "subscribers"
$subscriptionKey = Get-AzApiManagementSubscriptionKey -Context $apimContext -SubscriptionId "$($subscription.SubscriptionId)"

if ($tenant -eq "" -or $partner -eq "noetica")
{
    $url = "http://apim-$($partner)-$($environment)-$($location).azure-api.net/$($apiName)/noetica/api/$($apiName)/ping"
}
else 
{
    $url = "http://apim-$($tenant)-$($partner)-$($environment)-$($location).azure-api.net/$($apiName)/noetica/api/$($apiName)/ping"<# Action when all if and elseif conditions are false #>
}
    
if ($apiVersion -ne $null -and $apiVersion -ne "")
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

Write-Output "Attempt to connect to URL $url"
Write-Output "With Headers:"
foreach ($key in $headers.Keys)
{
    $value = $headers[$key]
    Write-Output "$key : $value"
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
    Write-Output "Fail: Unable to reach the URL $url. Error: $_"
    
    exit 1  # Indicate failure
}
