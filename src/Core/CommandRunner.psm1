# CommandRunner - THE single gateway for external commands.
# Every git/gh/docker/project call in Lamfa routes
# through Invoke-ExternalCommand; nothing else may start external processes.
#
# Contract highlights:
#   - argument ARRAYS, never a split command line;
#   - explicit working directory, never global Set-Location;
#   - returns a CommandResult; a failing command NEVER throws (only invalid
#     caller input does, via parameter validation);
#   - timeout and cooperative cancellation kill the whole process tree;
#   - stdout/stderr captured as UTF-8 (Unicode-safe).
Set-StrictMode -Version 3.0

Import-Module -Name (Join-Path $PSScriptRoot 'Logging.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Models/CommandResult.psm1') -DisableNameChecking

function Invoke-ExternalCommand {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter()][AllowEmptyCollection()][string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter()][hashtable]$Environment = @{},
        [Parameter()][ValidateRange(0, 86400)][int]$TimeoutSeconds = 0,
        [Parameter()][switch]$AllowNonZeroExitCode,
        [Parameter()][AllowNull()][System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None,
        # Text piped to the child's stdin (e.g. docker login --password-stdin).
        # NEVER logged: stdin content bypasses SanitizedCommand by design.
        [Parameter()][AllowNull()][AllowEmptyString()][string]$StandardInput = $null
    )

    $sanitized = Get-SanitizedCommandText -Executable $Executable -Arguments $Arguments
    $startedUtc = [DateTime]::UtcNow

    # Nested helper - reads the enclosing invocation's variables via dynamic scoping.
    function NewFailedResult([string]$Message) {
        New-CommandResult -Executable $Executable -Arguments $Arguments `
            -WorkingDirectory $WorkingDirectory -StartedUtc $startedUtc `
            -EndedUtc ([DateTime]::UtcNow) -ExitCode $null -Succeeded $false `
            -StandardError $Message -SanitizedCommand $sanitized
    }

    # Precondition failures return a failed result instead of throwing - the
    # runner must never terminate the application for a runnable-state problem.
    if (-not (Test-Path -Path $WorkingDirectory -PathType Container)) {
        return (NewFailedResult "Working directory does not exist: $WorkingDirectory")
    }
    # -First 1: the same executable can resolve to several applications (e.g. pwsh
    # exists both under Program Files and as a WindowsApps alias); PATH order wins.
    $resolvedExecutable = Get-Command -Name $Executable -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $resolvedExecutable) {
        return (NewFailedResult "Executable not found on PATH: $Executable")
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo.FileName = $resolvedExecutable.Source
    foreach ($argument in $Arguments) {
        # ArgumentList performs correct per-argument quoting (spaces, quotes).
        $process.StartInfo.ArgumentList.Add($argument)
    }
    $process.StartInfo.WorkingDirectory = $WorkingDirectory
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    if ($null -ne $StandardInput) { $process.StartInfo.RedirectStandardInput = $true }
    $process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $process.StartInfo.CreateNoWindow = $true
    foreach ($key in $Environment.Keys) {
        $process.StartInfo.EnvironmentVariables[$key] = [string]$Environment[$key]
    }

    $wasTimedOut = $false
    $wasCancelled = $false
    try {
        $null = $process.Start()

        if ($null -ne $StandardInput) {
            $process.StandardInput.Write($StandardInput)
            $process.StandardInput.Close()
        }

        # Async reads prevent the classic redirected-pipe deadlock on large output.
        $stdOutTask = $process.StandardOutput.ReadToEndAsync()
        $stdErrTask = $process.StandardError.ReadToEndAsync()

        $deadline = if ($TimeoutSeconds -gt 0) { $startedUtc.AddSeconds($TimeoutSeconds) } else { [DateTime]::MaxValue }
        while (-not $process.HasExited) {
            if ($CancellationToken.IsCancellationRequested) { $wasCancelled = $true; break }
            if ([DateTime]::UtcNow -gt $deadline) { $wasTimedOut = $true; break }
            Start-Sleep -Milliseconds 50
        }

        if ($wasTimedOut -or $wasCancelled) {
            try { $process.Kill($true) } catch { Write-Verbose "Process kill after stop request failed: $($_.Exception.Message)" }
            $null = $process.WaitForExit(5000)
        } else {
            # Ensure redirected streams are fully drained before reading results.
            $process.WaitForExit()
        }

        $standardOutput = $stdOutTask.GetAwaiter().GetResult()
        $standardError = $stdErrTask.GetAwaiter().GetResult()
        $exitCode = if ($process.HasExited) { $process.ExitCode } else { $null }

        $succeeded = (-not $wasTimedOut) -and (-not $wasCancelled) -and ($null -ne $exitCode) -and
            (($exitCode -eq 0) -or $AllowNonZeroExitCode.IsPresent)
        if ($wasTimedOut) { $standardError = "Command timed out after $TimeoutSeconds second(s). $standardError".Trim() }
        if ($wasCancelled) { $standardError = "Command was cancelled by the user. $standardError".Trim() }

        $result = New-CommandResult -Executable $Executable -Arguments $Arguments `
            -WorkingDirectory $WorkingDirectory -StartedUtc $startedUtc `
            -EndedUtc ([DateTime]::UtcNow) -ExitCode $exitCode -Succeeded $succeeded `
            -StandardOutput $standardOutput -StandardError $standardError `
            -WasCancelled $wasCancelled -WasTimedOut $wasTimedOut -SanitizedCommand $sanitized
    } catch {
        $result = NewFailedResult "Failed to run command: $($_.Exception.Message)"
    } finally {
        $process.Dispose()
    }

    Lamfa-WriteLog -Level ($(if ($result.Succeeded) { 'Info' } else { 'Warning' })) `
        -Message "external command finished" -Data @{
            command   = $result.SanitizedCommand
            directory = $result.WorkingDirectory
            exitCode  = $result.ExitCode
            durationMs = [int]$result.Duration.TotalMilliseconds
            succeeded = $result.Succeeded
            timedOut  = $result.WasTimedOut
            cancelled = $result.WasCancelled
        }
    return $result
}

Export-ModuleMember -Function Invoke-ExternalCommand
