<#
.SYNOPSIS
    Replicates channel definitions from a reference Octopus project to one or more target projects,
    and optionally removes auto-deploy triggers from target projects.

.DESCRIPTION
    Reads channel configurations (names, default flag, pre-release tag rules) from a reference project
    (default: nub_api_agent) and applies them to each target project. Action-package bindings in channel
    rules are discovered dynamically per target project from its deployment process.

    No triggers are created — deployments are driven by GitHub Actions workflows (deploy.personal.yml).
    Use -DeleteTriggerPattern to remove legacy auto-deploy triggers from target projects.

.EXAMPLE
    # Dry run against all nub_*/rep_* projects
    ./setup-octopus-channels.ps1 -OctopusUrl $env:OCTOPUS_APP_URL -ApiKey $env:OCTOPUS_API_KEY -AllNubProjects -WhatIf

.EXAMPLE
    # Apply to specific projects
    ./setup-octopus-channels.ps1 -OctopusUrl $env:OCTOPUS_APP_URL -ApiKey $env:OCTOPUS_API_KEY `
        -TargetProjectNames @("nub_api_customer", "nub_api_telephony")

.EXAMPLE
    # Apply and clean up legacy auto-* triggers
    ./setup-octopus-channels.ps1 -OctopusUrl $env:OCTOPUS_APP_URL -ApiKey $env:OCTOPUS_API_KEY `
        -AllNubProjects -DeleteTriggerPattern "^auto-"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OctopusUrl,

    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [string]$SpaceName = "Default",

    [Parameter(Mandatory = $false)]
    [string]$ReferenceProjectName = "nub_api_agent",

    [Parameter(Mandatory = $false)]
    [string[]]$TargetProjectNames,

    [Parameter(Mandatory = $false)]
    [switch]$AllNubProjects,

    [Parameter(Mandatory = $false)]
    [string]$DeleteTriggerPattern,

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

$baseUrl = $OctopusUrl.TrimEnd('/')
$header = @{ "X-Octopus-ApiKey" = $ApiKey }

# --- Helper functions ---

function Invoke-OctoGet {
    param([string]$Uri)
    Invoke-RestMethod -Method Get -Uri $Uri -Headers $header
}

function Invoke-OctoPost {
    param([string]$Uri, [object]$Body)
    Invoke-RestMethod -Method Post -Uri $Uri -Headers $header -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 20)
}

function Invoke-OctoPut {
    param([string]$Uri, [object]$Body)
    Invoke-RestMethod -Method Put -Uri $Uri -Headers $header -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 20)
}

function Invoke-OctoDelete {
    param([string]$Uri)
    Invoke-RestMethod -Method Delete -Uri $Uri -Headers $header
}

function Find-ByName {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $match = $Items | Where-Object { $_.Name -eq $Name }
    if (-not $match) {
        throw "Resource '$Name' was not found"
    }

    return $match | Select-Object -First 1
}

function Get-BuiltInPackageBindings {
    param([object]$DeploymentProcess)

    $bindings = @()

    foreach ($step in $DeploymentProcess.Steps) {
        foreach ($action in $step.Actions) {
            if (-not $action.Packages) { continue }

            foreach ($package in $action.Packages) {
                if ($package.FeedId -ne "feeds-builtin") { continue }

                $bindings += [PSCustomObject]@{
                    DeploymentActionId   = $action.Id
                    DeploymentActionSlug = $action.Slug
                    PackageReference     = if ($null -ne $package.Name) { [string]$package.Name } else { "" }
                }
            }
        }
    }

    return @($bindings)
}

# --- Resolve space ---

Write-Host "Resolving space '$SpaceName'..."
$spaces = Invoke-OctoGet -Uri "$baseUrl/api/spaces/all"
$space = Find-ByName -Items $spaces -Name $SpaceName
$spaceId = $space.Id
Write-Host "Space: $($space.Name) ($spaceId)"

# --- Resolve all projects ---

$allProjects = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/all"

# --- Resolve reference project and read its channels ---

$referenceProject = Find-ByName -Items $allProjects -Name $ReferenceProjectName
Write-Host "Reference project: $($referenceProject.Name) ($($referenceProject.Id))"

