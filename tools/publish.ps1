param([string]$Repository = 'chojema/ChojemaCopyKeep')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($Repository -notmatch '^chojema/[A-Za-z0-9_.-]+$') {
    throw 'Select a repository owned by chojema.'
}
function Require-Success([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed. Nothing further will be published." }
}
Push-Location -LiteralPath $projectRoot
try {
    $actualRoot = git rev-parse --show-toplevel
    Require-Success 'Repository check'
    if ([IO.Path]::GetFullPath($actualRoot) -ine [IO.Path]::GetFullPath($projectRoot)) {
        throw 'The project must have its own Git repository.'
    }
    $accountJson = gh api user
    Require-Success 'GitHub account verification'
    $account = $accountJson | ConvertFrom-Json
    if ($account.login -cne 'chojema' -or -not $account.id) { throw 'The active GitHub account does not match the owner.' }
    $repoJson = gh api "repos/$Repository"
    Require-Success 'Remote repository verification'
    $repo = $repoJson | ConvertFrom-Json
    if ($repo.full_name -ine $Repository -or $repo.private -or $repo.owner.id -ne $account.id -or -not $repo.permissions.push) {
        throw 'The destination must be a public repository owned by the active account with push access.'
    }
    python tools/public_audit.py
    Require-Success 'Public-file audit'
    $files = @(Get-Content -LiteralPath 'public-files.txt' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
    $branch = git branch --show-current
    Require-Success 'Branch check'
    if ($branch -cne 'main') { throw 'Review the current branch before publishing. Expected main.' }
    $remoteUrl = "https://github.com/$Repository.git"
    $remotes = @(git remote)
    Require-Success 'Remote check'
    if ($remotes -contains 'origin') {
        $origin = git remote get-url origin
        Require-Success 'Origin check'
        if ($origin -cne $remoteUrl) { throw 'An existing origin points elsewhere. It has not been changed.' }
    } else {
        git remote add origin $remoteUrl
        Require-Success 'Origin registration'
    }
    git add -- $files
    Require-Success 'Reviewed-file staging'
    $staged = @(git diff --cached --name-only)
    Require-Success 'Staged-file inspection'
    if (@($staged | Where-Object { $_ -notin $files }).Count) { throw 'Unexpected staged files; review the index before publishing.' }
    $publicEmail = "$($account.id)+$($account.login)@users.noreply.github.com"
    $identityKeys = @('GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL')
    $identityBackup = @{}
    foreach ($key in $identityKeys) { $identityBackup[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
    try {
        [Environment]::SetEnvironmentVariable('GIT_AUTHOR_NAME','Park Chulwoo','Process')
        [Environment]::SetEnvironmentVariable('GIT_COMMITTER_NAME','Park Chulwoo','Process')
        [Environment]::SetEnvironmentVariable('GIT_AUTHOR_EMAIL',$publicEmail,'Process')
        [Environment]::SetEnvironmentVariable('GIT_COMMITTER_EMAIL',$publicEmail,'Process')
        if ($staged.Count) {
            git commit -m 'Implement Windows clipboard history with Korean and English guides'
            Require-Success 'Commit creation'
        }
    } finally {
        foreach ($key in $identityKeys) { [Environment]::SetEnvironmentVariable($key,$identityBackup[$key],'Process') }
    }
    $commitIdentity = @(git show -s --format='%an%n%ae%n%cn%n%ce' HEAD)
    Require-Success 'Commit identity check'
    if ($commitIdentity.Count -ne 4 -or $commitIdentity[0] -cne 'Park Chulwoo' -or $commitIdentity[2] -cne 'Park Chulwoo' -or $commitIdentity[1] -cne $publicEmail -or $commitIdentity[3] -cne $publicEmail) {
        throw 'Commit identity differs from the approved name and public no-reply address.'
    }
    $commitMessage = (git show -s --format='%B' HEAD) -join "`n"
    Require-Success 'Commit message inspection'
    if ($commitMessage -match '(?im)^\s*Co-authored-by:') { throw 'Unexpected additional commit attribution.' }
    $treeFiles = @(git ls-tree -r --name-only HEAD)
    Require-Success 'Commit tree inspection'
    if (@(Compare-Object $files $treeFiles).Count) { throw 'The commit tree differs from the public manifest.' }
    git push --set-upstream origin main
    Require-Success 'Push'
    $localHead = git rev-parse HEAD
    Require-Success 'Local revision check'
    $remoteHead = gh api "repos/$Repository/git/ref/heads/main" --jq '.object.sha'
    Require-Success 'Published revision check'
    if ($localHead -cne $remoteHead) { throw 'The published revision could not be confirmed.' }
    Write-Output "Verified: https://github.com/$Repository"
    Write-Output "Commit: $localHead"
} finally {
    Pop-Location
}
