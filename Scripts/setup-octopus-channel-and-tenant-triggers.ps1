[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OctopusUrl,

    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [string]$SpaceName = "Default",

    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $false)]
    [string]$ContosoTenantName = "contoso",

    [Parameter(Mandatory = $true)]
    [string[]]$TenantAliases,

    [Parameter(Mandatory = $false)]
    [string[]]$PersonalEnvironmentKeys = @("dev", "uat", "prod"),

    [Parameter(Mandatory = $false)]
    [string]$TenantNameTemplate = "{alias}",

    [Parameter(Mandatory = $false)]
    [string]$PrototypeProjectName,

    [Parameter(Mandatory = $false)]
    [string]$ExportSeedTriggerPath,

    [Parameter(Mandatory = $false)]
    [string]$ExportSeedFromProjectName,

    [Parameter(Mandatory = $false)]
    [string]$ExportSeedTriggerName,

    [Parameter(Mandatory = $false)]
    [string]$SeedTriggerJsonPath,

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,

    [Parameter(Mandatory = $false)]
    [switch]$FailIfTemplatesMissing,

    [Parameter(Mandatory = $false)]
    [switch]$FailIfTenantMissing,

    [Parameter(Mandatory = $false)]
    [switch]$KeepProjectAutoCreateRelease,

    [Parameter(Mandatory = $false)]
    [switch]$DisableProjectAutoCreateRelease,

    [Parameter(Mandatory = $false)]
    [string]$ManagedLifecycleName,

    [Parameter(Mandatory = $false)]
    [switch]$KeepAutomaticDeployToDevelopment,

    [Parameter(Mandatory = $false)]
    [switch]$SkipStandardTrigger

    ,
    [Parameter(Mandatory = $false)]
    [switch]$AllowAnyPersonalAliasInChannels
)

$ErrorActionPreference = "Stop"

$baseUrl = $OctopusUrl.TrimEnd('/')
$header = @{ "X-Octopus-ApiKey" = $ApiKey }

$environmentNameByKey = @{
    "dev" = "Development"
    "uat" = "Test"
    "prod" = "Production"
}

$normalizedPersonalEnvironmentKeys = @($PersonalEnvironmentKeys | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
if ($normalizedPersonalEnvironmentKeys.Count -eq 0) {
    throw "PersonalEnvironmentKeys cannot be empty. Specify one or more of: dev, uat, prod"
}

$unsupportedEnvironmentKeys = @($normalizedPersonalEnvironmentKeys | Where-Object { -not $environmentNameByKey.ContainsKey($_) })
if ($unsupportedEnvironmentKeys.Count -gt 0) {
    throw "Unsupported PersonalEnvironmentKeys value(s): $($unsupportedEnvironmentKeys -join ', '). Supported values: dev, uat, prod"
}

$normalizedTenantAliases = @($TenantAliases | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
if ($normalizedTenantAliases.Count -eq 0) {
    throw "TenantAliases cannot be empty"
}

$escapedAliasPatterns = @($normalizedTenantAliases | ForEach-Object { [regex]::Escape($_) })
$personalAliasPattern = $escapedAliasPatterns -join "|"

if ($AllowAnyPersonalAliasInChannels) {
    $personalAliasPattern = "[0-9A-Za-z][0-9A-Za-z-]*"
}

$channelMatrix = @(
    @{ Name = "standard"; IsDefault = $true;  Tag = "^$" },
    @{ Name = "personal-dev"; IsDefault = $false; Tag = "^dev\.($personalAliasPattern)$" },
    @{ Name = "personal-uat"; IsDefault = $false; Tag = "^uat\.($personalAliasPattern)$" },
    @{ Name = "personal-prod"; IsDefault = $false; Tag = "^prod\.($personalAliasPattern)$" }
)

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

function Normalize-Clone {
    param([object]$Resource)

    $clone = $Resource | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $clone.Id = $null
    $clone.Links = $null
    return $clone
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
                    DeploymentActionId = $action.Id
                    DeploymentActionSlug = $action.Slug
                    PackageReference = if ($null -ne $package.Name) { [string]$package.Name } else { "" }
                }
            }
        }
    }

    return @($bindings)
}

