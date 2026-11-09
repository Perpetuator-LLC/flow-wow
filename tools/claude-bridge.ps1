<#
.SYNOPSIS
  Talk to Claude from inside WoW, and keep Flow up to date by itself.
  See docs/ASK-CLAUDE.md for setup.

  In game:  /si make the arrow green
  Flow shows the message for a moment as black and white squares (a code)
  and takes a screenshot, which WoW writes to _forever_\Screenshots at once:
  no reload. (Flow keeps it in its saved data too, written at the next
  reload.) This script decodes the screenshot (then deletes it), waits for
  Flow's saved data to change too (file-change events, no polling), and
  prints each new message as one line:
      ASK 3 | Sooth (DRUID 5, Mulgore) | make the arrow green
  While it runs it also writes "connected" into Learned\ClaudeInbox.lua
  (ns.claudeBridge.at, every 10 minutes): /si in game shows the chat when it
  was there at the last reload, else a prompt to connect Claude.
  A Claude session in Claude desktop (or any Claude Code) watches those lines
  with its Monitor tool, does what's asked, and answers with
      tools\claude-bridge.ps1 -Reply 3 -Text "Done: green arrow. Type /reload."
  which writes Learned\ClaudeInbox.lua. /claude in game (a reload) shows the
  answer, together with any change Claude made to Flow.

  Each time WoW saves, it also checks GitHub: a clean checkout on `main`
  fast-forwards to the newest Flow and tells you in game ("/reload to load
  it"), printing an UPDATE line. A checkout on another branch, or with changes
  of its own, is never touched.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\claude-bridge.ps1 [options]
    (no options)        listen: print ASK / UPDATE lines, keep Flow up to date
    -Reply ID -Text T   answer message ID (shown in game after /reload), then exit
    -Note T             tell the player something (no message to answer), then exit
    -NoAsk              only keep Flow up to date (no ASK lines)
    -NoUpdate           only pass messages on
    -Cli                answer by itself with the `claude` command line (Claude
                        Code), no session watching: -Permission acceptEdits|bypassPermissions
    -AddonDir PATH      your AddOns\Flow folder, when it isn't a link to this repo
    -SelfTest           check the file reading and writing on samples, then exit
#>
param(
    [string]$WowDir,
    [string]$Account,
    [string]$AddonDir,
    [int]$Reply,
    [string]$Text,
    [string]$Note,
    [switch]$NoAsk,
    [switch]$NoUpdate,
    [switch]$Cli,
    [string]$Claude,
    [string]$Permission = 'acceptEdits',
    [switch]$NoClaude,    # (older name for -NoAsk)
    [switch]$SelfTest
)
if ($NoClaude) { $NoAsk = $true }
# One event per line, out at once (a watching Claude session reads stdout).
function Emit([string]$line) { [Console]::Out.WriteLine($line); [Console]::Out.Flush() }
# UTF-8 out, so "é" in a message reaches the watching session as "é".
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch { }
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$repo = Split-Path $PSScriptRoot -Parent
if (-not $AddonDir) { $AddonDir = $repo }

$shotDir = $null
if ($SelfTest) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("flow-bridge-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Force (Join-Path $tmp 'Learned') | Out-Null
    $AddonDir = $tmp; $savedDir = $tmp; $saved = Join-Path $tmp 'Flow.lua'; $Cli = $false; $NoUpdate = $true
    $shotDir = $tmp
} elseif ($Reply -or $Note) {
    $savedDir = $null; $saved = $null   # (answering: only the answers file is needed)
} else {
    if (-not $WowDir) { $WowDir = Find-WowDir }
    if (-not $WowDir) { Write-Host "Can't find your WoW: Forever folder. Pass -WowDir or set FLOW_WOW_DIR."; exit 1 }
    if (-not $Account) { $Account = Find-WowAccount $WowDir }
    if (-not $Account) { Write-Host "No Flow saved data yet: log in once with Flow on, then start this again (or pass -Account)."; exit 1 }
    $savedDir = Join-Path $WowDir "WTF\Account\$Account\SavedVariables"
    $saved = Join-Path $savedDir 'Flow.lua'
    $shotDir = Join-Path $WowDir 'Screenshots'   # (Flow's coded screenshots: messages without a reload)
}

if ($Cli) {
    if (-not $Claude) { $Claude = $env:FLOW_CLAUDE }
    if (-not $Claude) { $c = Get-Command claude -ErrorAction SilentlyContinue; if ($c) { $Claude = $c.Source } }
    if (-not $Claude) {
        Write-Host "-Cli needs the 'claude' command line (Claude Code). Without -Cli, a Claude session watches this script instead (docs/ASK-CLAUDE.md)."
        exit 2
    }
}

$inboxFile = Join-Path $AddonDir 'Learned\ClaudeInbox.lua'
$stateDir = if ($SelfTest) { $AddonDir } else { Join-Path $repo 'reports' }
$stateFile = Join-Path $stateDir 'claude-bridge.json'
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force $stateDir | Out-Null }

