# Tag queries + guarded tag creation.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Get-GitTagList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string]$Path)
    $result = Invoke-ExternalCommand -Executable git `
        -Arguments @('for-each-ref', '--sort=-creatordate', '--format=%(refname:short)|%(objectname:short)|%(creatordate:iso-strict)', 'refs/tags') `
        -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: $($result.StandardError)" }
    $tags = foreach ($line in ($result.StandardOutput -split "`r?`n" | Where-Object { $_ })) {
        $parts = $line.Split('|')
        [pscustomobject]@{ PSTypeName = 'Lamfa.GitTag'; Name = $parts[0]; Commit = $parts[1]; Created = $parts[2] }
    }
    return @($tags)
}

function New-GitTag {
    <#
    .SYNOPSIS
        Creates an annotated tag on an explicit ref; optionally pushes it to one
        remote. Refuses to overwrite an existing tag.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][string]$Ref = 'HEAD',
        [Parameter()][AllowEmptyString()][string]$PushToRemote = ''
    )
    $existing = Invoke-ExternalCommand -Executable git -Arguments @('rev-parse', '-q', '--verify', "refs/tags/$Name") `
        -WorkingDirectory $Path -AllowNonZeroExitCode
    if ($existing.ExitCode -eq 0) { throw "PreconditionError: tag '$Name' already exists. Lamfa never moves or overwrites tags." }
    $result = Invoke-ExternalCommand -Executable git -Arguments @('tag', '-a', $Name, '-m', $Message, $Ref) -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: tag creation failed. $($result.StandardError)" }
    if ($PushToRemote) {
        $push = Invoke-ExternalCommand -Executable git -Arguments @('push', $PushToRemote, "refs/tags/$Name") `
            -WorkingDirectory $Path -TimeoutSeconds 600
        if (-not $push.Succeeded) { throw "ExternalCommandError: tag push failed (the local tag exists). $($push.StandardError)" }
    }
}

Export-ModuleMember -Function Get-GitTagList, New-GitTag
