param(
    [Parameter(Mandatory = $false)] [string]$ProjectId, # Id of the project to link, e.g. Projects-1
    [Parameter(Mandatory = $false)] [string]$ProjectSpaceId, # Id of the space where the project exists, e.g. Spaces-1
    [Parameter(Mandatory = $false)] [boolean]$VerboseOutput = $true # When true, REST actions and matching operations will be logged
)

$Octopus = @{
    ApiKey = $env:OCTOPUS_API_KEY
    Uri    = $env:OCTOPUS_INSTANCE
}

$Environments = @{
    Development = @{
        Id      = $null
        Tenants = @(
            @{ Id = $null; Name = 'Contoso' }
        )
    }
    Test        = @{
        Id      = $null
        Tenants = @(
            @{ Id = $null; Name = 'Fabrikam' }
        )
    }
    Production  = @{
        Id      = $null
        Tenants = $null
    }
}

$Project = @{
    Id    = $ProjectId
    Name  = $null
    Space = @{
        Id   = $ProjectSpaceId
        Name = $null
    }
}

$Request = @{
    Method  = $null
    Uri     = $null
    Headers = @{ 'X-Octopus-ApiKey' = $Octopus.ApiKey }
}

$Response = $null

# Function: Get all environments in a space
function GetEnvironments {
    # Set up request
    $Request.Method = 'GET'
    $Request.Uri = '{0}/api/{1}/environments/all' -f $Octopus.Uri, $Project.Space.Id
    
    # Output current action (and request uri if verbose)
    Write-Host 'Looking up environments...'
    ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null
            
    # Execute the request
    $Response = Invoke-RestMethod @Request
    foreach ($Object in $Response) {
        Write-Host (" [✓] Environment '{0}' ({1})" -f $Object.Name, $Object.Id)

    }
    Write-Host "Environments found.`n"

    # Map default tenants to environments
    Write-Host 'Mapping defaults...'
    foreach ($Object in $Response) {
        if ($Object.PSObject.Properties.Name -contains 'Name') {
            foreach ($Environment in $Environments.GetEnumerator()) {
                if ($Object.Name -ieq $Environment.Key) {
                    if ($null -ne $Environment.Value.Tenants) {
                        Write-Host $(" [✓] Tenant '{0}' assigned to default environment: '{1}' ({2})" -f (($Environment.Value.Tenants | ForEach-Object { $_.Name }) -join ', '), $Environment.Key, $Object.Id)
                    }
                    $Environments[$Environment.Key].Id = $Object.Id
                }
            }
        }
    }
    Write-Host "Defaults mapped.`n"
}

# Function: Get all tenants in a space
function GetTenants {
    # Set up request
    $Request.Method = 'GET'
    $Request.Uri = '{0}/api/{1}/tenants/all' -f $Octopus.Uri, $Project.Space.Id

    # Output current action (and request uri if verbose)
    Write-Host 'Looking up tenants...'
    ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null
            
    # Execute the request
    $Response = Invoke-RestMethod @Request
    foreach ($Object in $Response) {
        Write-Host (" [✓] Tenant '{0}' ({1})" -f $Object.Name, $Object.Id)
    }
    Write-Host "Tenants found.`n"

    Write-Host 'Mapping tenant environments...'
    if (-not($null -eq $Response)) {
        $Environments['Production'].Tenants = @()

        foreach ($Object in $Response) {
            $Exists = $Environments.Values | Where-Object { 
                $_.Tenants | Where-Object { $_.Name -eq $Object.Name }
            }
            
            if (-not ($Exists.Tenants | Where-Object { $_.Name -eq $Object.Name })) {
                Write-Output " [✓] Tenant '$($Object.Name)' ($($Object.Id)) assigned to environment: 'Production' ($($Environments['Production'].Id))"
                $Environments['Production'].Tenants += [PSCustomObject]@{
                    Id   = $Object.Id
                    Name = $Object.Name
                }
            }
            else {
                # Find the existing tenant and update its Id
                foreach ($Env in $Environments.Values) {
                    $TenantToUpdate = $Env.Tenants | Where-Object { $_.Name -eq $Object.Name }
                    if ($TenantToUpdate) {
                        $TenantToUpdate.Id = $Object.Id
                        Write-Output " Updated Tenant Id for '$($Object.Name)' ($($Object.Id))"
                        break
                    }
                }
            }
        }
    }

    Write-Host "Tenant environments mapped.`n`nSummary: $($Environments | ConvertTo-Json -Depth 3)`n"
}

# Function: Update tenants with project-environment mapping
function LinkTenants {
    Write-Host 'Updating tenants...'
    # Iterate through each environment
    foreach ($EnvironmentName in $Environments.Keys) {
        $Environment = $Environments[$EnvironmentName]

        Write-Host "Processing environment: $EnvironmentName"
        foreach ($Tenant in $Environment.Tenants) {
            # Set up request
            $Request.Method = 'GET'
            $Request.Uri = '{0}/api/{1}/tenants/{2}' -f $Octopus.Uri, $Project.Space.Id, $Tenant.Id

            # Output current action (and request uri if verbose)
            Write-Host "Looking up tenant '$($Tenant.Name)'..."
            ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null
            
            # Execute the request
            $Response = Invoke-RestMethod @Request

            foreach ($Object in $Response) {
                $ProjectEnvironments = @{}
                foreach ($Property in $Object.ProjectEnvironments.PSObject.Properties) {
                    $ProjectEnvironments[$Property.Name] = $Property.Value
                }
                $ProjectEnvironments[$Project.Id] = @($Environment.Id)
                $Object.ProjectEnvironments = $ProjectEnvironments

                # Set up request & payload
                $Request.Method = 'PUT'
                $Body = ($Object | ConvertTo-Json -Depth 10)

                # Output current action (and request uri if verbose)
                Write-Host "Updating tenant '$($Tenant.Name)'..."
                ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null

                # Execute the request
                $Response = Invoke-RestMethod @Request -Body $Body

                # Check response for update
                foreach ($Object in $Response.ProjectEnvironments) {
                    if ($Object.PSObject.Properties.Name -contains $Project.Id) {
                        # ($Object | ConvertTo-Json)
                        Write-Host (" [✓] Tenant linked`n")
                    }
                }
            }
        }
    }
    Write-Host "Tenants updated.`n"
}

GetEnvironments
GetTenants
LinkTenants
