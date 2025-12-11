<#
.SYNOPSIS
    Converts Windows Registry .reg files to JSON format.

.DESCRIPTION
    Parses Windows Registry export files (.reg format) and converts them to JSON.
    Handles registry keys, values, and basic data types.
    This is a simpler alternative to Export-RegistryToJson.ps1 for working with
    existing .reg files rather than live registry data.

.PARAMETER RegFilePath
    Path to the .reg file to convert.

.PARAMETER OutputPath
    Path for the output JSON file. If not specified, creates a .json file
    with the same name/location as the source .reg file.

.PARAMETER Encoding
    File encoding to use when reading the .reg file. Default: Unicode

.PARAMETER OutputEncoding
    File encoding to use when writing the JSON file. Default: UTF8

.PARAMETER PreserveComments
    When enabled, preserves comments from .reg file as JSONC format.

.PARAMETER PreserveFullPath
    When enabled, keeps full registry paths as keys (e.g., HKEY_LOCAL_MACHINE\SOFTWARE\...).
    When disabled (default), removes common base path and creates hierarchical nested structure.

.PARAMETER SplitMultiLineStrings
    When enabled, splits REG_MULTI_SZ strings containing newlines into arrays.
    This is recommended for REST APIs where consumers expect arrays of discrete values.
    When disabled (default), preserves multi-line strings with embedded \n characters.

.PARAMETER ConvertBooleanStrings
    When enabled, converts string values "true" and "false" to JSON boolean values.
    This is recommended for REST APIs where consumers expect proper boolean types.
    Case-insensitive. When disabled (default), preserves as strings.

.PARAMETER Force
    Overwrite output file if it exists without prompting.

.EXAMPLE
    .\Convert-RegFileToJson.ps1 -RegFilePath "C:\exports\registry.reg"
    Converts registry.reg to registry.json with hierarchical structure and simplified paths

.EXAMPLE
    .\Convert-RegFileToJson.ps1 -RegFilePath "C:\exports\registry.reg" -PreserveComments
    Converts to JSONC with comments preserved

.EXAMPLE
    .\Convert-RegFileToJson.ps1 -RegFilePath "C:\exports\registry.reg" -PreserveFullPath
    Converts to JSON keeping full registry paths as flat keys

.EXAMPLE
    .\Convert-RegFileToJson.ps1 -RegFilePath "C:\exports\registry.reg" -SplitMultiLineStrings
    Converts to JSON and splits multi-line REG_MULTI_SZ values into arrays (better for REST APIs)

.EXAMPLE
    .\Convert-RegFileToJson.ps1 -RegFilePath "C:\exports\registry.reg" -SplitMultiLineStrings -ConvertBooleanStrings
    Converts with REST API optimizations: arrays for multi-line values and boolean conversion

.NOTES
    Author: Created for Octopus project
    Version: 1.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RegFilePath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Unicode', 'UTF8', 'UTF16', 'ASCII', 'Default')]
    [string]$Encoding = 'Unicode',

    [Parameter(Mandatory = $false)]
    [ValidateSet('UTF8', 'ASCII', 'Unicode', 'UTF7', 'UTF32', 'Default')]
    [string]$OutputEncoding = 'UTF8',

    [Parameter(Mandatory = $false)]
    [switch]$PreserveComments,

    [Parameter(Mandatory = $false)]
    [switch]$PreserveFullPath,

    [Parameter(Mandatory = $false)]
    [switch]$SplitMultiLineStrings,

    [Parameter(Mandatory = $false)]
    [switch]$ConvertBooleanStrings,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

#region Helper Functions

function ConvertFrom-RegHexString {
    <#
    .SYNOPSIS
        Converts registry hex string to appropriate type.
    #>
    param(
        [string]$HexString,
        [string]$Type
    )

    # Remove whitespace and commas
    $cleanHex = $HexString -replace '[\s,\\]', ''

    # Convert hex pairs to bytes
    $bytes = @()
    for ($i = 0; $i -lt $cleanHex.Length; $i += 2) {
        if ($i + 1 -lt $cleanHex.Length) {
            $bytes += [Convert]::ToByte($cleanHex.Substring($i, 2), 16)
        }
    }

    switch ($Type) {
        'dword' {
            # REG_DWORD - Little-endian 32-bit
            if ($bytes.Count -ge 4) {
                return [BitConverter]::ToInt32($bytes, 0)
            }
            return 0
        }
        'qword' {
            # REG_QWORD - Little-endian 64-bit
            if ($bytes.Count -ge 8) {
                return [BitConverter]::ToInt64($bytes, 0)
            }
            return 0
        }
        'binary' {
            # REG_BINARY - Return as byte array
            return $bytes
        }
        default {
            # Unknown type, return as byte array
            return $bytes
        }
    }
}

