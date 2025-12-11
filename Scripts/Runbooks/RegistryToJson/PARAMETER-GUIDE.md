# Registry to JSON Conversion - Parameter Guide

Complete parameter reference for `Export-RegistryToJson.ps1` and `Convert-RegFileToJson.ps1`.

---

## Table of Contents
- [PowerShell Syntax Basics](#powershell-syntax-basics)
- [Script Comparison](#script-comparison)
- [Quick Reference](#quick-reference)
- [Common Parameters](#common-parameters)
- [Export-RegistryToJson.ps1 Parameters](#export-registrytojsonps1-parameters)
- [Convert-RegFileToJson.ps1 Parameters](#convert-regfiletojsonps1-parameters)
- [Type Conversion Reference](#type-conversion-reference)
- [Common Usage Examples](#common-usage-examples)

---

## PowerShell Syntax Basics

### Parameter Syntax

**❌ INCORRECT - Don't use equals sign:**
```powershell
./Export-RegistryToJson.ps1 -RegistryPath=HKLM:\SOFTWARE\MyApp
```

**✅ CORRECT - Use space:**
```powershell
./Export-RegistryToJson.ps1 -RegistryPath "HKLM:\SOFTWARE\MyApp"
```

### Parameter Types

**String parameters** (require a value):
```powershell
-RegistryPath "HKLM:\SOFTWARE\MyApp"
-OutputPath "C:\output\config.json"
-Encoding UTF8
```

**Switch parameters** (no value needed):
```powershell
-Recurse
-PreserveComments
-Force
-Verbose
```

**Integer parameters**:
```powershell
-MaxDepth 5
-MaxKeys 10000
```

### Multi-Line Commands

Use backtick (`` ` ``) to continue on next line:
```powershell
./Export-RegistryToJson.ps1 `
    -RegistryPath "HKLM:\SOFTWARE\MyApp" `
    -Recurse `
    -MaxDepth 3 `
    -PreserveComments
```

---

## Script Comparison

### When to Use Each Script

| Use Case | Script | Why |
|----------|--------|-----|
| Export live registry data | `Export-RegistryToJson.ps1` | Direct access to current registry |
| Convert existing .reg file | `Convert-RegFileToJson.ps1` | Process registry backups/exports |
| Need metadata (types, timestamps) | `Export-RegistryToJson.ps1` | Includes registry metadata |
| Recursive exports | `Export-RegistryToJson.ps1` | Built-in depth control |
| Process offline exports | `Convert-RegFileToJson.ps1` | No registry access required |

---

## Quick Reference

### Export-RegistryToJson.ps1

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-RegistryPath` | String | **Required** | Registry path to export |
| `-OutputPath` | String | Auto | Output JSON file path |
| `-Recurse` | Switch | False | Export subkeys recursively |
| `-MaxDepth` | Int | 5 | Max recursion depth (1-50) |
| `-IncludeMetadata` | Switch | False | Include registry metadata |
| `-PreserveComments` | Switch | False | Output JSONC with comments |
| `-PreserveFullPath` | Switch | False | Keep full registry paths as keys |
| `-ConvertBooleanStrings` | Switch | False | Convert "true"/"false" to booleans |
| `-BinaryAsBase64` | Switch | False | Convert binary to Base64 |
| `-ExpandEnvironmentStrings` | Switch | False | Expand %VARIABLES% |
| `-IncludeDefaultValue` | Bool | True | Include (Default) value |
| `-Encoding` | String | UTF8 | Output encoding |
| `-StrictMode` | Switch | False | Treat warnings as errors |
| `-Force` | Switch | False | Overwrite without prompt |
| `-Depth` | Int | 100 | JSON serialization depth |
| `-MaxKeys` | Int | 10000 | Max keys to process |

### Convert-RegFileToJson.ps1

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-RegFilePath` | String | **Required** | Path to .reg file |
| `-OutputPath` | String | Auto | Output JSON file path |
| `-Encoding` | String | Unicode | .reg file encoding |
| `-OutputEncoding` | String | UTF8 | JSON file encoding |
| `-PreserveComments` | Switch | False | Output JSONC with comments |
| `-PreserveFullPath` | Switch | False | Keep full registry paths |
| `-SplitMultiLineStrings` | Switch | False | Split REG_MULTI_SZ into arrays |
| `-ConvertBooleanStrings` | Switch | False | Convert "true"/"false" to booleans |
| `-Force` | Switch | False | Overwrite without prompt |

---

## Common Parameters

Parameters that work the same in both scripts.

### `-OutputPath`

**Default:** Auto-generated based on source name  
**Format:** File path string

```powershell
# Auto-generated (MyApp.json in current directory)
-RegistryPath "HKLM:\SOFTWARE\MyApp"

# Specific path
-OutputPath "C:\exports\config.json"

# With -PreserveComments, auto-generates .jsonc extension
-PreserveComments  # Creates MyApp.jsonc
```

### `-PreserveComments`

**Default:** False (creates .json)  
**When enabled:** Creates .jsonc file with descriptive comments

**Export-RegistryToJson.ps1** - Generates comments about structure:
```jsonc
{
  // Registry Key: HKEY_LOCAL_MACHINE\SOFTWARE\MyApp
  "MyApp": {
    "Version": "1.0",      // REG_SZ (String)
    "Port": 8080           // REG_DWORD (32-bit Integer)
  }
}
```

**Convert-RegFileToJson.ps1** - Preserves existing .reg comments:
```jsonc
{
  // Application configuration
  "MyApp": {
    "Version": "1.0"  // Current version
  }
}
```

### `-PreserveFullPath`

**Default:** False (creates hierarchical structure)  
**When enabled:** Uses full registry paths as flat keys

**Without (hierarchical):**
```json
{
  "MyApp": {
    "Database": {
      "Host": "localhost"
    }
  }
}
```

**With (flat):**
```json
{
  "HKEY_LOCAL_MACHINE\\SOFTWARE\\MyApp\\Database": {
    "Host": "localhost"
  }
}
```

### `-ConvertBooleanStrings`

**Default:** False (keeps as strings)  
**When enabled:** Converts "true"/"false" to boolean types

```powershell
# String values
"Enabled": "true"   →   "Enabled": true
"Debug": "false"    →   "Debug": false
"Active": "TRUE"    →   "Active": true
```

**Rules:**
- Case-insensitive
- Only exact matches ("true" or "false")
- Preserves other strings ("true story", "false alarm")

### `-Force`

**Default:** False (prompts if file exists)  
**When enabled:** Overwrites without confirmation

Use in automation/CI-CD where prompts aren't possible.

---

## Export-RegistryToJson.ps1 Parameters

Parameters specific to exporting live registry data.

### `-RegistryPath` (Required)

The registry path to export. Supports multiple formats:

```powershell
# PowerShell drive format (recommended)
-RegistryPath "HKLM:\SOFTWARE\MyApp"
-RegistryPath "HKCU:\Software\MyCompany"

# Full Windows format
-RegistryPath "HKEY_LOCAL_MACHINE\SOFTWARE\MyApp"

# Abbreviated
-RegistryPath "HKLM\SOFTWARE\MyApp"
```

**Registry Hives:**
- `HKCR` / `HKEY_CLASSES_ROOT` - File associations
- `HKCU` / `HKEY_CURRENT_USER` - Current user settings
- `HKLM` / `HKEY_LOCAL_MACHINE` - System-wide settings
- `HKU` / `HKEY_USERS` - All user profiles
- `HKCC` / `HKEY_CURRENT_CONFIG` - Hardware profiles

### `-Recurse`

**Default:** False (exports only specified key)  
**When enabled:** Exports subkeys recursively

```powershell
# Single key only
./Export-RegistryToJson.ps1 -RegistryPath "HKLM:\SOFTWARE\MyApp"

# Include all subkeys
./Export-RegistryToJson.ps1 `
    -RegistryPath "HKLM:\SOFTWARE\MyApp" `
    -Recurse
```

### `-MaxDepth`

**Range:** 1-50  
**Default:** 5  
**Only applies when:** `-Recurse` is used

Controls how many levels deep to traverse:

```powershell
# Shallow (immediate children only)
-Recurse -MaxDepth 1

# Typical application config
-Recurse -MaxDepth 3

# Deep branch export
-Recurse -MaxDepth 10
```

### `-IncludeMetadata`

**Default:** False  
**When enabled:** Includes registry metadata in output

```json
{
  "MyApp": {
    "_metadata": {
      "RegistryPath": "HKEY_LOCAL_MACHINE\\SOFTWARE\\MyApp",
      "LastWriteTime": "2024-01-15T10:30:00Z",
      "ValueCount": 3
    },
    "Version": {
      "Value": "1.0",
      "Type": "REG_SZ"
    }
  }
}
```

Use for auditing, documentation, or troubleshooting.

### `-BinaryAsBase64`

**Default:** False (exports as byte arrays)  
**When enabled:** Converts REG_BINARY to Base64 strings

```json
// Without
"BinaryData": [255, 254, 253, 252]

// With -BinaryAsBase64
"BinaryData": "//79/A=="
```

Recommended for REST APIs and network transmission.

### `-ExpandEnvironmentStrings`

**Default:** False (preserves variables)  
**When enabled:** Expands environment variables in REG_EXPAND_SZ values

```json
// Without
"InstallPath": "%ProgramFiles%\\MyApp"

// With -ExpandEnvironmentStrings
"InstallPath": "C:\\Program Files\\MyApp"
```

**Warning:** Expansion happens on current system. Don't use for portable configs.

### `-IncludeDefaultValue`

**Type:** Boolean  
**Default:** True

Controls whether to include the `(Default)` registry value.

```powershell
# Exclude default value
-IncludeDefaultValue $false

# Include (default behavior)
-IncludeDefaultValue $true
```

### `-StrictMode`

**Default:** False (warnings logged, processing continues)  
**When enabled:** Warnings become errors, script fails fast

Use in CI/CD pipelines to catch permission/access issues.

### `-MaxKeys`

**Range:** 1-100,000  
**Default:** 10,000

Safety limit to prevent processing too many keys:

```powershell
# Small export
-MaxKeys 1000

# Large registry branch
-MaxKeys 50000
```

Script warns when limit is reached.

### `-Encoding`

**Default:** UTF8  
**Valid Values:** UTF8, ASCII, Unicode, UTF7, UTF32, Default

Output file encoding. UTF8 recommended for JSON.

### `-Depth`

**Range:** 1-100  
**Default:** 100

Controls JSON serialization depth (not registry traversal depth).  
Rarely needs adjustment.

---

## Convert-RegFileToJson.ps1 Parameters

Parameters specific to converting .reg files.

### `-RegFilePath` (Required)

Path to the Windows Registry export file:

```powershell
-RegFilePath "C:\exports\config.reg"
-RegFilePath "\\server\share\backup.reg"
-RegFilePath ".\registry-export.reg"
```

**Supported formats:**
- Windows Registry Editor Version 5.00 (Windows 2000+)
- REGEDIT4 (Windows 95/98/NT)

### `-Encoding`

**Default:** Unicode  
**Valid Values:** Unicode, UTF8, UTF16, ASCII, Default

Encoding of the **input** .reg file (not output).

```powershell
# Default (most .reg files)
-Encoding Unicode

# UTF-8 .reg files
-Encoding UTF8
```

Most Windows .reg exports are Unicode (UTF-16 LE).

### `-OutputEncoding`

**Default:** UTF8  
**Valid Values:** UTF8, ASCII, Unicode, UTF7, UTF32, Default

Encoding of the **output** JSON file.

```powershell
# Read Unicode .reg, write UTF8 JSON
-Encoding Unicode -OutputEncoding UTF8
```

### `-SplitMultiLineStrings`

**Default:** False (preserves as string with \n)  
**When enabled:** Splits REG_MULTI_SZ into JSON arrays

```json
// Without
"Paths": "C:\\Path1\nC:\\Path2\nC:\\Path3"

// With -SplitMultiLineStrings
"Paths": [
  "C:\\Path1",
  "C:\\Path2",
  "C:\\Path3"
]
```

Recommended for REST APIs where consumers expect arrays.

---

## Type Conversion Reference

How registry data types map to JSON types.

### Registry Value Types

| Registry Type | Description | Default JSON Output | Options |
|---------------|-------------|---------------------|---------|
| REG_SZ | String | String | - |
| REG_DWORD | 32-bit integer | Number | - |
| REG_QWORD | 64-bit integer | Number | - |
| REG_BINARY | Binary data | Array of bytes | Base64 with `-BinaryAsBase64` |
| REG_MULTI_SZ | Multi-line string | String with \n | Array with `-SplitMultiLineStrings` |
| REG_EXPAND_SZ | Expandable string | String (unexpanded) | Expanded with `-ExpandEnvironmentStrings` |

### Examples

**REG_SZ (String):**
```json
{ "AppName": "MyApplication" }
```

**REG_DWORD (32-bit Integer):**
```json
{ "Port": 8080, "Timeout": 30 }
```

**REG_QWORD (64-bit Integer):**
```json
{ "MaxFileSize": 5368709120 }
```

**REG_BINARY:**
```json
// Default
{ "Data": [255, 254, 253, 252] }

// With -BinaryAsBase64
{ "Data": "//79/A==" }
```

**REG_MULTI_SZ:**
```json
// Default
{ "SearchPaths": "C:\\Path1\nC:\\Path2\nC:\\Path3" }

// With -SplitMultiLineStrings
{ "SearchPaths": ["C:\\Path1", "C:\\Path2", "C:\\Path3"] }
```

**REG_EXPAND_SZ:**
```json
// Default
{ "InstallPath": "%ProgramFiles%\\MyApp" }

// With -ExpandEnvironmentStrings
{ "InstallPath": "C:\\Program Files\\MyApp" }
```

**String Boolean Conversion:**
```json
// Default
{ "Enabled": "true", "Debug": "false" }

// With -ConvertBooleanStrings
{ "Enabled": true, "Debug": false }
```

---

## Common Usage Examples

### Basic Single Key Export
```powershell
./Export-RegistryToJson.ps1 -RegistryPath "HKLM:\SOFTWARE\MyApp"
```
Creates `MyApp.json` in current directory.

### Recursive Export with Comments
```powershell
./Export-RegistryToJson.ps1 `
    -RegistryPath "HKLM:\SOFTWARE\MyApp" `
    -Recurse `
    -MaxDepth 3 `
    -PreserveComments
```
Creates `MyApp.jsonc` with structure documentation.

### REST API Optimized Export
```powershell
./Export-RegistryToJson.ps1 `
    -RegistryPath "HKCU:\Software\MyApp" `
    -ConvertBooleanStrings `
    -BinaryAsBase64 `
    -OutputPath "api-config.json"
```
Proper types for API consumption.

### Convert .reg File to JSON
```powershell
./Convert-RegFileToJson.ps1 -RegFilePath "backup.reg"
```
Creates `backup.json` with hierarchical structure.

### Convert .reg with Full Paths
```powershell
./Convert-RegFileToJson.ps1 `
    -RegFilePath "backup.reg" `
    -PreserveFullPath `
    -PreserveComments
```
Maintains exact registry paths from .reg file.

### REST API Optimized .reg Conversion
```powershell
./Convert-RegFileToJson.ps1 `
    -RegFilePath "export.reg" `
    -SplitMultiLineStrings `
    -ConvertBooleanStrings `
    -OutputPath "api-ready.json"
```
Arrays and booleans for modern APIs.

### Full Documentation Export
```powershell
./Export-RegistryToJson.ps1 `
    -RegistryPath "HKLM:\SOFTWARE\MyCompany" `
    -Recurse `
    -MaxDepth 5 `
    -PreserveComments `
    -IncludeMetadata `
    -OutputPath "registry-docs.jsonc"
```
Complete documentation with metadata.

### CI/CD Pipeline Export
```powershell
./Export-RegistryToJson.ps1 `
    -RegistryPath "HKLM:\SOFTWARE\MyApp" `
    -Recurse `
    -StrictMode `
    -Force `
    -OutputPath "$env:BUILD_ARTIFACTSTAGINGDIRECTORY\config.json"
```
Automated export with strict validation.

### Cross-Platform Configuration
```powershell
./Export-RegistryToJson.ps1 `
    -RegistryPath "HKCU:\Software\MyApp" `
    -ConvertBooleanStrings `
    -OutputPath "portable-config.json"
```
Portable config (without `-ExpandEnvironmentStrings`).

### Audit Export with Full Paths
```powershell
./Export-RegistryToJson.ps1 `
    -RegistryPath "HKLM:\SOFTWARE\MyApp" `
    -Recurse `
    -PreserveFullPath `
    -IncludeMetadata `
    -StrictMode `
    -OutputPath "audit-report.json"
```
Complete audit trail with exact paths.

---

**Version:** 1.0  
**Last Updated:** 2024-01-15