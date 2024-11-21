Param (
	[Parameter(Mandatory=$True)]
	[string]$PackageName,
	[Parameter(Mandatory=$True)]
	[string]$SourceDir,
	[Parameter(Mandatory=$True)]
	[string]$TargetRoot,
	[Parameter(Mandatory=$True)]
	[string]$TargetDir,
	[Parameter(Mandatory=$True)]
	[string]$FileExclusions
)

Write-Host "## Deployment source: '$SourceDir'"
Write-Host "## Target root: '$TargetRoot'"
Write-Host "## Deployment target: '$TargetDir'"

if (-not (Test-Path -Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir
    Write-Host "Directory created: $TargetDir"
}
else {
    Write-Host "## Clearing target directory: '$TargetDir'..."    
    $totalToDeleteCount = 0
    $deletedFileCount = 0
    Get-ChildItem -Path $TargetDir -Recurse -Force | 
        Where-Object { $_.FullName -notin ($FileExclusions | ForEach-Object { Join-Path $TargetDir $_ }) } |
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
Write-Host "## Copying files from '$SourceDir' to '$TargetDir'..."
Get-ChildItem -Path $SourceDir -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Substring($SourceDir.Length + 1)
    $destinationPath = Join-Path -Path $TargetDir -ChildPath $relativePath
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
