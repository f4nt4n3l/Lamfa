# GitHub repository access + listing. JSON only.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../../Core/CommandRunner.psm1') -DisableNameChecking

function Test-GitHubRepositoryAccess {
    <#
    .SYNOPSIS
        Verifies the authenticated account can reach the repository behind the
        active remote. Runs INSIDE the repository so gh resolves the
        origin automatically.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Path)
    $result = Invoke-ExternalCommand -Executable gh `
        -Arguments @('repo', 'view', '--json', 'nameWithOwner,viewerPermission') `
        -WorkingDirectory $Path -TimeoutSeconds 60
    if ($result.ExitCode -ne 0) {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.GitHubAccess'
            Accessible = $false; Repository = $null; Permission = $null; Detail = $result.StandardError.Trim() }
    }
    $json = $result.StandardOutput | ConvertFrom-Json
    return [pscustomobject]@{ PSTypeName = 'Lamfa.GitHubAccess'
        Accessible = $true; Repository = $json.nameWithOwner; Permission = $json.viewerPermission; Detail = '' }
}

function Get-GitHubRepositoryList {
    <#
    .SYNOPSIS
        Lists repositories of the authenticated user or a named owner.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter()][AllowEmptyString()][string]$Owner = '',
        [Parameter()][ValidateRange(1, 500)][int]$Limit = 50,
        [Parameter()][switch]$IncludeArchived
    )
    $arguments = @('repo', 'list')
    if ($Owner) { $arguments += $Owner }
    $arguments += @('--limit', "$Limit", '--json', 'nameWithOwner,description,visibility,isArchived,updatedAt,sshUrl,url')
    if (-not $IncludeArchived) { $arguments += '--no-archived' }
    $result = Invoke-ExternalCommand -Executable gh -Arguments $arguments -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 120
    if (-not $result.Succeeded) { throw "ExternalCommandError: gh repo list failed. $($result.StandardError)" }
    return @($result.StandardOutput | ConvertFrom-Json)
}

function Open-GitHubRepositoryInBrowser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $null = Invoke-ExternalCommand -Executable gh -Arguments @('repo', 'view', '--web') -WorkingDirectory $Path -TimeoutSeconds 30
}

Export-ModuleMember -Function Test-GitHubRepositoryAccess, Get-GitHubRepositoryList, Open-GitHubRepositoryInBrowser