function Get-DeployTriggerPrototype {
    param([object[]]$Triggers)

    if (-not $Triggers) { return $null }

    $deployCandidates = @($Triggers |
        Where-Object {
            $_.Action -and
            $_.Action.ActionType -and
            ($_.Action.ActionType -eq "DeployNewRelease" -or $_.Action.ActionType -eq "DeployLatestRelease" -or $_.Action.ActionType -eq "DeployLatestReleaseToEnvironment")
        })

    if ($deployCandidates.Count -eq 0) { return $null }

    $feedDeployCandidate = $deployCandidates |
        Where-Object {
            $_.Filter -and
            $_.Filter.FilterType -and
            ($_.Filter.FilterType -eq "FeedFilter" -or $_.Filter.FilterType -eq "ArcFeedFilter")
        } |
        Select-Object -First 1

    if ($feedDeployCandidate) {
        return $feedDeployCandidate
    }

    $nonProbeCandidate = $deployCandidates |
        Where-Object { $_.Name -notmatch '^probe-' } |
        Select-Object -First 1

    if ($nonProbeCandidate) {
        return $nonProbeCandidate
    }

    return $deployCandidates | Select-Object -First 1
}

function Get-TriggerActionSummary {
    param([object[]]$Triggers)

    if (-not $Triggers) { return @() }

    return $Triggers |
        ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                ActionType = if ($_.Action -and $null -ne $_.Action.ActionType) { $_.Action.ActionType } else { "<none>" }
            }
        } |
        Sort-Object ActionType, Name
}

function Get-ProjectTriggerSummary {
    param([object[]]$Triggers)

    if (-not $Triggers) { return @() }

    return $Triggers |
        ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                ActionType = if ($_.Action -and $null -ne $_.Action.ActionType) { $_.Action.ActionType } else { "<none>" }
                FilterType = if ($_.Filter -and $null -ne $_.Filter.FilterType) { $_.Filter.FilterType } else { "<none>" }
                ChannelId = if ($_.Action -and $null -ne $_.Action.ChannelId) { $_.Action.ChannelId } else { "<none>" }
            }
        } |
        Sort-Object Name
}

function Resolve-TenantByAlias {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Tenants,
        [Parameter(Mandatory = $true)]
        [string]$Alias,
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentKey,
        [Parameter(Mandatory = $true)]
        [string]$Template
    )

    $aliasValue = $Alias.Trim()
    if ([string]::IsNullOrWhiteSpace($aliasValue)) {
        throw "Tenant alias cannot be empty"
    }

    $resolvedFromTemplate = $Template
    $resolvedFromTemplate = $resolvedFromTemplate.Replace("{alias}", $aliasValue)
    $resolvedFromTemplate = $resolvedFromTemplate.Replace("{aliasLower}", $aliasValue.ToLowerInvariant())
    $resolvedFromTemplate = $resolvedFromTemplate.Replace("{aliasUpper}", $aliasValue.ToUpperInvariant())
    $resolvedFromTemplate = $resolvedFromTemplate.Replace("{env}", $EnvironmentKey)
    $resolvedFromTemplate = $resolvedFromTemplate.Replace("{envLower}", $EnvironmentKey.ToLowerInvariant())
    $resolvedFromTemplate = $resolvedFromTemplate.Replace("{envUpper}", $EnvironmentKey.ToUpperInvariant())

    $candidateSet = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    $candidateList = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @(
        $resolvedFromTemplate,
        $aliasValue,
        "$($EnvironmentKey.ToUpperInvariant())-$aliasValue",
        "$($EnvironmentKey.ToLowerInvariant())-$aliasValue",
        "$($EnvironmentKey.ToUpperInvariant())_$aliasValue",
        "$($EnvironmentKey.ToLowerInvariant())_$aliasValue"
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and $candidateSet.Add($candidate)) {
            $candidateList.Add($candidate)
        }
    }

    foreach ($candidate in $candidateList) {
        $match = $Tenants | Where-Object { $_.Name -ieq $candidate } | Select-Object -First 1
        if ($match) {
            return @{
                Tenant = $match
                MatchedCandidate = $candidate
            }
        }
    }

    $containsMatches = $Tenants |
        Where-Object { $_.Name -match [regex]::Escape($aliasValue) } |
        Select-Object -First 10 -ExpandProperty Name

    $candidatesDisplay = ($candidateList -join ", ")
    if ($containsMatches -and $containsMatches.Count -gt 0) {
        $containsDisplay = ($containsMatches -join ", ")
        throw "No tenant matched alias '$aliasValue' for environment '$EnvironmentKey'. Tried: $candidatesDisplay. Nearby tenant names: $containsDisplay"
    }

    throw "No tenant matched alias '$aliasValue' for environment '$EnvironmentKey'. Tried: $candidatesDisplay"
}

