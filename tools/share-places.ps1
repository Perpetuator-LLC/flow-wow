<#
.SYNOPSIS
  Merges the NPC spots a Flow player chose to share (in game: /flow places
  share, then /reload) into Learned\Places.lua, the shared list that comes
  with Flow. A pull request then brings it to every Flow player.

  What's shared: NPCs only. Name, NPC ID, where, what they do (vendor,
  repair, trainer, flight master, innkeeper, banker, auctioneer, quest giver)
  and which faction used them; plus mailboxes. Nothing about the player.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\share-places.ps1
      your own saved data (WoW folder and account found by themselves)
  powershell -ExecutionPolicy Bypass -File tools\share-places.ps1 -From <path\to\Flow.lua>
      someone else's saved data (WTF\Account\<name>\SavedVariables\Flow.lua)
  -DryRun   say what would change, write nothing
  -Out      write somewhere else than Learned\Places.lua (tests)

  Then commit Learned\Places.lua and open a pull request: docs/SHARE-PLACES.md.
#>
param(
    [string]$WowDir,
    [string]$Account,
    [string]$From,
    [string]$Out,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$inv = [System.Globalization.CultureInfo]::InvariantCulture
if (-not $Out) { $Out = Join-Path $root 'Learned\Places.lua' }

# --- The saved data -----------------------------------------------------------
if (-not $From) {
    . (Join-Path $PSScriptRoot 'Common.ps1')
    if (-not $WowDir) { $WowDir = Find-WowDir }
    if (-not $WowDir) { Write-Host "Can't find your WoW: Forever folder. Pass -WowDir, or -From <Flow.lua>."; exit 1 }
    if (-not $Account) { $Account = Find-WowAccount $WowDir }
    if (-not $Account) { Write-Host "No Flow saved data under $WowDir yet. /reload in game first, or pass -Account."; exit 1 }
    $From = Join-Path $WowDir "WTF\Account\$Account\SavedVariables\Flow.lua"
}
if (-not (Test-Path $From)) { Write-Host "No saved data at $From."; exit 1 }
$text = Get-Content $From -Raw

# A ["name"] = { ... } table in $src (the first one), without its braces.
function Get-Block([string]$src, [string]$name) {
    $m = [regex]::Match($src, '\["' + $name + '"\]\s*=\s*\{')
    if (-not $m.Success) { return $null }
    $i = $m.Index + $m.Length; $depth = 1
    while ($i -lt $src.Length -and $depth -gt 0) {
        $ch = $src[$i]
        if ($ch -eq '"') { $i++; while ($i -lt $src.Length -and $src[$i] -ne '"') { if ($src[$i] -eq '\') { $i++ }; $i++ } }
        elseif ($ch -eq '{') { $depth++ } elseif ($ch -eq '}') { $depth-- }
        $i++
    }
    return $src.Substring($m.Index + $m.Length, $i - ($m.Index + $m.Length) - 1)
}
function Get-LuaList([string]$body) {
    [regex]::Matches($body, '"((?:[^"\\]|\\.)*)",') | ForEach-Object { $_.Groups[1].Value -replace '\\"', '"' -replace '\\\\', '\' }
}

$share = Get-Block $text 'share'
$list = if ($share) { Get-Block $share 'places' } else { $null }
if (-not $list) {
    Write-Host "Nothing shared in $From."
    Write-Host "In game: /flow places share, then /reload (the game saves the list on /reload), then run this again."
    exit 1
}
$lines = @(Get-LuaList $list)

# --- Reading and checking the shared lines -----------------------------------
$RoleNames = @('vendor', 'repair', 'trainer', 'flight', 'inn', 'bank', 'auction', 'quest')
function Test-Coord([string]$s) {
    $v = 0.0
    if (-not [double]::TryParse($s, [System.Globalization.NumberStyles]::Float, $inv, [ref]$v)) { return $null }
    if ($v -lt 0 -or $v -gt 1) { return $null }
    return [math]::Round($v, 4)
}
function Join-Factions([string]$a, [string]$b) {
    $s = "$a$b"
    return (($(if ($s -match 'A') { 'A' } else { '' })) + ($(if ($s -match 'H') { 'H' } else { '' })))
}

$incoming = @{}; $inMail = New-Object System.Collections.ArrayList; $bad = 0
foreach ($l in $lines) {
    $f = $l -split '\|'
    if ($f[0] -eq 'P' -and $f.Count -eq 8) {
        $name = $f[1]
        # A name: printable, no quotes or backslashes, not too long (it goes into Lua code).
        if ($name.Length -lt 1 -or $name.Length -gt 64 -or $name -match '[\x00-\x1f"\\]') { $bad++; continue }
        $map = 0
        if (-not [int]::TryParse($f[3], [ref]$map) -or $map -le 0) { $bad++; continue }
        $x = Test-Coord $f[4]; $y = Test-Coord $f[5]
        if ($null -eq $x -or $null -eq $y) { $bad++; continue }
        $roles = @($f[6] -split ',' | Where-Object { $RoleNames -contains $_ })
        if ($roles.Count -eq 0) { $bad++; continue }
        $id = 0; [void][int]::TryParse($f[2], [ref]$id)
        $fac = Join-Factions $f[7] ''
        $incoming[$name] = @{ id = $id; map = $map; x = $x; y = $y; roles = $roles; f = $fac }
    } elseif ($f[0] -eq 'M' -and $f.Count -eq 4) {
        $map = 0
        if (-not [int]::TryParse($f[1], [ref]$map) -or $map -le 0) { $bad++; continue }
        $x = Test-Coord $f[2]; $y = Test-Coord $f[3]
        if ($null -eq $x -or $null -eq $y) { $bad++; continue }
        [void]$inMail.Add(@{ map = $map; x = $x; y = $y })
    } else { $bad++ }
}

# --- What Flow already ships --------------------------------------------------
$npcs = @{}; $mail = New-Object System.Collections.ArrayList
if (Test-Path $Out) {
    foreach ($l in (Get-Content $Out)) {
        $m = [regex]::Match($l, '^\s*\["((?:[^"\\]|\\.)*)"\] = \{(.*)\},\s*$')
        if ($m.Success) {
            $body = $m.Groups[2].Value
            $get = { param($k, $pat) $mm = [regex]::Match($body, "\b$k = $pat"); if ($mm.Success) { $mm.Groups[1].Value } else { $null } }
            $name = $m.Groups[1].Value -replace '\\"', '"' -replace '\\\\', '\'
            $idS = & $get 'id' '(\d+)'
            $npcs[$name] = @{
                id = $(if ($idS) { [int]$idS } else { 0 })
                map = [int](& $get 'map' '(\d+)')
                x = [double]::Parse((& $get 'x' '([\d.]+)'), $inv)
                y = [double]::Parse((& $get 'y' '([\d.]+)'), $inv)
                roles = @(((& $get 'roles' '"([^"]*)"') -split ',') | Where-Object { $_ })
                f = [string](& $get 'f' '"([A-Z]*)"')
            }
            continue
        }
        $mm = [regex]::Match($l, '^\s*\{ map = (\d+), x = ([\d.]+), y = ([\d.]+) \},\s*$')
        if ($mm.Success) {
            [void]$mail.Add(@{ map = [int]$mm.Groups[1].Value; x = [double]::Parse($mm.Groups[2].Value, $inv); y = [double]::Parse($mm.Groups[3].Value, $inv) })
        }
    }
}

# --- Merge: new NPCs added; known ones only gain roles, factions, an ID ------
# (Where they stand stays as first shared, so it doesn't flip between players.)
$added = 0; $updated = 0; $mailAdded = 0
foreach ($name in $incoming.Keys) {
    $n = $incoming[$name]
    if (-not $npcs.ContainsKey($name)) { $npcs[$name] = $n; $added++; continue }
    $o = $npcs[$name]
    $roles = @($RoleNames | Where-Object { ($o.roles -contains $_) -or ($n.roles -contains $_) })
    $fac = Join-Factions $o.f $n.f
    $id = $(if ($o.id) { $o.id } else { $n.id })
    if (($roles -join ',') -ne (@($RoleNames | Where-Object { $o.roles -contains $_ }) -join ',') -or $fac -ne $o.f -or $id -ne $o.id) {
        $o.roles = $roles; $o.f = $fac; $o.id = $id; $updated++
    }
}
foreach ($b in $inMail) {
    $near = $mail | Where-Object { $_.map -eq $b.map -and [math]::Abs($_.x - $b.x) -lt 0.01 -and [math]::Abs($_.y - $b.y) -lt 0.01 }
    if (-not $near) { [void]$mail.Add($b); $mailAdded++ }
}

Write-Host ("From {0}: {1} spots shared ({2} skipped as not valid)." -f $From, $lines.Count, $bad)
Write-Host ("Learned\Places.lua: {0} NPCs added, {1} updated, {2} mailboxes added; {3} NPCs and {4} mailboxes in all." -f $added, $updated, $mailAdded, $npcs.Count, $mail.Count)
if ($added + $updated + $mailAdded -eq 0) { Write-Host "Nothing new: Flow already has all of these."; exit 0 }
if ($DryRun) { Write-Host "(dry run: nothing written)"; exit 0 }

# --- Write it (sorted, so the same data always gives the same file) ----------
function Format-Num([double]$v) { return $v.ToString('0.0000', $inv) }
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('-- GENERATED by tools/share-places.ps1 from spots Flow players shared')
[void]$sb.AppendLine('-- (/flow places share; docs/SHARE-PLACES.md). Do not edit by hand: run the')
[void]$sb.AppendLine('-- script. NPCs only: name, NPC ID, where, what they do (roles), and which')
[void]$sb.AppendLine('-- faction used them (f: H, A or AH). Nothing about the players.')
[void]$sb.AppendLine('local _, ns = ...')
[void]$sb.AppendLine('ns:Register("sharedPlaces", "community", {')
[void]$sb.AppendLine('    npcs = {')
foreach ($name in ($npcs.Keys | Sort-Object { $_ } -Culture $inv)) {
    $n = $npcs[$name]
    $esc = $name -replace '\\', '\\' -replace '"', '\"'
    $idPart = $(if ($n.id) { "id = $($n.id), " } else { '' })
    [void]$sb.AppendLine(('        ["{0}"] = {{ {1}map = {2}, x = {3}, y = {4}, roles = "{5}", f = "{6}" }},' -f
        $esc, $idPart, $n.map, (Format-Num $n.x), (Format-Num $n.y), ($n.roles -join ','), $n.f))
}
[void]$sb.AppendLine('    },')
[void]$sb.AppendLine('    mailboxes = {')
foreach ($b in ($mail | Sort-Object { $_.map }, { $_.x }, { $_.y })) {
    [void]$sb.AppendLine(('        {{ map = {0}, x = {1}, y = {2} }},' -f $b.map, (Format-Num $b.x), (Format-Num $b.y)))
}
[void]$sb.AppendLine('    },')
[void]$sb.AppendLine('})')
[IO.File]::WriteAllText($Out, $sb.ToString().Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
Write-Host "Written: $Out"
Write-Host "Next: commit it and open a pull request (docs/SHARE-PLACES.md). Data-only pull requests need no version bump or CHANGELOG entry."
