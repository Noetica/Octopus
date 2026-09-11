<#
.SYNOPSIS
    Removes the Call Player API service from a Synthesys tenant VM.

.DESCRIPTION
    Intended to be run as an Octopus Deploy runbook step on each tenant VM.

    No Octopus variables are required.

    Performs the standard Synthesys service removal sequence:
      1. Confirms the service is present and currently active in synthesys.inf.
      2. Stops the service via the Synthesys ControlPanel registry request.
      3. Comments out its Start batch line in the [System Services] section.
      4. Reloads the Synthesys services so the change takes effect.

    The script is idempotent: if the service is already commented out it exits
    cleanly without changing anything. A timestamped backup of synthesys.inf is
    taken before the file is modified, and the file is rewritten as ANSI
    (Windows-1252) to match the original encoding.

    If the Start batch line cannot be found, the script fails and lists the
    [System Services] entries it did find, so the correct name can be confirmed
    without guessing.
#>

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$ApiName        = "CallPlayerAPI"
$StartBatchName = "StartCallPlayerAPI.bat"

$InfPath    = "C:\Synthesys\etc\synthesys.inf"
$InfSection = "System Services"

$ControlPanelKey    = "HKLM:\Software\Noetica\Synthesys\Services\ControlPanel"
$ServicesManagerKey = "HKLM:\SOFTWARE\Noetica\Synthesys\Services\ServicesManager"

$StopTimeoutSeconds = 60

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Get-InfSectionLines {
    param (
        [Parameter()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$SectionName
    )

    $inSection = $false
    $collected = @()

    foreach ($line in $Lines) {
        if ($line -match "^\s*\[$([regex]::Escape($SectionName))\]\s*$") {
            $inSection = $true
            continue
        }

        if ($inSection -and $line -match "^\s*\[.*\]\s*$") {
            break
        }

        if ($inSection -and -not [string]::IsNullOrWhiteSpace($line)) {
            $collected += $line
        }
    }

    return $collected
}

function Stop-SynthesysApi {
    param (
        [Parameter(Mandatory = $true)][string]$ApiRequested
    )

    $applications = Get-ItemProperty -Path $ServicesManagerKey

    # Skip the PowerShell metadata properties (PSPath, PSParentPath, PSChildName,
    # PSDrive, PSProvider) so only genuine registry values are considered.
    $registryValues = $applications.PsObject.Properties |
        Where-Object { $_.Name -notlike "PS*" }

    $matched = $registryValues |
        Where-Object { "$($_.Value)" -match [regex]::Escape($ApiRequested) }

    if (-not $matched) {
        Write-Host "No ServicesManager entry matched '$ApiRequested' - the service is not registered on this VM. Nothing to stop."
        return
    }

    foreach ($entry in $matched) {
        $serviceName = $entry.Name
        Write-Host "Requesting Stop for service '$serviceName'."

        New-ItemProperty -Path $ControlPanelKey -Name "Request" -Value "Stop:$serviceName" -Force | Out-Null

        # Synthesys deletes the Request value once it has actioned the request.
        $counter  = 0
        $actioned = $false

        while ($counter -lt $StopTimeoutSeconds) {
            $pending = Get-ItemProperty -Path $ControlPanelKey -Name "Request" -ErrorAction SilentlyContinue
            if (-not $pending) {
                Write-Host "Request actioned by Synthesys. Continuing."
                # Allow file handles to be released before editing the INF.
                Start-Sleep -Seconds 2
                $actioned = $true
                break
            }

            Write-Host "  Request still pending, waiting... (attempt $($counter + 1)/$StopTimeoutSeconds)"
            Start-Sleep -Seconds 1
            $counter++
        }

        if (-not $actioned) {
            throw "Timeout: the ControlPanel Request value still exists after $StopTimeoutSeconds seconds. Synthesys has not actioned the Stop for '$serviceName', so synthesys.inf has been left unchanged."
        }
    }
}

# ---------------------------------------------------------------------------
# STEP 1 - Confirm the service is present and currently active
# ---------------------------------------------------------------------------
Write-Host "--- Step 1: Checking $ApiName in synthesys.inf ---"

if (-not (Test-Path -Path $InfPath -PathType Leaf)) {
    throw "File not found: '$InfPath'. Verify the Synthesys installation path before re-running."
}

$infLines     = [System.IO.File]::ReadAllLines($InfPath, [System.Text.Encoding]::GetEncoding(1252))
$sectionLines = Get-InfSectionLines -Lines $infLines -SectionName $InfSection
$serviceLines = $sectionLines | Where-Object { $_ -like "*$StartBatchName*" }

if (-not $serviceLines) {
    $found = ($sectionLines | ForEach-Object { "    $_" }) -join [Environment]::NewLine
    throw "No line referencing '$StartBatchName' was found in the [$InfSection] section of '$InfPath'. The batch file name may differ on this build. Entries actually present:$([Environment]::NewLine)$found"
}

$activeLines = $serviceLines | Where-Object { -not $_.TrimStart().StartsWith(";") }

if (-not $activeLines) {
    Write-Host "$ApiName is already commented out - nothing to do."
    Write-Host ""
    Write-Host "=== Runbook complete (no changes) ==="
    return
}

Write-Host "$ApiName is active. Proceeding with removal."
Write-Host ""

# ---------------------------------------------------------------------------
# STEP 2 - Stop the service
# ---------------------------------------------------------------------------
Write-Host "--- Step 2: Stopping $ApiName ---"

Stop-SynthesysApi -ApiRequested $ApiName

Write-Host ""

# ---------------------------------------------------------------------------
# STEP 3 - Comment the service out of synthesys.inf
# ---------------------------------------------------------------------------
Write-Host "--- Step 3: Commenting $StartBatchName out of [$InfSection] ---"

$inSection     = $false
$modifiedLines = @()
$madeChange    = $false

foreach ($line in $infLines) {
    if ($line -match "^\s*\[$([regex]::Escape($InfSection))\]\s*$") {
        $inSection = $true
        $modifiedLines += $line
        continue
    }

    if ($inSection -and $line -match "^\s*\[.*\]\s*$") {
        $inSection = $false
    }

    if ($inSection -and $line -like "*$StartBatchName*" -and -not $line.TrimStart().StartsWith(";")) {
        Write-Host "  Commenting: $line"
        $line = ";" + $line
        $madeChange = $true
    }

    $modifiedLines += $line
}

if (-not $madeChange) {
    throw "Expected to comment out '$StartBatchName' but no uncommented line was found. The file has been left unchanged."
}

$timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$fileName   = [System.IO.Path]::GetFileName($InfPath)
$dirName    = [System.IO.Path]::GetDirectoryName($InfPath)
$backupPath = Join-Path $dirName "$fileName.$timestamp.bak"

# Copy rather than rename, so the original stays in place if the write fails.
Copy-Item -Path $InfPath -Destination $backupPath -Force
Write-Host "Backup created at '$backupPath'."

# Rewrite as ANSI (Windows-1252) to match the original file encoding.
$ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)
[System.IO.File]::WriteAllLines($InfPath, $modifiedLines, $ansiEncoding)

Write-Host "$StartBatchName commented out."
Write-Host ""

# ---------------------------------------------------------------------------
# STEP 4 - Reload the Synthesys services
# ---------------------------------------------------------------------------
Write-Host "--- Step 4: Reloading services ---"

New-ItemProperty -Path $ControlPanelKey -Name "Request" -Value "ReloadServices" -Force | Out-Null

Write-Host "ReloadServices requested."
Write-Host ""
Write-Host "=== Runbook complete - $ApiName removed ==="