function Apply-TriggerRouting {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Trigger,
        [Parameter(Mandatory = $true)]
        [string]$ProjectId,
        [Parameter(Mandatory = $true)]
        [string]$ChannelId,
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentId,
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )

    $Trigger.ProjectId = $ProjectId
    $Trigger.Action.ChannelId = $ChannelId

    $actionPropertyNames = @($Trigger.Action.PSObject.Properties.Name)
    if ($actionPropertyNames -contains "EnvironmentId") {
        $Trigger.Action.EnvironmentId = $EnvironmentId
    }
    if ($actionPropertyNames -contains "EnvironmentIds") {
        $Trigger.Action.EnvironmentIds = @($EnvironmentId)
    }
    if ($actionPropertyNames -contains "DestinationEnvironmentId") {
        $Trigger.Action.DestinationEnvironmentId = $EnvironmentId
    }
    if ($actionPropertyNames -contains "SourceEnvironmentIds") {
        if ($null -eq $Trigger.Action.SourceEnvironmentIds -or $Trigger.Action.SourceEnvironmentIds.Count -eq 0) {
            $Trigger.Action.SourceEnvironmentIds = @($EnvironmentId)
        }
    }

    if ($Trigger.Filter) {
        $filterPropertyNames = @($Trigger.Filter.PSObject.Properties.Name)
        if ($filterPropertyNames -contains "EnvironmentIds") {
            $Trigger.Filter.EnvironmentIds = @($EnvironmentId)
        }
    }

    $Trigger.Action.TenantIds = @($TenantId)
    $Trigger.Action.TenantTags = @()
}

function Ensure-ProjectLifecycleDisablesAutoDeployToDevelopment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectId,
        [Parameter(Mandatory = $true)]
        [string]$ProjectName,
        [Parameter(Mandatory = $true)]
        [string]$CurrentLifecycleId,
        [Parameter(Mandatory = $true)]
        [string]$DevelopmentEnvironmentId,
        [Parameter(Mandatory = $false)]
        [string]$DesiredLifecycleName,
        [Parameter(Mandatory = $false)]
        [switch]$WhatIf
    )

    if ([string]::IsNullOrWhiteSpace($DesiredLifecycleName)) {
        $DesiredLifecycleName = "$ProjectName - Managed Personal Deploy"
    }

    $currentLifecycle = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/lifecycles/$CurrentLifecycleId"
    $autoDevPhase = @($currentLifecycle.Phases | Where-Object { $_.AutomaticDeploymentTargets -and ($_.AutomaticDeploymentTargets -contains $DevelopmentEnvironmentId) })
    if ($autoDevPhase.Count -eq 0) {
        return $CurrentLifecycleId
    }

    $allLifecycles = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/lifecycles/all"
    $existing = $allLifecycles | Where-Object { $_.Name -eq $DesiredLifecycleName } | Select-Object -First 1

    $managedLifecycleId = $null
    if ($existing) {
        $managedLifecycleId = $existing.Id
    }
    else {
        $payload = Normalize-Clone -Resource $currentLifecycle
        $payload.Name = $DesiredLifecycleName
        $payload.Slug = $null

        foreach ($phase in $payload.Phases) {
            if ($phase.AutomaticDeploymentTargets -and ($phase.AutomaticDeploymentTargets -contains $DevelopmentEnvironmentId)) {
                $phase.AutomaticDeploymentTargets = @($phase.AutomaticDeploymentTargets | Where-Object { $_ -ne $DevelopmentEnvironmentId })
                if (-not $phase.OptionalDeploymentTargets) {
                    $phase.OptionalDeploymentTargets = @()
                }
                if (-not ($phase.OptionalDeploymentTargets -contains $DevelopmentEnvironmentId)) {
                    $phase.OptionalDeploymentTargets += $DevelopmentEnvironmentId
                }
            }
        }

        if ($WhatIf) {
            Write-Host "[WhatIf] POST lifecycle '$DesiredLifecycleName' (disable auto-deploy to Development)"
            $managedLifecycleId = "WhatIf-Lifecycle"
        }
        else {
            $created = Invoke-OctoPost -Uri "$baseUrl/api/$spaceId/lifecycles" -Body $payload
            $managedLifecycleId = $created.Id
            Write-Host "Created managed lifecycle '$DesiredLifecycleName' ($managedLifecycleId)"
        }
    }

    if (-not $WhatIf) {
        $projectDetails = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$ProjectId"
        if ($projectDetails.LifecycleId -ne $managedLifecycleId) {
            $projectPayload = Normalize-Clone -Resource $projectDetails
            $projectPayload.Id = $projectDetails.Id
            $projectPayload.LifecycleId = $managedLifecycleId
            Invoke-OctoPut -Uri "$baseUrl/api/$spaceId/projects/$ProjectId" -Body $projectPayload | Out-Null
            Write-Host "Updated project '$ProjectName' (assigned managed lifecycle)"
        }
    }

    return $managedLifecycleId
}

