# Docker availability, contexts, guarded context switch.
# Docker being absent must never break Git features - status degrades gracefully.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Models/DependencyStatus.psm1') -DisableNameChecking

function Get-DockerStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $command = Get-Command -Name docker -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.DockerStatus'
            CliInstalled = $false; DaemonRunning = $false; ClientVersion = $null; ServerVersion = $null
            ComposeVersion = $null; CurrentContext = $null
            Message = 'Docker CLI is not installed. Docker features are optional; everything else keeps working.' }
    }
    $version = Invoke-ExternalCommand -Executable docker -Arguments @('version', '--format', 'json') `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -AllowNonZeroExitCode -TimeoutSeconds 30
    $client = $null; $server = $null
    if ($version.StandardOutput) {
        try {
            $json = $version.StandardOutput | ConvertFrom-Json
            if ($json.PSObject.Properties['Client'] -and $json.Client) { $client = $json.Client.Version }
            if ($json.PSObject.Properties['Server'] -and $json.Server) { $server = $json.Server.Version }
        } catch { $client = $null }
    }
    $compose = Invoke-ExternalCommand -Executable docker -Arguments @('compose', 'version', '--short') `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -AllowNonZeroExitCode -TimeoutSeconds 30
    $context = Invoke-ExternalCommand -Executable docker -Arguments @('context', 'show') `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -AllowNonZeroExitCode -TimeoutSeconds 30
    return [pscustomobject]@{
        PSTypeName     = 'Lamfa.DockerStatus'
        CliInstalled   = $true
        DaemonRunning  = ($null -ne $server)
        ClientVersion  = $client
        ServerVersion  = $server
        ComposeVersion = if ($compose.ExitCode -eq 0) { $compose.StandardOutput.Trim() } else { $null }
        CurrentContext = if ($context.ExitCode -eq 0) { $context.StandardOutput.Trim() } else { $null }
        Message        = if ($null -eq $server) { 'Docker CLI found but the daemon is not reachable. Start Docker Desktop.' } else { '' }
    }
}

function Get-DockerContextList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    $result = Invoke-ExternalCommand -Executable docker -Arguments @('context', 'ls', '--format', 'json') `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 30
    if (-not $result.Succeeded) { throw "ExternalCommandError: docker context ls failed. $($result.StandardError)" }
    # One JSON object per line.
    $contexts = foreach ($line in ($result.StandardOutput -split "`r?`n" | Where-Object { $_ })) {
        $json = $line | ConvertFrom-Json
        [pscustomobject]@{ PSTypeName = 'Lamfa.DockerContext'
            Name = $json.Name; Endpoint = $json.DockerEndpoint; Current = [bool]$json.Current
            LooksRemote = ($json.DockerEndpoint -match '^(tcp|ssh)://') }
    }
    return @($contexts)
}

function Switch-DockerContext {
    <#
    .SYNOPSIS
        Switches the PERSISTENT Docker context. The UI layer runs this
        through the operation engine with an endpoint preview + confirmation -
        a wrong context sends every later Docker action to the wrong machine.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Name)
    return Invoke-ExternalCommand -Executable docker -Arguments @('context', 'use', $Name) `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 30
}

Export-ModuleMember -Function Get-DockerStatus, Get-DockerContextList, Switch-DockerContext
