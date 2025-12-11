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

.PARAMETER EmptyAsNull
    When enabled, converts empty values (key=) to JSON null instead of empty strings.

.PARAMETER YesNoAsBoolean
    When enabled, converts Yes/No values to true/false booleans.

.PARAMETER PreserveComments
    When enabled, preserves comments from INF file as JSONC (JSON with Comments).
    Output will be .jsonc format with // style comments.

    Intelligently converts commented INF syntax to JSON syntax:
    - Commented key=value pairs become: // "key": "value",
    - Commented sections become: // "SectionName": { ... }
    - Regular comments are preserved as-is

    This allows comments to be uncommented and become valid JSON immediately.

.PARAMETER DefaultSection
    Name for the section to use for key-value pairs found before any section header.
    Default: "_global_"

.PARAMETER Depth
    Maximum depth for JSON conversion. Default: 10

.PARAMETER MaxFileSizeMB
    Maximum allowed file size in megabytes. Default: 100MB

.PARAMETER MaxSections
    Maximum number of sections allowed. Default: 10000

.PARAMETER Force
    Overwrite output file if it exists without prompting.

.EXAMPLE
    .\InfToJson.ps1 -InfPath "C:\config\app.inf"
    Creates C:\config\app.json

.EXAMPLE
    .\InfToJson.ps1 -InfPath "C:\config\app.inf" -OutputPath "C:\output\config.json"
    Creates C:\output\config.json

.EXAMPLE
    .\Convert-InfToJson.ps1 -InfPath "C:\config\app.inf" -StrictMode -StripQuotes
    Creates C:\config\app.json with strict validation

.EXAMPLE
    .\Convert-InfToJson.ps1 -InfPath "C:\config\app.inf" -EmptyAsNull
    Creates C:\config\app.json with empty values converted to null

.EXAMPLE
    .\Convert-InfToJson.ps1 -InfPath "C:\config\app.inf" -YesNoAsBoolean
    Creates C:\config\app.json with Yes/No values converted to true/false

.EXAMPLE
    .\Convert-InfToJson.ps1 -InfPath "C:\config\app.inf" -NoTypeConversion
    Creates C:\config\app.json with all values as strings (no type conversion)

.EXAMPLE
    .\Convert-InfToJson.ps1 -InfPath "C:\config\app.inf" -PreserveComments
    Creates C:\config\app.jsonc with comments preserved from the INF file.
    Commented INF syntax is converted to JSON format for easy uncommenting:
    ; Server=localhost becomes // "Server": "localhost",

.NOTES
    Author: Enhanced by code review
    Version: 2.1
#>

[CmdletBinding(SupportsShouldProcess)]
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
    [switch]$EmptyAsNull,

    [Parameter(Mandatory = $false)]
    [switch]$YesNoAsBoolean,

    [Parameter(Mandatory = $false)]
    [switch]$PreserveComments,

    [Parameter(Mandatory = $false)]
    [string]$DefaultSection = '_global_',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$Depth = 10,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 1024)]
    [int]$MaxFileSizeMB = 100,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100000)]
    [int]$MaxSections = 10000,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Initialize error and warning tracking
$script:HasErrors = $false
$script:WarningCount = 0

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

    # Empty string - convert to null if requested
    if ($Value -eq '') {
        if ($EmptyAsNull) {
            return $null
        }
        return $Value
    }

    # Boolean conversion (case-insensitive)
    if ($Value -imatch '^(true|false)$') {
        return ($Value -ieq 'true')
    }

    # Yes/No conversion (case-insensitive) - only if enabled
    if ($YesNoAsBoolean -and $Value -imatch '^(yes|no)$') {
        return ($Value -ieq 'yes')
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
            # Number too large for int64, keep as string to preserve exact value
            Write-Verbose "Value '$Value' exceeds int64 range, keeping as string to preserve precision"
            return $Value
        } catch {
            Write-Verbose "Failed to convert '$Value' to integer: $_"
            return $Value
        }
    }

    # Return as string for everything else
    return $Value
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

