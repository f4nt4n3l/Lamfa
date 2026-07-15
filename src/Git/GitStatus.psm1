# Porcelain v2 status parser. Machine-readable, locale-proof,
# NUL-delimited so paths with spaces and Unicode survive intact.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Get-GitStatus {
    <#
    .SYNOPSIS
        Parses 'git status --porcelain=v2 --branch -z': branch, upstream,
        ahead/behind, and one entry per changed/untracked/conflicted path.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][switch]$IncludeIgnored
    )

    $arguments = @('status', '--porcelain=v2', '--branch', '-z')
    if ($IncludeIgnored) { $arguments += '--ignored=matching' }
    $result = Invoke-ExternalCommand -Executable git -Arguments $arguments -WorkingDirectory $Path
    if (-not $result.Succeeded) {
        throw "ExternalCommandError: git status failed. $($result.StandardError)"
    }

    $branch = $null; $upstream = $null; $ahead = $null; $behind = $null
    $entries = [System.Collections.Generic.List[object]]::new()

    # -z terminates every record with NUL; rename records ('2') carry the ORIGINAL
    # path as an extra NUL-separated token after the record.
    $tokens = $result.StandardOutput -split "`0" | Where-Object { $_ -ne '' }
    $index = 0
    while ($index -lt $tokens.Count) {
        $record = $tokens[$index]; $index++
        if ($record.StartsWith('# branch.head ')) { $value = $record.Substring(14); if ($value -ne '(detached)') { $branch = $value }; continue }
        if ($record.StartsWith('# branch.upstream ')) { $upstream = $record.Substring(18); continue }
        if ($record.StartsWith('# branch.ab ')) {
            if ($record -match '\+(\d+) -(\d+)') { $ahead = [int]$Matches[1]; $behind = [int]$Matches[2] }
            continue
        }
        if ($record.StartsWith('# ')) { continue }

        $kind = $record.Substring(0, 1)
        switch ($kind) {
            '1' {
                # 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
                $parts = $record.Split(' ', 9)
                $entries.Add([pscustomobject]@{
                    PSTypeName = 'Lamfa.GitStatusEntry'; Kind = 'Changed'
                    IndexState = $parts[1][0]; WorktreeState = $parts[1][1]
                    Path = $parts[8]; OriginalPath = $null
                })
            }
            '2' {
                # 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>  NUL  <origPath>
                $parts = $record.Split(' ', 10)
                $original = if ($index -lt $tokens.Count) { $tokens[$index] } else { $null }
                $index++
                $entries.Add([pscustomobject]@{
                    PSTypeName = 'Lamfa.GitStatusEntry'; Kind = 'Renamed'
                    IndexState = $parts[1][0]; WorktreeState = $parts[1][1]
                    Path = $parts[9]; OriginalPath = $original
                })
            }
            'u' {
                $parts = $record.Split(' ', 11)
                $entries.Add([pscustomobject]@{
                    PSTypeName = 'Lamfa.GitStatusEntry'; Kind = 'Conflicted'
                    IndexState = $parts[1][0]; WorktreeState = $parts[1][1]
                    Path = $parts[10]; OriginalPath = $null
                })
            }
            '?' {
                $entries.Add([pscustomobject]@{
                    PSTypeName = 'Lamfa.GitStatusEntry'; Kind = 'Untracked'
                    IndexState = '?'; WorktreeState = '?'
                    Path = $record.Substring(2); OriginalPath = $null
                })
            }
            '!' {
                $entries.Add([pscustomobject]@{
                    PSTypeName = 'Lamfa.GitStatusEntry'; Kind = 'Ignored'
                    IndexState = '!'; WorktreeState = '!'
                    Path = $record.Substring(2); OriginalPath = $null
                })
            }
        }
    }

    return [pscustomobject]@{
        PSTypeName   = 'Lamfa.GitStatus'
        Branch       = $branch
        Upstream     = $upstream
        Ahead        = $ahead
        Behind       = $behind
        Entries      = $entries.ToArray()
        HasConflicts = [bool]($entries | Where-Object Kind -eq 'Conflicted')
        HasStaged    = [bool]($entries | Where-Object { $_.IndexState -notin @('.', '?', '!') })
        HasUntracked = [bool]($entries | Where-Object Kind -eq 'Untracked')
        IsClean      = ($entries.Count -eq 0)
    }
}

Export-ModuleMember -Function Get-GitStatus
