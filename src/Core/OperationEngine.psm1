# Operation engine - the mandatory lifecycle for every user-triggered
# action: resolve context -> preconditions -> block or
# explain -> confirm -> execute -> log -> result. Menu handlers must never
# bypass this for state-changing actions.
Set-StrictMode -Version 3.0

Import-Module -Name (Join-Path $PSScriptRoot 'Logging.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'Preconditions.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'Safety.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Models/OperationDefinition.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../UI/ConsoleRenderer.psm1') -DisableNameChecking

function Lamfa-InvokeOperation {
    <#
    .SYNOPSIS
        Runs one operation through the full engine lifecycle and returns an
        OperationResult. Handler exceptions are contained (section 26): they
        produce a failed result, never an application crash.
    .PARAMETER Context
        The active RepositoryContext (or $null for repository-independent actions).
    .PARAMETER Parameters
        Operation-specific values, passed to preconditions and the handler.
    .PARAMETER Prompter
        Injectable confirmation input for tests; see Lamfa-RequestConfirmation.
    .PARAMETER Quiet
        Suppresses the action preview rendering (used by tests and read-only
        dashboard refreshes; state-changing menu flows keep it on).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Operation,
        [Parameter()][AllowNull()][object]$Context = $null,
        [Parameter()][hashtable]$Parameters = @{},
        [Parameter()][bool]$BeginnerMode = $true,
        [Parameter()][AllowEmptyString()][string]$ConfirmationTargetName = '',
        [Parameter()][AllowEmptyString()][string]$ConfirmationExactPhrase = '',
        [Parameter()][scriptblock]$Prompter = { param($PromptText) Read-Host -Prompt $PromptText },
        [Parameter()][switch]$Quiet
    )

    $startedUtc = [DateTime]::UtcNow

    # 1-2. Safety policy: is this operation even available in the current mode?
    $decision = Lamfa-GetSafetyDecision -Operation $Operation -BeginnerMode $BeginnerMode
    if (-not $decision.Allowed) {
        if (-not $Quiet) { Lamfa-WriteMessage -Level Warning -Text $decision.Reason }
        Lamfa-WriteLog -Level Warning -Message 'operation blocked by safety policy' -Data @{ operationId = $Operation.Id; reason = $decision.Reason }
        return New-OperationResult -OperationId $Operation.Id -StartedUtc $startedUtc -EndedUtc ([DateTime]::UtcNow) `
            -Blocked $true -BlockReasons @($decision.Reason)
    }

    # 3-4. Preconditions: any failure blocks; a confirmation cannot override (6.7).
    $preconditionResults = @()
    if ($Operation.Preconditions.Count -gt 0) {
        $preconditionResults = Lamfa-TestPrecondition -Names $Operation.Preconditions -Context $Context -Parameters $Parameters
        $failed = @($preconditionResults | Where-Object { -not $_.Passed })
        if ($failed.Count -gt 0) {
            if (-not $Quiet) { Lamfa-WriteBlocked -FailedPreconditions $failed }
            $reasons = @($failed | ForEach-Object { $_.Description })
            Lamfa-WriteLog -Level Warning -Message 'operation blocked by preconditions' -Data @{ operationId = $Operation.Id; reasons = ($reasons -join '; ') }
            return New-OperationResult -OperationId $Operation.Id -StartedUtc $startedUtc -EndedUtc ([DateTime]::UtcNow) `
                -Blocked $true -BlockReasons $reasons `
                -RecoveryInstructions @($failed | ForEach-Object { $_.SafeNextAction })
        }
    }

    # 5-6. Explain the action and its exact targets before anything happens.
    if (-not $Quiet) { Lamfa-WriteActionPreview -Operation $Operation -PreconditionResults $preconditionResults }

    # 7. Confirmation.
    if ($decision.ConfirmationMode -ne 'None') {
        $confirmed = Lamfa-RequestConfirmation -ConfirmationMode $decision.ConfirmationMode `
            -TargetName $ConfirmationTargetName -ExactPhrase $ConfirmationExactPhrase -Prompter $Prompter
        if (-not $confirmed) {
            if (-not $Quiet) { Lamfa-WriteMessage -Level Info -Text 'Cancelled. Nothing was changed.' }
            Lamfa-WriteLog -Level Info -Message 'operation cancelled by user' -Data @{ operationId = $Operation.Id }
            return New-OperationResult -OperationId $Operation.Id -StartedUtc $startedUtc -EndedUtc ([DateTime]::UtcNow) -Cancelled $true
        }
    }

    # 8-9. Execute the handler; contain any exception (section 26).
    $handlerOutput = $null
    $succeeded = $false
    $recovery = @()
    try {
        $handlerOutput = & $Operation.Handler $Context $Parameters
        $succeeded = $true
    } catch {
        $recovery = @("The operation failed: $($_.Exception.Message)", 'Check the log file for details; no further steps were executed.')
        if (-not $Quiet) { Lamfa-WriteMessage -Level Error -Text $recovery[0] }
    }

    # 10-13. Collect results, log sanitized details, report.
    $commandResults = @()
    $stateChanges = @()
    if ($null -ne $handlerOutput) {
        foreach ($item in @($handlerOutput)) {
            if ($item -is [pscustomobject] -and $item.PSObject.TypeNames -contains 'Lamfa.CommandResult') {
                $commandResults += $item
                if (-not $item.Succeeded) {
                    $succeeded = $false
                    $recovery += "External command failed: $($item.SanitizedCommand)"
                }
            } elseif ($item -is [string]) {
                $stateChanges += $item
            }
        }
    }

    Lamfa-WriteLog -Level ($(if ($succeeded) { 'Info' } else { 'Warning' })) -Message 'operation finished' -Data @{
        operationId = $Operation.Id
        succeeded   = $succeeded
        durationMs  = [int]([DateTime]::UtcNow - $startedUtc).TotalMilliseconds
    }

    return New-OperationResult -OperationId $Operation.Id -StartedUtc $startedUtc -EndedUtc ([DateTime]::UtcNow) `
        -Succeeded $succeeded -CommandResults $commandResults -StateChanges $stateChanges -RecoveryInstructions $recovery
}

Export-ModuleMember -Function Lamfa-InvokeOperation
