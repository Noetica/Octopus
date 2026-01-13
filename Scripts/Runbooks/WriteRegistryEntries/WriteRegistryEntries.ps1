<#
.SYNOPSIS
    Writes Windows Registry entries from a .reg file to the registry.

.DESCRIPTION
    Stops the VoicePlatform service, imports registry entries from a .reg file,
    and starts the VoicePlatform service.

.PARAMETER RegFilePath
    Path to the .reg file containing registry entries to apply.

.PARAMETER WhatIf
    Shows which registry keys will be affected without making any changes.

.EXAMPLE
    .\WriteRegistryEntries.ps1 -RegFilePath "C:\exports\settings.reg"
    Stops VoicePlatform, applies all registry entries from settings.reg, and starts VoicePlatform.

.EXAMPLE
    .\WriteRegistryEntries.ps1 -RegFilePath "C:\exports\settings.reg" -WhatIf
    Displays the registry keys that would be affected without making changes.

.NOTES
    Requires administrative privileges for writing to HKEY_LOCAL_MACHINE.
    Run PowerShell as Administrator when modifying machine-level registry keys.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidatePattern('\.reg$', ErrorMessage = "The file must have a .reg extension")]
    [ValidateNotNullOrEmpty()]
    [string]$RegFilePath
)

# Source the control-scm utility (only required if not in WhatIf mode)
if (-not $WhatIfPreference) {
    $utilsPath = Join-Path $PSScriptRoot "..\..\utils"
    $scmScriptPath = Join-Path $utilsPath "control-scm.ps1"

    if (Test-Path $scmScriptPath) {
        . $scmScriptPath
    }
    else {
        Write-Error "Required utility script not found: $scmScriptPath"
        Write-Error "This script must be run from the correct location or the control-scm.ps1 utility must be available."
        exit 1
    }
}