function ConvertFrom-RegString {
    <#
    .SYNOPSIS
        Converts registry string value, handling escape sequences.
    #>
    param([string]$Value)

    # Remove surrounding quotes
    if ($Value.StartsWith('"') -and $Value.EndsWith('"')) {
        $Value = $Value.Substring(1, $Value.Length - 2)
    }

    # Unescape common sequences
    $Value = $Value -replace '\\\\', '\'
    $Value = $Value -replace '\\"', '"'

    return $Value
}

function Get-CommonBasePath {
    <#
    .SYNOPSIS
        Finds the common base path from a list of registry paths.
        Returns the parent directory of the shortest path to ensure proper nesting.
    #>
    param([string[]]$Paths)

    if ($Paths.Count -eq 0) { return "" }

    # Find the shortest path (this will be our root level)
    $shortestPath = $Paths | Sort-Object -Property Length | Select-Object -First 1

    # Return the parent directory of the shortest path
    $lastSlash = $shortestPath.LastIndexOf('\')
    if ($lastSlash -gt 0) {
        return $shortestPath.Substring(0, $lastSlash + 1)
    }

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

    # First, identify the root key (shortest path after base removal)
    $rootKey = $null
    $minSegments = [int]::MaxValue

    foreach ($fullPath in $FlatData.Keys) {
        $relativePath = $fullPath
        if (-not [string]::IsNullOrEmpty($BasePath) -and $fullPath.StartsWith($BasePath)) {
            $relativePath = $fullPath.Substring($BasePath.Length)
        }

        $segments = $relativePath -split '\\' | Where-Object { $_ -ne '' }
        if ($segments.Count -lt $minSegments) {
            $minSegments = $segments.Count
            $rootKey = $fullPath
        }
    }

    foreach ($fullPath in $FlatData.Keys) {
        # Remove base path
        $relativePath = $fullPath
        if (-not [string]::IsNullOrEmpty($BasePath) -and $fullPath.StartsWith($BasePath)) {
            $relativePath = $fullPath.Substring($BasePath.Length)
        }

        # Split into segments
        $segments = $relativePath -split '\\' | Where-Object { $_ -ne '' }

        if ($segments.Count -eq 0 -or $fullPath -eq $rootKey) {
            # This is the root key - its values will be merged with its children
            # Get the last segment of the full path before base removal
            $fullSegments = $fullPath -split '\\' | Where-Object { $_ -ne '' }
            $rootSegmentName = $fullSegments[-1]

            if (-not $result.Contains($rootSegmentName)) {
                $result[$rootSegmentName] = [ordered]@{}
            }

            # Add root values to this container
            foreach ($key in $FlatData[$fullPath].Keys) {
                $result[$rootSegmentName][$key] = $FlatData[$fullPath][$key]
            }
            continue
        }

        # Navigate/create nested structure
        $current = $result
        for ($i = 0; $i -lt $segments.Count; $i++) {
            $segment = $segments[$i]
            $isLast = ($i -eq $segments.Count - 1)

            if ($isLast) {
                # Last segment - add the values
                if (-not $current.Contains($segment)) {
                    $current[$segment] = [ordered]@{}
                }

                # Merge values into this segment
                foreach ($key in $FlatData[$fullPath].Keys) {
                    $current[$segment][$key] = $FlatData[$fullPath][$key]
                }
            } else {
                # Intermediate segment - ensure it exists
                if (-not $current.Contains($segment)) {
                    $current[$segment] = [ordered]@{}
                } elseif ($current[$segment] -isnot [System.Collections.Specialized.OrderedDictionary] -and
                          $current[$segment] -isnot [hashtable]) {
                    # Convert to ordered dictionary if it's not already
                    $temp = $current[$segment]
                    $current[$segment] = [ordered]@{ '_value' = $temp }
                }
                $current = $current[$segment]
            }
        }
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
            $value = ConvertTo-PlainHashtable -InputObject $InputObject[$key]
            $result | Add-Member -MemberType NoteProperty -Name $key -Value $value
        }
        return $result
    }

    if ($InputObject -is [array]) {
        $result = [System.Collections.ArrayList]@()
        foreach ($item in $InputObject) {
            $null = $result.Add((ConvertTo-PlainHashtable -InputObject $item))
        }
        return $result.ToArray()
    }

    return $InputObject
}

