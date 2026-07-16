@{
    RootModule        = 'Lamfa.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '89f823aa-cfef-4ae5-b04a-50598dccf9cf'
    Author            = 'Lamfa'
    CompanyName       = 'Lamfa'
    Copyright         = '(c) 2026 Lamfa. MIT License.'
    Description       = 'Console tool for managing Git repositories, GitHub/GitLab/Gitea/Bitbucket, and Docker.'

    # Floor is 7.0 so the module can load on any PowerShell 7 host; the documented
    # runtime TARGET is 7.6 LTS. The entry script warns below 7.6 and blocks below 7.
    # (Capability policy: prefer detection and warnings over hard version pins.)
    PowerShellVersion = '7.0'

    FunctionsToExport = @('Lamfa', 'Lamfa-Start', 'Lamfa-GetVersion', 'Lamfa-GetBootstrapInfo')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('git', 'github', 'gitlab', 'gitea', 'bitbucket', 'docker', 'repository', 'beginner', 'safety', 'windows', 'linux', 'macos')
            # Final URLs are set at launch; Publish-Lamfa.ps1 refuses to publish while empty.
            ProjectUri   = 'https://github.com/f4nt4n3l/Lamfa'
            LicenseUri   = 'https://github.com/f4nt4n3l/Lamfa/blob/main/LICENSE'
            ReleaseNotes = 'See CHANGELOG.md.'
        }
    }
}
