param (
    [Parameter(Mandatory = $true)] [string]$AppName, # Name of the artifact (versionless) or display name, e.g. ReportsAPI
    [Parameter(Mandatory = $true)] [string]$SourceDir, # Location of the source artifact to be deployed
    [Parameter(Mandatory = $true)] [string]$TargetDir, # Location of the target deployment directory
    [Parameter(Mandatory = $true)] [string]$DefaultPort, # Port mapping for the project
    [Parameter(Mandatory = $false)] [string[]]$FileExclusions # Files to ignore when deploying
)

Write-Host "## Application name: '$AppName'"
Write-Host "## Deployment source: '$SourceDir'"
Write-Host "## Deployment target: '$TargetDir'"
Write-Host "## Default port: '$DefaultPort'"
if ($null -ne $FileExclusions) { Write-Host "## Exclusions: '$FileExclusions'" }

function ControlService {
    param (
        [string]$target,
        [string]$operation
    )
    Write-Host "## Requesting $AppName state: '$operation'..."
    if ([string]::IsNullOrEmpty($target)) {
        New-ItemProperty -Path 'HKLM:\Software\Noetica\Synthesys\Services\ControlPanel' -Name 'Request' -Value "${operation}" 
    }
    else {
        $applications = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Noetica\Synthesys\Services\ServicesManager'
        foreach ($object_properties in $applications.PsObject.Properties) {
            $matched = $object_properties.Value -Match $target
            if ($matched) {
                $name = $object_properties.Name
                New-ItemProperty -Path 'HKLM:\Software\Noetica\Synthesys\Services\ControlPanel' -Name 'Request' -Value "${operation}:${name}" 
            }
        }
    }
}

function DeployLatestArtifact() {
    param (
        [string]$source,
        [string]$target,
        [string]$exclusions
    )
    if (-not (Test-Path -Path $target)) {
        New-Item -ItemType Directory -Path $target
        Write-Host "Directory created: $target"
    }
    else {
        Write-Host "## Clearing target directory: '$target'..."    
        $totalToDeleteCount = 0
        $deletedFileCount = 0
        Get-ChildItem -Path $target -Recurse -Force | 
            Where-Object { $_.FullName -notin ($exclusions | ForEach-Object { Join-Path $target $_ }) } |
                ForEach-Object {
                    $totalToDeleteCount++
                    try {
                        Remove-Item -Path $_.FullName -Force -Recurse
                        Write-Host "Deleted: $($_.FullName)"
                        $deletedFileCount++
                    }
                    catch {
                        Write-Host "[!] Error deleting: $($_.FullName) - $_"
                    }
                }
        Write-Host "## Cleared $deletedFileCount of $totalToDeleteCount"
    }
    
    $totalToCopyCount = 0
    $copiedFileCount = 0
    Write-Host "## Copying files from '$source' to '$target'..."
    Get-ChildItem -Path $source -Recurse -File | ForEach-Object {
        $relativePath = $_.FullName.Substring($source.Length + 1)
        $destinationPath = Join-Path -Path $target -ChildPath $relativePath
        $destinationDir = Split-Path -Path $destinationPath -Parent
        $totalToCopyCount++
    
        if (-not (Test-Path -Path $destinationPath)) {
            if (-not (Test-Path -Path $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }
            Copy-Item -Path $_.FullName -Destination $destinationPath
            Write-Host "Copied: $($_.FullName) to $destinationPath"
            $copiedFileCount++
        }
        else {
            Write-Host "[!] File already exists (skipped): $destinationPath"
        }
    
    }
    Write-Host "## Copied $copiedFileCount of $totalToCopyCount"
}

function CreateStartupScript() {
    param (
        [string]$target,
        [string]$port
    )
    Write-Host '## Creating startup script...'
    $serverBin = $OctopusParameters['Noetica.ServerBin']
    $filename = "$serverBin\Start$target.bat"
    $content = @"
cd "\Synthesys\NoeticaAPIs\$target"
start "$target" dotnet $target.dll --urls "http://+:$port"
"@
    Set-Content -Path $filename -Value $content
    if (Test-Path -Path $filename) {
        Write-Host "Created: $filename with content:`n$content"
    }
    else {
        Write-Host "[!] Startup script not created: $filename"
    }
}

ControlService -target $AppName -operation 'Stop'
DeployLatestArtifact -source $SourceDir -target $TargetDir -exclusions $FileExclusions
CreateStartupScript -target $AppName -port $DefaultPort
ControlService -target $AppName -operation 'Start'
