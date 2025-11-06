# Convert-InfToJson.ps1 - Parameter Guide

Complete guide to all parameters and their behaviors for converting INF files to JSON.

---

## Table of Contents
- [Quick Reference](#quick-reference)
- [Type Conversion Parameters](#type-conversion-parameters)
- [Comment Preservation (JSONC)](#comment-preservation-jsonc)
- [File Handling Parameters](#file-handling-parameters)
- [Validation Parameters](#validation-parameters)
- [Advanced Parameters](#advanced-parameters)
- [Common Scenarios](#common-scenarios)
- [Parameter Interactions](#parameter-interactions)

---

## Quick Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-InfPath` | String | Required | Path to the INF file to convert |
| `-OutputPath` | String | Auto | Path for output JSON file |
| `-Encoding` | String | UTF8 | File encoding (UTF8, ASCII, Unicode, etc.) |
| `-StrictMode` | Switch | False | Treat warnings as errors |
| `-NoTypeConversion` | Switch | False | Disable type conversion, keep all values as strings |
| `-StripQuotes` | Switch | False | Remove surrounding quotes from values |
| `-EmptyAsNull` | Switch | False | Convert empty values to JSON null |
| `-YesNoAsBoolean` | Switch | False | Convert Yes/No to true/false |
| `-PreserveComments` | Switch | False | Preserve comments as JSONC output |
| `-DefaultSection` | String | _global_ | Section name for keys before first section |
| `-Depth` | Int | 10 | Maximum JSON depth |
| `-MaxFileSizeMB` | Int | 100 | Maximum INF file size in MB |
| `-MaxSections` | Int | 10000 | Maximum number of sections |
| `-Force` | Switch | False | Overwrite output without prompting |

---

## Type Conversion Parameters

### Default Behavior (No Parameters)

**INF Input:**
```ini
[Config]
Name=MyApp
Version=2.5
Enabled=true
Port=8080
Setting=Yes
Empty=
```

**JSON Output:**
```json
{
  "Config": {
    "Name": "MyApp",
    "Version": 2.5,
    "Enabled": true,
    "Port": 8080,
    "Setting": "Yes",
    "Empty": ""
  }
}
```

**Behavior:**
- Strings remain strings
- Numbers convert to Int64 or Double
- `true`/`false` convert to boolean
- `Yes`/`No` remain as strings
- Empty values become empty strings `""`

---

### `-NoTypeConversion`

**Most Powerful Override** - Disables all automatic type detection. All values remain as strings, overriding all other type conversion parameters.

**Example:**
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -NoTypeConversion
```

**INF Input:**
```ini
[Config]
Name=MyApp
Version=2.5
Enabled=true
Port=8080
Setting=Yes
Empty=
```

**Output:**
```json
{
  "Config": {
    "Name": "MyApp",
    "Version": "2.5",
    "Enabled": "true",
    "Port": "8080",
    "Setting": "Yes",
    "Empty": ""
  }
}
```

**Key Points:**
- Overrides `-YesNoAsBoolean`, `-EmptyAsNull`, and default type conversion
- Empty values remain as empty strings `""`
- Most conservative option for maximum compatibility
- Everything stays exactly as it appears in the INF file

**Use When:**
- Legacy systems require string values
- You want predictable, uniform types
- You need exact string preservation
- Consuming system expects all strings
- Avoiding any type interpretation issues

---

### `-EmptyAsNull`

Converts empty values (`Key=`) to JSON `null` instead of empty strings.

**Example:**
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -EmptyAsNull
```

**INF Input:**
```ini
Password=
Timeout=
```

**Without `-EmptyAsNull`:**
```json
{
  "Password": "",
  "Timeout": ""
}
```

**With `-EmptyAsNull`:**
```json
{
  "Password": null,
  "Timeout": null
}
```

**Use When:**
- Database imports prefer null for missing values
- JSON Schema requires null for optional fields
- You want semantic difference between "empty" and "not set"

---

### `-YesNoAsBoolean`

Converts `Yes`/`No` values (case-insensitive) to `true`/`false` booleans.

**Example:**
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -YesNoAsBoolean
```

**INF Input:**
```ini
AutoSave=Yes
AutoBackup=No
EnableLogging=YES
ShowWarnings=yes
FilterCLI=NO
```

**Without `-YesNoAsBoolean`:**
```json
{
  "AutoSave": "Yes",
  "AutoBackup": "No",
  "EnableLogging": "YES",
  "ShowWarnings": "yes",
  "FilterCLI": "NO"
}
```

**With `-YesNoAsBoolean`:**
```json
{
  "AutoSave": true,
  "AutoBackup": false,
  "EnableLogging": true,
  "ShowWarnings": true,
  "FilterCLI": false
}
```

**Important:**
- Only converts standalone `Yes` or `No` values
- Preserves strings like `"Yes Bank"` or `"No Problem"`
- Case-insensitive: `Yes`, `YES`, `yes`, `No`, `NO`, `no` all work

**Use When:**
- INF files use Yes/No convention
- You want consistency with true/false values
- Consuming system expects boolean types

---

### `-StripQuotes`

Removes surrounding quotes from string values.

**Example:**
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -StripQuotes
```

**INF Input:**
```ini
Name="John Doe"
Path='C:\Program Files'
```

**Without `-StripQuotes`:**
```json
{
  "Name": "\"John Doe\"",
  "Path": "'C:\\Program Files'"
}
```

**With `-StripQuotes`:**
```json
{
  "Name": "John Doe",
  "Path": "C:\\Program Files"
}
```

**Use When:**
- INF file has quoted values
- You want clean string values without quotes

---

## Comment Preservation (JSONC)

### `-PreserveComments` Switch

When enabled, the script:
1. Outputs `.jsonc` file format (JSON with Comments)
2. Preserves all comments from the INF file
3. Intelligently converts commented INF syntax to JSON syntax
4. Maintains comment positioning (leading, trailing, section-level)
5. Handles commented-out section blocks

**Basic Example:**

**INF Input:**
```ini
[Database]
; Production database settings
Host=localhost
Port=5432
; Username=admin
; Password=secret
```

**Command:**
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -PreserveComments
```

**JSONC Output:**
```jsonc
{
  "Database": {
      // Production database settings
      "Host": "localhost",
      "Port": 5432
      // "Username": "admin",
      // "Password": "secret",
  }
}
```

### Comment Positioning

#### Leading Comments (Before Properties)
Comments that appear before a property are placed before it in JSONC:

**INF:**
```ini
[Settings]
; This enables debug mode
Debug=Yes
```

**JSONC:**
```jsonc
{
  "Settings": {
      // This enables debug mode
      "Debug": true
  }
}
```

#### Trailing Comments (After Properties)
Comments that appear after a property are placed after it in JSONC:

**INF:**
```ini
[Settings]
Debug=Yes
; Enable for production only
; Requires restart
```

**JSONC:**
```jsonc
{
  "Settings": {
      "Debug": true
      // Enable for production only
      // Requires restart
  }
}
```

#### Section-Level Comments
Comments right after a section header appear at the top of that section:

**INF:**
```ini
[Database]
; Connection settings for production
; Update before deployment
Host=localhost
Port=5432
```

**JSONC:**
```jsonc
{
  "Database": {
      // Connection settings for production
      // Update before deployment
      "Host": "localhost",
      "Port": 5432
  }
}
```

### Commented Section Blocks

When entire sections are commented out, they're preserved as cohesive blocks:

**INF:**
```ini
[Active Section]
Key=Value

;[Disabled Section]
;DebugMode=Yes
;LogLevel=Verbose

[Another Active Section]
Setting=Enabled
```

**JSONC:**
```jsonc
{
  "Active Section": {
      "Key": "Value"
  },
  // "Disabled Section": {
  //     "DebugMode": true,
  //     "LogLevel": "Verbose",
  // },
  "Another Active Section": {
      "Setting": "Enabled"
  }
}
```

### INF-to-JSON Syntax Conversion

Commented INF syntax is automatically converted to JSON format, making it easy to uncomment:

**INF:**
```ini
[Email Service]
;SMTP Server=smtp.gmail.com
;SMTP Port=587
;Use TLS=Yes
;From Address=noreply@example.com
ActiveServer=mail.example.com
```

**JSONC:**
```jsonc
{
  "Email Service": {
      // "SMTP Server": "smtp.gmail.com",
      // "SMTP Port": 587,
      // "Use TLS": true,
      // "From Address": "noreply@example.com",
      "ActiveServer": "mail.example.com"
  }
}
```

**Uncommenting:** Simply remove the `//` to activate commented properties:
```jsonc
{
  "Email Service": {
      "SMTP Server": "smtp.gmail.com",  // ← Now active!
      "SMTP Port": 587,                  // ← Now active!
      "Use TLS": true,                   // ← Now active!
      "From Address": "noreply@example.com", // ← Now active!
      "ActiveServer": "mail.example.com"
  }
}
```

### Type Conversion with Comments

Type conversion parameters work with `-PreserveComments`:

**Command:**
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -PreserveComments -YesNoAsBoolean -EmptyAsNull
```

**INF:**
```ini
[Settings]
; Enable=Yes
Debug=No
; Timeout=30
LogPath=
```

**JSONC:**
```jsonc
{
  "Settings": {
      // "Enable": true,      ← Boolean conversion applied
      "Debug": false,
      // "Timeout": 30,       ← Integer preserved
      "LogPath": null         ← Empty becomes null
  }
}
```

### JSONC vs JSON Output

| Feature | JSON (default) | JSONC (`-PreserveComments`) |
|---------|---------------|----------------------------|
| File Extension | `.json` | `.jsonc` |
| Comments | Not preserved | Preserved |
| Commented sections | Ignored | Preserved as blocks |
| Uncommenting | N/A | Produces valid JSON |
| File Size | Smaller | Larger (~30% more) |
| Editor Support | Universal | VS Code, IntelliJ, etc. |

### Real-World Example

**Production Configuration with Documentation:**

```powershell
./Convert-InfToJson.ps1 `
    -InfPath synthesys.template.inf `
    -PreserveComments `
    -YesNoAsBoolean `
    -EmptyAsNull `
    -StripQuotes `
    -Verbose
```

This creates a `.jsonc` file that:
- ✅ Preserves all documentation comments
- ✅ Keeps commented-out configuration options
- ✅ Converts types appropriately
- ✅ Can be uncommented for immediate use
- ✅ Maintains all structural relationships

### When to Use `-PreserveComments`

**Use JSONC for:**
- 📝 Configuration files with documentation
- 🔧 Template files with optional settings
- 📋 Files with commented-out alternatives
- 👥 Team environments where comments help understanding
- 🔄 Files that change frequently and need context

**Use JSON for:**
- 🚀 Production data files
- 🤖 Machine-to-machine communication
- 📦 Minimal file size requirements
- 🔒 No need for human-readable comments

---

## File Handling Parameters

### `-InfPath` (Required)

Path to the INF file to convert. Can be relative or absolute.

**Examples:**
```powershell
# Relative path
.\Convert-InfToJson.ps1 -InfPath .\config.inf

# Absolute path
.\Convert-InfToJson.ps1 -InfPath "C:\Config\app.inf"

# From Octopus variable (automatic)
# Script checks $OctopusParameters["Noetica.Inf"]
```

---

### `-OutputPath` (Optional)

Path for the output JSON file. If not specified, creates a `.json` file with the same name/location as the source INF.

**Examples:**
```powershell
# Automatic (config.inf -> config.json in same directory)
.\Convert-InfToJson.ps1 -InfPath config.inf

# Explicit output path
.\Convert-InfToJson.ps1 -InfPath config.inf -OutputPath "output\result.json"

# Different directory
.\Convert-InfToJson.ps1 -InfPath config.inf -OutputPath "C:\Output\config.json"
```

---

### `-Encoding`

File encoding for reading the INF file.

**Options:** `UTF8` (default), `ASCII`, `Unicode`, `UTF7`, `UTF32`, `Default`

**Example:**
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -Encoding Unicode
```

**Use When:**
- INF file uses non-UTF8 encoding
- You encounter character encoding issues

---

### `-Force`

Overwrites output file without prompting. Supports `-WhatIf` and `-Confirm`.

**Examples:**
```powershell
# Overwrite without prompting
.\Convert-InfToJson.ps1 -InfPath config.inf -Force

# Preview what would happen
.\Convert-InfToJson.ps1 -InfPath config.inf -WhatIf

# Prompt for confirmation
.\Convert-InfToJson.ps1 -InfPath config.inf -Confirm
```

---

## Validation Parameters

### `-StrictMode`

Treats warnings as errors and fails the conversion.

**Example:**
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -StrictMode
```

**What Triggers Errors:**
- Duplicate section names
- Duplicate keys in the same section
- Empty section names `[]`
- Empty key names
- Unparseable lines

**Use When:**
- Quality validation in CI/CD pipelines
- You want to enforce INF file standards
- Zero tolerance for malformed data

---

### `-MaxFileSizeMB`

Maximum allowed INF file size in megabytes.

**Default:** 100 MB  
**Range:** 1-1024 MB

**Example:**
```powershell
.\Convert-InfToJson.ps1 -InfPath large.inf -MaxFileSizeMB 500
```

**Use When:**
- Processing potentially large files
- Setting resource limits in automation

---

### `-MaxSections`

Maximum number of sections allowed in the INF file.

**Default:** 10,000  
**Range:** 1-100,000

**Example:**
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -MaxSections 5000
```

**Use When:**
- Protecting against malformed or malicious files
- Setting resource limits

---

## Advanced Parameters

### `-DefaultSection`

Section name for key-value pairs found before any `[Section]` header.

**Default:** `_global_`

**Example:**
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -DefaultSection "Defaults"
```

**INF Input:**
```ini
Version=1.0
Author=John

[Config]
Setting=Value
```

**Output:**
```json
{
  "Defaults": {
    "Version": "1.0",
    "Author": "John"
  },
  "Config": {
    "Setting": "Value"
  }
}
```

---

### `-Depth`

Maximum depth for JSON conversion.

**Default:** 10  
**Range:** 1-100

**Example:**
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -Depth 20
```

**Use When:**
- You have deeply nested structures
- You get truncated JSON warnings

---

## Common Scenarios

### Scenario 1: Maximum Compatibility (All Strings)

**Goal:** Ensure all values are strings for legacy system compatibility.

```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -NoTypeConversion
```

**Result:** Everything is a string, no type conversion.

---

### Scenario 2: Modern JSON with Type Safety

**Goal:** Convert to idiomatic JSON with proper types.

```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -YesNoAsBoolean -EmptyAsNull
```

**Result:**
- Numbers → integers/floats
- true/false → booleans
- Yes/No → booleans
- Empty values → null

---

### Scenario 8: Strict Validation for CI/CD

**Goal:** Fail fast on any data quality issues.

```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -StrictMode -YesNoAsBoolean -EmptyAsNull
```

**Result:** Conversion fails if warnings occur (duplicates, empty keys, etc.)

---

### Scenario 4: Database Import Preparation

**Goal:** Prepare data for database import with proper nulls.

```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -EmptyAsNull -YesNoAsBoolean
```

**Result:** Empty values become null, Yes/No become booleans, perfect for SQL/NoSQL imports.

---

### Scenario 5: Preserve Original INF Format

**Goal:** Keep everything exactly as it appears in the INF file.

```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -NoTypeConversion
```

**Result:** All values remain as strings, maximum fidelity to source.

---

## Parameter Interactions

### Priority Order (What Overrides What)

1. **`-NoTypeConversion`** - Overrides EVERYTHING (most powerful) - all values become strings
2. **`-EmptyAsNull`** - Converts empty to null
3. **`-YesNoAsBoolean`** - Converts Yes/No to boolean
4. **Default type conversion** - Numbers, true/false

### Valid Combinations

| Combination | Result |
|-------------|--------|
| `-NoTypeConversion` + anything | All strings (NoTypeConversion wins) |
| `-YesNoAsBoolean` + `-EmptyAsNull` | ✅ Both work together |
| `-StripQuotes` + any conversion | ✅ Works together |

### Conflicting Parameters

**⚠️ `-NoTypeConversion` vs. Type Parameters**
```powershell
# NoTypeConversion overrides everything
.\Convert-InfToJson.ps1 -InfPath config.inf -NoTypeConversion -YesNoAsBoolean -EmptyAsNull
# Result: All strings (YesNoAsBoolean and EmptyAsNull ignored)
```

**Why:** `-NoTypeConversion` is designed for maximum compatibility when you need all values as strings, so it takes precedence over all type conversion options.

---

## Return Object

The script returns a PowerShell object with conversion statistics:

```powershell
$result = .\Convert-InfToJson.ps1 -InfPath config.inf

# Properties:
$result.Success            # Boolean: True if successful
$result.SourceFile         # String: Input file path
$result.SourceFileSizeKB   # Decimal: Input file size in KB
$result.OutputFile         # String: Output file path
$result.OutputFileSizeKB   # Decimal: Output file size in KB
$result.SectionsProcessed  # Int: Number of sections
$result.LinesProcessed     # Int: Number of lines read
$result.Warnings           # Int: Number of warnings
$result.Errors             # String: Error status
$result.ConversionTime     # DateTime: When conversion completed
```

---

## Tips and Best Practices

### 1. Start Simple
Begin with default parameters, then add options as needed:
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf
```

### 2. Use Verbose for Debugging
See exactly what's happening:
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -Verbose
```

### 3. Test with WhatIf
Preview changes before committing:
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -WhatIf
```

### 4. Combine Parameters Thoughtfully
Don't use conflicting parameters:
```powershell
# ❌ Bad: NoTypeConversion makes YesNoAsBoolean useless
.\Convert-InfToJson.ps1 -InfPath config.inf -NoTypeConversion -YesNoAsBoolean

# ✅ Good: These work together
.\Convert-InfToJson.ps1 -InfPath config.inf -YesNoAsBoolean -EmptyAsNull
```

### 5. Use StrictMode in CI/CD
Catch data quality issues early:
```powershell
.\Convert-InfToJson.ps1 -InfPath config.inf -StrictMode -ErrorAction Stop
```

---

## Examples by Use Case

### Web Application Configuration
```powershell
.\Convert-InfToJson.ps1 -InfPath webapp.inf -YesNoAsBoolean -EmptyAsNull -Force
```

### Legacy System Integration
```powershell
.\Convert-InfToJson.ps1 -InfPath legacy.inf -NoTypeConversion -Force
```

### Database Seeding
```powershell
.\Convert-InfToJson.ps1 -InfPath seed.inf -EmptyAsNull -YesNoAsBoolean -StrictMode
```

### API Configuration
```powershell
.\Convert-InfToJson.ps1 -InfPath api.inf -YesNoAsBoolean -StripQuotes -Force
```

### Data Migration
```powershell
.\Convert-InfToJson.ps1 -InfPath migrate.inf -EmptyAsNull -Force
```

---

## Troubleshooting

### Warnings about Duplicate Keys
**Cause:** INF file has duplicate keys in same section  
**Solution:** Use `-StrictMode` to fail, or fix INF file

### JSON Appears Truncated
**Cause:** Depth limit reached  
**Solution:** Increase `-Depth` parameter

### File Size Error
**Cause:** File exceeds default 100MB limit  
**Solution:** Increase `-MaxFileSizeMB` parameter

### Backslashes Doubled in JSON
**Info:** This is correct JSON escaping behavior. `\\` in JSON = `\` in actual value.

---

## Version History

**v2.1** - Current
- Added `-YesNoAsBoolean` parameter
- Added `-EmptyAsNull` parameter
- Clarified `-NoTypeConversion` behavior and priority
- Fixed null handling in verbose logging
- Improved type conversion logic
- Added order preservation for sections and keys

**v2.0**
- Added comprehensive security validation
- Added `-StrictMode`, `-MaxFileSizeMB`, `-MaxSections`
- Added `-Force` with `-WhatIf` support
- Improved error handling and logging
- Added return object with statistics

---

For more information, use:
```powershell
Get-Help .\Convert-InfToJson.ps1 -Full
```
