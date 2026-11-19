# Dev helper: post real key-down / key-up messages to the Dwarf Fortress
# window, so the game runs them through its own keybindings (unlike
# cc-dev/keys, which feeds already-translated interface keys). The window does
# not need to be in front.
#
#   .\sendkeys.ps1 k up up shift+up shift+comma minus equals enter esc
#
# Each argument is one key press: an optional "shift+", "ctrl+" or "alt+"
# prefix, then a key name: a-z, 0-9, up/down/left/right, enter, esc, space,
# tab, comma, period, minus, equals, slash, pgup, pgdn, home, end.
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)][string[]]$Keys,
    [int]$DelayMs = 220
)

Add-Type @"
using System; using System.Runtime.InteropServices;
public class DfKeys {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
}
"@

$named = @{
    'up' = 0x26; 'down' = 0x28; 'left' = 0x25; 'right' = 0x27
    'enter' = 0x0D; 'esc' = 0x1B; 'space' = 0x20; 'tab' = 0x09; 'backspace' = 0x08
    'pgup' = 0x21; 'pgdn' = 0x22; 'end' = 0x23; 'home' = 0x24
    ',' = 0xBC; '.' = 0xBE; '-' = 0xBD; '=' = 0xBB; '/' = 0xBF
    ';' = 0xBA; "'" = 0xDE; '[' = 0xDB; ']' = 0xDD
    # spelled-out names: a bare "-" or "=" argument confuses PowerShell's
    # own parameter parsing
    'comma' = 0xBC; 'period' = 0xBE; 'minus' = 0xBD; 'equals' = 0xBB; 'slash' = 0xBF
}
$extended = @(0x26, 0x28, 0x25, 0x27, 0x21, 0x22, 0x23, 0x24)
$modifiers = @{ 'shift' = 0x10; 'ctrl' = 0x11; 'alt' = 0x12 }

$WM_KEYDOWN = 0x0100
$WM_KEYUP = 0x0101

$proc = Get-Process "Dwarf Fortress" -ErrorAction Stop | Select-Object -First 1
$hwnd = $proc.MainWindowHandle

function Send-Key([int]$vk, [bool]$down) {
    $scan = [DfKeys]::MapVirtualKey([uint32]$vk, 0)
    [int64]$lparam = 1 -bor ($scan -shl 16)
    if ($extended -contains $vk) { $lparam = $lparam -bor (1 -shl 24) }
    if ($down) {
        [void][DfKeys]::PostMessage($hwnd, $WM_KEYDOWN, [IntPtr]$vk, [IntPtr]$lparam)
    } else {
        $lparam = $lparam -bor (1 -shl 30) -bor (1 -shl 31)
        [void][DfKeys]::PostMessage($hwnd, $WM_KEYUP, [IntPtr]$vk, [IntPtr]$lparam)
    }
}

foreach ($spec in $Keys) {
    # "char:<" types a character without a key press: what the game's
    # character bindings ([KEY:<]) see when Shift+comma is really pressed.
    # A posted Shift does not shift the character Windows produces, so this
    # is the only way to deliver < > + and the like.
    if ($spec -like 'char:*') {
        $ch = [int][char]$spec.Substring(5, 1)
        [void][DfKeys]::PostMessage($hwnd, 0x0102, [IntPtr]$ch, [IntPtr]1)
        Start-Sleep -Milliseconds $DelayMs
        continue
    }
    $parts = $spec.ToLower() -split '\+'
    # a bare "+" key splits into empty parts; treat "shift+=" as the way to type it
    $keyName = $parts[-1]
    $mods = @()
    if ($parts.Count -gt 1) { $mods = $parts[0..($parts.Count - 2)] }

    if ($named.ContainsKey($keyName)) {
        $vk = $named[$keyName]
    } elseif ($keyName -match '^[a-z0-9]$') {
        $vk = [int][char]$keyName.ToUpper()
    } else {
        throw "unknown key '$spec'"
    }

    # No pause between a modifier and its key: SDL checks the real keyboard
    # after each batch of messages and releases a Shift that is not physically
    # held, so the two must arrive in the same batch.
    foreach ($m in $mods) { Send-Key $modifiers[$m] $true }
    Send-Key $vk $true
    # With a modifier the key goes down and up in the same batch too: holding
    # it while SDL drops the Shift makes the game report it again unshifted.
    if ($mods.Count -eq 0) { Start-Sleep -Milliseconds 40 }
    Send-Key $vk $false
    foreach ($m in $mods) { Send-Key $modifiers[$m] $false }
    Start-Sleep -Milliseconds $DelayMs
}
