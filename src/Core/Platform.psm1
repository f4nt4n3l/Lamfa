# Platform abstractions. Windows stays first-class; these
# helpers give Linux/macOS correct equivalents instead of silent breakage.
# No dependencies - this is the lowest layer.
Set-StrictMode -Version 3.0

function Lamfa-IsWindows {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool]$IsWindows
}

function Lamfa-GetAppDataRoot {
    <#
    .SYNOPSIS
        The per-user Lamfa data root: %LOCALAPPDATA%\Lamfa on Windows,
        $XDG_DATA_HOME/lamfa (default ~/.local/share/lamfa) elsewhere.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($IsWindows) { return Join-Path $env:LOCALAPPDATA 'Lamfa' }
    $xdg = $env:XDG_DATA_HOME
    if ([string]::IsNullOrWhiteSpace($xdg)) { $xdg = Join-Path $HOME '.local/share' }
    return Join-Path $xdg 'lamfa'
}

function Lamfa-OpenPath {
    <#
    .SYNOPSIS
        Opens a folder or URL with the platform's default handler
        (explorer / open / xdg-open).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if ($IsWindows) { Start-Process explorer.exe -ArgumentList $Path; return }
    if ($IsMacOS) { Start-Process open -ArgumentList $Path; return }
    Start-Process xdg-open -ArgumentList $Path -ErrorAction SilentlyContinue
}

function Lamfa-SendToRecycle {
    <#
    .SYNOPSIS
        Reversible folder deletion: Windows Recycle Bin; 'gio trash' / 'trash'
        on Linux/macOS when available. Where no safe recycle exists the call is
        REFUSED with guidance - Lamfa never falls back to permanent deletion.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if ($IsWindows) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
        return
    }
    foreach ($tool in @(@{ Exe = 'gio'; Args = @('trash', $Path) }, @{ Exe = 'trash'; Args = @($Path) })) {
        $command = Get-Command -Name $tool.Exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            & $command.Source @($tool.Args)
            if ($LASTEXITCODE -eq 0) { return }
        }
    }
    throw ("PreconditionError: no trash utility found on this system (tried 'gio trash' and 'trash'). " +
        "Lamfa refuses PERMANENT deletion - install trash-cli, or delete the folder manually after your own verification.")
}

function Lamfa-IsSshAgentRunning {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if ($IsWindows) {
        $agent = Get-Service -Name 'ssh-agent' -ErrorAction SilentlyContinue
        return ($null -ne $agent -and $agent.Status -eq 'Running')
    }
    return -not [string]::IsNullOrWhiteSpace($env:SSH_AUTH_SOCK)
}

Export-ModuleMember -Function Lamfa-IsWindows, Lamfa-GetAppDataRoot, Lamfa-OpenPath, Lamfa-SendToRecycle, Lamfa-IsSshAgentRunning
