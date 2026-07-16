# Stash queries + create/apply/pop.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Get-GitStashList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string]$Path)
    $result = Invoke-ExternalCommand -Executable git `
        -Arguments @('stash', 'list', '--format=%gd%x1f%s') -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: $($result.StandardError)" }
    $stashes = foreach ($line in ($result.StandardOutput -split "`r?`n" | Where-Object { $_ })) {
        $parts = $line -split "`u{1f}"
        [pscustomobject]@{ PSTypeName = 'Lamfa.GitStash'; Ref = $parts[0]; Description = $parts[1] }
    }
    return @($stashes)
}

function Add-GitStash {
    <#
    .SYNOPSIS
        Creates a NAMED stash. Untracked files are included only via
        the explicit switch - silent loss of new files is the classic stash trap.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][switch]$IncludeUntracked
    )
    $arguments = @('stash', 'push', '-m', $Message)
    if ($IncludeUntracked) { $arguments += '--include-untracked' }
    $result = Invoke-ExternalCommand -Executable git -Arguments $arguments -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: stash failed. $($result.StandardError)" }
}

function Use-GitStash {
    <#
    .SYNOPSIS
        Applies (keeps the stash) or pops (drops on success) one stash entry
       . A conflicted apply keeps the stash and reports guidance.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string]$Ref = 'stash@{0}',
        [Parameter()][ValidateSet('Apply', 'Pop')][string]$Mode = 'Apply'
    )
    $result = Invoke-ExternalCommand -Executable git -Arguments @('stash', $Mode.ToLowerInvariant(), $Ref) `
        -WorkingDirectory $Path
    if ($result.ExitCode -eq 0) {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.GitStashResult'; Outcome = 'Applied'; Detail = '' }
    }
    if (($result.StandardError + $result.StandardOutput) -match 'conflict') {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.GitStashResult'; Outcome = 'Conflicted'
            Detail = 'The stash conflicts with current changes. Resolve the conflicts, then drop the stash manually - it was NOT deleted.' }
    }
    return [pscustomobject]@{ PSTypeName = 'Lamfa.GitStashResult'; Outcome = 'Failed'; Detail = $result.StandardError }
}

Export-ModuleMember -Function Get-GitStashList, Add-GitStash, Use-GitStash
