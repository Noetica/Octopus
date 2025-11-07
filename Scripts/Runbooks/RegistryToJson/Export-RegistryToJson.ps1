<#
.SYNOPSIS
    Exports Windows Registry keys and values to JSON/JSONC format with intelligent type conversion.

.DESCRIPTION
    Reads Windows Registry keys and their values, converting them to structured JSON output.
    Supports automatic type detection for registry value types (String, DWord, QWord, Binary, etc.).
    Can export single keys or entire registry branches with depth control.
    Handles various edge cases including binary data, multi-string values, and expandable strings.

.PARAMETER RegistryPath
    Registry path to export. Supports both full paths (HKLM:\Software\...) and abbreviated forms.
    Examples: "HKLM:\SOFTWARE\MyApp", "HKEY_LOCAL_MACHINE\SOFTWARE\MyApp"

.PARAMETER OutputPath
    Path for the output JSON file. If not specified, creates a .json file in the current directory
    based on the registry key name.

.PARAMETER Recurse
    When enabled, exports all subkeys recursively up to the specified MaxDepth.

.PARAMETER MaxDepth
    Maximum depth for recursive registry key traversal. Default: 5
    Only applies when -Recurse is specified.

.PARAMETER IncludeMetadata
    When enabled, includes additional metadata like registry value types and last write time.

.PARAMETER PreserveComments
    When enabled, adds descriptive comments to the output as JSONC (JSON with Comments).
    Comments include registry paths, value types, and helpful context.

.PARAMETER PreserveFullPath
    When enabled, keeps full registry paths as keys (e.g., HKEY_LOCAL_MACHINE\SOFTWARE\...).
    When disabled (default), removes common base path and creates hierarchical nested structure.

.PARAMETER ConvertBooleanStrings
    When enabled, converts string values "true" and "false" to JSON boolean values.
    This is recommended for REST APIs where consumers expect proper boolean types.
    Case-insensitive. When disabled (default), preserves as strings.

.PARAMETER BinaryAsBase64
    When enabled, converts binary registry values to Base64 strings.
    When disabled (default), binary values are represented as byte arrays.

.PARAMETER ExpandEnvironmentStrings
    When enabled, expands environment variables in REG_EXPAND_SZ values.
    When disabled (default), keeps the original unexpanded strings.

.PARAMETER IncludeDefaultValue
    When enabled, includes the (Default) registry value if it exists.
    Default: true

.PARAMETER Encoding
    File encoding to use when writing the JSON file. Default: UTF8

.PARAMETER StrictMode
    When enabled, treats warnings as errors and fails on access denied or missing keys.

.PARAMETER Force
    Overwrite output file if it exists without prompting.

.PARAMETER Depth
    Maximum depth for JSON conversion. Default: 100

.PARAMETER MaxKeys
    Maximum number of registry keys to process. Safety limit. Default: 10000

.EXAMPLE
    .\Export-RegistryToJson.ps1 -RegistryPath "HKLM:\SOFTWARE\MyApp"
    Exports a single registry key to MyApp.json

.EXAMPLE
    .\Export-RegistryToJson.ps1 -RegistryPath "HKLM:\SOFTWARE\MyApp" -Recurse -MaxDepth 3
    Exports registry key and all subkeys up to 3 levels deep

.EXAMPLE
    .\Export-RegistryToJson.ps1 -RegistryPath "HKCU:\Software\MyApp" -OutputPath "C:\exports\config.json"
    Exports to a specific output file

.EXAMPLE
    .\Export-RegistryToJson.ps1 -RegistryPath "HKLM:\SOFTWARE\MyApp" -PreserveComments
    Creates MyApp.jsonc with descriptive comments about registry structure

.EXAMPLE
    .\Export-RegistryToJson.ps1 -RegistryPath "HKLM:\SOFTWARE\MyApp" -IncludeMetadata
    Includes registry value types and metadata in the output

.EXAMPLE
    .\Export-RegistryToJson.ps1 -RegistryPath "HKLM:\SOFTWARE\MyApp" -BinaryAsBase64
    Converts binary registry values to Base64 encoded strings

.EXAMPLE
    .\Export-RegistryToJson.ps1 -RegistryPath "HKLM:\SOFTWARE\MyApp" -Recurse -PreserveFullPath
    Exports with full registry paths as flat keys instead of hierarchical nesting

.EXAMPLE
    .\Export-RegistryToJson.ps1 -RegistryPath "HKLM:\SOFTWARE\MyApp" -Recurse
    Exports with hierarchical nested structure and simplified paths (default behavior)

