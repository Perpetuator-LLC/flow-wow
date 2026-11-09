<#
.SYNOPSIS
  Talk to Claude from inside WoW, and keep Flow up to date by itself.
  See docs/ASK-CLAUDE.md for setup.

  In game:  /si make the arrow green
  Flow whispers the message to the player, tagged "[FlowAsk:id:part/n]", and
  WoW writes that to its chat log (Logs\WoWChatLog.txt) at once: no reload.
  (Flow keeps it in its saved data too, written at the next reload.) This
  script waits for either file to change (a file-change event, no polling)
  and prints each new message as one line:
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
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$repo = Split-Path $PSScriptRoot -Parent
if (-not $AddonDir) { $AddonDir = $repo }

$chatLog = $null
if ($SelfTest) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("flow-bridge-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Force (Join-Path $tmp 'Learned') | Out-Null
    $AddonDir = $tmp; $savedDir = $tmp; $saved = Join-Path $tmp 'Flow.lua'; $Cli = $false; $NoUpdate = $true
    $chatLog = Join-Path $tmp 'WoWChatLog.txt'
} elseif ($Reply -or $Note) {
    $savedDir = $null; $saved = $null   # (answering: only the answers file is needed)
} else {
    if (-not $WowDir) { $WowDir = Find-WowDir }
    if (-not $WowDir) { Write-Host "Can't find your WoW: Forever folder. Pass -WowDir or set FLOW_WOW_DIR."; exit 1 }
    if (-not $Account) { $Account = Find-WowAccount $WowDir }
    if (-not $Account) { Write-Host "No Flow saved data yet: log in once with Flow on, then start this again (or pass -Account)."; exit 1 }
    $savedDir = Join-Path $WowDir "WTF\Account\$Account\SavedVariables"
    $saved = Join-Path $savedDir 'Flow.lua'
    $chatLog = Join-Path $WowDir 'Logs\WoWChatLog.txt'   # (Flow turns WoW's chat log on when you send)
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
        if ($null -ne $s.chatLogPos) { $state.chatLogPos = [long]$s.chatLogPos }
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

# --- messages sent without a reload: Flow's tagged whispers in WoW's chat log ---
# "[FlowAsk:<id>:0/<n>] char;class;level;zone", then parts 1..n of the text.
# Each whisper shows twice in the log ("To you:" and "you whispers:").
$chatParts = @{}
function Add-ChatLines([string[]]$lines) {
    $done = @()
    foreach ($l in $lines) {
        $x = [regex]::Match([string]$l, '\[FlowAsk:(\d+):(\d+)/(\d+)\] ?(.*?)\s*$')
        if (-not $x.Success) { continue }
        $id = [int]$x.Groups[1].Value; $k = [int]$x.Groups[2].Value; $n = [int]$x.Groups[3].Value
        if (-not $chatParts.ContainsKey($id)) { $chatParts[$id] = @{ n = $n; who = $null; parts = @{} } }
        $e = $chatParts[$id]
        # (Trailing spaces trimmed above; Flow never ends a part with one.)
        if ($k -eq 0) { $e.who = $x.Groups[4].Value } else { $e.parts[$k] = $x.Groups[4].Value }
        if ($null -ne $e.who -and $e.parts.Count -ge $e.n) {
            $text = (@(1..$e.n | ForEach-Object { $e.parts[$_] })) -join ''
            $f = @($e.who -split ';', 4) + @('', '', '', '')
            $done += @{ id = $id; text = $text; char = $f[0]; class = $f[1]; level = $f[2]; zone = $f[3] }
            $chatParts.Remove($id)
        }
    }
    return $done
}
# New whole lines since last time (the last line may still be being written).
function Read-ChatLogLines {
    if (-not $chatLog -or -not (Test-Path $chatLog)) { return @() }
    Load-State
    $fs = [IO.File]::Open($chatLog, 'Open', 'Read', 'ReadWrite')
    try {
        $len = $fs.Length
        # First run: start at the end (not your whole chat history).
        $pos = if ($null -ne $state.chatLogPos) { [long]$state.chatLogPos } else { $len }
        if ($pos -gt $len) { $pos = 0 }   # a new log file
        $count = [int]($len - $pos)
        if ($count -le 0) { $state.chatLogPos = $pos; Save-State; return @() }
        $buf = New-Object byte[] $count
        $fs.Seek($pos, 'Begin') | Out-Null
        $read = $fs.Read($buf, 0, $count)
    } finally { $fs.Dispose() }
    $last = -1
    for ($i = $read - 1; $i -ge 0; $i--) { if ($buf[$i] -eq 10) { $last = $i; break } }
    if ($last -lt 0) { return @() }
    $state.chatLogPos = $pos + $last + 1
    Save-State
    return ([Text.Encoding]::UTF8.GetString($buf, 0, $last + 1) -split "`r?`n")
}
function Handle-ChatLog {
    if ($NoAsk) { return }
    foreach ($m in @(Add-ChatLines @(Read-ChatLogLines))) { Deliver $m }
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
    # Sent without a reload: Flow's whispers in WoW's chat log (each twice,
    # "To" and "whispers"), a part starting with a space, a line still being
    # written at the end, and someone else's chat in between.
    $log = @(
        '11/9 08:40:01.123  To Yang-Forever: [FlowAsk:7:0/2] Yang;PALADIN;2;Tirisfal Glades',
        '11/9 08:40:01.124  Yang-Forever whispers: [FlowAsk:7:0/2] Yang;PALADIN;2;Tirisfal Glades',
        '11/9 08:40:01.200  [1. General] Bob: anyone for Hogger?',
        '11/9 08:40:01.373  To Yang-Forever: [FlowAsk:7:1/2] make the arrow',
        '11/9 08:40:01.374  Yang-Forever whispers: [FlowAsk:7:1/2] make the arrow',
        '11/9 08:40:01.623  To Yang-Forever: [FlowAsk:7:2/2]  purple please',
        ''
    ) -join "`r`n"
    $state.chatLogPos = 0; Save-State
    [IO.File]::WriteAllText($chatLog, $log + '11/9 08:40:02.000  To Yang-Forever: [FlowAsk:8:0/1] Ya')
    Handle-ChatLog    # prints: ASK 7 | Yang (PALADIN 2, Tirisfal Glades) | make the arrow purple please
    if ($state.delivered -notcontains 7) { Write-Host "FAIL: chat-log message 7 not passed on"; $ok = $false }
    if ($state.delivered -contains 8) { Write-Host "FAIL: a half-written line was read"; $ok = $false }
    $got = @(Add-ChatLines @('x  To Y: [FlowAsk:9:0/2] A;B;1;Z', 'x [FlowAsk:9:1/2] make the arrow', 'x [FlowAsk:9:2/2]  purple'))
    if (@($got).Count -ne 1 -or $got[0].text -ne 'make the arrow purple' -or $got[0].zone -ne 'Z') {
        Write-Host "FAIL chat-log parts: '$($got[0].text)'"; $ok = $false
    }
    Handle-ChatLog    # nothing new
    if (@($state.delivered | Where-Object { $_ -eq 7 }).Count -ne 1) { Write-Host "FAIL: message 7 passed on twice"; $ok = $false }
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
# WoW's chat log: messages sent without a reload (Flow turns the log on).
$logWatcher = $null
$logDir = Split-Path $chatLog
if (-not $NoAsk -and (Test-Path $logDir)) {
    $logWatcher = New-Object System.IO.FileSystemWatcher $logDir, 'WoWChatLog.txt'
    $logWatcher.NotifyFilter = [IO.NotifyFilters]'LastWrite, FileName, Size'
    $logWatcher.EnableRaisingEvents = $true
    Register-ObjectEvent $logWatcher Changed -SourceIdentifier 'FlowChatLogChanged' | Out-Null
    Register-ObjectEvent $logWatcher Created -SourceIdentifier 'FlowChatLogCreated' | Out-Null
    $ids += @('FlowChatLogChanged', 'FlowChatLogCreated')
}

if (-not (Test-Path $inboxFile)) { Write-Inbox }   # (Flow.toc lists it: make sure it's there)
$mode = if ($NoAsk) { 'off' } elseif ($Cli) { 'by itself (claude -p)' } else { 'passed on as ASK lines (a Claude session answers with -Reply)' }
$live = if ($logWatcher) { " | live (no reload): $chatLog" } else { '' }
Emit "READY watching $saved$live | /claude messages: $mode | updates: $(if ($NoUpdate) { 'off' } else { 'on' })"
try {
    Beat
    Sync-Flow
    Handle-Messages
    Handle-ChatLog
    $lastSync = Get-Date; $lastBeat = Get-Date
    while ($true) {
        # Sleeps until WoW writes a file: Flow's saved data (a /reload, logout
        # or exit) or its chat log (any chat, a Flow message among it). Every
        # 10 min it says "connected" again; every 30 min it checks for updates.
        $e = Wait-Event -Timeout 600
        $saveSeen = $false
        if ($e) {
            Start-Sleep -Milliseconds 300
            $kinds = @(Get-Event | ForEach-Object { $_.SourceIdentifier })
            Get-Event | Remove-Event               # one write fires several events
            if ($kinds -like 'FlowChatLog*') { Handle-ChatLog }
            if ($kinds -like 'FlowSaved*') {
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
    if ($logWatcher) { $logWatcher.Dispose() }
}
