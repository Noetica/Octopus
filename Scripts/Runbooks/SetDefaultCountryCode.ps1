# Default country code to set/update
$defaultCountryCode = $OctopusParameters["Tenant.DefaultCountryCode"];
$iniFilePath = "C:\Synthesys\etc\synthesys.inf"

# Validate defaultCountryCode is not empty
if ([string]::IsNullOrWhiteSpace($defaultCountryCode)) {
    Write-Error "DefaultCountryCode in Octopus variables is blank."
    exit 1
}

# Validate defaultCountryCode format: +{digits}
if ($defaultCountryCode -notmatch '^\+\d+$') {
    Write-Error "DefaultCountryCode in Octopus variables must match the pattern '+{digits}' (e.g., +44, +1). Current value is: '$defaultCountryCode'"
    exit 1
}

# Verify file exists
if (-not (Test-Path $iniFilePath)) {
    Write-Error "File $iniFilePath not found"
    exit 1
}

# Read file and initialize tracking variables
$content = Get-Content $iniFilePath -Encoding Default
$inSection = $false
$sectionLine = -1
$linesToReplace = @()

Write-Host "Scanning $iniFilePath..."

# Scan for [Predictive] section and find DefaultCountryCode lines
for ($i = 0; $i -lt $content.Count; $i++) {
    if ($content[$i] -match '^\s*\[Predictive\]\s*$') {
        # Found the [Predictive] section header (allowing whitespace)
        $inSection = $true
        $sectionLine = $i
        Write-Host "Found [Predictive] section at line $($i + 1)"
    }
    elseif ($inSection -and $content[$i] -match '^\[.*\]') {
        # Hit another section, stop scanning
        break
    }
    elseif ($inSection -and $content[$i] -match '^DefaultCountryCode=') {
        # Found DefaultCountryCode variable (ignores lines starting with ";")
        Write-Host "Found DefaultCountryCode at line $($i + 1)"
        $linesToReplace += $i
    }
}

# Ensure [Predictive] section was found
if ($sectionLine -lt 0) {
    Write-Error "[Predictive] section not found"
    exit 1
}

# Build new content: replace existing or add new DefaultCountryCode
$newContent = for ($i = 0; $i -lt $content.Count; $i++) {
    if ($linesToReplace -contains $i) {
        # Replace existing DefaultCountryCode line
        "DefaultCountryCode=$defaultCountryCode"
    }
    else {
        # Keep the original line
        $content[$i]
        # Add DefaultCountryCode after [Predictive] header if it wasn't found
        if ($linesToReplace.Count -eq 0 -and $i -eq $sectionLine) {
            "DefaultCountryCode=$defaultCountryCode"
        }
    }
}

try {
    $newContent | Set-Content $iniFilePath -Encoding Default
    Write-Host "Updated successfully. DefaultCountryCode=$defaultCountryCode"
}
catch {
    Write-Error "Failed to update ${iniFilePath}: $($_.Exception.Message)"
    exit 1
}