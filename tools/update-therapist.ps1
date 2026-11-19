# Make Dwarf Therapist able to read the running version of Dwarf Fortress.
#
# Therapist needs a "memory layout" file for each build of the game and only
# ships them for the versions that existed when it was released. DFHack can
# write that file for whatever version is running (devel/export-dt-ini); this
# script runs it and puts the result where Therapist looks.
#
# Run it once after each game update, with the game running (started through
# DFHack) and a fort loaded:
#
#   .\update-therapist.ps1 -TherapistDir "D:\Tools\DwarfTherapist"
#
# or set DWARF_THERAPIST_DIR once and leave the argument off. The game's
# folder and DFHack are found from the running game; -GameDir and -DfhackRun
# override them. Then start (or restart) Dwarf Therapist.
param(
    [string]$TherapistDir = $env:DWARF_THERAPIST_DIR,
    [string]$GameDir = "",
    [string]$DfhackRun = ""
)
$ErrorActionPreference = 'Stop'

# The game's folder and DFHack's dfhack-run.exe, from the running game: DFHack
# from Steam is a separate app beside the game (steamapps\common\DFHack), a
# manual install puts it in the game's own folder.
function Find-GameDir {
    $p = Get-Process 'Dwarf Fortress' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p -and $p.Path) { return Split-Path $p.Path }
}
function Find-DfhackRun([string]$gameDir) {
    if (-not $gameDir) { return }
    foreach ($c in @((Join-Path $gameDir 'dfhack-run.exe'),
                     (Join-Path (Split-Path $gameDir) 'DFHack\hack\dfhack-run.exe'))) {
        if (Test-Path $c) { return $c }
    }
}

if (-not $TherapistDir) { throw "Say where Dwarf Therapist is: -TherapistDir <folder>, or set DWARF_THERAPIST_DIR" }
if (-not $GameDir) { $GameDir = Find-GameDir }
if (-not $DfhackRun) { $DfhackRun = Find-DfhackRun $GameDir }

$layouts = Join-Path $TherapistDir "data\memory_layouts\windows"
if (-not (Test-Path $layouts)) { throw "No memory_layouts\windows folder under $TherapistDir" }
if (-not (Get-Process "Dwarf Fortress" -ErrorAction SilentlyContinue)) {
    throw "Dwarf Fortress is not running. Start it through DFHack and load a fort first."
}
if (-not $DfhackRun -or -not (Test-Path $DfhackRun)) { throw "Could not find dfhack-run.exe: pass -DfhackRun <path>" }

$ini = Join-Path $GameDir "therapist.ini"
if (Test-Path $ini) { Remove-Item $ini }
& $DfhackRun devel/export-dt-ini | Out-Null
if (-not (Test-Path $ini)) { throw "DFHack did not write $ini (is the game running with DFHack?)" }

$text = Get-Content $ini
$name = ($text | Where-Object { $_ -like 'version_name=*' } | Select-Object -First 1) -replace '^version_name=', ''
$checksum = ($text | Where-Object { $_ -like 'checksum=*' } | Select-Object -First 1) -replace '^checksum=', ''
$complete = ($text | Where-Object { $_ -like 'complete=*' } | Select-Object -First 1) -replace '^complete=', ''
# "v0.53.17 win64 STEAM" -> "v0.53.17-steam_win64.ini", as Therapist names its own
if ($name -notmatch '^(v[\d.]+) (\w+) (\w+)$') { throw "Unexpected version name in the layout: '$name'" }
$file = "{0}-{1}_{2}.ini" -f $Matches[1], $Matches[3].ToLower(), $Matches[2]

$target = Join-Path $layouts $file
Move-Item $ini $target -Force
"Wrote $target"
"  game version: $name   checksum: $checksum   complete: $complete"
if ($complete -ne 'true') {
    "  DFHack could not find every address for this version: some of Therapist's columns may be wrong."
}
