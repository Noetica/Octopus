# Convert-InfToJson.ps1 - Parameter Guide

Complete guide to all parameters and their behaviors for converting INF files to JSON.

---

## Table of Contents
- [PowerShell Syntax](#powershell-syntax)
- [Quick Reference](#quick-reference)
- [Type Conversion Parameters](#type-conversion-parameters)
- [Comment Preservation (JSONC)](#comment-preservation-jsonc)
- [File Handling Parameters](#file-handling-parameters)
- [Validation Parameters](#validation-parameters)
- [Advanced Parameters](#advanced-parameters)
- [Common Scenarios](#common-scenarios)
- [Parameter Interactions](#parameter-interactions)

---

## PowerShell Syntax

### Common Mistake: Using Equals Sign

**❌ INCORRECT - This will NOT work:**
```powershell
./Convert-InfToJson.ps1 -MaxSections=2
./Convert-InfToJson.ps1 -InfPath=file.inf
./Convert-InfToJson.ps1 -YesNoAsBoolean=true
```

**Error you'll see:**
```
A parameter cannot be found that matches parameter name 'MaxSections=2'
```

**✅ CORRECT - Use a space, not equals:**
```powershell
./Convert-InfToJson.ps1 -MaxSections 2
./Convert-InfToJson.ps1 -InfPath file.inf
./Convert-InfToJson.ps1 -YesNoAsBoolean
```

### Parameter Types

#### Parameters with Values
Use a **space** between parameter name and value:

```powershell
# String parameters
-InfPath ./config/app.inf
-OutputPath ./output/app.json
-DefaultSection "GlobalSettings"
-Encoding UTF8

# Integer parameters
-MaxSections 100
-MaxFileSizeMB 50
-Depth 10
```

#### Switch Parameters (Boolean)
Switch parameters don't need a value - their presence means "true":

```powershell
# Correct - just use the parameter name
-NoTypeConversion
-StripQuotes
-EmptyAsNull
-YesNoAsBoolean
-PreserveComments
-StrictMode
-Force
-Verbose
-WhatIf

# Don't do this (unnecessary)
-YesNoAsBoolean $true
-PreserveComments true
```

### Multi-Line Commands

For readability, use backticks (`` ` ``) to continue commands on multiple lines:

```powershell
./Convert-InfToJson.ps1 `
    -InfPath ./config/app.inf `
    -OutputPath ./output/app.jsonc `
    -PreserveComments `
    -YesNoAsBoolean `
    -EmptyAsNull `
    -MaxSections 100 `
    -Verbose
```

**Note:** The backtick must be the **last character** on the line (no spaces after it).

### File Paths with Spaces

Always quote paths containing spaces:

```powershell
# Correct
-InfPath "C:\Program Files\config.inf"
-OutputPath "C:\My Documents\output.json"

# Incorrect
-InfPath C:\Program Files\config.inf
```

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

## Quick Start Examples

### Basic Conversion
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf
```
Creates `config.json` with automatic type detection.

### With JSONC Comments
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -PreserveComments
```
Creates `config.jsonc` with all comments preserved.

### Full Type Conversion
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -YesNoAsBoolean -EmptyAsNull -StripQuotes
```
Converts Yes/No to booleans, empty values to null, removes quotes.

### Production Configuration
```powershell
./Convert-InfToJson.ps1 `
    -InfPath synthesys.template.inf `
    -PreserveComments `
    -YesNoAsBoolean `
    -EmptyAsNull `
    -MaxSections 100 `
    -StrictMode `
    -Verbose
```
Full-featured conversion with validation and documentation.

### Preview Changes
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -WhatIf -Verbose
```
See what would happen without creating files.

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

## Troubleshooting

### Common Errors and Solutions

#### Error: "Parameter cannot be found"

**Error Message:**
```
A parameter cannot be found that matches parameter name 'MaxSections=2'
```

**Problem:** Using equals sign instead of space for parameter values.

**Solution:**
```powershell
# Wrong
./Convert-InfToJson.ps1 -MaxSections=2

# Correct
./Convert-InfToJson.ps1 -MaxSections 2
```

---

#### Error: "Cannot validate argument"

**Error Message:**
```
Cannot validate argument on parameter 'MaxSections'. The 0 argument is less than the minimum allowed range of 1.
```

**Problem:** Parameter value is outside valid range.

**Solution:** Use valid values:
- `-MaxSections`: minimum 1
- `-MaxFileSizeMB`: minimum 1
- `-Depth`: minimum 1

```powershell
# Wrong
./Convert-InfToJson.ps1 -MaxSections 0

# Correct
./Convert-InfToJson.ps1 -MaxSections 1
```

---

#### Error: "Number of sections exceeds maximum allowed"

**Error Message:**
```
Error reading INF file at line 50: Number of sections exceeds maximum allowed (10).
```

**Problem:** INF file has more sections than the limit allows.

**Solution:** Increase `-MaxSections`:
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -MaxSections 100
```

---

#### Error: "File size exceeds maximum"

**Error Message:**
```
File size (150 MB) exceeds maximum allowed (100 MB)
```

**Problem:** INF file is larger than size limit.

**Solution:** Increase `-MaxFileSizeMB`:
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -MaxFileSizeMB 200
```

---

#### Issue: Type Conversions Not Working

**Problem:** Using `-NoTypeConversion` with other type parameters.

**Explanation:** `-NoTypeConversion` overrides all other type conversion parameters.

**Solution:** Remove `-NoTypeConversion` if you want type conversions:
```powershell
# This won't convert types (NoTypeConversion wins)
./Convert-InfToJson.ps1 -InfPath config.inf -NoTypeConversion -YesNoAsBoolean

# This will convert types
./Convert-InfToJson.ps1 -InfPath config.inf -YesNoAsBoolean
```

---

#### Issue: Comments Not Preserved

**Problem:** Forgot `-PreserveComments` parameter.

**Solution:** Add `-PreserveComments` to create JSONC output:
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -PreserveComments
```

**Note:** Only works with `.jsonc` extension (automatically added).

---

#### Issue: File Path Not Found

**Problem:** Path contains spaces without quotes.

**Solution:** Quote paths with spaces:
```powershell
# Wrong
./Convert-InfToJson.ps1 -InfPath C:\Program Files\config.inf

# Correct
./Convert-InfToJson.ps1 -InfPath "C:\Program Files\config.inf"
```

---

#### Issue: Output File Not Created in WhatIf Mode

**Problem:** Using `-WhatIf` prevents file creation.

**Explanation:** `-WhatIf` is a preview mode - it shows what would happen without actually creating files.

**Solution:** Remove `-WhatIf` to create the file:
```powershell
# Preview only (no file created)
./Convert-InfToJson.ps1 -InfPath config.inf -WhatIf

# Actually create file
./Convert-InfToJson.ps1 -InfPath config.inf
```

---

#### Issue: Warnings About Duplicate Keys

**Warning Message:**
```
WARNING: Line 10: Duplicate key 'Setting' in section '[Config]'. Previous value will be overwritten.
```

**Explanation:** INF file has the same key multiple times in one section. Last value wins.

**Solutions:**
1. **Fix the source INF file** (recommended)
2. **Use `-StrictMode`** to treat warnings as errors:
   ```powershell
   ./Convert-InfToJson.ps1 -InfPath config.inf -StrictMode
   ```
3. **Accept the warning** - script will continue and use last value

---

### Getting Help

#### View All Parameters
```powershell
Get-Help ./Convert-InfToJson.ps1 -Full
```

#### View Examples
```powershell
Get-Help ./Convert-InfToJson.ps1 -Examples
```

#### View Specific Parameter
```powershell
Get-Help ./Convert-InfToJson.ps1 -Parameter PreserveComments
```

#### Enable Verbose Output
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -Verbose
```

Shows detailed processing information including:
- Line-by-line parsing
- Type conversion decisions
- Comment association
- Section processing

---

### Best Practices

1. **Test with `-WhatIf` first:**
   ```powershell
   ./Convert-InfToJson.ps1 -InfPath config.inf -WhatIf -Verbose
   ```

2. **Use `-PreserveComments` for configuration files:**
   - Maintains documentation
   - Allows easy uncommenting
   - Creates human-readable output

3. **Enable `-StrictMode` for production:**
   - Catches data quality issues early
   - Fails fast on problems
   - Ensures clean conversions

4. **Set appropriate limits:**
   - `-MaxSections` based on your needs
   - `-MaxFileSizeMB` for security
   - Prevents processing of malformed/malicious files

5. **Use consistent type conversions:**
   - `-YesNoAsBoolean` for cleaner booleans
   - `-EmptyAsNull` for database imports
   - `-StripQuotes` for cleaner strings

6. **Quote paths with spaces:**
   - Always use quotes for paths containing spaces
   - Use forward slashes or escaped backslashes on Windows

7. **Use backticks for multi-line commands:**
   - Improves readability
   - Easier to maintain
   - No trailing spaces after backticks

---

### Performance Tips

- **File Size:** Processing is fast for files under 10MB
- **Section Count:** Performance scales linearly with section count
- **JSONC Mode:** Adds ~30% overhead for comment processing
- **Type Conversion:** Minimal overhead (~1-2ms)
- **Verbose Mode:** Adds minimal overhead, useful for debugging

---

### Support and Documentation

**Files:**
- This guide: Comprehensive parameter reference
- Script help: `Get-Help ./Convert-InfToJson.ps1 -Full`
- Test results: `parameter-test-results.md` (if available)

**Common Use Cases:**
- Configuration file conversion
- Template generation with comments
- Database import preparation
- CI/CD pipeline integration
- Legacy system migration

---

For more information, use:
```powershell
Get-Help .\Convert-InfToJson.ps1 -Full
```
