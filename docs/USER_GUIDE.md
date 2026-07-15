# Lamfa User Guide

Lamfa is a console tool for managing Git repositories, GitHub, and Docker.
Every action shows an explanation - what it does and how to recover - before
it runs.

## Starting

```powershell
pwsh -File Lamfa.ps1
```

On first start Lamfa checks your tools (Git required; GitHub CLI and Docker
optional) and offers three ways to get a repository: register an existing
folder, scan a folder, or clone from a URL.

## The dashboard

The header always shows: your environment, the ACTIVE repository (name, path,
branch, upstream, clean/dirty, ahead/behind), and one recommended next action.
If the header says the wrong repository is active, fix that first - every
action targets the active repository.

## Menus

| # | Menu | What you do there |
|---|---|---|
| 1 | Repositories | switch / register / scan / clone / open / unregister / guarded delete |
| 2 | Git status and changes | status, diffs, history, fetch, safe pull (fast-forward only) |
| 3 | Branches and worktrees | create/switch branches, stash, delete merged branches, worktrees |
| 4 | Commit and push | commit wizard (pick files -> review -> commit), push with exact-target preview |
| 5 | Pull requests | create PR (explicit base), checks, reviews, open in browser |
| 6 | Build, test, quality | run the repository profile's commands; comment audit; trust profiles |
| 7 | Docker | images, containers, compose, guarded context switch, guarded registry push |
| 8 | Release | version + changelog view, resumable release record, guarded tag |
| 9 | Backup and recovery | plain-language guidance for stuck states; Git bundle backup |
| 10 | Accounts | Git identity vs GitHub account vs Docker login - shown separately |
| 11 | Settings and help | Beginner/Advanced mode, help, glossary, logs |

## Safety rules

1. **A failed check blocks the action.** If a precondition fails, the action
   does not run; Lamfa shows the reason and the next step.
2. **Destructive actions require typing the exact target name** (branch name,
   repository name, full image reference).
3. **Beginner Mode hides force push, hard reset, and volume deletion.**
   Advanced Mode reveals them - type ADVANCED in Settings to switch.

## Typical daily flow

1. Open Lamfa -> check the dashboard is on the right repository and branch.
2. Menu 3: create a branch for your work.
3. Edit files in your editor as usual.
4. Menu 4: commit wizard - select ONLY the files that belong together, give a
   short imperative title.
5. Push (the preview shows exactly where the commits go).
6. Menu 5: create the pull request with an explicit base branch.

## When something looks broken

Open menu 9. Lamfa detects merges/rebases in progress, detached HEAD,
diverged branches, and missing upstreams, and lists steps that PRESERVE your
work. Nothing there deletes anything.

## Where things live

- Configuration: `%LOCALAPPDATA%\Lamfa\config.json`
- Logs (secrets redacted): `%LOCALAPPDATA%\Lamfa\logs\`
- Release state: `%LOCALAPPDATA%\Lamfa\release-state\`

Full glossary: menu 11 -> Help.
