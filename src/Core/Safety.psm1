# Safety and confirmation engine - applies the risk/confirmation
# policy matrix. Policy evaluation is pure and fully
# testable; the interactive prompt lives in Lamfa-RequestConfirmation and is
# injectable so the operation engine can be tested without a console.
Set-StrictMode -Version 3.0

function Lamfa-GetSafetyDecision {
    <#
    .SYNOPSIS
        Decides whether an operation may proceed in the current mode and which
        confirmation it requires. Never prompts.
    .OUTPUTS
        @{ Allowed(bool); ConfirmationMode(string); Reason(string) }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Operation,
        [Parameter()][bool]$BeginnerMode = $true
    )

    # HighRisk is hidden outright in Beginner Mode (section 13.3); a confirmation
    # can never override this (section 6.7).
    if ($BeginnerMode -and $Operation.RiskLevel -eq 'HighRisk') {
        return [pscustomobject]@{
            Allowed          = $false
            ConfirmationMode = 'Disabled'
            Reason           = "'$($Operation.Title)' is a high-risk operation and is not available in Beginner Mode. Switch to Advanced Mode in Settings if you fully understand the consequences."
        }
    }
    if ($Operation.ConfirmationMode -eq 'AdvancedModeOnly' -and $BeginnerMode) {
        return [pscustomobject]@{
            Allowed          = $false
            ConfirmationMode = 'Disabled'
            Reason           = "'$($Operation.Title)' is only available in Advanced Mode."
        }
    }
    if ($Operation.ConfirmationMode -eq 'Disabled') {
        return [pscustomobject]@{
            Allowed          = $false
            ConfirmationMode = 'Disabled'
            Reason           = "'$($Operation.Title)' is disabled."
        }
    }

    # Destructive operations always confirm by typing the exact target, even when
    # the definition asked for something weaker - policy beats definition.
    $mode = $Operation.ConfirmationMode
    if ($Operation.RiskLevel -eq 'Destructive' -and $mode -notin @('TypeTargetName', 'TypeExactPhrase')) {
        $mode = 'TypeTargetName'
    }
    if (-not $Operation.RequiresConfirmation -and $Operation.RiskLevel -eq 'ReadOnly') {
        $mode = 'None'
    }

    return [pscustomobject]@{
        Allowed          = $true
        ConfirmationMode = $mode
        Reason           = ''
    }
}

function Lamfa-RequestConfirmation {
    <#
    .SYNOPSIS
        Performs the interactive confirmation for a mode decided by
        Lamfa-GetSafetyDecision. Returns $true only on an exact affirmative.
    .PARAMETER TargetName
        The value the user must retype for TypeTargetName (e.g. a branch name).
    .PARAMETER ExactPhrase
        The phrase the user must retype for TypeExactPhrase.
    .PARAMETER Prompter
        Injectable input source for tests. Receives the prompt text, returns the
        user's answer. Defaults to Read-Host.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('None', 'YesNo', 'TypeTargetName', 'TypeExactPhrase')]
        [string]$ConfirmationMode,
        [Parameter()][AllowEmptyString()][string]$TargetName = '',
        [Parameter()][AllowEmptyString()][string]$ExactPhrase = '',
        [Parameter()][scriptblock]$Prompter = { param($PromptText) Read-Host -Prompt $PromptText }
    )

    switch ($ConfirmationMode) {
        'None' { return $true }
        'YesNo' {
            $answer = [string](& $Prompter 'Continue? Type y to proceed, anything else cancels')
            return $answer -match '^(y|yes)$'
        }
        'TypeTargetName' {
            if ([string]::IsNullOrWhiteSpace($TargetName)) { return $false }
            $answer = [string](& $Prompter "Type the exact target name '$TargetName' to proceed")
            return $answer -ceq $TargetName
        }
        'TypeExactPhrase' {
            if ([string]::IsNullOrWhiteSpace($ExactPhrase)) { return $false }
            $answer = [string](& $Prompter "Type exactly '$ExactPhrase' to proceed")
            return $answer -ceq $ExactPhrase
        }
    }
    return $false
}

Export-ModuleMember -Function Lamfa-GetSafetyDecision, Lamfa-RequestConfirmation
