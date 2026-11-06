<#
.SYNOPSIS
  Prints Flow's diagnostics (log + latest snapshot) from the saved data file,
  so Claude (or you) can read what Flow saw in game. The file is written by
  the game on /reload, logout or exit.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\read-diag.ps1 [-Account YOUR_ACCOUNT] [-Tail 60]
#>
param(
    [string]$WowDir = 'G:\Blizzard\World of Warcraft\_forever_',
    [string]$Account = 'YOUR_ACCOUNT',
    [int]$Tail = 60
)
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
