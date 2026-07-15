# ConsoleRenderer - console output helpers. All output must stay understandable
# without color, so color is decoration only, never meaning.
Set-StrictMode -Version 3.0

# When PwshSpectreConsole is installed the renderer
# upgrades headers/messages to Spectre panels; otherwise the classic output
# below runs unchanged. Detection happens once per import.
$script:UseSpectre = $false
if (Get-Module -ListAvailable -Name PwshSpectreConsole -ErrorAction SilentlyContinue) {
    try {
        Import-Module PwshSpectreConsole -DisableNameChecking -ErrorAction Stop
        $script:UseSpectre = $true
    } catch { $script:UseSpectre = $false }
}

function Lamfa-WriteHeader {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)
    if ($script:UseSpectre) {
        Format-SpectrePanel -Data $Text -Border Rounded -Color Cyan1 | Out-SpectreHost
        return
    }
    $line = '=' * 56
    Write-Host ''
    Write-Host $line -ForegroundColor Cyan
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
}

function Lamfa-WriteKeyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter()][AllowEmptyString()][AllowNull()][string]$Value
    )
    Write-Host ('   {0,-12}: {1}' -f $Key, $Value)
}

function Lamfa-WriteMessage {
    [CmdletBinding()]
    param(
        [Parameter()][ValidateSet('Info', 'Success', 'Warning', 'Error')][string]$Level = 'Info',
        [Parameter(Mandatory)][string]$Text
    )
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'Gray' }
    }
    Write-Host " [$Level] $Text" -ForegroundColor $color
}

function Lamfa-WriteActionPreview {
    <#
    .SYNOPSIS
        Renders the standard pre-execution explanation for an operation
       : what it does, what it does not do, precondition
        results, exact target, and recovery.
    .PARAMETER PreconditionResults
        Records from Lamfa-TestPrecondition; rendered as [ok]/[!!] lines.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Operation,
        [Parameter()][object[]]$PreconditionResults = @()
    )
    Write-Host ''
    Write-Host 'ACTION' -ForegroundColor White
    Write-Host " $($Operation.Title)"
    Write-Host ''
    Write-Host 'WHAT THIS DOES' -ForegroundColor White
    Write-Host " $($Operation.WhatItDoes)"
    if (-not [string]::IsNullOrWhiteSpace($Operation.WhatItDoesNotDo)) {
        Write-Host ''
        Write-Host 'WHAT THIS DOES NOT DO' -ForegroundColor White
        Write-Host " $($Operation.WhatItDoesNotDo)"
    }
    if ($PreconditionResults.Count -gt 0) {
        Write-Host ''
        Write-Host 'PRECONDITIONS' -ForegroundColor White
        foreach ($result in $PreconditionResults) {
            if ($result.Passed) {
                Write-Host " [ok] $($result.Description)" -ForegroundColor Green
            } else {
                Write-Host " [!!] $($result.Description)" -ForegroundColor Red
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Operation.TargetDescription)) {
        Write-Host ''
        Write-Host 'TARGET' -ForegroundColor White
        Write-Host " $($Operation.TargetDescription)"
    }
    if (-not [string]::IsNullOrWhiteSpace($Operation.RecoveryDescription)) {
        Write-Host ''
        Write-Host 'RECOVERY' -ForegroundColor White
        Write-Host " $($Operation.RecoveryDescription)"
    }
    Write-Host ''
}

function Lamfa-WriteBlocked {
    <#
    .SYNOPSIS
        Renders the standard BLOCKED screen: reason, why it
        matters, and the safe next action for every failed prerequisite.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$FailedPreconditions)
    Write-Host ''
    Write-Host 'BLOCKED' -ForegroundColor Red
    foreach ($failure in $FailedPreconditions) {
        Write-Host ''
        Write-Host ' Reason:' -ForegroundColor White
        Write-Host "   $($failure.Description)"
        Write-Host ' Why this matters:' -ForegroundColor White
        Write-Host "   $($failure.WhyItMatters)"
        Write-Host ' Safe next action:' -ForegroundColor White
        Write-Host "   $($failure.SafeNextAction)"
    }
    Write-Host ''
}


