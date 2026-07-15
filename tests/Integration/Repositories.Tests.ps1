# Repository registry integration tests: registration, duplicates,
# spaces, discovery, clone from local source, deletion guards.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Repositories/RepositoryValidation.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Repositories/RepositoryRegistry.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Repositories/RepositoryDiscovery.psm1') -Force
    . (Join-Path $repoRoot 'tools/New-TestRepository.ps1')

    $script:sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("lamfa-reg-" + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $script:sandbox
    $script:cfg = Join-Path $script:sandbox 'config.json'
}
AfterAll {
    Remove-Item -Path $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Path normalization' {
    It 'normalizes trailing separators and resolves dots' -Skip:(-not $IsWindows) {
        Get-NormalizedPath 'C:\Repos\Demo\' | Should -Be 'C:\Repos\Demo'
        Get-NormalizedPath 'C:\Repos\.\Sub\..\Demo' | Should -Be 'C:\Repos\Demo'
    }
    It 'compares case-insensitively' -Skip:(-not $IsWindows) {
        Test-SamePath 'C:\REPOS\demo' 'c:\Repos\Demo\' | Should -BeTrue
        Test-SamePath 'C:\Repos\A' 'C:\Repos\B' | Should -BeFalse
    }
    It 'detects containment and drive roots' -Skip:(-not $IsWindows) {
        Test-PathInsideRoot -Path 'C:\Repos\Demo\sub' -Root 'C:\Repos' | Should -BeTrue
        Test-PathInsideRoot -Path 'C:\Other' -Root 'C:\Repos' | Should -BeFalse
        Test-IsDriveRoot 'D:\' | Should -BeTrue
        Test-IsDriveRoot 'D:\Lamfa' | Should -BeFalse
    }
}

Describe 'Registry' {
    It 'registers a folder with spaces and lists it' {
        $folder = Join-Path $script:sandbox 'my repo one'
        $null = New-Item -ItemType Directory -Path $folder
        $registration = Lamfa-AddRepository -Path $folder -ConfigPath $script:cfg
        $registration.name | Should -Be 'my repo one'
        @(Lamfa-GetRepositoryList -ConfigPath $script:cfg).Count | Should -Be 1
    }
    It 'rejects duplicate paths regardless of case/trailing slash' {
        # POSIX paths are case-sensitive, so only vary the case on Windows.
        $base = Join-Path $script:sandbox 'my repo one'
        $folder = if ($IsWindows) { $base.ToUpperInvariant() + '\' } else { $base + '/' }
        { Lamfa-AddRepository -Path $folder -ConfigPath $script:cfg } | Should -Throw '*already registered*'
    }
    It 'switches the active repository and returns a context' {
        $id = (Lamfa-GetRepositoryList -ConfigPath $script:cfg)[0].id
        $context = Lamfa-SetActiveRepository -Id $id -ConfigPath $script:cfg
        $context.Name | Should -Be 'my repo one'
        $context.IsGitRepository | Should -BeFalse
    }
    It 'unregisters without deleting the folder' {
        $id = (Lamfa-GetRepositoryList -ConfigPath $script:cfg)[0].id
        Lamfa-RemoveRepository -Id $id -ConfigPath $script:cfg
        @(Lamfa-GetRepositoryList -ConfigPath $script:cfg).Count | Should -Be 0
        Test-Path (Join-Path $script:sandbox 'my repo one') | Should -BeTrue
    }
}

Describe 'Discovery' {
    It 'finds git repositories under a root, skipping non-repos' {
        $fx = New-TestRepository -State Clean
        try {
            $found = Lamfa-FindRepository -Root $fx.Root -MaxDepth 3
            @($found).Count | Should -Be 1
            $found[0].Path | Should -Be (Get-NormalizedPath $fx.Path)
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Clone' {
    It 'clones from a local source and registers it' {
        $fx = New-TestRepository -State Clean
        try {
            $registration = Lamfa-InvokeClone -Url $fx.Path -DestinationParent $script:sandbox -Name 'cloned repo' -ConfigPath $script:cfg
            $registration.name | Should -Be 'cloned repo'
            (Lamfa-TestRepository -Path $registration.path).IsGitRepository | Should -BeTrue
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'refuses an invalid source and a non-empty destination' {
        { Lamfa-InvokeClone -Url 'ftp://nope' -DestinationParent $script:sandbox -ConfigPath $script:cfg } | Should -Throw '*not an HTTPS, SSH, or local*'
        { Lamfa-InvokeClone -Url 'https://example.test/x.git' -DestinationParent $script:sandbox -Name 'cloned repo' -ConfigPath $script:cfg } | Should -Throw '*'
    }
}

Describe 'Guarded deletion' {
    It 'refuses deletion when uncommitted changes exist' {
        $fx = New-TestRepository -State Modified
        try {
            Lamfa-AddWorkspaceRoot -Path $fx.Root -ConfigPath $script:cfg
            $registration = Lamfa-AddRepository -Path $fx.Path -Name 'dirty fixture' -ConfigPath $script:cfg
            { Lamfa-RemoveRepositoryFolder -Id $registration.id -ConfigPath $script:cfg } |
                Should -Throw '*Uncommitted*'
            Test-Path $fx.Path | Should -BeTrue
            Lamfa-RemoveRepository -Id $registration.id -ConfigPath $script:cfg
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'refuses deletion when no remote exists (history nowhere else)' {
        $fx = New-TestRepository -State Clean
        try {
            Lamfa-AddWorkspaceRoot -Path $fx.Root -ConfigPath $script:cfg
            $registration = Lamfa-AddRepository -Path $fx.Path -Name 'no remote fixture' -ConfigPath $script:cfg
            { Lamfa-RemoveRepositoryFolder -Id $registration.id -ConfigPath $script:cfg } |
                Should -Throw '*No remote*'
            Lamfa-RemoveRepository -Id $registration.id -ConfigPath $script:cfg
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'refuses deletion outside approved workspace roots without the override' {
        $fx = New-TestRepository -State WithRemote
        try {
            $registration = Lamfa-AddRepository -Path $fx.Path -Name 'outside roots fixture' -ConfigPath $script:cfg
            { Lamfa-RemoveRepositoryFolder -Id $registration.id -ConfigPath $script:cfg } |
                Should -Throw '*outside every approved workspace root*'
            Lamfa-RemoveRepository -Id $registration.id -ConfigPath $script:cfg
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