function Process-PendingValue {
    <#
    .SYNOPSIS
        Processes accumulated hex data for a registry value.
    #>
    param(
        [string]$ValueName,
        [string]$ValueType,
        [string]$HexData,
        [bool]$SplitMultiLine = $false,
        [bool]$ConvertBooleans = $false
    )

    Write-Verbose "Processing $ValueType value '$ValueName' with data length: $($HexData.Length)"

    switch ($ValueType) {
        'qword' {
            $bytes = ConvertFrom-RegHexString -HexString $HexData -Type 'qword'
            return $bytes
        }
        'expand_sz' {
            $bytes = ConvertFrom-RegHexString -HexString $HexData -Type 'binary'
            if ($bytes.Count -gt 0) {
                $stringValue = [System.Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0)

                # Convert boolean strings if enabled
                if ($ConvertBooleans -and $stringValue -match '^(true|false)$') {
                    return [bool]::Parse($stringValue)
                }

                return $stringValue
            }
            return ""
        }
        'multi_sz' {
            $bytes = ConvertFrom-RegHexString -HexString $HexData -Type 'binary'
            if ($bytes.Count -gt 0) {
                $stringValue = [System.Text.Encoding]::Unicode.GetString($bytes)
                # Split on null terminators and filter out empty strings
                # Use -split with [char]0 to avoid issues with escape sequences
                $strings = [System.Collections.ArrayList]@()
                $splitResult = $stringValue -split [char]0
                foreach ($str in $splitResult) {
                    if ($str -ne '') {
                        $null = $strings.Add($str)
                    }
                }

                Write-Verbose "  multi_sz: Found $($strings.Count) string(s) after null split"
                Write-Verbose "  SplitMultiLine parameter: $SplitMultiLine"

                # If SplitMultiLine is enabled, further split on newlines
                if ($SplitMultiLine -and $strings.Count -eq 1) {
                    $firstString = [string]$strings[0]
                    Write-Verbose "  First string length: $($firstString.Length)"

                    # Check for newline character (LF = 10)
                    $hasNewline = $firstString.IndexOf([char]10) -ge 0
                    Write-Verbose "  Contains LF (char 10): $hasNewline"

                    if ($hasNewline) {
                        # Single string with embedded newlines - split for better API representation
                        $lines = [System.Collections.ArrayList]@()
                        $splitLines = $firstString -split [char]10
                        foreach ($line in $splitLines) {
                            $trimmed = $line.Trim([char]13).Trim()  # Trim CR and whitespace
                            if ($trimmed -ne '') {
                                $null = $lines.Add($trimmed)
                            }
                        }
                        Write-Verbose "  Split into $($lines.Count) lines for API"
                        return $lines.ToArray()
                    }
                }

                return $strings.ToArray()
            }
            return @()
        }
        'binary' {
            $bytes = ConvertFrom-RegHexString -HexString $HexData -Type 'binary'
            return $bytes
        }
        default {
            Write-Verbose "Unknown value type: $ValueType"
            return $HexData
        }
    }
}

