<#
.SYNOPSIS
    Uploads tenant export files to Azure Blob Storage using Azure CLI.

.DESCRIPTION
    Scans for exported JSON/JSONC files in the specified directory and uploads them
    to Azure Blob Storage using Azure CLI (az). This is an alternative to the
    Az.Storage PowerShell module version for systems where Azure CLI is available.

    Supports authentication via:
    - Azure Service Principal
    - Octopus Azure Account variables
    - Managed Identity
    - Azure CLI default credentials

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
    Azure Subscription ID. Optional if already set in Azure CLI context.

.PARAMETER TenantId
    Azure AD Tenant ID for authentication. Required for Service Principal auth.

.PARAMETER ClientId
    Service Principal Client ID (Application ID).

.PARAMETER ClientSecret
    Service Principal Client Secret.

.PARAMETER UseManagedIdentity
    Use Azure Managed Identity for authentication instead of Service Principal.

.PARAMETER Overwrite
    Overwrite existing blobs with the same name. Default: true

.PARAMETER DeleteAfterUpload
    Delete local files after successful upload. Default: false

.PARAMETER ContentType
    Content-Type header for uploaded blobs. Default: "application/json"

.EXAMPLE
    .\Upload-ExportsToBlob-AzCLI.ps1 -StorageAccountName "myaccount" -ContainerName "exports"
    Uploads all matching files from TEMP directory using current Azure CLI credentials

.EXAMPLE
    .\Upload-ExportsToBlob-AzCLI.ps1 -StorageAccountName "myaccount" -BlobPrefix "2025-01/dev"
    Uploads files to a date/environment-specific folder in blob storage

.EXAMPLE
    .\Upload-ExportsToBlob-AzCLI.ps1 -StorageAccountName "myaccount" -UseManagedIdentity
    Uploads using Azure Managed Identity authentication

.NOTES
    Author: Octopus Deploy
    Requires: Azure CLI (az) installed and available in PATH
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
    [string]$ContentType = "application/json"
)

#region Initialization

$ErrorActionPreference = "Stop"

Write-Host "Azure Blob Upload (Azure CLI) - Tenant Exports"
Write-Host "================================================"
Write-Host ""

#endregion

#region Helper Functions

function Test-AzureCLI {
    <#
    .SYNOPSIS
        Checks if Azure CLI is available.
    #>
    try {
        $azVersion = az version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Verbose "Azure CLI is available"
            return $true
        }
    } catch {
        Write-Verbose "Azure CLI not found"
    }
    return $false
}

function Get-OctopusAzureCredentials {
    <#
    .SYNOPSIS
        Attempts to read Azure credentials from Octopus variables.
    #>
    $creds = @{}

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

function Connect-AzureCLI {
    <#
    .SYNOPSIS
        Authenticates to Azure using Azure CLI.
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
            az login --identity 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Authenticated using Managed Identity"
                if ($SubscriptionId) {
                    az account set --subscription $SubscriptionId 2>&1 | Out-Null
                }
                return $true
            }
        } catch {
            Write-Warning "Managed Identity authentication failed: $_"
        }
    }

    # Try Service Principal authentication
    if ($ClientId -and $ClientSecret -and $TenantId) {
        try {
            Write-Verbose "Attempting Service Principal authentication"
            az login --service-principal --username $ClientId --password $ClientSecret --tenant $TenantId 2>&1 | Out-Null

            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Authenticated using Service Principal"
                if ($SubscriptionId) {
                    az account set --subscription $SubscriptionId 2>&1 | Out-Null
                }
                return $true
            }
        } catch {
            Write-Warning "Service Principal authentication failed: $_"
        }
    }

    # Check if already logged in
    $accountInfo = az account show 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Using existing Azure CLI credentials"
        if ($SubscriptionId) {
            az account set --subscription $SubscriptionId 2>&1 | Out-Null
        }
        return $true
    }

    Write-Warning "No valid authentication method succeeded"
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

