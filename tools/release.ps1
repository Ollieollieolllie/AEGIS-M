<#
.SYNOPSIS
    Releases AEGIS-M: sets the version, builds, and publishes a GitHub
    release with the zipped mod attached.

.DESCRIPTION
    1. Shows the current version (.hemtt\project.toml) and asks for the
       new one: patch, minor, major, build, one you type, or unchanged.
    2. Asks before anything leaves this PC.
    3. Writes the version and commits it ("Release vX").
    4. Builds with "hemtt release" (checked, signed, zipped into
       releases\). If the build fails, the version commit is taken back
       and nothing has been pushed.
    5. Tags the commit, pushes the branch and the tag.
    6. Creates the GitHub release and uploads the zip.

    Needs: hemtt, git, the GitHub CLI logged in (gh auth login), an
    "origin" remote (tools\github-setup.cmd), and nothing uncommitted.

.PARAMETER Bump
    major, minor, patch, build, or keep -- instead of being asked.

.PARAMETER Version
    The new version itself, "1.2.3" or "1.2.3.4" -- instead of being asked.

.PARAMETER Notes
    The release's text. Default: GitHub's own notes, generated from the
    commits since the last release.

.PARAMETER Draft
    Creates the release as a draft (not visible until published on GitHub).

.PARAMETER PreRelease
    Marks the release as a pre-release.

.PARAMETER Yes
    Doesn't ask before publishing.

.PARAMETER DryRun
    Shows what would be done -- the version, the tag, the [version] section
    as it would be written -- and changes nothing. What a real run needs
    and doesn't have is listed, not stopped on.

.EXAMPLE
    tools\release.cmd

.EXAMPLE
    tools\release.cmd -Bump patch -Draft
#>
param(
    [ValidateSet("major", "minor", "patch", "build", "keep")]
    [string]$Bump,
    [string]$Version,
    [string]$Notes,
    [switch]$Draft,
    [switch]$PreRelease,
    [switch]$Yes,
    [switch]$DryRun
)

function Stop-Script([string]$Message) {
    Write-Host ""
    Write-Host "STOPPED: $Message" -ForegroundColor Red
    exit 1
}
# Something a real run needs: a dry run only says so.
function Stop-Unless-Dry([string]$Message) {
    if ($DryRun) { Write-Host "(a real run would stop here: $Message)" -ForegroundColor Yellow } else { Stop-Script $Message }
}

Set-Location (Split-Path $PSScriptRoot -Parent)
$projectFile = ".hemtt\project.toml"

# --- What it needs ---------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Stop-Script "git isn't installed (or isn't on the PATH)." }
if (-not (Get-Command hemtt -ErrorAction SilentlyContinue)) { Stop-Unless-Dry "hemtt isn't installed (or isn't on the PATH)." }
if (Get-Command gh -ErrorAction SilentlyContinue) {
    gh auth status | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-Unless-Dry "Not logged in to GitHub. Run:  gh auth login" }
} else {
    Stop-Unless-Dry "The GitHub CLI isn't installed. Install it with:  winget install GitHub.cli   then log in with:  gh auth login"
}
if (@(git remote) -notcontains "origin") { Stop-Unless-Dry "This repository has no 'origin' remote yet. Run tools\github-setup.cmd first." }
$dirty = @(git status --porcelain)
if ($dirty.Count -gt 0) {
    $dirty | Select-Object -First 10 | ForEach-Object { Write-Host "   $_" }
    Stop-Unless-Dry "There are uncommitted changes. Commit them (or put them aside) first: a release is built from what's committed."
}
$branch = (git rev-parse --abbrev-ref HEAD).Trim()

