<#
.SYNOPSIS
    Installs .NET 10 Runtime if not already installed.

.DESCRIPTION
    Checks if .NET 10 Runtime is installed on the machine. If not present,
    downloads and installs it silently without requiring a reboot.

.PARAMETER RuntimeType
    The type of .NET runtime to install: 'Runtime', 'AspNetCore', 'Desktop', or 'SDK'.
    Defaults to 'Runtime'.

.PARAMETER Force
    Force installation even if .NET 10 is already detected.

.PARAMETER WhatIf
    Shows what would happen without making any changes.

.EXAMPLE
    .\InstallDotNet10.ps1
    Installs .NET 10 Runtime if not already installed.

.EXAMPLE
    .\InstallDotNet10.ps1 -RuntimeType AspNetCore
    Installs ASP.NET Core 10 Runtime if not already installed.

.EXAMPLE
    .\InstallDotNet10.ps1 -RuntimeType SDK
    Installs .NET 10 SDK if not already installed.

.NOTES
    Requires administrative privileges.
    Run PowerShell as Administrator.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Runtime', 'AspNetCore', 'Desktop', 'SDK')]
    [string]$RuntimeType = 'Runtime',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# .NET 10 version to install (update as needed)
$DotNetMajorVersion = 10
$DotNetVersion = "10.0.0"

# Download URLs (update these when .NET 10 is released)
$DownloadUrls = @{
    'Runtime'    = "https://download.visualstudio.microsoft.com/download/pr/dotnet-runtime-$DotNetVersion-win-x64.exe"
    'AspNetCore' = "https://download.visualstudio.microsoft.com/download/pr/aspnetcore-runtime-$DotNetVersion-win-x64.exe"
    'Desktop'    = "https://download.visualstudio.microsoft.com/download/pr/windowsdesktop-runtime-$DotNetVersion-win-x64.exe"
    'SDK'        = "https://download.visualstudio.microsoft.com/download/pr/dotnet-sdk-$DotNetVersion-win-x64.exe"
}

function Test-DotNetInstalled {
    param(
        [int]$MajorVersion,
        [string]$Type
    )

    Write-Host "Checking for .NET $MajorVersion ($Type)..."

    try {
        switch ($Type) {
            'SDK' {
                $sdks = & dotnet --list-sdks 2>$null
                if ($sdks) {
                    $installed = $sdks | Where-Object { $_ -match "^$MajorVersion\." }
                    return $null -ne $installed
                }
            }
            default {
                $runtimes = & dotnet --list-runtimes 2>$null
                if ($runtimes) {
                    $runtimeName = switch ($Type) {
                        'Runtime'    { 'Microsoft.NETCore.App' }
                        'AspNetCore' { 'Microsoft.AspNetCore.App' }
                        'Desktop'    { 'Microsoft.WindowsDesktop.App' }
                    }
                    $installed = $runtimes | Where-Object { $_ -match "^$runtimeName $MajorVersion\." }
                    return $null -ne $installed
                }
            }
        }
    }
    catch {
        Write-Host "dotnet command not found or error checking version"
    }

    return $false
}

function Get-DotNetInstallerUrl {
    param(
        [string]$Type,
        [string]$Version
    )

    # Use the official dotnet-install script to get the correct URL
    # For now, construct based on known pattern
    $baseUrl = "https://builds.dotnet.microsoft.com/dotnet"
    
    switch ($Type) {
        'Runtime' {
            return "$baseUrl/Runtime/$Version/dotnet-runtime-$Version-win-x64.exe"
        }
        'AspNetCore' {
            return "$baseUrl/aspnetcore/Runtime/$Version/aspnetcore-runtime-$Version-win-x64.exe"
        }
        'Desktop' {
            return "$baseUrl/WindowsDesktop/$Version/windowsdesktop-runtime-$Version-win-x64.exe"
        }
        'SDK' {
            return "$baseUrl/Sdk/$Version/dotnet-sdk-$Version-win-x64.exe"
        }
    }
}

function Install-DotNetRuntime {
    param(
        [string]$InstallerPath
    )

    Write-Host "Installing .NET $DotNetMajorVersion ($RuntimeType)..."
    
    $arguments = @('/install', '/quiet', '/norestart')
    
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    
    return $process.ExitCode
}

# Main script execution
Write-Host "============================================"
Write-Host ".NET $DotNetMajorVersion Installation Script"
Write-Host "Runtime Type: $RuntimeType"
Write-Host "============================================"

# Check if already installed
$isInstalled = Test-DotNetInstalled -MajorVersion $DotNetMajorVersion -Type $RuntimeType

if ($isInstalled -and -not $Force) {
    Write-Host ".NET $DotNetMajorVersion ($RuntimeType) is already installed." -ForegroundColor Green
    Write-Host "Use -Force to reinstall."
    exit 0
}

if ($isInstalled -and $Force) {
    Write-Host ".NET $DotNetMajorVersion ($RuntimeType) is installed, but -Force specified. Reinstalling..."
}

# Download the installer
$installerUrl = Get-DotNetInstallerUrl -Type $RuntimeType -Version $DotNetVersion
$installerFileName = Split-Path $installerUrl -Leaf
$tempPath = Join-Path $env:TEMP $installerFileName

if ($PSCmdlet.ShouldProcess(".NET $DotNetMajorVersion $RuntimeType", "Download and Install")) {
    Write-Host "Downloading installer from: $installerUrl"
    
    try {
        # Use TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($installerUrl, $tempPath)
        Write-Host "Downloaded to: $tempPath"
    }
    catch {
        Write-Error "Failed to download installer: $_"
        exit 1
    }

    # Verify download
    if (-not (Test-Path $tempPath)) {
        Write-Error "Installer file not found after download."
        exit 1
    }

    # Install
    $exitCode = Install-DotNetRuntime -InstallerPath $tempPath

    # Clean up
    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue

    # Check result
    switch ($exitCode) {
        0 {
            Write-Host ".NET $DotNetMajorVersion ($RuntimeType) installed successfully." -ForegroundColor Green
        }
        1641 {
            Write-Host ".NET $DotNetMajorVersion ($RuntimeType) installed successfully. A reboot is required." -ForegroundColor Yellow
        }
        3010 {
            Write-Host ".NET $DotNetMajorVersion ($RuntimeType) installed successfully. A reboot is required." -ForegroundColor Yellow
        }
        default {
            Write-Error "Installation failed with exit code: $exitCode"
            exit $exitCode
        }
    }

    # Verify installation
    $verifyInstalled = Test-DotNetInstalled -MajorVersion $DotNetMajorVersion -Type $RuntimeType
    if ($verifyInstalled) {
        Write-Host "Verified: .NET $DotNetMajorVersion ($RuntimeType) is now installed." -ForegroundColor Cyan
    }
    else {
        Write-Warning "Installation completed but verification failed. A reboot may be required."
    }
}
