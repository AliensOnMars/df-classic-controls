# Build a ready-to-run Dwarf Therapist for the GitHub release: a copy of an
# official Therapist release with this repository's memory layouts added
# (therapist\*.ini), so that it reads the game builds those were made for.
#
#   .\tools\build-therapist-bundle.ps1 -TherapistDir "D:\Tools\DwarfTherapist-v42.1.21-win64"
#
# Point it at an unpacked official release (from
# https://github.com/Dwarf-Therapist/Dwarf-Therapist/releases). Logs are left
# out. The result is dist\DwarfTherapist-v<version>-win64-df<game>.zip.
param(
    [Parameter(Mandatory = $true)][string]$TherapistDir
)
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot
if (-not (Test-Path (Join-Path $TherapistDir 'DwarfTherapist.exe'))) { throw "No DwarfTherapist.exe in $TherapistDir" }
$manifestPath = Join-Path $TherapistDir 'manifest.json'
$manifest = Get-Content $manifestPath -Raw
$version = [regex]::Match($manifest, '"content_version":\s*"([^"]+)"').Groups[1].Value
if (-not $version) { throw "No content_version in $manifestPath" }

$layouts = Get-ChildItem (Join-Path $root 'therapist') -Filter '*.ini'
if (-not $layouts) { throw 'No layouts in therapist\' }
# v0.53.17-steam_win64.ini -> 0.53.17
$gameVersions = $layouts | ForEach-Object { if ($_.Name -match '^v(\d+\.\d+\.\d+)-') { $Matches[1] } } | Sort-Object { [version]$_ }
$newest = $gameVersions | Select-Object -Last 1
$short = $newest -replace '^0\.', ''

$name = "DwarfTherapist-v$version-win64-df$short"
$dist = Join-Path $root 'dist'
$out = Join-Path $dist $name
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Copy-Item $TherapistDir $out -Recurse
Get-ChildItem $out -Recurse -Include '*.log' | Remove-Item -Force
if (Test-Path (Join-Path $out 'log')) { Remove-Item (Join-Path $out 'log') -Recurse -Force }

$target = Join-Path $out 'data\memory_layouts\windows'
foreach ($l in $layouts) { Copy-Item $l.FullName $target -Force }

# launchers that read the manifest (PyLNP and the like) hide tools whose range
# stops short of the game's version
$manifest = [regex]::Replace($manifest, '("df_max_version":\s*")[^"]+(")', "`${1}$newest`${2}")
Set-Content -Path (Join-Path $out 'manifest.json') -Value $manifest -NoNewline -Encoding ASCII

$note = @"
Dwarf Therapist $version, repackaged for Dwarf Fortress $short (Steam, Windows)
=====================================================================

This is the official Dwarf Therapist $version release, unchanged, with
memory layouts added for game builds newer than the release supports:

$(($layouts | ForEach-Object { "    data\memory_layouts\windows\" + $_.Name }) -join "`r`n")

They were written by DFHack's devel/export-dt-ini against the Steam release
and tested with this version of Therapist. Without them, Therapist finds the
game and then stops with "Unidentified Game Version". manifest.json's
df_max_version is raised to match.

Dwarf Therapist is by Trey Stout and the Dwarf Therapist contributors, under
the MIT licence (LICENSE.txt). The Qt libraries are as shipped in the
official release. Official releases and source:
https://github.com/Dwarf-Therapist/Dwarf-Therapist

Repackaged by Classic Controls (https://github.com/AliensOnMars/df-classic-controls).
Labors set in Therapist only stick while its "Allow labor changes" option is
ticked; see docs/labors-and-therapist.md there.
"@
Set-Content -Path (Join-Path $out 'REPACKAGED-README.txt') -Value $note -Encoding ASCII

$zip = Join-Path $dist "$name.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $out -DestinationPath $zip
"built   $out"
"zipped  $zip ({0:N1} MB)" -f ((Get-Item $zip).Length / 1MB)
