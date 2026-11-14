<#
.SYNOPSIS
  Merges the game facts a Flow player chose to share (in game: /flow places
  share, then /reload) into Learned\Facts.lua, the shared list that comes
  with Flow. A pull request then brings it to every Flow player.

  What's shared: game facts only.
    S  what a class trainer lists: class, spell, rank, the level it asks, its price
    L  a spell of Flow's class list that no trainer had up to a level
    Q  where a quest's objective was done or the quest handed in (quest number, map spot)
  Nothing about the player.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\share-facts.ps1
      your own saved data (WoW folder and account found by themselves)
  powershell -ExecutionPolicy Bypass -File tools\share-facts.ps1 -From <path\to\Flow.lua>
      someone else's saved data (WTF\Account\<name>\SavedVariables\Flow.lua)
  -DryRun   say what would change, write nothing
  -Out      write somewhere else than Learned\Facts.lua (tests)

  Then commit Learned\Facts.lua and open a pull request: docs/SHARE-PLACES.md.
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
if (-not $Out) { $Out = Join-Path $root 'Learned\Facts.lua' }

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
$list = if ($share) { Get-Block $share 'facts' } else { $null }
if (-not $list) {
    Write-Host "No game facts shared in $From."
    Write-Host "In game: /flow places share, then /reload (the game saves the list on /reload), then run this again."
    exit 1
}
$lines = @(Get-LuaList $list)

# --- Reading and checking the shared lines -----------------------------------
# A name that goes into Lua code: printable, no quotes or backslashes, not too long.
function Test-Name([string]$s) { return ($s.Length -ge 1 -and $s.Length -le 64 -and $s -notmatch '[\x00-\x1f"\\|]') }
function Test-Class([string]$s) { return ($s -cmatch '^[A-Z]{3,12}$') }
function Test-Coord([string]$s) {
    $v = 0.0
    if (-not [double]::TryParse($s, [System.Globalization.NumberStyles]::Float, $inv, [ref]$v)) { return $null }
    if ($v -lt 0 -or $v -gt 1) { return $null }
    return [math]::Round($v, 4)
}

$inSpells = @{}; $inLacks = @{}; $inSpots = @{}; $bad = 0
foreach ($l in $lines) {
    $f = $l -split '\|'
    if ($f[0] -eq 'S' -and $f.Count -eq 6) {
        $level = 0; $cost = 0
        if (-not (Test-Class $f[1]) -or -not (Test-Name $f[2]) -or ($f[3] -ne '' -and -not (Test-Name $f[3])) `
            -or -not [int]::TryParse($f[4], [ref]$level) -or -not [int]::TryParse($f[5], [ref]$cost) `
            -or $level -lt 0 -or $level -gt 80 -or $cost -lt 0) { $bad++; continue }
        $key = $f[1] + '|' + $f[2] + '|' + $f[3]
        $inSpells[$key] = @{ class = $f[1]; name = $f[2]; rank = $f[3]; level = $level; cost = $cost }
    } elseif ($f[0] -eq 'L' -and $f.Count -eq 4) {
        $level = 0
        if (-not (Test-Class $f[1]) -or -not (Test-Name $f[2]) -or -not [int]::TryParse($f[3], [ref]$level) -or $level -lt 1 -or $level -gt 80) { $bad++; continue }
        $inLacks[$f[1] + '|' + $f[2]] = @{ class = $f[1]; name = $f[2]; level = $level }
    } elseif ($f[0] -eq 'Q' -and $f.Count -eq 6) {
        $quest = 0; $map = 0
        if (-not [int]::TryParse($f[1], [ref]$quest) -or $quest -le 0 -or -not [int]::TryParse($f[3], [ref]$map) -or $map -le 0) { $bad++; continue }
        if ($f[2] -ne 'done' -and $f[2] -notmatch '^\d{1,2}$') { $bad++; continue }
        $x = Test-Coord $f[4]; $y = Test-Coord $f[5]
        if ($null -eq $x -or $null -eq $y) { $bad++; continue }
        $key = "$quest|$($f[2])"
        if (-not $inSpots.ContainsKey($key)) { $inSpots[$key] = New-Object System.Collections.ArrayList }
        [void]$inSpots[$key].Add(@{ map = $map; x = $x; y = $y })
    } else { $bad++ }
}

