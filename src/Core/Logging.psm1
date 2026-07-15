# Logging - secret redaction and structured JSON-lines
# operation logging under %LOCALAPPDATA%\Lamfa\logs.
# EVERYTHING that reaches a log file passes through Get-RedactedText first.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'Platform.psm1') -DisableNameChecking

# Redaction patterns. Order matters: URL credentials before generic
# token shapes so 'https://user:token@host' redacts the credential pair whole.
$script:RedactionPatterns = @(
    # user:password@ inside URLs
    @{ Pattern = '(?<=://)[^/@\s:]+:[^/@\s]+(?=@)';                                Replacement = '[REDACTED]' }
    # Authorization headers (Bearer/Basic/token ...)
    @{ Pattern = '(?i)(authorization\s*[:=]\s*)(bearer|basic|token)?\s*\S+';        Replacement = '$1[REDACTED]' }
    # Known credential CLI arguments: --password=x, -p x, --token x ...
    @{ Pattern = '(?i)((?:--?)(?:password|passwd|pwd|token|secret|api-?key)[= ])\S+'; Replacement = '$1[REDACTED]' }
    # Well-known token shapes: GitHub (classic + fine-grained + oauth), GitLab, AWS key id
    @{ Pattern = '\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b';                    Replacement = '[REDACTED]' }
    @{ Pattern = '\bgithub_pat_[A-Za-z0-9_]{20,}\b';                                Replacement = '[REDACTED]' }
    @{ Pattern = '\bglpat-[A-Za-z0-9_\-]{15,}\b';                                   Replacement = '[REDACTED]' }
    @{ Pattern = '\bAKIA[0-9A-Z]{16}\b';                                            Replacement = '[REDACTED]' }
    @{ Pattern = '\bnpm_[A-Za-z0-9]{30,}\b';                                        Replacement = '[REDACTED]' }
    @{ Pattern = '\bxox[baprs]-[A-Za-z0-9\-]{10,}\b';                                Replacement = '[REDACTED]' }
    # KEY=value style assignments for sensitive names (env vars, config lines)
    @{ Pattern = '(?i)\b([A-Z0-9_]*(?:PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY)[A-Z0-9_]*\s*=\s*)\S+'; Replacement = '$1[REDACTED]' }
    # PEM private key blocks
    @{ Pattern = '(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----'; Replacement = '[REDACTED PRIVATE KEY]' }
)

function Get-RedactedText {
    <#
    .SYNOPSIS
        Returns the input with every recognizable secret replaced by [REDACTED].
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $result = $Text
    foreach ($rule in $script:RedactionPatterns) {
        $result = [regex]::Replace($result, $rule.Pattern, $rule.Replacement)
    }
    return $result
}

function Get-SanitizedCommandText {
    <#
    .SYNOPSIS
        Renders an executable + argument array as one display string with secrets
        redacted and space-containing arguments quoted. For logs and previews only -
        never for execution.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter()][string[]]$Arguments = @()
    )
    $parts = @($Executable)
    foreach ($argument in $Arguments) {
        $safe = Get-RedactedText -Text $argument
        if ($safe -match '\s') { $safe = '"' + $safe + '"' }
        $parts += $safe
    }
    # Second pass over the JOINED line: flag/value secrets ('--password', 'S3cret!')
    # arrive as two separate arguments, so only the assembled text exposes the pair.
    return (Get-RedactedText -Text ($parts -join ' '))
}

function Lamfa-GetLogDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return Join-Path (Lamfa-GetAppDataRoot) 'logs'
}

function Lamfa-WriteLog {
    <#
    .SYNOPSIS
        Appends one structured JSON line to the daily log file. All string values
        are redacted before writing. Logging failures never break the application.
    .PARAMETER Data
        Optional flat hashtable with additional context (repository, branch,
        operation id, exit code, duration, ...). Values are stringified + redacted.
    .PARAMETER LogDirectory
        Override for tests. Defaults to %LOCALAPPDATA%\Lamfa\logs.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][ValidateSet('Debug', 'Info', 'Warning', 'Error')][string]$Level = 'Info',
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][hashtable]$Data = @{},
        [Parameter()][string]$LogDirectory = (Lamfa-GetLogDirectory)
    )
    try {
        if (-not (Test-Path -Path $LogDirectory)) {
            $null = New-Item -ItemType Directory -Path $LogDirectory -Force
        }
        $entry = [ordered]@{
            timestampUtc = [DateTime]::UtcNow.ToString('o')
            level        = $Level
            message      = Get-RedactedText -Text $Message
        }
        foreach ($key in $Data.Keys) {
            $value = $Data[$key]
            $entry[$key] = if ($value -is [string]) { Get-RedactedText -Text $value } else { $value }
        }
        $file = Join-Path $LogDirectory ('lamfa-{0}.log' -f [DateTime]::UtcNow.ToString('yyyyMMdd'))
        Add-Content -Path $file -Value ($entry | ConvertTo-Json -Compress -Depth 4) -Encoding utf8
    } catch {
        # Logging must never take the application down; surface once on the console.
        Write-Warning "Lamfa logging failed: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Get-RedactedText, Get-SanitizedCommandText, Lamfa-GetLogDirectory, Lamfa-WriteLog
