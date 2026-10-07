<#
.SYNOPSIS
    One-time: puts this repository on GitHub and pushes the current branch.

.DESCRIPTION
    If the repository has no "origin" remote yet, creates a GitHub
    repository for it (asking whether private or public) and adds it as
    "origin". Then pushes the current branch and sets it to track origin.
    Only the current branch is pushed -- no other local branch, no tags.

    Needs the GitHub CLI (winget install GitHub.cli). If it isn't logged
    in, the login is started for you.

.PARAMETER Name
    The GitHub repository's name. Default: AEGIS-M.

.PARAMETER Visibility
    "private" or "public". Asked for if not given.

.EXAMPLE
    tools\github-setup.cmd
#>
param(
    [string]$Name = "AEGIS-M",
    [ValidateSet("private", "public")]
    [string]$Visibility
)

function Stop-Script([string]$Message) {
    Write-Host ""
    Write-Host "STOPPED: $Message" -ForegroundColor Red
    exit 1
}

# The GitHub CLI: on the PATH, or where its installer puts it (a terminal
# opened before it was installed doesn't have it on its PATH yet).
function Find-GitHubCli {
    $command = Get-Command gh -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($folder in $env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs") {
        if ($folder -and (Test-Path "$folder\GitHub CLI\gh.exe")) { return "$folder\GitHub CLI\gh.exe" }
    }
    return $null
}
# Logged in to GitHub? If not, the login is started here (it opens the
# browser), and asked again after.
function Test-GitHubLogin([string]$Cli) {
    & $Cli auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { return $true }
    Write-Host ""
    Write-Host "The GitHub CLI isn't logged in yet. Starting the login (it opens your browser)..." -ForegroundColor Yellow
    & $Cli auth login --hostname github.com --git-protocol https --web
    & $Cli auth status 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Stop-Script "git isn't installed." }
$gh = Find-GitHubCli
if (-not $gh) { Stop-Script "The GitHub CLI isn't installed. Install it with:  winget install GitHub.cli   and run this again." }
if (-not (Test-GitHubLogin $gh)) { Stop-Script "Still not logged in to GitHub. Run:  `"$gh`" auth login   and then this again." }

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
$remotes = @(git remote)

if ($remotes -notcontains "origin") {
    if (-not $Visibility) {
        Write-Host ""
        Write-Host "This repository isn't on GitHub yet."
        $answer = Read-Host "Create '$Name' as (1) private or (2) public? [1]"
        if ($answer -eq "2") { $Visibility = "public" } else { $Visibility = "private" }
    }
    Write-Host "Creating the $Visibility repository '$Name' on GitHub..."
    & $gh repo create $Name "--$Visibility" --source . --remote origin
    if ($LASTEXITCODE -ne 0) { Stop-Script "GitHub didn't create the repository (see above). If it already exists, add it with:  git remote add origin <its URL>   and run this again." }
} else {
    Write-Host "Remote 'origin' is $(git remote get-url origin)."
}

Write-Host "Pushing $branch..."
git push -u origin $branch
if ($LASTEXITCODE -ne 0) { Stop-Script "The push failed (see above)." }

Write-Host ""
Write-Host "Done: $branch is on GitHub." -ForegroundColor Green
& $gh repo view --json url --jq ".url"
