param(
    [Parameter(Mandatory = $false)] [string]$ProjectSpace, # Target space for the cloned project
    [Parameter(Mandatory = $false)] [string]$ProjectGroup, # Target group for the cloned project
    [Parameter(Mandatory = $false)] [string]$ProjectName, # Name of the project, e.g. nub_api_reports
    [Parameter(Mandatory = $false)] [string]$ProjectType, # Type of project, matching a template slug (api,website)
    [Parameter(Mandatory = $false)] [string]$ArtifactName, # Name of the artifact (versionless) or display name, e.g. ReportsAPI
    [Parameter(Mandatory = $false)] [string]$ProjectLifecycle, # Target lifecycle to use (currently from template source)
    [Parameter(Mandatory = $false)] [string]$ProjectDescription, # Project description
    [Parameter(Mandatory = $false)] [string]$TemplateSpace, # Template space to clone from
    [Parameter(Mandatory = $false)] [string]$TemplateGroup, # Template group to clone from
    [Parameter(Mandatory = $false)] [boolean]$VerboseOutput = $true # When true, REST actions and matching operations will be logged
)

<#
    Input parameter examples
    Note: The mandatory flag is false to prevent interactive execution
    All input parameters are required when running unattended, e.g.

    .\clone-project.ps1 `
      -ProjectSpace 'Default' `
      -ProjectGroup 'Default Project Group' `
      -ProjectName 'nub_clone_example' `
      -ProjectType 'Website' `
      -ArtifactName 'ExampleCloneWeb'
      -ProjectLifecycle 'Default Lifecycle' `
      -ProjectDescription 'Cloned Project Example' `
      -TemplateSpace 'Default' `
      -TemplateGroup 'Templates'
#>

$Octopus = @{
    ApiKey = $env:OCTOPUS_API_KEY
    Uri    = $env:OCTOPUS_INSTANCE
}

$Project = @{
    Template = @{
        Id          = $null
        Name        = $null
        Space       = @{ Id = $null; Name = $TemplateSpace }
        Group       = @{ Id = $null; Name = $TemplateGroup; }
        Lifecycle   = @{ Id = $null; Name = $ProjectLifecycle; }
        ProjectsUri = $null
        Type        = $ProjectType
    }
    Target   = @{
        Id              = $null
        Name            = $ProjectName
        Space           = @{ Id = $null; Name = $ProjectSpace; }
        Group           = @{ Id = $null; Name = $ProjectGroup; }
        Description     = $ProjectDescription
        PackageVariable = @{
            Id          = $null
            Name        = 'Artifact'
            Value       = $ArtifactName
            Type        = 'String'
            IsSensitive = $false
        }
        VariableSet     = @{
            Id        = $null
            Variables = $null
        }
        Slug            = $ProjectName.Replace('_', '-')
    }
}

$Request = @{
    Method  = $null
    Uri     = $null
    Headers = @{ 'X-Octopus-ApiKey' = $Octopus.ApiKey }
}

