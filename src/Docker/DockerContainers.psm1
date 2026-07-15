# Container list/inspect/lifecycle.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Get-DockerContainerList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter()][AllowEmptyString()][string]$NameFilter = '',
        [Parameter()][switch]$All
    )
    $arguments = @('ps', '--format', 'json')
    if ($All) { $arguments += '-a' }
    if ($NameFilter) { $arguments += @('--filter', "name=$NameFilter") }
    $result = Invoke-ExternalCommand -Executable docker -Arguments $arguments -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 60
    if (-not $result.Succeeded) { throw "ExternalCommandError: docker ps failed. $($result.StandardError)" }
    $containers = foreach ($line in ($result.StandardOutput -split "`r?`n" | Where-Object { $_ })) {
        $json = $line | ConvertFrom-Json
        [pscustomobject]@{ PSTypeName = 'Lamfa.DockerContainer'
            Id = $json.ID; Name = $json.Names; Image = $json.Image; State = $json.State; Status = $json.Status }
    }
    return @($containers)
}

function Invoke-DockerContainerAction {
    <#
    .SYNOPSIS
        Start/Stop/Restart one container by exact name or id.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Container,
        [Parameter(Mandatory)][ValidateSet('start', 'stop', 'restart')][string]$Action
    )
    return Invoke-ExternalCommand -Executable docker -Arguments @($Action, $Container) `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 300
}

function Get-DockerContainerLog {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Container,
        [Parameter()][ValidateRange(1, 10000)][int]$Tail = 200
    )
    $result = Invoke-ExternalCommand -Executable docker -Arguments @('logs', '--tail', "$Tail", $Container) `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 120
    if (-not $result.Succeeded) { throw "ExternalCommandError: docker logs failed. $($result.StandardError)" }
    return ($result.StandardOutput + $result.StandardError)
}

Export-ModuleMember -Function Get-DockerContainerList, Invoke-DockerContainerAction, Get-DockerContainerLog
