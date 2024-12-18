Param (
    [Parameter(Mandatory = $True)]
    [string]$PackageName,
    [Parameter(Mandatory = $True)]
    [string]$SourceDir,
    [Parameter(Mandatory = $True)]
    [int]$DefaultPort,
    [Parameter(Mandatory = $True)]
    [string]$targetApiDir,
    [Parameter(Mandatory = $True)]
    [string]$FileExclusions
)

Write-Host "## Deployment package: '$PackageName'"
Write-Host "## Deployment source: '$SourceDir'"
Write-Host "## Target root: '$targetApiRoot'"
Write-Host "## Deployment target: '$targetApiDir'"
Write-Host "## Default hosting port: '$DefaultPort'"

function ControlService {
    param (
        [string]$targetApi,
        [string]$operation
    )
    if ([string]::IsNullOrEmpty($targetApi)) {
        New-ItemProperty -Path 'HKLM:\Software\Noetica\Synthesys\Services\ControlPanel' -Name 'Request' -Value "${operation}" 
    }
    else {
        $applications = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Noetica\Synthesys\Services\ServicesManager'
        foreach ($object_properties in $applications.PsObject.Properties) {
            $matched = $object_properties.Value -Match $targetApi
            if ($matched) {
                $name = $object_properties.Name
                New-ItemProperty -Path 'HKLM:\Software\Noetica\Synthesys\Services\ControlPanel' -Name 'Request' -Value "${operation}:${name}" 
            }
        }
    }
}

Write-Host "## Stopping $PackageName..."
ControlService -apiRequested $PackageName -operation 'Stop'

if (-not (Test-Path -Path $targetApiDir)) {
    New-Item -ItemType Directory -Path $targetApiDir
    Write-Host "Directory created: $targetApiDir"
}
else {
    Write-Host "## Clearing target directory: '$targetApiDir'..."    
    $totalToDeleteCount = 0
    $deletedFileCount = 0
    Get-ChildItem -Path $targetApiDir -Recurse -Force | 
        Where-Object { $_.FullName -notin ($FileExclusions | ForEach-Object { Join-Path $targetApiDir $_ }) } |
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
Write-Host "## Copying files from '$SourceDir' to '$targetApiDir'..."
Get-ChildItem -Path $SourceDir -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Substring($SourceDir.Length + 1)
    $destinationPath = Join-Path -Path $targetApiDir -ChildPath $relativePath
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

function CreateStartupScript() {
    param (
        [string]$targetApi,
        [string]$port
    )
    Write-Host '## Creating startup script...'
    $serverBin = $OctopusParameters['Noetica.ServerBinRoot']
    $filename = "$serverBin\Start$targetApi.bat"
    $content = @"
cd "\Synthesys\NoeticaAPIs\$targetApi"
start "$targetApi" dotnet $targetApi.dll --urls "http://+:$port"
"@
    Set-Content -Path $filename -Value $content
    if (Test-Path -Path $filename) {
        Write-Host "Created: $filename with content:`n$content"
    }
    else {
        Write-Host "[!] Startup script not created: $filename"
    }
}
CreateStartupScript -targetApi $PackageName -port $DefaultPort

Write-Host "## Starting $PackageName..."
ControlService -apiRequested $PackageName -operation 'Start'
