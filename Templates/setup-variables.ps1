# The root directory the Octopus tentacle agent has deployed the package to
$PackageRoot = $OctopusParameters["Octopus.Tentacle.Agent.ApplicationDirectoryPath"];

# The name of the machine
$MachineName = $OctopusParameters["env:COMPUTERNAME"];

# The name of the environment / environment tag
$EnvironmentName = $OctopusParameters["Octopus.Environment.Name"];

<#
  Effective Logging Level for the target Environment.
  The value of 'Noetica.LogLevel' is an expression, and the value
  is determined by the environment tag of the deployment task.
#>
$EffectiveLogLevel = $OctopusParameters["Noetica.LogLevel"];
<#
  'Noetica.LogLevel' is defined in Octopus variable set 'Logging config'.
  There are currently 2 other keys in this variable set, which are used by the expression:
  1. 'Noetica.Scoped.LogLevel' which has 3 values, each of which is scoped to an environment tag.
    a. 'DEBUG' is scoped to 'Development'.
    b. 'INFO' is scoped to 'Test'.
    c. 'ERROR' is scoped to 'Production'.
  2. 'Noetica.Unscoped.LogLevel' serves as a default unscoped value of 'ERROR'.
  
  The expression for 'Noetica.LogLevel', below, retrieves either a scoped value if the tag
  matches, or the unscoped 'default' value if there is no matching environment or none provided:
  #{if Noetica.Scoped.LogLevel}#{Noetica.Scoped.LogLevel}#{else}#{Noetica.Unscoped.LogLevel}#{/if}
#>
Write-Host "-- Logging (requires variable set: 'Logging config')"
Write-Host "Noetica.LogLevel: $EffectiveLogLevel"

<#
  App hosting variables
  These are defined in Octopus variable set 'App hosting'.
#>
$AppInstallRoot = $OctopusParameters["Noetica.AppRoot"]
$AppInstallFrag = $OctopusParameters["Noetica.AppRoot.Fragment"]
<#
  The fragment contains 'Synthesys\NoeticaAPIs'
  The root is a composite variable which contains '#{env:SystemDrive}\#{Noetica.AppRoot.Fragment}'
  The result is a path on the correct system drive for the target
  - e.g. C:\Synthesys\NoeticaAPIs
#>
Write-Host "-- App (requires variable set: 'App hosting')"
Write-Host "Noetica.AppRoot: $AppInstallRoot"
Write-Host "Noetica.AppRoot.Fragment: $AppInstallFrag"

<#
  Database hosting variables
  These are defined in Octopus variable set 'Database hosting'.
#>
$DatabaseServer = $OctopusParameters["Noetica.Database.Server"]
$DatabaseName = $OctopusParameters["Noetica.Database.Name"]
$DatabaseUser = $OctopusParameters["Noetica.Database.UID"]
$DatabasePass = $OctopusParameters["Noetica.Database.PWD"]
$DatabaseConn = $OctopusParameters["Noetica.Database.ConnectionString"]
<#
  The name, pwd, and server are all 'sensitive' variables which are redacted from logs
  The connection string is a composite variable which contains: 'data source=#{Noetica.Database.Server};initial catalog=#{Noetica.Database.Name};integrated security=false;user id=#{Noetica.Database.UID};password=#{Noetica.Database.PWD};multipleactiveresultsets=true;'
#>
Write-Host "-- Database (requires variable set: 'Database hosting')"
Write-Host "Noetica.Database.Server: $DatabaseServer"
Write-Host "Noetica.Database.Name: $DatabaseName"
Write-Host "Noetica.Database.UID: $DatabaseUser"
Write-Host "Noetica.Database.PWD: $DatabasePass"
Write-Host "Noetica.Database.ConnectionString: $DatabaseConn"

<#
  Voice hosting variables
  These are defined in Octopus variable set 'Voice hosting'.
#>
$VoiceInstallRoot = $OctopusParameters["Noetica.VoiceRoot"]
$VoiceInstallFrag = $OctopusParameters["Noetica.VoiceRoot.Fragment"]
<#
  The fragment contains 'VoicePlatform'
  The root is a composite variable which contains '#{env:SystemDrive}\#{Noetica.VoiceRoot.Fragment}'
  The result is a path on the correct system drive for the target
  - e.g. C:\VoicePlatform
#>
Write-Host "-- Voice (requires variable set: 'Voice hosting')"
Write-Host "Noetica.VoiceRoot: $VoiceInstallRoot"
Write-Host "Noetica.VoiceRoot.Fragment: $VoiceInstallFrag"

<#
  Web hosting variables
  These are defined in Octopus variable set 'Web hosting'.
#>
$WebInstallRoot = $OctopusParameters["Noetica.WebRoot"]
$WebInstallFrag = $OctopusParameters["Noetica.WebRoot.Fragment"]
<#
  The fragment contains 'Noetica\Synthesys.NET\v2.2\Tenants\General\Web'
  The root is a composite variable which contains '#{env:ProgramFiles}\#{Noetica.WebRoot.Fragment}'
  The result is a path on the correct system drive for the target
  - e.g. C:\Program Files\Noetica\Synthesys.NET\v2.2\Tenants\General\Web
#>
Write-Host "-- Web (requires variable set: 'Web hosting')"
Write-Host "Noetica.WebRoot: $WebInstallRoot"
Write-Host "Noetica.WebRoot.Fragment: $WebInstallFrag"

<#
  Output variables
  These can be consumed by a subsequent step
  These can also be mapped to a project variable, see best practices: https://octopus.com/docs/projects/variables/output-variables#best-practice
  - "A useful pattern is to create a project variable which evaluates to the output variable"
#>
Write-Host "---------------`n--- Outputs ---`n---------------"
<# https://octopus.com/docs/projects/variables/output-variables #>

Write-Host "[Environment.Machine] Machine Name: $MachineName"
Set-OctopusVariable -name "Environment.Machine" -value $MachineName

Write-Host "[Environment.Name] Environment Name: $EnvironmentName"
Set-OctopusVariable -name "Environment.Name" -value $EnvironmentName

Write-Host "[Install.Root] Deployment Root Directory: $PackageRoot"
Set-OctopusVariable -name "Install.Root" -value $PackageRoot

Write-Host "[Logging.LogLevel] Log Level: $EffectiveLogLevel"
Set-OctopusVariable -name "Logging.LogLevel" -value $EffectiveLogLevel

Write-Host "[Application.Root] API Root Directory: $AppInstallRoot"
Set-OctopusVariable -name "Application.Root" -value $AppInstallRoot

Write-Host "[Voice.Root] Voice Root Directory: $VoiceInstallRoot"
Set-OctopusVariable -name "Voice.Root" -value $VoiceInstallRoot

Write-Host "[Web.Root] Website Root Directory: $WebInstallRoot"
Set-OctopusVariable -name "Web.Root" -value $WebInstallRoot

Write-Host "[Database.UID] Database User: $DatabaseUser"
Set-OctopusVariable -name "Database.UID" -value $DatabaseUser

Write-Host "[Database.PWD] Database Password: $DatabasePass"
Set-OctopusVariable -name "Database.PWD" -value $DatabasePass

Write-Host "[Database.ConnectionString] Database Connection String: $DatabaseConn"
Set-OctopusVariable -name "Database.ConnectionString" -value $DatabaseConn