function Upload-BlobWithAzCLI {
    <#
    .SYNOPSIS
        Uploads a file to blob storage using Azure CLI.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$BlobName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $false)]
        [string]$ContentType,

        [Parameter(Mandatory = $false)]
        [bool]$Overwrite
    )

    $uploadArgs = @(
        "storage", "blob", "upload",
        "--account-name", $StorageAccountName,
        "--container-name", $ContainerName,
        "--name", $BlobName,
        "--file", $FilePath,
        "--auth-mode", "login"
    )

    if ($ContentType) {
        $uploadArgs += "--content-type"
        $uploadArgs += $ContentType
    }

    if ($Overwrite) {
        $uploadArgs += "--overwrite"
    }

    Write-Verbose "Executing: az $($uploadArgs -join ' ')"

    $output = az @uploadArgs 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Upload failed: $output"
    }

    return $output
}

#endregion

#region Main Logic

try {
    # Check for Azure CLI
    if (-not (Test-AzureCLI)) {
        throw "Azure CLI is not installed or not available in PATH. Please install it from: https://aka.ms/InstallAzureCLI"
    }

    # Get credentials from parameters or Octopus variables
    $octopusCreds = Get-OctopusAzureCredentials

    # Use provided parameters or fall back to Octopus variables
    $finalTenantId = if ($TenantId) { $TenantId } else { $octopusCreds.TenantId }
    $finalClientId = if ($ClientId) { $ClientId } else { $octopusCreds.ClientId }
    $finalClientSecret = if ($ClientSecret) { $ClientSecret } else { $octopusCreds.ClientSecret }
    $finalSubscriptionId = if ($SubscriptionId) { $SubscriptionId } else { $octopusCreds.SubscriptionId }

    # Authenticate to Azure
    $authenticated = Connect-AzureCLI `
        -SubscriptionId $finalSubscriptionId `
        -TenantId $finalTenantId `
        -ClientId $finalClientId `
        -ClientSecret $finalClientSecret `
        -UseManagedIdentity $UseManagedIdentity

    if (-not $authenticated) {
        throw "Failed to authenticate to Azure. Please provide valid credentials or run 'az login' first."
    }

    # Verify storage account exists
    Write-Host "Verifying storage account: $StorageAccountName"
    $accountCheck = az storage account show --name $StorageAccountName 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Storage account '$StorageAccountName' not found or inaccessible: $accountCheck"
    }
    Write-Host "[OK] Storage account found"

    # Ensure container exists
    Write-Host "Checking container: $ContainerName"
    $containerCheck = az storage container exists --name $ContainerName --account-name $StorageAccountName --auth-mode login 2>&1 | ConvertFrom-Json

    if (-not $containerCheck.exists) {
        Write-Host "Container does not exist, creating: $ContainerName"
        if ($PSCmdlet.ShouldProcess($ContainerName, "Create container")) {
            az storage container create --name $ContainerName --account-name $StorageAccountName --auth-mode login 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create container"
            }
            Write-Host "[OK] Container created"
        }
    } else {
        Write-Host "[OK] Container exists"
    }

    # Find files to upload
    Write-Host ""
    Write-Host "Scanning for files in: $SourcePath"
    Write-Host "Pattern: $FilePattern"

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
                $result = Upload-BlobWithAzCLI `
                    -FilePath $file.FullName `
                    -BlobName $blobName `
                    -ContainerName $ContainerName `
                    -StorageAccountName $StorageAccountName `
                    -ContentType $ContentType `
                    -Overwrite $Overwrite

                $uploadedCount++
                Write-Host ("  [OK] Uploaded (" + [math]::Round($file.Length / 1KB, 2) + " KB)")

                # Construct blob URL
                $blobUrl = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$blobName"

                $uploadResults += [PSCustomObject]@{
                    FileName = $file.Name
                    BlobName = $blobName
                    Size = $file.Length
                    Status = "Success"
                    Uri = $blobUrl
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