function Parse-RegFile {
    <#
    .SYNOPSIS
        Parses a .reg file into a structured object.
    #>
    param(
        [string]$FilePath,
        [string]$FileEncoding
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "File not found: $FilePath"
    }

    # Read file with appropriate encoding
    $lines = Get-Content -LiteralPath $FilePath -Encoding $FileEncoding

    $result = [ordered]@{}
    $currentKey = $null
    $currentKeyData = [ordered]@{}
    $comments = @()
    $pendingValueName = $null
    $pendingValueType = $null
    $pendingHexData = ""

    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()

        # Skip header line (Windows Registry Editor Version...)
        if ($trimmedLine -match '^Windows Registry Editor') {
            continue
        }

        # Skip empty lines
        if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
            continue
        }

        # Handle comments
        if ($trimmedLine.StartsWith(';')) {
            if ($PreserveComments) {
                $commentText = $trimmedLine.Substring(1).Trim()
                $comments += $commentText
            }
            continue
        }

        # Handle registry key [HKEY_...]
        if ($trimmedLine -match '^\[(.+)\]$') {
            # Process any pending value first
            if ($null -ne $pendingValueName) {
                $processedValue = Process-PendingValue -ValueName $pendingValueName -ValueType $pendingValueType -HexData $pendingHexData -SplitMultiLine $SplitMultiLineStrings -ConvertBooleans $ConvertBooleanStrings
                $currentKeyData[$pendingValueName] = $processedValue
                $pendingValueName = $null
                $pendingValueType = $null
                $pendingHexData = ""
            }

            # Save previous key if exists
            if ($null -ne $currentKey -and $currentKeyData.Count -gt 0) {
                $result[$currentKey] = $currentKeyData
            }

            $currentKey = $matches[1]
            $currentKeyData = [ordered]@{}

            # Add comments if any
            if ($PreserveComments -and $comments.Count -gt 0) {
                $currentKeyData['_comments'] = $comments
                $comments = @()
            }
            continue
        }

        # Check if this is a continuation line (only hex digits, commas, and backslash)
        $isContinuation = $trimmedLine -match '^[0-9a-fA-F,\\s]+\\?$' -and $null -ne $pendingValueName

        if ($isContinuation) {
            # Append to pending hex data
            $pendingHexData += $trimmedLine
            Write-Verbose "Continuation line for '$pendingValueName': $trimmedLine"
            continue
        }

        # Process any pending value before starting a new one
        if ($null -ne $pendingValueName) {
            $processedValue = Process-PendingValue -ValueName $pendingValueName -ValueType $pendingValueType -HexData $pendingHexData -SplitMultiLine $SplitMultiLineStrings -ConvertBooleans $ConvertBooleanStrings
            $currentKeyData[$pendingValueName] = $processedValue
            $pendingValueName = $null
            $pendingValueType = $null
            $pendingHexData = ""
        }

        # Handle value assignments
        if ($trimmedLine -match '^"?([^"=]+)"?\s*=\s*(.+)$') {
            $valueName = $matches[1]
            $valueData = $matches[2].Trim()

            # Handle default value
            if ($valueName -eq '@') {
                $valueName = '(Default)'
            }

            # Skip if no current key is set
            if ($null -eq $currentKey) {
                Write-Verbose "Skipping value '$valueName' - no current key set"
                continue
            }

            # Parse value based on type
            if ($valueData.StartsWith('"')) {
                # REG_SZ - String (process immediately)
                $stringValue = ConvertFrom-RegString -Value $valueData

                # Convert boolean strings if enabled
                if ($ConvertBooleanStrings -and $stringValue -match '^(true|false)$') {
                    $currentKeyData[$valueName] = [bool]::Parse($stringValue)
                } else {
                    $currentKeyData[$valueName] = $stringValue
                }
            }
            elseif ($valueData -match '^dword:([0-9a-fA-F]+)$') {
                # REG_DWORD (process immediately)
                $hexValue = $matches[1]
                $currentKeyData[$valueName] = [Convert]::ToInt32($hexValue, 16)
            }
            elseif ($valueData -match '^hex\(b\):(.+)$') {
                # REG_QWORD (might be multi-line)
                $pendingValueName = $valueName
                $pendingValueType = 'qword'
                $pendingHexData = $matches[1]
            }
            elseif ($valueData -match '^hex\(2\):(.+)$') {
                # REG_EXPAND_SZ (might be multi-line)
                $pendingValueName = $valueName
                $pendingValueType = 'expand_sz'
                $pendingHexData = $matches[1]
            }
            elseif ($valueData -match '^hex\(7\):(.+)$') {
                # REG_MULTI_SZ (might be multi-line)
                $pendingValueName = $valueName
                $pendingValueType = 'multi_sz'
                $pendingHexData = $matches[1]
            }
            elseif ($valueData -match '^hex:(.+)$') {
                # REG_BINARY (might be multi-line)
                $pendingValueName = $valueName
                $pendingValueType = 'binary'
                $pendingHexData = $matches[1]
            }
            else {
                # Unknown format, store as string
                $currentKeyData[$valueName] = $valueData
            }
        }
    }

    # Process any final pending value
    if ($null -ne $pendingValueName) {
        $processedValue = Process-PendingValue -ValueName $pendingValueName -ValueType $pendingValueType -HexData $pendingHexData -SplitMultiLine $SplitMultiLineStrings -ConvertBooleans $ConvertBooleanStrings
        $currentKeyData[$pendingValueName] = $processedValue
    }

    # Save last key
    if ($null -ne $currentKey -and $currentKeyData.Count -gt 0) {
        $result[$currentKey] = $currentKeyData
    }

    # Apply hierarchical nesting and path simplification if needed
    if (-not $PreserveFullPath) {
        $allPaths = @($result.Keys)
        $basePath = Get-CommonBasePath -Paths $allPaths

        Write-Verbose "Common base path: $basePath"

        $result = ConvertTo-HierarchicalStructure -FlatData $result -BasePath $basePath
    }

    return $result
}