.EXAMPLE
    .\Export-RegistryToJson.ps1 -RegistryPath "HKLM:\SOFTWARE\MyApp" -Recurse -SplitMultiLineStrings -ConvertBooleanStrings
    Exports with REST API optimizations: arrays for multi-line values and boolean conversion

.NOTES
    Author: Inspired by Convert-InfToJson.ps1
    Version: 2.0
    Requires: Windows PowerShell 5.1+ or PowerShell 7+ on Windows

    Registry Value Type Mappings:
    - REG_SZ (String) -> JSON string
    - REG_DWORD (DWord) -> JSON number
    - REG_QWORD (QWord) -> JSON number
    - REG_BINARY (Binary) -> JSON array of bytes or Base64 string
    - REG_MULTI_SZ (MultiString) -> JSON array of strings
    - REG_EXPAND_SZ (ExpandString) -> JSON string (optionally expanded)
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RegistryPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$Recurse,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 50)]
    [int]$MaxDepth = 5,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeMetadata,

    [Parameter(Mandatory = $false)]
    [switch]$PreserveComments,

    [Parameter(Mandatory = $false)]
    [switch]$PreserveFullPath,

    [Parameter(Mandatory = $false)]
    [switch]$ConvertBooleanStrings,

    [Parameter(Mandatory = $false)]
    [switch]$BinaryAsBase64,

    [Parameter(Mandatory = $false)]
    [switch]$ExpandEnvironmentStrings,

    [Parameter(Mandatory = $false)]
    [bool]$IncludeDefaultValue = $true,

    [Parameter(Mandatory = $false)]
    [ValidateSet('UTF8', 'ASCII', 'Unicode', 'UTF7', 'UTF32', 'Default')]
    [string]$Encoding = 'UTF8',

    [Parameter(Mandatory = $false)]
    [switch]$StrictMode,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$Depth = 100,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100000)]
    [int]$MaxKeys = 10000
)

# Initialize error and warning tracking
$script:HasErrors = $false
$script:WarningCount = 0
$script:ProcessedKeysCount = 0

# Registry hive abbreviation mapping
$script:RegistryHiveMap = @{
    'HKCR' = 'HKEY_CLASSES_ROOT'
    'HKCU' = 'HKEY_CURRENT_USER'
    'HKLM' = 'HKEY_LOCAL_MACHINE'
    'HKU'  = 'HKEY_USERS'
    'HKCC' = 'HKEY_CURRENT_CONFIG'
}

#region Helper Functions

function Write-ScriptWarning {
    param([string]$Message)

    $script:WarningCount++

    if ($StrictMode) {
        $script:HasErrors = $true
        Write-Error $Message
    } else {
        Write-Warning $Message
    }
}

function Normalize-RegistryPath {
    <#
    .SYNOPSIS
        Normalizes registry path to PowerShell-compatible format.
    #>
    param([string]$Path)

    # Remove quotes if present
    $Path = $Path.Trim('"', "'")

    # Handle HKEY_* full names - convert to PowerShell drive notation
    foreach ($abbrev in $script:RegistryHiveMap.Keys) {
        $fullName = $script:RegistryHiveMap[$abbrev]
        if ($Path -like "$fullName*") {
            $Path = $Path -replace "^$([regex]::Escape($fullName))", "${abbrev}:"
            break
        }
    }

    # Ensure PowerShell drive notation (HKLM:, HKCU:, etc.)
    if ($Path -notmatch '^HK[A-Z]{1,2}:') {
        foreach ($abbrev in $script:RegistryHiveMap.Keys) {
            if ($Path -like "$abbrev\*") {
                $Path = $Path -replace "^$abbrev\\", "${abbrev}:\"
                break
            }
        }
    }

    # Ensure backslashes after drive notation
    $Path = $Path -replace '^(HK[A-Z]{1,2}):([^\\])', '$1:\$2'

    return $Path
}

function Test-RegistryPathExists {
    <#
    .SYNOPSIS
        Tests if a registry path exists and is accessible.
    #>
    param([string]$Path)

    try {
        $normalizedPath = Normalize-RegistryPath -Path $Path
        return Test-Path -LiteralPath $normalizedPath -PathType Container
    } catch {
        return $false
    }
}

