# Switch between running Classic Controls from this repository (the working
# copy) and from an installed copy (the Steam Workshop item, or a release
# unpacked into the mods folder).
#
# DFHack finds the working copy through a line in the game's
# dfhack-config\script-paths.txt:
#
#     +<this repository>/scripts
#
# and the "+" puts it ahead of any installed copy, which it then hides. To
# test what players get, switch it off, restart the game, test, and switch it
# back on.
#
#   .\tools\dev-scripts.ps1 status     which copy the game will use (and, if
#                                      it is running, which it is using now)
#   .\tools\dev-scripts.ps1 off        use the installed copy (from the next start)
#   .\tools\dev-scripts.ps1 on         use the working copy (from the next start)
#
# The game's folder is found from the running game, else Steam's default
# library; -GameDir overrides it.
param(
    [Parameter(Position = 0)][ValidateSet('status', 'on', 'off')][string]$Action = 'status',
    [string]$GameDir = ""
)
$ErrorActionPreference = 'Stop'

$scriptsDir = (Join-Path (Split-Path $PSScriptRoot) 'scripts') -replace '\\', '/'
$running = Get-Process 'Dwarf Fortress' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $GameDir -and $running -and $running.Path) { $GameDir = Split-Path $running.Path }
if (-not $GameDir) { $GameDir = Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\Dwarf Fortress' }
$pathsFile = Join-Path $GameDir 'dfhack-config\script-paths.txt'
if (-not (Test-Path $pathsFile)) { throw "No $pathsFile (pass -GameDir with the game's folder)" }

$lines = @(Get-Content $pathsFile)
$active = "+$scriptsDir"
$isOurs = { param($l) ($l.Trim() -replace '^#\s*', '') -ieq $active }
$present = @($lines | Where-Object { & $isOurs $_ })
$on = @($present | Where-Object { -not $_.Trim().StartsWith('#') }).Count -gt 0

if ($Action -eq 'on' -or $Action -eq 'off') {
    $want = $Action -eq 'on'
    if ($want -ne $on -or $present.Count -eq 0) {
        $new = @($lines | Where-Object { -not (& $isOurs $_) })
        $new += $(if ($want) { $active } else { "# $active" })
        Set-Content -Path $pathsFile -Value $new -Encoding ASCII
        $on = $want
    }
    "working copy {0} in {1}" -f $(if ($on) { 'ON' } else { 'OFF' }), $pathsFile
    if ($running) { 'Restart the game for this to take effect.' }
} else {
    "working copy is {0} in {1}" -f $(if ($on) { 'ON' } else { 'OFF' }), $pathsFile
}

# what the running game actually loaded
if ($running) {
    $run = @((Join-Path $GameDir 'dfhack-run.exe'), (Join-Path (Split-Path $GameDir) 'DFHack\hack\dfhack-run.exe')) |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($run) {
        $where = & $run lua "print(dfhack.findScript('classic-controls') or 'not found')" 2>$null | Select-Object -First 1
        "the running game is using: $where"
    }
}