function Test-FileReadable {
    param([string]$Path)

    try {
        # Resolve to absolute path if relative
        $resolvedPath = Resolve-Path -LiteralPath $Path -ErrorAction Stop
        $stream = [System.IO.File]::OpenRead($resolvedPath.Path)
        $stream.Close()
        $stream.Dispose()
    } catch [System.Management.Automation.ItemNotFoundException] {
        throw "File not found: $Path"
    } catch [System.UnauthorizedAccessException] {
        throw "Access denied reading file: $Path"
    } catch [System.IO.IOException] {
        throw "I/O error accessing file: $Path - $($_.Exception.Message)"
    } catch {
        throw "Cannot read file '$Path': $($_.Exception.Message)"
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

function ConvertTo-JsonComment {
    <#
    .SYNOPSIS
        Converts INF syntax in comments to JSON syntax for better uncommentability.

    .DESCRIPTION
        Detects if a comment contains INF syntax (key=value or [section]) and converts
        it to proper JSON syntax so that uncommenting produces valid JSON.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommentText,

        [Parameter(Mandatory = $false)]
        [string]$CurrentSection
    )

    $trimmed = $CommentText.Trim()

    # Check if it's a section header: [SectionName]
    if ($trimmed -match '^\[([^\[\]\r\n\t]+)\]$') {
        $sectionName = $matches[1].Trim()
        # Escape the section name for JSON
        $escapedName = $sectionName -replace '\\', '\\' -replace '"', '\"'
        # Note: We don't add closing brace as it would be on a separate comment line
        # Users will need to uncomment both the opening and add a closing brace manually
        return "`"$escapedName`": { ... }"
    }

    # Check if it's a key=value pair
    if ($trimmed -match '^([A-Za-z0-9_\-\.\s]+?)\s*=\s*(.*)$') {
        $key = $matches[1].Trim()
        $rawValue = $matches[2].Trim()

        # Remove trailing commas
        $rawValue = $rawValue.TrimEnd(',').Trim()

        # Convert the value using the same logic as the main parser
        $typedValue = ConvertTo-TypedValue -Value $rawValue

        # Escape key for JSON
        $escapedKey = $key -replace '\\', '\\' -replace '"', '\"'

        # Convert typed value to JSON representation
        if ($null -eq $typedValue) {
            $jsonValue = "null"
        }
        elseif ($typedValue -is [bool]) {
            $jsonValue = $typedValue.ToString().ToLower()
        }
        elseif ($typedValue -is [int] -or $typedValue -is [long] -or $typedValue -is [double]) {
            $jsonValue = $typedValue.ToString()
        }
        else {
            # String - escape special characters
            $escaped = $typedValue -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`r", '\r' -replace "`t", '\t'
            $jsonValue = "`"$escaped`""
        }

        return "`"$escapedKey`": $jsonValue,"
    }

    # Not INF syntax, return as-is (plain comment)
    return $CommentText
}

function ConvertTo-JSONC {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Data,

        [Parameter(Mandatory = $false)]
        [hashtable]$Comments = @{},

        [Parameter(Mandatory = $false)]
        $SectionComments = @{},

        [Parameter(Mandatory = $false)]
        $TrailingComments = @{},

        [Parameter(Mandatory = $false)]
        $CommentedSectionBlocks = @(),

        [Parameter(Mandatory = $false)]
        [int]$Depth = 10,

        [Parameter(Mandatory = $false)]
        [int]$IndentLevel = 0
    )

    if ($Depth -le 0) {
        return '"..."'
    }

    $indent = "  " * $IndentLevel
    $nextIndent = "  " * ($IndentLevel + 1)
    $nestedIndent = "  " * ($IndentLevel + 2)
    $lines = @()
    $lines += "$indent{"

    $sectionIndex = 0
    $sectionCount = $Data.Keys.Count

    foreach ($sectionKey in $Data.Keys) {
        $sectionIndex++
        $isLastSection = ($sectionIndex -eq $sectionCount)

        $sectionValue = $Data[$sectionKey]

        # Handle array sections
        if ($sectionValue -is [array]) {
            $lines += "$nextIndent`"$sectionKey`": ["

            # Add section comments inside array
            if ($SectionComments.Contains($sectionKey)) {
                foreach ($comment in $SectionComments[$sectionKey]) {
                    $lines += "$nestedIndent// $comment"
                }
            }

            for ($i = 0; $i -lt $sectionValue.Count; $i++) {
                $item = $sectionValue[$i]
                $isLast = ($i -eq $sectionValue.Count - 1)
                $itemJson = ConvertTo-JsonValue -Value $item -IndentLevel ($IndentLevel + 2)
                $comma = if ($isLast) { "" } else { "," }
                $lines += "$nestedIndent$itemJson$comma"
            }
            $comma = if ($isLastSection) { "" } else { "," }
            $lines += "$nextIndent]$comma"
        }
        # Handle object sections
        elseif ($sectionValue -is [System.Collections.Specialized.OrderedDictionary] -or $sectionValue -is [hashtable]) {
            $lines += "$nextIndent`"$sectionKey`": {"

            # Add section comments inside object (at the top)
            if ($SectionComments.Contains($sectionKey)) {
                foreach ($comment in $SectionComments[$sectionKey]) {
                    $lines += "$nestedIndent// $comment"
                }
            }

            $keyIndex = 0
            $keyCount = $sectionValue.Keys.Count

            foreach ($key in $sectionValue.Keys) {
                $keyIndex++
                $isLastKey = ($keyIndex -eq $keyCount)

                # Add key-specific leading comments
                $commentKey = "${sectionKey}.${key}"
                if ($Comments.ContainsKey($commentKey)) {
                    foreach ($comment in $Comments[$commentKey]) {
                        $lines += "$nestedIndent// $comment"
                    }
                }

                $value = $sectionValue[$key]
                $valueJson = ConvertTo-JsonValue -Value $value -IndentLevel ($IndentLevel + 2)

                # Check if there are trailing comments for this key
                $hasTrailingComments = $TrailingComments.Contains($commentKey)

                # If there are trailing comments, don't add comma to value line
                # The comma will be added after the last trailing comment
                if ($hasTrailingComments) {
                    $lines += "$nestedIndent`"$key`": $valueJson"
                } else {
                    $comma = if ($isLastKey) { "" } else { "," }
                    $lines += "$nestedIndent`"$key`": $valueJson$comma"
                }

                # Add key-specific trailing comments
                if ($hasTrailingComments) {
                    $trailingCommentList = $TrailingComments[$commentKey]
                    for ($i = 0; $i -lt $trailingCommentList.Count; $i++) {
                        $comment = $trailingCommentList[$i]
                        $isLastComment = ($i -eq $trailingCommentList.Count - 1)

                        # Add comma after the last trailing comment if this isn't the last key
                        if ($isLastComment -and -not $isLastKey) {
                            $lines += "$nestedIndent// $comment,"
                        } else {
                            $lines += "$nestedIndent// $comment"
                        }
                    }
                }
            }

            $comma = if ($isLastSection) { "" } else { "," }
            $lines += "$nextIndent}$comma"
        }
        else {
            # Primitive value at section level
            $valueJson = ConvertTo-JsonValue -Value $sectionValue -IndentLevel ($IndentLevel + 1)
            $comma = if ($isLastSection) { "" } else { "," }
            $lines += "$nextIndent`"$sectionKey`": $valueJson$comma"
        }

        # Check if there are any commented section blocks that should appear after this section
        foreach ($block in $CommentedSectionBlocks) {
            if ($block.AfterSection -eq $sectionKey) {
                # Output the commented section block
                $escapedBlockName = $block.SectionName -replace '\\', '\\' -replace '"', '\"'
                $lines += "$nextIndent// `"$escapedBlockName`": {"
                foreach ($comment in $block.Comments) {
                    $lines += "$nestedIndent//   $comment"
                }
                $comma = if ($isLastSection) { "" } else { "," }
                $lines += "$nextIndent// }$comma"
            }
        }
    }

    $lines += "$indent}"

    return ($lines -join "`n")
}

function ConvertTo-JsonValue {
    param(
        [Parameter(Mandatory = $false)]
        $Value,

        [Parameter(Mandatory = $false)]
        [int]$IndentLevel = 0
    )

    if ($null -eq $Value) {
        return "null"
    }

    $type = $Value.GetType().Name

    switch ($type) {
        "Boolean" {
            return $Value.ToString().ToLower()
        }
        "Int32" { return $Value.ToString() }
        "Int64" { return $Value.ToString() }
        "Double" { return $Value.ToString() }
        "Single" { return $Value.ToString() }
        "String" {
            # Escape special characters for JSON
            $escaped = $Value -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`r", '\r' -replace "`t", '\t'
            return "`"$escaped`""
        }
        "Object[]" {
            $indent = "  " * $IndentLevel
            $nextIndent = "  " * ($IndentLevel + 1)
            $items = @()
            foreach ($item in $Value) {
                $itemJson = ConvertTo-JsonValue -Value $item -IndentLevel ($IndentLevel + 1)
                $items += "$nextIndent$itemJson"
            }
            if ($items.Count -gt 0) {
                return "[`n$($items -join ",`n")`n$indent]"
            } else {
                return "[]"
            }
        }
        "ArrayList" {
            $indent = "  " * $IndentLevel
            $nextIndent = "  " * ($IndentLevel + 1)
            $items = @()
            foreach ($item in $Value) {
                $itemJson = ConvertTo-JsonValue -Value $item -IndentLevel ($IndentLevel + 1)
                $items += "$nextIndent$itemJson"
            }
            if ($items.Count -gt 0) {
                return "[`n$($items -join ",`n")`n$indent]"
            } else {
                return "[]"
            }
        }
        default {
            # Try to convert as string
            $escaped = $Value.ToString() -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`r", '\r' -replace "`t", '\t'
            return "`"$escaped`""
        }
    }
}

# Determine INF file path
if (-not $InfPath) {
    # Try to get from Octopus variable
    if ($null -ne $OctopusParameters -and $OctopusParameters.ContainsKey("Noetica.Inf")) {
        $InfPath = $OctopusParameters["Noetica.Inf"]
    }
}

# Validate INF path is provided
if ([string]::IsNullOrWhiteSpace($InfPath)) {
    throw "INF file path not provided. Use -InfPath parameter or set Octopus variable 'Noetica.Inf'"
}

# Validate INF file path safety
try {
    $null = Test-PathSafety -Path $InfPath -PathType "Input"
} catch {
    throw $_
}

# Check INF file exists
if (-not (Test-Path -LiteralPath $InfPath -PathType Leaf)) {
    throw "INF file not found at: $InfPath"
}

# Validate file size
$maxFileSizeBytes = $MaxFileSizeMB * 1MB
$fileInfo = Get-Item -LiteralPath $InfPath -ErrorAction Stop
if ($fileInfo.Length -gt $maxFileSizeBytes) {
    throw "File size ($([math]::Round($fileInfo.Length / 1MB, 2)) MB) exceeds maximum allowed ($MaxFileSizeMB MB)"
}

# Validate file is readable
try {
    $null = Test-FileReadable -Path $InfPath
} catch {
    throw $_
}

Write-Verbose "Processing INF file: $InfPath"
Write-Verbose "File size: $([math]::Round($fileInfo.Length / 1KB, 2)) KB"
Write-Verbose "Encoding: $Encoding"
Write-Verbose "Strict Mode: $StrictMode"
Write-Verbose "Type Conversion: $(-not $NoTypeConversion)"
Write-Verbose "Strip Quotes: $StripQuotes"
Write-Verbose "Empty As Null: $EmptyAsNull"
Write-Verbose "Yes/No As Boolean: $YesNoAsBoolean"
Write-Verbose "Preserve Comments: $PreserveComments"
Write-Verbose "Max File Size: $MaxFileSizeMB MB"
Write-Verbose "Max Sections: $MaxSections"

# Initialize result structure (using [ordered] to preserve section/key order)
$result = [ordered]@{}
$section = $null
$seenKeys = @{}  # Track keys per section for duplicate detection
$sectionArrayItems = [ordered]@{}  # Track array items for non-standard sections
$sectionHasKeyValue = @{}  # Track if section has any key=value pairs
$lineNumber = 0

# Comment tracking for JSONC output
$comments = [ordered]@{}  # Comments by section and key (leading comments)
$trailingComments = [ordered]@{}  # Trailing comments after keys
$pendingComments = @()  # Comments waiting to be associated
$sectionComments = [ordered]@{}  # Comments for sections
$lastKey = $null  # Track the last processed key for trailing comments
$commentedSectionBlocks = [System.Collections.ArrayList]@()  # Track commented section blocks
$inCommentedSectionBlock = $false  # Flag to track if we're in a commented section block
$currentCommentedBlock = $null  # Current commented section block being built

# Read and process the INF file
try {
    Get-Content -LiteralPath $InfPath -Encoding $Encoding -ErrorAction Stop | ForEach-Object {
        $lineNumber++
        $line = $_.Trim()

        # Handle empty lines
        if ($line -eq '') {
            return
        }

        # Handle full-line comments - capture if PreserveComments enabled
        if ($line -match '^[;#]' -or $line -match '^//') {
            if ($PreserveComments) {
                # Remove comment prefix and store
                $commentText = $line -replace '^[;#]\s*', '' -replace '^//\s*', ''

                # Check if this is a commented section header
                if ($commentText -match '^\[([^\[\]\r\n\t]+)\]$') {
                    # Close previous commented section block if one exists
                    if ($inCommentedSectionBlock -and $currentCommentedBlock -ne $null) {
                        $null = $commentedSectionBlocks.Add($currentCommentedBlock)
                        Write-Verbose "Closed commented section block [$($currentCommentedBlock.SectionName)] with $($currentCommentedBlock.Comments.Count) lines"
                    }

                    # Start a new commented section block
                    $commentedSectionName = $matches[1].Trim()
                    $inCommentedSectionBlock = $true
                    $currentCommentedBlock = @{
                        SectionName = $commentedSectionName
                        Comments = @()
                        AfterSection = $section  # Track which section this follows
                    }
                    Write-Verbose "Line ${lineNumber}: Started commented section block [$commentedSectionName]"
                    return
                }

                # If we're in a commented section block, add to it
                if ($inCommentedSectionBlock) {
                    # Convert INF syntax in comments to JSON syntax
                    $jsonComment = ConvertTo-JsonComment -CommentText $commentText -CurrentSection $null
                    $currentCommentedBlock.Comments += $jsonComment
                    Write-Verbose "Line ${lineNumber}: Added to commented section block: $jsonComment"
                    return
                }

                # Regular comment - convert INF syntax to JSON syntax
                $jsonComment = ConvertTo-JsonComment -CommentText $commentText -CurrentSection $section
                $pendingComments += $jsonComment
                Write-Verbose "Line ${lineNumber}: Captured comment: $jsonComment"
            }
            return
        }

        # If we reach here with a non-comment line, close any commented section block
        if ($inCommentedSectionBlock -and $currentCommentedBlock -ne $null) {
            $null = $commentedSectionBlocks.Add($currentCommentedBlock)
            Write-Verbose "Closed commented section block [$($currentCommentedBlock.SectionName)] with $($currentCommentedBlock.Comments.Count) lines"
            $inCommentedSectionBlock = $false
            $currentCommentedBlock = $null
        }

        # Section header: [SectionName]
        # More restrictive regex - disallow brackets, newlines, and control characters in section names
        if ($line -match '^\[([^\[\]\r\n\t]+)\]$') {
            $sectionName = $matches[1].Trim()

            # Check for empty section name
            if ($sectionName -eq '') {
                Write-ScriptWarning "Line ${lineNumber}: Empty section name '[]' found"
                return
            }

            # Check section count limit
            if ($result.Count -ge $MaxSections) {
                throw "Number of sections exceeds maximum allowed ($MaxSections). Consider increasing -MaxSections parameter."
            }

            # Before opening new section, assign any pending comments
            if ($PreserveComments -and $pendingComments.Count -gt 0) {
                if ($section -and $lastKey) {
                    # Assign to the last key in the previous section (trailing comments)
                    $commentKey = "${section}.${lastKey}"
                    if (-not $trailingComments.Contains($commentKey)) {
                        $trailingComments[$commentKey] = @()
                    }
                    $trailingComments[$commentKey] += $pendingComments
                    Write-Verbose "Assigned $($pendingComments.Count) trailing comment(s) to key [$section].$lastKey"
                    $pendingComments = @()
                } elseif ($section) {
                    # No keys in previous section, assign to section itself
                    if (-not $sectionComments.Contains($section)) {
                        $sectionComments[$section] = @()
                    }
                    $sectionComments[$section] += $pendingComments
                    Write-Verbose "Assigned $($pendingComments.Count) comment(s) to previous section [$section]"
                    $pendingComments = @()
                } else {
                    # This is the first section, assign comments to it
                    if (-not $sectionComments.Contains($sectionName)) {
                        $sectionComments[$sectionName] = @()
                    }
                    $sectionComments[$sectionName] += $pendingComments
                    Write-Verbose "Assigned $($pendingComments.Count) comment(s) to first section [$sectionName]"
                    $pendingComments = @()
                }
            }

            # Check for duplicate section
            if ($result.Contains($sectionName)) {
                Write-ScriptWarning "Line ${lineNumber}: Duplicate section '[$sectionName]' found. Values will be merged."
            } else {
                $result[$sectionName] = [ordered]@{}
                $seenKeys[$sectionName] = @{}
            }

            $section = $sectionName
            $lastKey = $null  # Reset last key for new section
            Write-Verbose "Line ${lineNumber}: Found section [$sectionName]"

            # Initialize tracking for this section
            if (-not $sectionArrayItems.Contains($sectionName)) {
                $sectionArrayItems[$sectionName] = New-Object System.Collections.ArrayList
                $sectionHasKeyValue[$sectionName] = $false
            }

            return
        }

        # Key-value pair: Key=Value
        # More restrictive key validation - alphanumeric, spaces, underscores, hyphens, dots
        if ($line -match '^([A-Za-z0-9_\-\.\s]+?)\s*=\s*(.*)$') {
            $key = $matches[1].Trim()
            $rawValue = $matches[2].Trim()

            # Validate key
            if ($key -eq '') {
                Write-ScriptWarning "Line ${lineNumber}: Empty key name found"
                return
            }

            # Additional key validation - no leading/trailing dots or hyphens
            if ($key -match '^[\.\-]|[\.\-]$') {
                Write-ScriptWarning "Line ${lineNumber}: Invalid key format (leading/trailing dots or hyphens): '$key'"
                return
            }

            # Handle keys before any section
            if (-not $section) {
                if ($DefaultSection) {
                    Write-Verbose "Line ${lineNumber}: Key '$key' found before any section, using default section '$DefaultSection'"
                    $section = $DefaultSection
                    if (-not $result.Contains($section)) {
                        $result[$section] = [ordered]@{}
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

            # Handle null type for verbose logging
            $typeName = if ($null -eq $typedValue) { "Null" } else { $typedValue.GetType().Name }
            Write-Verbose "Line ${lineNumber}: [$section] $key = $rawValue (Type: $typeName)"

            # Store pending comments for this key (leading comments)
            if ($PreserveComments -and $pendingComments.Count -gt 0) {
                $commentKey = "${section}.${key}"
                $comments[$commentKey] = $pendingComments
                $pendingComments = @()
                Write-Verbose "Assigned $($comments[$commentKey].Count) leading comment(s) to key [$section].$key"
            }

            $result[$section][$key] = $typedValue
            $sectionHasKeyValue[$section] = $true
            $lastKey = $key  # Track this key for potential trailing comments
            return
        }

        # Line didn't match key=value pattern
        # If we're in a section, store as array item (for CSV-like sections)
        if ($section) {
            Write-Verbose "Line ${lineNumber}: Storing non-standard line in section '[$section]' as array item"
            $null = $sectionArrayItems[$section].Add($line)
            return
        }

        # No section context, warn about unparseable line
        Write-ScriptWarning "Line ${lineNumber}: Unable to parse line: $line"
    }
} catch {
    throw "Error reading INF file at line ${lineNumber}: $_"
}

# Check if we encountered any errors in strict mode
if ($StrictMode -and $script:HasErrors) {
    throw "Processing failed due to errors (StrictMode enabled)"
}

# Close any remaining commented section block
if ($PreserveComments -and $inCommentedSectionBlock -and $currentCommentedBlock -ne $null) {
    $null = $commentedSectionBlocks.Add($currentCommentedBlock)
    Write-Verbose "Closed final commented section block [$($currentCommentedBlock.SectionName)] with $($currentCommentedBlock.Comments.Count) lines"
}

# Handle any remaining pending comments - assign to last key or section
if ($PreserveComments -and $pendingComments.Count -gt 0 -and $section) {
    if ($lastKey) {
        # Assign to the last key (trailing comments)
        $commentKey = "${section}.${lastKey}"
        if (-not $trailingComments.Contains($commentKey)) {
            $trailingComments[$commentKey] = @()
        }
        $trailingComments[$commentKey] += $pendingComments
        Write-Verbose "Assigned $($pendingComments.Count) trailing comment(s) to last key [$section].$lastKey"
    } else {
        # No keys in section, assign to section itself
        if (-not $sectionComments.Contains($section)) {
            $sectionComments[$section] = @()
        }
        $sectionComments[$section] += $pendingComments
        Write-Verbose "Assigned $($pendingComments.Count) trailing comment(s) to section [$section]"
    }
    $pendingComments = @()
}

# Process sections with array items
# Use array copy to avoid modification during enumeration
foreach ($sectionName in @($sectionArrayItems.Keys)) {
    if ($sectionArrayItems[$sectionName].Count -gt 0) {
        # If section has NO key=value pairs, make it a pure array
        if (-not $sectionHasKeyValue[$sectionName]) {
            $result[$sectionName] = @($sectionArrayItems[$sectionName])
            Write-Verbose "Section [$sectionName] converted to array with $($sectionArrayItems[$sectionName].Count) items"
        }
        # If section has BOTH key=value pairs and array items, add as _items property
        else {
            if (-not $result.Contains($sectionName)) {
                $result[$sectionName] = [ordered]@{}
            }
            $result[$sectionName]['_items'] = @($sectionArrayItems[$sectionName])
            Write-Verbose "Added $($sectionArrayItems[$sectionName].Count) array items to section [$sectionName] under '_items'"
        }
    }
}

# Check if any data was parsed
if ($result.Count -eq 0) {
    Write-Warning "No sections or data found in INF file"
}

# Validate section count
if ($result.Count -gt $MaxSections) {
    throw "Number of sections ($($result.Count)) exceeds maximum allowed ($MaxSections)"
}

# Convert to JSON or JSONC
if ($PreserveComments) {
    Write-Verbose "Generating JSONC output with preserved comments"
    try {
        $jsonOutput = ConvertTo-JSONC -Data $result -Comments $comments -SectionComments $sectionComments -TrailingComments $trailingComments -CommentedSectionBlocks $commentedSectionBlocks -Depth $Depth
    } catch {
        throw "Error converting to JSONC: $_"
    }
} else {
    Write-Verbose "Generating standard JSON output"
    try {
        $jsonOutput = $result | ConvertTo-Json -Depth $Depth -Compress:$false

        # Check if JSON might be truncated due to depth limit
        if ($jsonOutput -match 'System\.Collections' -or ($Depth -lt 5 -and $result.Count -gt 10)) {
            Write-Warning "JSON output may be truncated due to depth limit. Consider increasing -Depth parameter (current: $Depth)"
        }
    } catch {
        throw "Error converting to JSON: $_"
    }
}

# Determine output file path
if (-not $OutputPath) {
    # Generate output path from input path (same location, .json or .jsonc extension)
    $infFileInfo = Get-Item -LiteralPath $InfPath
    $extension = if ($PreserveComments) { ".jsonc" } else { ".json" }
    $outputFileName = [System.IO.Path]::GetFileNameWithoutExtension($infFileInfo.Name) + $extension
    $OutputPath = Join-Path $infFileInfo.DirectoryName $outputFileName
    Write-Verbose "Output path not specified, using: $OutputPath"
}

# Validate output path safety
try {
    $null = Test-PathSafety -Path $OutputPath -PathType "Output"
} catch {
    throw $_
}

# Ensure output directory exists
$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir -PathType Container)) {
    try {
        $null = New-Item -Path $outputDir -ItemType Directory -Force -ErrorAction Stop
        Write-Verbose "Created output directory: $outputDir"
    } catch {
        throw "Cannot create output directory '$outputDir': $_"
    }
}

# Validate output directory is writable
if ($outputDir) {
    try {
        $null = Test-DirectoryWritable -DirectoryPath $outputDir
    } catch {
        throw $_
    }
}

# Check if output file exists and handle -Force
if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
    if ($PSCmdlet.ShouldProcess($OutputPath, "Overwrite existing file")) {
        # Continue with write
    } else {
        Write-Warning "Output file exists and -Force not specified. Use -Force to overwrite."
        return
    }
}

# Write JSON to file
try {
    if ($PSCmdlet.ShouldProcess($OutputPath, "Write JSON output")) {
        $jsonOutput | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
        Write-Verbose "JSON file written to: $OutputPath"
        Write-Verbose "Output file size: $([math]::Round((Get-Item -LiteralPath $OutputPath).Length / 1KB, 2)) KB"
    } else {
        # WhatIf mode - return early without accessing file
        Write-Verbose "WhatIf mode: Conversion would have been successful"
        return [PSCustomObject]@{
            Success = $true
            SourceFile = $InfPath
            SourceFileSizeKB = [math]::Round($fileInfo.Length / 1KB, 2)
            OutputFile = $OutputPath
            OutputFileSizeKB = 0
            SectionsProcessed = $result.Count
            LinesProcessed = $lineNumber
            Warnings = $script:WarningCount
            Errors = "WhatIf mode - no file written"
            ConversionTime = (Get-Date)
        }
    }
} catch {
    throw "Error writing JSON file to '$OutputPath': $_"
}

Write-Verbose "Conversion completed successfully"
Write-Verbose "Sections processed: $($result.Count)"
Write-Verbose "Lines processed: $lineNumber"
Write-Verbose "Warnings: $script:WarningCount"

Write-Host "Successfully converted '$InfPath' to '$OutputPath'" -ForegroundColor Green

# Return summary object
return [PSCustomObject]@{
    Success = $true
    SourceFile = $InfPath
    SourceFileSizeKB = [math]::Round($fileInfo.Length / 1KB, 2)
    OutputFile = $OutputPath
    OutputFileSizeKB = [math]::Round((Get-Item -LiteralPath $OutputPath).Length / 1KB, 2)
    SectionsProcessed = $result.Count
    LinesProcessed = $lineNumber
    Warnings = $script:WarningCount
    Errors = if ($script:HasErrors) { "Errors encountered in StrictMode" } else { "None" }
    ConversionTime = (Get-Date)
}
