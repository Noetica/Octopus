param (
        [string]$apiRequested,
        [string]$operation
    )

function ControlService {
    param (
        [string]$apiRequested,
        [string]$operation
    )

    if([string]::IsNullOrEmpty($apiRequested))
    {
        New-ItemProperty -Path "HKLM:\Software\Noetica\Synthesys\Services\ControlPanel" -Name "Request" -Value "${operation}" 
    }
    else
    {
        $applications = Get-ItemProperty -path "HKLM:\SOFTWARE\Noetica\Synthesys\Services\ServicesManager"
        foreach($object_properties in $applications.PsObject.Properties)
        {
            $services = $object_properties.Value -Match $apiRequested
            if($services) 
            {
                $name = $object_properties.Name
                New-ItemProperty -Path "HKLM:\Software\Noetica\Synthesys\Services\ControlPanel" -Name "Request" -Value "${operation}:${name}" 

                # Wait until the value is deleted
                $counter = 0
                while ($counter -lt 60) {
                    $exists = Get-ItemProperty -Path "HKLM:\Software\Noetica\Synthesys\Services\ControlPanel" -Name "Request" -ErrorAction SilentlyContinue
                    if (-not $exists) {
                        Write-Host "Registry value deleted. Continuing..."
                        break
                    }
                    Write-Host "Registry value exists. Waiting... (attempt $($counter + 1)/60)"
                    Start-Sleep -Seconds 1
                    $counter++
                }
                
                if ($counter -ge 60) {
                    Write-Warning "Timeout: Registry value still exists after 60 attempts"
                }
            }
        }
    }
}

function CommentInfLine {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$SectionName,

        [Parameter(Mandatory = $true)]
        [string]$SearchText
    )

    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        return
    }

    $lines = Get-Content $FilePath
    $inSection = $false
    $modifiedLines = @()
    $madechange = $false

    foreach ($line in $lines) {
        if ($line -match "^\s*\[$SectionName\]\s*$") {
            $inSection = $true
            $modifiedLines += $line
            continue
        }

        if ($inSection -and $line -match "^\s*\[.*\]\s*$") {
            $inSection = $false
        }

        if ($inSection -and $line -like "*$SearchText*") {
            if(!$line.StartsWith(";")) {
                $line = -join(";", $line)
                $madechange = $true
            }
        }

        $modifiedLines += $line
    }

    if (-not $madechange) {
        Write-Output "No changes made. The specified text was not found or already commented."
        return
    }


    # Create timestamped backup filename
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $dirName = [System.IO.Path]::GetDirectoryName($FilePath)
    $backupPath = Join-Path $dirName "$baseName.$timestamp.bak"
    Rename-Item -Path $FilePath -NewName $backupPath -Force

    # Save as ANSI (Windows-1252 encoding)
    $ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)
    [System.IO.File]::WriteAllLines($FilePath, $modifiedLines, $ansiEncoding)

    Write-Output "File updated. Backup saved as $backupPath"
}

function IsServiceCommented {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$SectionName,

        [Parameter(Mandatory = $true)]
        [string]$SearchText
    )

    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        return
    }

    $lines = Get-Content $FilePath
    $inSection = $false

    foreach ($line in $lines) {
        if ($line -match "^\s*\[$SectionName\]\s*$") {
            $inSection = $true
            continue
        }

        if ($inSection -and $line -match "^\s*\[.*\]\s*$") {
            return $false
        }

        if ($inSection -and $line -like "*$SearchText*") {
            if($line.StartsWith(";")) {
                return $true
            }
        }
    }

    return $false
}

# This script comments out a specific line in a section of an INF file that matches the specified text.
# usage example:
# CommentInfLine -FilePath "C:\Drivers\example.inf" -SectionName "Manufacturer" -SearchText "OldValue"
$isServiceCommented = IsServiceCommented `
    -FilePath "C:\Synthesys\etc\synthesys.inf" `
    -SectionName "System Services" `
    -SearchText "HouseKeeper.exe"

if($isServiceCommented) {
    Write-Output "Old HouseKeeper Service is not active. Exiting script."
    exit
}

ControlService -apiRequested "HouseKeeper" -operation "Stop"

CommentInfLine `
    -FilePath "C:\Synthesys\etc\synthesys.inf" `
    -SectionName "System Services" `
    -SearchText "HouseKeeper.exe"

ControlService -operation "ReloadServices"
