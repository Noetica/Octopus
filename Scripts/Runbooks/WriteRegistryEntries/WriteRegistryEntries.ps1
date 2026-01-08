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

.EXAMPLE
    .\WriteRegistryEntries.ps1 -RegFilePath "C:\exports\settings.reg"
    Applies all registry entries from settings.reg to the registry.

.EXAMPLE
    .\WriteRegistryEntries.ps1 -RegFilePath "C:\exports\settings.reg" -WhatIf
    Shows what registry changes would be made without applying them.

.NOTES
    Author: Created for Octopus project
    Version: 1.0

    Requires administrative privileges for writing to HKEY_LOCAL_MACHINE.
    Run PowerShell as Administrator when modifying machine-level registry keys.

    The following parameters are automatically provided by [CmdletBinding(SupportsShouldProcess)]:
    
    -WhatIf
        Shows what changes would be made without actually applying them.
    
    -Confirm
        Prompts for confirmation before applying each registry change.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidatePattern('\.reg$', ErrorMessage = "The file must have a .reg extension")]
    [ValidateNotNullOrEmpty()]
    [string]$RegFilePath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Unicode', 'UTF8', 'UTF16', 'ASCII', 'Default')]
    [string]$Encoding = 'Unicode',

    [Parameter(Mandatory = $false)]
    [string]$LogFilePath
)

Write-Output "The script is running from: $PSScriptRoot"
. "$PSScriptRoot\utils\file-logger.ps1"
. "$PSScriptRoot\utils\control-scm.ps1"

if ($PSCmdlet.ShouldProcess('XChange service', 'Stop')) {
    Write-Output "Stopping XChange"
    Use-SCM -target 'XChange' -operation 'Stop'
}

#region Helper Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes a log entry with timestamp and log level.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $false)]
        [string]$LogFile
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"

    # Write to console based on log level
    switch ($Level) {
        'ERROR'   { Write-Verbose $logEntry -Verbose }
        'WARNING' { Write-Verbose $logEntry -Verbose }
        'INFO'    { Write-Verbose $logEntry }
        'DEBUG'   { Write-Verbose $logEntry }
    }

    # Write to log file if specified
    if ($LogFile) {
        try {
            Add-Content -Path $LogFile -Value $logEntry -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $($_.Exception.Message)"
        }
    }
}

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
                Write-Log -Message "Creating registry key: $KeyPath" -Level 'INFO' -LogFile $script:LogFilePath
                $null = New-Item -Path $psPath -Force -ErrorAction Stop
                Write-Host "  Created key: $KeyPath" -ForegroundColor Green
                Write-Log -Message "Successfully created registry key: $KeyPath" -Level 'INFO' -LogFile $script:LogFilePath
            }
            catch {
                Write-Error "Failed to create registry key '$KeyPath': $($_.Exception.Message)"
                Write-Log -Message "Failed to create registry key '$KeyPath': $($_.Exception.Message)" -Level 'ERROR' -LogFile $script:LogFilePath
                Write-Log -Message "Exception details: $($_.Exception.ToString())" -Level 'ERROR' -LogFile $script:LogFilePath
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
            Write-Log -Message "Setting registry value: $KeyPath\$displayName = $displayValue ($ValueType)" -Level 'INFO' -LogFile $script:LogFilePath
            Set-ItemProperty -LiteralPath $psPath -Name $ValueName -Value $ValueData -Type $valueKind -Force -ErrorAction Stop
            Write-Host "  Set value: $displayName = $displayValue ($ValueType)" -ForegroundColor Cyan
            Write-Log -Message "Successfully set registry value: $KeyPath\$displayName" -Level 'INFO' -LogFile $script:LogFilePath
            return $true
        }
        catch {
            Write-Error "Failed to set registry value '$displayName' in '$KeyPath': $($_.Exception.Message)"
            Write-Error "Exception details: $($_.Exception.ToString())"
            Write-Log -Message "Failed to set registry value '$displayName' in '$KeyPath': $($_.Exception.Message)" -Level 'ERROR' -LogFile $script:LogFilePath
            Write-Log -Message "Exception details: $($_.Exception.ToString())" -Level 'ERROR' -LogFile $script:LogFilePath
            if ($_.Exception.InnerException) {
                Write-Error "Inner exception: $($_.Exception.InnerException.ToString())"
                Write-Log -Message "Inner exception: $($_.Exception.InnerException.ToString())" -Level 'ERROR' -LogFile $script:LogFilePath
            }
            return $false
        }
    }

    return $true
}