# --- state: messages passed on / answered, the answers shown in game ---
# Read from disk before every change: the listener and -Reply run as two
# processes and must not overwrite each other's answers.
$state = @{ answered = @(); delivered = @(); session = $null; replies = @(); nextId = 1 }
function Load-State {
    if (-not (Test-Path $stateFile)) { return }
    try {
        $s = Get-Content $stateFile -Raw | ConvertFrom-Json
        $state.answered = @($s.answered | Where-Object { $_ -ne $null })
        $state.delivered = @($s.delivered | Where-Object { $_ -ne $null })
        $state.session = $s.session
        $state.replies = @($s.replies | Where-Object { $_ } | ForEach-Object { @{ id = [int]$_.id; replyTo = $_.replyTo; at = [int]$_.at; text = [string]$_.text } })
        if ($s.nextId) { $state.nextId = [int]$s.nextId }
        $state.toldDirty = [bool]$s.toldDirty
        if ($s.deathsSeen) { $state.deathsSeen = [int]$s.deathsSeen }
        if ($s.bridgeAt) { $state.bridgeAt = [long]$s.bridgeAt }
    } catch { Write-Host "(couldn't read ${stateFile}: starting fresh)" }
}
Load-State
function Save-State { $state | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding utf8 }

# --- the answers file WoW reads on /reload ---
function Write-Inbox {
    $lines = @('-- GENERATED by tools/claude-bridge.ps1: answers to /claude and update notes. Not in git.',
               'local _, ns = ...', 'ns.claudeInbox = {')
    foreach ($r in ($state.replies | Select-Object -Last 20)) {
        $text = ([string]$r.text) -replace '\]==\]', '] ==]'
        $reply = if ($r.replyTo) { $r.replyTo } else { 'nil' }
        $lines += "    { id = $($r.id), replyTo = $reply, at = $($r.at), text = [==[$text]==] },"
    }
    $lines += '}'
    # When this script last ran: /si in game shows the chat (not the connect prompt).
    if ($state.bridgeAt) { $lines += "ns.claudeBridge = { at = $([long]$state.bridgeAt) }" }
    $dir = Split-Path $inboxFile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [IO.File]::WriteAllText($inboxFile, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
}
function Add-Reply([string]$text, $replyTo) {
    Load-State
    $state.replies = @($state.replies) + @(@{ id = $state.nextId; replyTo = $replyTo; at = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); text = $text })
    $state.nextId++
    if ($replyTo -and ($state.answered -notcontains [int]$replyTo)) { $state.answered = @($state.answered) + @([int]$replyTo) }
    Write-Inbox
    Save-State
}

