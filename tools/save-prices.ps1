# Saves today's public auction prices for WoW: Forever, to build a price history.
#
#   powershell -ExecutionPolicy Bypass -File tools\save-prices.ps1
#   powershell -ExecutionPolicy Bypass -File tools\save-prices.ps1 -Region eu -Faction alliance
#   powershell -ExecutionPolicy Bypass -File tools\save-prices.ps1 -Summary     (what's been saved so far)
#
# The files are TradeSkillMaster's public data (https://tradeskillmaster.com/public-data):
# current prices per item, in copper, for the region and for each ruleset's auction house.
# They hold today's values only, so a history is these files kept day by day.
#
#   - One fetch a file a day: a day already saved is skipped (run it as often as you like).
#   - Kept outside this repository (by default in ..\flow-market-data\<date>\, gzipped):
#     the data is TradeSkillMaster's, free to use with credit, not to republish in bulk.
#   - Nothing about you or your characters is sent: these are plain downloads.

param(
    [string]$Region = "us",
    [string]$Faction = "horde",
    [string]$Out = "",
    [switch]$Summary
)

$ErrorActionPreference = "Stop"
$base = "https://public-data.tradeskillmaster.com/forever/$Region"
$rulesets = @("normal", "pvp", "roleplay", "roleplay-pvp")
if (-not $Out) { $Out = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "flow-market-data" }

if ($Summary) {
    if (-not (Test-Path $Out)) { Write-Output "Nothing saved yet ($Out doesn't exist)."; exit 0 }
    $days = Get-ChildItem $Out -Directory | Sort-Object Name
    $bytes = (Get-ChildItem $Out -Recurse -File | Measure-Object Length -Sum).Sum
    Write-Output ("{0} day(s) saved in {1}, {2:N1} MB" -f $days.Count, $Out, ($bytes / 1MB))
    if ($days.Count -gt 0) { Write-Output ("from {0} to {1}" -f $days[0].Name, $days[-1].Name) }
    exit 0
}

$files = @(@{ name = "region"; url = "$base/region/items.csv" })
foreach ($r in $rulesets) { $files += @{ name = "$r-$Faction"; url = "$base/realm/$r-$Faction/items.csv" } }

$day = (Get-Date).ToString("yyyy-MM-dd")
$dir = Join-Path $Out $day
New-Item -ItemType Directory -Force $dir | Out-Null

$saved = 0; $skipped = 0; $failed = 0
foreach ($f in $files) {
    $path = Join-Path $dir ("{0}-{1}.csv.gz" -f $Region, $f.name)
    if (Test-Path $path) { $skipped++; continue }
    try {
        $resp = Invoke-WebRequest -Uri $f.url -UseBasicParsing -UserAgent "price-history-saver" -TimeoutSec 120
        $text = $resp.Content
        if ($text -is [byte[]]) { $text = [System.Text.Encoding]::UTF8.GetString($text) }
        # A real file starts with its column names; anything else (an error page) isn't kept.
        if (-not $text.StartsWith("itemId,")) { throw "not a price file" }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $fs = [System.IO.File]::Create($path)
        try {
            $gz = New-Object System.IO.Compression.GZipStream($fs, [System.IO.Compression.CompressionMode]::Compress)
            $gz.Write($bytes, 0, $bytes.Length)
            $gz.Close()
        } finally { $fs.Close() }
        $lines = ($text -split "`n").Count - 1
        Write-Output ("saved {0}: {1} item(s), {2:N0} KB" -f $f.name, $lines, ((Get-Item $path).Length / 1KB))
        $saved++
    } catch {
        if (Test-Path $path) { Remove-Item $path -Force }
        Write-Output ("FAILED {0}: {1}" -f $f.name, $_.Exception.Message)
        $failed++
    }
    Start-Sleep -Milliseconds 500
}
Write-Output ("{0}: {1} saved, {2} already there, {3} failed -> {4}" -f $day, $saved, $skipped, $failed, $dir)
if ($failed -gt 0) { exit 1 }
