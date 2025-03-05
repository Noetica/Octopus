$script:path = $PSScriptRoot
. "$script:path\utils\control-service.ps1"


$targetRoot = $OctopusParameters["Application.Root"];
$synthesysInf = $OctopusParameters["Synthesys.Inf"]
Write-Host "## Configuration file: '$synthesysInf'"

$packageName = $OctopusParameters['Octopus.Action[Deploy latest package].Package.PackageId']

# Read the file content
$fileContent = Get-Content -Path $synthesysInf -Raw

# Define the section and the new line to add
$sectionName = '[System Services]'

$newServiceLine = "Start$packageName.bat,$packageName,$packageName,30"

# Find the section using regex
Write-Host "## Finding $sectionName section..."

$pattern = '(?<=\[' + [regex]::Escape($sectionName.Trim('[', ']')) + '\][\r\n]+).*?(?=(?:[\r\n]+\[|\z))'
$match = [regex]::Match($fileContent, $pattern, 16)  # 16 = Singleline option

if ($match.Success) {
    Write-Host "## Reading $sectionName section..."

    # Extract the section content
    $sectionContent = $match.Value

    # Check if the line already exists
    if ($sectionContent -like "*$newServiceLine*") {
        Write-Host "[!] Entry already exists (skipped): $newServiceLine"
    }
    else {
        # Add a new line entry to the section
        $updatedSection = $sectionContent.TrimEnd() + "`r`n" + $newServiceLine

        # Ensure a single newServiceLine before the next section
        $updatedSection = $updatedSection.TrimEnd() + "`r`n"

        # Replace the section in $fileContent
        Write-Host '## Appending new service entry...'
        Write-Host "Adding: $newServiceLine"
        $updatedContent = $fileContent -replace [regex]::Escape($sectionContent), $updatedSection

        # Clean up excessive empty lines (no more than one empty line between sections)
        Write-Host '## Tidying up...'
        $cleanedContent = $updatedContent -replace '(\r?\n){3,}', "`r`n`r`n"

        # Write changes to the file
        Try {
            Write-Host '## Saving...'
            Set-Content -Path $synthesysInf -Value $cleanedContent -Force -Encoding Ascii
            Write-Host "Saved changes to $synthesysInf"
        }
        Catch {
            Write-Host "[!] Failed to write changes to the file: $_"
        }
    }
}
else {
    Write-Host "[!] Section $sectionName not found"
}

Update-ServiceConfig
Start-Service -targets $packageName
