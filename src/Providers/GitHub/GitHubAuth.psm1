# GitHub CLI detection + authentication status/launchers.
# Lamfa never reads or displays tokens; gh owns credential storage.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../../Core/CommandRunner.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../../Models/DependencyStatus.psm1') -DisableNameChecking

function Get-GitHubCliStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $command = Get-Command -Name gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return New-DependencyStatus -Name 'GitHub CLI' -Executable gh -Installed $false `
            -Message 'GitHub CLI is not installed. GitHub features are optional; Git keeps working. Install: https://cli.github.com/'
    }
    $result = Invoke-ExternalCommand -Executable gh -Arguments @('--version') -WorkingDirectory ([System.IO.Path]::GetTempPath())
    $version = if ($result.Succeeded -and $result.StandardOutput -match 'gh version (\S+)') { $Matches[1] } else { $null }
    return New-DependencyStatus -Name 'GitHub CLI' -Executable gh -Installed $true -Version $version `
        -Supported $true -Capabilities @('auth', 'repo', 'pr', 'json')
}

function Get-GitHubAuthStatus {
    <#
    .SYNOPSIS
        Hosts and account names from 'gh auth status'. Names only -
        never tokens. Also flags insecure plaintext token storage when gh says so.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $result = Invoke-ExternalCommand -Executable gh -Arguments @('auth', 'status') `
        -WorkingDirectory ([System.IO.Path]::GetTempPath())
    $text = $result.StandardOutput + "`n" + $result.StandardError
    $accounts = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^\s*([\w.\-]+\.[\w.\-]+)\s*$') { continue }   # standalone host header line
        if ($line -match 'Logged in to (\S+) (?:account|as) (\S+)') {
            $accounts.Add([pscustomobject]@{ PSTypeName = 'Lamfa.GitHubAccount'
                HostName = $Matches[1]; Account = ($Matches[2] -replace '\(.*\)', ''); Active = ($line -notmatch 'inactive') })
        }
    }
    return [pscustomobject]@{
        PSTypeName          = 'Lamfa.GitHubAuthStatus'
        Authenticated       = ($result.ExitCode -eq 0)
        Accounts            = $accounts.ToArray()
        UsesPlaintextTokens = ($text -match 'plain.?text')
        RawSummary          = $text.Trim()
    }
}

function Start-GitHubLogin {
    <#
    .SYNOPSIS
        Launches interactive 'gh auth login' in a visible console window
        - the login flow needs real user input and a browser, which the
        capturing runner cannot host. Explicit user action only; never automatic.
    #>
    [CmdletBinding()]
    param([Parameter()][string]$HostName = 'github.com')
    Start-Process -FilePath gh -ArgumentList @('auth', 'login', '--hostname', $HostName) -Wait
}

function Switch-GitHubAccount {
    <#
    .SYNOPSIS
        Switches the active gh account with an exact host+user target.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Account,
        [Parameter()][string]$HostName = 'github.com'
    )
    return Invoke-ExternalCommand -Executable gh `
        -Arguments @('auth', 'switch', '--hostname', $HostName, '--user', $Account) -WorkingDirectory ([System.IO.Path]::GetTempPath())
}

Export-ModuleMember -Function Get-GitHubCliStatus, Get-GitHubAuthStatus, Start-GitHubLogin, Switch-GitHubAccount