# --- answering (a watching Claude session runs these) ---
if ($Reply -or $Note) {
    if ($Reply) {
        if (-not $Text) { Write-Host "-Reply needs -Text `"the answer`""; exit 1 }
        Add-Reply $Text $Reply
        Write-Host "Answer to message $Reply written. In game: /claude (it reloads) to see it."
    } else {
        Add-Reply $Note $null
        Write-Host "Note written. In game: /claude (it reloads) to see it."
    }
    exit 0
}

# --- reading /claude messages out of Flow's saved data ---
function Get-Block([string]$text, [string]$key) {
    # The { ... } after ["key"] = , braces inside strings ignored.
    $i = $text.IndexOf("[`"$key`"] = {")
    if ($i -lt 0) { return $null }
    $start = $text.IndexOf('{', $i)
    $depth = 0; $inStr = $false
    for ($j = $start; $j -lt $text.Length; $j++) {
        $ch = $text[$j]
        if ($inStr) {
            if ($ch -eq '\') { $j++ } elseif ($ch -eq '"') { $inStr = $false }
        } elseif ($ch -eq '"') { $inStr = $true }
        elseif ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($start, $j - $start + 1) } }
    }
    return $null
}
function Unescape-Lua([string]$s) {
    $s -replace '\\n', "`n" -replace '\\"', '"' -replace '\\\\', '\'
}
function Get-Outbox {
    if (-not (Test-Path $saved)) { return @() }
    $text = Get-Content $saved -Raw
    $chat = Get-Block $text 'chat'
    if (-not $chat) { return @() }
    $box = Get-Block $chat 'outbox'
    if (-not $box) { return @() }
    $out = @()
    foreach ($m in [regex]::Matches($box.Substring(1), '\{((?:[^{}"]|"(?:[^"\\]|\\.)*")*)\}')) {
        $body = $m.Groups[1].Value
        $get = { param($k) $x = [regex]::Match($body, "\[`"$k`"\]\s*=\s*(`"((?:[^`"\\]|\\.)*)`"|[\-\d\.]+)"); if ($x.Success) { if ($x.Groups[2].Success) { Unescape-Lua $x.Groups[2].Value } else { $x.Groups[1].Value } } }
        $id = & $get 'id'
        if ($id) {
            $out += @{ id = [int]$id; text = (& $get 'text'); char = (& $get 'char'); class = (& $get 'class');
                       level = (& $get 'level'); zone = (& $get 'zone') }
        }
    }
    return $out
}

# --- asking Claude Code ---
$maintainer = $false
Push-Location $repo
try { $maintainer = ((git rev-parse --abbrev-ref HEAD 2>$null) -ne 'main') -or ($env:FLOW_MAINTAINER -eq '1') } catch {}
Pop-Location

function Ask-Claude($msg) {
    $role = if ($maintainer) {
        "This is the maintainer's checkout: make the change the way CLAUDE.md says (test, lint, version bump, changelog, commit). Never push."
    } else {
        "This checkout follows the public repo on main: make the change in the files but don't commit, don't bump the version, never push. Say they can ask you to open a pull request later (CONTRIBUTING.md)."
    }
    $prompt = @"
A message typed in World of Warcraft through Flow's in-game chat (/claude). You're in the Flow addon's folder: read CLAUDE.md first.
$role
Your answer is shown in WoW's chat window: reply in at most 3 short sentences, plain text, no markdown. If they need to /reload (or restart WoW, for new files) to see a change, say so.
Player: $($msg.char) ($($msg.class), level $($msg.level), in $($msg.zone)).
Message: $($msg.text)
"@
    $cliArgs = @('-p', $prompt, '--output-format', 'json', '--permission-mode', $Permission)
    if ($state.session) { $cliArgs += @('--resume', $state.session) }
    Push-Location $repo
    try {
        $raw = (& $Claude @cliArgs 2>$null | Out-String)
    } finally { Pop-Location }
    try {
        $o = $raw | ConvertFrom-Json
        if ($o.session_id) { $state.session = $o.session_id }
        $text = [string]$o.result
    } catch { $text = $raw }
    if (-not $text -or -not $text.Trim()) { $text = "(no answer: is Claude Code logged in? Run 'claude' once on your PC.)" }
    ($text -replace '`', '' -replace '\*\*', '').Trim()
}

# --- deaths: Flow's death reports (FlowDB.deathReports), one DEATH line each ---
# "id|char|class|level|zone|summary || findings" (Engine.lua, PLAYER_DEAD).
function Get-Deaths {
    if (-not (Test-Path $saved)) { return @() }
    $text = Get-Content $saved -Raw
    $block = Get-Block $text 'deathReports'
    if (-not $block) { return @() }
    $out = @()
    foreach ($m in [regex]::Matches($block, '"((?:[^"\\]|\\.)*)"')) {
        $f = (Unescape-Lua $m.Groups[1].Value) -split '\|', 6
        if ($f.Count -eq 6 -and $f[0] -match '^\d+$') {
            $out += @{ id = [int]$f[0]; char = $f[1]; class = $f[2]; level = $f[3]; zone = $f[4]; text = $f[5] }
        }
    }
    return $out
}
function Handle-Deaths {
    if ($NoAsk -or $Cli) { return }
    Load-State
    $seen = if ($state.deathsSeen) { [int]$state.deathsSeen } else { 0 }
    $new = @(Get-Deaths | Where-Object { $_.id -gt $seen } | Sort-Object { $_.id })
    foreach ($d in $new) {
        # For the watching Claude session: a post-mortem to do (CLAUDE.md).
        Emit ("DEATH {0} | {1} ({2} {3}, {4}) | {5}" -f $d.id, $d.char, $d.class, $d.level, $d.zone, $d.text)
        $seen = [math]::Max($seen, $d.id)
    }
    if ($new.Count -gt 0) { $state.deathsSeen = $seen; Save-State }
}

# One message, from either path (saved data or chat log): passed on once.
function Deliver($m) {
    Load-State
    if ($state.answered -contains $m.id -or $state.delivered -contains $m.id) { return }
    $state.delivered = @($state.delivered) + @($m.id)
    Save-State
    if ($Cli) {
        Write-Host ("[{0}] WoW > {1}" -f (Get-Date -Format HH:mm:ss), $m.text)
        $reply = Ask-Claude $m
        Write-Host ("[{0}] Claude > {1}" -f (Get-Date -Format HH:mm:ss), $reply)
        Add-Reply $reply $m.id
    } else {
        # For the watching Claude session: one line per message.
        $who = "{0} ({1} {2}, {3})" -f $m.char, $m.class, $m.level, $m.zone
        Emit ("ASK {0} | {1} | {2}" -f $m.id, $who, (($m.text -replace "`r?`n", ' ')))
    }
}

function Handle-Messages {
    Handle-Deaths
    if ($NoAsk) { return }
    foreach ($m in (Get-Outbox)) { Deliver $m }
}

# --- messages sent without a reload: Flow's coded screenshots ---
# WoW never lets an add-on write a file while it runs (and WoW: Forever writes
# its chat log only when the game closes), but it writes a screenshot at once. Flow
# (AskClaude.lua, AC:ShowCode) draws the message as black and white squares
# in a white box at the screen's top left, takes a screenshot and hides them.
# Read in rows of `cols` squares from the box's first square: 16 magic
# squares, three 16-bit numbers (columns, length in bytes, checksum = the
# bytes summed mod 65536), then the bytes; most significant bit first,
# 1 = black. One more black square sits in row 0 at column cols+1 (white
# either side), to measure the square size on a scaled screenshot. The bytes:
# "FLOW1|<id>|<char;class;level;zone>|<text>" (UTF-8).
$FlowMagic = @(1, 0, 1, 1, 0, 0, 1, 0, 1, 1, 1, 0, 0, 1, 0, 1)
$FlowCell = 12

# A screenshot as { w, h, stride, bpp, px } (rows top-down, blue-green-red).
function Get-Image([string]$path) {
    $bytes = $null
    for ($try = 0; $try -lt 15; $try++) {   # WoW may still be writing it
        try { $bytes = [IO.File]::ReadAllBytes($path); if ($bytes.Length -gt 0) { break } } catch { }
        Start-Sleep -Milliseconds 200
    }
    if (-not $bytes -or $bytes.Length -lt 18) { return $null }
    if ($path -match '\.tga$') { return (Get-Tga $bytes) }
    Add-Type -AssemblyName System.Drawing
    $ms = New-Object IO.MemoryStream (, $bytes)
    try {
        $src = [System.Drawing.Image]::FromStream($ms)
        $bmp = New-Object System.Drawing.Bitmap $src
        $src.Dispose()
        $rect = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height
        $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $px = New-Object byte[] ($data.Stride * $bmp.Height)
        [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $px, 0, $px.Length)
        $im = @{ w = $bmp.Width; h = $bmp.Height; stride = $data.Stride; bpp = 3; px = $px }
        $bmp.UnlockBits($data); $bmp.Dispose()
        return $im
    } catch { return $null } finally { $ms.Dispose() }
}
# Uncompressed true-colour TGA (WoW's other screenshot format).
function Get-Tga([byte[]]$b) {
    if ($b[2] -ne 2 -or ($b[16] -ne 24 -and $b[16] -ne 32)) { return $null }
    $w = $b[12] + 256 * $b[13]; $h = $b[14] + 256 * $b[15]; $bpp = $b[16] / 8
    $top = ($b[17] -band 32) -ne 0
    $off = 18 + $b[0]; $stride = $w * $bpp
    if ($b.Length -lt $off + $stride * $h) { return $null }
    $px = New-Object byte[] ($stride * $h)
    for ($y = 0; $y -lt $h; $y++) {
        $sy = if ($top) { $y } else { $h - 1 - $y }
        [Array]::Copy($b, $off + $sy * $stride, $px, $y * $stride, $stride)
    }
    return @{ w = $w; h = $h; stride = $stride; bpp = $bpp; px = $px }
}
function Lum($im, [int]$x, [int]$y) {
    if ($x -lt 0 -or $y -lt 0 -or $x -ge $im.w -or $y -ge $im.h) { return 255 }
    $i = $y * $im.stride + $x * $im.bpp
    return ([int]$im.px[$i] + [int]$im.px[$i + 1] + [int]$im.px[$i + 2]) / 3
}
# Black square at this point? (Its centre and a little either side.)
function Dark($im, [double]$x, [double]$y) {
    $xi = [int][math]::Round($x); $yi = [int][math]::Round($y)
    return ((Lum $im $xi $yi) + (Lum $im ($xi - 2) $yi) + (Lum $im ($xi + 2) $yi)) / 3 -lt 128
}

# The message in a screenshot: $null (not Flow's), @{ error = "..." }, or
# @{ msg = @{ id, text, char, class, level, zone } }.
function Read-FlowCode($im) {
    # The first square (black) is the first dark point on the diagonal from
    # the top left; its edges are where the dark ends going left and up.
    $lim = [math]::Min(400, [math]::Min($im.w, $im.h) - 1)
    $d = -1
    for ($i = 0; $i -lt $lim; $i++) { if ((Lum $im $i $i) -lt 128) { $d = $i; break } }
    if ($d -lt 0) { return $null }
    $x0 = $d; while ($x0 -gt 0 -and (Lum $im ($x0 - 1) $d) -lt 128) { $x0-- }
    $y0 = $d; while ($y0 -gt 0 -and (Lum $im $d ($y0 - 1)) -lt 128) { $y0-- }
    # The magic row: its colour changes at these squares (the 16th: the
    # header's first square is always white).
    $edges = @(1, 2, 4, 6, 7, 8, 11, 13, 14, 15, 16)
    $run = 0; while ($run -lt 80 -and (Lum $im ($x0 + $run) ($y0 + 2)) -lt 128) { $run++ }
    if ($run -lt 4 -or $run -ge 80) { return $null }
    $y = $y0 + [int]($run / 2)
    $found = @(); $was = $true
    for ($x = $x0; $x -lt [math]::Min($im.w, $x0 + 20 * $run + 10) -and $found.Count -lt $edges.Count; $x++) {
        $now = (Lum $im $x $y) -lt 128
        if ($now -ne $was) { $found += $x; $was = $now }
    }
    if ($found.Count -lt $edges.Count) { return $null }
    $cell = ($found[-1] - $x0) / 16.0
    for ($k = 0; $k -lt $edges.Count; $k++) {
        if ([math]::Abs($found[$k] - ($x0 + $edges[$k] * $cell)) -gt $cell / 3) { return $null }   # not Flow's magic
    }
    if ([math]::Abs($cell - $FlowCell) -lt 0.3) { $cell = [double]$FlowCell }   # (a screenshot at screen size)
    $bit = { param($k, $cols, $c) $r = [math]::Floor($k / $cols); $col = $k % $cols
             if (Dark $im ($x0 + ($col + 0.5) * $c) ($y0 + ($r + 0.5) * $c)) { 1 } else { 0 } }
    $num = { param($from, $c) $n = 0; for ($k = $from; $k -lt $from + 16; $k++) { $n = $n * 2 + (& $bit $k 100000 $c) }; $n }
    $cols = & $num 16 $cell
    if ($cols -lt 64 -or $cols -gt 400) { return @{ error = "columns $cols" } }
    # Scaled: measure the square size from the end square (row 0, column cols+1).
    if ($cell -ne $FlowCell) {
        $ex = $x0 + ($cols + 1.5) * $cell
        $best = $null
        for ($x = [int]($ex - 2 * $cell); $x -le [int]($ex + 2 * $cell); $x++) {
            if ((Lum $im $x $y) -lt 128 -and (Lum $im ($x - 1) $y) -ge 128) {
                if ($null -eq $best -or [math]::Abs($x - ($ex - $cell / 2)) -lt [math]::Abs($best - ($ex - $cell / 2))) { $best = $x }
            }
        }
        if ($null -ne $best) { $cell = ($best - $x0) / ($cols + 1.0) }
    }
    $len = & $num 32 $cell
    $sum = & $num 48 $cell
    if ($len -lt 1 -or $len -gt 8000) { return @{ error = "length $len" } }
    $bytes = New-Object byte[] $len
    $total = 0
    for ($i = 0; $i -lt $len; $i++) {
        $v = 0
        for ($b = 0; $b -lt 8; $b++) { $v = $v * 2 + (& $bit (64 + $i * 8 + $b) $cols $cell) }
        $bytes[$i] = $v; $total = ($total + $v) % 65536
    }
    if ($total -ne $sum) { return @{ error = "checksum $total, not $sum" } }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $x = [regex]::Match($text, '(?s)^FLOW1\|(\d+)\|([^|]*)\|(.*)$')
    if (-not $x.Success) { return @{ error = "not a Flow message" } }
    $f = @($x.Groups[2].Value -split ';', 4) + @('', '', '', '')
    return @{ msg = @{ id = [int]$x.Groups[1].Value; text = $x.Groups[3].Value; char = $f[0]; class = $f[1]; level = $f[2]; zone = $f[3] } }
}

# A new screenshot: Flow's? Pass the message on and delete the screenshot
# (Flow's own, taken to carry it). Anyone else's screenshot is left alone.
$shotsSeen = @{}
function Handle-Screenshot([string]$path) {
    if ($NoAsk -or $shotsSeen.ContainsKey($path) -or $path -notmatch '\.(jpe?g|tga|png)$') { return }
    $shotsSeen[$path] = $true
    $im = Get-Image $path
    if (-not $im) { return }
    $r = Read-FlowCode $im
    if (-not $r) { return }
    if ($r.error) { Emit "INFO a Flow screenshot couldn't be read ($($r.error)), kept: $path"; return }
    Deliver $r.msg
    Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
}

# (Self-test) Flow's code drawn into a JPEG the way AC:ShowCode draws it:
# white box, squares from (2, 2) squares in, the end square at column cols+1.
function Get-FlowBits([byte[]]$payload, [int]$cols) {
    $bits = New-Object System.Collections.Generic.List[int]
    foreach ($b in $FlowMagic) { $bits.Add($b) }
    $sum = 0; foreach ($v in $payload) { $sum = ($sum + $v) % 65536 }
    foreach ($n in @($cols, $payload.Length, $sum)) { for ($b = 15; $b -ge 0; $b--) { $bits.Add(($n -shr $b) -band 1) } }
    foreach ($v in $payload) { for ($b = 7; $b -ge 0; $b--) { $bits.Add(($v -shr $b) -band 1) } }
    return , $bits
}
function New-FlowCodeImage([string]$path, [string]$payload, [int]$cell, [int]$w, [int]$h, [int]$quality) {
    Add-Type -AssemblyName System.Drawing
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $cols = [math]::Min(240, [math]::Floor($w / $cell) - 6)
    $bits = Get-FlowBits $bytes $cols
    $rows = [math]::Ceiling($bits.Count / $cols)
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(70, 90, 60))      # the game behind it
    $g.FillRectangle([System.Drawing.Brushes]::White, 0, 0, ($cols + 6) * $cell, ($rows + 4) * $cell)
    for ($k = 0; $k -lt $bits.Count; $k++) {
        if ($bits[$k]) { $g.FillRectangle([System.Drawing.Brushes]::Black, (2 + $k % $cols) * $cell, (2 + [math]::Floor($k / $cols)) * $cell, $cell, $cell) }
    }
    $g.FillRectangle([System.Drawing.Brushes]::Black, (2 + $cols + 1) * $cell, 2 * $cell, $cell, $cell)   # the end square
    $g.Dispose()
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $ep = New-Object System.Drawing.Imaging.EncoderParameters 1
    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]$quality)
    $bmp.Save($path, $codec, $ep)
    $bmp.Dispose()
}

