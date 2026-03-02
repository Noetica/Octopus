[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$InfPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Mappings,

    [Parameter(Mandatory = $false)]
    [switch]$CreateMissingSections,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Default', 'UTF8', 'Unicode', 'ASCII')]
    [string]$Encoding = 'Default'
)

function Get-OctopusVariableValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $OctopusParameters) {
        throw 'OctopusParameters is not available in the current execution context.'
    }

    if (-not $OctopusParameters.ContainsKey($Name)) {
        throw "Octopus variable '$Name' was not found."
    }

    return [string]$OctopusParameters[$Name]
}

function ConvertTo-MappingObject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mapping
    )

    $parts = $Mapping.Split('|')
    if ($parts.Count -ne 3) {
        throw "Invalid mapping '$Mapping'. Expected format: Section|Key|Octopus.VariableName"
    }

    $section = $parts[0].Trim()
    $key = $parts[1].Trim()
    $variableName = $parts[2].Trim()

    if ([string]::IsNullOrWhiteSpace($section) -or [string]::IsNullOrWhiteSpace($key) -or [string]::IsNullOrWhiteSpace($variableName)) {
        throw "Invalid mapping '$Mapping'. Section, Key and variable name must all be provided."
    }

    [PSCustomObject]@{
        Section      = $section
        Key          = $key
        VariableName = $variableName
    }
}

function Find-SectionBounds {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Lines,

        [Parameter(Mandatory = $true)]
        [string]$SectionName
    )

    $sectionHeaderPattern = '^\s*\[(.+)\]\s*$'
    $start = -1
    $end = $Lines.Count - 1

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match $sectionHeaderPattern) {
            if ($matches[1] -eq $SectionName) {
                $start = $index
                break
            }
        }
    }

    if ($start -eq -1) {
        return $null
    }

    for ($index = $start + 1; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match $sectionHeaderPattern) {
            $end = $index - 1
            break
        }
    }

    return [PSCustomObject]@{ Start = $start; End = $end }
}

if ([string]::IsNullOrWhiteSpace($InfPath)) {
    if ($null -ne $OctopusParameters -and $OctopusParameters.ContainsKey('Noetica.Inf')) {
        $InfPath = $OctopusParameters['Noetica.Inf']
    }
}

if ([string]::IsNullOrWhiteSpace($InfPath)) {
    throw "INF file path not provided. Use -InfPath or set Octopus variable 'Noetica.Inf'."
}

if (-not (Test-Path -LiteralPath $InfPath)) {
    throw "INF file not found: $InfPath"
}

$resolvedPath = (Resolve-Path -LiteralPath $InfPath).Path
$mappingsToApply = @($Mappings | ForEach-Object { ConvertTo-MappingObject -Mapping $_ })

$rawLines = Get-Content -LiteralPath $resolvedPath -Encoding $Encoding
$updatedLines = New-Object System.Collections.Generic.List[string]
# Use Add() per element rather than AddRange() to avoid PS 5.1 Object[] / string[] type mismatch
foreach ($line in $rawLines) { $updatedLines.Add([string]$line) }

$changes = 0

foreach ($mapping in $mappingsToApply) {
    $sectionBounds = Find-SectionBounds -Lines ([string[]]($updatedLines | ForEach-Object { [string]$_ })) -SectionName $mapping.Section
    if ($null -eq $sectionBounds) {
        if (-not $CreateMissingSections) {
            throw "Section [$($mapping.Section)] was not found. Use -CreateMissingSections to add it."
        }

        if ($updatedLines.Count -gt 0 -and $updatedLines[$updatedLines.Count - 1].Trim() -ne '') {
            $updatedLines.Add('')
        }

        $updatedLines.Add("[$($mapping.Section)]")
        $updatedLines.Add("$($mapping.Key)=$(Get-OctopusVariableValue -Name $mapping.VariableName)")
        $changes++
        continue
    }

    $replacementValue = Get-OctopusVariableValue -Name $mapping.VariableName
    $keyPattern = '^\s*' + [regex]::Escape($mapping.Key) + '\s*='
    $targetIndex = -1

    for ($index = $sectionBounds.Start + 1; $index -le $sectionBounds.End; $index++) {
        if ($updatedLines[$index] -match $keyPattern) {
            $targetIndex = $index
            break
        }
    }

    if ($targetIndex -ge 0) {
        $updatedLines[$targetIndex] = "$($mapping.Key)=$replacementValue"
    }
    else {
        $insertIndex = $sectionBounds.End + 1
        $updatedLines.Insert($insertIndex, "$($mapping.Key)=$replacementValue")
    }

    $changes++
}

$targetDescription = "$resolvedPath ($changes mappings)"
if ($PSCmdlet.ShouldProcess($targetDescription, 'Update INF values')) {
    Set-Content -LiteralPath $resolvedPath -Value $updatedLines -Encoding $Encoding
    Write-Host "Updated INF file: $resolvedPath"
    Write-Host "Mappings applied: $changes"
}
