# Compose validation + lifecycle. 'down --volumes' is
# deliberately impossible here: volume deletion is HighRisk (hidden in Beginner
# Mode) and would need its own Advanced-Mode operation.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Test-DockerComposeConfiguration {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ComposeFile
    )
    $result = Invoke-ExternalCommand -Executable docker `
        -Arguments @('compose', '-f', $ComposeFile, 'config', '--quiet') `
        -WorkingDirectory $Path -AllowNonZeroExitCode -TimeoutSeconds 60
    return [pscustomobject]@{ PSTypeName = 'Lamfa.ComposeValidation'
        Valid = ($result.ExitCode -eq 0); Detail = $result.StandardError.Trim() }
}

function Get-DockerComposeServiceList {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ComposeFile
    )
    $result = Invoke-ExternalCommand -Executable docker `
        -Arguments @('compose', '-f', $ComposeFile, 'config', '--services') `
        -WorkingDirectory $Path -TimeoutSeconds 60
    if (-not $result.Succeeded) { throw "ExternalCommandError: compose config failed. $($result.StandardError)" }
    return @($result.StandardOutput -split "`r?`n" | Where-Object { $_ })
}

function Invoke-DockerComposeAction {
    <#
    .SYNOPSIS
        up (detached) / down / restart / logs for one Compose file.
        Volumes are NEVER removed by this function.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ComposeFile,
        [Parameter(Mandatory)][ValidateSet('up', 'down', 'restart', 'logs')][string]$Action,
        [Parameter()][AllowEmptyString()][string]$Service = ''
    )
    $arguments = @('compose', '-f', $ComposeFile, $Action)
    switch ($Action) {
        'up'   { $arguments += '--detach' }
        'logs' { $arguments += @('--tail', '200') }
    }
    if ($Service) { $arguments += $Service }
    return Invoke-ExternalCommand -Executable docker -Arguments $arguments `
        -WorkingDirectory $Path -TimeoutSeconds 1800
}

Export-ModuleMember -Function Test-DockerComposeConfiguration, Get-DockerComposeServiceList, Invoke-DockerComposeAction