#endregion

#region Main Script

# Initialize script-level log file path variable
$script:LogFilePath = $LogFilePath

# Log script start
Write-Log -Message "======================================" -Level 'INFO' -LogFile $script:LogFilePath
Write-Log -Message "WriteRegistryEntries.ps1 - Script Started" -Level 'INFO' -LogFile $script:LogFilePath
Write-Log -Message "Parameters: RegFilePath=$RegFilePath, Encoding=$Encoding, LogFilePath=$LogFilePath" -Level 'INFO' -LogFile $script:LogFilePath
Write-Log -Message "Executed by: $env:USERNAME on $env:COMPUTERNAME" -Level 'INFO' -LogFile $script:LogFilePath
Write-Log -Message "======================================" -Level 'INFO' -LogFile $script:LogFilePath

# Validate input file exists
if (-not (Test-Path -LiteralPath $RegFilePath)) {
    Write-Error "Registry file not found: $RegFilePath"
    Write-Log -Message "Registry file not found: $RegFilePath" -Level 'ERROR' -LogFile $script:LogFilePath
    exit 1
}

Write-Host "Reading registry file: $RegFilePath" -ForegroundColor Yellow
Write-Log -Message "Reading registry file: $RegFilePath" -Level 'INFO' -LogFile $script:LogFilePath
Write-Host ""

# Read file with appropriate encoding
try {
    Write-Log -Message "Reading file with encoding: $Encoding" -Level 'DEBUG' -LogFile $script:LogFilePath
    $lines = Get-Content -LiteralPath $RegFilePath -Encoding $Encoding -ErrorAction Stop
    Write-Log -Message "Successfully read $($lines.Count) lines from file" -Level 'INFO' -LogFile $script:LogFilePath
}
catch {
    Write-Error "Failed to read registry file: $($_.Exception.Message)"
    Write-Error "Exception details: $($_.Exception.ToString())"
    Write-Log -Message "Failed to read registry file: $($_.Exception.Message)" -Level 'ERROR' -LogFile $script:LogFilePath
    Write-Log -Message "Exception details: $($_.Exception.ToString())" -Level 'ERROR' -LogFile $script:LogFilePath
    if ($_.Exception.InnerException) {
        Write-Error "Inner exception: $($_.Exception.InnerException.ToString())"
        Write-Log -Message "Inner exception: $($_.Exception.InnerException.ToString())" -Level 'ERROR' -LogFile $script:LogFilePath
    }
    exit 1
}

# Validate file header
$headerFound = $false
foreach ($line in $lines) {
    if ($line -match '^Windows Registry Editor') {
        $headerFound = $true
        Write-Log -Message "Found valid registry file header: $line" -Level 'INFO' -LogFile $script:LogFilePath
        break
    }
}