Write-Host "Resolving space/project/tenants/environments..."
$spaces = Invoke-OctoGet -Uri "$baseUrl/api/spaces/all"
$space = Find-ByName -Items $spaces -Name $SpaceName
$spaceId = $space.Id

$projects = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/all"
$project = Find-ByName -Items $projects -Name $ProjectName
$projectId = $project.Id

$projectDetails = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$projectId"
if ($DisableProjectAutoCreateRelease -and -not $KeepProjectAutoCreateRelease -and $projectDetails.AutoCreateRelease) {
    $projectPayload = Normalize-Clone -Resource $projectDetails
    $projectPayload.Id = $projectDetails.Id
    $projectPayload.AutoCreateRelease = $false

    if ($WhatIf) {
        Write-Host "[WhatIf] PUT project '$ProjectName' (AutoCreateRelease: true -> false)"
    }
    else {
        Invoke-OctoPut -Uri "$baseUrl/api/$spaceId/projects/$projectId" -Body $projectPayload | Out-Null
        Write-Host "Updated project '$ProjectName' (AutoCreateRelease disabled)"
    }
}

$allEnvironments = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/environments/all"
$developmentEnvironment = Find-ByName -Items $allEnvironments -Name $environmentNameByKey["dev"]

if (-not $KeepAutomaticDeployToDevelopment -and -not [string]::IsNullOrWhiteSpace($projectDetails.LifecycleId)) {
    $managedLifecycle = Ensure-ProjectLifecycleDisablesAutoDeployToDevelopment -ProjectId $projectId -ProjectName $ProjectName -CurrentLifecycleId $projectDetails.LifecycleId -DevelopmentEnvironmentId $developmentEnvironment.Id -DesiredLifecycleName $ManagedLifecycleName -WhatIf:$WhatIf
    if ($WhatIf -and $managedLifecycle -eq 'WhatIf-Lifecycle') {
        Write-Host "[WhatIf] Would assign project '$ProjectName' to managed lifecycle '$($ManagedLifecycleName ?? ("$ProjectName - Managed Personal Deploy"))'"
    }
}

