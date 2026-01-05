<#
.SYNOPSIS
    Writes Windows Registry entries from a .reg file to the registry.

.DESCRIPTION
    Parses a Windows Registry export file (.reg format) and applies the entries
    to the Windows Registry. Supports all standard registry value types including
    REG_SZ, REG_DWORD, REG_QWORD, REG_BINARY, REG_EXPAND_SZ, and REG_MULTI_SZ.

    This script reads the exported registry values and writes them to their
    original locations as specified in the .reg file.

.PARAMETER RegFilePath
    Path to the .reg file containing registry entries to apply.

.PARAMETER Encoding
    File encoding to use when reading the .reg file. Default: Unicode

.PARAMETER WhatIf
    Shows what changes would be made without actually applying them.

.PARAMETER Confirm
    Prompts for confirmation before applying each registry change.

.PARAMETER Force
    Suppresses confirmation prompts and overwrites existing values without warning.

.EXAMPLE
    .\WriteRegistryEntries.ps1 -RegFilePath "C:\exports\settings.reg"
    Applies all registry entries from settings.reg to the registry.

.EXAMPLE
    .\WriteRegistryEntries.ps1 -RegFilePath "C:\exports\settings.reg" -WhatIf
    Shows what registry changes would be made without applying them.

.EXAMPLE
    .\WriteRegistryEntries.ps1 -RegFilePath "C:\exports\settings.reg" -Force
    Applies registry entries without prompting for confirmation.

.NOTES
    Author: Created for Octopus project
    Version: 1.0

    Requires administrative privileges for writing to HKEY_LOCAL_MACHINE.
    Run PowerShell as Administrator when modifying machine-level registry keys.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RegFilePath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Unicode', 'UTF8', 'UTF16', 'ASCII', 'Default')]
    [string]$Encoding = 'Unicode',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

#region Helper Functions

