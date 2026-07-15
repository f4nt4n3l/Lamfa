# Declarative workflow execution. Profile commands
# run through the central runner; repository-owned profiles require trust first.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Logging.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'ProfileLoader.psm1') -DisableNameChecking

function Lamfa-GetWorkflowCommand {
    <#
    .SYNOPSIS
        Resolves one named command (build/test/run/clean/...) from a resolved
        profile; $null when the profile does not define it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$ResolvedProfile,
        [Parameter(Mandatory)][string]$CommandName
    )
    $commands = $ResolvedProfile.Data.PSObject.Properties['commands']
    if (-not $commands -or $null -eq $commands.Value) { return $null }
    $definition = $commands.Value.PSObject.Properties[$CommandName]
    if (-not $definition) { return $null }
    $command = $definition.Value
    $argumentList = @()
    if ($command.PSObject.Properties['arguments'] -and $null -ne $command.arguments) {
        $argumentList = @($command.arguments | ForEach-Object { [string]$_ })
    }
    return [pscustomobject]@{
        PSTypeName = 'Lamfa.WorkflowCommand'
        Name       = $CommandName
        Executable = [string]$command.executable
        Arguments  = $argumentList
    }
}

function Lamfa-InvokeWorkflowCommand {
    <#
    .SYNOPSIS
        Runs one profile command in the repository. Repository-owned
        profiles must be trusted for THIS content hash first -
        untrusted execution is refused, never silently allowed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string]$RepositoryId,
        [Parameter(Mandatory)][pscustomobject]$ResolvedProfile,
        [Parameter(Mandatory)][string]$CommandName,
        [Parameter()][int]$TimeoutSeconds = 3600,
        [Parameter()][string]$TrustStorePath = (Join-Path (Lamfa-GetConfigDirectory) 'profile-trust.json')
    )
    $command = Lamfa-GetWorkflowCommand -ResolvedProfile $ResolvedProfile -CommandName $CommandName
    if ($null -eq $command) {
        throw "ValidationError: the profile ($($ResolvedProfile.Source)) does not define a '$CommandName' command."
    }
    if ($ResolvedProfile.IsRepositoryOwned) {
        if (-not (Lamfa-IsProfileTrusted -RepositoryId $RepositoryId -ProfilePath $ResolvedProfile.Source -TrustStorePath $TrustStorePath)) {
            throw ("PreconditionError: the repository-owned profile is not trusted (or changed since it was trusted).`n" +
                "Review it, then grant trust explicitly. Command it wants to run: " +
                (Get-SanitizedCommandText -Executable $command.Executable -Arguments $command.Arguments))
        }
    }
    Lamfa-WriteLog -Message 'workflow command starting' -Data @{
        workflow = $CommandName; repository = $RepositoryPath
        command  = (Get-SanitizedCommandText -Executable $command.Executable -Arguments $command.Arguments)
    }
    return Invoke-ExternalCommand -Executable $command.Executable -Arguments $command.Arguments `
        -WorkingDirectory $RepositoryPath -TimeoutSeconds $TimeoutSeconds -AllowNonZeroExitCode
}

function Lamfa-GetCommentAudit {
    <#
    .SYNOPSIS
        Generic source comment audit: TODO/FIXME/HACK/TEMP markers and
        likely secrets inside comments. Reporting only - never modifies files.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string[]]$Include = @('*.ps1', '*.psm1', '*.cs', '*.js', '*.ts', '*.py', '*.sql', '*.yaml', '*.yml'),
        [Parameter()][int]$MaxFiles = 2000
    )
    $findings = [System.Collections.Generic.List[object]]::new()
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Include $Include -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(\.git|node_modules|bin|obj|dist)\\' } |
        Select-Object -First $MaxFiles)
    foreach ($file in $files) {
        $lineNumber = 0
        foreach ($line in (Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
            $lineNumber++
            if ($line -notmatch '(//|#|--|/\*|\*|<!--|;)') { continue }
            if ($line -match '\b(TODO|FIXME|HACK|TEMP)\b') {
                $findings.Add([pscustomobject]@{ PSTypeName = 'Lamfa.CommentFinding'
                    File = [System.IO.Path]::GetRelativePath($Path, $file.FullName); Line = $lineNumber
                    Kind = $Matches[1]; Text = $line.Trim() })
            } elseif ((Get-RedactedText -Text $line) -ne $line) {
                $findings.Add([pscustomobject]@{ PSTypeName = 'Lamfa.CommentFinding'
                    File = [System.IO.Path]::GetRelativePath($Path, $file.FullName); Line = $lineNumber
                    Kind = 'LikelySecret'; Text = (Get-RedactedText -Text $line.Trim()) })
            }
        }
    }
    return $findings.ToArray()
}


function Lamfa-TestCommitTitle {
    <#
    .SYNOPSIS
        Validates a commit title against the profile's optional convention
       : commit.titlePattern (regex) + commit.hint (beginner text).
        No configured convention = everything is valid.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$ResolvedProfile,
        [Parameter(Mandatory)][string]$Title
    )
    $commitSection = $ResolvedProfile.Data.PSObject.Properties['commit']
    if (-not $commitSection -or $null -eq $commitSection.Value) {
        return [pscustomobject]@{ Valid = $true; Hint = '' }
    }
    $patternProperty = $commitSection.Value.PSObject.Properties['titlePattern']
    if (-not $patternProperty -or [string]::IsNullOrWhiteSpace([string]$patternProperty.Value)) {
        return [pscustomobject]@{ Valid = $true; Hint = '' }
    }
    $hintProperty = $commitSection.Value.PSObject.Properties['hint']
    $hint = if ($hintProperty -and $hintProperty.Value) { [string]$hintProperty.Value }
        else { "Title must match: $($patternProperty.Value)" }
    return [pscustomobject]@{
        Valid = [bool]($Title -match [string]$patternProperty.Value)
        Hint  = $hint
    }
}

Export-ModuleMember -Function Lamfa-GetWorkflowCommand, Lamfa-InvokeWorkflowCommand, Lamfa-GetCommentAudit, Lamfa-TestCommitTitle
