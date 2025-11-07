# Azure Blob Storage Upload Setup Guide

This guide explains how to configure Octopus Deploy to upload tenant export files to Azure Blob Storage.

## Overview

After running tenant export runbooks (Variables, Synthesys, Voice Platform), you'll have multiple JSON/JSONC files in the TEMP directory that need to be centralized in Azure Blob Storage for backup, auditing, or downstream processing.

Two upload scripts are provided:
1. **Upload-ExportsToBlob.ps1** - Uses Azure PowerShell modules (Az.Storage)
2. **Upload-ExportsToBlob-AzCLI.ps1** - Uses Azure CLI (az command)

---

## Prerequisites

### Option 1: Azure PowerShell (Recommended)

Install on your Octopus tentacles:
```powershell
Install-Module -Name Az.Storage -Force -AllowClobber
Install-Module -Name Az.Accounts -Force -AllowClobber
```

### Option 2: Azure CLI

Install Azure CLI from: https://aka.ms/InstallAzureCLI

Or via Chocolatey:
```powershell
choco install azure-cli -y
```

---

## Azure Setup

### 1. Create Storage Account

```bash
# Using Azure CLI
az storage account create \
  --name "mytenantstorage" \
  --resource-group "MyResourceGroup" \
  --location "eastus" \
  --sku Standard_LRS

# The container will be created automatically by the script
```

### 2. Create Service Principal (for Octopus authentication)

```bash
# Create service principal
az ad sp create-for-rbac --name "OctopusExportUploader" \
  --role "Storage Blob Data Contributor" \
  --scopes /subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Storage/storageAccounts/{storage-account}

# Output will contain:
# - appId (ClientId)
# - password (ClientSecret)
# - tenant (TenantId)
```

### 3. Assign Storage Permissions

```bash
# Get storage account resource ID
STORAGE_ID=$(az storage account show \
  --name "mytenantstorage" \
  --resource-group "MyResourceGroup" \
  --query id -o tsv)

# Assign Storage Blob Data Contributor role
az role assignment create \
  --assignee {service-principal-appId} \
  --role "Storage Blob Data Contributor" \
  --scope $STORAGE_ID
```

---

## Octopus Deploy Configuration

### Option A: Using Octopus Azure Account (Recommended)

1. **Create Azure Account in Octopus:**
   - Go to **Infrastructure → Accounts → Add Account → Azure Subscription**
   - Fill in:
     - Name: `Azure Tenant Exports`
     - Subscription ID: `{your-subscription-id}`
     - Authentication Method: Service Principal
     - Tenant ID: `{from service principal creation}`
     - Application ID: `{appId from service principal}`
     - Application Password: `{password from service principal}`

2. **Create Project Variables:**
   ```
   Azure.StorageAccount = "mytenantstorage"
   Azure.BlobContainer = "tenant-exports"
   Azure.BlobPrefix = "#{Octopus.Environment.Name}/#{Octopus.Release.Created | Format Date: yyyy-MM}"
   ```

3. **Add Upload Step:**
   - Add step: **Run a Script**
   - Step name: `Upload Exports to Blob Storage`
   - Execution Location: Run on the same targets as export steps
   - Script source: Package reference to your Octopus repository
   - Script file: `Scripts/Runbooks/Upload-ExportsToBlob.ps1`
   - Parameters:
     ```powershell
     -StorageAccountName "#{Azure.StorageAccount}" `
     -ContainerName "#{Azure.BlobContainer}" `
     -BlobPrefix "#{Azure.BlobPrefix}" `
     -SourcePath "$env:TEMP" `
     -FilePattern "*-*.json*" `
     -Overwrite $true `
     -DeleteAfterUpload $false
     ```

### Option B: Using Direct Credentials

1. **Create Encrypted Variables:**
   ```
   Azure.SubscriptionId = {subscription-id}
   Azure.TenantId = {tenant-id}
   Azure.ClientId = {client-id}
   Azure.ClientSecret = {client-secret} [Mark as sensitive]
   Azure.StorageAccount = "mytenantstorage"
   Azure.BlobContainer = "tenant-exports"
   ```

2. **Add Upload Step with Explicit Credentials:**
   ```powershell
   -StorageAccountName "#{Azure.StorageAccount}" `
   -ContainerName "#{Azure.BlobContainer}" `
   -SubscriptionId "#{Azure.SubscriptionId}" `
   -TenantId "#{Azure.TenantId}" `
   -ClientId "#{Azure.ClientId}" `
   -ClientSecret "#{Azure.ClientSecret}" `
   -SourcePath "$env:TEMP" `
   -FilePattern "*-*.json*"
   ```

---

## Runbook Process Flow

### Complete Export + Upload Process

```
1. Export Octopus Variables
   ↓