# --- "connected": when this script last ran, for /si in game ---
function Beat {
    if ($NoAsk) { return }
    Load-State
    $state.bridgeAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Save-State
    Write-Inbox
}

# --- keeping Flow up to date ---
function Toc-Version([string]$text) { if ($text -match '## Version:\s*(\S+)') { $Matches[1] } else { '?' } }
function Toc-Files([string]$text) { ($text -split "`r?`n") | Where-Object { $_ -match '\.(lua|xml)\s*$' } }
function Sync-Flow {
    if ($NoUpdate) { return }
    Push-Location $repo
    try {
        $remote = (git remote -v 2>$null | Select-String 'Perpetuator-LLC/flow-wow' | Select-Object -First 1)
        if (-not $remote) { return }
        $remote = ($remote.ToString() -split '\s+')[0]
        if ((git rev-parse --abbrev-ref HEAD 2>$null) -ne 'main') { return }   # your own branch: never touched
        $dirty = git status --porcelain 2>$null
        git fetch $remote main --quiet 2>$null
        $behind = [int](git rev-list --count HEAD..FETCH_HEAD 2>$null)
        if ($behind -le 0) { return }
        if ($dirty) {
            Load-State
            if (-not $state.toldDirty) {
                Emit "UPDATE waiting: this folder has changes of its own, so it wasn't updated"
                Add-Reply "A Flow update is waiting, but your Flow folder has your own changes, so it wasn't updated. Ask Claude to open a pull request with them, or to set them aside." $null
                $state.toldDirty = $true; Save-State
            }
            return
        }
        $oldToc = Get-Content (Join-Path $repo 'Flow.toc') -Raw
        git merge --ff-only FETCH_HEAD --quiet 2>$null
        if ($LASTEXITCODE -ne 0) { return }
        $newToc = Get-Content (Join-Path $repo 'Flow.toc') -Raw
        $restart = (Compare-Object (Toc-Files $oldToc) (Toc-Files $newToc)) -ne $null
        $how = if ($restart) { 'Restart WoW to load it (it adds new files).' } else { 'Type /reload to load it.' }
        $msg = "Flow updated: $(Toc-Version $oldToc) -> $(Toc-Version $newToc). $how See CHANGELOG.md for what's new."
        Emit "UPDATE $msg"
        Add-Reply $msg $null
        $state.toldDirty = $false; Save-State
    } finally { Pop-Location }
}