# Function to parse and display registry keys from .reg file
function Show-RegistryKeys {
    param([string]$FilePath)
    
    # Helper function to format registry value for human reading
    function Format-RegistryValue {
        param([string]$RawValue)
        
        # String value (quoted)
        if ($RawValue -match '^"(.*)"$') {
            $stringValue = $matches[1] -replace '\\\\', '\' -replace '\\"', '"'
            return 'String: "' + $stringValue + '"'
        }
        # DWORD value
        elseif ($RawValue -match '^dword:([0-9a-fA-F]+)$') {
            $hexValue = $matches[1]
            $decValue = [Convert]::ToInt32($hexValue, 16)
            return "DWORD: $decValue (0x$hexValue)"
        }
        # Binary/hex value
        elseif ($RawValue -match '^hex(\([0-9a-fA-F]+\))?:(.+)$') {
            $typeCode = $matches[1] -replace '[()]', ''
            $hexData = $matches[2] -replace ',', ' '
            $typeName = switch ($typeCode) {
                '' { 'REG_BINARY' }
                '0' { 'REG_NONE' }
                '1' { 'REG_SZ' }
                '2' { 'REG_EXPAND_SZ' }
                '3' { 'REG_BINARY' }
                '4' { 'REG_DWORD' }
                '7' { 'REG_MULTI_SZ' }
                '8' { 'REG_RESOURCE_LIST' }
                'b' { 'REG_QWORD' }
                default { "Type $typeCode" }
            }
            
            # Try to decode as string for text types
            if ($typeCode -eq '1' -or $typeCode -eq '2' -or $typeCode -eq '7') {
                try {
                    $bytes = $hexData -split '\s+' | Where-Object { $_ } | ForEach-Object { [byte]"0x$_" }
                    $decodedString = [System.Text.Encoding]::Unicode.GetString($bytes)
                    
                    # Special handling for REG_MULTI_SZ (multiple strings separated by nulls)
                    if ($typeCode -eq '7') {
                        $nullChar = [char]0
                        $strings = $decodedString -split $nullChar | Where-Object { $_ -ne '' }
                        if ($strings) {
                            $quotedStrings = $strings | ForEach-Object { 
                                $escaped = $_ -replace '"', '""'
                                '"' + $escaped + '"'
                            }
                            $joinedStrings = $quotedStrings -join ' '
                            $newline = [System.Environment]::NewLine
                            return "$typeName (Hex): $hexData$newline      Decoded: $joinedStrings"
                        }
                    }
                    else {
                        # Single string types (REG_SZ, REG_EXPAND_SZ)
                        $nullChar = [char]0
                        $decodedString = $decodedString -replace $nullChar, ''
                        if ($decodedString) {
                            $newline = [System.Environment]::NewLine
                            return "$typeName (Hex): $hexData$newline      Decoded: " + '"' + $decodedString + '"'
                        }
                    }
                }
                catch { }
            }
            
            return "$typeName (Hex): $hexData"
        }
        # Unknown format
        else {
            return "Raw: $RawValue"
        }
    }
    
    $newline = [System.Environment]::NewLine
    Write-Output "$newline=== Registry Keys to be Modified ==="
    $content = Get-Content -LiteralPath $FilePath -Encoding Unicode -ErrorAction SilentlyContinue
    if (-not $content) {
        $content = Get-Content -LiteralPath $FilePath -Encoding UTF8
    }
    
    # Handle multi-line hex values (lines ending with \)
    $processedLines = @()
    $continuedLine = ""
    foreach ($rawLine in $content) {
        if ($continuedLine) {
            # Append continuation to previous line
            $continuedLine += $rawLine.TrimStart()
        }
        else {
            $continuedLine = $rawLine
        }
        
        # Check if line continues on next line (ends with \)
        if ($continuedLine -match '\\$') {
            # Remove trailing \ and continue
            $continuedLine = $continuedLine -replace '\\$', ''
        }
        else {
            # Line is complete
            $processedLines += $continuedLine
            $continuedLine = ""
        }
    }
    
    $keyCount = 0
    $valueCount = 0
    $newline = [System.Environment]::NewLine
    foreach ($line in $processedLines) {
        if ($line -match '^\[(.+)\]$') {
            $keyPath = $matches[1]
            Write-Output "${newline}Key: $keyPath"
            $keyCount++
        }
        elseif ($line -match '^"(.+?)"=(.+)$' -or $line -match '^@=(.+)$') {
            $valueName = if ($matches[1]) { $matches[1] } else { "(Default)" }
            $valueData = if ($matches[2]) { $matches[2] } else { $matches[1] }
            $formattedValue = Format-RegistryValue -RawValue $valueData
            Write-Output "  └─ $valueName"
            Write-Output "      $formattedValue"
            $valueCount++
        }
    }
    $newline = [System.Environment]::NewLine
    Write-Output "${newline}=== Summary ==="
    Write-Output "Total Keys: $keyCount"
    Write-Output "Total Values: $valueCount"
    Write-Output "==========================================${newline}"
}

# Validate input file exists
if (-not (Test-Path -LiteralPath $RegFilePath)) {
    Write-Error "Registry file not found: $RegFilePath"
    exit 1
}

if ($WhatIfPreference) {
    $newline = [System.Environment]::NewLine
    Write-Output "${newline}========== WhatIf Mode: Showing what would be performed =========="
}

# Stop VoicePlatform service
if ($WhatIfPreference) {
    Write-Output "WhatIf: Would stop VoicePlatform service"
} else {
    Write-Output "Stopping VoicePlatform service..."
    Use-SCM -target 'VoicePlatform' -operation 'Stop'
}

# Import registry entries
if ($WhatIfPreference) {
    Write-Output "WhatIf: Would import registry entries from: $RegFilePath"
    Show-RegistryKeys -FilePath $RegFilePath
} else {
    Write-Output "Importing registry entries from: $RegFilePath"
    try {
        $result = reg import $RegFilePath 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Output "Registry entries imported successfully."
            Write-Output ""
            Write-Output "Summary of imported registry keys:"
            Show-RegistryKeys -FilePath $RegFilePath
        } else {
            Write-Error "Failed to import registry entries. Exit code: $LASTEXITCODE"
            Write-Error $result
            exit 1
        }
    }
    catch {
        Write-Error "Failed to import registry file: $($_.Exception.Message)"
        exit 1
    }
}

# Start VoicePlatform service
if ($WhatIfPreference) {
    Write-Output "WhatIf: Would start VoicePlatform service"
    $newline = [System.Environment]::NewLine
    Write-Output "${newline}========== WhatIf Summary: No changes were made =========="
} else {
    Write-Output "Starting VoicePlatform service..."
    Use-SCM -target 'VoicePlatform' -operation 'Start'
}

Write-Output "Script completed successfully."
exit 0