function Lamfa-ReadMenuKey {
    <#
    .SYNOPSIS
        Single-keypress menu input: no Enter needed, Escape
        acts as back ('0'). Falls back to Read-Host when input is redirected
        (tests, dumb terminals) - behavior then equals the classic prompt.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()][string[]]$Breadcrumb = @(),
        [Parameter()][string]$Prompt = 'Choose'
    )
    if ($Breadcrumb.Count -gt 0) {
        Write-Host (' ' + ($Breadcrumb -join ' > ')) -ForegroundColor DarkCyan
    }
    if ([Console]::IsInputRedirected) { return (Read-Host $Prompt) }
    Write-Host "${Prompt}: " -NoNewline
    $key = [Console]::ReadKey($true)
    if ($key.Key -eq [ConsoleKey]::Escape) { Write-Host '(back)'; return '0' }
    Write-Host ([string]$key.KeyChar)
    return [string]$key.KeyChar
}

function Lamfa-SelectMenuChoice {
    <#
    .SYNOPSIS
        Arrow-key menu selector. Up/Down move the highlight,
        Enter selects, a direct hotkey selects immediately, Escape/0 goes back
        ($null), '?' shows the highlighted item's help. Plain-terminal fallback:
        numbered list + Read-Host (same contract).
    .PARAMETER Items
        Objects/hashtables with Key (hotkey string), Label, optional Help.
    .PARAMETER Reader
        Injectable plain-mode input for tests.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter()][string]$Title = '',
        [Parameter()][string[]]$Breadcrumb = @(),
        [Parameter()][switch]$ForcePlain,
        [Parameter()][scriptblock]$Reader = { param($PromptText) Read-Host -Prompt $PromptText }
    )
    if ($Breadcrumb.Count -gt 0) {
        Write-Host (' ' + ($Breadcrumb -join ' > ')) -ForegroundColor DarkCyan
    }
    if ($Title) { Write-Host $Title -ForegroundColor Cyan }

    $plain = $ForcePlain.IsPresent -or [Console]::IsInputRedirected
    if ($plain) {
        foreach ($item in $Items) { Write-Host ("  {0,3}. {1}" -f $item.Key, $item.Label) }
        Write-Host '    0. Back'
        while ($true) {
            $answer = [string](& $Reader 'Choose')
            if ($answer -eq '0' -or [string]::IsNullOrEmpty($answer)) { return $null }
            $match = $Items | Where-Object { [string]$_.Key -ieq $answer } | Select-Object -First 1
            if ($match) { return $match }
            Lamfa-WriteMessage -Level Warning -Text "Unknown option '$answer'."
        }
    }

    $index = 0
    $rendered = $false
    while ($true) {
        if ($rendered) { Write-Host ("`e[{0}A" -f ($Items.Count + 1)) -NoNewline }
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $marker = if ($i -eq $index) { '>' } else { ' ' }
            $color = if ($i -eq $index) { 'Cyan' } else { 'Gray' }
            Write-Host ("`e[2K {0} {1,3}. {2}" -f $marker, $Items[$i].Key, $Items[$i].Label) -ForegroundColor $color
        }
        Write-Host "`e[2K   Enter=select  Esc/0=back  ?=help" -ForegroundColor DarkGray
        $rendered = $true
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { $index = ($index - 1 + $Items.Count) % $Items.Count }
            'DownArrow' { $index = ($index + 1) % $Items.Count }
            'Enter'     { return $Items[$index] }
            'Escape'    { return $null }
            default {
                $char = [string]$key.KeyChar
                if ($char -eq '0') { return $null }
                if ($char -eq '?') {
                    $helpProperty = $Items[$index].PSObject.Properties['Help']
                    $helpText = if ($helpProperty -and $helpProperty.Value) { $helpProperty.Value } else { 'No help recorded for this action.' }
                    Write-Host ("`e[2K [?] {0}" -f $helpText) -ForegroundColor Yellow
                    $rendered = $false
                    continue
                }
                $match = $Items | Where-Object { [string]$_.Key -ieq $char } | Select-Object -First 1
                if ($match) { return $match }
            }
        }
    }
}

Export-ModuleMember -Function Lamfa-WriteHeader, Lamfa-WriteKeyValue, Lamfa-WriteMessage, Lamfa-WriteActionPreview, Lamfa-WriteBlocked, Lamfa-ReadMenuKey, Lamfa-SelectMenuChoice
