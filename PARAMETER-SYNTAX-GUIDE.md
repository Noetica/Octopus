# PowerShell Parameter Syntax Guide

## Common PowerShell Parameter Mistakes

### ❌ INCORRECT - Using Equals Sign
```powershell
# This will NOT work in PowerShell
./Convert-InfToJson.ps1 -MaxSections=2
./Convert-InfToJson.ps1 -InfPath=file.inf
./Convert-InfToJson.ps1 -YesNoAsBoolean=true
```

**Error you'll see:**
```
A parameter cannot be found that matches parameter name 'MaxSections=2'
```

### ✅ CORRECT - Using Space
```powershell
# This is the correct PowerShell syntax
./Convert-InfToJson.ps1 -MaxSections 2
./Convert-InfToJson.ps1 -InfPath file.inf
./Convert-InfToJson.ps1 -YesNoAsBoolean
```

---

## Convert-InfToJson.ps1 - Parameter Syntax Examples

### Parameters with Values

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

### Switch Parameters (Boolean)

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

---

## Complete Examples

### Basic Conversion
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf
```

### With Output Path
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -OutputPath output.json
```

### With Type Conversions
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -YesNoAsBoolean -EmptyAsNull
```

### With Comments Preserved (JSONC Output)
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -PreserveComments
```

**What this does:**
- Creates `.jsonc` file (JSON with Comments)
- Preserves all comments from INF file
- Converts commented INF syntax to JSON format
- Comments can be uncommented to activate settings

**Example Input (config.inf):**
```ini
[Database]
; Production database settings
Host=localhost
Port=5432
; Username=admin
; Password=secret
```

**Example Output (config.jsonc):**
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

### With Validation Limits
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -MaxSections 50 -MaxFileSizeMB 10 -StrictMode
```

### Full Production Example
```powershell
./Convert-InfToJson.ps1 `
    -InfPath ./synthesys.template.inf `
    -OutputPath ./synthesys.jsonc `
    -PreserveComments `
    -YesNoAsBoolean `
    -EmptyAsNull `
    -StripQuotes `
    -MaxSections 100 `
    -StrictMode `
    -Verbose
```

### Preview Mode (WhatIf)
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -WhatIf -Verbose
```

### Force Overwrite
```powershell
./Convert-InfToJson.ps1 -InfPath config.inf -OutputPath existing.json -Force
```

---

## Multi-Line Command Syntax

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

---

## Common Parameter Combinations

### Minimal (Default Behavior)
```powershell
./Convert-InfToJson.ps1 -InfPath file.inf
```
- Auto-detect types (integers, booleans, strings)
- Standard JSON output
- Auto-generate output filename

### Clean Data Conversion
```powershell
./Convert-InfToJson.ps1 -InfPath file.inf -StripQuotes -EmptyAsNull -YesNoAsBoolean
```
- Remove unnecessary quotes
- Empty values become `null`
- Yes/No becomes `true`/`false`

### Documentation Mode (JSONC with Comments)
```powershell
./Convert-InfToJson.ps1 -InfPath file.inf -PreserveComments -YesNoAsBoolean
```
- Creates `.jsonc` file with all comments
- Converts Yes/No to true/false
- Commented properties use JSON syntax
- Uncomment to activate settings

**Example:**
```ini
[Email]
;SMTP Server=smtp.gmail.com
;Use TLS=Yes
ActiveServer=mail.local
```

**Becomes:**
```jsonc
{
  "Email": {
      // "SMTP Server": "smtp.gmail.com",
      // "Use TLS": true,
      "ActiveServer": "mail.local"
  }
}
```

### Security/Validation Mode
```powershell
./Convert-InfToJson.ps1 -InfPath file.inf -StrictMode -MaxSections 50 -MaxFileSizeMB 5
```
- Treats warnings as errors
- Enforces section limit
- Enforces file size limit

### No Type Conversion (Strings Only)
```powershell
./Convert-InfToJson.ps1 -InfPath file.inf -NoTypeConversion
```
- All values remain as strings
- Overrides all other type conversion parameters

---

## Parameter Priority

When parameters conflict, this is the priority order:

1. **NoTypeConversion** (highest - overrides all type conversions)
2. **EmptyAsNull**
3. **YesNoAsBoolean**
4. **Default type detection** (integers, floats)
5. **StripQuotes** (lowest)

Example:
```powershell
# YesNoAsBoolean is ignored because NoTypeConversion is present
./Convert-InfToJson.ps1 -InfPath file.inf -NoTypeConversion -YesNoAsBoolean
```

---

## Getting Help

### View All Parameters
```powershell
Get-Help ./Convert-InfToJson.ps1 -Full
```

### View Examples Only
```powershell
Get-Help ./Convert-InfToJson.ps1 -Examples
```

### View Parameter Details
```powershell
Get-Help ./Convert-InfToJson.ps1 -Parameter PreserveComments
```

---

## Quick Reference Table

| Parameter | Type | Example | Default |
|-----------|------|---------|---------|
| InfPath | String | `-InfPath file.inf` | (required) |
| OutputPath | String | `-OutputPath out.json` | auto-generated |
| NoTypeConversion | Switch | `-NoTypeConversion` | false |
| StripQuotes | Switch | `-StripQuotes` | false |
| EmptyAsNull | Switch | `-EmptyAsNull` | false |
| YesNoAsBoolean | Switch | `-YesNoAsBoolean` | false |
| PreserveComments | Switch | `-PreserveComments` | false (creates .jsonc) |
| StrictMode | Switch | `-StrictMode` | false |
| MaxSections | Integer | `-MaxSections 100` | 10000 |
| MaxFileSizeMB | Integer | `-MaxFileSizeMB 50` | 100 |
| Depth | Integer | `-Depth 10` | 10 |
| DefaultSection | String | `-DefaultSection "Global"` | "_global_" |
| Encoding | String | `-Encoding UTF8` | UTF8 |
| Force | Switch | `-Force` | false |
| WhatIf | Switch | `-WhatIf` | false |
| Verbose | Switch | `-Verbose` | false |

---

## Troubleshooting

### "Parameter cannot be found" Error
**Problem:** Using `=` instead of space
```powershell
❌ -MaxSections=2
✅ -MaxSections 2
```

### "Cannot validate argument" Error
**Problem:** Value out of valid range
```powershell
❌ -MaxSections 0     # Minimum is 1
✅ -MaxSections 1
```

### Switch Parameter Not Working
**Problem:** Adding unnecessary value
```powershell
❌ -PreserveComments true
✅ -PreserveComments
```

### File Path with Spaces
**Problem:** Path not quoted
```powershell
❌ -InfPath C:\Program Files\config.inf
✅ -InfPath "C:\Program Files\config.inf"
```

---

## Best Practices

1. **Quote paths with spaces:** Use double quotes around file paths containing spaces
2. **Use relative paths:** Makes scripts portable across systems
3. **Test with -WhatIf first:** Preview changes before committing
4. **Use -Verbose for debugging:** See exactly what the script is doing
5. **Enable -StrictMode for production:** Catch issues early
6. **Set appropriate limits:** Use -MaxSections and -MaxFileSizeMB for security
7. **Preserve comments for documentation:** Use -PreserveComments for configuration files

---

---

## JSONC (JSON with Comments) Details

### What is JSONC?

JSONC is JSON with Comments - a format that allows `//` style comments in JSON files. It's supported by:
- Visual Studio Code
- IntelliJ IDEA
- Many modern editors and tools

