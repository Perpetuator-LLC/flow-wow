<#
.SYNOPSIS
  Prints Flow's diagnostics (log + latest snapshot) from the saved data file,
  so Claude (or you) can read what Flow saw in game. The file is written by
  the game on /reload, logout or exit.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\read-diag.ps1 [-Account NAME] [-WowDir PATH] [-Tail 60]
  The WoW folder and account are found by themselves (tools\Common.ps1);
  set FLOW_WOW_DIR / FLOW_WOW_ACCOUNT if the guess is wrong.
#>
param(
    [string]$WowDir,
    [string]$Account,
    [int]$Tail = 60
)
. (Join-Path $PSScriptRoot 'Common.ps1')
if (-not $WowDir) { $WowDir = Find-WowDir }
if (-not $WowDir) { Write-Host "Can't find your WoW: Forever folder. Pass -WowDir or set FLOW_WOW_DIR."; exit 1 }
if (-not $Account) { $Account = Find-WowAccount $WowDir }
if (-not $Account) { Write-Host "No Flow saved data under $WowDir yet. /reload in game first, or pass -Account."; exit 1 }
$file = Join-Path $WowDir "WTF\Account\$Account\SavedVariables\Flow.lua"
if (-not (Test-Path $file)) { Write-Host "No saved data at $file yet. /reload in game first."; exit 1 }
$info = Get-Item $file
Write-Host "Flow saved data: $file (written $($info.LastWriteTime))"
$text = Get-Content $file -Raw

function Get-LuaList([string]$body) {
    # Lua string list entries:  "text",  (escaped quotes \" and backslashes \\)
    [regex]::Matches($body, '"((?:[^"\\]|\\.)*)",') | ForEach-Object {
        $_.Groups[1].Value -replace '\\"', '"' -replace '\\\\', '\' -replace '\\n', "`n"
    }
}

function Get-Block([string]$name) {
    $m = [regex]::Match($text, '\["' + $name + '"\]\s*=\s*\{')
    if (-not $m.Success) { return $null }
    $i = $m.Index + $m.Length; $depth = 1
    while ($i -lt $text.Length -and $depth -gt 0) {
        $ch = $text[$i]
        if ($ch -eq '"') { $i++; while ($i -lt $text.Length -and $text[$i] -ne '"') { if ($text[$i] -eq '\') { $i++ }; $i++ } }
        elseif ($ch -eq '{') { $depth++ } elseif ($ch -eq '}') { $depth-- }
        $i++
    }
    return $text.Substring($m.Index + $m.Length, $i - ($m.Index + $m.Length) - 1)
}

$diag = Get-Block 'diag'
if (-not $diag) { Write-Host "No diagnostics yet (needs Flow 0.17.6+ and a /reload)."; exit 0 }
$text = $diag
$snap = Get-Block 'snapshot'
$log = Get-Block 'log'
Write-Host "`n=== Snapshot ==="
if ($snap) { Get-LuaList $snap | ForEach-Object { Write-Host $_ } } else { Write-Host "(none)" }
Write-Host "`n=== Log (last $Tail) ==="
if ($log) { Get-LuaList $log | Select-Object -Last $Tail | ForEach-Object { Write-Host $_ } } else { Write-Host "(empty)" }

# Blocked actions: the "only available to the Blizzard UI" errors. Always
# printed (also when there are none) so whoever reads this checks them.
Write-Host "`n=== Blocked actions ==="
$blockedLines = @()
if ($log) { $blockedLines = Get-LuaList $log | Where-Object { $_ -match '\[blocked\]' } }
if ($blockedLines.Count -gt 0) {
    $blockedLines | ForEach-Object { Write-Host "!! $_" }
    Write-Host "!! FIX THESE: find what tainted the blamed function (taint.log below), fix it, add a test."
} else { Write-Host "none" }

# The game's taint log (developer installs turn it on): lines about Flow.
$taint = Join-Path $WowDir 'Logs\taint.log'
Write-Host "`n=== taint.log (Flow lines) ==="
if (Test-Path $taint) {
    $t = Get-Content $taint -Tail 4000 | Select-String -Pattern 'Flow|blocked|forbidden' -SimpleMatch:$false
    if ($t) { $t | Select-Object -Last 40 | ForEach-Object { Write-Host $_.Line } } else { Write-Host "nothing about Flow" }
} else { Write-Host "(no taint.log yet: it starts after a /reload with a developer install)" }