if ($SelfTest) {
    # A saved-data file as WoW writes it, with a message that has quotes and braces in it.
    $sample = @'
FlowDB = {
["nav"] = {
["mode"] = "optimal",
},
["chat"] = {
["nextId"] = 3,
["outbox"] = {
{
["text"] = "make the {arrow} \"green\"",
["id"] = 2,
["char"] = "Sooth",
["level"] = 9,
["zone"] = "Mulgore",
}, -- [1]
},
["seen"] = {
},
},
["deathReports"] = {
"1|Sooth|DRUID|6|Mulgore|died after 30 s fighting Bristleback (level 9, you 6); heals: suggested 0 times, cast 0 || Flow didn't suggest a heal",
},
}
'@
    [IO.File]::WriteAllText($saved, $sample)
    $ok = $true
    $box = @(Get-Outbox)
    if ($box.Count -ne 1) { Write-Host "FAIL outbox count: $($box.Count)"; $ok = $false }
    elseif ($box[0].id -ne 2) { Write-Host "FAIL id: $($box[0].id)"; $ok = $false }
    elseif ($box[0].text -ne 'make the {arrow} "green"') { Write-Host "FAIL text: $($box[0].text)"; $ok = $false }
    elseif ($box[0].zone -ne 'Mulgore') { Write-Host "FAIL zone: $($box[0].zone)"; $ok = $false }
    Handle-Messages   # prints: DEATH 1 | ..., then ASK 2 | Sooth ( 9, Mulgore) | make the {arrow} "green"
    if ($state.delivered -notcontains 2) { Write-Host "FAIL: message 2 not passed on"; $ok = $false }
    if ([int]$state.deathsSeen -ne 1) { Write-Host "FAIL: death 1 not passed on ($($state.deathsSeen))"; $ok = $false }
    $before = $state.deathsSeen
    Handle-Deaths     # nothing new: no second DEATH line
    if ($state.deathsSeen -ne $before) { Write-Host "FAIL: death passed on twice"; $ok = $false }
    Add-Reply 'Done: the arrow is green. Type /reload.' 2
    if ($state.answered -notcontains 2) { Write-Host "FAIL: message 2 not marked answered"; $ok = $false }
    $lua = Get-Content $inboxFile -Raw
    if ($lua -notmatch 'ns\.claudeInbox = \{' -or $lua -notmatch 'replyTo = 2' -or $lua -notmatch '\[==\[Done: the arrow is green\. Type /reload\.\]==\]') {
        Write-Host "FAIL inbox file:`n$lua"; $ok = $false
    }
    # Sent without a reload: Flow's coded screenshot, drawn here the way
    # AC:ShowCode draws it (same layout), saved as a rough JPEG; at screen
    # size, and scaled down (a screenshot smaller than the screen).
    $text7 = 'make the arrow purple, with a | and é ünïcode'
    New-FlowCodeImage (Join-Path $shotDir 'WoWScrnShot_1.jpg') "FLOW1|7|Yang;PALADIN;2;Tirisfal Glades|$text7" 12 1920 1080 35
    $r = Read-FlowCode (Get-Image (Join-Path $shotDir 'WoWScrnShot_1.jpg'))
    if (-not ($r -and $r.msg -and $r.msg.text -eq $text7 -and $r.msg.zone -eq 'Tirisfal Glades')) { Write-Host "FAIL: screenshot text '$(if ($r -and $r.msg) { $r.msg.text } else { $r.error })'"; $ok = $false }
    Handle-Screenshot (Join-Path $shotDir 'WoWScrnShot_1.jpg')   # prints: ASK 7 | Yang (PALADIN 2, Tirisfal Glades) | ...
    if ($state.delivered -notcontains 7) { Write-Host "FAIL: screenshot message 7 not passed on"; $ok = $false }
    if (Test-Path (Join-Path $shotDir 'WoWScrnShot_1.jpg')) { Write-Host "FAIL: Flow's screenshot not deleted after reading"; $ok = $false }
    New-FlowCodeImage (Join-Path $shotDir 'WoWScrnShot_2.jpg') ("FLOW1|8|A;B;1;Z|" + ('x' * 600)) 9 1440 810 50
    $r = Read-FlowCode (Get-Image (Join-Path $shotDir 'WoWScrnShot_2.jpg'))
    if (-not ($r -and $r.msg -and $r.msg.id -eq 8 -and $r.msg.text -eq ('x' * 600))) { Write-Host "FAIL: a scaled screenshot ($(if ($r) { $r.error }))"; $ok = $false }
    # Someone's own screenshot: not Flow's, left alone.
    Add-Type -AssemblyName System.Drawing
    $plain = New-Object System.Drawing.Bitmap 800, 600
    $g = [System.Drawing.Graphics]::FromImage($plain); $g.Clear([System.Drawing.Color]::FromArgb(40, 60, 30)); $g.Dispose()
    $plain.Save((Join-Path $shotDir 'WoWScrnShot_3.jpg'), [System.Drawing.Imaging.ImageFormat]::Jpeg); $plain.Dispose()
    Handle-Screenshot (Join-Path $shotDir 'WoWScrnShot_3.jpg')
    if (-not (Test-Path (Join-Path $shotDir 'WoWScrnShot_3.jpg'))) { Write-Host "FAIL: someone else's screenshot was deleted"; $ok = $false }
    Beat
    if ((Get-Content $inboxFile -Raw) -notmatch 'ns\.claudeBridge = \{ at = \d+ \}') { Write-Host "FAIL: no 'connected' note in the inbox"; $ok = $false }
    Remove-Item $tmp -Recurse -Force
    if ($ok) { Write-Host "self-test OK" ; exit 0 } else { exit 1 }
}