function Get-RegistryKeyInfo {
    <#
    .SYNOPSIS
        Gets detailed information about a registry key.
    #>
    param(
        [string]$Path,
        [int]$CurrentDepth = 0
    )

    # Check max keys limit
    $script:ProcessedKeysCount++
    if ($script:ProcessedKeysCount -gt $MaxKeys) {
        Write-ScriptWarning "Maximum key limit ($MaxKeys) reached. Stopping enumeration."
        return $null
    }

    try {
        $normalizedPath = Normalize-RegistryPath -Path $Path

        if (-not (Test-Path -LiteralPath $normalizedPath)) {
            Write-ScriptWarning "Registry path not found: $normalizedPath"
            return $null
        }

        # Get the registry key object
        $key = Get-Item -LiteralPath $normalizedPath -ErrorAction Stop

        # Initialize result structure
        $result = [ordered]@{}

        # Add metadata if requested
        if ($IncludeMetadata) {
            $result['_metadata'] = @{
                'RegistryPath' = $normalizedPath
                'SubKeyCount' = $key.SubKeyCount
                'ValueCount' = $key.ValueCount
            }

            # Add last write time if available (requires registry access)
            try {
                $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($key.Name.Replace('HKEY_LOCAL_MACHINE\', ''), $false)
                if ($regKey) {
                    $result['_metadata']['LastWriteTime'] = $regKey.LastWriteTime.ToString('o')
                    $regKey.Close()
                }
            } catch {
                # LastWriteTime not available, skip
            }
        }

        # Process registry values
        $valueNames = $key.GetValueNames()
        foreach ($valueName in $valueNames) {
            # Handle (Default) value
            if ([string]::IsNullOrEmpty($valueName)) {
                if (-not $IncludeDefaultValue) {
                    continue
                }
                $valueName = '(Default)'
            }

            try {
                $value = $key.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $valueKind = $key.GetValueKind($valueName)

                $convertedValue = Convert-RegistryValue -Value $value -ValueKind $valueKind -ValueName $valueName

                if ($IncludeMetadata) {
                    $result[$valueName] = @{
                        'Value' = $convertedValue
                        'Type' = $valueKind.ToString()
                    }
                } else {
                    $result[$valueName] = $convertedValue
                }
            } catch {
                Write-ScriptWarning "Failed to read registry value '$valueName' from '$normalizedPath': $($_.Exception.Message)"
            }
        }

        # Process subkeys if recursion is enabled
        if ($Recurse -and $CurrentDepth -lt $MaxDepth) {
            try {
                $subKeys = $key.GetSubKeyNames()

                if ($subKeys.Count -gt 0) {
                    if (-not $result.Contains('_subkeys')) {
                        $result['_subkeys'] = [ordered]@{}
                    }

                    foreach ($subKeyName in $subKeys) {
                        $subKeyPath = Join-Path $normalizedPath $subKeyName

                        try {
                            $subKeyInfo = Get-RegistryKeyInfo -Path $subKeyPath -CurrentDepth ($CurrentDepth + 1)
                            if ($null -ne $subKeyInfo) {
                                $result['_subkeys'][$subKeyName] = $subKeyInfo
                            }
                        } catch {
                            Write-ScriptWarning "Failed to access subkey '$subKeyName': $($_.Exception.Message)"
                        }
                    }
                }
            } catch {
                Write-ScriptWarning "Failed to enumerate subkeys of '$normalizedPath': $($_.Exception.Message)"
            }
        }

        return $result

    } catch [System.UnauthorizedAccessException] {
        Write-ScriptWarning "Access denied to registry path: $Path"
        return $null
    } catch {
        Write-ScriptWarning "Error reading registry key '$Path': $($_.Exception.Message)"
        return $null
    }
}

function Convert-RegistryValue {
    <#
    .SYNOPSIS
        Converts a registry value to an appropriate JSON-compatible type.
    #>
    param(
        $Value,
        [Microsoft.Win32.RegistryValueKind]$ValueKind,
        [string]$ValueName
    )

    switch ($ValueKind) {
        'String' {
            # REG_SZ - Regular string
            $stringValue = [string]$Value

            # Convert boolean strings if enabled
            if ($ConvertBooleanStrings -and $stringValue -match '^(true|false)$') {
                return [bool]::Parse($stringValue)
            }

            return $stringValue
        }

        'ExpandString' {
            # REG_EXPAND_SZ - String with environment variables
            if ($ExpandEnvironmentStrings) {
                $expandedValue = [System.Environment]::ExpandEnvironmentVariables($Value)
            } else {
                $expandedValue = [string]$Value
            }

            # Convert boolean strings if enabled
            if ($ConvertBooleanStrings -and $expandedValue -match '^(true|false)$') {
                return [bool]::Parse($expandedValue)
            }

            return $expandedValue
        }

        'Binary' {
            # REG_BINARY - Binary data
            if ($null -eq $Value -or $Value.Length -eq 0) {
                return @()
            }

            if ($BinaryAsBase64) {
                return [System.Convert]::ToBase64String($Value)
            } else {
                # Return as array of integers for JSON compatibility
                return @($Value | ForEach-Object { [int]$_ })
            }
        }

        'DWord' {
            # REG_DWORD - 32-bit number
            return [int]$Value
        }

        'QWord' {
            # REG_QWORD - 64-bit number
            return [long]$Value
        }

        'MultiString' {
            # REG_MULTI_SZ - Array of strings
            if ($null -eq $Value) {
                return @()
            }
            return @($Value)
        }

        'None' {
            # REG_NONE - No defined value type
            if ($null -eq $Value) {
                return $null
            }
            # Treat as binary
            if ($BinaryAsBase64) {
                return [System.Convert]::ToBase64String($Value)
            } else {
                return @($Value | ForEach-Object { [int]$_ })
            }
        }

        default {
            Write-Verbose "Unknown registry value type '$ValueKind' for '$ValueName', returning as string"
            return [string]$Value
        }
    }
}

function ConvertTo-JSONC {
    <#
    .SYNOPSIS
        Converts data to JSONC format with comments.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Data,

        [Parameter(Mandatory = $false)]
        [string]$RegistryPath,

        [Parameter(Mandatory = $false)]
        [int]$IndentLevel = 0
    )

    $indent = "  " * $IndentLevel
    $nextIndent = "  " * ($IndentLevel + 1)
    $lines = @()

    # Add header comment
    if ($IndentLevel -eq 0 -and $PreserveComments) {
        $lines += "// Registry Export"
        $lines += "// Source: $RegistryPath"
        $lines += "// Exported: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
        $lines += "// "
        if ($Recurse) {
            $lines += "// Recursive export (Max Depth: $MaxDepth)"
        } else {
            $lines += "// Single key export (no subkeys)"
        }
        $lines += ""
    }

    $lines += "$indent{"

    if ($Data -is [System.Collections.Specialized.OrderedDictionary] -or $Data -is [hashtable]) {
        $keys = @($Data.Keys)
        $keyCount = $keys.Count

        for ($i = 0; $i -lt $keyCount; $i++) {
            $key = $keys[$i]
            $value = $Data[$key]
            $isLast = ($i -eq $keyCount - 1)

            # Add comments for special keys
            if ($PreserveComments) {
                if ($key -eq '_metadata') {
                    $lines += "$nextIndent// Registry Key Metadata"
                } elseif ($key -eq '_subkeys') {
                    $lines += "$nextIndent// Subkeys"
                }
            }

            $escapedKey = $key -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`r", '\r' -replace "`t", '\t'

            if ($value -is [System.Collections.Specialized.OrderedDictionary] -or $value -is [hashtable]) {
                $lines += "$nextIndent`"$escapedKey`": {"

                $nestedLines = ConvertTo-JSONC -Data $value -IndentLevel ($IndentLevel + 2)
                # Remove outer braces from nested conversion
                $nestedContent = $nestedLines | Select-Object -Skip 1 | Select-Object -SkipLast 1
                $lines += $nestedContent

                $comma = if ($isLast) { "" } else { "," }
                $lines += "$nextIndent}$comma"
            } elseif ($value -is [array]) {
                $lines += "$nextIndent`"$escapedKey`": ["

                for ($j = 0; $j -lt $value.Count; $j++) {
                    $item = $value[$j]
                    $isLastItem = ($j -eq $value.Count - 1)
                    $itemJson = ConvertTo-JsonValue -Value $item
                    $comma = if ($isLastItem) { "" } else { "," }
                    $lines += "    $nextIndent$itemJson$comma"
                }

                $comma = if ($isLast) { "" } else { "," }
                $lines += "$nextIndent]$comma"
            } else {
                $valueJson = ConvertTo-JsonValue -Value $value
                $comma = if ($isLast) { "" } else { "," }
                $lines += "$nextIndent`"$escapedKey`": $valueJson$comma"
            }
        }
    }

    $lines += "$indent}"

    return $lines
}

function ConvertTo-JsonValue {
    <#
    .SYNOPSIS
        Converts a single value to JSON representation.
    #>
    param($Value)

    if ($null -eq $Value) {
        return "null"
    }
    elseif ($Value -is [bool]) {
        return $Value.ToString().ToLower()
    }
    elseif ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) {
        return $Value.ToString()
    }
    elseif ($Value -is [string]) {
        $escaped = $Value -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`r", '\r' -replace "`t", '\t'
        return "`"$escaped`""
    }
    else {
        # Fallback: convert to string
        $escaped = $Value.ToString() -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`r", '\r' -replace "`t", '\t'
        return "`"$escaped`""
    }
}

function Format-JsonIndent {
    <#
    .SYNOPSIS
        Fixes PowerShell's extreme indentation in ConvertTo-Json output by normalizing to 2-space indents.
    #>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Json
    )

    $lines = $Json -split "`r`n|`n"
    $output = @()
    $currentIndent = 0

    foreach ($line in $lines) {
        $trimmed = $line.TrimStart()

        # Normalize double spaces after colons to single space
        $trimmed = $trimmed -replace ':\s{2,}', ': '

        # Decrease indent for closing brackets
        if ($trimmed -match '^[\}\]]') {
            $currentIndent = [Math]::Max(0, $currentIndent - 1)
        }

        # Add line with proper indentation
        if ($trimmed) {
            $output += ("  " * $currentIndent) + $trimmed
        } else {
            $output += ""
        }

        # Increase indent for opening brackets
        if ($trimmed -match '[\{\[]$') {
            $currentIndent++
        }
    }

    return ($output -join "`n")
}

function Test-PathSafety {
    param(
        [string]$Path,
        [string]$PathType
    )

    # Check for path traversal sequences
    $normalizedPath = $Path -replace '\\', '/'
    if ($normalizedPath -match '\.\./|/\.\.' -or $normalizedPath -match '\.\.\\|\\\.\.') {
        throw "$PathType path contains potentially unsafe traversal sequences: $Path"
    }

    # Check for invalid characters
    $invalidChars = [System.IO.Path]::GetInvalidPathChars()
    foreach ($char in $invalidChars) {
        if ($Path.Contains($char)) {
            throw "$PathType path contains invalid character: $char"
        }
    }
}

function Test-DirectoryWritable {
    param([string]$DirectoryPath)

    if (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container)) {
        throw "Directory does not exist: $DirectoryPath"
    }

    try {
        $testFile = Join-Path $DirectoryPath ([System.IO.Path]::GetRandomFileName())
        $null = New-Item -Path $testFile -ItemType File -Force -ErrorAction Stop -WhatIf:$false
        Remove-Item -Path $testFile -Force -ErrorAction Stop -WhatIf:$false
    } catch [System.UnauthorizedAccessException] {
        throw "Access denied writing to directory: $DirectoryPath"
    } catch {
        throw "Cannot write to directory '$DirectoryPath': $_"
    }
}

function Get-CommonBasePath {
    <#
    .SYNOPSIS
        Finds the common base path from a list of registry paths.
        Returns the parent directory of the shortest path to ensure proper nesting.
    #>
    param([string[]]$Paths)

    Write-Verbose "=== Get-CommonBasePath START ==="
    Write-Verbose "Input paths count: $($Paths.Count)"

    if ($Paths.Count -eq 0) {
        Write-Verbose "No paths provided, returning empty string"
        return ""
    }

    # Show all paths
    foreach ($p in $Paths) {
        Write-Verbose "  Path: '$p' (Length=$($p.Length))"
    }

    # Find the shortest path (this will be our root level)
    $shortestPath = $Paths | Sort-Object -Property Length | Select-Object -First 1
    Write-Verbose "Shortest path: '$shortestPath' (Length=$($shortestPath.Length))"

    # Return the parent directory of the shortest path
    $lastSlash = $shortestPath.LastIndexOf('\')
    Write-Verbose "Last backslash position: $lastSlash"

    if ($lastSlash -gt 0) {
        $basePath = $shortestPath.Substring(0, $lastSlash + 1)
        Write-Verbose "Calculated base path: '$basePath' (Length=$($basePath.Length))"
        Write-Verbose "=== Get-CommonBasePath END ==="
        return $basePath
    }

    Write-Verbose "No base path (lastSlash <= 0), returning empty string"
    Write-Verbose "=== Get-CommonBasePath END ==="
    return ""
}

function ConvertTo-HierarchicalStructure {
    <#
    .SYNOPSIS
        Converts flat registry structure to hierarchical nested structure.
    #>
    param(
        [System.Collections.Specialized.OrderedDictionary]$FlatData,
        [string]$BasePath
    )

    $result = [ordered]@{}

    Write-Verbose "=== ConvertTo-HierarchicalStructure START ==="
    Write-Verbose "BasePath: '$BasePath' (Length=$($BasePath.Length))"
    Write-Verbose "FlatData Keys Count: $($FlatData.Keys.Count)"

    # Process in two passes to handle keys with both values and subkeys correctly
    # Pass 1: Create the structure and identify all paths
    $pathSegmentMap = [ordered]@{}

    foreach ($fullPath in $FlatData.Keys) {
        Write-Verbose ""
        Write-Verbose "--- Pass 1: Processing fullPath='$fullPath'"

        # Remove base path
        $relativePath = $fullPath
        if (-not [string]::IsNullOrEmpty($BasePath) -and $fullPath.StartsWith($BasePath)) {
            $relativePath = $fullPath.Substring($BasePath.Length)
            Write-Verbose "    After base removal: '$relativePath'"
        } else {
            Write-Verbose "    No base removal needed"
        }

        # Split into segments
        $segments = $relativePath -split '\\' | Where-Object { $_ -ne '' }

        Write-Verbose "    Segments Count: $($segments.Count)"
        for ($i = 0; $i -lt $segments.Count; $i++) {
            Write-Verbose "      [$i]: '$($segments[$i])' (Length=$($segments[$i].Length), Chars=$([string]::Join(',', [int[]][char[]]$segments[$i])))"
        }

        if ($segments.Count -eq 0) {
            # This is the root key - skip it as its values should be at the top level
            Write-Verbose "    ACTION: Skipping root key with 0 segments"
            continue
        }

        # Force array storage to prevent PowerShell unwrapping single-element arrays
        $pathSegmentMap[$fullPath] = @($segments)
    }

    # Sort paths by segment count to process parent keys before child keys
    $sortedPaths = $pathSegmentMap.Keys | Sort-Object { $pathSegmentMap[$_].Count }

    Write-Verbose ""
    Write-Verbose "=== Pass 2: Building hierarchical structure ==="
    Write-Verbose "Processing $($sortedPaths.Count) paths in order:"

    # Pass 2: Build the hierarchical structure
    foreach ($fullPath in $sortedPaths) {
        Write-Verbose ""
        Write-Verbose "--- Pass 2: Processing fullPath='$fullPath'"

        $segments = $pathSegmentMap[$fullPath]
        $keyData = $FlatData[$fullPath]

        Write-Verbose "    Segments: $($segments -join ' -> ')"
        Write-Verbose "    KeyData has $($keyData.Keys.Count) properties"

        # Navigate/create nested structure
        $current = $result
        for ($i = 0; $i -lt $segments.Count; $i++) {
            $segment = $segments[$i]
            Write-Verbose "    Processing Segment[$i]: '$segment' (Length=$($segment.Length))"

            if ($i -eq $segments.Count - 1) {
                # Last segment - this is where we place the data
                Write-Verbose "      This is the LAST segment - placing data here"

                # Ensure the key entry exists
                if (-not $current.Contains($segment)) {
                    Write-Verbose "        Creating new key: '$segment'"
                    $current[$segment] = [ordered]@{}
                } else {
                    Write-Verbose "        Key already exists: '$segment' (has $($current[$segment].Keys.Count) existing properties)"
                }

                # Add all values (non-subkey properties) to this key
                $valueCount = 0
                foreach ($valueName in $keyData.Keys) {
                    if ($valueName -ne '_subkeys') {
                        $valueCount++
                        Write-Verbose "          Adding value [$valueCount]: '$valueName' = $($keyData[$valueName])"
                        $current[$segment][$valueName] = $keyData[$valueName]
                    }
                }
                Write-Verbose "        Added $valueCount values to '$segment'"

                # Process subkeys if they exist (these are nested keys under this one)
                if ($keyData.Contains('_subkeys')) {
                    $subKeyCount = $keyData['_subkeys'].Count
                    Write-Verbose "        Processing $subKeyCount subkeys under '$segment'"
                    foreach ($subKeyName in $keyData['_subkeys'].Keys) {
                        Write-Verbose "          Merging subkey: '$subKeyName'"
                        # Subkeys should be merged into the current segment
                        if (-not $current[$segment].Contains($subKeyName)) {
                            $current[$segment][$subKeyName] = [ordered]@{}
                        }
                        # Merge subkey data
                        foreach ($subKeyValue in $keyData['_subkeys'][$subKeyName].Keys) {
                            $current[$segment][$subKeyName][$subKeyValue] = $keyData['_subkeys'][$subKeyName][$subKeyValue]
                        }
                    }
                }
            } else {
                # Intermediate segment - ensure path exists
                Write-Verbose "      This is an INTERMEDIATE segment - creating path and continuing"
                if (-not $current.Contains($segment)) {
                    Write-Verbose "        Creating intermediate path: '$segment'"
                    $current[$segment] = [ordered]@{}
                } else {
                    Write-Verbose "        Intermediate path already exists: '$segment'"
                }
                $current = $current[$segment]
            }
        }
    }

    Write-Verbose ""
    Write-Verbose "=== ConvertTo-HierarchicalStructure COMPLETE ==="
    Write-Verbose "Result has $($result.Keys.Count) top-level keys:"
    foreach ($key in $result.Keys) {
        Write-Verbose "  - '$key' (Length=$($key.Length), Chars=$([string]::Join(',', [int[]][char[]]$key)))"
    }

    return $result
}

function ConvertTo-PlainHashtable {
    <#
    .SYNOPSIS
        Recursively converts OrderedDictionary to PSCustomObject for JSON serialization.
    #>
    param($InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.Specialized.OrderedDictionary] -or
        $InputObject -is [hashtable]) {
        $result = [PSCustomObject]@{}
        foreach ($key in $InputObject.Keys) {
            Write-Verbose "ConvertTo-PlainHashtable: Processing key '$key' (Length=$($key.Length), Type=$($key.GetType().Name))"
            $value = ConvertTo-PlainHashtable -InputObject $InputObject[$key]
            Write-Verbose "  Adding member with name='$key'"
            $result | Add-Member -MemberType NoteProperty -Name $key -Value $value
            Write-Verbose "  Member added successfully"
        }
        Write-Verbose "ConvertTo-PlainHashtable: Returning PSCustomObject with $(@($result.PSObject.Properties).Count) properties"
        return $result
    }

    if ($InputObject -is [array]) {
        $result = @()
        foreach ($item in $InputObject) {
            $result += ConvertTo-PlainHashtable -InputObject $item
        }
        return $result
    }

    return $InputObject
}

function Get-RegistryDataFlat {
    <#
    .SYNOPSIS
        Collects all registry data in a flat structure for hierarchical conversion.
    #>
    param(
        [string]$Path,
        [int]$CurrentDepth = 0
    )

    $script:ProcessedKeysCount++

    if ($script:ProcessedKeysCount -gt $MaxKeys) {
        Write-ScriptWarning "Maximum key limit ($MaxKeys) reached. Stopping enumeration."
        return $null
    }

    $normalizedPath = Normalize-RegistryPath -Path $Path
    $result = [ordered]@{}
    $flatResult = [ordered]@{}

    try {
        $key = Get-Item -LiteralPath $normalizedPath -ErrorAction Stop

        # Get all value names (properties)
        $valueNames = $key.GetValueNames()

        foreach ($valueName in $valueNames) {
            # Skip (Default) if not including it
            if ($valueName -eq '' -and -not $IncludeDefaultValue) {
                continue
            }

            try {
                $displayName = if ($valueName -eq '') { '(Default)' } else { $valueName }
                $rawValue = $key.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $valueKind = $key.GetValueKind($valueName)

                $convertedValue = Convert-RegistryValue -Value $rawValue -ValueKind $valueKind -ValueName $displayName

                if ($IncludeMetadata) {
                    $result[$displayName] = @{
                        'Value' = $convertedValue
                        'Type'  = $valueKind.ToString()
                    }
                } else {
                    $result[$displayName] = $convertedValue
                }
            } catch {
                Write-ScriptWarning "Failed to read registry value '$valueName' from '$normalizedPath': $($_.Exception.Message)"
            }
        }

        # Store current key data
        $flatResult[$normalizedPath] = $result

        # Process subkeys if recursion is enabled
        if ($Recurse -and $CurrentDepth -lt $MaxDepth) {
            try {
                $subKeys = $key.GetSubKeyNames()

                if ($subKeys.Count -gt 0) {
                    foreach ($subKeyName in $subKeys) {
                        $subKeyPath = Join-Path $normalizedPath $subKeyName

                        try {
                            $subKeyData = Get-RegistryDataFlat -Path $subKeyPath -CurrentDepth ($CurrentDepth + 1)
                            if ($null -ne $subKeyData) {
                                # Merge subkey data into flat result
                                foreach ($subPath in $subKeyData.Keys) {
                                    $flatResult[$subPath] = $subKeyData[$subPath]
                                }
                            }
                        } catch {
                            Write-ScriptWarning "Failed to access subkey '$subKeyName': $($_.Exception.Message)"
                        }
                    }
                }
            } catch {
                Write-ScriptWarning "Failed to enumerate subkeys of '$normalizedPath': $($_.Exception.Message)"
            }
        }

        return $flatResult

    } catch [System.UnauthorizedAccessException] {
        Write-ScriptWarning "Access denied to registry path: $Path"
        return $null
    } catch {
        Write-ScriptWarning "Error reading registry key '$Path': $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Main Execution

try {
    Write-Verbose "Starting registry export process..."
    Write-Verbose "Registry Path: $RegistryPath"

    # Normalize the registry path
    $normalizedRegistryPath = Normalize-RegistryPath -Path $RegistryPath
    Write-Verbose "Normalized Path: $normalizedRegistryPath"

    # Validate registry path exists
    if (-not (Test-RegistryPathExists -Path $normalizedRegistryPath)) {
        throw "Registry path does not exist or is not accessible: $normalizedRegistryPath"
    }

    # Determine output path
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        # Extract key name for filename
        $keyName = Split-Path -Leaf $normalizedRegistryPath
        if ([string]::IsNullOrWhiteSpace($keyName)) {
            $keyName = "RegistryExport"
        }

        # Sanitize filename
        $keyName = $keyName -replace '[\\/:*?"<>|]', '_'

        $extension = if ($PreserveComments) { ".jsonc" } else { ".json" }
        $OutputPath = Join-Path (Get-Location).Path "$keyName$extension"
    }

    Write-Verbose "Output Path: $OutputPath"

    # Validate output path safety
    Test-PathSafety -Path $OutputPath -PathType "Output"

    # Check if output file exists
    if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
        if (-not $PSCmdlet.ShouldProcess($OutputPath, "Overwrite existing file")) {
            throw "Output file already exists. Use -Force to overwrite: $OutputPath"
        }
    }

    # Validate output directory is writable
    $outputDirectory = Split-Path -Parent $OutputPath
    if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
        $outputDirectory = Get-Location
    }
    Test-DirectoryWritable -DirectoryPath $outputDirectory

    # Export registry data
    Write-Verbose "Reading registry data..."

    if ($PreserveFullPath -or -not $Recurse) {
        # Use original nested structure
        $registryData = Get-RegistryKeyInfo -Path $normalizedRegistryPath -CurrentDepth 0

        if ($null -eq $registryData) {
            throw "Failed to read registry data from: $normalizedRegistryPath"
        }
    } else {
        # Collect flat data for hierarchical conversion
        $flatData = Get-RegistryDataFlat -Path $normalizedRegistryPath -CurrentDepth 0

        if ($null -eq $flatData -or $flatData.Count -eq 0) {
            throw "Failed to read registry data from: $normalizedRegistryPath"
        }

        # Apply hierarchical nesting and path simplification
        $allPaths = @($flatData.Keys)
        $basePath = Get-CommonBasePath -Paths $allPaths

        Write-Verbose "Common base path: $basePath"
        Write-Verbose "Flat data contains $($flatData.Count) keys:"
        foreach ($key in $flatData.Keys) {
            Write-Verbose "  - '$key'"
        }
        Write-Verbose "Converting to hierarchical structure..."

        $registryData = ConvertTo-HierarchicalStructure -FlatData $flatData -BasePath $basePath
    }

    Write-Verbose "Processed $script:ProcessedKeysCount registry key(s)"

    # Convert OrderedDictionary to plain object for JSON compatibility
    Write-Verbose "Converting data structure for JSON serialization..."
    $registryData = ConvertTo-PlainHashtable -InputObject $registryData

    # Convert to JSON
    Write-Verbose "Converting to JSON format..."

    if ($PreserveComments) {
        # Add JSONC header
        $jsonContent = "// Exported from: $RegistryPath`n"
        $jsonContent += "// Export date: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))`n"
        $jsonContent += "`n"
        $rawJson = $registryData | ConvertTo-Json -Depth $Depth -Compress:$false
        $jsonContent += (Format-JsonIndent -Json $rawJson)
    } else {
        # Use built-in ConvertTo-Json and fix indentation
        $rawJson = $registryData | ConvertTo-Json -Depth $Depth -Compress:$false
        $jsonContent = Format-JsonIndent -Json $rawJson
    }

    # Write output file
    if ($PSCmdlet.ShouldProcess($OutputPath, "Write JSON output")) {
        Write-Verbose "Writing output to: $OutputPath"

        $encodingObj = switch ($Encoding) {
            'UTF8' { [System.Text.UTF8Encoding]::new($false) } # UTF8 without BOM
            'ASCII' { [System.Text.ASCIIEncoding]::new() }
            'Unicode' { [System.Text.UnicodeEncoding]::new() }
            'UTF7' { [System.Text.UTF7Encoding]::new() }
            'UTF32' { [System.Text.UTF32Encoding]::new() }
            'Default' { [System.Text.Encoding]::Default }
            default { [System.Text.UTF8Encoding]::new($false) }
        }

        [System.IO.File]::WriteAllText($OutputPath, $jsonContent, $encodingObj)

        Write-Host "Successfully exported registry to: $OutputPath" -ForegroundColor Green

        # Output statistics
        Write-Host "  Keys processed: $script:ProcessedKeysCount" -ForegroundColor Cyan
        if ($script:WarningCount -gt 0) {
            Write-Host "  Warnings: $script:WarningCount" -ForegroundColor Yellow
        }
    }

    # Return output path for pipeline usage
    return $OutputPath

} catch {
    $script:HasErrors = $true
    Write-Error "Registry export failed: $($_.Exception.Message)"
    throw
} finally {
    # Exit with appropriate code
    if ($script:HasErrors) {
        exit 1
    } else {
        exit 0
    }
}

#endregion