2. Export Synthesys Configuration  
   ↓
3. Export Voice Platform Configuration
   ↓
4. Upload All Exports to Blob Storage
   ↓
5. (Optional) Clean up local files
```

### Recommended Step Configuration

#### Step 1-3: Export Steps
- **Target**: Deployment targets
- **Output**: Files in `$env:TEMP\{tenant-slug}-{export-type}.json`

#### Step 4: Upload to Blob
- **Target**: Same as export steps
- **Execution**: After all exports complete
- **Script**: `Upload-ExportsToBlob.ps1` or `Upload-ExportsToBlob-AzCLI.ps1`
- **Condition**: Always run (even if previous steps have warnings)

---

## Usage Examples

### Basic Upload (Using Octopus Azure Account)

```powershell
.\Upload-ExportsToBlob.ps1 `
  -StorageAccountName "mytenantstorage" `
  -ContainerName "tenant-exports"
```

### Upload with Date-Based Folder Structure

```powershell
.\Upload-ExportsToBlob.ps1 `
  -StorageAccountName "mytenantstorage" `
  -ContainerName "tenant-exports" `
  -BlobPrefix "2025-01/production"
```

Resulting blob paths:
```
tenant-exports/
  2025-01/
    production/
      contoso-variables.json
      contoso-synthesys.jsonc
      contoso-voiceplatform.jsonc
```

### Upload with Managed Identity (Azure VM)

```powershell
.\Upload-ExportsToBlob.ps1 `
  -StorageAccountName "mytenantstorage" `
  -UseManagedIdentity
```

### Upload and Clean Up Local Files

```powershell
.\Upload-ExportsToBlob.ps1 `
  -StorageAccountName "mytenantstorage" `
  -ContainerName "tenant-exports" `
  -DeleteAfterUpload $true
```

### Custom File Pattern

```powershell
.\Upload-ExportsToBlob.ps1 `
  -StorageAccountName "mytenantstorage" `
  -SourcePath "C:\Exports" `
  -FilePattern "*.jsonc"
```

---

## Advanced Configuration

### Multi-Tenant Upload with Environment Segregation

Create variable sets:
```
BlobPrefix.Dev = "dev/#{Octopus.Release.Created | Format Date: yyyy-MM-dd}"
BlobPrefix.Test = "test/#{Octopus.Release.Created | Format Date: yyyy-MM-dd}"
BlobPrefix.Prod = "prod/#{Octopus.Release.Created | Format Date: yyyy-MM-dd}"
```

Script parameters:
```powershell
-BlobPrefix "#{BlobPrefix.#{Octopus.Environment.Name}}"
```

Resulting structure:
```
tenant-exports/
  dev/
    2025-01-15/
      contoso-variables.json
      fabrikam-variables.json
  test/
    2025-01-15/
      contoso-variables.json
  prod/
    2025-01-15/
      contoso-variables.json
      fabrikam-variables.json
```

### Conditional Upload Based on Environment

In the upload step, set **Run Condition**:
```
#{unless Octopus.Environment.Name == "Development"}true#{/unless}
```

This skips upload in Development but runs in all other environments.

### Parallel Multi-Tenant Execution

If running exports across 20+ tenants in parallel:
1. Each tenant's export runs on its target
2. Files are written to TEMP with tenant slug prefix
3. Upload step runs on each target after all exports complete
4. Each target uploads only its own tenant's files

**Important**: Ensure `FilePattern` is specific enough:
```powershell
-FilePattern "#{Octopus.Deployment.Tenant.Slug}-*.json*"
```

---

## Troubleshooting

### Issue: "Azure PowerShell modules not installed"

**Solution**: Install modules on tentacle:
```powershell
Install-Module -Name Az.Storage -Force -AllowClobber
Install-Module -Name Az.Accounts -Force -AllowClobber
```

Or use the Azure CLI version instead.

### Issue: "Storage account not found"

**Solution**: Verify:
1. Service principal has access to the subscription
2. Storage account name is correct
3. Subscription ID is set correctly

### Issue: "Failed to authenticate to Azure"

**Solution**: Check:
1. Octopus Azure Account credentials are correct
2. Service Principal hasn't expired
3. Tenant ID matches the Azure AD tenant

