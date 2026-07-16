# Worktree queries + create/remove.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Get-GitWorktreeList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string]$Path)
    $result = Invoke-ExternalCommand -Executable git -Arguments @('worktree', 'list', '--porcelain') -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: $($result.StandardError)" }
    $worktrees = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($line in ($result.StandardOutput -split "`r?`n")) {
        if ($line -like 'worktree *') {
            if ($current) { $worktrees.Add($current) }
            $current = [pscustomobject]@{ PSTypeName = 'Lamfa.GitWorktree'
                Path = $line.Substring(9); Branch = $null; Commit = $null; IsBare = $false; IsPrunable = $false }
        } elseif ($null -ne $current) {
            if ($line -like 'branch *') { $current.Branch = $line.Substring(7) -replace '^refs/heads/', '' }
            elseif ($line -like 'HEAD *') { $current.Commit = $line.Substring(5) }
            elseif ($line -eq 'bare') { $current.IsBare = $true }
            elseif ($line -like 'prunable*') { $current.IsPrunable = $true }
        }
    }
    if ($current) { $worktrees.Add($current) }
    return $worktrees.ToArray()
}

function Add-GitWorktree {
    <#
    .SYNOPSIS
        Creates a linked worktree for a NEW branch (-NewBranch) or an existing
        one. The destination must not exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter()][switch]$NewBranch,
        [Parameter()][string]$SourceRef = 'HEAD'
    )
    if (Test-Path -LiteralPath $Destination) { throw "ValidationError: destination already exists: $Destination" }
    $arguments = if ($NewBranch) { @('worktree', 'add', '-b', $Branch, $Destination, $SourceRef) }
    else { @('worktree', 'add', $Destination, $Branch) }
    $result = Invoke-ExternalCommand -Executable git -Arguments $arguments -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: worktree add failed. $($result.StandardError)" }
}

function Remove-GitWorktree {
    <#
    .SYNOPSIS
        Removes a CLEAN worktree (git itself refuses dirty ones without force,
        and Lamfa never passes force).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$WorktreePath
    )
    $result = Invoke-ExternalCommand -Executable git -Arguments @('worktree', 'remove', $WorktreePath) `
        -WorkingDirectory $Path
    if ($result.ExitCode -ne 0) {
        throw "PreconditionError: worktree removal refused (it may contain local changes). $($result.StandardError)"
    }
}

Export-ModuleMember -Function Get-GitWorktreeList, Add-GitWorktree, Remove-GitWorktree
