param (
    [Parameter(Mandatory = $true)] [string]$AppName, # Name of the artifact (versionless) or display name, e.g. ReportsAPI
    [Parameter(Mandatory = $true)] [string]$SourceDir, # Location of the source artifact to be deployed
    [Parameter(Mandatory = $true)] [string]$TargetDir, # Location of the target deployment directory
    [Parameter(Mandatory = $false)] [string]$DefaultPort, # Port mapping for the project
    [Parameter(Mandatory = $false)] [string]$StartupScript, # Override startup script for batch file
    [Parameter(Mandatory = $false)] [string[]]$FileExclusions # Files to ignore when deploying
)

Write-Output "The script is running from: $PSScriptRoot"

# Initialize script-scoped variables from parameters
$script:appName = $AppName
$script:sourceDir = $SourceDir
$script:targetDir = $TargetDir
$script:defaultPort = $DefaultPort
$script:startupScript = $StartupScript

. "$PSScriptRoot\utils\control-service.ps1"
. "$PSScriptRoot\utils\file-logger.ps1"

<#==================================================#>

function DeployLatestArtifact() {
    param (
        [string]$exclusions
    )
    if (-not (Test-Path -Path $script:targetDir)) {
        $logger.Log('Debug', 'Creating target directory...')
        New-Item -ItemType Directory -Path $script:targetDir
        if (Test-Path $script:targetDir) {
            $logger.Log('Debug', "Directory created successfully. ($script:targetDir)")
        }
        else {
            $logger.Log('Critical', "Directory not created. ($script:targetDir)")
            exit 1
        }
    }
    else {
        $logger.Log('Debug', 'Clearing deployment target directory...')
        $totalToDeleteCount = 0
        $deletedFileCount = 0
        $errorList = @() # Initialize an array to collect errors

        Get-ChildItem -Path $script:targetDir -Recurse -Force | 
            Where-Object { $_.FullName -notin ($exclusions | ForEach-Object { Join-Path $script:targetDir $_ }) } |
                ForEach-Object {
                    $totalToDeleteCount++
                    $currentItem = $_  # Capture the item reference before try-catch
                    $currentPath = $_.FullName
                    $itemType = if ($currentItem.PSIsContainer) { "Directory" } else { "File" }
                    $logger.Log('Debug', "Attempting to delete ${itemType}: $currentPath")
                    try {
                        Remove-Item -LiteralPath $currentPath -Force -Recurse -ErrorAction Stop
                        $logger.Log('Debug', "Deleted successfully. ($currentPath)")
                        $deletedFileCount++
                    }
                    catch {
                        # Collect errors with full details
                        $errorMessage = "Failed to delete: $currentPath | Error: $($_.Exception.Message)"
                        $errorList += $errorMessage
                        $logger.Log('Error', $errorMessage)
                        # Log additional details if available
                        if ($_.Exception.InnerException) {
                            $logger.Log('Debug', "Inner exception: $($_.Exception.InnerException.Message)")
                        }
                    }
                }
        $logger.Log('Debug', "Cleared $deletedFileCount of $totalToDeleteCount")

        # After the loop, if there are errors, output them and exit with code 1
        if ($errorList.Count -gt 0) {
            $logger.Log('Error', "===== DELETION ERRORS SUMMARY =====")
            $logger.Log('Error', "Failed to delete $($errorList.Count) item(s) out of $totalToDeleteCount")
            $logger.Log('Error', "Successfully deleted: $deletedFileCount")
            $logger.Log('Error', "-----------------------------------")
            $logger.Log('Error', "Details of failed deletions:")
            $errorList | ForEach-Object { $logger.Log('Error', $_) }
            $logger.Log('Error', "===================================")
            $logger.Log('Error', "Common causes: Files in use by running processes, insufficient permissions, or locked files.")
            $logger.Log('Error', "Suggestion: Ensure the service is fully stopped and no processes are using the files.")
            exit 1
        }
        else {
            $logger.Log('Info', "All files were successfully deleted. ($deletedFileCount items removed)")
        }
    }

    $totalToCopyCount = 0
    $copiedFileCount = 0
    $logger.Log('Info', 'Deploying latest artifact...')
    # Copy items from source directory, unless marked as exclusion
    $itemsToCopy = Get-ChildItem -Path $script:sourceDir -Recurse | Where-Object { $FileExclusions -notcontains $_.Name }
    foreach ($item in $itemsToCopy) {
        $relativePath = $item.FullName.Substring($script:sourceDir.Length).TrimStart('\')
        $destinationPath = Join-Path -Path $script:targetDir -ChildPath $relativePath

        if ($item.PSIsContainer) {
            # If item is a directory, create it and check it was created
            $logger.Log('Debug', "Creating directory ($($item.Name))...")
            $logger.Log('Debug', "Source: ($($item.FullName))")
            $logger.Log('Debug', "Target: ($($destinationPath))")
            New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
            if (Test-Path $destinationPath) {
                $logger.Log('Debug', 'Directory created successfully.')
            }
            else {
                $logger.Log('Critical', "Directory not created. ($($destinationPath))")
                exit 1
            }
        }
        else {
            $totalToCopyCount++
            # If item is a file, copy it and check it was created
            $logger.Log('Info', "Copying ($($item.Name))...")
            $logger.Log('Debug', "Source: ($($item.FullName))")
            $logger.Log('Debug', "Target: ($destinationPath)")
            try {
                Copy-Item -Path $item.FullName -Destination $destinationPath -Force -ErrorAction Stop
                # Belt and braces - this should always succeed, but nice to see
                # it logging the new file has been copied. If it fails, it should 
                # go direct to the exception.
                if (Test-Path $destinationPath) {
                    $logger.Log('Info', 'Copied successfully.')
                    $copiedFileCount++
                }
                else {
                    $logger.Log('Critical', "File not copied. ($($item.FullName))")
                    exit 1
                }
            }
            catch {
                $logger.Log('Critical', "Failed to copy file. ($($item.FullName)) - $_")
                exit 1
            }
        }
    }
    $logger.Log('Debug', "Copied $copiedFileCount of $totalToCopyCount")
}

function CreateStartupScript() {
    param (
        [string]$target = $script:appName,
        [string]$port = $script:defaultPort
    )
    $logger.Log('Info', 'Creating startup script...')
    $appRootFragment = $OctopusParameters['Noetica.AppRoot.Fragment']
    $serverBin = $OctopusParameters['Noetica.ServerBinRoot']
    $filename = "$serverBin\Start$target.bat"
    $content = @"
cd "\$appRootFragment\$target"
start "$target" dotnet $target.dll --urls "http://+:$port"
"@
    Set-Content -Path $filename -Value $content
    $logger.Log('Debug', "Target: ($filename)")
    $logger.Log('Debug', "Content:`n$content")
    if (Test-Path -Path $filename) {
        $logger.Log('Info', 'Created successfully.')
    }
    else {
        $logger.Log('Warn', "Script not created. ($filename)")
    }
}

function CreateStartupStartupScript() {
    param (
        [string]$target = $script:appName,
        [string]$startupScript = $script:startupScript
    )
    $logger.Log('Info', 'Creating startup startup script...')
    $appRootFragment = $OctopusParameters['Noetica.AppRoot.Fragment']
    $serverBin = $OctopusParameters['Noetica.ServerBinRoot']
    $filename = "$serverBin\Start$target.bat"
    $content = @"
cd "\$appRootFragment\$target"
$startupScript
"@ -f $target
    $content = $content.Replace("&quot;","`"")
    Set-Content -Path $filename -Value $content
    $logger.Log('Debug', "Target: ($filename)")
    $logger.Log('Debug', "Content:`n$content")
    if (Test-Path -Path $filename) {
        $logger.Log('Info', 'Created successfully.')
    }
    else {
        $logger.Log('Warn', "Script not created. ($filename)")
    }
}

$logger = File-Logger  # Use File-Logger util

# Stop the service using the control-service utility
$logger.Log('Info', "Stopping service: $script:appName")
Stop-Service -targets $script:appName

# Wait for the actual process to fully terminate and release file locks
# The service may report as "Stopped" but the process can still be shutting down
# Note: We handle multiple instances in case of previous failures or manual starts

# Extract the actual process name and arguments from the startup script
# For native executables: "start \"WindowTitle\" ProcessName.exe" -> ProcessName
# For dotnet apps: "start \"WindowTitle\" dotnet App.dll" -> need to filter by App.dll in command line
$processName = $script:appName  # Default fallback
$isDotnetApp = $false
$dllName = $null

if (-not [string]::IsNullOrEmpty($script:startupScript)) {
    # Parse the startup script to extract the actual executable name
    # Pattern: start "title" executable [args...]
    if ($script:startupScript -match 'start\s+"[^"]+"\s+(\S+)(?:\s+(\S+))?') {
        $executablePath = $matches[1]
        $firstArg = $matches[2]
        
        # Validate that we actually captured an executable path
        if (-not [string]::IsNullOrEmpty($executablePath)) {
            # Extract just the process name without path or extension
            $processName = [System.IO.Path]::GetFileNameWithoutExtension($executablePath)
            
            # Check if this is a dotnet application
            if ($processName -eq 'dotnet' -and $firstArg -like '*.dll') {
                $isDotnetApp = $true
                $dllName = [System.IO.Path]::GetFileName($firstArg)
                $logger.Log('Info', "Detected dotnet application from startup script. Will filter processes by DLL: '$dllName'")
            } else {
                $logger.Log('Info', "Extracted process name from startup script: '$processName'")
            }
        } else {
            $logger.Log('Warn', "Startup script matched pattern but executable path is empty. Using service name: '$processName'")
        }
    } else {
        $logger.Log('Warn', "Could not parse startup script to extract process name. Using service name: '$processName'")
    }
} elseif (-not [string]::IsNullOrEmpty($script:defaultPort)) {
    # Standard dotnet app deployed with DefaultPort (startup script will be created later)
    $processName = 'dotnet'
    $isDotnetApp = $true
    $dllName = "$script:appName.dll"
    $logger.Log('Info', "Detected dotnet application via DefaultPort parameter. Will filter processes by DLL: '$dllName'")
} else {
    $logger.Log('Info', "No startup script or DefaultPort provided. Using service name as process name: '$processName'")
}

# Helper function to retrieve target processes based on app type
function Get-TargetProcesses {
    if ($isDotnetApp) {
        # For dotnet apps, filter by command line containing the specific DLL
        if ([string]::IsNullOrEmpty($dllName)) {
            $logger.Log('Error', "Cannot filter dotnet processes: DLL name is empty. This would match all dotnet.exe processes.")
            return @()
        }
        # Use regex matching with delimiters to avoid matching DLL names embedded in longer names
        $escapedDllName = [regex]::Escape($dllName)
        return @(Get-CimInstance Win32_Process -Filter "Name='dotnet.exe'" -ErrorAction SilentlyContinue | 
            Where-Object { $_.CommandLine -match "[\s`"]$escapedDllName[\s`"]" })
    } else {
        # For native executables, just get by process name
        return @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
    }
}

$maxWaitSeconds = 10
$waitInterval = 1
$waited = 0

if ($isDotnetApp -and -not [string]::IsNullOrEmpty($dllName)) {
    $logger.Log('Info', "Waiting for dotnet process hosting '$dllName' to fully exit...")
} elseif ($isDotnetApp) {
    $logger.Log('Info', "Waiting for dotnet process to fully exit (DLL name unknown)...")
} else {
    $logger.Log('Info', "Waiting for process '$processName.exe' to fully exit...")
}
# Loop up to maxWaitSeconds, checking every waitInterval if the process has exited
while ($waited -lt $maxWaitSeconds) {
    $processes = Get-TargetProcesses
    if ($processes.Count -eq 0) {
        $logger.Log('Info', "Process exited after $waited seconds")
        break
    }
    if ($processes.Count -gt 1) {
        # Log warning if multiple instances found - this is unexpected but we'll wait for all to exit
        if ($isDotnetApp) {
            $pids = ($processes | ForEach-Object { $_.ProcessId }) -join ', '
        } else {
            $pids = ($processes | ForEach-Object { $_.Id }) -join ', '
        }
        $logger.Log('Warn', "Multiple instances detected ($($processes.Count)): PIDs $pids")
    }
    Start-Sleep -Seconds $waitInterval
    $waited += $waitInterval
}

# Final check to confirm all process instances have terminated
$processes = Get-TargetProcesses

if ($processes.Count -gt 0) {
    if ($isDotnetApp) {
        $pids = ($processes | ForEach-Object { $_.ProcessId }) -join ', '
        $logger.Log('Warn', "Dotnet process running '$dllName' still active after $maxWaitSeconds seconds: $($processes.Count) instance(s) with PID(s) $pids")
    } else {
        $pids = ($processes | ForEach-Object { $_.Id }) -join ', '
        $logger.Log('Warn', "Process '$processName.exe' still running after $maxWaitSeconds seconds: $($processes.Count) instance(s) with PID(s) $pids")
    }
    
    # Attempt to force-terminate any remaining process instances
    $logger.Log('Warn', "Attempting to force-terminate remaining process(es)...")
    $processes | ForEach-Object {
        try {
            if ($isDotnetApp) {
                $processId = $_.ProcessId
                Stop-Process -Id $processId -Force -ErrorAction Stop
                $logger.Log('Info', "Force-terminated dotnet process (PID $processId) running '$dllName'")
            } else {
                Stop-Process -Id $_.Id -Force -ErrorAction Stop
                $logger.Log('Info', "Force-terminated process '$processName.exe' (PID $($_.Id))")
            }
        }
        catch {
            if ($isDotnetApp) {
                $logger.Log('Error', "Failed to force-terminate dotnet process (PID $($_.ProcessId)) running '$dllName': $($_.Exception.Message)")
            } else {
                $logger.Log('Error', "Failed to force-terminate process '$processName.exe' (PID $($_.Id)): $($_.Exception.Message)")
            }
        }
    }
    
    # Give the OS a moment to clean up after forced termination
    Start-Sleep -Seconds 2
    
    # Verify all processes are now gone - fail deployment if any remain
    $processes = Get-TargetProcesses
    if ($isDotnetApp) {
        if ($processes.Count -gt 0) {
            $pids = ($processes | ForEach-Object { $_.ProcessId }) -join ', '
            $logger.Log('Critical', "Unable to terminate dotnet process(es) running '$dllName' after force-kill attempt. PID(s): $pids. Deployment cannot proceed safely.")
            exit 1
        }
    } else {
        $processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
        if ($processes.Count -gt 0) {
            $pids = ($processes | ForEach-Object { $_.Id }) -join ', '
            $logger.Log('Critical', "Unable to terminate process '$processName.exe' after force-kill attempt. PID(s): $pids. Deployment cannot proceed safely.")
            exit 1
        }
    }
    $logger.Log('Info', "All processes successfully terminated")
} else {
    if ($isDotnetApp) {
        $logger.Log('Info', "Dotnet process running '$dllName' has fully terminated")
    } else {
        $logger.Log('Info', "Process '$processName.exe' has fully terminated")
    }
}

# Now safe to proceed with file operations
DeployLatestArtifact -exclusions $FileExclusions
$logger.Log('Debug', "Startup script selection")
$logger.Log('Debug', "DefaultPort: [($DefaultPort)]")
$logger.Log('Debug', "StartupScript: [($StartupScript)]")
if (-not [string]::IsNullOrEmpty($DefaultPort)) { CreateStartupScript }
if (-not [string]::IsNullOrEmpty($StartupScript)) { CreateStartupStartupScript }
$logFileLocation = File-Logger-Location
Write-Host "Deployment run completed. Full log file can be found at $logFileLocation."