# --- The version now -------------------------------------------------------
$text = [System.IO.File]::ReadAllText((Resolve-Path $projectFile))
$section = [regex]::Match($text, '(?ms)^\[version\]\s*$(.*?)(?=^\[|\z)')
if (-not $section.Success) { Stop-Script "No [version] section in $projectFile." }
$now = @{}
foreach ($part in "major", "minor", "patch", "build") {
    $match = [regex]::Match($section.Groups[1].Value, "(?m)^\s*$part\s*=\s*(\d+)")
    if ($match.Success) { $now[$part] = [int]$match.Groups[1].Value } else { $now[$part] = 0 }
}
function Format-Version($v) { "{0}.{1}.{2}.{3}" -f $v.major, $v.minor, $v.patch, $v.build }
# (A tag leaves the build number off while it's 0: v1.2.3.)
function Format-Tag($v) { if ($v.build -gt 0) { "v" + (Format-Version $v) } else { "v{0}.{1}.{2}" -f $v.major, $v.minor, $v.patch } }
function Step-Version($v, [string]$how) {
    $next = @{ major = $v.major; minor = $v.minor; patch = $v.patch; build = $v.build }
    switch ($how) {
        "major" { $next.major++; $next.minor = 0; $next.patch = 0; $next.build = 0 }
        "minor" { $next.minor++; $next.patch = 0; $next.build = 0 }
        "patch" { $next.patch++; $next.build = 0 }
        "build" { $next.build++ }
    }
    $next
}
function Read-Version([string]$typed) {
    $match = [regex]::Match($typed.Trim().TrimStart("v"), '^(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?$')
    if (-not $match.Success) { return $null }
    $build = 0
    if ($match.Groups[4].Success) { $build = [int]$match.Groups[4].Value }
    @{ major = [int]$match.Groups[1].Value; minor = [int]$match.Groups[2].Value; patch = [int]$match.Groups[3].Value; build = $build }
}

# --- The version to release ------------------------------------------------
$new = $null
if ($Version) {
    $new = Read-Version $Version
    if (-not $new) { Stop-Script "'$Version' isn't a version (1.2.3 or 1.2.3.4)." }
} elseif ($Bump) {
    $new = Step-Version $now $Bump
} else {
    Write-Host ""
    Write-Host "AEGIS-M is at version $(Format-Version $now). Release it as:"
    Write-Host "  1) patch  $(Format-Version (Step-Version $now 'patch'))   (fixes)"
    Write-Host "  2) minor  $(Format-Version (Step-Version $now 'minor'))   (new features)"
    Write-Host "  3) major  $(Format-Version (Step-Version $now 'major'))"
    Write-Host "  4) build  $(Format-Version (Step-Version $now 'build'))"
    Write-Host "  5) another version (type it)"
    Write-Host "  6) $(Format-Version $now), unchanged"
    $choice = Read-Host "Choice [1]"
    switch ($choice) {
        "" { $new = Step-Version $now "patch" }
        "1" { $new = Step-Version $now "patch" }
        "2" { $new = Step-Version $now "minor" }
        "3" { $new = Step-Version $now "major" }
        "4" { $new = Step-Version $now "build" }
        "5" {
            $new = Read-Version (Read-Host "Version (1.2.3 or 1.2.3.4)")
            if (-not $new) { Stop-Script "That isn't a version (1.2.3 or 1.2.3.4)." }
        }
        "6" { $new = Step-Version $now "keep" }
        default { Stop-Script "'$choice' isn't one of the choices." }
    }
}
$versionText = Format-Version $new
$tag = Format-Tag $new
$changed = $versionText -ne (Format-Version $now)

if (@(git tag --list $tag).Count -gt 0) { Stop-Script "The tag $tag already exists: that version has been released. Choose another." }

# --- Last look before anything leaves this PC ------------------------------
Write-Host ""
Write-Host "About to release AEGIS-M $tag from branch $branch :" -ForegroundColor Cyan
if ($changed) { Write-Host "  - set the version to $versionText and commit it" }
Write-Host "  - build it (hemtt release)"
Write-Host "  - push $branch and the tag $tag to GitHub"
$kind = "release"
if ($Draft) { $kind = "DRAFT release" } elseif ($PreRelease) { $kind = "pre-release" }
Write-Host "  - publish the GitHub $kind $tag with the zipped mod"
if (-not $Yes -and -not $DryRun) {
    $answer = Read-Host "Go ahead? (y/N)"
    if ($answer -notmatch '^(y|yes)$') { Stop-Script "Nothing was changed." }
}

