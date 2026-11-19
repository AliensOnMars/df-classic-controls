# Dev helper: post a real left-button drag to the Dwarf Fortress window, from
# one map tile to another, on the level in view (the window need not be in
# front). Tiles are map coordinates; the script turns them into pixels from
# the viewport DFHack reports.
#
#   .\sendmouse.ps1 101 17 103 17          drag from 101,17 to 103,17
#   .\sendmouse.ps1 101 17                  a single click on 101,17
param(
    [Parameter(Mandatory = $true)][int]$X1,
    [Parameter(Mandatory = $true)][int]$Y1,
    [int]$X2 = [int]::MinValue,
    [int]$Y2 = [int]::MinValue,
    [string]$DfhackRun = ""
)
if ($X2 -eq [int]::MinValue) { $X2 = $X1; $Y2 = $Y1 }

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

if (-not $DfhackRun) { $DfhackRun = Find-DfhackRun (Find-GameDir) }
if (-not $DfhackRun) { throw "Could not find dfhack-run.exe (is the game running?): pass -DfhackRun <path>" }

Add-Type @"
using System; using System.Runtime.InteropServices;
public class DfMouse {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[void][DfMouse]::SetProcessDPIAware()
$proc = Get-Process "Dwarf Fortress" -ErrorAction Stop | Select-Object -First 1
$hwnd = $proc.MainWindowHandle
$r = New-Object DfMouse+RECT
[void][DfMouse]::GetClientRect($hwnd, [ref]$r)

$vp = (& $DfhackRun lua "local vp=require('gui.dwarfmode').Viewport.get(); print(vp.x1, vp.y1, vp.width, vp.height)" | Select-Object -First 1) -split '\s+'
$vx = [int]$vp[0]; $vy = [int]$vp[1]; $vw = [int]$vp[2]; $vh = [int]$vp[3]
$tw = $r.R / $vw; $th = $r.B / $vh

function Px([int]$tx, [int]$ty) {
    $px = [int](($tx - $vx) * $tw + $tw / 2); $py = [int](($ty - $vy) * $th + $th / 2)
    return [IntPtr](($py -shl 16) -bor ($px -band 0xFFFF))
}
$WM_MOUSEMOVE = 0x0200; $WM_LBUTTONDOWN = 0x0201; $WM_LBUTTONUP = 0x0202; $MK_LBUTTON = [IntPtr]1

$a = Px $X1 $Y1; $b = Px $X2 $Y2
[void][DfMouse]::PostMessage($hwnd, $WM_MOUSEMOVE, [IntPtr]0, $a); Start-Sleep -Milliseconds 150
[void][DfMouse]::PostMessage($hwnd, $WM_LBUTTONDOWN, $MK_LBUTTON, $a); Start-Sleep -Milliseconds 200
# a few steps along the way, as a hand would
foreach ($f in 0.33, 0.66, 1.0) {
    $mx = [int]($X1 + ($X2 - $X1) * $f); $my = [int]($Y1 + ($Y2 - $Y1) * $f)
    [void][DfMouse]::PostMessage($hwnd, $WM_MOUSEMOVE, $MK_LBUTTON, (Px $mx $my)); Start-Sleep -Milliseconds 150
}
[void][DfMouse]::PostMessage($hwnd, $WM_LBUTTONUP, [IntPtr]0, $b); Start-Sleep -Milliseconds 200
"dragged $X1,$Y1 -> $X2,$Y2 (tile ${tw}x${th} px, viewport at $vx,$vy)"
