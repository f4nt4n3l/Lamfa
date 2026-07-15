# Help topics + beginner glossary.
Set-StrictMode -Version 3.0

$script:Glossary = [ordered]@{
    'Repository'      = 'A project directory whose history is managed by Git.'
    'Working tree'    = 'The files currently checked out and visible in the repository directory.'
    'Stage / index'   = 'The selected snapshot that will be included in the next commit.'
    'Commit'          = 'A recorded project snapshot with metadata and a message.'
    'Branch'          = 'A movable name pointing to a line of development.'
    'Remote'          = 'A named reference to another repository location (usually on a server).'
    'Upstream branch' = 'The remote branch associated with your current local branch.'
    'Fetch'           = 'Downloads remote references WITHOUT changing your working files.'
    'Pull'            = 'Fetches and then integrates remote changes into your branch.'
    'Push'            = 'Uploads local commits to a remote.'
    'Pull request'    = 'A GitHub review-and-merge request between branches.'
    'Merge'           = 'Combines another branch into yours, keeping both histories.'
    'Rebase'          = 'Replays commits on another base and CHANGES commit identities. Advanced.'
    'Docker image'    = 'A read-only package used to create containers.'
    'Docker container'= 'A running or stopped instance of an image.'
    'Docker registry' = 'A service that stores and distributes images.'
    'Docker context'  = 'The machine the Docker CLI talks to. A wrong context targets the wrong machine.'
}

$script:HelpTopics = [ordered]@{
    'first-steps'   = 'Register an existing folder (Repositories menu) or clone one. Lamfa always shows the active repository in the header; every action explains itself before running.'
    'daily-flow'    = 'Typical loop: 1) check Status, 2) create/switch a branch, 3) edit files in your editor, 4) commit selected files, 5) push, 6) open a pull request.'
    'safety'        = 'Beginner Mode hides destructive operations (force push, hard reset, volume deletion). A failed prerequisite BLOCKS an action - a confirmation never overrides it. Deletions require typing the exact target name.'
    'accounts'      = 'Git commit identity (name/email per commit), the GitHub login (gh account), and Docker registry logins are three separate things. The Accounts menu shows each one explicitly.'
    'profiles'      = 'A repository may carry .lamfa.json defining build/test/run commands. Repository-owned profiles run only after you review and trust them; a changed profile must be re-trusted.'
    'recovery'      = 'If something looks stuck (merge conflict, rebase, detached HEAD), open Backup and recovery -> Guidance. Every suggested step preserves your work.'
    'logs'          = 'Every operation is logged (secrets redacted) under %LOCALAPPDATA%\Lamfa\logs.'
}

function Lamfa-GetGlossary {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()
    return $script:Glossary
}

function Lamfa-GetHelpTopic {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()][AllowEmptyString()][string]$Topic = '')
    if ($Topic -and $script:HelpTopics.Contains($Topic)) { return $script:HelpTopics[$Topic] }
    return ($script:HelpTopics.Keys -join ', ')
}

function Lamfa-ShowHelp {
    [CmdletBinding()]
    param()
    Write-Host ''
    Write-Host 'HELP TOPICS' -ForegroundColor Cyan
    foreach ($key in $script:HelpTopics.Keys) {
        Write-Host (' {0,-14} {1}' -f $key, $script:HelpTopics[$key])
        Write-Host ''
    }
    Write-Host 'GLOSSARY' -ForegroundColor Cyan
    foreach ($key in $script:Glossary.Keys) {
        Write-Host (' {0,-17} {1}' -f $key, $script:Glossary[$key])
    }
}

Export-ModuleMember -Function Lamfa-GetGlossary, Lamfa-GetHelpTopic, Lamfa-ShowHelp
