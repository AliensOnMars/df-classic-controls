# Build the mod: dist\<id>\ (the folder that goes in the game's mods folder or
# up to the Steam Workshop) and dist\<id>-<version>.zip (for a GitHub release
# or a manual install).
#
#   .\tools\build-mod.ps1            build only
#   .\tools\build-mod.ps1 -Stage     and put it in the game's mods\mod_upload
#                                    folder, ready for the Mods screen's
#                                    Publish button
#
# The game keeps mods in its user folder, %APPDATA%\Bay 12 Games\Dwarf
# Fortress, unless it runs in portable mode, when they are in the game's own
# folder. With the game running through DFHack the folder is asked of DFHack;
# otherwise the user folder is used if it exists. -DataDir overrides it.
#
# After the first publish the game writes [STEAM_FILE_ID:...] into the staged
# info.txt. Staging again keeps that line (so the next publish updates the
# same Workshop item), and says to copy it into mod\info.txt here too.
param(
    [switch]$Stage,
    [string]$DataDir = ""
)
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot
$infoPath = Join-Path $root 'mod\info.txt'
$info = Get-Content $infoPath -Raw
if ($info -match '@AUTHOR@') { throw 'mod\info.txt still has the @AUTHOR@ placeholder' }
$id = [regex]::Match($info, '\[ID:([^\]]+)\]').Groups[1].Value
$version = [regex]::Match($info, '\[DISPLAYED_VERSION:([^\]]+)\]').Groups[1].Value
if (-not $id -or -not $version) { throw 'mod\info.txt needs [ID:...] and [DISPLAYED_VERSION:...]' }

# --- the mod folder ------------------------------------------------------------
$dist = Join-Path $root 'dist'
$out = Join-Path $dist $id
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
$scripts = Join-Path $out 'scripts_modinstalled'
New-Item -ItemType Directory -Force -Path $scripts | Out-Null

Copy-Item $infoPath $out
$preview = Join-Path $root 'mod\preview.png'
if (Test-Path $preview) { Copy-Item $preview $out } else { Write-Warning 'no mod\preview.png: the Workshop item will have no picture' }
# DFHack adds scripts_modinstalled to its script paths for any installed mod,
# whether or not the mod is active in the world, so the overlay is there in
# every fort.
foreach ($name in 'classic-controls.lua', 'classic-labors.lua') {
    Copy-Item (Join-Path $root "scripts\$name") $scripts
}
Copy-Item (Join-Path $root 'README.md') $out
Copy-Item (Join-Path $root 'CHANGELOG.md') $out
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $out 'LICENSE.txt')
New-Item -ItemType Directory -Force -Path (Join-Path $out 'docs') | Out-Null
Copy-Item (Join-Path $root 'docs\keys.md') (Join-Path $out 'docs')
Copy-Item (Join-Path $root 'docs\labors-and-therapist.md') (Join-Path $out 'docs')

$zip = Join-Path $dist "$id-$version.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $out -DestinationPath $zip
"built   $out"
"zipped  $zip ({0:N0} KB)" -f ((Get-Item $zip).Length / 1KB)
if (Test-Path (Join-Path $out 'preview.png')) {
    $kb = (Get-Item (Join-Path $out 'preview.png')).Length / 1KB
    if ($kb -gt 1000) { Write-Warning ("preview.png is {0:N0} KB; Steam wants under 1 MB" -f $kb) }
}

if (-not $Stage) { return }

# --- staging for the game's Publish button -------------------------------------
$userDir = Join-Path $env:APPDATA 'Bay 12 Games\Dwarf Fortress'
if (-not $DataDir) {
    $p = Get-Process 'Dwarf Fortress' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p -and $p.Path) {
        $gameDir = Split-Path $p.Path
        foreach ($run in @((Join-Path $gameDir 'dfhack-run.exe'),
                           (Join-Path (Split-Path $gameDir) 'DFHack\hack\dfhack-run.exe'))) {
            if (Test-Path $run) {
                $base = & $run lua "print(dfhack.filesystem.getBaseDir())" 2>$null | Select-Object -First 1
                if ($base -and (Test-Path $base)) { $DataDir = $base.TrimEnd('/', '\') }
                break
            }
        }
        if (-not $DataDir -and -not (Test-Path $userDir)) { $DataDir = $gameDir }
    }
}
if (-not $DataDir) { $DataDir = $userDir }
if (-not (Test-Path $DataDir)) {
    throw "Folder not found: $DataDir (pass -DataDir with the folder that holds the game's mods folder)"
}
$uploadDir = Join-Path $DataDir 'mods\mod_upload'
$staged = Join-Path $uploadDir $id
$fileId = $null
$stagedInfo = Join-Path $staged 'info.txt'
if (Test-Path $stagedInfo) {
    $m = [regex]::Match((Get-Content $stagedInfo -Raw), '\[STEAM_FILE_ID:(\d+)\]')
    if ($m.Success) { $fileId = $m.Groups[1].Value }
}
if (Test-Path $staged) { Remove-Item $staged -Recurse -Force }
New-Item -ItemType Directory -Force -Path $uploadDir | Out-Null
Copy-Item $out $uploadDir -Recurse
if ($fileId -and ($info -notmatch '\[STEAM_FILE_ID:')) {
    Add-Content (Join-Path $staged 'info.txt') "[STEAM_FILE_ID:$fileId]"
    Write-Warning "kept [STEAM_FILE_ID:$fileId] from the last publish; add that line to mod\info.txt as well"
}
"staged  $staged"
