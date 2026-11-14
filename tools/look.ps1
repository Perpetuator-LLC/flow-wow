<#
  Looks at the game: saves a picture of the World of Warcraft window, and only
  that window, so Claude can check how something looks while you play (an
  add-on can't be asked from outside the game, and the saved data only changes
  on /reload).

    powershell -ExecutionPolicy Bypass -File tools\look.ps1
    powershell -ExecutionPolicy Bypass -File tools\look.ps1 -Crop "0.40,0.30,0.20,0.25"
    powershell -ExecutionPolicy Bypass -File tools\look.ps1 -Out C:\somewhere\shot.png -Scale 0.5

  -Crop  left,top,width,height as shares of the window (0-1): a close look at
         one part at full size (the arrow, a menu), where a whole 4K window
         would be shrunk too far to read.
  -Scale shrink the picture (0.5 = half size).
  -Out   where to write it; by default a new file under %TEMP%\flow-look.

  Prints "LOOK <path> <width>x<height>" (or "NO-GAME ..."). The picture stays
  on this machine: the script sends nothing anywhere. The game has to be on
  screen (not minimised); a window lying over it is in the picture too.
#>
param(
    [string]$Out,
    [double]$Scale = 1.0,
    [string]$Crop
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class FlowLook {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
# (Real pixels, not the scaled ones a high-DPI desktop reports.)
[void][FlowLook]::SetProcessDPIAware()

$game = Get-Process -Name Wow, WowClassic, WowT, WowB -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $game) { Write-Output "NO-GAME World of Warcraft isn't running (no window found)."; exit 1 }
$h = $game.MainWindowHandle
if ([FlowLook]::IsIconic($h)) { Write-Output "NO-GAME World of Warcraft is minimised: nothing to look at."; exit 1 }

$rect = New-Object FlowLook+RECT
[void][FlowLook]::GetClientRect($h, [ref]$rect)
$origin = New-Object FlowLook+POINT
[void][FlowLook]::ClientToScreen($h, [ref]$origin)
$w, $ht = ($rect.R - $rect.L), ($rect.B - $rect.T)
if ($w -le 0 -or $ht -le 0) { Write-Output "NO-GAME the game's window has no size."; exit 1 }

# The part to take.
$x, $y = $origin.X, $origin.Y
if ($Crop) {
    $c = $Crop -split '[,; ]+' | Where-Object { $_ -ne '' } | ForEach-Object { [double]::Parse($_, [Globalization.CultureInfo]::InvariantCulture) }
    if ($c.Count -ne 4) { Write-Output "BAD-CROP give left,top,width,height as shares of the window, like 0.4,0.3,0.2,0.25"; exit 1 }
    # (Doubles throughout: with a whole number first, [Math]::Min picks its
    # whole-number form and turns 0.34 into 0.)
    [double]$cl = [Math]::Max([double]0, [Math]::Min([double]1, [double]$c[0]))
    [double]$ct = [Math]::Max([double]0, [Math]::Min([double]1, [double]$c[1]))
    [double]$cw = [Math]::Max([double]0.01, [Math]::Min([double](1 - $cl), [double]$c[2]))
    [double]$ch = [Math]::Max([double]0.01, [Math]::Min([double](1 - $ct), [double]$c[3]))
    $x += [int]($w * $cl); $y += [int]($ht * $ct)
    $w = [int]($w * $cw); $ht = [int]($ht * $ch)
}

$bmp = New-Object System.Drawing.Bitmap $w, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size $w, $ht))
$g.Dispose()

if ($Scale -gt 0 -and $Scale -ne 1.0) {
    $sw, $sh = [Math]::Max(1, [int]($w * $Scale)), [Math]::Max(1, [int]($ht * $Scale))
    $small = New-Object System.Drawing.Bitmap $sw, $sh
    $g2 = [System.Drawing.Graphics]::FromImage($small)
    $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g2.DrawImage($bmp, 0, 0, $sw, $sh)
    $g2.Dispose(); $bmp.Dispose()
    $bmp = $small; $w = $sw; $ht = $sh
}

if (-not $Out) {
    $dir = Join-Path $env:TEMP 'flow-look'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $Out = Join-Path $dir ("look-{0}.png" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
}
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("LOOK {0} {1}x{2}" -f $Out, $w, $ht)
