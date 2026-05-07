<#
.SYNOPSIS
    Ensures the required .NET runtime is installed, installing it automatically if missing.

.DESCRIPTION
    Designed to run as an early deployment step in Octopus Deploy. Checks whether the
    required .NET runtime is present and, if not, downloads and installs it silently.
    Fails with exit code 1 only if installation is attempted and fails.

.PARAMETER MajorVersion
    The major .NET version required (e.g. 10).

.PARAMETER RuntimeType
    The type of .NET runtime required: 'Runtime', 'AspNetCore', 'Desktop', or 'SDK'.
    Defaults to 'AspNetCore'.

.EXAMPLE
    .\check-dotnet-prerequisite.ps1 -MajorVersion 10
    Ensures ASP.NET Core 10 runtime is installed, installing if needed.

.EXAMPLE
    .\check-dotnet-prerequisite.ps1 -MajorVersion 10 -RuntimeType SDK
    Ensures .NET 10 SDK is installed, installing if needed.
#>

param(
    [Parameter(Mandatory = $true)]
    [int]$MajorVersion,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Runtime', 'AspNetCore', 'Desktop', 'SDK')]
    [string]$RuntimeType = 'AspNetCore'
)

$ErrorActionPreference = 'Stop'

# Fail fast if not running elevated — installing to Program Files requires admin.
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must run with administrative privileges to install .NET. Tentacle should run as SYSTEM or an elevated account."
    exit 1
}

Write-Host "============================================"
Write-Host "Prerequisite Check: .NET $MajorVersion ($RuntimeType)"
Write-Host "Machine: $env:COMPUTERNAME"
Write-Host "============================================"

function Test-DotNetInstalled {
    $dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $dotnetCmd) {
        return $false
    }

    switch ($RuntimeType) {
        'SDK' {
            $sdks = & dotnet --list-sdks 2>&1
            if ($LASTEXITCODE -ne 0) { return $false }
            $match = $sdks | Where-Object { $_ -match "^$MajorVersion\." }
            return ($null -ne $match -and @($match).Count -gt 0)
        }
        default {
            $runtimes = & dotnet --list-runtimes 2>&1
            if ($LASTEXITCODE -ne 0) { return $false }

            $runtimeName = switch ($RuntimeType) {
                'Runtime'    { 'Microsoft.NETCore.App' }
                'AspNetCore' { 'Microsoft.AspNetCore.App' }
                'Desktop'    { 'Microsoft.WindowsDesktop.App' }
            }

            $match = $runtimes | Where-Object { $_ -match "^$runtimeName $MajorVersion\." }
            return ($null -ne $match -and @($match).Count -gt 0)
        }
    }
}

function Install-DotNetSilently {
    # Use the official EXE installer via aka.ms stable links. The EXE installer uses
    # Windows Installer under the hood, which handles file locks gracefully (unlike
    # dotnet-install.ps1 which extracts a zip and fails if dotnet.exe is in use).
    $channel = "$MajorVersion.0"

    # aka.ms links always resolve to the latest patch version for the channel.
    $installerUrl = switch ($RuntimeType) {
        'Runtime'    { "https://aka.ms/dotnet/$channel/dotnet-runtime-win-x64.exe" }
        'AspNetCore' { "https://aka.ms/dotnet/$channel/aspnetcore-runtime-win-x64.exe" }
        'Desktop'    { "https://aka.ms/dotnet/$channel/windowsdesktop-runtime-win-x64.exe" }
        'SDK'        { "https://aka.ms/dotnet/$channel/dotnet-sdk-win-x64.exe" }
    }

    $installerFile = Join-Path $env:TEMP "dotnet-$MajorVersion-$RuntimeType-installer.exe"

    Write-Host "Downloading .NET $MajorVersion ($RuntimeType) installer..."
    Write-Host "  URL: $installerUrl"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($installerUrl, $installerFile)
    }
    catch {
        Write-Error "Failed to download installer: $_"
        exit 1
    }

    if (-not (Test-Path $installerFile)) {
        Write-Error "Installer file not found after download."
        exit 1
    }

    # Verify Authenticode signature before executing
    Write-Host "Verifying installer signature..."
    $sig = Get-AuthenticodeSignature -FilePath $installerFile
    if ($sig.Status -ne 'Valid') {
        Remove-Item $installerFile -Force -ErrorAction SilentlyContinue
        Write-Error "Installer signature is invalid (status: $($sig.Status)). Aborting."
        exit 1
    }
    if ($sig.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
        Remove-Item $installerFile -Force -ErrorAction SilentlyContinue
        Write-Error "Installer not signed by Microsoft Corporation (signer: $($sig.SignerCertificate.Subject)). Aborting."
        exit 1
    }
    Write-Host "Signature verified: $($sig.SignerCertificate.Subject)"

    # Install silently — the EXE installer handles file locks via pending file operations
    Write-Host "Installing .NET $MajorVersion ($RuntimeType)..."
    $process = Start-Process -FilePath $installerFile -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru -NoNewWindow

    # Clean up
    Remove-Item $installerFile -Force -ErrorAction SilentlyContinue

    switch ($process.ExitCode) {
        0       { Write-Host "Installation completed successfully." }
        1641    { Write-Host "Installation completed. A reboot may be required to finalize." -ForegroundColor Yellow }
        3010    { Write-Host "Installation completed. A reboot may be required to finalize." -ForegroundColor Yellow }
        default {
            Write-Error "Installation failed with exit code: $($process.ExitCode)"
            exit 1
        }
    }
}

# --- Main ---

# Display what's currently installed
$dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
if ($dotnetCmd) {
    Write-Host "Found dotnet at: $($dotnetCmd.Source)"
    $runtimes = & dotnet --list-runtimes 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Installed runtimes:"
        $runtimes | ForEach-Object { Write-Host "  $_" }
    }
}
else {
    Write-Host "dotnet command not found on this machine."
}

# Check and install if needed
if (Test-DotNetInstalled) {
    Write-Host ""
    Write-Host "PASSED: .NET $MajorVersion ($RuntimeType) is already installed." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host ".NET $MajorVersion ($RuntimeType) is NOT installed. Installing automatically..." -ForegroundColor Yellow

Install-DotNetSilently

# Verify after install
# Refresh PATH so the new dotnet install is visible in this session.
# Prepend Machine+User paths to the existing process PATH to pick up the new
# install location without dropping any process-scoped entries Octopus may have added.
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$combined = @($machinePath, $userPath, $env:Path) | Where-Object { $_ }
$env:Path = ($combined -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'

if (Test-DotNetInstalled) {
    Write-Host ""
    Write-Host "PASSED: .NET $MajorVersion ($RuntimeType) is now installed." -ForegroundColor Green
    exit 0
}
else {
    Write-Host ""
    Write-Error "Installation completed but .NET $MajorVersion ($RuntimeType) could not be verified. A reboot may be required."
    exit 1
}
