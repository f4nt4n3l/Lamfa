# Lamfa Admin Guide

For the person who installs and maintains Lamfa for a team.

## Installation

Lamfa is portable - no installer.

1. Requirements: Windows 10/11 x64, PowerShell 7 (`winget install Microsoft.PowerShell`),
   Git for Windows. GitHub CLI and Docker Desktop are optional (their menus
   degrade gracefully when absent).
2. Copy the repository (or the generated `dist/Lamfa.ps1` single file).
3. Run: `pwsh -File Lamfa.ps1`.

## Per-user state

Everything user-specific lives under `%LOCALAPPDATA%\Lamfa\`:

| Path | Content |
|---|---|
| `config.json` | mode, workspace roots, repository registrations |
| `logs\` | JSON-lines operation logs, secrets redacted |
| `release-state\` | resumable release step records |
| `profile-trust.json` | trusted repository-profile hashes |

Deleting the folder resets Lamfa to first-run; no repositories are touched.

## Security model (short)

- Secrets are not stored or logged: Git/gh/Docker own the credentials.
- All external commands run through one runner with argument arrays - no shell
  string assembly.
- Repository-owned profiles are data, validated, and trust-gated by content
  hash. Built-in profiles ship with the tool.
- Beginner Mode (default) hides HighRisk operations; the safety engine enforces
  this in code, not just in menus.

## Team profiles

Ship team defaults by adding `profiles/<repositoryname>.json` (see
PROFILE_SCHEMA.md) - matched when a user registers the repository under that
name. Repository-owned `.lamfa.json` takes precedence after user trust.

## Development / quality gate

```powershell
# once per machine (Documents may be write-protected by Controlled Folder
# Access - if so, install to a path under LocalAppData and prepend it to PSModulePath)
Install-Module Pester, PSScriptAnalyzer -Scope CurrentUser

pwsh -File tools/Invoke-QualityChecks.ps1   # PSSA + full Pester suite
pwsh -File tools/Build.ps1                  # regenerate dist/ + checksums
```

CI (`.github/workflows/ci.yml`) runs the same gate plus both self-tests and
uploads `dist/` as an artifact. No production credentials are used anywhere.

## Diagnostics

`pwsh -File tools/Export-DiagnosticBundle.ps1` writes a sanitized ZIP
(versions, redacted config, recent redacted logs) for support - no repository
source files, no tokens.
