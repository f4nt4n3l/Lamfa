# OperationDefinition + OperationResult - metadata contract for every
# user-triggered action and its execution outcome.
# Risk levels and confirmation modes are the section 13 vocabulary; the safety
# engine owns the policy that combines them.
Set-StrictMode -Version 3.0

function New-OperationDefinition {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$WhatItDoes,
        [Parameter()][AllowEmptyString()][string]$WhatItDoesNotDo = '',
        [Parameter(Mandatory)]
        [ValidateSet('ReadOnly', 'LocalChange', 'RemoteChange', 'Destructive', 'HighRisk')]
        [string]$RiskLevel,
        [Parameter()][string[]]$Preconditions = @(),
        [Parameter()][AllowEmptyString()][string]$TargetDescription = '',
        [Parameter()][AllowEmptyString()][string]$RecoveryDescription = '',
        [Parameter()][bool]$RequiresConfirmation = $true,
        [Parameter()]
        [ValidateSet('None', 'YesNo', 'TypeTargetName', 'TypeExactPhrase', 'AdvancedModeOnly', 'Disabled')]
        [string]$ConfirmationMode = 'YesNo',
        [Parameter(Mandatory)][scriptblock]$Handler
    )
    return [pscustomobject]@{
        PSTypeName           = 'Lamfa.OperationDefinition'
        Id                   = $Id
        Title                = $Title
        Category             = $Category
        Description          = $Description
        WhatItDoes           = $WhatItDoes
        WhatItDoesNotDo      = $WhatItDoesNotDo
        RiskLevel            = $RiskLevel
        Preconditions        = $Preconditions
        TargetDescription    = $TargetDescription
        RecoveryDescription  = $RecoveryDescription
        RequiresConfirmation = $RequiresConfirmation
        ConfirmationMode     = $ConfirmationMode
        Handler              = $Handler
    }
}

function New-OperationResult {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][datetime]$StartedUtc,
        [Parameter(Mandatory)][datetime]$EndedUtc,
        [Parameter()][bool]$Succeeded = $false,
        [Parameter()][bool]$Cancelled = $false,
        [Parameter()][bool]$Blocked = $false,
        [Parameter()][string[]]$BlockReasons = @(),
        [Parameter()][object[]]$CommandResults = @(),
        [Parameter()][string[]]$StateChanges = @(),
        [Parameter()][string[]]$RecoveryInstructions = @(),
        [Parameter()][string[]]$RecommendedNextActions = @()
    )
    return [pscustomobject]@{
        PSTypeName             = 'Lamfa.OperationResult'
        OperationId            = $OperationId
        StartedUtc             = $StartedUtc
        EndedUtc               = $EndedUtc
        Succeeded              = $Succeeded
        Cancelled              = $Cancelled
        Blocked                = $Blocked
        BlockReasons           = $BlockReasons
        CommandResults         = $CommandResults
        StateChanges           = $StateChanges
        RecoveryInstructions   = $RecoveryInstructions
        RecommendedNextActions = $RecommendedNextActions
    }
}

Export-ModuleMember -Function New-OperationDefinition, New-OperationResult
