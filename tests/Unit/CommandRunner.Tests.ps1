# Command runner tests - the section 11 mandatory matrix:
# spaces, Unicode, non-zero exit, missing executable, missing directory,
# timeout, cancellation, sanitization. Uses pwsh itself as the external command
# so the suite runs anywhere PowerShell 7 runs.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Core/CommandRunner.psm1') -Force -DisableNameChecking
    $script:workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("lamfa cmd test " + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $script:workDir
}
AfterAll {
    Remove-Item -Path $script:workDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-ExternalCommand' {
    It 'runs a command and captures stdout, exit code, duration' {
        $result = Invoke-ExternalCommand -Executable pwsh `
            -Arguments @('-NoProfile', '-Command', 'Write-Output hello') -WorkingDirectory $script:workDir
        $result.Succeeded | Should -BeTrue
        $result.ExitCode | Should -Be 0
        $result.StandardOutput.Trim() | Should -Be 'hello'
        $result.Duration.TotalMilliseconds | Should -BeGreaterThan 0
    }

    It 'preserves arguments containing spaces (working directory has spaces too)' {
        # -File + param proves the OS-level argument quoting: the value must arrive
        # as ONE argument even though it contains spaces.
        $echoScript = Join-Path $script:workDir 'echo-arg.ps1'
        Set-Content -Path $echoScript -Value 'param($Value) Write-Output $Value' -Encoding utf8
        $result = Invoke-ExternalCommand -Executable pwsh `
            -Arguments @('-NoProfile', '-File', $echoScript, 'two words here') `
            -WorkingDirectory $script:workDir
        $result.StandardOutput.Trim() | Should -Be 'two words here'
    }

    It 'preserves Unicode output' {
        # The test string (u-umlaut, sharp-s, CJK) is composed from code points so
        # this source file stays ASCII-only.
        $unicode = 'H' + [char]0x00FC + 'ttner-' + [char]0x00DF + '-' + [char]0x65E5 + [char]0x672C
        $echoScript = Join-Path $script:workDir 'echo-unicode.ps1'
        Set-Content -Path $echoScript -Value 'param($Value) [Console]::OutputEncoding=[Text.Encoding]::UTF8; Write-Output $Value' -Encoding utf8
        $result = Invoke-ExternalCommand -Executable pwsh `
            -Arguments @('-NoProfile', '-File', $echoScript, $unicode) `
            -WorkingDirectory $script:workDir
        $result.StandardOutput | Should -Match ([regex]::Escape($unicode))
    }

    It 'reports non-zero exit codes as failure without throwing' {
        $result = Invoke-ExternalCommand -Executable pwsh `
            -Arguments @('-NoProfile', '-Command', 'exit 3') -WorkingDirectory $script:workDir
        $result.Succeeded | Should -BeFalse
        $result.ExitCode | Should -Be 3
    }

    It 'captures standard error' {
        $result = Invoke-ExternalCommand -Executable pwsh `
            -Arguments @('-NoProfile', '-Command', '[Console]::Error.WriteLine("bad thing"); exit 1') `
            -WorkingDirectory $script:workDir
        $result.StandardError | Should -Match 'bad thing'
    }

    It 'returns a failed result for a missing executable - no exception' {
        $result = Invoke-ExternalCommand -Executable 'lamfa-does-not-exist-xyz' -WorkingDirectory $script:workDir
        $result.Succeeded | Should -BeFalse
        $result.StandardError | Should -Match 'not found on PATH'
    }

    It 'returns a failed result for a missing working directory - no exception' {
        $result = Invoke-ExternalCommand -Executable pwsh -Arguments @('-NoProfile', '-Command', '1') `
            -WorkingDirectory (Join-Path $script:workDir 'nope')
        $result.Succeeded | Should -BeFalse
        $result.StandardError | Should -Match 'Working directory does not exist'
    }

    It 'passes extra environment variables to the child process' {
        $result = Invoke-ExternalCommand -Executable pwsh `
            -Arguments @('-NoProfile', '-Command', 'Write-Output $env:LAMFA_TEST_VALUE') `
            -WorkingDirectory $script:workDir -Environment @{ LAMFA_TEST_VALUE = 'wired-through' }
        $result.StandardOutput.Trim() | Should -Be 'wired-through'
    }

    It 'produces a redacted SanitizedCommand' {
        $result = Invoke-ExternalCommand -Executable pwsh `
            -Arguments @('-NoProfile', '-Command', 'exit 0', '--password', 'S3cret!') `
            -WorkingDirectory $script:workDir
        $result.SanitizedCommand | Should -Not -Match 'S3cret!'
        $result.SanitizedCommand | Should -Match 'REDACTED'
    }
}

Describe 'Timeout and cancellation' {
    It 'kills the process on timeout and flags WasTimedOut' {
        $result = Invoke-ExternalCommand -Executable pwsh `
            -Arguments @('-NoProfile', '-Command', 'Start-Sleep -Seconds 60') `
            -WorkingDirectory $script:workDir -TimeoutSeconds 2
        $result.WasTimedOut | Should -BeTrue
        $result.Succeeded | Should -BeFalse
        $result.Duration.TotalSeconds | Should -BeLessThan 30
    }

    It 'kills the process on cancellation and flags WasCancelled' {
        $cts = [System.Threading.CancellationTokenSource]::new()
        $cts.CancelAfter(1000)
        $result = Invoke-ExternalCommand -Executable pwsh `
            -Arguments @('-NoProfile', '-Command', 'Start-Sleep -Seconds 60') `
            -WorkingDirectory $script:workDir -CancellationToken $cts.Token
        $cts.Dispose()
        $result.WasCancelled | Should -BeTrue
        $result.Succeeded | Should -BeFalse
        $result.Duration.TotalSeconds | Should -BeLessThan 30
    }
}
