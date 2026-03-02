# Octopus Scripts Repository

PowerShell scripts, runbooks, templates, and pipeline workflow snippets used with Octopus Deploy for Noetica platform deployments.

The repository mainly covers:
- Deploying API, web app, and service artifacts
- Managing Octopus project/tenant automation via Octopus REST API
- Environment checks and smoke tests
- Runbook utilities for exporting/converting config data

## Repository Layout

- `Scripts/` - Deployment and automation scripts used in Octopus steps
- `Scripts/Runbooks/` - Operational runbook scripts (registry, INF/REG conversion, variable export)
- `Scripts/utils/` - Shared helpers for SCM/service control, logging, and JSON formatting
- `Templates/` - Reusable deployment script templates
- `Workflows/` - CI workflow templates (`angular`, `.NET`, `msbuild`, `vue`)

## Most Useful Scripts

### Core Deployment

- `Scripts/setup-api.ps1`  
  Deploys API packages to target folders, stops/starts services, handles file cleanup with exclusions, and creates startup batch scripts (including custom startup command support).

- `Scripts/setup-webapp.ps1`  
  Deploys IIS web applications, checks/imports required IIS modules/features, manages app pools, and supports backup/restore of selected files during deployment.

- `Scripts/setup-simple.ps1`  
  Lightweight package deployment (copy/clean) for simpler components where service/IIS orchestration is not required.

- `Scripts/setup-api-tests.ps1` + `Scripts/run-tests.ps1`  
  Deploys test artifacts and executes test assemblies with `dotnet vstest`.

### Environment Validation

- `Scripts/healthcheck.ps1`  
  Basic URL health probe using HTTP HEAD against an application login endpoint.

- `Scripts/checkfrontdoorapi.ps1`  
  Azure APIM/Front Door API check using subscription keys and optional API version headers.

### Octopus Project/Tenant Automation

- `Scripts/clone-project.ps1`  
  Clones Octopus projects from templates, configures core variables (artifact/port/startup script), and validates target/template spaces and groups.

- `Scripts/connect-project-to-tenants.ps1`  
  Maps tenants to environments and updates project-environment links through Octopus REST API.

- `Scripts/setup-variables.ps1`  
  Reads Octopus variables and emits standardized output variables for downstream deployment steps.

### Runbooks / Operations

- `Scripts/Runbooks/WriteRegistryEntries/WriteRegistryEntries.ps1`  
  Imports `.reg` files safely (with `-WhatIf` support), shows affected keys/values, and restarts VoicePlatform service around the operation.

- `Scripts/Runbooks/Export-OctopusVariables.ps1`  
  Exports non-internal Octopus variables to JSON/JSONC with nested object structure.

- `Scripts/Runbooks/InfToJson/Convert-InfToJson.ps1`  
  Robust INF/INI to JSON converter with strict mode, type conversion controls, comment-preserving JSONC output, and safety checks.

- `Scripts/Runbooks/RegistryToJson/Convert-RegFileToJson.ps1`  
  Converts registry export (`.reg`) files to JSON/JSONC, with options suited for REST/config workflows.

- `Scripts/Runbooks/Write-OctopusVariablesToInf.ps1`  
  Writes selected Octopus variables into `synthesys.inf` (or any INF) using explicit mappings in the form `Section|Key|Octopus.VariableName`.

## Writing Octopus Variables to INF

Use `Scripts/Runbooks/Write-OctopusVariablesToInf.ps1` when you want a generic way to map Octopus variables into INF keys.

### Mapping format

Each mapping must be provided as:

- `Section|Key|Octopus.VariableName`

Example mappings:

- `Predictive|DefaultCountryCode|Tenant.DefaultCountryCode`
- `Database|Server|Noetica.Database.Server`
- `Database|Name|Noetica.Database.Name`

### Example usage

```powershell
.\Scripts\Runbooks\Write-OctopusVariablesToInf.ps1 \
  -InfPath "C:\Synthesys\etc\synthesys.inf" \
  -Mappings @( \
    "Predictive|DefaultCountryCode|Tenant.DefaultCountryCode", \
    "Database|Server|Noetica.Database.Server", \
    "Database|Name|Noetica.Database.Name" \
  ) \
  -CreateMissingSections
```

Notes:
- If `-InfPath` is omitted, the script uses Octopus variable `Noetica.Inf`.
- Use `-WhatIf` to preview changes without writing.
- If a key already exists in the section, it is replaced; otherwise it is added.
- A companion sample file is available at `Scripts/Runbooks/Write-OctopusVariablesToInf.sample.txt`.

### Using the sample mappings file

```powershell
$mappings = Get-Content ".\Scripts\Runbooks\Write-OctopusVariablesToInf.sample.txt" |
  Where-Object { $_ -and -not $_.TrimStart().StartsWith('#') }

.\Scripts\Runbooks\Write-OctopusVariablesToInf.ps1 -Mappings $mappings -CreateMissingSections
```

## Typical Execution Context

Most scripts assume they run inside an Octopus step where `OctopusParameters` and output variable commands are available. Some scripts also require environment variables such as:

- `OCTOPUS_INSTANCE`
- `OCTOPUS_API_KEY`

Many scripts depend on paths and utilities under `Scripts/utils/` and should be executed from their expected repository locations.

## Notes

- Scripts are primarily intended for Windows PowerShell/PowerShell environments used by Octopus workers/tentacles.
- For runbook converters, see the `PARAMETER-GUIDE.md` files in the relevant runbook subfolders for detailed option guidance.