# Safety and confirmation policy tests - proves the section 13 matrix.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Models/OperationDefinition.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Core/Safety.psm1') -Force

    function New-TestOperation {
        param([string]$Risk, [string]$Mode = 'YesNo', [bool]$ConfirmationRequired = $true)
        New-OperationDefinition -Id t -Title 'Test op' -Category T -Description d -WhatItDoes w `
            -RiskLevel $Risk -ConfirmationMode $Mode -RequiresConfirmation $ConfirmationRequired -Handler {}
    }
}

Describe 'Lamfa-GetSafetyDecision' {
    It 'blocks HighRisk operations in Beginner Mode - confirmation cannot override' {
        $decision = Lamfa-GetSafetyDecision -Operation (New-TestOperation -Risk HighRisk) -BeginnerMode $true
        $decision.Allowed | Should -BeFalse
        $decision.Reason | Should -Match 'Beginner Mode'
    }

    It 'allows HighRisk operations in Advanced Mode' {
        (Lamfa-GetSafetyDecision -Operation (New-TestOperation -Risk HighRisk) -BeginnerMode $false).Allowed |
            Should -BeTrue
    }

    It 'escalates Destructive operations to a typed confirmation even when defined weaker' {
        $decision = Lamfa-GetSafetyDecision -Operation (New-TestOperation -Risk Destructive -Mode YesNo)
        $decision.Allowed | Should -BeTrue
        $decision.ConfirmationMode | Should -Be 'TypeTargetName'
    }

    It 'lets a ReadOnly operation without RequiresConfirmation run unprompted' {
        (Lamfa-GetSafetyDecision -Operation (New-TestOperation -Risk ReadOnly -ConfirmationRequired $false)).ConfirmationMode |
            Should -Be 'None'
    }

    It 'blocks AdvancedModeOnly operations in Beginner Mode' {
        (Lamfa-GetSafetyDecision -Operation (New-TestOperation -Risk LocalChange -Mode AdvancedModeOnly) -BeginnerMode $true).Allowed |
            Should -BeFalse
    }

    It 'blocks Disabled operations in every mode' {
        (Lamfa-GetSafetyDecision -Operation (New-TestOperation -Risk ReadOnly -Mode Disabled) -BeginnerMode $false).Allowed |
            Should -BeFalse
    }
}

Describe 'Lamfa-RequestConfirmation' {
    It 'YesNo accepts y and rejects anything else' {
        Lamfa-RequestConfirmation -ConfirmationMode YesNo -Prompter { param($p) 'y' } | Should -BeTrue
        Lamfa-RequestConfirmation -ConfirmationMode YesNo -Prompter { param($p) 'n' } | Should -BeFalse
        Lamfa-RequestConfirmation -ConfirmationMode YesNo -Prompter { param($p) '' } | Should -BeFalse
    }

    It 'TypeTargetName requires the exact, case-sensitive target' {
        Lamfa-RequestConfirmation -ConfirmationMode TypeTargetName -TargetName 'feature/x' -Prompter { param($p) 'feature/x' } | Should -BeTrue
        Lamfa-RequestConfirmation -ConfirmationMode TypeTargetName -TargetName 'feature/x' -Prompter { param($p) 'FEATURE/X' } | Should -BeFalse
        Lamfa-RequestConfirmation -ConfirmationMode TypeTargetName -TargetName 'feature/x' -Prompter { param($p) 'y' } | Should -BeFalse
    }

    It 'TypeTargetName fails closed when no target name was provided' {
        Lamfa-RequestConfirmation -ConfirmationMode TypeTargetName -Prompter { param($p) '' } | Should -BeFalse
    }

    It 'TypeExactPhrase requires the exact phrase' {
        Lamfa-RequestConfirmation -ConfirmationMode TypeExactPhrase -ExactPhrase 'delete everything' -Prompter { param($p) 'delete everything' } | Should -BeTrue
        Lamfa-RequestConfirmation -ConfirmationMode TypeExactPhrase -ExactPhrase 'delete everything' -Prompter { param($p) 'delete' } | Should -BeFalse
    }

    It 'None returns true without prompting' {
        Lamfa-RequestConfirmation -ConfirmationMode None -Prompter { param($p) throw 'must not prompt' } | Should -BeTrue
    }
}
