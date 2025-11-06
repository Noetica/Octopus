<#
.SYNOPSIS
    Converts INF configuration files to JSON format with intelligent type conversion.

.DESCRIPTION
    Parses INF/INI formatted configuration files and converts them to JSON output.
    Supports automatic type detection for booleans, integers, floats, and strings.
    Handles sections, comments, duplicate keys, and various edge cases.

.PARAMETER InfPath
    Path to the INF file to convert. Can be provided via parameter or Octopus variable.

.PARAMETER OutputPath
    Path for the output JSON file. If not specified, automatically creates a .json file
    with the same name/location as the source INF file.

.PARAMETER Encoding
    File encoding to use when reading the INF file. Default: UTF8

.PARAMETER StrictMode
    When enabled, treats warnings as errors and fails on issues like duplicate keys.

.PARAMETER NoTypeConversion
    When enabled, keeps all values as strings without automatic type conversion.

.PARAMETER StripQuotes
    When enabled, removes surrounding quotes from string values.

.PARAMETER DefaultSection
    Name for the section to use for key-value pairs found before any section header.
    Default: "_global_"

.PARAMETER Depth
    Maximum depth for JSON conversion. Default: 10

.EXAMPLE
    .\InfToJson.ps1 -InfPath "C:\config\app.inf"
    Creates C:\config\app.json

.EXAMPLE
    .\InfToJson.ps1 -InfPath "C:\config\app.inf" -OutputPath "C:\output\config.json"
    Creates C:\output\config.json

.EXAMPLE
    .\InfToJson.ps1 -InfPath "C:\config\app.inf" -StrictMode -StripQuotes
    Creates C:\config\app.json with strict validation

.NOTES
    Author: Enhanced by code review
    Version: 2.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$InfPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('UTF8', 'ASCII', 'Unicode', 'UTF7', 'UTF32', 'Default')]
    [string]$Encoding = 'UTF8',

    [Parameter(Mandatory = $false)]
    [switch]$StrictMode,

    [Parameter(Mandatory = $false)]
    [switch]$NoTypeConversion,

    [Parameter(Mandatory = $false)]
    [switch]$StripQuotes,

    [Parameter(Mandatory = $false)]
    [string]$DefaultSection = '_global_',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$Depth = 10
)

# Initialize error tracking for strict mode
$script:HasErrors = $false

function Write-ScriptWarning {
    param([string]$Message)

    if ($StrictMode) {
        $script:HasErrors = $true
        Write-Error $Message
    } else {
        Write-Warning $Message
    }
}

function ConvertTo-TypedValue {
    param([string]$Value)

    # Return as-is if type conversion is disabled
    if ($NoTypeConversion) {
        return $Value
    }

    # Strip quotes if requested
    if ($StripQuotes -and $Value.Length -ge 2) {
        if (($Value.StartsWith('"') -and $Value.EndsWith('"')) -or
            ($Value.StartsWith("'") -and $Value.EndsWith("'"))) {
            $Value = $Value.Substring(1, $Value.Length - 2)
        }
    }

    # Empty string
    if ($Value -eq '') {
        return $Value
    }

    # Boolean conversion (case-insensitive)
    if ($Value -imatch '^(true|false)$') {
        return ($Value -ieq 'true')
    }

    # Numeric conversions
    # Pattern 1: Decimal: 1.23, -2.5, 0.001
    if ($Value -match '^-?\d+\.\d+$') {
        try {
            return [double]$Value
        } catch {
            Write-Verbose "Failed to convert '$Value' to double: $_"
            return $Value
        }
    }

    # Pattern 2: Plain integer (exclude leading zeros like 01, 007)
    if ($Value -match '^-?\d+$' -and $Value -notmatch '^-?0\d+') {
        # Check for int64 overflow
        try {
            $int64Value = [int64]$Value
            return $int64Value
        } catch [System.OverflowException] {
            # Number too large for int64, try as double
            Write-Verbose "Value '$Value' too large for int64, converting to double"
            try {
                return [double]$Value
            } catch {
                Write-Verbose "Failed to convert large number '$Value': $_"
                return $Value
            }
        } catch {
            Write-Verbose "Failed to convert '$Value' to integer: $_"
            return $Value
        }
    }

    # Return as string for everything else
    return $Value
}

# Determine INF file path
if (-not $InfPath) {
    # Try to get from Octopus variable
    if ($null -ne $OctopusParameters -and $OctopusParameters.ContainsKey("Noetica.Inf")) {
        $InfPath = $OctopusParameters["Noetica.Inf"]
    }
}

if (-not $InfPath) {
    throw "INF file path not provided. Use -InfPath parameter or set Octopus variable 'Noetica.Inf'"
}

if (-not (Test-Path $InfPath -PathType Leaf)) {
    throw "INF file not found at: $InfPath"
}

Write-Verbose "Processing INF file: $InfPath"
Write-Verbose "Encoding: $Encoding"
Write-Verbose "Strict Mode: $StrictMode"
Write-Verbose "Type Conversion: $(-not $NoTypeConversion)"
Write-Verbose "Strip Quotes: $StripQuotes"

# Initialize result structure
$result = @{}
$section = $null
$seenKeys = @{}  # Track keys per section for duplicate detection
$sectionArrayItems = @{}  # Track array items for non-standard sections
$sectionHasKeyValue = @{}  # Track if section has any key=value pairs
$lineNumber = 0

