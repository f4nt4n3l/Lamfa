# Blame + commit search + .gitignore helper.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Get-GitBlame {
    <#
    .SYNOPSIS
        Per-line authorship of one file: Line, Commit, Author, Date, Text.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$File
    )
    $result = Invoke-ExternalCommand -Executable git -Arguments @('blame', '--line-porcelain', '--', $File) -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: git blame failed. $($result.StandardError)" }
    $entries = [System.Collections.Generic.List[object]]::new()
    $commit = ''; $author = ''; $time = [DateTime]::MinValue; $lineNumber = 0
    foreach ($line in ($result.StandardOutput -split "`r?`n")) {
        if ($line -match '^([0-9a-f]{40}) \d+ (\d+)') { $commit = $Matches[1].Substring(0, 8); $lineNumber = [int]$Matches[2]; continue }
        if ($line.StartsWith('author '))      { $author = $line.Substring(7); continue }
        if ($line.StartsWith('author-time ')) { $time = [DateTimeOffset]::FromUnixTimeSeconds([long]$line.Substring(12)).UtcDateTime; continue }
        if ($line.StartsWith("`t")) {
            $entries.Add([pscustomobject]@{ PSTypeName = 'Lamfa.GitBlameLine'
                Line = $lineNumber; Commit = $commit; Author = $author; Date = $time; Text = $line.Substring(1) })
        }
    }
    return $entries.ToArray()
}

function Find-GitCommit {
    <#
    .SYNOPSIS
        Searches history by commit message (-Message) and/or by code
        content that a commit ADDED or REMOVED (-Code, git pickaxe).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][AllowEmptyString()][string]$Message = '',
        [Parameter()][AllowEmptyString()][string]$Code = '',
        [Parameter()][ValidateRange(1, 500)][int]$Limit = 50
    )
    if (-not $Message -and -not $Code) { throw 'ValidationError: give -Message and/or -Code to search for.' }
    $arguments = @('log', "--max-count=$Limit", '--date=iso-strict', '--format=%h%x1f%an%x1f%ad%x1f%s', '--branches')
    if ($Message) { $arguments += @('--grep', $Message, '-i') }
    if ($Code) { $arguments += @('-S', $Code) }
    $result = Invoke-ExternalCommand -Executable git -Arguments $arguments -WorkingDirectory $Path
    if ($result.ExitCode -ne 0) { return @() }
    $commits = foreach ($line in ($result.StandardOutput -split "`r?`n" | Where-Object { $_ })) {
        $parts = $line -split "`u{1f}"
        [pscustomobject]@{ PSTypeName = 'Lamfa.GitCommit'
            Hash = $parts[0]; Author = $parts[1]; Date = $parts[2]; Subject = $parts[3] }
    }
    return @($commits)
}

$script:IgnoreTemplates = @{
    dotnet = @('bin/', 'obj/', '*.user', 'TestResults/', '.vs/')
    node   = @('node_modules/', 'dist/', '.env', 'npm-debug.log*', 'coverage/')
    python = @('__pycache__/', '*.pyc', '.venv/', 'venv/', '.pytest_cache/', 'dist/')
    docker = @('.env')
}

function Add-GitIgnoreEntry {
    <#
    .SYNOPSIS
        Appends entries to .gitignore, skipping ones already present.
        Returns the entries actually added.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Entries
    )
    $ignoreFile = Join-Path $Path '.gitignore'
    $existing = @()
    if (Test-Path -LiteralPath $ignoreFile) { $existing = @(Get-Content -LiteralPath $ignoreFile) }
    $added = @($Entries | Where-Object { $_ -and ($_ -notin $existing) })
    if ($added.Count -gt 0) { Add-Content -Path $ignoreFile -Value $added -Encoding utf8 }
    return ,$added
}

function Get-GitIgnoreTemplate {
    <#
    .SYNOPSIS
        Built-in ignore entries per project type (dotnet/node/python/docker).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][ValidateSet('dotnet', 'node', 'python', 'docker')][string]$ProjectType)
    return ,@($script:IgnoreTemplates[$ProjectType])
}

Export-ModuleMember -Function Get-GitBlame, Find-GitCommit, Add-GitIgnoreEntry, Get-GitIgnoreTemplate