try {
    <#
        Check input parameters
    #>
    if ([string]::IsNullOrWhiteSpace($ProjectSpace)) { throw "Required input parameter 'ProjectSpace' is empty or was not provided"; exit 1; }
    if ([string]::IsNullOrWhiteSpace($ProjectGroup)) { throw "Required input parameter 'ProjectGroup' is empty or was not provided"; exit 1; }
    if ([string]::IsNullOrWhiteSpace($ProjectName)) { throw "Required input parameter 'ProjectName' is empty or was not provided"; exit 1; }
    if ([string]::IsNullOrWhiteSpace($ProjectType)) { throw "Required input parameter 'ProjectType' is empty or was not provided"; exit 1; }
    if ([string]::IsNullOrWhiteSpace($ProjectLifecycle)) { throw "Required input parameter 'ProjectLifecycle' is empty or was not provided"; exit 1; }
    if ([string]::IsNullOrWhiteSpace($ProjectDescription)) { throw "Required input parameter 'ProjectDescription' is empty or was not provided"; exit 1; }
    if ([string]::IsNullOrWhiteSpace($ArtifactName)) { throw "Required input parameter 'ArtifactName' is empty or was not provided"; exit 1; }
    if ([string]::IsNullOrWhiteSpace($TemplateSpace)) { throw "Required input parameter 'TemplateSpace' is empty or was not provided"; exit 1; }
    if ([string]::IsNullOrWhiteSpace($TemplateGroup)) { throw "Required input parameter 'TemplateGroup' is empty or was not provided"; exit 1; }

    <#
        Get the id of space $ProjectSpace
    #>
    try {
        # Set up request
        $Request.Method = 'GET'
        $Request.Uri = '{0}/api/spaces/all?partialName={1}' -f $Octopus.Uri, $Project.Target.Space.Name

        # Output current action (and request uri if verbose)
        Write-Host "`nLocating target space..."
        ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null
        
        # Execute the request
        $Response = Invoke-RestMethod @Request

        # Locate matching space
        foreach ($Object in $Response) {
            if ($Object.PSObject.Properties.Name -contains 'Name') {
                if ($Object.Name -ieq $Project.Target.Space.Name) {
                    Write-Host (" [✓] Space '{0}' ({1})" -f $Object.Name, $Object.Id)
                    $Project.Target.Space.Id = $Object.Id
                }
                else {
                    if ($VerboseOutput -eq $true) {
                        Write-Host (" [-] Space '{0}' ({1})" -f $Object.Name, $Object.Id)
                    }
                }
            }
        }
        if ($null -eq $Project.Target.Space.Id) {
            if (-not($null -eq $Response[0].Name) -and -not ($null -eq $Response[0].Id)) {
                if ($VerboseOutput -eq $true) {
                    Write-Host 'Selecting first partial match'
                }
                Write-Host (" [✓] Space '{0}' ({1})" -f $Response[0].Name, $Response[0].Id)
                $Project.Target.Space.Id = $Response[0].Id
                $Project.Target.Space.Name = $Response[0].Name
            }
        }
    }
    catch { 
        Write-Error $_ 
        throw
    }
    finally {
        if ($null -eq $Project.Target.Space.Id) {
            Write-Host "Not found.`n"

            Write-Warning ("Invalid target space '{0}'`n" -f $Project.Target.Space.Name)
            throw 'Target space required.'
            exit 1
        }
        else {
            Write-Host "Space found.`n"
        }
    }

    <#
        Check if a project with name $ProjectName exists in space $ProjectSpace
    #>
    try {
        # Set up request
        $Request.Method = 'GET'
        $Request.Uri = '{0}/api/spaces/{1}/search?keyword={2}' -f $Octopus.Uri, $Project.Target.Space.Id, $Project.Target.Name

        # Output current action (and request uri if verbose)
        Write-Host 'Searching existing projects...'
        ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null
        
        # Execute the request
        $Response = Invoke-RestMethod @Request

        # Locate matching project
        if (-not($null -eq $Response)) {
            foreach ($Object in $Response) {
                if ($Object.Name -ieq $Project.Target.Name) {
                    Write-Host (" [✓] Project '{0}' ({1})" -f $Object.Name, $Object.Id)
                    $Project.Target.Id = $Object.Id
                }
                else {
                    if ($VerboseOutput -eq $true) {
                        Write-Host (" [ ] Project '{0}' ({1})" -f $Object.Name, $Object.Id)
                    }
                }
            }
        }
    }
    catch { 
        Write-Error $_ 
        throw 
    }
    finally {
        if ($null -eq $Project.Target.Id) {
            Write-Host "No conflict.`n"
        }
        else {
            Write-Host "Project already setup - exiting.`n"
            exit 0
        }
    }

    <#
        Get the id of space $TemplateSpace
    #>
    if ($Project.Template.Space.Name -ieq $Project.Target.Space.Name ) {
        $Project.Template.Space.Id = $Project.Target.Space.Id 
        Write-Host 'Locating template space (Matches project space)...'
        Write-Host (" [✓] Space '{0}' ({1})" -f $Project.Template.Space.Name, $Project.Template.Space.Id)
        Write-Host "Space found.`n"
    }
    else {
        try {
            # Set up request
            $Request.Method = 'GET'
            $Request.Uri = '{0}/api/spaces/all?partialName={1}' -f $Octopus.Uri, $Project.Template.Space.Name

            # Output current action (and request uri if verbose)
            Write-Host 'Locating template space...'
            ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null
            
            # Execute the request
            $Response = Invoke-RestMethod @Request

            # Locate matching space
            foreach ($Object in $Response) {
                if ($Object.PSObject.Properties.Name -contains 'Name') {
                    if ($Object.Name -ieq $Project.Template.Space.Name) {
                        Write-Host (" [✓] Space '{0}' ({1})" -f $Object.Name, $Object.Id)
                        $Project.Template.Space.Id = $Object.Id
                    }
                    else {
                        if ($VerboseOutput -eq $true) {
                            Write-Host (" [-] Space '{0}' ({1})" -f $Object.Name, $Object.Id)
                        }
                    }
                }
            }
            if ($null -eq $Project.Template.Space.Id) {
                if (-not($null -eq $Response[0].Name) -and -not ($null -eq $Response[0].Id)) {
                    if ($VerboseOutput -eq $true) {
                        Write-Host 'Selecting first partial match'
                    }
                    Write-Host (" [✓] Space '{0}' ({1})" -f $Response[0].Name, $Response[0].Id)
                    $Project.Template.Space.Id = $Response[0].Id
                    $Project.Template.Space.Name = $Response[0].Name
                }
            }
        }
        catch { 
            Write-Error $_ 
            throw 
        }
        finally {
            if ($null -eq $Project.Template.Space.Id) {
                Write-Host "Not found.`n"

                Write-Warning ("Invalid template space '{0}'`n" -f $Project.Template.Space.Name)
                throw 'Template space required.'
                exit 1
            }
            else {
                Write-Host "Space found.`n"
            }
        }
    }

    <#
        Get the template group from space $TemplateSpace, $TemplateGroup
    #>
    try {
        # Set up request
        $Request.Method = 'GET'
        $Request.Uri = '{0}/api/{1}/projectgroups/all' -f $Octopus.Uri, $Project.Template.Space.Id

        # Output current action (and request uri if verbose)
        Write-Host 'Locating template group...'
        ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null
        
        # Execute the request
        $Response = Invoke-RestMethod @Request

        # Locate matching group
        foreach ($Object in $Response) {
            if ($Object.PSObject.Properties.Name -contains 'Name') {
                if ($Object.Name -ieq $Project.Template.Group.Name) {
                    Write-Host (" [✓] Group '{0}' ({1})" -f $Object.Name, $Object.Id)
                    $Project.Template.Group.Id = $Object.Id
                    $Project.Template.ProjectsUri = $Object.Links.Projects
                }
            }
        }
    }
    catch { 
        Write-Error $_ 
        throw
    }
    finally {
        if ($null -eq $Project.Template.Group.Id) {
            Write-Host "Not found.`n"

            Write-Warning ("Invalid template group '{0}'`n" -f $Project.Template.Group.Name)
            throw 'Template group required.'
            exit 1
        }
        else {
            Write-Host "Group found.`n"
        }
    }

    <#
        Get the project group from $ProjectGroup
    #>
    try {
        # Set up request
        $Request.Method = 'GET'
        $Request.Uri = '{0}/api/{1}/projectgroups/all' -f $Octopus.Uri, $Project.Target.Space.Id

        # Output current action (and request uri if verbose)
        Write-Host 'Locating target project group...'
        ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null
        
        # Execute the request
        $Response = Invoke-RestMethod @Request

        # Locate matching group
        foreach ($Object in $Response) {
            if ($Object.PSObject.Properties.Name -contains 'Name') {
                if ($Object.Name -ieq $Project.Target.Group.Name) {
                    Write-Host (" [✓] Group '{0}' ({1})" -f $Object.Name, $Object.Id)
                    $Project.Target.Group.Id = $Object.Id
                }
            }
        }
    }
    catch { 
        Write-Error $_ 
        throw
    }
    finally {
        if ($null -eq $Project.Target.Group.Id) {
            Write-Host "Not found.`n"

            <# Removing on-error behaviour to create target group before continuing #>
            # Write-Warning ("Invalid target group '{0}'`n" -f $Project.Target.Group.Name)
            # throw 'Target group required.'
            # exit 1
        }
        else {
            Write-Host "Group found.`n"
        }
    }

    <#
        Create the target project group from $ProjectGroup if it doesn't exist
    #>
    if ($null -eq $Project.Target.Group.Id) {
        try {
            # Set up request
            $Request.Method = 'POST'
            $Request.Uri = '{0}/api/{1}/projectgroups' -f $Octopus.Uri, $Project.Target.Space.Id

            # Output current action (and request uri if verbose)
            Write-Host 'Creating target project group...'
            ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null

            # Set up request payload (create project group)
            $Body = @{
                Id                = $null
                Name              = $Project.Target.Group.Name
                EnvironmentIds    = @()
                Links             = $null
                RetentionPolicyId = $null
                Description       = $null
            }

            # Execute the request
            $Response = Invoke-RestMethod @Request -Body ($Body | ConvertTo-Json -Depth 10)

            # Check response for project group
            foreach ($Object in $Response) {
                if (($Object.PSObject.Properties.Name -contains 'Name') -and ($Object.PSObject.Properties.Name -contains 'Id')) {
                    if ($Object.Name -ieq $Project.Target.Group.Name) {
                        Write-Host (" [✓] Group '{0}' ({1})" -f $Object.Name, $Object.Id)
                        $Project.Target.Group.Id = $Object.Id
                    }
                }
            }
        }
        catch { 
            Write-Error $_ 
            throw
        }
        finally {
            if ($null -eq $Project.Target.Group.Id) {
                Write-Host "Not found.`n"
    
                Write-Warning ("Invalid target group '{0}'`n" -f $Project.Target.Group.Name)
                throw 'Target group required.'
                exit 1
            }
            else {
                Write-Host "Group found.`n"
            }
        }
    }

    <#
        Get the project template from $TemplateSpace, $TemplateGroup, and $ProjectType
    #>
    try {
        # Set up request
        $Request.Method = 'GET'
        $Request.Uri = '{0}/api/spaces/{1}/projectgroups/{2}/projects' -f $Octopus.Uri, $Project.Template.Space.Id, $Project.Template.Group.Id

        # Output current action (and request uri if verbose)
        Write-Host 'Locating template project...'
        ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null
        
        # Execute the request
        $Response = Invoke-RestMethod @Request

        # Locate matching project
        foreach ($Object in $Response.Items) {
            if ($Object.PSObject.Properties.Name -contains 'Slug') {
                if ($Object.Slug -ieq $Project.Template.Type) {
                    Write-Host (" [✓] Template '{0}' ({1})" -f $Object.Name, $Object.Id)
                    $Project.Template.Id = $Object.Id
                    $Project.Template.Name = $Object.Name
                }
            }
        }
    }
    catch { 
        Write-Error $_ 
        throw
    }
    finally {
        if ($null -eq $Project.Template.Id) {
            Write-Host "Not found.`n"

            Write-Warning ("Invalid template project '{0}'`n" -f $Project.Template.Type)
            throw 'Template project required.'
            exit 1
        }
        else {
            Write-Host "Project found.`n"
        }
    }

    <#
        Get the project lifecycle (template or target? unsure at this point) from $ProjectLifecycle
    #>
    try {
        # Set up request
        $Request.Method = 'GET'
        $Request.Uri = '{0}/api/{1}/lifecycles?partialName={2}&skip=0&take=100' -f $Octopus.Uri, $Project.Template.Space.Id, ([uri]::EscapeDataString($Project.Template.Lifecycle.Name))

        # Output current action (and request uri if verbose)
        Write-Host 'Locating lifecycle...'
        ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null
        
        # Execute the request
        $Response = Invoke-RestMethod @Request

        # Locate matching lifecycle
        foreach ($Object in $Response.Items) {
            if ($Object.PSObject.Properties.Name -contains 'Name') {
                if ($Object.Name -ieq $Project.Template.Lifecycle.Name) {
                    Write-Host (" [✓] Lifecycle '{0}' ({1})" -f $Object.Name, $Object.Id)
                    $Project.Template.Lifecycle.Id = $Object.Id
                }
            }
        }
    }
    catch { 
        Write-Error $_ 
        throw
    }
    finally {
        if ($null -eq $Project.Template.Lifecycle.Id) {
            Write-Host "Not found.`n"

            Write-Warning ("Invalid lifecycle '{0}'`n" -f $Project.Template.Lifecycle.Name)
            throw 'Template lifecycle required.'
            exit 1
        }
        else {
            Write-Host "Lifecycle found.`n"
        }
    }

    <#
        Clone the template project
    #>
    try {
        # Set up request
        $Request.Method = 'POST'
        $Request.Uri = '{0}/api/{1}/projects?clone={2}' -f $Octopus.Uri, $Project.Target.Space.Id, $Project.Template.Id

        # Set up request payload (clone project)
        $Body = @{
            Name           = $Project.Target.Name
            Description    = $Project.Target.Description
            LifecycleId    = $Project.Template.Lifecycle.Id
            ProjectGroupId = $Project.Target.Group.Id
        }

        # Output current action (and request uri if verbose)
        Write-Host 'Cloning project...'
        ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null
        
        # Execute the request
        $Response = Invoke-RestMethod @Request -Body ($Body | ConvertTo-Json -Depth 10)

        # Check response for project
        foreach ($Object in $Response) {
            if (($Object.PSObject.Properties.Name -contains 'Name') -and ($Object.PSObject.Properties.Name -contains 'Id')) {
                if ($Object.Name -ieq $Project.Target.Name) {
                    Write-Host (" [✓] Project '{0}' ({1})" -f $Object.Name, $Object.Id)
                    $Project.Target.Id = $Object.Id
                }
            }
        }
    }
    catch {
        Write-Error $_
        throw
        exit 1
    }
    finally {
        if ($null -eq $Project.Target.Id) {
            Write-Host "Not cloned.`n"
            throw 'Unable to create project'
            exit 1
        }
        else {
            Write-Host "Cloned.`n"
            exit 0
        }
    }

    <#
        Modify target project variables
    #>
    try {
        <# Get the project variable set id #>
        # Set up request
        $Request.Method = 'GET'
        $Request.Uri = '{0}/api/{1}/projects/all' -f $Octopus.Uri, $Project.Target.Space.Id

        # Output current action (and request uri if verbose)
        Write-Host 'Retrieving variable set...'
        ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null

        # Execute the request
        $Response = (Invoke-RestMethod @Request) | Where-Object { $_.Name -eq $ProjectName }
        $Project.Target.VariableSet.Id = $Response.VariableSetId

        if ($null -eq $Project.Target.VariableSet.Id) {
            Write-Host "Not found.`n"

            throw 'Unable to retrieve project variables.'
            exit 1
        }
        
        <# Get the project variables #>
        # Set up request
        $Request.Method = 'GET'
        $Request.Uri = '{0}/api/{1}/variables/{2}' -f $Octopus.Uri, $Project.Target.Space.Id, $Project.Target.VariableSet.Id

        # Output current action (and request uri if verbose)
        Write-Host 'Retrieving project variables...'
        ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null

        # Execute the request
        $Response = Invoke-RestMethod @Request

        <# Modify the variable #>
        # Set up request payload (update project variable)
        $Body = $Response
        
        # Check to see if variable is already present
        $VariableToUpdate = $Body.Variables | Where-Object { $_.Name -eq $Project.Target.PackageVariable.Name }
        if ($null -eq $VariableToUpdate) {
            $Body.Variables += $Project.Target.PackageVariable
        }

        # Update the value
        $VariableToUpdate = $Project.Target.PackageVariable
        
        # Update the collection
        # Set up request
        $Request.Method = 'PUT'
        $Request.Uri = '{0}/api/{1}/variables/{2}' -f $Octopus.Uri, $Project.Target.Space.Id, $Project.Target.VariableSet.Id

        # Output current action (and request uri if verbose)
        Write-Host 'Updating variables with artifact name...'
        ($VerboseOutput -eq $true) ? (Write-Host $Request.Method $Request.Uri.Replace($Octopus.Uri, '***')) : $null

        # Execute the request
        $Response = Invoke-RestMethod @Request -Body ($Body | ConvertTo-Json -Depth 10)

        <# Verify response value matches input #>
        
        $CheckUpdateStatus = $Response.Variables | Where-Object { $_.Name -eq $Project.Target.PackageVariable.Name }
        if ($null -eq $CheckUpdateStatus) {
            Write-Host "Not set.`n"
            Write-Warning ("Variable not set '{0}'`n" -f $Project.Target.PackageVariable.Name)
        }
        else {
            Write-Host (" [✓] Variable '{0}' updated with value '{1}' ({2})" -f $CheckUpdateStatus.Name, $Project.Target.PackageVariable.Value, $CheckUpdateStatus.Id)
            $Project.Target.PackageVariable.Id = $CheckUpdateStatus.Id
        }
    }
    catch {
        Write-Error $_
        throw
        exit 1
    }
    finally {
        if ($null -eq $Project.Target.PackageVariable.Id) {
            Write-Host "Not updated.`n"
            Write-Warning ("Unable to set project variable {0} - manual update required.'`n" -f $Project.Target.PackageVariable.Name)
        }
        else {
            Write-Host "Updated.`n"
            exit 0
        }
    }
}
catch {
    Write-Error $_
}
finally {
    if ($?) {
        Write-Host "Script successfully ran to completion.`n"
    }
    else {
        Write-Host "Script execution failed with exit code $LASTEXITCODE.`n"
    }
}
