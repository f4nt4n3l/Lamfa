# Security Policy

Lamfa runs Git, GitHub/GitLab/Gitea CLIs, and Docker on your machine. Its
security rules:

- **No telemetry.** Lamfa sends no data anywhere.
- **No secret storage in Lamfa files.** Credentials live in the native stores
  (git-credential-manager, gh, docker) or your SecretManagement vault; logs and
  diagnostics are redacted (tokens, passwords, keys, headers).
- **No silent actions.** Nothing is installed, deleted, pushed, or switched
  without explicit consent; destructive operations require typing the exact
  target name and are hidden in Beginner Mode.
- **One command gateway.** Every external command runs through a single runner
  with argument arrays (no shell strings, no Invoke-Expression) - enforced by
  automated regression tests.


## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private vulnerability
reporting (Security -> Report a vulnerability) on this repository. You will
get an acknowledgment within 7 days. Fixes ship as patch releases with credit
to the reporter (unless you prefer anonymity).

## Supported versions

Only the latest released version receives security fixes.
