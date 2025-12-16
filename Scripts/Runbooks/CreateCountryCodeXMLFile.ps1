# Set path for etc folder from Octopus parameter
$etcRoot = $OctopusParameters["Noetica.EtcRoot"]

# Validate that etcRoot parameter is set
if ([string]::IsNullOrWhiteSpace($etcRoot)) {
    Write-Error "Noetica.EtcRoot parameter is not set"
    exit 1
}

# Set XML properties folder path to Properties
$xmlPropertiesFolder = $etcRoot + "\Properties\"

# Check if XML properties folder exists
if (-not (Test-Path -Path $xmlPropertiesFolder)) {
    Write-Error "Properties folder not found at: $xmlPropertiesFolder"
    exit 1
}

# Set CountryCode XML file path
$countryCodeFile = Join-Path -Path $xmlPropertiesFolder -ChildPath "CountryCode.xml"

# Create the CountryCode.xml file with fixed content
# Note: Intentionally overwrites existing file to ensure correct configuration
$xmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<Property type="String" name="CountryCode">
<DisplayName>Country Code</DisplayName>
<EnabledType>Optional</EnabledType>
<Enabled>true</Enabled>
<Classes>
<Class>User</Class>
<Class>Campaign</Class>
<Class>OutboundList</Class>
</Classes>
<Hint>This Setting sets the country code.</Hint>
<Default/>
<Widget>
<Type>Text</Type>
</Widget>
<Validation>
<Type>Regex</Type>
<Value>^(\+[1-9]\d{0,3})?$</Value>
<ErrorText>Must be a valid country code</ErrorText>
</Validation>
</Property>
"@

try {
    $xmlContent | Set-Content -Path $countryCodeFile -Encoding UTF8
    Write-Host "CountryCode.xml file created successfully at: $countryCodeFile"
}
catch {
    Write-Error "Failed to create CountryCode.xml file: $($_.Exception.Message)"
    exit 1
}

# Set optional properties folder path to OptionalProperties
$optionalPropertiesFolder = $etcRoot + "\OptionalProperties\"

# Check if optional properties folder exists
if (-not (Test-Path -Path $optionalPropertiesFolder)) {
    Write-Error "Optional Properties folder not found at: $optionalPropertiesFolder"
    exit 1
}

# Set Properties TXT file path
$propertiesFile = Join-Path -Path $optionalPropertiesFolder -ChildPath "Properties.txt"

# Check if CountryCode exists in Properties.txt, add if missing
$countryCodeExists = $false
if (Test-Path $propertiesFile) {
    # Read file as array of lines for line-by-line iteration
    $content = Get-Content -Path $propertiesFile
    foreach ($line in $content) {
        # Looking for exact match "CountryCode" (case-sensitive, with trimmed whitespace)
        if ($line.Trim() -eq "CountryCode") {
            $countryCodeExists = $true
            break
        }
    }
} else {
    Write-Host "Properties.txt file does not exist at path: $propertiesFile"
    exit 1
}

if ($countryCodeExists) {
    Write-Host "CountryCode already exists in Properties.txt"
    # Intentional early exit - no further action needed when CountryCode already exists
    exit 0
} else {
    try {
        # Ensure file ends with newline before adding CountryCode
        # Read entire file as single string to preserve newlines, carriage returns, and formatting
        $fileContent = [System.IO.File]::ReadAllText($propertiesFile)
        if (-not $fileContent.EndsWith("`n")) {
            [System.IO.File]::AppendAllText($propertiesFile, "`r`nCountryCode")
        } else {
            [System.IO.File]::AppendAllText($propertiesFile, "CountryCode")
        }
        Write-Host "CountryCode added to Properties.txt"
        exit 0
    }
    catch {
        Write-Error "Failed to update Properties.txt file: $($_.Exception.Message)"
        exit 1
    }
}