<#
.SYNOPSIS
    Releases AEGIS-M: sets the version, builds, publishes a GitHub release
    with the zipped mod attached, and updates the Steam Workshop item.

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
    7. Updates the Steam Workshop item (workshop\item-id.txt) with the same
       build, and a change note made from the commits since the last
       release. Needs Steam running, logged in as the item's owner, and
       Arma 3 Tools. Not done for a draft or a pre-release. If this step
       fails, the GitHub release stands: run again with -WorkshopOnly.

    Needs: hemtt, git, the GitHub CLI (winget install GitHub.cli) and an
    "origin" remote (tools\github-setup.cmd). If the GitHub CLI isn't
    logged in, the login is started for you. If something isn't committed,
    you're asked for a commit message to commit it with, or it stops.

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

.PARAMETER NoWorkshop
    Leaves the Steam Workshop item alone.

.PARAMETER WorkshopOnly
    Only updates the Steam Workshop item, with a fresh build of what is
    committed now: no version change, nothing pushed, no GitHub release.
    For when the GitHub release went through and the Workshop step didn't.

.PARAMETER WorkshopId
    The Workshop item's ID, instead of the one in workshop\item-id.txt.

.PARAMETER DryRun
    Shows what would be done -- the version, the tag, the [version] section
    as it would be written -- and changes nothing. What a real run needs
    and doesn't have is listed, not stopped on.

.EXAMPLE
    tools\release.cmd

.EXAMPLE
    tools\release.cmd -Bump patch -Draft

.EXAMPLE
    tools\release.cmd -WorkshopOnly
