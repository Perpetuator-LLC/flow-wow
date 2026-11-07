<#
.SYNOPSIS
  Checks the Lua before you /reload: runs luacheck (rules in .luacheckrc) and the
  texture-path check. Catches a missing "local", a local used before it's declared,
  typos in names, unused or overwritten values and unreachable code.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\lint.ps1            # whole add-on
  powershell -ExecutionPolicy Bypass -File tools\lint.ps1 Modules\Nav # one folder or file

  Exit code 0 = clean. Finds luacheck.exe via FLOW_LUACHECK, then PATH, then
  %USERPROFILE%\tools\luacheck\luacheck.exe.
  Get it from https://github.com/lunarmodules/luacheck/releases (luacheck.exe).
#>
param([string[]]$Paths)
$root = Split-Path $PSScriptRoot -Parent

$exe = $null
if ($env:FLOW_LUACHECK -and (Test-Path $env:FLOW_LUACHECK)) { $exe = $env:FLOW_LUACHECK }
if (-not $exe) { $c = Get-Command luacheck -ErrorAction SilentlyContinue; if ($c) { $exe = $c.Source } }
if (-not $exe) {
    $guess = Join-Path $env:USERPROFILE 'tools\luacheck\luacheck.exe'
    if (Test-Path $guess) { $exe = $guess }
}
if (-not $exe) {
    "luacheck not found. Download luacheck.exe from https://github.com/lunarmodules/luacheck/releases"
    "and put it in $env:USERPROFILE\tools\luacheck\ (or set FLOW_LUACHECK to its path)."
    exit 2
}

if (-not $Paths) { $Paths = @('.') }
Push-Location $root
try {
    & $exe @Paths --no-color
    $lua = $LASTEXITCODE
} finally { Pop-Location }

& (Join-Path $PSScriptRoot 'check-paths.ps1')
$tex = $LASTEXITCODE

if ($lua -ne 0 -or $tex -ne 0) { "LINT FAILED: fix the lines above before committing."; exit 1 }
"lint OK"