# --- The version, written and committed ------------------------------------
if ($changed -or $DryRun) {
    $body = $section.Groups[1].Value
    foreach ($part in "major", "minor", "patch", "build") {
        $pattern = "(?m)^(\s*$part\s*=\s*)\d+"
        if ([regex]::IsMatch($body, $pattern)) {
            $body = [regex]::Replace($body, $pattern, ('${1}' + $new[$part]))
        } else {
            $body = $body.TrimEnd() + "`n$part = $($new[$part])`n"
        }
    }
    if ($DryRun) {
        Write-Host ""
        Write-Host "Dry run: nothing was changed. $projectFile would read:" -ForegroundColor Green
        Write-Host ("[version]" + $body.TrimEnd())
        exit 0
    }
    $text = $text.Substring(0, $section.Groups[1].Index) + $body + $text.Substring($section.Groups[1].Index + $section.Groups[1].Length)
    [System.IO.File]::WriteAllText((Resolve-Path $projectFile), $text, (New-Object System.Text.UTF8Encoding($false)))
    git add $projectFile
    git commit -q -m "Release $tag"
    if ($LASTEXITCODE -ne 0) { Stop-Script "The version commit failed (see above)." }
}

# --- The build ---------------------------------------------------------------
# (After the commit, so the build carries this commit's hash.)
Write-Host ""
Write-Host "Building..." -ForegroundColor Cyan
hemtt release
if ($LASTEXITCODE -ne 0) {
    if ($changed) {
        # Its own commit, made a moment ago and not pushed: taken back.
        git reset -q --mixed HEAD~1
        git checkout -q -- $projectFile
        Stop-Script "The build failed (see above). The version is back at $(Format-Version $now); nothing was pushed."
    }
    Stop-Script "The build failed (see above). Nothing was pushed."
}
$zip = Get-ChildItem "releases\*.zip" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$versionText*" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $zip) { $zip = Get-ChildItem "releases\*.zip" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
if (-not $zip) { Stop-Script "The build made no zip in releases\ (is [hemtt.release] archive = true in $projectFile?). The version commit is still there, unpushed." }
Write-Host "Built $($zip.Name) ($([math]::Round($zip.Length / 1MB, 2)) MB)."

# --- GitHub ------------------------------------------------------------------
git tag -a $tag -m "AEGIS-M $tag"
if ($LASTEXITCODE -ne 0) { Stop-Script "Couldn't make the tag $tag (see above). Nothing was pushed." }
Write-Host "Pushing $branch and $tag..." -ForegroundColor Cyan
git push origin $branch
if ($LASTEXITCODE -ne 0) { Stop-Script "Pushing $branch failed (see above). The tag $tag exists here but isn't on GitHub; once the push works, run:  git push origin $tag   and create the release on GitHub with $($zip.FullName)." }
git push origin $tag
if ($LASTEXITCODE -ne 0) { Stop-Script "Pushing the tag $tag failed (see above)." }

$arguments = @("release", "create", $tag, $zip.FullName, "--title", "AEGIS-M $tag", "--verify-tag")
if ($Notes) { $arguments += @("--notes", $Notes) } else { $arguments += "--generate-notes" }
if ($Draft) { $arguments += "--draft" }
if ($PreRelease) { $arguments += "--prerelease" }
& gh @arguments
if ($LASTEXITCODE -ne 0) { Stop-Script "GitHub didn't create the release (see above). The branch and the tag are pushed; create it by hand with:  gh release create $tag `"$($zip.FullName)`" --generate-notes" }

Write-Host ""
Write-Host "Released AEGIS-M $tag." -ForegroundColor Green