#endregion

#region Main Execution

try {
    Write-Verbose "Starting .reg file conversion..."
    Write-Verbose "Input file: $RegFilePath"

    # Validate input file
    $resolvedPath = Resolve-Path -LiteralPath $RegFilePath -ErrorAction Stop

    # Determine output path
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
        $directory = Split-Path -Parent $resolvedPath
        $extension = if ($PreserveComments) { ".jsonc" } else { ".json" }
        $OutputPath = Join-Path $directory "$baseName$extension"
    }

    # Resolve output path to absolute path
    if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path (Get-Location).Path $OutputPath
    }
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

    Write-Verbose "Output file: $OutputPath"

    # Check if output exists
    if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
        if (-not $PSCmdlet.ShouldProcess($OutputPath, "Overwrite existing file")) {
            throw "Output file already exists. Use -Force to overwrite: $OutputPath"
        }
    }

    # Parse the .reg file
    Write-Verbose "Parsing .reg file..."
    $registryData = Parse-RegFile -FilePath $resolvedPath -FileEncoding $Encoding

    if ($registryData.Count -eq 0) {
        Write-Warning "No registry data found in file"
    }

    # Track count before conversion
    $registryKeyCount = $registryData.Count

    # Convert OrderedDictionary to plain hashtable for JSON compatibility
    Write-Verbose "Converting data structure for JSON serialization..."
    $registryData = ConvertTo-PlainHashtable -InputObject $registryData

    # Convert to JSON
    Write-Verbose "Converting to JSON..."

    if ($PreserveComments) {
        # Add JSONC header
        $jsonContent = "// Converted from: $RegFilePath`n"
        $jsonContent += "// Conversion date: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))`n"
        $jsonContent += "`n"
        $jsonContent += ($registryData | ConvertTo-Json -Depth 100)
    } else {
        $jsonContent = $registryData | ConvertTo-Json -Depth 100
    }

    if ([string]::IsNullOrWhiteSpace($jsonContent)) {
        throw "JSON conversion produced empty output"
    }

    Write-Verbose "JSON content size: $($jsonContent.Length) characters"

    # Write output file
    if ($PSCmdlet.ShouldProcess($OutputPath, "Write JSON output")) {
        Write-Verbose "Writing output file..."

        $encodingObj = switch ($OutputEncoding) {
            'UTF8' { [System.Text.UTF8Encoding]::new($false) }
            'ASCII' { [System.Text.ASCIIEncoding]::new() }
            'Unicode' { [System.Text.UnicodeEncoding]::new() }
            'UTF7' { [System.Text.UTF7Encoding]::new() }
            'UTF32' { [System.Text.UTF32Encoding]::new() }
            'Default' { [System.Text.Encoding]::Default }
            default { [System.Text.UTF8Encoding]::new($false) }
        }

        [System.IO.File]::WriteAllText($OutputPath, $jsonContent, $encodingObj)

        # Verify file was written
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            throw "File was not created at: $OutputPath"
        }

        $fileInfo = Get-Item -LiteralPath $OutputPath
        Write-Host "Successfully converted .reg to JSON: $OutputPath" -ForegroundColor Green
        Write-Host "  Registry keys processed: $registryKeyCount" -ForegroundColor Cyan
        Write-Host "  Output file size: $($fileInfo.Length) bytes" -ForegroundColor Cyan
    }

    # Return output path for pipeline usage
    return $OutputPath

} catch {
    Write-Error "Conversion failed: $($_.Exception.Message)"
    throw
}

#endregion
