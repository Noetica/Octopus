<#
.SYNOPSIS
    Exports Octopus Deploy variables to JSON/JSONC format with custom formatting.

.DESCRIPTION
    Reads Octopus Deploy parameters and converts them to structured JSON output.
    Filters out internal Octopus variables, Fragment parameters, and environment variables.
    Creates a hierarchical nested structure from dot-notation parameter names.
    Outputs to the Windows TEMP directory with tenant-specific naming.

.PARAMETER IncludeComments
    When enabled, adds descriptive comments to the output as JSONC (JSON with Comments).
    Comments include export metadata, timestamp, and helpful context.
    Default: true

.PARAMETER OutputPath
    Custom output path for the JSON file. If not specified, uses TEMP directory
    with tenant slug in filename (e.g., contoso-variables.json).

.PARAMETER Depth
    Maximum depth for JSON conversion. Default: 10

.EXAMPLE
    .\Export-OctopusVariables.ps1
    Exports all non-Octopus variables to TEMP directory with default settings

.EXAMPLE
    .\Export-OctopusVariables.ps1 -IncludeComments:$false
    Exports without JSONC comments

.EXAMPLE
    .\Export-OctopusVariables.ps1 -OutputPath "C:\exports\config.json"
    Exports to a specific output file

.NOTES
    Author: Octopus Deploy
    Requires: PowerShell 5.1 or higher
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [bool]$IncludeComments = $true,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [int]$Depth = 10
)

#region Initialization

# Dot-source the JSON formatter utility
. "$PSScriptRoot\..\utils\json-formatter.ps1"

Write-Host "Exporting Octopus Variables"
Write-Host "=============================="

#endregion

#region Filter and Process Parameters

# Filter OctopusParameters to exclude:
# - Any parameters starting with "Octopus" (internal Octopus variables)
# - Any parameters containing "Fragment" (fragment path components)
# - Any parameters containing "env:" (environment variables)
# Sort the remaining parameters alphabetically for consistent output
Write-Host "Filtering parameters..."
$parameters = $OctopusParameters.Keys | Where-Object {
    -not $_.StartsWith("Octopus") -and -not $_.Contains("Fragment") -and -not $_.Contains("env:")
} | Sort-Object

Write-Host ("Found " + $parameters.Count + " parameters to export")

#endregion

#region Build Nested Structure

# Initialize the root hashtable for building nested JSON structure
$result = @{}

# Process each parameter and build a nested object structure
# Example: "Noetica.Database.Name" becomes { "Noetica": { "Database": { "Name": "value" } } }
Write-Host "Building nested structure..."
foreach ($parameter in $parameters) {
    $value = $OctopusParameters[$parameter]

    # Split the parameter name by dots to get the hierarchy path
    # Example: "Noetica.Database.Name" -> ["Noetica", "Database", "Name"]
    $parts = $parameter -split '\.'

    # Navigate through the nested structure, creating objects as needed
    $current = $result

    # Loop through all parts except the last one (which will hold the actual value)
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $part = $parts[$i]

        # Create a new hashtable if this level doesn't exist yet
        if (-not $current.ContainsKey($part)) {
            $current[$part] = @{}
        }

        # Move deeper into the nested structure
        $current = $current[$part]
    }

    # Set the actual value at the deepest level using the last part of the path
    $current[$parts[-1]] = $value
}

#endregion

#region Generate Output Path

# Generate the output file path using the tenant slug for identification
# Example: For tenant "contoso" -> "contoso-variables.json"
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $tenantSlug = $OctopusParameters["Octopus.Deployment.Tenant.Slug"]
    if ([string]::IsNullOrWhiteSpace($tenantSlug)) {
        $tenantSlug = "untenanted"
    }
    $fileName = "$tenantSlug-variables.json"
    $filePath = Join-Path $env:TEMP $fileName
}
else {
    $filePath = $OutputPath
}

#endregion

#region Convert to JSON

Write-Host "Generating JSON output..."

# Build header comments if requested
if ($IncludeComments) {
    $tenantName = $OctopusParameters['Octopus.Deployment.Tenant.Name']
    $tenantSlugComment = $OctopusParameters['Octopus.Deployment.Tenant.Slug']
    $projectName = $OctopusParameters['Octopus.Project.Name']
    $environmentName = $OctopusParameters['Octopus.Environment.Name']
    $exportedDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    $headerComments = @(
        "// Octopus Deploy Variables Export",
        "// Tenant: $tenantName",
        "// Tenant Slug: $tenantSlugComment",
        "// Project: $projectName",
        "// Environment: $environmentName",
        "// Exported: $exportedDate",
        "//",
        "// Note: Octopus internal variables, Fragment parameters, and environment variables are excluded",
        ""
    )

    # Use custom JSONC formatter with comments
    $jsonLines = ConvertTo-CustomJson -Data $result -HeaderComments $headerComments
    $jsonContent = $jsonLines -join "`n"
}
else {
    # Use PowerShell's built-in ConvertTo-Json with custom indentation formatting
    $rawJson = $result | ConvertTo-Json -Depth $Depth -Compress:$false
    $jsonContent = Format-JsonIndent -Json $rawJson
}

#endregion

#region Write Output

# Write to the output file with UTF-8 encoding
Write-Host ("Writing to file: " + $filePath)
$jsonContent | Out-File -FilePath $filePath -Encoding UTF8 -Force

#endregion

#region Verify and Report

# Verify file was created
if (Test-Path $filePath) {
    $fileInfo = Get-Item $filePath
    Write-Host ("✓ Successfully exported " + $parameters.Count + " parameters")
    Write-Host ("✓ File size: " + [math]::Round($fileInfo.Length / 1KB, 2) + " KB")
    Write-Host ("✓ Output: " + $filePath)
}
else {
    Write-Error ("Failed to create output file: " + $filePath)
    exit 1
}

Write-Host ""
Write-Host "Export completed successfully!"

#endregion