#>
param(
    [ValidateSet("major", "minor", "patch", "build", "keep")]
    [string]$Bump,
    [string]$Version,
    [string]$Notes,
    [switch]$Draft,
    [switch]$PreRelease,
    [switch]$Yes,
    [switch]$NoWorkshop,
    [switch]$WorkshopOnly,
    [string]$WorkshopId,
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

# Arma 3 Tools' command-line publisher: where Arma 3 Tools says it is
# installed, or in Steam's own library.
function Find-PublisherCmd {
    $folders = @()
    $tools = Get-ItemProperty "HKCU:\Software\Bohemia Interactive\Arma 3 Tools" -ErrorAction SilentlyContinue
    if ($tools -and $tools.path) { $folders += $tools.path }
    $steam = Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
    if ($steam -and $steam.SteamPath) { $folders += (Join-Path $steam.SteamPath "steamapps\common\Arma 3 Tools") }
    foreach ($folder in $folders) {
        $exe = Join-Path $folder "Publisher\PublisherCmd.exe"
        if (Test-Path $exe) { return $exe }
    }
    return $null
}
# The Workshop item's title, from Steam (to show what is about to be
# updated); "" if Steam can't be asked.
function Get-WorkshopTitle([string]$Id) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $reply = Invoke-RestMethod -Method Post -TimeoutSec 15 -Uri "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" -Body @{ itemcount = 1; "publishedfileids[0]" = $Id }
        return [string]$reply.response.publishedfiledetails[0].title
    } catch {
        return ""
    }
}
# The Workshop change note for a release: its tag, then the notes given, or
# the commits since the release before it; and a link to the GitHub release
# if the repository is public.
function Get-ChangeNote([string]$Tag, [string]$Since) {
    $lines = @("AEGIS-M $Tag", "")
    if ($Notes) {
        $lines += $Notes
    } elseif (-not $Since) {
        # (The first release: not the whole history.)
        $lines += "Initial release."
    } else {
        $subjects = @(git log "$Since..HEAD" --no-merges --format=%s | Where-Object { $_ -notmatch '^Release v' } | Select-Object -First 40)
        foreach ($subject in $subjects) { $lines += "- $subject" }
        if ($subjects.Count -eq 0) { $lines += "Rebuilt; no changes to the mod's code." }
    }
    if ($script:repoPublic -and $script:repoUrl) { $lines += @("", "Full notes: $($script:repoUrl)/releases/tag/$Tag") }
    $lines -join "`r`n"
}
# Uploads the built mod (.hemttout\release) to the Workshop item.
function Publish-Workshop([string]$Note) {
    if (-not (Get-Process steam -ErrorAction SilentlyContinue)) {
        Write-Host "Steam isn't running: the Workshop item can only be updated with Steam running, logged in as its owner." -ForegroundColor Yellow
        return $false
    }
    $content = (Resolve-Path ".hemttout\release" -ErrorAction SilentlyContinue).Path
    if (-not $content) {
        Write-Host "There is no build in .hemttout\release to upload." -ForegroundColor Yellow
        return $false
    }
    $noteFile = Join-Path $env:TEMP "aegism-workshop-changenote.txt"
    [System.IO.File]::WriteAllText($noteFile, $Note, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Updating the Steam Workshop item $WorkshopId..." -ForegroundColor Cyan
    & $publisher update "/id:$WorkshopId" "/changeNoteFile:$noteFile" "/path:$content" /nologo /nosummary
    return ($LASTEXITCODE -eq 0)
}

Set-Location (Split-Path $PSScriptRoot -Parent)
$projectFile = ".hemtt\project.toml"

# --- What it needs ---------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Stop-Script "git isn't installed (or isn't on the PATH)." }
if (-not (Get-Command hemtt -ErrorAction SilentlyContinue)) { Stop-Unless-Dry "hemtt isn't installed (or isn't on the PATH)." }
$gh = Find-GitHubCli
if (-not $WorkshopOnly) {
    if (-not $gh) {
        Stop-Unless-Dry "The GitHub CLI isn't installed. Install it with:  winget install GitHub.cli   and run this again."
    } elseif ($DryRun) {
        & $gh auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Stop-Unless-Dry "the GitHub CLI isn't logged in (a real run starts the login itself)." }
    } elseif (-not (Test-GitHubLogin $gh)) {
        Stop-Script "Still not logged in to GitHub. Run:  `"$gh`" auth login   and then this again."
    }
    if (@(git remote) -notcontains "origin") { Stop-Unless-Dry "This repository has no 'origin' remote yet. Run tools\github-setup.cmd first." }
}

# The Steam Workshop item: its ID from workshop\item-id.txt (or -WorkshopId),
# and why it won't be updated, if it won't.
if (-not $WorkshopId -and (Test-Path "workshop\item-id.txt")) {
    $WorkshopId = [string](Get-Content "workshop\item-id.txt" | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1)
    if ($WorkshopId) { $WorkshopId = $WorkshopId.Trim() }
}
$publisher = Find-PublisherCmd
$workshopSkip = ""
if ($NoWorkshop) { $workshopSkip = "-NoWorkshop was given" }
elseif (-not $WorkshopId) { $workshopSkip = "there is no item ID in workshop\item-id.txt" }
elseif (-not $publisher) { $workshopSkip = "Arma 3 Tools' PublisherCmd.exe wasn't found" }
elseif ($Draft -and -not $WorkshopOnly) { $workshopSkip = "this is a draft release" }
elseif ($PreRelease -and -not $WorkshopOnly) { $workshopSkip = "this is a pre-release" }
if ($WorkshopOnly -and $workshopSkip) { Stop-Script "The Workshop item can't be updated: $workshopSkip." }
$workshopTitle = ""
if (-not $workshopSkip) { $workshopTitle = Get-WorkshopTitle $WorkshopId }
# (For the change note's link: only a public repository's is any use.)
$script:repoUrl = ""
$script:repoPublic = $false
if (@(git remote) -contains "origin") { $script:repoUrl = ((git remote get-url origin) -replace '\.git$', '').Trim() }
if ($gh -and $script:repoUrl) {
    $visibility = & $gh repo view --json visibility --jq .visibility 2>&1
    if ($LASTEXITCODE -eq 0 -and "$visibility".Trim() -eq "PUBLIC") { $script:repoPublic = $true }
}
# A release is built from what's committed. Anything that isn't: commit it
# here and now, with a message of your own, or stop.
$dirty = @(git status --porcelain)
if ($dirty.Count -gt 0) {
    Write-Host ""
    Write-Host "Not committed yet:" -ForegroundColor Yellow
    $dirty | Select-Object -First 20 | ForEach-Object { Write-Host "   $_" }
    if ($dirty.Count -gt 20) { Write-Host "   ... and $($dirty.Count - 20) more" }
    if ($DryRun -or $Yes -or $WorkshopOnly) {
        Stop-Unless-Dry "There are uncommitted changes, and a release is built from what's committed. Commit them first."
    } else {
        $message = Read-Host "A release is built from what's committed. Type a commit message to commit all of these now, or just press Enter to stop"
        if ($message.Trim() -eq "") { Stop-Script "Nothing was changed. Commit them (or put them aside) and run this again." }
        git add -A
        git commit -q -m $message.Trim()
        if ($LASTEXITCODE -ne 0) { Stop-Script "That commit failed (see above)." }
        Write-Host "Committed."
    }
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

# --- Only the Workshop item --------------------------------------------------
if ($WorkshopOnly) {
    $tag = Format-Tag $now
    $tags = @(git tag --list "v*" --sort=-creatordate)
    $since = ""
    $at = [array]::IndexOf($tags, $tag)
    if ($at -ge 0 -and $at + 1 -lt $tags.Count) { $since = $tags[$at + 1] }
    if ($at -lt 0) {
        Write-Host "Version $(Format-Version $now) has no release tag ($tag): it hasn't been released on GitHub." -ForegroundColor Yellow
    } elseif ((git rev-parse "$tag^{commit}").Trim() -ne (git rev-parse HEAD).Trim()) {
        Write-Host "What is committed now isn't the commit released as $tag : the Workshop would get something newer than that release." -ForegroundColor Yellow
    }
    $note = Get-ChangeNote $tag $since
    Write-Host ""
    Write-Host "About to update the Steam Workshop item $WorkshopId $(if ($workshopTitle) { "($workshopTitle) " })with AEGIS-M $tag :" -ForegroundColor Cyan
    Write-Host "  - build it (hemtt release)"
    Write-Host "  - upload .hemttout\release, with this change note:"
    $note -split "`r`n" | ForEach-Object { Write-Host "      $_" }
    if ($DryRun) { Write-Host ""; Write-Host "Dry run: nothing was changed." -ForegroundColor Green; exit 0 }
    if (-not $Yes) {
        $answer = Read-Host "Go ahead? (y/N)"
        if ($answer -notmatch '^(y|yes)$') { Stop-Script "Nothing was changed." }
    }
    hemtt release
    if ($LASTEXITCODE -ne 0) { Stop-Script "The build failed (see above). The Workshop item wasn't touched." }
    if (-not (Publish-Workshop $note)) { Stop-Script "The Workshop update didn't go through (see above)." }
    Write-Host ""
    Write-Host "The Steam Workshop item is updated to AEGIS-M $tag." -ForegroundColor Green
    exit 0
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

if (@(git tag --list $tag).Count -gt 0) { Stop-Script "The tag $tag already exists: that version has been released. Choose another. (To send it to the Workshop again: -WorkshopOnly.)" }
# (The release before this one, for the Workshop change note.)
$previousTag = [string](git tag --list "v*" --sort=-creatordate | Select-Object -First 1)

# --- Last look before anything leaves this PC ------------------------------
Write-Host ""
Write-Host "About to release AEGIS-M $tag from branch $branch :" -ForegroundColor Cyan
if ($changed) { Write-Host "  - set the version to $versionText and commit it" }
Write-Host "  - build it (hemtt release)"
Write-Host "  - push $branch and the tag $tag to GitHub"
$kind = "release"
if ($Draft) { $kind = "DRAFT release" } elseif ($PreRelease) { $kind = "pre-release" }
Write-Host "  - publish the GitHub $kind $tag with the zipped mod"
if ($workshopSkip) {
    Write-Host "  - (the Steam Workshop item is left alone: $workshopSkip)"
} else {
    Write-Host "  - update the Steam Workshop item $WorkshopId $(if ($workshopTitle) { "($workshopTitle) " })with it; Steam has to be running"
}
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
        if (-not $workshopSkip) {
            Write-Host ""
            Write-Host "The Workshop change note would be:"
            (Get-ChangeNote $tag $previousTag) -split "`r`n" | ForEach-Object { Write-Host "    $_" }
        }
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
& $gh @arguments
if ($LASTEXITCODE -ne 0) { Stop-Script "GitHub didn't create the release (see above). The branch and the tag are pushed; create it by hand with:  gh release create $tag `"$($zip.FullName)`" --generate-notes" }

Write-Host ""
Write-Host "Released AEGIS-M $tag on GitHub." -ForegroundColor Green

# --- The Steam Workshop --------------------------------------------------------
if (-not $workshopSkip) {
    if (Publish-Workshop (Get-ChangeNote $tag $previousTag)) {
        Write-Host "The Steam Workshop item is updated to AEGIS-M $tag." -ForegroundColor Green
    } else {
        Stop-Script "The GitHub release is done, but the Workshop update didn't go through (see above). When Steam is running, send it with:  tools\release.cmd -WorkshopOnly"
    }
}