if (-not $headerFound) {
    Write-Error "Invalid registry file format. Missing 'Windows Registry Editor' header."
    Write-Log -Message "Invalid registry file format. Missing 'Windows Registry Editor' header." -Level 'ERROR' -LogFile $script:LogFilePath
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
        Write-Log -Message "Processing registry key [$keyCount]: $currentKey" -Level 'INFO' -LogFile $script:LogFilePath
        continue
    }

    # Check if this is a continuation line (hex data that continues from previous line)
    # Continuation lines are indented and contain hex pairs, and the previous line ended with backslash
    $isContinuation = $trimmedLine -match '^[0-9A-Fa-f]{2}(?:,[0-9A-Fa-f]{2})*' -and $null -ne $pendingValueName

    if ($isContinuation) {
        # Remove trailing backslash if present
        $continuationData = $trimmedLine -replace '\\$', ''
        $pendingHexData += $continuationData
        Write-Log -Message "Appending continuation data for '$pendingValueName'" -Level 'DEBUG' -LogFile $script:LogFilePath
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
    # Pattern matches either: "quoted name"=value OR unquoted_name=value OR @=value
    if ($trimmedLine -match '^(?:"([^"]+)"|([^=]+?))\s*=\s*(.+)$') {
        # Value name is in either $matches[1] (quoted) or $matches[2] (unquoted)
        $valueName = if ($matches[1]) { $matches[1] } else { $matches[2].Trim() }
        $valueData = $matches[3].Trim()

        # Handle default value
        if ($valueName -eq '@') {
            $valueName = '(Default)'
        }

        # Skip if no current key is set
        if ($null -eq $currentKey) {
            Write-Warning "Skipping value '$valueName' - no registry key context"
            Write-Log -Message "Skipping value '$valueName' - no registry key context" -Level 'WARNING' -LogFile $script:LogFilePath
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
        elseif ($valueData -match '^hex\(b\):(.+?)(?:\\)?$') {
            # REG_QWORD (might be multi-line)
            $pendingValueName = $valueName
            $pendingValueType = 'qword'
            $pendingHexData = $matches[1]
        }
        elseif ($valueData -match '^hex\(2\):(.+?)(?:\\)?$') {
            # REG_EXPAND_SZ (might be multi-line)
            $pendingValueName = $valueName
            $pendingValueType = 'expand_sz'
            $pendingHexData = $matches[1]
        }
        elseif ($valueData -match '^hex\(7\):(.+?)(?:\\)?$') {
            # REG_MULTI_SZ (might be multi-line)
            $pendingValueName = $valueName
            $pendingValueType = 'multi_sz'
            $pendingHexData = $matches[1]
        }
        elseif ($valueData -match '^hex:(.+?)(?:\\)?$') {
            # REG_BINARY (might be multi-line)
            $pendingValueName = $valueName
            $pendingValueType = 'binary'
            $pendingHexData = $matches[1]
        }
        else {
            Write-Warning "Unknown value format for '$valueName': $valueData"
            Write-Log -Message "Unknown value format for '$valueName': $valueData" -Level 'WARNING' -LogFile $script:LogFilePath
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

# Log summary
Write-Log -Message "======================================" -Level 'INFO' -LogFile $script:LogFilePath
Write-Log -Message "Registry Import Summary" -Level 'INFO' -LogFile $script:LogFilePath
Write-Log -Message "Keys processed: $keyCount" -Level 'INFO' -LogFile $script:LogFilePath
Write-Log -Message "Values succeeded: $successCount" -Level 'INFO' -LogFile $script:LogFilePath
Write-Log -Message "Values failed: $errorCount" -Level $(if ($errorCount -gt 0) { 'ERROR' } else { 'INFO' }) -LogFile $script:LogFilePath
Write-Log -Message "======================================" -Level 'INFO' -LogFile $script:LogFilePath

if ($errorCount -gt 0) {
    Write-Warning "Some registry entries failed to apply. Run as Administrator if modifying HKEY_LOCAL_MACHINE keys."
    Write-Log -Message "Script completed with errors. Some registry entries failed to apply." -Level 'ERROR' -LogFile $script:LogFilePath
    Write-Log -Message "WriteRegistryEntries.ps1 - Script Ended with Exit Code 1" -Level 'ERROR' -LogFile $script:LogFilePath
    exit 1
}

Write-Host "Registry entries applied successfully." -ForegroundColor Green
Write-Log -Message "Registry entries applied successfully." -Level 'INFO' -LogFile $script:LogFilePath
Write-Log -Message "WriteRegistryEntries.ps1 - Script Ended with Exit Code 0" -Level 'INFO' -LogFile $script:LogFilePath

Write-Output "Starting VoicePlatform"
Use-SCM -target 'VoicePlatform' -operation 'Start'
exit 0

#endregion
