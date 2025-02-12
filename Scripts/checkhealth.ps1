param (
    [string]$BaseUrl = $OctopusParameters["Tenant.Domain"],
    [string]$AppLoginPage = "campaignmanager"
)
Write-Output "URLto check is $($Url)"
$Url = $BaseUrl + "/" + $AppLoginPage
try {
    $response = Invoke-WebRequest -Uri $Url -Method Head -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-Output "Success: The URL returned a status code 200."
        exit 0  # Indicate success
    } else {
        Write-Output "Fail: The URL returned a status code $($response.StatusCode)."
        exit 1  # Indicate failure
    }
} catch {
    Write-Output "Fail: Unable to reach the URL. Error: $_"
    exit 1  # Indicate failure
}