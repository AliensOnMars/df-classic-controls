# Dev helper: capture the Dwarf Fortress window (even when it is not in front)
# to a PNG, optionally cropped and scaled.
#   .\capture.ps1 -Out shot.png [-X 0 -Y 0 -W 1920 -H 1080] [-Scale 0.5]
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$X = 0,
    [int]$Y = 0,
    [int]$W = 0,
    [int]$H = 0,
    [double]$Scale = 1.0
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class DfCap {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[void][DfCap]::SetProcessDPIAware()

$proc = Get-Process "Dwarf Fortress" -ErrorAction Stop | Select-Object -First 1
$hwnd = $proc.MainWindowHandle
$rect = New-Object DfCap+RECT
[void][DfCap]::GetClientRect($hwnd, [ref]$rect)
if ($rect.R -le 0) { throw "Dwarf Fortress window has no client area (minimised?)" }

$full = New-Object System.Drawing.Bitmap $rect.R, $rect.B
$g = [System.Drawing.Graphics]::FromImage($full)
$hdc = $g.GetHdc()
# 2 = PW_RENDERFULLCONTENT, needed for GPU-rendered windows
[void][DfCap]::PrintWindow($hwnd, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()

if ($W -le 0) { $W = $rect.R - $X }
if ($H -le 0) { $H = $rect.B - $Y }
$W = [Math]::Min($W, $rect.R - $X)
$H = [Math]::Min($H, $rect.B - $Y)

$outW = [int]($W * $Scale)
$outH = [int]($H * $Scale)
$result = New-Object System.Drawing.Bitmap $outW, $outH
$g2 = [System.Drawing.Graphics]::FromImage($result)
$g2.InterpolationMode = 'HighQualityBicubic'
$src = New-Object System.Drawing.Rectangle $X, $Y, $W, $H
$dst = New-Object System.Drawing.Rectangle 0, 0, $outW, $outH
$g2.DrawImage($full, $dst, $src, [System.Drawing.GraphicsUnit]::Pixel)
$g2.Dispose()
$result.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$full.Dispose()
$result.Dispose()
Write-Output "window $($rect.R)x$($rect.B); saved ${outW}x${outH} to $Out"