$refChannelsResp = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$($referenceProject.Id)/channels?take=50"
$refChannels = @($refChannelsResp.Items)

if ($refChannels.Count -eq 0) {
    throw "Reference project '$ReferenceProjectName' has no channels"
}

Write-Host "Reference channels ($($refChannels.Count)):"
foreach ($ch in $refChannels | Sort-Object Name) {
    $tagDisplay = if ($ch.Rules -and $ch.Rules.Count -gt 0) { $ch.Rules[0].Tag } else { "(no rules)" }
    Write-Host "  $($ch.Name) | IsDefault=$($ch.IsDefault) | Tag='$tagDisplay'"
}

# --- Determine target projects ---

$targetProjects = @()

if ($AllNubProjects) {
    $targetProjects = @($allProjects | Where-Object {
        ($_.Name -like "nub_*" -or $_.Name -like "rep_*") -and $_.Name -ne $ReferenceProjectName
    })
}

if ($TargetProjectNames -and $TargetProjectNames.Count -gt 0) {
    foreach ($name in $TargetProjectNames) {
        $proj = Find-ByName -Items $allProjects -Name $name
        if ($targetProjects | Where-Object { $_.Id -eq $proj.Id }) { continue }
        $targetProjects += $proj
    }
}

if ($targetProjects.Count -eq 0) {
    throw "No target projects resolved. Use -TargetProjectNames or -AllNubProjects."
}

Write-Host "`nTarget projects ($($targetProjects.Count)):"
foreach ($p in $targetProjects | Sort-Object Name) {
    Write-Host "  $($p.Name)"
}

# --- Process each target project ---

