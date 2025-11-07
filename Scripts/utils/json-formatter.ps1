<#
.SYNOPSIS
    Reusable JSON formatting utilities for PowerShell scripts.

.DESCRIPTION
    Provides functions for converting PowerShell objects to JSON/JSONC format
    with custom formatting, proper indentation, and optional comments.

    This utility can be dot-sourced into any PowerShell script:
        . "$PSScriptRoot\utils\json-formatter.ps1"

.NOTES
    Author: Octopus Deploy
    Version: 1.0.0
    Requires: PowerShell 5.1 or higher

.EXAMPLE
    # Dot-source the utility
    . "$PSScriptRoot\utils\json-formatter.ps1"

    # Use the formatter
    $data = @{ Name = "Test"; Value = 123 }
    $json = ConvertTo-CustomJson -Data $data
    $json | Out-File "output.json"

.EXAMPLE
    # Format with JSONC comments
    $headerComments = @(
        "// Configuration Export",
        "// Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        ""
    )
    $json = ConvertTo-CustomJson -Data $data -HeaderComments $headerComments
#>

#region Public Functions

function ConvertTo-CustomJson {
    <#
    .SYNOPSIS
        Converts a PowerShell object to JSON/JSONC with custom formatting.

    .DESCRIPTION
        Converts hashtables, ordered dictionaries, and other objects to JSON
        with 2-space indentation, proper escaping, and optional header comments.

    .PARAMETER Data
        The data to convert to JSON. Supports hashtables, ordered dictionaries,
        arrays, and primitive types.

    .PARAMETER HeaderComments
        Array of comment lines to add at the top of the output.
        Each line should start with "//".

    .PARAMETER InlineKeyComments
        Hashtable of key names to comment arrays for inline comments.
        Comments are added before the key in the JSON output.
        Example: @{ "_metadata" = @("Registry Key Metadata"); "_subkeys" = @("Subkeys") }

    .PARAMETER IndentLevel
        Starting indentation level. Typically 0 for root level.
        Default: 0

    .OUTPUTS
        Array of strings representing JSON lines.

    .EXAMPLE
        $data = @{ Name = "John"; Age = 30 }
        $lines = ConvertTo-CustomJson -Data $data
        $json = $lines -join "`n"

    .EXAMPLE
        $comments = @("// My Config", "// Date: 2024-01-01", "")
        $lines = ConvertTo-CustomJson -Data $config -HeaderComments $comments
        $json = $lines -join "`n"

    .EXAMPLE
        $inlineComments = @{ "_metadata" = @("Registry Key Metadata"); "_subkeys" = @("Subkeys") }
        $lines = ConvertTo-CustomJson -Data $registryData -InlineKeyComments $inlineComments
        $json = $lines -join "`n"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Data,

        [Parameter(Mandatory = $false)]
        [string[]]$HeaderComments,

        [Parameter(Mandatory = $false)]
        [hashtable]$InlineKeyComments,

        [Parameter(Mandatory = $false)]
        [int]$IndentLevel = 0
    )

    $indent = "  " * $IndentLevel
    $nextIndent = "  " * ($IndentLevel + 1)
    $lines = @()

    # Add header comments at root level
    if ($IndentLevel -eq 0 -and $HeaderComments -and $HeaderComments.Count -gt 0) {
        $lines += $HeaderComments
    }

    $lines += "$indent{"

    if ($Data -is [System.Collections.Specialized.OrderedDictionary] -or $Data -is [hashtable]) {
        $keys = @($Data.Keys)
        $keyCount = $keys.Count

        for ($i = 0; $i -lt $keyCount; $i++) {
            $key = $keys[$i]
            $value = $Data[$key]
            $isLast = ($i -eq $keyCount - 1)

            # Add inline comments for specific keys if provided
            if ($InlineKeyComments -and $InlineKeyComments.ContainsKey($key)) {
                foreach ($comment in $InlineKeyComments[$key]) {
                    $lines += "$nextIndent// $comment"
                }
            }

            $escapedKey = $key -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`r", '\r' -replace "`t", '\t'

            if ($value -is [System.Collections.Specialized.OrderedDictionary] -or $value -is [hashtable]) {
                $lines += "$nextIndent`"$escapedKey`": {"

                $nestedLines = ConvertTo-CustomJson -Data $value -IndentLevel ($IndentLevel + 2) -InlineKeyComments $InlineKeyComments
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

    .DESCRIPTION
        Handles type conversion for primitive values (null, bool, numbers, strings)
        to their JSON equivalents with proper formatting and escaping.

    .PARAMETER Value
        The value to convert to JSON format.

    .OUTPUTS
        String containing the JSON representation of the value.

    .EXAMPLE
        ConvertTo-JsonValue -Value $null
        # Returns: "null"

    .EXAMPLE
        ConvertTo-JsonValue -Value $true
        # Returns: "true"

    .EXAMPLE
        ConvertTo-JsonValue -Value "Hello`nWorld"
        # Returns: "\"Hello\\nWorld\""
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $Value
    )

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

    .DESCRIPTION
        Normalizes JSON output from ConvertTo-Json to use consistent 2-space indentation
        instead of PowerShell's default 4-space indentation. Also cleans up excessive
        whitespace after colons.

    .PARAMETER Json
        The JSON string to reformat.

    .OUTPUTS
        String containing the reformatted JSON with consistent 2-space indentation.

    .EXAMPLE
        $json = $data | ConvertTo-Json -Depth 10
        $formatted = Format-JsonIndent -Json $json

    .EXAMPLE
        $json | Format-JsonIndent | Out-File "output.json"
    #>
    [CmdletBinding()]
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

#endregion
