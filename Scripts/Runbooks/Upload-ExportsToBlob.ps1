<#
.SYNOPSIS
    Uploads tenant export files to Azure Blob Storage.

.DESCRIPTION
    Scans for exported JSON/JSONC files in the specified directory and uploads them
    to Azure Blob Storage. Designed to run after tenant export runbooks to centralize
    all generated configuration files.

    Supports authentication via:
    - Azure Service Principal (ClientId, ClientSecret, TenantId)
    - Octopus Azure Account variables
    - Managed Identity (when running on Azure VMs)

.PARAMETER StorageAccountName
    Name of the Azure Storage Account.

.PARAMETER ContainerName
    Name of the blob container to upload to. Default: "tenant-exports"

.PARAMETER SourcePath
    Directory containing files to upload. Default: $env:TEMP

.PARAMETER FilePattern
    File pattern to match for upload. Default: "*-*.json*" (matches tenant-prefixed files)

.PARAMETER BlobPrefix
    Optional prefix/folder path within the container. Useful for organizing by date or environment.
    Example: "2025-01/production" creates blobs like "2025-01/production/tenant-variables.json"

.PARAMETER SubscriptionId
    Azure Subscription ID. Required if using Service Principal authentication.

.PARAMETER TenantId
    Azure AD Tenant ID for authentication. Can be provided or read from Octopus variables.

.PARAMETER ClientId
    Service Principal Client ID (Application ID). Can be provided or read from Octopus variables.

.PARAMETER ClientSecret
    Service Principal Client Secret. Can be provided or read from Octopus variables.

.PARAMETER UseManagedIdentity
    Use Azure Managed Identity for authentication instead of Service Principal.

.PARAMETER Overwrite
    Overwrite existing blobs with the same name. Default: true

.PARAMETER DeleteAfterUpload
    Delete local files after successful upload. Default: false

.PARAMETER ContentType
    Content-Type header for uploaded blobs. Default: "application/json"

.PARAMETER MaxConcurrentUploads
    Maximum number of concurrent upload operations. Default: 5

.EXAMPLE
    .\Upload-ExportsToBlob.ps1 -StorageAccountName "myaccount" -ContainerName "exports"
    Uploads all matching files from TEMP directory using Octopus Azure account variables

.EXAMPLE
    .\Upload-ExportsToBlob.ps1 -StorageAccountName "myaccount" -BlobPrefix "2025-01/dev"
    Uploads files to a date/environment-specific folder in blob storage

.EXAMPLE
    .\Upload-ExportsToBlob.ps1 -StorageAccountName "myaccount" -UseManagedIdentity
    Uploads using Azure Managed Identity authentication

.EXAMPLE
    .\Upload-ExportsToBlob.ps1 -StorageAccountName "myaccount" -SourcePath "C:\exports" -FilePattern "*.json"
    Uploads all JSON files from a custom directory

.NOTES
    Author: Octopus Deploy
    Requires: Az.Storage PowerShell module or Azure CLI
    Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $false)]
    [string]$ContainerName = "tenant-exports",

    [Parameter(Mandatory = $false)]
    [string]$SourcePath = $env:TEMP,

    [Parameter(Mandatory = $false)]
    [string]$FilePattern = "*-*.json*",

    [Parameter(Mandatory = $false)]
    [string]$BlobPrefix = "",

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [switch]$UseManagedIdentity,

    [Parameter(Mandatory = $false)]
    [bool]$Overwrite = $true,

    [Parameter(Mandatory = $false)]
    [bool]$DeleteAfterUpload = $false,

    [Parameter(Mandatory = $false)]
    [string]$ContentType = "application/json",

    [Parameter(Mandatory = $false)]
    [int]$MaxConcurrentUploads = 5
)

#region Initialization

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "Azure Blob Upload - Tenant Exports"
Write-Host "===================================="
Write-Host ""

#endregion

#region Helper Functions

function Test-AzureModule {
    <#
    .SYNOPSIS
        Checks if Azure PowerShell module is available.
    #>
    $azStorageModule = Get-Module -ListAvailable -Name "Az.Storage"
    $azAccountsModule = Get-Module -ListAvailable -Name "Az.Accounts"

    if ($azStorageModule -and $azAccountsModule) {
        Write-Verbose "Az.Storage and Az.Accounts modules found"
        return $true
    }

    Write-Verbose "Azure PowerShell modules not found"
    return $false
}