foreach ($targetProject in ($targetProjects | Sort-Object Name)) {
    $targetProjectId = $targetProject.Id
    $targetProjectName = $targetProject.Name
    Write-Host "`n=========================================="
    Write-Host "Processing: $targetProjectName ($targetProjectId)"
    Write-Host "=========================================="

    # Detect and disable built-in feed trigger (AutoCreateRelease)
    $targetProjectDetails = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$targetProjectId"
    if ($targetProjectDetails.AutoCreateRelease) {
        if ($WhatIf) {
            Write-Host "  [WhatIf] PUT project '$targetProjectName' (AutoCreateRelease: true -> false)"
        }
        else {
            $targetProjectDetails.AutoCreateRelease = $false
            $targetProjectDetails.PSObject.Properties.Remove("Links")
            Invoke-OctoPut -Uri "$baseUrl/api/$spaceId/projects/$targetProjectId" -Body $targetProjectDetails | Out-Null
            Write-Host "  Disabled built-in feed trigger (AutoCreateRelease) on '$targetProjectName'"
        }
    }
    else {
        Write-Host "  Built-in feed trigger already disabled on '$targetProjectName'"
    }

    # Get target project's deployment process for package bindings
    $targetDp = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$targetProjectId/deploymentprocesses"
    $targetBindings = Get-BuiltInPackageBindings -DeploymentProcess $targetDp

    if ($targetBindings.Count -eq 0) {
        Write-Warning "  No built-in package bindings found on '$targetProjectName'. Skipping channel rule action packages."
    }

    # Build action package list for channel rules (per target project)
    $targetActionPackages = @($targetBindings | ForEach-Object {
        @{
            DeploymentAction = $_.DeploymentActionId
            PackageReference = $_.PackageReference
        }
    })

    # Get existing channels on target project
    $targetChannelsResp = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$targetProjectId/channels?take=50"
    $targetChannels = @($targetChannelsResp.Items)
    $targetChannelByName = @{}
    foreach ($ch in $targetChannels) {
        $targetChannelByName[$ch.Name] = $ch
    }

    # Upsert channels from reference
    foreach ($refChannel in $refChannels) {
        $channelName = $refChannel.Name
        $isDefault = $refChannel.IsDefault

        # Build rules using reference channel's tag patterns but target project's action packages
        $rules = @()
        if ($refChannel.Rules -and $refChannel.Rules.Count -gt 0) {
            foreach ($refRule in $refChannel.Rules) {
                $rule = @{
                    VersionRange   = if ($null -ne $refRule.VersionRange) { $refRule.VersionRange } else { "" }
                    Tag            = if ($null -ne $refRule.Tag) { $refRule.Tag } else { "" }
                    ActionPackages = $targetActionPackages
                }
                $rules += $rule
            }
        }

        $existing = $targetChannelByName[$channelName]

        if ($existing) {
            # Update existing channel
            $payload = $existing | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $payload.IsDefault = $isDefault
            $payload.Rules = $rules
            # Remove Links to avoid API issues on PUT
            $payload.PSObject.Properties.Remove("Links")

            if ($WhatIf) {
                Write-Host "  [WhatIf] PUT channel '$channelName' (update rules)"
            }
            else {
                try {
                    Invoke-OctoPut -Uri "$baseUrl/api/$spaceId/channels/$($existing.Id)" -Body $payload | Out-Null
                    Write-Host "  Updated channel '$channelName'"
                }
                catch {
                    $err = $_ | Out-String
                    if ($err -match "Version rules must specify a package step") {
                        Write-Warning "  Channel '$channelName' — target project has no matching package steps. Retrying without rules."
                        $payload.Rules = @()
                        Invoke-OctoPut -Uri "$baseUrl/api/$spaceId/channels/$($existing.Id)" -Body $payload | Out-Null
                        Write-Host "  Updated channel '$channelName' (without rules)"
                    }
                    else {
                        throw
                    }
                }
            }
        }
        else {
            # Create new channel
            $payload = @{
                ProjectId = $targetProjectId
                Name      = $channelName
                IsDefault = $isDefault
                Rules     = $rules
            }

            if ($WhatIf) {
                Write-Host "  [WhatIf] POST channel '$channelName'"
            }
            else {
                try {
                    Invoke-OctoPost -Uri "$baseUrl/api/$spaceId/channels" -Body $payload | Out-Null
                    Write-Host "  Created channel '$channelName'"
                }
                catch {
                    $err = $_ | Out-String
                    if ($err -match "Version rules must specify a package step") {
                        Write-Warning "  Channel '$channelName' — target project has no matching package steps. Retrying without rules."
                        $payload.Rules = @()
                        Invoke-OctoPost -Uri "$baseUrl/api/$spaceId/channels" -Body $payload | Out-Null
                        Write-Host "  Created channel '$channelName' (without rules)"
                    }
                    else {
                        throw
                    }
                }
            }
        }
    }

    # --- Delete triggers matching pattern ---

    if (-not [string]::IsNullOrWhiteSpace($DeleteTriggerPattern)) {
        $triggersResp = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$targetProjectId/triggers?take=100"
        $triggers = @($triggersResp.Items)

        $matchingTriggers = @($triggers | Where-Object { $_.Name -match $DeleteTriggerPattern })

        if ($matchingTriggers.Count -eq 0) {
            Write-Host "  No triggers matching pattern '$DeleteTriggerPattern' found."
        }
        else {
            foreach ($trigger in $matchingTriggers) {
                if ($WhatIf) {
                    Write-Host "  [WhatIf] DELETE trigger '$($trigger.Name)' ($($trigger.Id))"
                }
                else {
                    Invoke-OctoDelete -Uri "$baseUrl/api/$spaceId/projects/$targetProjectId/triggers/$($trigger.Id)"
                    Write-Host "  Deleted trigger '$($trigger.Name)'"
                }
            }
        }
    }

    # --- Verify final state ---

    if (-not $WhatIf) {
        $finalChannelsResp = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$targetProjectId/channels?take=50"
        $finalChannels = @($finalChannelsResp.Items)
        Write-Host "  Final channels ($($finalChannels.Count)):"
        foreach ($ch in $finalChannels | Sort-Object Name) {
            $tagDisplay = if ($ch.Rules -and $ch.Rules.Count -gt 0) { $ch.Rules[0].Tag } else { "(no rules)" }
            Write-Host "    $($ch.Name) | IsDefault=$($ch.IsDefault) | Tag='$tagDisplay'"
        }
    }
}

Write-Host "`nComplete."
