# Lamfa Changelog

## [0.1.0] - 2026-07-15

First release.

- Guided console: `lamfa` opens the menu; git-style subcommands jump straight in
  (`status`, `fetch`, `pull`, `push`, `commit`, `branch`, `repos`, `pr`, `docker`,
  `release`, `recover`, `accounts`, `settings`, `doctor`, `help`).
- Repository registry: register, scan, clone, switch, unregister, plus guarded
  deletion that goes to the Recycle Bin/trash - never permanent.
- Git: status/diff/history/branches/remotes/tags/stash/worktrees, selective and
  hunk-level staging, commit wizard, ff-only pull, push with exact-target preview,
  work-preserving undo of the last commit, guided squash, conflict helper, blame,
  commit search, .gitignore helper.
- Providers: GitHub (gh), GitLab (glab), Gitea (tea), and Bitbucket Cloud (REST,
  vault credentials) behind one provider-neutral pull-request menu.
- Docker: images, containers, compose lifecycle (volumes are never deleted),
  registry login via the secret vault and `--password-stdin`.
- Safety model: preconditions block unsafe actions with plain-language reasons,
  remote-changing actions show the exact target first, destructive actions require
  retyping the target name, Beginner Mode hides catastrophic operations, secrets
  are redacted from all logs and output, no telemetry.
- Repository profiles (`.lamfa.json`): schema-validated, content-hash trust,
  project detection, per-project workflow commands.
- Release tools: resumable release state, gated annotated tags, GitHub releases,
  verified git-bundle backups.
- Local web dashboard (127.0.0.1, per-session token; state-changing flows stay in
  the terminal by design).
- Windows first; runs on Linux/macOS wherever PowerShell 7 runs.
- Install: PowerShell Gallery module or portable single-file script.
  Requirements: PowerShell 7 and Git.