function Get-OctopusAzureCredentials {
    <#
    .SYNOPSIS
        Attempts to read Azure credentials from Octopus variables.
    #>
    $creds = @{}

    # Check for Octopus Azure Account variables
    if ($OctopusParameters) {
        $azureAccountName = $OctopusParameters["Octopus.Action.Azure.AccountId"]
        if ($azureAccountName) {
            Write-Verbose "Found Octopus Azure Account: $azureAccountName"

            $creds.SubscriptionId = $OctopusParameters["Octopus.Action.Azure.SubscriptionId"]
            $creds.TenantId = $OctopusParameters["Octopus.Action.Azure.TenantId"]
            $creds.ClientId = $OctopusParameters["Octopus.Action.Azure.ClientId"]
            $creds.ClientSecret = $OctopusParameters["Octopus.Action.Azure.Password"]
        }
    }

    return $creds
}

function Connect-ToAzure {
    <#
    .SYNOPSIS
        Authenticates to Azure using available credentials.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $false)]
        [string]$TenantId,

        [Parameter(Mandatory = $false)]
        [string]$ClientId,

        [Parameter(Mandatory = $false)]
        [string]$ClientSecret,

        [Parameter(Mandatory = $false)]
        [bool]$UseManagedIdentity
    )

    Write-Host "Authenticating to Azure..."

    # Try Managed Identity first if requested
    if ($UseManagedIdentity) {
        try {
            Write-Verbose "Attempting Managed Identity authentication"
            Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
            Write-Host ("[OK] Authenticated using Managed Identity")
            return $true
        } catch {
            Write-Warning "Managed Identity authentication failed: $_"
            return $false
        }
    }

    # Try Service Principal authentication
    if ($ClientId -and $ClientSecret -and $TenantId) {
        try {
            Write-Verbose "Attempting Service Principal authentication"
            $securePassword = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($ClientId, $securePassword)

            $connectParams = @{
                ServicePrincipal = $true
                Credential = $credential
                Tenant = $TenantId
                ErrorAction = "Stop"
            }

            if ($SubscriptionId) {
                $connectParams.Subscription = $SubscriptionId
            }

            Connect-AzAccount @connectParams | Out-Null
            Write-Host ("[OK] Authenticated using Service Principal")
            return $true
        } catch {
            Write-Warning "Service Principal authentication failed: $_"
            return $false
        }
    }

    Write-Warning "No valid authentication credentials provided"
    return $false
}

function Get-FilesToUpload {
    <#
    .SYNOPSIS
        Finds files matching the specified pattern in the source directory.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Source path does not exist or is not a directory: $Path"
    }

    $files = Get-ChildItem -LiteralPath $Path -Filter $Pattern -File -ErrorAction SilentlyContinue

    return $files
}

#endregion

#region Main Logic