# --- What Flow already ships --------------------------------------------------
$spells = @{}; $lacks = @{}; $spots = @{}
if (Test-Path $Out) {
    foreach ($l in (Get-Content $Out)) {
        $m = [regex]::Match($l, '^\s*-- S\|([A-Z]+)\|([^|]*)\|([^|]*)\|(\d+)\|(\d+)\s*$')
        if ($m.Success) {
            $spells[$m.Groups[1].Value + '|' + $m.Groups[2].Value + '|' + $m.Groups[3].Value] = @{
                class = $m.Groups[1].Value; name = $m.Groups[2].Value; rank = $m.Groups[3].Value
                level = [int]$m.Groups[4].Value; cost = [int]$m.Groups[5].Value }
            continue
        }
        $m = [regex]::Match($l, '^\s*-- L\|([A-Z]+)\|([^|]*)\|(\d+)\s*$')
        if ($m.Success) {
            $lacks[$m.Groups[1].Value + '|' + $m.Groups[2].Value] = @{ class = $m.Groups[1].Value; name = $m.Groups[2].Value; level = [int]$m.Groups[3].Value }
            continue
        }
        $m = [regex]::Match($l, '^\s*-- Q\|(\d+)\|(\w+)\|(\d+)\|([\d.]+)\|([\d.]+)\s*$')
        if ($m.Success) {
            $key = $m.Groups[1].Value + '|' + $m.Groups[2].Value
            if (-not $spots.ContainsKey($key)) { $spots[$key] = New-Object System.Collections.ArrayList }
            [void]$spots[$key].Add(@{ map = [int]$m.Groups[3].Value; x = [double]::Parse($m.Groups[4].Value, $inv); y = [double]::Parse($m.Groups[5].Value, $inv) })
        }
    }
}

# --- Merge --------------------------------------------------------------------
# A trainer line: the lowest level and price seen win. A lack: the highest
# level seen; dropped once any trainer lists the spell. A spot: added unless
# one is already right there, at most six per objective.
$added = 0; $updated = 0
foreach ($key in $inSpells.Keys) {
    $n = $inSpells[$key]
    if (-not $spells.ContainsKey($key)) { $spells[$key] = $n; $added++; continue }
    $o = $spells[$key]
    $changed = $false
    if ($n.level -gt 0 -and ($o.level -eq 0 -or $n.level -lt $o.level)) { $o.level = $n.level; $changed = $true }
    if ($n.cost -gt 0 -and ($o.cost -eq 0 -or $n.cost -lt $o.cost)) { $o.cost = $n.cost; $changed = $true }
    if ($changed) { $updated++ }
}
foreach ($key in $inLacks.Keys) {
    $n = $inLacks[$key]
    if (-not $lacks.ContainsKey($key)) { $lacks[$key] = $n; $added++ }
    elseif ($n.level -gt $lacks[$key].level) { $lacks[$key].level = $n.level; $updated++ }
}
$taught = @{}
foreach ($s in $spells.Values) { $taught[$s.class + '|' + $s.name] = $true }
foreach ($key in @($lacks.Keys)) { if ($taught.ContainsKey($key)) { $lacks.Remove($key); $updated++ } }
foreach ($key in $inSpots.Keys) {
    if (-not $spots.ContainsKey($key)) { $spots[$key] = New-Object System.Collections.ArrayList }
    foreach ($p in $inSpots[$key]) {
        $near = $spots[$key] | Where-Object { $_.map -eq $p.map -and [math]::Abs($_.x - $p.x) -lt 0.02 -and [math]::Abs($_.y - $p.y) -lt 0.02 }
        if (-not $near -and $spots[$key].Count -lt 6) { [void]$spots[$key].Add($p); $added++ }
    }
}

$spotCount = 0
foreach ($v in $spots.Values) { $spotCount += $v.Count }
Write-Host ("From {0}: {1} facts shared ({2} skipped as not valid)." -f $From, $lines.Count, $bad)
Write-Host ("Learned\Facts.lua: {0} added, {1} updated; {2} trainer lines, {3} missing spells and {4} quest spots in all." -f $added, $updated, $spells.Count, $lacks.Count, $spotCount)
if ($added + $updated -eq 0) { Write-Host "Nothing new: Flow already has all of these."; exit 0 }
if ($DryRun) { Write-Host "(dry run: nothing written)"; exit 0 }

