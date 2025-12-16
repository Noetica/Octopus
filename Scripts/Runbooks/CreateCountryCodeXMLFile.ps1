# Set path for etc folder from Octopus parameter
$etcRoot = $OctopusParameters["Noetica.EtcRoot"]

# Set properties folder path to Properties
$propertiesFolder = $etcRoot + "\Properties\"

# Check if properties folder exists
if (-not (Test-Path -Path $propertiesFolder)) {
    Write-Error "Properties folder not found at: $propertiesFolder"
    exit 1
}

# Set CountryCode XML file path
$countryCodeFile = Join-Path -Path $propertiesFolder -ChildPath "CountryCode.xml"

# Create the CountryCode.xml file with fixed content
$xmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<Property type="String" name="CountryCode">
<DisplayName>Country Code</DisplayName>
<EnabledType>Optional</EnabledType>
<Enabled>true</Enabled>
<Modules>OBManager,SynthesysSwitchh,CTI\Interfaces\Mitel,SynCTIIntX</Modules>
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


# Set properties folder path to OptionalProperties
$propertiesFolder = $etcRoot + "\OptionalProperties\"

# Set Properties TXT file path
$propertiesFile = Join-Path -Path $propertiesFolder -ChildPath "Properties.txt"

# Check if CountryCode exists in Properties.txt, add if missing
$countryCodeExists = $false
if (Test-Path $propertiesFile) {
    $content = Get-Content -Path $propertiesFile
    foreach ($line in $content) {
        if ($line -eq "CountryCode") {
            $countryCodeExists = $true
            break
        }
    }
} else {
    Write-Host "Properties.txt file does not exist at path: $propertiesFile"
    exit
}

if ($countryCodeExists) {
    Write-Host "CountryCode already exists in Properties.txt"
    exit
} else {
    # Ensure file ends with newline before adding CountryCode
    $fileContent = [System.IO.File]::ReadAllText($propertiesFile)
    if (-not $fileContent.EndsWith("`n")) {
        [System.IO.File]::AppendAllText($propertiesFile, "`r`nCountryCode")
    } else {
        [System.IO.File]::AppendAllText($propertiesFile, "CountryCode")
    }
    Write-Host "CountryCode added to Properties.txt"
    exit
}