### When to Use `-PreserveComments`

**Use for:**
- 📝 Configuration files needing documentation
- 🔧 Template files with optional settings
- 📋 Files with commented alternatives
- 👥 Team environments
- 🔄 Frequently changing configurations

**Don't use for:**
- 🤖 Machine-only data
- 📦 Minimal file size needs
- 🔒 No human comments needed

### JSONC Features

#### 1. Leading Comments
Comments before properties stay before them:
```jsonc
{
  "Settings": {
      // This enables debug mode
      "Debug": true
  }
}
```

#### 2. Trailing Comments
Comments after properties stay after them:
```jsonc
{
  "Settings": {
      "Debug": true
      // Restart required for changes
  }
}
```

#### 3. Commented Section Blocks
Entire commented sections are preserved:
```jsonc
{
  "Active Section": {
      "Key": "Value"
  },
  // "Disabled Section": {
  //     "Key": "Value",
  // },
  "Another Section": {
      "Key": "Value"
  }
}
```

#### 4. INF-to-JSON Conversion
Commented properties are converted to valid JSON syntax:

**INF:**
```ini
;Server=localhost
;Port=5432
;Enabled=Yes
```

**JSONC:**
```jsonc
// "Server": "localhost",
// "Port": 5432,
// "Enabled": true,
```

**To activate:** Simply remove `//` and it's valid JSON!

### Complete JSONC Example

```powershell
./Convert-InfToJson.ps1 `
    -InfPath synthesys.template.inf `
    -PreserveComments `
    -YesNoAsBoolean `
    -EmptyAsNull `
    -Verbose
```

**Input (synthesys.template.inf):**
```ini
[System]
; Company configuration
CompanyName=Acme Corp
;BackupServer=backup.acme.com
LocalServer=main.acme.com

;[Development]
;Debug=Yes
;LogLevel=Verbose

[Production]
Debug=No
LogLevel=Error
```

**Output (synthesys.template.jsonc):**
```jsonc
{
  "System": {
      // Company configuration
      "CompanyName": "Acme Corp",
      // "BackupServer": "backup.acme.com",
      "LocalServer": "main.acme.com"
  },
  // "Development": {
  //     "Debug": true,
  //     "LogLevel": "Verbose",
  // },
  "Production": {
      "Debug": false,
      "LogLevel": "Error"
  }
}
```

---

**For complete parameter documentation, see:** [PARAMETER-GUIDE.md](./Scripts/Runbooks/InfToJson/PARAMETER-GUIDE.md)