function ConvertFrom-RegHexString {
    <#
    .SYNOPSIS
        Converts registry hex string to byte array.
    #>
    param([string]$HexString)

    # Remove whitespace, commas, and backslashes
    $cleanHex = $HexString -replace '[\s,\\]', ''

    # Convert hex pairs to bytes
    $bytes = [System.Collections.ArrayList]@()
    for ($i = 0; $i -lt $cleanHex.Length; $i += 2) {
        if ($i + 1 -lt $cleanHex.Length) {
            $null = $bytes.Add([Convert]::ToByte($cleanHex.Substring($i, 2), 16))
        }
    }

    return [byte[]]$bytes.ToArray()
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

function Convert-RegPathToPSDrive {
    <#
    .SYNOPSIS
        Converts a registry path to PowerShell provider path.
    #>
    param([string]$RegPath)

    $mappings = @{
        'HKEY_LOCAL_MACHINE' = 'HKLM:'
        'HKEY_CURRENT_USER'  = 'HKCU:'
        'HKEY_CLASSES_ROOT'  = 'HKCR:'
        'HKEY_USERS'         = 'HKU:'
        'HKEY_CURRENT_CONFIG' = 'HKCC:'
    }

    foreach ($key in $mappings.Keys) {
        if ($RegPath.StartsWith($key)) {
            return $RegPath.Replace($key, $mappings[$key])
        }
    }

    return $RegPath
}

function Get-RegistryValueKind {
    <#
    .SYNOPSIS
        Returns the appropriate RegistryValueKind for a value type.
    #>
    param([string]$ValueType)

    switch ($ValueType) {
        'string'    { return [Microsoft.Win32.RegistryValueKind]::String }
        'dword'     { return [Microsoft.Win32.RegistryValueKind]::DWord }
        'qword'     { return [Microsoft.Win32.RegistryValueKind]::QWord }
        'binary'    { return [Microsoft.Win32.RegistryValueKind]::Binary }
        'expand_sz' { return [Microsoft.Win32.RegistryValueKind]::ExpandString }
        'multi_sz'  { return [Microsoft.Win32.RegistryValueKind]::MultiString }
        default     { return [Microsoft.Win32.RegistryValueKind]::String }
    }
}

function Process-PendingValue {
    <#
    .SYNOPSIS
        Processes accumulated hex data for a registry value.
    #>
    param(
        [string]$ValueType,
        [string]$HexData
    )

    $bytes = ConvertFrom-RegHexString -HexString $HexData

    switch ($ValueType) {
        'qword' {
            if ($bytes.Count -ge 8) {
                return [BitConverter]::ToInt64($bytes, 0)
            }
            return [long]0
        }
        'expand_sz' {
            if ($bytes.Count -gt 0) {
                return [System.Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0)
            }
            return ""
        }
        'multi_sz' {
            if ($bytes.Count -gt 0) {
                $stringValue = [System.Text.Encoding]::Unicode.GetString($bytes)
                $strings = [System.Collections.ArrayList]@()
                $splitResult = $stringValue -split [char]0
                foreach ($str in $splitResult) {
                    if ($str -ne '') {
                        $null = $strings.Add($str)
                    }
                }
                return [string[]]$strings.ToArray()
            }
            return @()
        }
        'binary' {
            return $bytes
        }
        default {
            return $bytes
        }
    }
}

function Write-RegistryValue {
    <#
    .SYNOPSIS
        Writes a single registry value.
    #>
    param(
        [string]$KeyPath,
        [string]$ValueName,
        $ValueData,
        [string]$ValueType
    )

    $psPath = Convert-RegPathToPSDrive -RegPath $KeyPath
    $valueKind = Get-RegistryValueKind -ValueType $ValueType

    # Create the registry key if it doesn't exist
    if (-not (Test-Path -LiteralPath $psPath)) {
        if ($PSCmdlet.ShouldProcess($psPath, "Create registry key")) {
            try {
                $null = New-Item -Path $psPath -Force -ErrorAction Stop
                Write-Host "  Created key: $KeyPath" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to create registry key '$KeyPath': $($_.Exception.Message)"
                return $false
            }
        }
    }

    # Write the registry value
    $displayValue = if ($ValueData -is [byte[]]) {
        "hex:$($ValueData | ForEach-Object { $_.ToString('x2') } | Join-String -Separator ',')"
    } elseif ($ValueData -is [array]) {
        "[" + ($ValueData -join ", ") + "]"
    } else {
        $ValueData
    }

    $displayName = if ($ValueName -eq '(Default)') { '(Default)' } else { $ValueName }

    if ($PSCmdlet.ShouldProcess("$KeyPath\$displayName", "Set registry value to '$displayValue' ($ValueType)")) {
        try {
            Set-ItemProperty -LiteralPath $psPath -Name $ValueName -Value $ValueData -Type $valueKind -Force -ErrorAction Stop
            Write-Host "  Set value: $displayName = $displayValue ($ValueType)" -ForegroundColor Cyan
            return $true
        }
        catch {
            Write-Error "Failed to set registry value '$displayName' in '$KeyPath': $($_.Exception.Message)"
            return $false
        }
    }

    return $true
}

#endregion

#region Main Script

# Validate input file exists
if (-not (Test-Path -LiteralPath $RegFilePath)) {
    Write-Error "Registry file not found: $RegFilePath"
    exit 1
}

Write-Host "Reading registry file: $RegFilePath" -ForegroundColor Yellow
Write-Host ""

# Read file with appropriate encoding
try {
    $lines = Get-Content -LiteralPath $RegFilePath -Encoding $Encoding -ErrorAction Stop
}
catch {
    Write-Error "Failed to read registry file: $($_.Exception.Message)"
    exit 1
}

# Validate file header
$headerFound = $false
foreach ($line in $lines) {
    if ($line -match '^Windows Registry Editor') {
        $headerFound = $true
        break
    }
}

if (-not $headerFound) {
    Write-Error "Invalid registry file format. Missing 'Windows Registry Editor' header."
    exit 1
}

# Parse and apply registry entries
$currentKey = $null
$pendingValueName = $null
$pendingValueType = $null
$pendingHexData = ""
$successCount = 0
$errorCount = 0
$keyCount = 0

foreach ($line in $lines) {
    $trimmedLine = $line.Trim()

    # Skip header and empty lines
    if ($trimmedLine -match '^Windows Registry Editor' -or [string]::IsNullOrWhiteSpace($trimmedLine)) {
        continue
    }

    # Skip comments
    if ($trimmedLine.StartsWith(';')) {
        continue
    }

    # Handle registry key [HKEY_...]
    if ($trimmedLine -match '^\[(.+)\]$') {
        # Process any pending value first
        if ($null -ne $pendingValueName -and $null -ne $currentKey) {
            $processedValue = Process-PendingValue -ValueType $pendingValueType -HexData $pendingHexData
            if (Write-RegistryValue -KeyPath $currentKey -ValueName $pendingValueName -ValueData $processedValue -ValueType $pendingValueType) {
                $successCount++
            } else {
                $errorCount++
            }
            $pendingValueName = $null
            $pendingValueType = $null
            $pendingHexData = ""
        }

        $currentKey = $matches[1]
        $keyCount++
        Write-Host "Processing key: $currentKey" -ForegroundColor White
        continue
    }

    # Check if this is a continuation line
    $isContinuation = $trimmedLine -match '^[0-9a-fA-F,\s]+\\?$' -and $null -ne $pendingValueName

    if ($isContinuation) {
        $pendingHexData += $trimmedLine
        continue
    }

    # Process any pending value before starting a new one
    if ($null -ne $pendingValueName -and $null -ne $currentKey) {
        $processedValue = Process-PendingValue -ValueType $pendingValueType -HexData $pendingHexData
        if (Write-RegistryValue -KeyPath $currentKey -ValueName $pendingValueName -ValueData $processedValue -ValueType $pendingValueType) {
            $successCount++
        } else {
            $errorCount++
        }
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
            Write-Warning "Skipping value '$valueName' - no registry key context"
            continue
        }

        # Parse value based on type
        if ($valueData.StartsWith('"')) {
            # REG_SZ - String
            $stringValue = ConvertFrom-RegString -Value $valueData
            if (Write-RegistryValue -KeyPath $currentKey -ValueName $valueName -ValueData $stringValue -ValueType 'string') {
                $successCount++
            } else {
                $errorCount++
            }
        }
        elseif ($valueData -match '^dword:([0-9a-fA-F]+)$') {
            # REG_DWORD
            $intValue = [Convert]::ToInt32($matches[1], 16)
            if (Write-RegistryValue -KeyPath $currentKey -ValueName $valueName -ValueData $intValue -ValueType 'dword') {
                $successCount++
            } else {
                $errorCount++
            }
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
            Write-Warning "Unknown value format for '$valueName': $valueData"
        }
    }
}

# Process any remaining pending value
if ($null -ne $pendingValueName -and $null -ne $currentKey) {
    $processedValue = Process-PendingValue -ValueType $pendingValueType -HexData $pendingHexData
    if (Write-RegistryValue -KeyPath $currentKey -ValueName $pendingValueName -ValueData $processedValue -ValueType $pendingValueType) {
        $successCount++
    } else {
        $errorCount++
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Registry Import Summary" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Keys processed:     $keyCount" -ForegroundColor White
Write-Host "Values succeeded:   $successCount" -ForegroundColor Green
Write-Host "Values failed:      $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { 'Red' } else { 'White' })
Write-Host "========================================" -ForegroundColor Yellow

if ($errorCount -gt 0) {
    Write-Warning "Some registry entries failed to apply. Run as Administrator if modifying HKEY_LOCAL_MACHINE keys."
    exit 1
}

Write-Host "Registry entries applied successfully." -ForegroundColor Green
exit 0

#endregion
