# Hunk staging, undo/squash, blame/search, API facade, web dashboard, self-update.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    foreach ($m in @('Git/GitHunks', 'Git/GitUndo', 'Git/GitInsights', 'Git/GitCommits',
                     'Git/GitStatus', 'Git/GitHistory', 'Git/GitBranches', 'Core/ApiFacade',
                     'Core/SelfUpdate', 'UI/WebUi', 'Repositories/RepositoryRegistry')) {
        Import-Module (Join-Path $repoRoot "src/$m.psm1") -Force -DisableNameChecking
    }
    . (Join-Path $repoRoot 'tools/New-TestRepository.ps1')
    $script:fixtures = [System.Collections.Generic.List[object]]::new()
    function New-Fx([string]$State = 'Clean') {
        $fx = New-TestRepository -State $State
        $script:fixtures.Add($fx)
        return $fx
    }
}
AfterAll {
    foreach ($fx in $script:fixtures) { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Hunk-level staging' {
    It 'stages ONE hunk of a file, leaving the other unstaged' {
        $fx = New-Fx
        # two edits far apart -> two hunks
        $content = @('top-original') + (1..12 | ForEach-Object { "context line $_" }) + @('bottom-original')
        Set-Content -Path (Join-Path $fx.Path 'multi.txt') -Value $content
        Add-GitStagedFile -Path $fx.Path -Files @('multi.txt')
        $null = New-GitCommit -Path $fx.Path -Title 'baseline'
        $content[0] = 'top-CHANGED'
        $content[-1] = 'bottom-CHANGED'
        Set-Content -Path (Join-Path $fx.Path 'multi.txt') -Value $content

        $fileHunks = Get-GitFileHunkList -Path $fx.Path -File 'multi.txt'
        @($fileHunks.Hunks).Count | Should -Be 2
        Add-GitStagedHunk -Path $fx.Path -FileHunks $fileHunks -HunkIndexes @(1)
        $staged = Get-GitStagedDiff -Path $fx.Path
        $staged | Should -Match 'top-CHANGED'
        $staged | Should -Not -Match 'bottom-CHANGED'
        # the second hunk is still waiting, unstaged
        @((Get-GitFileHunkList -Path $fx.Path -File 'multi.txt').Hunks).Count | Should -Be 1
    }
}

Describe 'Oops undo' {
    It 'undoes the last commit softly with a backup branch' {
        $fx = New-Fx
        Set-Content -Path (Join-Path $fx.Path 'oops.txt') -Value 'committed too early'
        Add-GitStagedFile -Path $fx.Path -Files @('oops.txt')
        $null = New-GitCommit -Path $fx.Path -Title 'oops commit'
        $plan = Get-GitUndoPlan -Path $fx.Path
        $plan.Kind | Should -Be 'LastCommit'
        $backup = Invoke-GitUndoLastCommit -Path $fx.Path
        $backup | Should -Match '^lamfa-backup/'
        (Get-GitHistory -Path $fx.Path -Limit 1)[0].Subject | Should -Be 'initial commit'
        (Get-GitStatus -Path $fx.Path).HasStaged | Should -BeTrue        # work preserved, staged
        @(Get-GitBranchList -Path $fx.Path).Name | Should -Contain $backup
    }
    It 'refuses when there is nothing safely undoable' {
        $fx = New-Fx
        { Invoke-GitUndoLastCommit -Path $fx.Path } | Should -Throw '*not an undoable commit*'
    }
}

Describe 'Squash last N' {
    It 'squashes 2 commits into one, preserving history on a backup branch' {
        $fx = New-Fx
        foreach ($n in 1, 2) {
            Set-Content -Path (Join-Path $fx.Path "file$n.txt") -Value "content $n"
            Add-GitStagedFile -Path $fx.Path -Files @("file$n.txt")
            $null = New-GitCommit -Path $fx.Path -Title "step $n"
        }
        $backup = Invoke-GitSquashHistory -Path $fx.Path -Count 2 -Title 'steps combined'
        $history = @(Get-GitHistory -Path $fx.Path -Limit 5)
        $history[0].Subject | Should -Be 'steps combined'
        $history.Count | Should -Be 2   # combined + initial
        @(Get-GitBranchList -Path $fx.Path).Name | Should -Contain $backup
        Test-Path (Join-Path $fx.Path 'file1.txt') | Should -BeTrue
    }
    It 'refuses to squash more commits than exist' {
        $fx = New-Fx
        { Invoke-GitSquashHistory -Path $fx.Path -Count 5 -Title x } | Should -Throw '*does not have more than*'
    }
}

Describe 'Blame + commit search + gitignore' {
    It 'blames lines and finds commits by message and by code' {
        $fx = New-Fx
        $blame = @(Get-GitBlame -Path $fx.Path -File 'readme.txt')
        $blame.Count | Should -BeGreaterThan 0
        $blame[0].Author | Should -Be 'Fixture User'
        @(Find-GitCommit -Path $fx.Path -Message 'initial').Count | Should -Be 1
        @(Find-GitCommit -Path $fx.Path -Code 'hello fixture').Count | Should -Be 1
        @(Find-GitCommit -Path $fx.Path -Message 'nothing-matches-this').Count | Should -Be 0
    }
    It 'adds ignore templates without duplicating entries' {
        $fx = New-Fx
        $added = Add-GitIgnoreEntry -Path $fx.Path -Entries (Get-GitIgnoreTemplate -ProjectType dotnet)
        @($added).Count | Should -Be 5
        (Add-GitIgnoreEntry -Path $fx.Path -Entries @('bin/', 'custom/')).Count | Should -Be 1
    }
}

Describe 'API facade' {
    BeforeAll {
        $script:fx = New-Fx 'WithRemote'
        $script:cfg = Join-Path $script:fx.Root 'config.json'
        $registration = Lamfa-AddRepository -Path $script:fx.Path -Name 'api fixture' -ConfigPath $script:cfg
        $null = Lamfa-SetActiveRepository -Id $registration.id -ConfigPath $script:cfg
    }
    It 'answers version and lists operations' {
        $response = Lamfa-Api '{"operation":"version"}' -ConfigPath $script:cfg | ConvertFrom-Json
        $response.ok | Should -BeTrue
        $response.result.version | Should -Match '^\d+\.\d+\.\d+$'
        (Lamfa-Api '{"operation":"operations"}' -ConfigPath $script:cfg | ConvertFrom-Json).result.operations |
            Should -Contain 'status'
    }
    It 'returns structured status for the active repository' {
        $response = Lamfa-Api '{"operation":"status"}' -ConfigPath $script:cfg | ConvertFrom-Json
        $response.ok | Should -BeTrue
        $response.result.branch | Should -Be 'main'
        $response.result.clean | Should -BeTrue
    }
    It 'returns structured errors, never throws' {
        $response = Lamfa-Api '{"operation":"no.such.op"}' -ConfigPath $script:cfg | ConvertFrom-Json
        $response.ok | Should -BeFalse
        $response.type | Should -Be 'ValidationError'
        { Lamfa-Api 'not-json-at-all' -ConfigPath $script:cfg } | Should -Not -Throw
    }
}

Describe 'Web UI guardrails' {
    It 'serves the dashboard and the API only with the session token' {
        # Ask the OS for a genuinely free port - a random pick can collide
        # with a port already in use on the runner.
        $portProbe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $portProbe.Start()
        $port = ([System.Net.IPEndPoint]$portProbe.LocalEndpoint).Port
        $portProbe.Stop()
        $token = 'test-token-123'
        $runner = [powershell]::Create()
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $null = $runner.AddScript({
            param($RepoRoot, $Port, $Token, $Cfg)
            Import-Module (Join-Path $RepoRoot 'src/UI/WebUi.psm1') -Force -DisableNameChecking
            Lamfa-StartWebUi -Port $Port -MaxRequests 3 -Token $Token -NoBrowser -ConfigPath $Cfg
        }).AddArgument($repoRoot).AddArgument($port).AddArgument($token).AddArgument($script:cfg)
        $async = $runner.BeginInvoke()
        try {
            # The authenticated call doubles as the readiness probe - a fixed
            # sleep is a race on loaded CI runners. Connection-refused retries
            # never reach the listener, so they do not consume MaxRequests.
            $ok = $null
            $deadline = [DateTime]::UtcNow.AddSeconds(15)
            while ($null -eq $ok -and [DateTime]::UtcNow -lt $deadline) {
                try {
                    $ok = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api" -Method Post -Body '{"operation":"version"}' `
                        -Headers @{ 'X-Lamfa-Token' = $token; 'Content-Type' = 'application/json' } -TimeoutSec 5
                } catch { Start-Sleep -Milliseconds 250 }
            }
            if ($null -eq $ok) {
                throw "Web UI never came up on port $port. Runspace errors: $($runner.Streams.Error | Out-String)"
            }
            $ok.ok | Should -BeTrue
            { Invoke-RestMethod -Uri "http://127.0.0.1:$port/api" -Method Post -Body '{"operation":"version"}' -TimeoutSec 5 } |
                Should -Throw   # 401 without token
            $html = Invoke-WebRequest -Uri "http://127.0.0.1:$port/?token=$token" -TimeoutSec 10
            $html.Content | Should -Match '<h1>Lamfa</h1>'
        } finally {
            if (-not $async.AsyncWaitHandle.WaitOne(5000)) { $runner.Stop() }   # never hang the suite
            $runner.Dispose()
        }
    }
}

Describe 'Self-update check' {
    It 'reports pre-launch builds as not configured' {
        $check = Lamfa-CheckUpdate -CurrentVersion ([version]'0.1.0') -ProjectUri ''
        $check.UpdateAvailable | Should -BeFalse
        $check.Detail | Should -Match 'pre-launch'
    }
    It 'detects a newer release from the GitHub API (mocked)' {
        $check = Lamfa-CheckUpdate -CurrentVersion ([version]'0.1.0') -ProjectUri 'https://github.com/owner/lamfa' `
            -Fetcher { param($Uri) [pscustomobject]@{ tag_name = 'v0.2.0'; html_url = 'https://github.com/owner/lamfa/releases/v0.2.0' } }
        $check.UpdateAvailable | Should -BeTrue
        $check.Latest | Should -Be '0.2.0'
    }
    It 'reports up-to-date correctly' {
        (Lamfa-CheckUpdate -CurrentVersion ([version]'0.2.0') -ProjectUri 'https://github.com/o/r' `
            -Fetcher { param($u) [pscustomobject]@{ tag_name = 'v0.2.0'; html_url = 'x' } }).UpdateAvailable | Should -BeFalse
    }
}
