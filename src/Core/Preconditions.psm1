# Precondition engine - reusable prerequisite checks with
# beginner-readable block reasons. Git-state preconditions
# (WorkingTreeClean, NoMergeInProgress, ...) register here.
Set-StrictMode -Version 3.0

# name -> @{ Description; Test = scriptblock(context, parameters) -> bool; WhyItMatters; SafeNextAction }
$script:Preconditions = @{}

function Lamfa-RegisterPrecondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$Test,
        [Parameter(Mandatory)][string]$WhyItMatters,
        [Parameter(Mandatory)][string]$SafeNextAction
    )
    $script:Preconditions[$Name] = @{
        Description    = $Description
        Test           = $Test
        WhyItMatters   = $WhyItMatters
        SafeNextAction = $SafeNextAction
    }
}

function Lamfa-GetPreconditionList {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return @($script:Preconditions.Keys | Sort-Object)
}

function Lamfa-TestPrecondition {
    <#
    .SYNOPSIS
        Evaluates the named preconditions against a repository context. Returns one
        record per precondition: Name, Passed, Description, WhyItMatters,
        SafeNextAction. Unknown names fail closed (Passed = false).
    .PARAMETER Parameters
        Optional operation-specific values some checks need (e.g. RequiredFile,
        RequiredCommand).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Names,
        [Parameter()][AllowNull()][object]$Context = $null,
        [Parameter()][hashtable]$Parameters = @{}
    )
    $results = foreach ($name in $Names) {
        if (-not $script:Preconditions.ContainsKey($name)) {
            [pscustomobject]@{
                Name = $name; Passed = $false
                Description    = "Unknown precondition '$name'."
                WhyItMatters   = 'Lamfa cannot verify a check it does not know; it refuses instead of guessing.'
                SafeNextAction = 'Report this as a Lamfa defect: an operation references an unregistered precondition.'
            }
            continue
        }
        $definition = $script:Preconditions[$name]
        $passed = $false
        try {
            $passed = [bool](& $definition.Test $Context $Parameters)
        } catch {
            $passed = $false
        }
        [pscustomobject]@{
            Name           = $name
            Passed         = $passed
            Description    = $definition.Description
            WhyItMatters   = $definition.WhyItMatters
            SafeNextAction = $definition.SafeNextAction
        }
    }
    return @($results)
}

# ---- built-in context-only preconditions (no Git dependency) ----------------

Lamfa-RegisterPrecondition -Name 'RepositorySelected' `
    -Description 'An active repository is selected.' `
    -Test { param($Context, $Parameters) $null -ne $Context -and -not [string]::IsNullOrWhiteSpace([string]$Context.Path) } `
    -WhyItMatters 'Without an active repository Lamfa cannot know which project the action targets.' `
    -SafeNextAction 'Open the Repositories menu and select or register a repository.'

Lamfa-RegisterPrecondition -Name 'RepositoryPathExists' `
    -Description 'The active repository folder exists on disk.' `
    -Test { param($Context, $Parameters) $null -ne $Context -and (Test-Path -LiteralPath ([string]$Context.Path) -PathType Container) } `
    -WhyItMatters 'The registered folder was moved or deleted; commands would run in the wrong place.' `
    -SafeNextAction 'Re-register the repository with its new location, or restore the folder.'

Lamfa-RegisterPrecondition -Name 'IsGitRepository' `
    -Description 'The active folder is a Git repository.' `
    -Test { param($Context, $Parameters) $null -ne $Context -and [bool]$Context.IsGitRepository } `
    -WhyItMatters 'Git actions need a .git directory; this folder does not have one.' `
    -SafeNextAction 'Select a Git repository, or clone one first.'

Lamfa-RegisterPrecondition -Name 'RequiredFileExists' `
    -Description 'A file required by this action exists in the repository.' `
    -Test {
        param($Context, $Parameters)
        if ($null -eq $Context -or -not $Parameters.ContainsKey('RequiredFile')) { return $false }
        Test-Path -LiteralPath (Join-Path ([string]$Context.Path) ([string]$Parameters.RequiredFile))
    } `
    -WhyItMatters 'The action reads or runs a file that is not present, so it would fail halfway.' `
    -SafeNextAction 'Check the repository profile: the configured file path may be wrong for this project.'

Lamfa-RegisterPrecondition -Name 'RequiredCommandAvailable' `
    -Description 'A command-line tool required by this action is installed.' `
    -Test {
        param($Context, $Parameters)
        if (-not $Parameters.ContainsKey('RequiredCommand')) { return $false }
        $null -ne (Get-Command -Name ([string]$Parameters.RequiredCommand) -CommandType Application -ErrorAction SilentlyContinue)
    } `
    -WhyItMatters 'The external tool this action depends on was not found on PATH.' `
    -SafeNextAction 'Install the tool or fix PATH, then retry. Lamfa never installs software silently.'

Export-ModuleMember -Function Lamfa-RegisterPrecondition, Lamfa-GetPreconditionList, Lamfa-TestPrecondition
