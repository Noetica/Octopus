# function File-Logger {
#     param (
#         [Parameter(Mandatory = $true)] [string]$path
#     )

#     Write-Host "[Log-Module] Creating logger..."
    
#     # Define the Log function as a script block outside the hash table
#     $logFunction = {
#         param (
#             [ValidateSet('Debug', 'Info', 'Warn', 'Error', 'Critical')]
#             [Parameter(Mandatory = $false)] [string]$level = 'Info',
#             [Parameter(Mandatory = $true)] [string]$message
#         )
#         $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
#         $logItem = "[$timestamp] [$level] $message"

#         # Write-Host "[File-Logger] Received log request ---`nLevel: $level`nMessage: $message"
#         # Write-Host "[File-Logger] Setting log entry timestamp: $timestamp"
#         # Write-Host "[File-Logger] Setting line item in variable: $logItem"

#         Write-Host $message

#         try {
#             $logDirectory = Split-Path -Parent $this.filePath
#             $logFileExists = Test-Path -Path $this.filePath

#             # Write-Host "[File-Logger] Checking if log file exists at: $($this.filePath)"
#             if (-not $logFileExists) {
#                 Write-Host "[File-Logger] Log file does not exist, checking for directory..."
#                 if (-not (Test-Path -Path $logDirectory)) {
#                     Write-Host "[File-Logger] Directory does not exist, creating directory at: $logDirectory"
#                     New-Item -ItemType Directory -Path $logDirectory -Force
#                 }
#                 Write-Host "[File-Logger] Creating log file at: $($this.filePath)"
#                 New-Item -Path $this.filePath -ItemType File -Force
#             }

#             # Write-Host "[File-Logger] Log file exists, writing log entry."
#             # Proceed with logging
#             Add-Content -Path $this.filePath -Value $logItem
#         }
#         catch {
#             Write-Host "[File-Logger] Exception caught"
#             Write-Host "Failed to write to log file: $_" -ForegroundColor Red
#         }
#     }

#     # Create the logger object
#     $logger = New-Object PSObject -Property @{
#         filePath = $path
#     }
#     # Add logger object member as a method
#     $logger | Add-Member -MemberType ScriptMethod -Name "Log" -Value $logFunction

#     Write-Host "[File-Logger] Returning logger: $logger"
#     return $logger
# }

function File-Logger {
    param (
        [Parameter(Mandatory = $true)] [string]$path
    )

    Write-Host "[Log-Module] Creating logger..."
    
$logFunction = {
    param (
        [ValidateSet('Debug', 'Info', 'Warn', 'Error', 'Critical')]
        [string]$level = 'Info',
        [string]$message
    )
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $logItem = "[$timestamp] [$level] $message"

    # Log to file
    try {
        $logDirectory = Split-Path -Parent $this.filePath
        if (-not (Test-Path -Path $logDirectory)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }
        Add-Content -Path $this.filePath -Value $logItem
    }
    catch {
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }

    # Log to Octopus with appropriate log level
    switch ($level) {
        "Debug"    { Write-Verbose $message }
        "Info"     { Write-Host $message }
        "Warn"     { Write-Warning $message }
        "Error"    { Write-Error $message }
        "Critical" { Write-Error "[CRITICAL] $message"; exit 1 }
    }
}

    # Create the logger object
    $logger = New-Object PSObject -Property @{
        filePath = $path
    }
    # Add logger object member as a method
    $logger | Add-Member -MemberType ScriptMethod -Name "Log" -Value $logFunction

    Write-Host "[File-Logger] Returning logger: $logger"
    return $logger
}
