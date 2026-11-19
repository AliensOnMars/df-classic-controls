-- Dev helper: simulate a left click at an interface-grid position on the
-- topmost DF viewscreen.
-- Usage: cc-dev/click <x> <y>

local gui = require('gui')
local gps = df.global.gps

local args = {...}
local x = tonumber(args[1]) or qerror('usage: cc-dev/click <x> <y>')
local y = tonumber(args[2]) or qerror('usage: cc-dev/click <x> <y>')

gps.mouse_x = x
gps.mouse_y = y
gps.precise_mouse_x = x * gps.tile_pixel_x + gps.tile_pixel_x // 2
gps.precise_mouse_y = y * gps.tile_pixel_y + gps.tile_pixel_y // 2

gui.simulateInput(dfhack.gui.getDFViewscreen(true), '_MOUSE_L')
print(('clicked %d,%d (px %d,%d)'):format(x, y, gps.precise_mouse_x, gps.precise_mouse_y))