# --- wait for WoW to save (an event from Windows, not a polling loop) ---
$watcher = New-Object System.IO.FileSystemWatcher $savedDir, 'Flow.lua'
$watcher.NotifyFilter = [IO.NotifyFilters]'LastWrite, FileName, Size'
$watcher.EnableRaisingEvents = $true
$ids = @('FlowSavedChanged', 'FlowSavedCreated', 'FlowSavedRenamed')
Register-ObjectEvent $watcher Changed -SourceIdentifier $ids[0] | Out-Null
Register-ObjectEvent $watcher Created -SourceIdentifier $ids[1] | Out-Null
Register-ObjectEvent $watcher Renamed -SourceIdentifier $ids[2] | Out-Null
# WoW's Screenshots folder: messages sent without a reload (Flow's coded
# screenshots). (WoW makes the folder at its first screenshot; made here so
# it can be watched before that.)
$shotWatcher = $null
if (-not $NoAsk -and $shotDir) {
    if (-not (Test-Path $shotDir)) { New-Item -ItemType Directory -Force $shotDir | Out-Null }
    $shotWatcher = New-Object System.IO.FileSystemWatcher $shotDir
    $shotWatcher.NotifyFilter = [IO.NotifyFilters]'LastWrite, FileName, Size'
    $shotWatcher.EnableRaisingEvents = $true
    Register-ObjectEvent $shotWatcher Created -SourceIdentifier 'FlowShotCreated' | Out-Null
    Register-ObjectEvent $shotWatcher Renamed -SourceIdentifier 'FlowShotRenamed' | Out-Null
    $ids += @('FlowShotCreated', 'FlowShotRenamed')
}

