@{
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # The console renderer IS the UI: Write-Host is the intended mechanism
        # for colored interactive output.
        'PSAvoidUsingWriteHost',
        # Lamfa routes ALL confirmations through the Safety engine and
        # the operation engine lifecycle - not through ShouldProcess. The
        # New-* model factories create in-memory objects and change no system state.
        'PSUseShouldProcessForStateChangingFunctions',
        # Precondition tests, operation handlers, and prompters are CALLBACK
        # CONTRACTS: every scriptblock receives the full signature (Context,
        # Parameters / PromptText) even when a specific callback ignores part of it.
        'PSReviewUnusedParameter',
        # Owner convention: every Lamfa-owned function is brand-first
        # (Lamfa-GetConfiguration, Lamfa-IsWindows) - deliberate, consistent, and
        # documented; the approved-verb rule cannot express it.
        'PSUseApprovedVerbs'
    )
}
