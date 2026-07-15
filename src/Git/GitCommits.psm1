# Selective staging + commit engine.
# 'git add -A' is deliberately impossible through this module: staging always
# takes an explicit file list (plan 17.7).
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Logging.psm1') -DisableNameChecking

function Add-GitStagedFile {
    <#
    .SYNOPSIS
        Stages ONLY the named files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Files
    )
    $result = Invoke-ExternalCommand -Executable git -Arguments (@('add', '--') + $Files) -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: git add failed. $($result.StandardError)" }
}

function Remove-GitStagedFile {
    <#
    .SYNOPSIS
        Unstages the named files WITHOUT touching their working-tree content
       : git restore --staged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Files
    )
    $result = Invoke-ExternalCommand -Executable git -Arguments (@('restore', '--staged', '--') + $Files) -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: git restore --staged failed. $($result.StandardError)" }
}

function Test-GitPreCommitConcern {
    <#
    .SYNOPSIS
        Pre-commit review of selected files: likely secrets (reusing
        the central redaction patterns) and unusually large files. WARNING data
        for the wizard - reporting only, never an automatic rewrite.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Files,
        [Parameter()][int]$LargeFileKB = 1024
    )
    $concerns = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $Files) {
        $fullPath = Join-Path $Path $file
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
        $item = Get-Item -LiteralPath $fullPath
        if ($item.Length -gt ($LargeFileKB * 1KB)) {
            $concerns.Add([pscustomobject]@{ PSTypeName = 'Lamfa.PreCommitConcern'
                File = $file; Kind = 'LargeFile'
                Detail = ('{0:N0} KB - large files bloat the repository forever; consider Git LFS or exclusion.' -f ($item.Length / 1KB)) })
        }
        if ($item.Length -le 5MB) {
            $content = Get-Content -LiteralPath $fullPath -Raw -ErrorAction SilentlyContinue
            if ($content -and ((Get-RedactedText -Text $content) -ne $content)) {
                $concerns.Add([pscustomobject]@{ PSTypeName = 'Lamfa.PreCommitConcern'
                    File = $file; Kind = 'LikelySecret'
                    Detail = 'Content matches a known secret pattern (token/password/key). Committing secrets is practically irreversible.' })
            }
        }
    }
    return $concerns.ToArray()
}

function Get-GitStagedDiff {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][switch]$StatOnly
    )
    $arguments = @('diff', '--cached')
    if ($StatOnly) { $arguments += '--stat' }
    $result = Invoke-ExternalCommand -Executable git -Arguments $arguments -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: $($result.StandardError)" }
    return $result.StandardOutput
}

function New-GitCommit {
    <#
    .SYNOPSIS
        Creates a commit from the CURRENT staged snapshot. Refuses when
        nothing is staged. Title/body passed as separate -m arguments (no shell string assembly).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Title,
        [Parameter()][AllowEmptyString()][string]$Body = ''
    )
    $staged = Invoke-ExternalCommand -Executable git -Arguments @('diff', '--cached', '--name-only') -WorkingDirectory $Path
    if (-not $staged.Succeeded) { throw "ExternalCommandError: $($staged.StandardError)" }
    if ([string]::IsNullOrWhiteSpace($staged.StandardOutput)) {
        throw 'PreconditionError: nothing is staged. Select and stage files first.'
    }
    $arguments = @('commit', '-m', $Title)
    if (-not [string]::IsNullOrWhiteSpace($Body)) { $arguments += @('-m', $Body) }
    $result = Invoke-ExternalCommand -Executable git -Arguments $arguments -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: commit failed. $($result.StandardError)" }
    return $result
}

Export-ModuleMember -Function Add-GitStagedFile, Remove-GitStagedFile, Test-GitPreCommitConcern, Get-GitStagedDiff, New-GitCommit