if (-not (Test-Path $inboxFile)) { Write-Inbox }   # (Flow.toc lists it: make sure it's there)
$mode = if ($NoAsk) { 'off' } elseif ($Cli) { 'by itself (claude -p)' } else { 'passed on as ASK lines (a Claude session answers with -Reply)' }
$live = if ($shotWatcher) { " | live (no reload): Flow's screenshots in $shotDir" } else { '' }
Emit "READY watching $saved$live | /claude messages: $mode | updates: $(if ($NoUpdate) { 'off' } else { 'on' })"
try {
    Beat
    Sync-Flow
    Handle-Messages
    $lastSync = Get-Date; $lastBeat = Get-Date
    while ($true) {
        # Sleeps until WoW writes a file: Flow's saved data (a /reload, logout
        # or exit) or a screenshot (Flow's coded message, or anyone's). Every
        # 10 min it says "connected" again; every 30 min it checks for updates.
        $e = Wait-Event -Timeout 600
        $saveSeen = $false
        if ($e) {
            Start-Sleep -Milliseconds 300
            $events = @(Get-Event)
            $events | Remove-Event                 # one write fires several events
            $shots = @($events | Where-Object { $_.SourceIdentifier -like 'FlowShot*' } |
                ForEach-Object { $_.SourceEventArgs.FullPath } | Select-Object -Unique)
            foreach ($p in $shots) { Handle-Screenshot $p }
            if (@($events | Where-Object { $_.SourceIdentifier -like 'FlowSaved*' }).Count -gt 0) {
                $saveSeen = $true
                Start-Sleep -Milliseconds 500      # let WoW finish writing
                Handle-Messages
            }
        }
        if (((Get-Date) - $lastBeat).TotalMinutes -ge 10) { Beat; $lastBeat = Get-Date }
        if ($saveSeen -or ((Get-Date) - $lastSync).TotalMinutes -ge 30) { Sync-Flow; $lastSync = Get-Date }
    }
} finally {
    foreach ($id in $ids) { Unregister-Event -SourceIdentifier $id -ErrorAction SilentlyContinue }
    $watcher.Dispose()
    if ($shotWatcher) { $shotWatcher.Dispose() }
}