# Read and process the INF file
try {
    Get-Content -Path $InfPath -Encoding $Encoding -ErrorAction Stop | ForEach-Object {
        $lineNumber++
        $line = $_.Trim()

        # Skip empty lines and full-line comments
        if ($line -eq '' -or $line -match '^[;#]') {
            return
        }

        # Section header: [SectionName]
        if ($line -match '^\[(.+?)\]$') {
            $sectionName = $matches[1].Trim()

            # Check for empty section name
            if ($sectionName -eq '') {
                Write-ScriptWarning "Line ${lineNumber}: Empty section name '[]' found"
                return
            }

            # Check for duplicate section
            if ($result.ContainsKey($sectionName)) {
                Write-ScriptWarning "Line ${lineNumber}: Duplicate section '[$sectionName]' found. Values will be merged."
            } else {
                $result[$sectionName] = @{}
                $seenKeys[$sectionName] = @{}
            }

            $section = $sectionName
            Write-Verbose "Line ${lineNumber}: Found section [$sectionName]"

            # Initialize tracking for this section
            if (-not $sectionArrayItems.ContainsKey($sectionName)) {
                $sectionArrayItems[$sectionName] = @()
                $sectionHasKeyValue[$sectionName] = $false
            }

            return
        }

        # Key-value pair: Key=Value
        if ($line -match '^([^=]+?)=(.*)$') {
            $key = $matches[1].Trim()
            $rawValue = $matches[2].Trim()

            # Validate key
            if ($key -eq '') {
                Write-ScriptWarning "Line ${lineNumber}: Empty key name found"
                return
            }

            # Handle keys before any section
            if (-not $section) {
                if ($DefaultSection) {
                    Write-Verbose "Line ${lineNumber}: Key '$key' found before any section, using default section '$DefaultSection'"
                    $section = $DefaultSection
                    if (-not $result.ContainsKey($section)) {
                        $result[$section] = @{}
                        $seenKeys[$section] = @{}
                    }
                } else {
                    Write-ScriptWarning "Line ${lineNumber}: Key-value pair found before any section header: $line"
                    return
                }
            }

            # Check for duplicate keys in the same section
            if ($seenKeys[$section].ContainsKey($key)) {
                Write-ScriptWarning "Line ${lineNumber}: Duplicate key '$key' in section '[$section]'. Previous value will be overwritten."
            }
            $seenKeys[$section][$key] = $true

            # NOTE: We do NOT remove inline comments with semicolons
            # because semicolons may be part of legitimate values (paths, URLs, etc.)
            # INF format doesn't have a standard for inline comments anyway.
            # If your INF file uses inline comments, consider pre-processing the file.

            # Remove trailing commas (common in some INF variants)
            $rawValue = $rawValue.TrimEnd(',').Trim()

            # Convert value to appropriate type
            $typedValue = ConvertTo-TypedValue -Value $rawValue

            Write-Verbose "Line ${lineNumber}: [$section] $key = $rawValue (Type: $($typedValue.GetType().Name))"

            $result[$section][$key] = $typedValue
            $sectionHasKeyValue[$section] = $true
            return
        }

        # Line didn't match key=value pattern
        # If we're in a section, store as array item (for CSV-like sections)
        if ($section) {
            Write-Verbose "Line ${lineNumber}: Storing non-standard line in section '[$section]' as array item"
            $sectionArrayItems[$section] += $line
            return
        }

        # No section context, warn about unparseable line
        Write-ScriptWarning "Line ${lineNumber}: Unable to parse line: $line"
    }
} catch {
    throw "Error reading INF file: $_"
}

# Check if we encountered any errors in strict mode
if ($StrictMode -and $script:HasErrors) {
    throw "Processing failed due to errors (StrictMode enabled)"
}

# Process sections with array items
foreach ($sectionName in $sectionArrayItems.Keys) {
    if ($sectionArrayItems[$sectionName].Count -gt 0) {
        # If section has NO key=value pairs, make it a pure array
        if (-not $sectionHasKeyValue[$sectionName]) {
            $result[$sectionName] = $sectionArrayItems[$sectionName]
            Write-Verbose "Section [$sectionName] converted to array with $($sectionArrayItems[$sectionName].Count) items"
        }
        # If section has BOTH key=value pairs and array items, add as _items property
        else {
            if (-not $result.ContainsKey($sectionName)) {
                $result[$sectionName] = @{}
            }
            $result[$sectionName]['_items'] = $sectionArrayItems[$sectionName]
            Write-Verbose "Added $($sectionArrayItems[$sectionName].Count) array items to section [$sectionName] under '_items'"
        }
    }
}

# Check if any data was parsed
if ($result.Count -eq 0) {
    Write-Warning "No sections or data found in INF file"
}

# Convert to JSON
try {
    $jsonOutput = $result | ConvertTo-Json -Depth $Depth -Compress:$false
} catch {
    throw "Error converting to JSON: $_"
}

# Determine output file path
if (-not $OutputPath) {
    # Generate output path from input path (same location, .json extension)
    $infFileInfo = Get-Item -Path $InfPath
    $outputFileName = [System.IO.Path]::GetFileNameWithoutExtension($infFileInfo.Name) + ".json"
    $OutputPath = Join-Path $infFileInfo.DirectoryName $outputFileName
    Write-Verbose "Output path not specified, using: $OutputPath"
}

# Write JSON to file
try {
    $jsonOutput | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    Write-Verbose "JSON file written to: $OutputPath"
} catch {
    throw "Error writing JSON file to '$OutputPath': $_"
}

Write-Verbose "Conversion completed successfully"
Write-Verbose "Sections processed: $($result.Count)"
Write-Host "Successfully converted '$InfPath' to '$OutputPath'" -ForegroundColor Green
