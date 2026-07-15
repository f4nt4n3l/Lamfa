# Repository discovery - scans workspace roots for Git repositories.
# Depth-limited, skips reparse points and protected folders, returns a preview;
# registration is a separate explicit step.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'RepositoryValidation.psm1') -DisableNameChecking

function Lamfa-FindRepository {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter()][ValidateRange(1, 10)][int]$MaxDepth = 3
    )
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "ValidationError: scan root does not exist: $Root"
    }
    $found = [System.Collections.Generic.List[object]]::new()
    $skipNames = @('$Recycle.Bin', 'System Volume Information', 'Windows', 'Program Files', 'Program Files (x86)', 'node_modules')

    function ScanFolder([string]$Folder, [int]$Depth) {
        # .git may be a directory (normal clone) or a file (linked worktree).
        if (Test-Path -LiteralPath (Join-Path $Folder '.git')) {
            $found.Add([pscustomobject]@{
                PSTypeName = 'Lamfa.DiscoveredRepository'
                Name       = Split-Path -Path $Folder -Leaf
                Path       = Get-NormalizedPath $Folder
            })
            return  # do not descend into a repository looking for nested ones
        }
        if ($Depth -ge $MaxDepth) { return }
        $children = Get-ChildItem -LiteralPath $Folder -Directory -Force -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            if ($child.Name -in $skipNames) { continue }
            if ($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            ScanFolder $child.FullName ($Depth + 1)
        }
    }
    ScanFolder (Get-NormalizedPath $Root) 0
    return $found.ToArray()
}

Export-ModuleMember -Function Lamfa-FindRepository