if (-not [string]::IsNullOrWhiteSpace($ExportSeedTriggerPath)) {
    $sourceProjectName = if (-not [string]::IsNullOrWhiteSpace($ExportSeedFromProjectName)) { $ExportSeedFromProjectName } elseif (-not [string]::IsNullOrWhiteSpace($PrototypeProjectName)) { $PrototypeProjectName } else { $ProjectName }
    $sourceProject = Find-ByName -Items $projects -Name $sourceProjectName
    $sourceProjectTriggersResponse = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$($sourceProject.Id)/triggers"
    $sourceTriggers = @($sourceProjectTriggersResponse.Items)

    $deployTriggers = $sourceTriggers |
        Where-Object {
            $_.Action -and
            $_.Action.ActionType -and
            ($_.Action.ActionType -eq "DeployNewRelease" -or $_.Action.ActionType -eq "DeployLatestRelease" -or $_.Action.ActionType -eq "DeployLatestReleaseToEnvironment")
        }

    if (-not [string]::IsNullOrWhiteSpace($ExportSeedTriggerName)) {
        $deployTriggers = $deployTriggers | Where-Object { $_.Name -eq $ExportSeedTriggerName }
    }

    $seedTrigger = $deployTriggers | Select-Object -First 1
    if (-not $seedTrigger) {
        Write-Warning "No deploy trigger found to export from project '$sourceProjectName'."
        $summary = Get-TriggerActionSummary -Triggers $sourceTriggers
        if ($summary.Count -gt 0) {
            Write-Host "Available trigger action types on '$sourceProjectName':"
            $summary | Format-Table -AutoSize | Out-String | Write-Host
        }
        throw "Task blocked: cannot export seed trigger JSON because no deploy trigger exists on source project '$sourceProjectName'."
    }

    $seedPayload = Normalize-Clone -Resource $seedTrigger
    $seedPayload.ProjectId = $null

    $targetDirectory = Split-Path -Path $ExportSeedTriggerPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($targetDirectory) -and -not (Test-Path -Path $targetDirectory)) {
        New-Item -Path $targetDirectory -ItemType Directory -Force | Out-Null
    }

    $seedPayload | ConvertTo-Json -Depth 20 | Set-Content -Path $ExportSeedTriggerPath -Encoding UTF8
    Write-Host "Exported deploy-trigger seed JSON to '$ExportSeedTriggerPath' from trigger '$($seedTrigger.Name)' on project '$sourceProjectName'."
}

$allTenants = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/tenants/all"

$deploymentProcess = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$projectId/deploymentprocesses"
$builtInPackageBindings = Get-BuiltInPackageBindings -DeploymentProcess $deploymentProcess
if ($builtInPackageBindings.Count -eq 0) {
    throw "No built-in package step bindings were found on project '$ProjectName'. Cannot provision package-feed triggers."
}

$feedFilterPackages = @($builtInPackageBindings | ForEach-Object {
    @{
        DeploymentActionSlug = $_.DeploymentActionSlug
        PackageReference = $_.PackageReference
    }
})

$channelRuleActionPackages = @($builtInPackageBindings | ForEach-Object {
    @{
        DeploymentAction = $_.DeploymentActionId
        PackageReference = $_.PackageReference
    }
})

$channelsResponse = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$projectId/channels"
$channels = @($channelsResponse.Items)

