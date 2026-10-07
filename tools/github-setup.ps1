<#
.SYNOPSIS
    One-time: puts this repository on GitHub and pushes the current branch.

.DESCRIPTION
    If the repository has no "origin" remote yet, creates a GitHub
    repository for it (asking whether private or public) and adds it as
    "origin". Then pushes the current branch and sets it to track origin.
    Only the current branch is pushed -- no other local branch, no tags.

    Needs the GitHub CLI, logged in:
        winget install GitHub.cli
        gh auth login

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

Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Stop-Script "git isn't installed." }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Stop-Script "The GitHub CLI isn't installed. Install it with:  winget install GitHub.cli   then log in with:  gh auth login   (open a new terminal after installing)."
}
gh auth status
if ($LASTEXITCODE -ne 0) { Stop-Script "Not logged in to GitHub. Run:  gh auth login" }

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
    gh repo create $Name "--$Visibility" --source . --remote origin
    if ($LASTEXITCODE -ne 0) { Stop-Script "GitHub didn't create the repository (see above). If it already exists, add it with:  git remote add origin <its URL>   and run this again." }
} else {
    Write-Host "Remote 'origin' is $(git remote get-url origin)."
}

Write-Host "Pushing $branch..."
git push -u origin $branch
if ($LASTEXITCODE -ne 0) { Stop-Script "The push failed (see above)." }

Write-Host ""
Write-Host "Done: $branch is on GitHub." -ForegroundColor Green
gh repo view --json url --jq ".url"
