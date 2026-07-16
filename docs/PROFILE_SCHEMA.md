# Lamfa Profile Schema (schemaVersion 1)

A profile tells Lamfa how to work with a specific repository: its branches,
its build/test/run commands, its Docker targets. Profiles are data only - no
scripts, no expressions. Two kinds:

- **Repository-owned:** `.lamfa.json` in the repository root. Runs only
  after you review and trust it; any content change requires re-trusting.
- **Built-in:** shipped under `profiles/`, matched by registered repository
  name (lowercased), e.g. `profiles/myapp.json`. `profiles/default.json`
  is the fallback.

An invalid profile does not disable generic Git features - Lamfa falls back
to the default profile and reports the validation errors.

## Shape

```json
{
  "schemaVersion": 1,
  "repository": {
    "preferredRemote": "origin",
    "defaultBranch": "main",
    "integrationBranch": "develop",
    "releaseBranch": "main"
  },
  "project": {
    "type": "dotnet",
    "versionFile": "src/App/App.csproj"
  },
  "commands": {
    "build": { "executable": "dotnet", "arguments": ["build", "src/App/App.csproj"] },
    "test":  { "executable": "dotnet", "arguments": ["test"] }
  },
  "docker": {
    "dockerfile": "Dockerfile",
    "composeFiles": ["compose.yaml"],
    "image": "example/app",
    "registry": "ghcr.io/company"
  },
  "workflows": {}
}
```

## Rules

| Field | Rule |
|---|---|
| `schemaVersion` | must be `1` |
| `commands.<name>.executable` | required, no shell metacharacters (`| ; & < >`) |
| `commands.<name>.arguments` | JSON array of strings; each element is passed as ONE argument (spaces safe) |
| `project.versionFile` | `.csproj` (`<Version>`), `package.json` (`version`), or a one-line version file |
| `docker.registry` + `docker.image` | both required for registry push; the push reference is `registry/image:tag` |
| `repository.provider` | optional override: `github`, `gitlab`, `gitea`, `bitbucket` - wins over remote-URL detection (self-hosted instances need this) |
| `commit.titlePattern` + `commit.hint` | optional regex the commit wizard enforces on titles, with a plain-language hint |

Command names are free-form; `build`, `test`, `run`, `clean`, `backup`,
`quality` appear in the Build/test menu automatically. Commands always execute
through Lamfa's command runner (explicit working directory = repository
root, output captured, secrets redacted in logs).