Write-Host "Upserting channels and pre-release rules..."
foreach ($channelSpec in $channelMatrix) {
    $existing = $channels | Where-Object { $_.Name -eq $channelSpec.Name } | Select-Object -First 1

    $rules = @(
        @{
            VersionRange = ""
            Tag = $channelSpec.Tag
            ActionPackages = $channelRuleActionPackages
        }
    )

    if ($existing) {
        $payload = Normalize-Clone -Resource $existing
        $payload.Id = $existing.Id
        $payload.Name = $channelSpec.Name
        $payload.Description = "Managed by setup-octopus-channel-and-tenant-triggers.ps1"
        $payload.IsDefault = $channelSpec.IsDefault
        $payload.ProjectId = $projectId
        $payload.Rules = $rules

        if ($WhatIf) {
            Write-Host "[WhatIf] PUT channel '$($channelSpec.Name)'"
        }
        else {
            try {
                Invoke-OctoPut -Uri "$baseUrl/api/$spaceId/channels/$($existing.Id)" -Body $payload | Out-Null
            }
            catch {
                $channelUpdateError = $_ | Out-String
                if ($channelUpdateError -match "Version rules must specify a package step") {
                    Write-Warning "Channel '$($channelSpec.Name)' rules require package-step bindings on this project. Retrying update without rules."
                    $payload.Rules = @()
                    Invoke-OctoPut -Uri "$baseUrl/api/$spaceId/channels/$($existing.Id)" -Body $payload | Out-Null
                }
                else {
                    throw
                }
            }

            Write-Host "Updated channel '$($channelSpec.Name)'"
        }
    }
    else {
        $payload = @{
            ProjectId = $projectId
            Name = $channelSpec.Name
            Description = "Managed by setup-octopus-channel-and-tenant-triggers.ps1"
            IsDefault = $channelSpec.IsDefault
            Rules = $rules
        }

        if ($WhatIf) {
            Write-Host "[WhatIf] POST channel '$($channelSpec.Name)'"
        }
        else {
            try {
                Invoke-OctoPost -Uri "$baseUrl/api/$spaceId/channels" -Body $payload | Out-Null
            }
            catch {
                $channelCreateError = $_ | Out-String
                if ($channelCreateError -match "Version rules must specify a package step") {
                    Write-Warning "Channel '$($channelSpec.Name)' rules require package-step bindings on this project. Retrying create without rules."
                    $payload.Rules = @()
                    Invoke-OctoPost -Uri "$baseUrl/api/$spaceId/channels" -Body $payload | Out-Null
                }
                else {
                    throw
                }
            }

            Write-Host "Created channel '$($channelSpec.Name)'"
        }
    }
}

$channelsResponse = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$projectId/channels"
$channels = @($channelsResponse.Items)
$channelByName = @{}
foreach ($channel in $channels) {
    $channelByName[$channel.Name] = $channel
}

if ($WhatIf) {
    foreach ($channelSpec in $channelMatrix) {
        if (-not $channelByName.ContainsKey($channelSpec.Name)) {
            $placeholderChannel = [PSCustomObject]@{
                Id = "WhatIf-$($channelSpec.Name)"
                Name = $channelSpec.Name
            }

            $channelByName[$channelSpec.Name] = $placeholderChannel
            Write-Host "[WhatIf] Assigned placeholder id '$($placeholderChannel.Id)' for channel '$($channelSpec.Name)'"
        }
    }
}

Write-Host "Resolving trigger templates..."
$projectTriggersResponse = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$projectId/triggers"
$projectTriggers = @($projectTriggersResponse.Items)

$templateByName = @{}
$templateByName["standard"] = $projectTriggers | Where-Object { $_.Name -eq "TEMPLATE-deploy-standard" } | Select-Object -First 1
$templateByName["dev"] = $projectTriggers | Where-Object { $_.Name -eq "TEMPLATE-deploy-personal-dev" } | Select-Object -First 1
$templateByName["uat"] = $projectTriggers | Where-Object { $_.Name -eq "TEMPLATE-deploy-personal-uat" } | Select-Object -First 1
$templateByName["prod"] = $projectTriggers | Where-Object { $_.Name -eq "TEMPLATE-deploy-personal-prod" } | Select-Object -First 1

$missingTemplateNames = New-Object System.Collections.Generic.List[string]
$missingTemplateKeys = New-Object System.Collections.Generic.List[string]
foreach ($key in @("standard", "dev", "uat", "prod")) {
    if (-not $templateByName[$key]) {
        $missingTemplateKeys.Add($key)
        $missingTemplateNames.Add("TEMPLATE-deploy-$($key -eq "standard" ? "standard" : "personal-$key")")
    }
}

