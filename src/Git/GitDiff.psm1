# Diff services. Thin, read-only wrappers over git diff.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Get-GitDiff {
    <#
    .SYNOPSIS
        Returns diff text for the requested scope: Unstaged (default), Staged,
        Upstream, or between two explicit refs. -NameOnly / -Stat summarize.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][ValidateSet('Unstaged', 'Staged', 'Upstream', 'Refs')][string]$Scope = 'Unstaged',
        [Parameter()][AllowEmptyString()][string]$FromRef = '',
        [Parameter()][AllowEmptyString()][string]$ToRef = '',
        [Parameter()][AllowEmptyString()][string]$File = '',
        [Parameter()][switch]$NameOnly,
        [Parameter()][switch]$Stat
    )
    $arguments = @('diff')
    switch ($Scope) {
        'Staged'   { $arguments += '--cached' }
        'Upstream' { $arguments += '@{upstream}...HEAD' }
        'Refs'     {
            if (-not $FromRef -or -not $ToRef) { throw 'ValidationError: Refs scope needs -FromRef and -ToRef.' }
            $arguments += "$FromRef..$ToRef"
        }
    }
    if ($NameOnly) { $arguments += '--name-only' }
    if ($Stat) { $arguments += '--stat' }
    if ($File) { $arguments += @('--', $File) }
    $result = Invoke-ExternalCommand -Executable git -Arguments $arguments -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: git diff failed. $($result.StandardError)" }
    return $result.StandardOutput
}

Export-ModuleMember -Function Get-GitDiff
