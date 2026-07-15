# Model contract tests.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Models/CommandResult.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Models/DependencyStatus.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Models/RepositoryContext.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Models/OperationDefinition.psm1') -Force
}

Describe 'CommandResult' {
    It 'carries the full section 10.1 contract and computes Duration' {
        $start = [DateTime]::UtcNow
        $result = New-CommandResult -Executable git -Arguments @('status') -WorkingDirectory 'C:\x' `
            -StartedUtc $start -EndedUtc $start.AddSeconds(2) -ExitCode 0 -Succeeded $true `
            -StandardOutput 'out' -SanitizedCommand 'git status'
        $result.PSObject.TypeNames | Should -Contain 'Lamfa.CommandResult'
        $result.Duration.TotalSeconds | Should -Be 2
        foreach ($name in 'Executable','Arguments','WorkingDirectory','StartedUtc','EndedUtc','Duration','ExitCode','Succeeded','StandardOutput','StandardError','WasCancelled','WasTimedOut','SanitizedCommand') {
            $result.PSObject.Properties.Name | Should -Contain $name
        }
    }

    It 'accepts a null exit code (process never ran)' {
        $now = [DateTime]::UtcNow
        (New-CommandResult -Executable x -WorkingDirectory 'C:\x' -StartedUtc $now -EndedUtc $now `
            -SanitizedCommand x).ExitCode | Should -BeNullOrEmpty
    }
}

Describe 'DependencyStatus' {
    It 'carries the section 10.2 contract' {
        $status = New-DependencyStatus -Name Git -Executable git -Installed $true -Version '2.55' -Supported $true -Required $true
        $status.PSObject.TypeNames | Should -Contain 'Lamfa.DependencyStatus'
        foreach ($name in 'Name','Executable','Installed','Version','Supported','Required','Capabilities','Message') {
            $status.PSObject.Properties.Name | Should -Contain $name
        }
    }
}

Describe 'RepositoryContext' {
    It 'carries the section 10.3 contract with safe defaults' {
        $context = New-RepositoryContext -Id ([guid]::NewGuid()) -Name Demo -Path 'C:\Repos\Demo'
        $context.PSObject.TypeNames | Should -Contain 'Lamfa.RepositoryContext'
        $context.WorkingTreeState | Should -Be 'Unknown'
        $context.IsGitRepository | Should -BeFalse
        foreach ($name in 'Id','Name','Path','IsGitRepository','GitDirectory','CurrentBranch','IsDetachedHead','HeadCommit','Remotes','PreferredRemote','UpstreamBranch','DefaultBranch','IntegrationBranch','WorkingTreeState','AheadCount','BehindCount','MergeInProgress','RebaseInProgress','CherryPickInProgress','RevertInProgress','Profile','Provider') {
            $context.PSObject.Properties.Name | Should -Contain $name
        }
    }
}

Describe 'OperationDefinition + OperationResult' {
    It 'rejects unknown risk levels' {
        { New-OperationDefinition -Id x -Title x -Category x -Description x -WhatItDoes x `
            -RiskLevel 'Catastrophic' -Handler {} } | Should -Throw
    }

    It 'creates a definition with the section 10.4 contract' {
        $operation = New-OperationDefinition -Id 'demo' -Title 'Demo' -Category 'Git' -Description 'd' `
            -WhatItDoes 'nothing' -RiskLevel ReadOnly -Handler { 42 }
        $operation.PSObject.TypeNames | Should -Contain 'Lamfa.OperationDefinition'
        $operation.ConfirmationMode | Should -Be 'YesNo'
    }

    It 'creates a result with the section 10.5 contract' {
        $now = [DateTime]::UtcNow
        $result = New-OperationResult -OperationId demo -StartedUtc $now -EndedUtc $now -Blocked $true -BlockReasons @('r')
        $result.PSObject.TypeNames | Should -Contain 'Lamfa.OperationResult'
        $result.Blocked | Should -BeTrue
        foreach ($name in 'OperationId','StartedUtc','EndedUtc','Succeeded','Cancelled','Blocked','BlockReasons','CommandResults','StateChanges','RecoveryInstructions','RecommendedNextActions') {
            $result.PSObject.Properties.Name | Should -Contain $name
        }
    }
}
