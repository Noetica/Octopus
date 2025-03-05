#This is powershell that is copied from octopus scripts,
#so that we can the code locally and also reference them from our own code 
#without having to include Script Module when setting up processes
#in octopus.  Also allows this to be run from other deployments
#which aren't dependant on octopus.
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