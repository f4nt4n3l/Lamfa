# Generic remote-provider helpers - provider detection
# from remote URLs and provider-neutral browser navigation. The foundation the
# multi-provider adapters build on.
Set-StrictMode -Version 3.0

function Lamfa-GetProviderFromRemote {
    <#
    .SYNOPSIS
        Infers the hosting provider from a remote URL. Self-hosted Gitea/GitLab
        instances cannot be inferred from the URL alone - the repository profile
        can override via repository.provider (checked by callers first).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$RemoteUrl)

    $hostName = $null
    if ($RemoteUrl -match '^(?:https?|ssh)://(?:[^@/]+@)?([^/:]+)') { $hostName = $Matches[1] }
    elseif ($RemoteUrl -match '^[\w.\-]+@([\w.\-]+):') { $hostName = $Matches[1] }

    $provider = 'generic'
    if ($hostName) {
        if ($hostName -ieq 'github.com') { $provider = 'github' }
        elseif ($hostName -match '(?i)gitlab') { $provider = 'gitlab' }
        elseif ($hostName -match '(?i)bitbucket') { $provider = 'bitbucket' }
        elseif ($hostName -match '(?i)gitea|forgejo|codeberg') { $provider = 'gitea' }
        elseif ($hostName -match '(?i)dev\.azure\.com|visualstudio\.com') { $provider = 'azuredevops' }
    }
    return [pscustomobject]@{
        PSTypeName = 'Lamfa.RemoteProvider'
        Provider   = $provider
        HostName   = $hostName
        RemoteUrl  = $RemoteUrl
    }
}

function Lamfa-ConvertToWebUrl {
    <#
    .SYNOPSIS
        Converts a fetch/push URL (SSH or HTTPS) into the browsable HTTPS page,
        provider-neutrally: git@host:owner/repo.git -> https://host/owner/repo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$RemoteUrl)

    $url = $RemoteUrl.Trim()
    if ($url -match '^[\w.\-]+@([\w.\-]+):(.+)$') { $url = "https://$($Matches[1])/$($Matches[2])" }
    elseif ($url -match '^ssh://(?:[^@/]+@)?([^/:]+)(?::\d+)?/(.+)$') { $url = "https://$($Matches[1])/$($Matches[2])" }
    $url = $url -replace '\.git/?$', ''
    if ($url -notmatch '^https?://') { return $null }
    return $url
}

function Lamfa-OpenRemoteInBrowser {
    <#
    .SYNOPSIS
        Opens the remote's web page in the default browser - works for every
        provider, no CLI needed.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RemoteUrl)
    $web = Lamfa-ConvertToWebUrl -RemoteUrl $RemoteUrl
    if (-not $web) { throw "ValidationError: cannot derive a browsable URL from '$RemoteUrl'." }
    Start-Process $web
}

Export-ModuleMember -Function Lamfa-GetProviderFromRemote, Lamfa-ConvertToWebUrl, Lamfa-OpenRemoteInBrowser
