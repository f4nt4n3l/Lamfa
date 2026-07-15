# DependencyStatus - detection result for one external dependency.
# Consumed by dependency dashboards and
# RequiredCommandAvailable-style preconditions.
Set-StrictMode -Version 3.0

function New-DependencyStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Executable,
        [Parameter()][bool]$Installed = $false,
        [Parameter()][AllowNull()][string]$Version = $null,
        [Parameter()][bool]$Supported = $false,
        [Parameter()][bool]$Required = $false,
        [Parameter()][string[]]$Capabilities = @(),
        [Parameter()][AllowEmptyString()][string]$Message = ''
    )
    return [pscustomobject]@{
        PSTypeName   = 'Lamfa.DependencyStatus'
        Name         = $Name
        Executable   = $Executable
        Installed    = $Installed
        Version      = $Version
        Supported    = $Supported
        Required     = $Required
        Capabilities = $Capabilities
        Message      = $Message
    }
}

Export-ModuleMember -Function New-DependencyStatus
