# Project type detection - evidence only, never executes project code.
Set-StrictMode -Version 3.0

function Lamfa-FindProjectEvidence {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string]$Path)

    $rules = @(
        @{ Pattern = '*.sln';               Type = 'dotnet';  What = 'Visual Studio solution' }
        @{ Pattern = '*.csproj';            Type = 'dotnet';  What = '.NET project' }
        @{ Pattern = 'package.json';        Type = 'node';    What = 'Node.js project' }
        @{ Pattern = 'pnpm-lock.yaml';      Type = 'node';    What = 'pnpm lockfile' }
        @{ Pattern = 'yarn.lock';           Type = 'node';    What = 'yarn lockfile' }
        @{ Pattern = 'pyproject.toml';      Type = 'python';  What = 'Python project' }
        @{ Pattern = 'requirements.txt';    Type = 'python';  What = 'Python requirements' }
        @{ Pattern = 'Dockerfile';          Type = 'docker';  What = 'Dockerfile' }
        @{ Pattern = 'compose.yaml';        Type = 'docker';  What = 'Docker Compose file' }
        @{ Pattern = 'compose.yml';         Type = 'docker';  What = 'Docker Compose file' }
        @{ Pattern = 'docker-compose.yml';  Type = 'docker';  What = 'Docker Compose file' }
        @{ Pattern = 'docker-compose.yaml'; Type = 'docker';  What = 'Docker Compose file' }
        @{ Pattern = '.gitmodules';         Type = 'git';     What = 'Git submodules' }
        @{ Pattern = '.lamfa.json';      Type = 'profile'; What = 'Lamfa repository profile' }
    )
    $evidence = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in $rules) {
        # Top level + one directory deep - deeper matches create more noise than signal.
        $matches_ = @(Get-ChildItem -LiteralPath $Path -Filter $rule.Pattern -File -ErrorAction SilentlyContinue)
        $matches_ += @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter $rule.Pattern -File -ErrorAction SilentlyContinue })
        foreach ($match in $matches_) {
            $evidence.Add([pscustomobject]@{
                PSTypeName  = 'Lamfa.ProjectEvidence'
                ProjectType = $rule.Type
                Description = $rule.What
                File        = [System.IO.Path]::GetRelativePath($Path, $match.FullName)
            })
        }
    }
    # GitHub Actions
    if (Test-Path -LiteralPath (Join-Path $Path '.github/workflows')) {
        $evidence.Add([pscustomobject]@{ PSTypeName = 'Lamfa.ProjectEvidence'
            ProjectType = 'ci'; Description = 'GitHub Actions workflows'; File = '.github/workflows' })
    }
    return $evidence.ToArray()
}

Export-ModuleMember -Function Lamfa-FindProjectEvidence
