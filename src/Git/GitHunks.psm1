# Hunk-level staging - stage PARTS of a file, the biggest gap vs.
# GUI competitors. Hunks are parsed from 'git diff' and applied to the index
# with 'git apply --cached' fed through the runner's stdin channel.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Get-GitFileHunkList {
    <#
    .SYNOPSIS
        Parses the unstaged diff of ONE file into selectable hunk records:
        Index, Header (@@ line), Lines, Preview.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$File
    )
    $result = Invoke-ExternalCommand -Executable git -Arguments @('diff', '--no-color', '--', $File) -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: git diff failed. $($result.StandardError)" }

    $lines = $result.StandardOutput -split "`r?`n"
    $headerLines = [System.Collections.Generic.List[string]]::new()
    $hunks = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($line in $lines) {
        if ($line.StartsWith('@@')) {
            if ($current) { $hunks.Add($current) }
            $current = [pscustomobject]@{
                PSTypeName = 'Lamfa.GitHunk'
                Index      = $hunks.Count + 1
                Header     = $line
                Lines      = [System.Collections.Generic.List[string]]::new()
            }
            continue
        }
        if ($null -eq $current) { $headerLines.Add($line); continue }
        $current.Lines.Add($line)
    }
    if ($current) { $hunks.Add($current) }

    return [pscustomobject]@{
        PSTypeName  = 'Lamfa.GitFileHunks'
        File        = $File
        DiffHeader  = ($headerLines | Where-Object { $_ }) -join "`n"
        Hunks       = $hunks.ToArray()
    }
}

function Add-GitStagedHunk {
    <#
    .SYNOPSIS
        Stages ONLY the selected hunks of a file: rebuilds a patch
        from the chosen hunks and applies it to the index. Working-tree content
        is never modified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][pscustomobject]$FileHunks,
        [Parameter(Mandatory)][int[]]$HunkIndexes
    )
    $selected = @($FileHunks.Hunks | Where-Object { $_.Index -in $HunkIndexes })
    if ($selected.Count -eq 0) { throw 'ValidationError: no hunks selected.' }
    # LF-only joins: git apply rejects patches whose context lines grew a CR
    # (classic Windows AppendLine/CRLF trap).
    $patchLines = [System.Collections.Generic.List[string]]::new()
    $patchLines.Add($FileHunks.DiffHeader)
    foreach ($hunk in $selected) {
        $patchLines.Add($hunk.Header)
        foreach ($line in $hunk.Lines) { $patchLines.Add($line) }
    }
    $patchText = ($patchLines -join "`n") + "`n"
    # --recount lets git recompute line offsets after we removed sibling hunks.
    $result = Invoke-ExternalCommand -Executable git -Arguments @('apply', '--cached', '--recount', '--whitespace=nowarn', '-') `
        -WorkingDirectory $Path -StandardInput $patchText
    if (-not $result.Succeeded) { throw "ExternalCommandError: staging the selected hunks failed. $($result.StandardError)" }
}

Export-ModuleMember -Function Get-GitFileHunkList, Add-GitStagedHunk
