# Redaction + structured logging tests.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Core/Logging.psm1') -Force
}

Describe 'Get-RedactedText' {
    It 'redacts <kind>' -ForEach @(
        @{ kind = 'GitHub classic token';      text = 'push failed for ghp_abcdefghij1234567890KLMNOP';          mustNotContain = 'ghp_abcdefghij1234567890KLMNOP' }
        @{ kind = 'GitHub fine-grained token'; text = 'auth github_pat_11ABCDEFG0_abcdefghijklmnopqrstuv';       mustNotContain = 'github_pat_11ABCDEFG0' }
        @{ kind = 'GitLab token';              text = 'using glpat-ABCdef123456789012345';                        mustNotContain = 'glpat-ABCdef123456789012345' }
        @{ kind = 'AWS access key id';         text = 'key AKIAIOSFODNN7EXAMPLE used';                            mustNotContain = 'AKIAIOSFODNN7EXAMPLE' }
        @{ kind = 'URL credentials';           text = 'clone https://user:hunter2@github.com/x/y.git';            mustNotContain = 'hunter2' }
        @{ kind = 'Authorization header';      text = 'Authorization: Bearer eyJhbGciOi.secret.value';            mustNotContain = 'eyJhbGciOi' }
        @{ kind = 'password argument';         text = 'docker login --password S3cret! -u me';                    mustNotContain = 'S3cret!' }
        @{ kind = 'env-style assignment';      text = 'set MY_API_KEY=abc123def456';                              mustNotContain = 'abc123def456' }
    ) {
        $redacted = Get-RedactedText -Text $text
        $redacted | Should -Not -Match ([regex]::Escape($mustNotContain))
        $redacted | Should -Match 'REDACTED'
    }

    It 'leaves ordinary text untouched' {
        Get-RedactedText -Text 'git commit -m "fix login page"' | Should -Be 'git commit -m "fix login page"'
    }
}

Describe 'Get-SanitizedCommandText' {
    It 'quotes arguments containing spaces' {
        Get-SanitizedCommandText -Executable git -Arguments @('commit', '-m', 'two words') |
            Should -Be 'git commit -m "two words"'
    }

    It 'redacts secret arguments' {
        Get-SanitizedCommandText -Executable git -Arguments @('clone', 'https://u:tok@host/r.git') |
            Should -Not -Match 'tok@'
    }
}

Describe 'Lamfa-WriteLog' {
    BeforeAll {
        $script:logDir = Join-Path ([System.IO.Path]::GetTempPath()) ("lamfa-logtest-" + [guid]::NewGuid())
    }
    AfterAll {
        Remove-Item -Path $script:logDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes one JSON line with timestamp, level, message, and data - redacted' {
        Lamfa-WriteLog -Level Warning -Message 'token ghp_abcdefghij1234567890KLMNOP leaked' `
            -Data @{ operationId = 'op-1'; detail = 'password=abc MY_TOKEN=xyz' } -LogDirectory $script:logDir
        $file = Get-ChildItem -Path $script:logDir -Filter 'lamfa-*.log' | Select-Object -First 1
        $file | Should -Not -BeNullOrEmpty
        $entry = Get-Content -Path $file.FullName -Tail 1 | ConvertFrom-Json
        $entry.level | Should -Be 'Warning'
        $entry.operationId | Should -Be 'op-1'
        $entry.timestampUtc | Should -Not -BeNullOrEmpty
        $entry.message | Should -Not -Match 'ghp_abcdefghij'
        $entry.detail | Should -Not -Match 'xyz'
    }

    It 'never throws when the log directory is invalid' {
        { Lamfa-WriteLog -Message 'x' -LogDirectory 'Q:\::invalid::path' -WarningAction SilentlyContinue } |
            Should -Not -Throw
    }
}
