# CommandResult - structured contract for every external command
# execution. Produced exclusively by the command
# runner; consumers must never fall back to $LASTEXITCODE.
Set-StrictMode -Version 3.0

function New-CommandResult {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter()][string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][datetime]$StartedUtc,
        [Parameter(Mandatory)][datetime]$EndedUtc,
        [Parameter()][Nullable[int]]$ExitCode = $null,
        [Parameter()][bool]$Succeeded = $false,
        [Parameter()][AllowEmptyString()][string]$StandardOutput = '',
        [Parameter()][AllowEmptyString()][string]$StandardError = '',
        [Parameter()][bool]$WasCancelled = $false,
        [Parameter()][bool]$WasTimedOut = $false,
        [Parameter(Mandatory)][string]$SanitizedCommand
    )
    return [pscustomobject]@{
        PSTypeName       = 'Lamfa.CommandResult'
        Executable       = $Executable
        Arguments        = $Arguments
        WorkingDirectory = $WorkingDirectory
        StartedUtc       = $StartedUtc
        EndedUtc         = $EndedUtc
        Duration         = $EndedUtc - $StartedUtc
        ExitCode         = $ExitCode
        Succeeded        = $Succeeded
        StandardOutput   = $StandardOutput
        StandardError    = $StandardError
        WasCancelled     = $WasCancelled
        WasTimedOut      = $WasTimedOut
        SanitizedCommand = $SanitizedCommand
    }
}

Export-ModuleMember -Function New-CommandResult
