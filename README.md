# Lamfa

A console tool for managing Git repositories, GitHub / GitLab / Gitea /
Bitbucket, and Docker.

Before an action runs, Lamfa shows what it will do and how to undo it.
Failed checks block the action; destructive operations require typing the
exact target name; force-push, hard reset, and volume deletion are only
available in Advanced Mode.

```text
> lamfa
 Lamfa > main menu           Enter=select  Esc=back  ?=help
   1. Repositories          6. Build, test, and quality
   2. Git status/changes    7. Docker
 > 3. Branches/worktrees    8. Release
   4. Commit and push       9. Backup and recovery
   5. Pull requests         A. Accounts   S. Settings

> lamfa push
 PUSH TARGET
   Branch  : feature/login
   Remote  : origin  git@github.com:you/app.git
   Commits : 2
 Push? [y/N]
```

## Install

```powershell
# PowerShell Gallery (after first public release)
Install-Module Lamfa
lamfa

# Or portable: download Lamfa-<version>.zip from Releases, then
pwsh -File Lamfa.ps1
```

Requirements: PowerShell 7 (`winget install Microsoft.PowerShell`) + Git.
GitHub CLI, glab, tea, and Docker are optional - Lamfa offers to install a
missing tool when a feature needs it (after confirmation).

## Commands

`lamfa` opens the menu; subcommands jump straight in:

```text
lamfa status    lamfa push      lamfa pr        lamfa docker
lamfa fetch     lamfa commit    lamfa release   lamfa recover
lamfa pull      lamfa branch    lamfa repos     lamfa doctor
```

## Safety model

1. Preconditions gate every operation - a failure blocks the action and shows
   the reason and the next step.
2. Remote-changing actions show the exact target (remote URL, branch, image
   reference) before confirmation.
3. Destructive actions require retyping the target name; repository deletion
   goes to the Recycle Bin/trash instead of being deleted permanently.
4. Beginner Mode (default) hides force-push, hard reset, and volume deletion.
   Advanced Mode is enabled explicitly in Settings.
5. Secrets live in native credential stores or your SecretManagement vault,
   not in Lamfa files, logs, or output (log redaction is automatic).

Full details: [SECURITY.md](SECURITY.md).

## Documentation

- [User guide](docs/USER_GUIDE.md) - menus, daily flow, safety rules
- [Recovery guide](docs/RECOVERY_GUIDE.md) - merge conflicts, detached HEAD, diverged branches
- [Profile schema](docs/PROFILE_SCHEMA.md) - define your project's build/test/run commands
- [Admin guide](docs/ADMIN_GUIDE.md) - installation, configuration, development
- [Docs index](docs/index.md)

## License

[MIT](LICENSE) - (c) 2026 Lamfa.
