# Operation engine tests - the section 12 lifecycle, including the
# A read-only sample operation must complete end to end.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Models/OperationDefinition.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Models/RepositoryContext.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Core/CommandRunner.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Core/OperationEngine.psm1') -Force -DisableNameChecking
    $script:workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("lamfa-engine-" + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $script:workDir
}
AfterAll {
    Remove-Item -Path $script:workDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Lamfa-InvokeOperation' {
    It 'completes a read-only sample operation end to end' {
        $operation = New-OperationDefinition -Id 'sample.echo' -Title 'Echo sample' -Category 'Diagnostics' `
            -Description 'Runs one harmless external command.' -WhatItDoes 'Prints hello via pwsh.' `
            -RiskLevel ReadOnly -RequiresConfirmation $false `
            -Preconditions @('RepositorySelected', 'RepositoryPathExists') `
            -Handler {
                param($Context, $Parameters)
                Invoke-ExternalCommand -Executable pwsh -Arguments @('-NoProfile', '-Command', 'Write-Output hello') `
                    -WorkingDirectory $Context.Path
            }
        $context = New-RepositoryContext -Id x -Name Demo -Path $script:workDir
        $result = Lamfa-InvokeOperation -Operation $operation -Context $context -Quiet
        $result.Succeeded | Should -BeTrue
        $result.Blocked | Should -BeFalse
        $result.CommandResults.Count | Should -Be 1
        $result.CommandResults[0].StandardOutput.Trim() | Should -Be 'hello'
    }

    It 'blocks when a precondition fails and reports remediation' {
        $operation = New-OperationDefinition -Id 'blocked.op' -Title 'Needs repo' -Category T -Description d `
            -WhatItDoes w -RiskLevel ReadOnly -RequiresConfirmation $false `
            -Preconditions @('RepositorySelected') -Handler { throw 'handler must not run' }
        $result = Lamfa-InvokeOperation -Operation $operation -Context $null -Quiet
        $result.Blocked | Should -BeTrue
        $result.BlockReasons.Count | Should -BeGreaterThan 0
        $result.RecoveryInstructions.Count | Should -BeGreaterThan 0
    }

    It 'blocks HighRisk operations in Beginner Mode before preconditions or handler' {
        $operation = New-OperationDefinition -Id 'danger.op' -Title 'Force push' -Category Git -Description d `
            -WhatItDoes w -RiskLevel HighRisk -Handler { throw 'handler must not run' }
        $result = Lamfa-InvokeOperation -Operation $operation -BeginnerMode $true -Quiet
        $result.Blocked | Should -BeTrue
        $result.BlockReasons[0] | Should -Match 'Beginner Mode'
    }

    It 'returns Cancelled when the user declines the confirmation' {
        $operation = New-OperationDefinition -Id 'confirm.op' -Title 'Change' -Category T -Description d `
            -WhatItDoes w -RiskLevel LocalChange -Handler { throw 'handler must not run' }
        $result = Lamfa-InvokeOperation -Operation $operation -Prompter { param($p) 'n' } -Quiet
        $result.Cancelled | Should -BeTrue
        $result.Succeeded | Should -BeFalse
    }

    It 'runs the handler after a positive confirmation' {
        $operation = New-OperationDefinition -Id 'confirm.yes' -Title 'Change' -Category T -Description d `
            -WhatItDoes w -RiskLevel LocalChange -Handler { param($Context, $Parameters) 'state changed' }
        $result = Lamfa-InvokeOperation -Operation $operation -Prompter { param($p) 'y' } -Quiet
        $result.Succeeded | Should -BeTrue
        $result.StateChanges | Should -Contain 'state changed'
    }

    It 'contains handler exceptions as a failed result with recovery text - never throws' {
        $operation = New-OperationDefinition -Id 'boom.op' -Title 'Boom' -Category T -Description d `
            -WhatItDoes w -RiskLevel ReadOnly -RequiresConfirmation $false -Handler { throw 'kaboom' }
        $result = $null
        { $script:result = Lamfa-InvokeOperation -Operation $operation -Quiet } | Should -Not -Throw
        $script:result.Succeeded | Should -BeFalse
        ($script:result.RecoveryInstructions -join ' ') | Should -Match 'kaboom'
    }

    It 'marks the operation failed when an embedded CommandResult failed' {
        $operation = New-OperationDefinition -Id 'cmdfail.op' -Title 'Cmd fail' -Category T -Description d `
            -WhatItDoes w -RiskLevel ReadOnly -RequiresConfirmation $false `
            -Handler {
                param($Context, $Parameters)
                Invoke-ExternalCommand -Executable pwsh -Arguments @('-NoProfile', '-Command', 'exit 9') `
                    -WorkingDirectory ([System.IO.Path]::GetTempPath())
            }
        $result = Lamfa-InvokeOperation -Operation $operation -Quiet
        $result.Succeeded | Should -BeFalse
        ($result.RecoveryInstructions -join ' ') | Should -Match 'External command failed'
    }
}
