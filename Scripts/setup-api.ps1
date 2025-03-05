param (
    [Parameter(Mandatory = $true)] [string]$AppName, # Name of the artifact (versionless) or display name, e.g. ReportsAPI
    [Parameter(Mandatory = $true)] [string]$SourceDir, # Location of the source artifact to be deployed
    [Parameter(Mandatory = $true)] [string]$TargetDir, # Location of the target deployment directory
    [Parameter(Mandatory = $false)] [string]$DefaultPort, # Port mapping for the project
    [Parameter(Mandatory = $false)] [string]$StartupScript, # Override startup script for batch file
    [Parameter(Mandatory = $false)] [string[]]$FileExclusions, # Files to ignore when deploying
    [Parameter(Mandatory = $false)] [string[]]$Output # Specify a custom location for the log output
)

<#==================================================#>

# Backup/Restore variables
$script:backupDir = "$env:TentacleHome" + '\Logs\' + "$($script:appName)_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
# Logging: Use override if specified, or default value
$script:logFile = if ($null -ne $Output) { $Output } else { "$($script:backupDir).log" }

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
                    try {
                        Remove-Item -Path $_.FullName -Force -Recurse
                        $logger.Log('Debug', "Deleted successfully. ($($_.FullName))")
                        $deletedFileCount++
                    }
                    catch {
                        # Collect errors instead of exiting
                        $errorList += "Not deleted. $($_.FullName) - $_"
                        $logger.Log('Critical', "Not deleted. ($($_.FullName))")
                    }
                }
        $logger.Log('Debug', "Cleared $deletedFileCount of $totalToDeleteCount")

        # After the loop, if there are errors, output them and exit with code 1
        if ($errorList.Count -gt 0) {
            $logger.Log('Debug', 'Error(s) occurred during deletion:')
            $errorList | ForEach-Object { $logger.Log('Critical', $_) }
            exit 1
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
            Copy-Item -Path $item.FullName -Destination $destinationPath -Force
            if (Test-Path $destinationPath) {
                $logger.Log('Info', 'Copied successfully.')
                $copiedFileCount++
            }
            else {
                $logger.Log('Critical', "File not copied. ($(item.FullName))")
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

# $util = [Util]::new($script:logFile) # Create an instance of the Util class
$logger = File-Logger -path $script:logFile # Use the File-Logger Script Module
Stop-Service -targets $script:appName
DeployLatestArtifact -exclusions $FileExclusions
$logger.Log('Debug', "Startup script selection")
$logger.Log('Debug', "DefaultPort: [($DefaultPort)]")
$logger.Log('Debug', "StartupScript: [($StartupScript)]")
if (-not [string]::IsNullOrEmpty($DefaultPort)) { CreateStartupScript }
if (-not [string]::IsNullOrEmpty($StartupScript)) { CreateStartupStartupScript }
Write-Host "Deployment run completed. Full log file can be found at $script:logFile."