# --- Write it (sorted, so the same data always gives the same file) ----------
# Each fact is written twice: as a "-- S|..." comment line this script reads
# back, and as the Lua the game loads.
function Format-Num([double]$v) { return $v.ToString('0.0000', $inv) }
function Sorted($keys) { return @($keys | Sort-Object { $_ } -Culture $inv) }
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('-- GENERATED by tools/share-facts.ps1 from game facts Flow players shared')
[void]$sb.AppendLine('-- (/flow places share; docs/SHARE-PLACES.md). Do not edit by hand: run the')
[void]$sb.AppendLine('-- script. Game facts only: what class trainers teach (spell, rank, level,')
[void]$sb.AppendLine('-- price), spells they don''t have, and where quests were done. Nothing about')
[void]$sb.AppendLine('-- the players.')
foreach ($key in (Sorted $spells.Keys)) { $s = $spells[$key]; [void]$sb.AppendLine(('-- S|{0}|{1}|{2}|{3}|{4}' -f $s.class, $s.name, $s.rank, $s.level, $s.cost)) }
foreach ($key in (Sorted $lacks.Keys)) { $s = $lacks[$key]; [void]$sb.AppendLine(('-- L|{0}|{1}|{2}' -f $s.class, $s.name, $s.level)) }
foreach ($key in (Sorted $spots.Keys)) {
    $parts = $key -split '\|'
    foreach ($p in $spots[$key]) { [void]$sb.AppendLine(('-- Q|{0}|{1}|{2}|{3}|{4}' -f $parts[0], $parts[1], $p.map, (Format-Num $p.x), (Format-Num $p.y))) }
}
[void]$sb.AppendLine('local _, ns = ...')
[void]$sb.AppendLine('ns:Register("sharedFacts", "community", {')
[void]$sb.AppendLine('    spells = {')
$classes = Sorted (@($spells.Values | ForEach-Object { $_.class }) | Select-Object -Unique)
foreach ($class in $classes) {
    [void]$sb.AppendLine("        $class = {")
    foreach ($key in (Sorted ($spells.Keys | Where-Object { $spells[$_].class -eq $class }))) {
        $s = $spells[$key]
        $luaKey = $(if ($s.rank) { "$($s.name) ($($s.rank))" } else { $s.name })
        $rankPart = $(if ($s.rank) { ", rank = `"$($s.rank)`"" } else { '' })
        [void]$sb.AppendLine(('            ["{0}"] = {{ name = "{1}"{2}, level = {3}, cost = {4} }},' -f $luaKey, $s.name, $rankPart, $s.level, $s.cost))
    }
    [void]$sb.AppendLine('        },')
}
[void]$sb.AppendLine('    },')
[void]$sb.AppendLine('    lacks = {')
$classes = Sorted (@($lacks.Values | ForEach-Object { $_.class }) | Select-Object -Unique)
foreach ($class in $classes) {
    [void]$sb.AppendLine("        $class = {")
    foreach ($key in (Sorted ($lacks.Keys | Where-Object { $lacks[$_].class -eq $class }))) {
        $s = $lacks[$key]
        [void]$sb.AppendLine(('            ["{0}"] = {1},' -f $s.name, $s.level))
    }
    [void]$sb.AppendLine('        },')
}
[void]$sb.AppendLine('    },')
[void]$sb.AppendLine('    spots = {')
$quests = @($spots.Keys | ForEach-Object { [int](($_ -split '\|')[0]) } | Sort-Object -Unique)
foreach ($quest in $quests) {
    [void]$sb.AppendLine("        [$quest] = {")
    foreach ($key in (Sorted ($spots.Keys | Where-Object { ($_ -split '\|')[0] -eq "$quest" }))) {
        $index = ($key -split '\|')[1]
        $luaIndex = $(if ($index -eq 'done') { 'done' } else { "[$index]" })
        $pts = @($spots[$key] | ForEach-Object { '{{ {0}, {1}, {2} }}' -f $_.map, (Format-Num $_.x), (Format-Num $_.y) }) -join ', '
        [void]$sb.AppendLine("            $luaIndex = { $pts },")
    }
    [void]$sb.AppendLine('        },')
}
[void]$sb.AppendLine('    },')
[void]$sb.AppendLine('})')
[IO.File]::WriteAllText($Out, $sb.ToString().Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
Write-Host "Written: $Out"
Write-Host "Next: commit it and open a pull request (docs/SHARE-PLACES.md). Data-only pull requests need no version bump or CHANGELOG entry."
