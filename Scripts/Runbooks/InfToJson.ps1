# Local testing:
# $infPath = [System.IO.Path]::Combine($env:SystemDrive + "\", "Synthesys", "Etc", "Synthesys.inf")

# Octopus runner:
$infPath = $OctopusParameters["Noetica.Inf"]

if (-not $infPath -or -not (Test-Path $infPath)) {
    throw "INF file not found at: $infPath"
}
$result = @{}
$section = $null
$seenKeys = @{}  # Track keys per section for duplicate detection

Get-Content -Path $infPath | ForEach-Object {
    $line = $_.Trim()

    # Skip empty lines and full-line comments
    if ($line -eq '' -or $line -match '^;') { return }

    # Section header
    if ($line -match '^\[(.+)\]$') {
        $section = $matches[1]
        $result[$section] = @{}
        $seenKeys[$section] = @{}
    }
    # Key-value pair
    elseif ($line -match '^([^=;]+)=(.*)$') {
        # Check if we have a section defined
        if (-not $section) {
            Write-Warning "Key-value pair found before any section header: $line"
            return
        }
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()

        # Check for duplicate keys in the same section
        if ($seenKeys[$section].ContainsKey($key)) {
            Write-Warning "Duplicate key '$key' found in section '[$section]'. Previous value will be overwritten."
        }
        $seenKeys[$section][$key] = $true

        # Remove inline comments
        if ($value -match '^([^;]+?)\s*;') {
            $value = $matches[1].Trim()
        }

        # Remove trailing commas
        $value = $value.TrimEnd(',').Trim()

        # Type conversion
        if ($value -imatch '^(true|false)$') {
            # Boolean conversion (case-insensitive)
            $value = $value -ieq 'true'
        }
        # Decimal/float/scientific notation conversion (must have decimal or exponent)
        elseif ($value -match '^-?\d+\.\d+([eE][+-]?\d+)?$' -or $value -match '^-?\d+([eE][+-]?\d+)$') {
            $value = [double]$value
        }
        # Integer conversion (exclude leading zeros)
        elseif ($value -match '^-?\d+$' -and $value -notmatch '^-?0\d+') {
            $value = [int64]$value
        }
        elseif ($value -match '^\[.*\]$|^\{.*\}$') {
            # Try to parse JSON objects/arrays
            try {
                $value = $value | ConvertFrom-Json
            }
            catch {
                # Keep as string if JSON parsing fails
            }
        }

        $result[$section][$key] = $value
    }
}

# Convert to JSON with depth limit to handle nested structures
# Note: -Depth 10 limits nesting depth. Deeply nested JSON structures (>10 levels)
# in INF values will be truncated. Increase depth if needed for complex structures.
$result | ConvertTo-Json -Depth 10
