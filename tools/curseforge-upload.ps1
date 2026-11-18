<#
.SYNOPSIS
  Uploads a release zip of Flow to CurseForge (project ID from Flow.toc's
  ## X-Curse-Project-ID), tagged with the game version from ## Interface
  (16001 -> 1.60.1, the Forever flavour). The changelog is every CHANGELOG.md
  section since the release before it (-Since; the workflow finds it on
  GitHub, by hand it's read from your git tags), newest first: a release
  covers many versions, and CurseForge players only see this changelog. With
  no earlier release known, just this version's section.

  The GitHub Action .github/workflows/curseforge.yml runs this for every
  release, with the token stored as the repository secret CF_API_TOKEN.

.USAGE
  $env:CF_API_TOKEN = "<your CurseForge API token>"   (never commit it)
  powershell -ExecutionPolicy Bypass -File tools\curseforge-upload.ps1 [-Zip dist\Flow-0.35.96.zip] [-Since 0.35.95] [-DryRun]

  -Since    the version of the release before this one (its changes are
            left out). Default: the highest v* git tag below this version.
  -DryRun   shows what it would upload (zip, project, game version name,
            changelog) without a token and without uploading.
#>
param(
    [string]$Zip,
    [string]$Since,
    [string]$Token = $env:CF_API_TOKEN,
    [string]$ProjectId,
    [string]$GameVersion,
    [string]$ReleaseType = 'release',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$api = 'https://wow.curseforge.com/api'

# --- What to upload -----------------------------------------------------------
$toc = Get-Content (Join-Path $root 'Flow.toc') -Raw
# The version: the zip's ("Flow-0.35.96.zip": an older release uploaded with
# today's script), else Flow.toc's.
$version = if ($Zip -and ((Split-Path $Zip -Leaf) -match '^Flow-(.+)\.zip$')) { $Matches[1] }
    elseif ($toc -match '## Version:\s*(\S+)') { $Matches[1] } else { throw 'No ## Version in Flow.toc' }
if (-not $ProjectId) { $ProjectId = if ($toc -match '## X-Curse-Project-ID:\s*(\d+)') { $Matches[1] } else { throw 'No ## X-Curse-Project-ID in Flow.toc' } }
if (-not $GameVersion) {
    # ## Interface: 16001 -> "1.60.1" (major, minor, patch: 1 / 60 / 01).
    if ($toc -match '## Interface:\s*(\d+)') {
        $n = [int]$Matches[1]
        $GameVersion = '{0}.{1}.{2}' -f [math]::Floor($n / 10000), ([math]::Floor($n / 100) % 100), ($n % 100)
    } else { throw 'No ## Interface in Flow.toc' }
}
if (-not $Zip) { $Zip = Join-Path $root "dist\Flow-$version.zip" }
if (-not (Test-Path $Zip)) { throw "No zip at $Zip (run tools\package.ps1 first)." }

# The changelog: every section of CHANGELOG.md after the release before this
# one, up to this version, newest first.
function ConvertTo-FlowVersion([string]$s) {
    if ($s -match '^v?(\d+(\.\d+){1,3})$') { return [version]$Matches[1] }
    return $null
}
$thisVersion = ConvertTo-FlowVersion $version
if (-not $Since) {
    # By hand: the highest release tag below this version, from your git tags.
    $tags = @(& git -C $root tag -l 'v*' 2>$null)
    $below = @($tags | ForEach-Object { ConvertTo-FlowVersion $_ } | Where-Object { $_ -and $thisVersion -and $_ -lt $thisVersion } | Sort-Object -Descending)
    if ($below.Count -gt 0) { $Since = $below[0].ToString() }
}
$after = if ($Since) { ConvertTo-FlowVersion $Since } else { $null }
$history = 'https://github.com/Perpetuator-LLC/flow-wow/blob/main/CHANGELOG.md'
$MAX_CHARS = 30000   # (cut, oldest first, past this: the rest is in the link)
$lines = Get-Content (Join-Path $root 'CHANGELOG.md')
$sections = New-Object System.Collections.ArrayList
$current = $null
foreach ($l in $lines) {
    if ($l -match '^## (\S+)') {
        $v = ConvertTo-FlowVersion $Matches[1]
        $current = $null
        if (-not $v) { continue }                       # (## Unreleased and the like)
        if ($thisVersion -and $v -gt $thisVersion) { continue }       # (newer than this release)
        if ($after -and $v -le $after) { break }        # (the release before and older)
        if (-not $after -and $sections.Count -gt 0) { break }   # (no earlier release known: this one only)
        $current = New-Object System.Collections.ArrayList
        [void]$sections.Add(@{ version = $Matches[1]; lines = $current })
        continue
    }
    if ($null -ne $current) { [void]$current.Add($l) }
}
$parts = New-Object System.Collections.ArrayList
$length, $cut = 0, 0
foreach ($s in $sections) {
    $text = ("## Flow {0}`n{1}" -f $s.version, (($s.lines -join "`n").Trim()))
    if ($length + $text.Length -gt $MAX_CHARS -and $parts.Count -gt 0) { $cut++; continue }
    [void]$parts.Add($text)
    $length += $text.Length + 2
}
$changelog = ($parts -join "`n`n").Trim()
if ($cut -gt 0) { $changelog += "`n`n$cut older version(s) in this release: see the full history, $history" }
if ($sections.Count -eq 0) { $changelog = "Flow $version. Full history: $history" }
Write-Host ("changelog: {0} version(s){1}" -f $sections.Count, $(if ($Since) { " since $Since" } else { '' }))

Write-Host ("Flow {0}: {1} -> CurseForge project {2}, game version {3}, {4}" -f $version, (Split-Path $Zip -Leaf), $ProjectId, $GameVersion, $ReleaseType)
if ($DryRun) {
    Write-Host "Changelog:"
    Write-Host $changelog
    Write-Host "(dry run: nothing uploaded)"
    exit 0
}
if (-not $Token) {
    Write-Host "::warning::No CurseForge token (CF_API_TOKEN): Flow $version was not uploaded to CurseForge. See docs/PUBLISHING.md."
    exit 0
}

# --- The game version's ID (Forever's 1.60.1) ----------------------------------
$headers = @{ 'X-Api-Token' = $Token }
$versions = Invoke-RestMethod -Uri "$api/game/versions" -Headers $headers
$types = Invoke-RestMethod -Uri "$api/game/version-types" -Headers $headers
$matching = @($versions | Where-Object { $_.name -eq $GameVersion })
if ($matching.Count -eq 0) { throw "CurseForge has no game version named $GameVersion." }
# More than one (the same number in two flavours): the Forever one.
$forever = @($types | Where-Object { $_.name -match 'Forever' -or $_.slug -match 'forever' } | ForEach-Object { $_.id })
$pick = @($matching | Where-Object { $forever -contains $_.gameVersionTypeID })
if ($pick.Count -eq 0) { $pick = $matching }
$gameVersionIds = @($pick | Select-Object -First 1 | ForEach-Object { [int]$_.id })
Write-Host ("game version {0}: id {1}" -f $GameVersion, ($gameVersionIds -join ','))

# --- Upload (multipart: metadata JSON + the zip) -------------------------------
Add-Type -AssemblyName System.Net.Http
$metadata = @{
    changelog = $changelog
    changelogType = 'markdown'
    displayName = "Flow $version"
    gameVersions = $gameVersionIds
    releaseType = $ReleaseType
} | ConvertTo-Json -Depth 4
$client = New-Object System.Net.Http.HttpClient
$client.DefaultRequestHeaders.Add('X-Api-Token', $Token)
$form = New-Object System.Net.Http.MultipartFormDataContent
$form.Add((New-Object System.Net.Http.StringContent($metadata, [Text.Encoding]::UTF8, 'application/json')), 'metadata')
$bytes = [IO.File]::ReadAllBytes((Resolve-Path $Zip))
$fileContent = New-Object System.Net.Http.ByteArrayContent(, $bytes)
$fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/zip')
$form.Add($fileContent, 'file', (Split-Path $Zip -Leaf))
$response = $client.PostAsync("$api/projects/$ProjectId/upload-file", $form).Result
$body = $response.Content.ReadAsStringAsync().Result
if (-not $response.IsSuccessStatusCode) { throw "CurseForge upload failed ($([int]$response.StatusCode)): $body" }
Write-Host "Uploaded to CurseForge: $body"
