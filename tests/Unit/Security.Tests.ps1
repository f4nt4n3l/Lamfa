# Automated security guards - regression-proofs the review findings:
# the forbidden patterns below must never (re)appear in Lamfa sources.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:sources = @(Get-ChildItem -Path (Join-Path $repoRoot 'src') -Recurse -Include '*.psm1') +
        @(Get-Item (Join-Path $repoRoot 'Lamfa.psm1'), (Get-Item (Join-Path $repoRoot 'Lamfa.ps1')),
          (Get-Item (Join-Path $repoRoot 'Build.ps1')))
}

Describe 'Security guards' {
    It 'never uses Invoke-Expression (arbitrary code execution)' {
        @($script:sources | Select-String -Pattern 'Invoke-Expression|\biex\b' -CaseSensitive:$false) |
            Should -BeNullOrEmpty
    }
    It 'never splits a command string into arguments' {
        @($script:sources | Select-String -Pattern "-split\s+' '") | Should -BeNullOrEmpty
    }
    It 'never force-pushes and never hard-resets' {
        @($script:sources | Select-String -Pattern "'--force'|'-f'.*push|'reset'.*'--hard'") |
            Should -BeNullOrEmpty
    }
    It 'never passes --volumes to compose down' {
        $hits = @($script:sources | Select-String -Pattern '--volumes' |
            Where-Object { $_.Line -notmatch '^\s*#' })   # comments may DOCUMENT the ban
        $hits | Should -BeNullOrEmpty
    }
    It 'never reads token-displaying gh commands' {
        @($script:sources | Select-String -Pattern "'auth'\s*,\s*'token'") | Should -BeNullOrEmpty
    }
    It 'never stores a plain password parameter' {
        @($script:sources | Select-String -Pattern '\[string\]\$Password') | Should -BeNullOrEmpty
    }
    It 'external commands are invoked only through the runner (one Process.Start in the codebase)' {
        $processStarts = @($script:sources | Select-String -Pattern '\[System\.Diagnostics\.Process\]::new|Diagnostics\.Process\b')
        @($processStarts | Where-Object { $_.Filename -ne 'CommandRunner.psm1' }) | Should -BeNullOrEmpty
    }
}
