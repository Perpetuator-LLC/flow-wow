<#
.SYNOPSIS
  Renders the CurseForge graphics from their SVG sources, using Edge (or Chrome)
  in headless mode, so no image tools need installing:
    docs\flow-logo.svg   -> docs\flow-logo.png    400x400, the project avatar
    docs\flow-banner.svg -> docs\flow-banner.png  1800x440 (2x), for the description

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\render-graphics.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$docs = Join-Path $root 'docs'

$browser = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { throw 'Needs Microsoft Edge or Google Chrome.' }

# A throwaway profile, so this never touches (or waits on) your open browser.
$profileDir = Join-Path ([IO.Path]::GetTempPath()) ('flow-render-' + [guid]::NewGuid())

function Render($svg, $png, $width, $height, $scale) {
    $src = Join-Path $docs $svg
    $out = Join-Path $docs $png
    if (Test-Path $out) { Remove-Item $out -Force }
    $url = 'file:///' + $src.Replace('\', '/')
    $browserArgs = @(
        '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
        "--user-data-dir=$profileDir", "--force-device-scale-factor=$scale",
        "--window-size=$width,$height", "--screenshot=$out", $url
    )
    Start-Process -FilePath $browser -ArgumentList $browserArgs -Wait -WindowStyle Hidden
    if (-not (Test-Path $out)) { throw "Rendering $svg failed." }
    Add-Type -AssemblyName System.Drawing
    $img = [Drawing.Image]::FromFile($out)
    try { Write-Host ("Built {0} ({1}x{2})" -f $out, $img.Width, $img.Height) } finally { $img.Dispose() }
}

try {
    Render 'flow-logo.svg' 'flow-logo.png' 400 400 1
    Render 'flow-banner.svg' 'flow-banner.png' 900 220 2
} finally {
    if (Test-Path $profileDir) { Remove-Item $profileDir -Recurse -Force -ErrorAction SilentlyContinue }
}
