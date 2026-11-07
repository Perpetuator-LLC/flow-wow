<#
  Shared by the tools: finds your WoW: Forever folder and account without
  anything hard-coded, so the scripts work on any machine.

  Override with environment variables when the guess is wrong:
    FLOW_WOW_DIR      e.g. C:\Program Files (x86)\World of Warcraft\_forever_
    FLOW_WOW_ACCOUNT  the folder name under WTF\Account
#>

function Find-WowDir {
    if ($env:FLOW_WOW_DIR -and (Test-Path $env:FLOW_WOW_DIR)) { return $env:FLOW_WOW_DIR }
    # Dev install: the AddOns\Flow folder is a junction to this repo, so the
    # WoW folder is wherever a junction to us lives. Otherwise, common spots.
    $roots = @()
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $roots += Join-Path $d.Root 'Program Files (x86)\World of Warcraft'
        $roots += Join-Path $d.Root 'Program Files\World of Warcraft'
        $roots += Join-Path $d.Root 'World of Warcraft'
        $roots += Join-Path $d.Root 'Games\World of Warcraft'
        $roots += Join-Path $d.Root 'Blizzard\World of Warcraft'
    }
    foreach ($r in $roots) {
        $f = Join-Path $r '_forever_'
        if (Test-Path (Join-Path $f 'WTF')) { return $f }
    }
    return $null
}

function Find-WowAccount([string]$WowDir) {
    if ($env:FLOW_WOW_ACCOUNT) { return $env:FLOW_WOW_ACCOUNT }
    # The account whose Flow saved data was written most recently.
    $saved = Get-ChildItem (Join-Path $WowDir 'WTF\Account\*\SavedVariables\Flow.lua') -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($saved) { return $saved.Directory.Parent.Name }
    return $null
}
