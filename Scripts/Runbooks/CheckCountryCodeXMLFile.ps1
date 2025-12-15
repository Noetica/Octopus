# Default path for country code XML file
$propertiesFolder = "C:\Synthesys\Etc\Properties\"

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

