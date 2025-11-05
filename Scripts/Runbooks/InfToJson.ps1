# Local testing:
# $infPath = [System.IO.Path]::Combine($env:SystemDrive + "\", "Synthesys", "Etc", "Synthesys.inf")

# Octopus runner:
$infPath = $OctopusParameters["Noetica.Inf"]

$result = @{}
$section = $null

Get-Content -Path $infPath | ForEach-Object {
    $line = $_.Trim()
    
    # Skip empty lines and full-line comments
    if ($line -eq '' -or $line -match '^;') { return }
    
    # Section header
    if ($line -match '^\[(.+)\]$') {
        $section = $matches[1]
        $result[$section] = @{}
    }
    # Key-value pair
    elseif ($line -match '^([^=;]+)=(.*)$' -and $section) {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        
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
        elseif ($value -match '^-?\d+$' -and $value -notmatch '^-?0\d+') {
            # Integer conversion (exclude leading zeros to preserve them as strings)
            $value = [int64]$value
        }
        elseif ($value -match '^-?\d+\.\d+([eE][+-]?\d+)?$') {
            # Decimal/float/scientific notation conversion (with decimal point)
            $value = [double]$value
        }
        elseif ($value -match '^-?\d+([eE][+-]?\d+)$') {
            # Scientific notation conversion (integer part only)
            $value = [double]$value
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

$result | ConvertTo-Json -Depth 10
