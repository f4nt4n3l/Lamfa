<#
    New-TestRepository.ps1 - creates a disposable Git repository in a
    requested state for tests. Dot-source and call New-TestRepository.
    States: Clean, Modified, Staged, Untracked, Renamed, Conflicted, Detached,
            WithRemote (local bare remote + upstream), AheadBehind.
#>
Set-StrictMode -Version 3.0

function Invoke-TestGit {
    param([string]$WorkDir, [string[]]$GitArguments)
    $output = & git -C $WorkDir @GitArguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "test fixture git $($GitArguments -join ' ') failed: $output" }
    return $output
}

function New-TestRepository {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][ValidateSet('Clean', 'Modified', 'Staged', 'Untracked', 'Renamed', 'Conflicted', 'Detached', 'WithRemote', 'AheadBehind')]
        [string]$State = 'Clean',
        [Parameter()][string]$BaseName = 'repo fixture'
    )
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("lamfa-fx-" + [guid]::NewGuid())
    $repo = Join-Path $root $BaseName     # spaces in the path by default - on purpose
    $null = New-Item -ItemType Directory -Path $repo -Force
    Invoke-TestGit $repo @('init', '-b', 'main') | Out-Null
    Invoke-TestGit $repo @('config', 'user.name', 'Fixture User') | Out-Null
    Invoke-TestGit $repo @('config', 'user.email', 'fixture@example.test') | Out-Null
    Set-Content -Path (Join-Path $repo 'readme.txt') -Value 'hello fixture'
    Invoke-TestGit $repo @('add', '--', 'readme.txt') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'initial commit') | Out-Null

    $remote = $null
    switch ($State) {
        'Modified'  { Set-Content -Path (Join-Path $repo 'readme.txt') -Value 'changed content' }
        'Staged'    {
            Set-Content -Path (Join-Path $repo 'staged file.txt') -Value 'staged'
            Invoke-TestGit $repo @('add', '--', 'staged file.txt') | Out-Null
        }
        'Untracked' { Set-Content -Path (Join-Path $repo 'new file.txt') -Value 'untracked' }
        'Renamed'   {
            Invoke-TestGit $repo @('mv', 'readme.txt', 'renamed readme.txt') | Out-Null
        }
        'Conflicted' {
            Invoke-TestGit $repo @('switch', '-c', 'feature') | Out-Null
            Set-Content -Path (Join-Path $repo 'readme.txt') -Value 'feature version'
            Invoke-TestGit $repo @('commit', '-am', 'feature edit') | Out-Null
            Invoke-TestGit $repo @('switch', 'main') | Out-Null
            Set-Content -Path (Join-Path $repo 'readme.txt') -Value 'main version'
            Invoke-TestGit $repo @('commit', '-am', 'main edit') | Out-Null
            & git -C $repo merge feature 2>&1 | Out-Null   # expected to conflict
        }
        'Detached'  {
            $hash = (Invoke-TestGit $repo @('rev-parse', 'HEAD')).ToString().Trim()
            Invoke-TestGit $repo @('checkout', $hash) | Out-Null
        }
        'WithRemote' {
            $remote = Join-Path $root 'remote.git'
            Invoke-TestGit $root @('init', '--bare', '-b', 'main', $remote) | Out-Null
            Invoke-TestGit $repo @('remote', 'add', 'origin', $remote) | Out-Null
            Invoke-TestGit $repo @('push', '-u', 'origin', 'main') | Out-Null
        }
        'AheadBehind' {
            $remote = Join-Path $root 'remote.git'
            Invoke-TestGit $root @('init', '--bare', '-b', 'main', $remote) | Out-Null
            Invoke-TestGit $repo @('remote', 'add', 'origin', $remote) | Out-Null
            Invoke-TestGit $repo @('push', '-u', 'origin', 'main') | Out-Null
            # behind: a second clone pushes a commit; ahead: local commit not pushed
            $other = Join-Path $root 'other'
            Invoke-TestGit $root @('clone', $remote, $other) | Out-Null
            Invoke-TestGit $other @('config', 'user.name', 'Other User') | Out-Null
            Invoke-TestGit $other @('config', 'user.email', 'other@example.test') | Out-Null
            Set-Content -Path (Join-Path $other 'other.txt') -Value 'from other'
            Invoke-TestGit $other @('add', '--', 'other.txt') | Out-Null
            Invoke-TestGit $other @('commit', '-m', 'other commit') | Out-Null
            Invoke-TestGit $other @('push') | Out-Null
            Set-Content -Path (Join-Path $repo 'local.txt') -Value 'local ahead'
            Invoke-TestGit $repo @('add', '--', 'local.txt') | Out-Null
            Invoke-TestGit $repo @('commit', '-m', 'local commit') | Out-Null
            Invoke-TestGit $repo @('fetch') | Out-Null
        }
    }
    return [pscustomobject]@{
        PSTypeName = 'Lamfa.TestRepository'
        Root       = $root
        Path       = $repo
        RemotePath = $remote
    }
}