if ($missingTemplateNames.Count -gt 0) {
    $prototype = $null

    if (-not [string]::IsNullOrWhiteSpace($PrototypeProjectName)) {
        $prototypeSourceProject = Find-ByName -Items $projects -Name $PrototypeProjectName
        $prototypeSourceTriggersResponse = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$($prototypeSourceProject.Id)/triggers"
        $prototype = Get-DeployTriggerPrototype -Triggers @($prototypeSourceTriggersResponse.Items)
    }

    if (-not $prototype) {
        $prototype = Get-DeployTriggerPrototype -Triggers $projectTriggers
    }

    if (-not $prototype) {
        $allProjectTriggersResponse = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projecttriggers?skip=0&take=10000"
        $prototype = Get-DeployTriggerPrototype -Triggers @($allProjectTriggersResponse.Items)
    }

    if (-not $prototype -and -not [string]::IsNullOrWhiteSpace($SeedTriggerJsonPath)) {
        if (-not (Test-Path -Path $SeedTriggerJsonPath)) {
            throw "Seed trigger JSON file was not found: $SeedTriggerJsonPath"
        }

        $seedRaw = Get-Content -Path $SeedTriggerJsonPath -Raw
        if ([string]::IsNullOrWhiteSpace($seedRaw)) {
            throw "Seed trigger JSON file is empty: $SeedTriggerJsonPath"
        }

        $seedTrigger = $seedRaw | ConvertFrom-Json
        if (-not $seedTrigger.Action -or -not $seedTrigger.Action.ActionType) {
            throw "Seed trigger JSON does not contain Action.ActionType"
        }

        if ($seedTrigger.Action.ActionType -ne "DeployNewRelease" -and $seedTrigger.Action.ActionType -ne "DeployLatestRelease" -and $seedTrigger.Action.ActionType -ne "DeployLatestReleaseToEnvironment") {
            throw "Seed trigger JSON action type '$($seedTrigger.Action.ActionType)' is not a deploy trigger type"
        }

        $prototype = $seedTrigger
        Write-Warning "Using seed trigger JSON from '$SeedTriggerJsonPath' to bootstrap trigger provisioning."
    }

    if ($prototype) {
        foreach ($missingKey in $missingTemplateKeys) {
            $templateByName[$missingKey] = $prototype
        }

        $prototypeFilterType = if ($prototype.Filter -and $null -ne $prototype.Filter.FilterType) { $prototype.Filter.FilterType } else { "<none>" }
        if ($prototypeFilterType -ne "FeedFilter" -and $prototypeFilterType -ne "ArcFeedFilter") {
            Write-Warning "Prototype trigger '$($prototype.Name)' uses FilterType '$prototypeFilterType'. The script will overwrite filter payloads with FeedFilter for generated auto triggers."
        }

        Write-Warning "Template trigger(s) missing: $((($missingTemplateNames | Sort-Object) -join ', ')). Using prototype trigger '$($prototype.Name)' ($($prototype.Action.ActionType)) to continue provisioning."
    }
    else {
        $missingDisplay = ($missingTemplateNames | Sort-Object) -join ", "
        $message = "Template trigger(s) not found on project '$ProjectName': $missingDisplay"

        if ($FailIfTemplatesMissing) {
            throw "$message. Create template triggers once in Octopus UI/API, then re-run script."
        }

        Write-Warning $message
        Write-Warning "No deploy trigger prototype was found to bootstrap from. Skipping trigger provisioning. Channels and channel rules were still applied."
        Write-Host "Complete (channels only)."
        return
    }
}

$contosoTenant = Find-ByName -Items $allTenants -Name $ContosoTenantName

if (-not $SkipStandardTrigger) {
    $standardEnvironment = Find-ByName -Items $allEnvironments -Name $environmentNameByKey["dev"]
    $standardTriggerName = "auto-standard-contoso"
    $standardExisting = $projectTriggers | Where-Object { $_.Name -eq $standardTriggerName } | Select-Object -First 1
    $standardTemplate = $templateByName["standard"]
    $standardTrigger = Normalize-Clone -Resource $standardTemplate
    $standardTrigger.Name = $standardTriggerName
    $standardTrigger.Filter = @{
        FilterType = "FeedFilter"
        Packages = $feedFilterPackages
    }
    Apply-TriggerRouting -Trigger $standardTrigger -ProjectId $projectId -ChannelId $channelByName["standard"].Id -EnvironmentId $standardEnvironment.Id -TenantId $contosoTenant.Id

    if ($standardExisting) {
        $standardTrigger.Id = $standardExisting.Id
        if ($WhatIf) {
            Write-Host "[WhatIf] PUT trigger '$standardTriggerName'"
        }
        else {
            Invoke-OctoPut -Uri "$baseUrl/api/$spaceId/projects/$projectId/triggers/$($standardExisting.Id)" -Body $standardTrigger | Out-Null
            Write-Host "Updated trigger '$standardTriggerName'"
        }
    }
    else {
        if ($WhatIf) {
            Write-Host "[WhatIf] POST trigger '$standardTriggerName'"
        }
        else {
            Invoke-OctoPost -Uri "$baseUrl/api/$spaceId/projects/$projectId/triggers" -Body $standardTrigger | Out-Null
            Write-Host "Created trigger '$standardTriggerName'"
        }
    }
}