try {
    # Check for Azure PowerShell module
    if (-not (Test-AzureModule)) {
        throw "Azure PowerShell modules (Az.Storage, Az.Accounts) are not installed. Please install them using: Install-Module -Name Az.Storage -Force"
    }

    # Import required modules
    Write-Verbose "Importing Azure modules..."
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.Storage -ErrorAction Stop

    # Get credentials from parameters or Octopus variables
    $octopusCreds = Get-OctopusAzureCredentials

    # Use provided parameters or fall back to Octopus variables
    $finalTenantId = if ($TenantId) { $TenantId } else { $octopusCreds.TenantId }
    $finalClientId = if ($ClientId) { $ClientId } else { $octopusCreds.ClientId }
    $finalClientSecret = if ($ClientSecret) { $ClientSecret } else { $octopusCreds.ClientSecret }
    $finalSubscriptionId = if ($SubscriptionId) { $SubscriptionId } else { $octopusCreds.SubscriptionId }

    # Authenticate to Azure
    $authenticated = Connect-ToAzure `
        -SubscriptionId $finalSubscriptionId `
        -TenantId $finalTenantId `
        -ClientId $finalClientId `
        -ClientSecret $finalClientSecret `
        -UseManagedIdentity $UseManagedIdentity

    if (-not $authenticated) {
        throw "Failed to authenticate to Azure. Please provide valid credentials."
    }

    # Get storage account context
    Write-Host "Connecting to storage account: $StorageAccountName"
    try {
        $storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $StorageAccountName }

        if (-not $storageAccount) {
            throw "Storage account '$StorageAccountName' not found in the current subscription"
        }

        $ctx = $storageAccount.Context
        Write-Host ("[OK] Connected to storage account")
    } catch {
        throw "Failed to get storage account context: $_"
    }

    # Ensure container exists
    Write-Host "Checking container: $ContainerName"
    try {
        $container = Get-AzStorageContainer -Name $ContainerName -Context $ctx -ErrorAction SilentlyContinue

        if (-not $container) {
            Write-Host "Container does not exist, creating: $ContainerName"
            if ($PSCmdlet.ShouldProcess($ContainerName, "Create container")) {
                New-AzStorageContainer -Name $ContainerName -Context $ctx -ErrorAction Stop | Out-Null
                Write-Host ("[OK] Container created")
            }
        } else {
            Write-Host ("[OK] Container exists")
        }
    } catch {
        throw "Failed to access or create container: $_"
    }

    # Find files to upload
    Write-Host ""
    Write-Host "Scanning for files in: $SourcePath"
    Write-Host ("Pattern: " + $FilePattern)

    $files = Get-FilesToUpload -Path $SourcePath -Pattern $FilePattern

    if ($files.Count -eq 0) {
        Write-Warning "No files found matching pattern '$FilePattern' in '$SourcePath'"
        Write-Host ""
        Write-Host "Upload completed: 0 files uploaded"
        exit 0
    }

    Write-Host ("[OK] Found " + $files.Count + " file(s) to upload")
    Write-Host ""

    # Upload files
    $uploadedCount = 0
    $failedCount = 0
    $uploadResults = @()

    foreach ($file in $files) {
        $blobName = if ($BlobPrefix) {
            "$BlobPrefix/$($file.Name)"
        } else {
            $file.Name
        }

        try {
            Write-Host ("Uploading: " + $file.Name + " -> " + $blobName)

            if ($PSCmdlet.ShouldProcess($blobName, "Upload to blob storage")) {
                $uploadParams = @{
                    File = $file.FullName
                    Container = $ContainerName
                    Blob = $blobName
                    Context = $ctx
                    Force = $Overwrite
                    ErrorAction = "Stop"
                }

                # Set content type if specified
                if ($ContentType) {
                    $uploadParams.Properties = @{"ContentType" = $ContentType}
                }

                $blob = Set-AzStorageBlobContent @uploadParams

                $uploadedCount++
                Write-Host ("  [OK] Uploaded (" + [math]::Round($file.Length / 1KB, 2) + " KB)")

                $uploadResults += [PSCustomObject]@{
                    FileName = $file.Name
                    BlobName = $blobName
                    Size = $file.Length
                    Status = "Success"
                    Uri = $blob.ICloudBlob.Uri.AbsoluteUri
                }

                # Delete local file if requested
                if ($DeleteAfterUpload) {
                    try {
                        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                        Write-Verbose "Deleted local file: $($file.FullName)"
                    } catch {
                        Write-Warning "Failed to delete local file: $_"
                    }
                }
            }
        } catch {
            $failedCount++
            Write-Error ("  [FAIL] Upload failed: " + $_.Exception.Message)

            $uploadResults += [PSCustomObject]@{
                FileName = $file.Name
                BlobName = $blobName
                Size = $file.Length
                Status = "Failed"
                Error = $_.Exception.Message
            }
        }
    }

    # Summary
    Write-Host ""
    Write-Host "Upload Summary"
    Write-Host "=============="
    Write-Host ("Total files found: " + $files.Count)
    Write-Host ("Successfully uploaded: " + $uploadedCount)
    Write-Host ("Failed: " + $failedCount)
    Write-Host ("Storage Account: " + $StorageAccountName)
    Write-Host ("Container: " + $ContainerName)

    if ($BlobPrefix) {
        Write-Host ("Blob Prefix: " + $BlobPrefix)
    }

    # Show blob URLs
    if ($uploadedCount -gt 0) {
        Write-Host ""
        Write-Host "Uploaded Blobs:"
        foreach ($result in $uploadResults | Where-Object { $_.Status -eq "Success" }) {
            Write-Host ("  - " + $result.BlobName)
        }
    }

    # Exit with error if any uploads failed
    if ($failedCount -gt 0) {
        Write-Host ""
        Write-Error "Some uploads failed. Check the logs above for details."
        exit 1
    }

    Write-Host ""
    Write-Host "Upload completed successfully!"

} catch {
    Write-Error "Upload process failed: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

#endregion