### Issue: "No files found matching pattern"

**Solution**: 
1. Verify export steps ran successfully
2. Check `$env:TEMP` for generated files
3. Verify file naming matches pattern (e.g., `contoso-variables.json`)
4. Try `-FilePattern "*.json*"` to match all JSON/JSONC files

### Issue: "403 Forbidden" when uploading

**Solution**: Verify service principal has "Storage Blob Data Contributor" role:
```bash
az role assignment list --assignee {client-id} --all
```

### Issue: Unicode/encoding errors in uploaded files

The export scripts have been fixed to use ASCII-safe characters. If issues persist:
1. Ensure latest version of export scripts
2. Check that `-ContentType "application/json"` is set
3. Verify files are UTF-8 encoded before upload

---

## Security Best Practices

1. **Use Azure Key Vault** for storing Service Principal secrets in production
2. **Enable Managed Identity** on Azure VMs instead of Service Principal credentials
3. **Use Octopus Azure Accounts** instead of variables for credentials
4. **Limit Service Principal permissions** to only the required storage account
5. **Use private endpoints** for storage account in production environments
6. **Enable storage account firewall** to restrict access to known IPs
7. **Enable blob versioning** for audit trail and rollback capability

---

## Monitoring and Alerts

### Enable Azure Storage Logging

```bash
az monitor diagnostic-settings create \
  --name "StorageAccountLogs" \
  --resource "/subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Storage/storageAccounts/{storage-account}" \
  --logs '[{"category": "StorageWrite", "enabled": true}]' \
  --workspace "/subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.OperationalInsights/workspaces/{workspace-name}"
```

### Create Alert for Failed Uploads

In Octopus Deploy:
1. Go to **Configuration → Subscriptions**
2. Add subscription for deployment events
3. Filter: Deployment failed, Step name contains "Upload"
4. Action: Send email/Slack notification

---

## Cost Optimization

### Storage Tiers

For long-term retention:
```bash
# Set lifecycle policy to move old exports to Cool/Archive tier
az storage account management-policy create \
  --account-name "mytenantstorage" \
  --policy @lifecycle-policy.json
```

Example `lifecycle-policy.json`:
```json
{
  "rules": [
    {
      "name": "MoveOldExportsToCool",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["prod/"]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": {
              "daysAfterModificationGreaterThan": 30
            },
            "tierToArchive": {
              "daysAfterModificationGreaterThan": 90
            },
            "delete": {
              "daysAfterModificationGreaterThan": 365
            }
          }
        }
      }
    }
  ]
}
```

### Estimated Costs (60 files/day, 1KB each)

- **Hot tier**: ~$0.02/month
- **Cool tier (after 30 days)**: ~$0.01/month
- **Archive tier (after 90 days)**: ~$0.002/month
- **Transactions**: Negligible for this volume

---

## FAQ

**Q: Can I upload to multiple storage accounts?**  
A: Yes, run the upload step multiple times with different `-StorageAccountName` parameters.

**Q: How do I download files from blob storage?**  
A: Use Azure Storage Explorer, Azure Portal, or:
```bash
az storage blob download \
  --account-name "mytenantstorage" \
  --container-name "tenant-exports" \
  --name "prod/2025-01/contoso-variables.json" \
  --file "local-file.json"
```

**Q: Can I use SAS tokens instead of Service Principal?**  
A: Yes, but it's not recommended for automation. SAS tokens expire and need rotation.

**Q: What if I want to upload to AWS S3 or other cloud storage?**  
A: The scripts can be adapted. Replace Azure-specific commands with AWS CLI (`aws s3 cp`) or other providers.

**Q: How do I verify files were uploaded correctly?**  
A: The script outputs blob URLs. You can also check:
```bash
az storage blob list \
  --account-name "mytenantstorage" \
  --container-name "tenant-exports" \
  --auth-mode login
```

---

## Related Documentation

- [Azure Blob Storage Documentation](https://docs.microsoft.com/azure/storage/blobs/)
- [Octopus Deploy Azure Integration](https://octopus.com/docs/infrastructure/accounts/azure)
- [Azure PowerShell Documentation](https://docs.microsoft.com/powershell/azure/)
- [Azure CLI Documentation](https://docs.microsoft.com/cli/azure/)

---

## Support

For issues or questions:
1. Check Octopus deployment logs for error details
2. Verify Azure permissions and connectivity
3. Review troubleshooting section above
4. Contact your Azure administrator for access issues