foreach ($envKey in $normalizedPersonalEnvironmentKeys) {
    $envName = $environmentNameByKey[$envKey]
    $environment = Find-ByName -Items $allEnvironments -Name $envName
    $channel = $channelByName["personal-$envKey"]
    $template = $templateByName[$envKey]

    foreach ($alias in $TenantAliases) {
        $tenantAlias = $alias.Trim()
        if ([string]::IsNullOrWhiteSpace($tenantAlias)) { continue }

        try {
            $resolvedTenant = Resolve-TenantByAlias -Tenants $allTenants -Alias $tenantAlias -EnvironmentKey $envKey -Template $TenantNameTemplate
        }
        catch {
            if ($FailIfTenantMissing) {
                throw
            }

            Write-Warning "Skipping tenant alias '$tenantAlias' for environment '$envKey': $($_.Exception.Message)"
            continue
        }

        $tenant = $resolvedTenant.Tenant

        $tenantAliasToken = ($tenantAlias.ToLowerInvariant() -replace '[^a-z0-9-]', '-').Trim('-')
        if ([string]::IsNullOrWhiteSpace($tenantAliasToken)) {
            $tenantAliasToken = "tenant"
        }

        $triggerName = "auto-personal-$envKey-$tenantAliasToken"
        $existing = $projectTriggers | Where-Object { $_.Name -eq $triggerName } | Select-Object -First 1

        $trigger = Normalize-Clone -Resource $template
        $trigger.Name = $triggerName
        $trigger.Filter = @{
            FilterType = "FeedFilter"
            Packages = $feedFilterPackages
        }
        Apply-TriggerRouting -Trigger $trigger -ProjectId $projectId -ChannelId $channel.Id -EnvironmentId $environment.Id -TenantId $tenant.Id

        Write-Host "Tenant alias '$tenantAlias' ($envKey) resolved to tenant '$($tenant.Name)' using candidate '$($resolvedTenant.MatchedCandidate)'"

        if ($existing) {
            $trigger.Id = $existing.Id
            if ($WhatIf) {
                Write-Host "[WhatIf] PUT trigger '$triggerName'"
            }
            else {
                Invoke-OctoPut -Uri "$baseUrl/api/$spaceId/projects/$projectId/triggers/$($existing.Id)" -Body $trigger | Out-Null
                Write-Host "Updated trigger '$triggerName'"
            }
        }
        else {
            if ($WhatIf) {
                Write-Host "[WhatIf] POST trigger '$triggerName'"
            }
            else {
                Invoke-OctoPost -Uri "$baseUrl/api/$spaceId/projects/$projectId/triggers" -Body $trigger | Out-Null
                Write-Host "Created trigger '$triggerName'"
            }
        }
    }
}

if (-not $WhatIf) {
    $finalTriggersResponse = Invoke-OctoGet -Uri "$baseUrl/api/$spaceId/projects/$projectId/triggers"
    $finalTriggers = @($finalTriggersResponse.Items)
    $managedTriggerSummary = Get-ProjectTriggerSummary -Triggers @($finalTriggers | Where-Object { $_.Name -eq "auto-standard-contoso" -or $_.Name -like "auto-personal-*" -or $_.Name -eq "Built-in Feed Trigger" -or $_.Name -like "probe-*" })

    if ($managedTriggerSummary.Count -gt 0) {
        Write-Host "Trigger summary (ActionType/FilterType):"
        $managedTriggerSummary | Format-Table -AutoSize | Out-String | Write-Host
    }
}

Write-Host "Complete."
