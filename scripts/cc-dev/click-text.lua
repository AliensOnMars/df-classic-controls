-- Dev helper: click the middle of a piece of text wherever it is on screen
-- (the first place it appears, top to bottom), so that tests do not depend on
-- the interface grid's size.
-- Usage: cc-dev/click-text <text> [<occurrence>]

local gui = require('gui')
local gps = df.global.gps
local args = {...}
local text = args[1] or qerror('usage: cc-dev/click-text <text> [<occurrence>]')
local want = tonumber(args[2]) or 1

local w, h = dfhack.screen.getWindowSize()
local seen = 0
for y = 0, h - 1 do
    local chars = {}
    for x = 0, w - 1 do
        local pen = dfhack.screen.readTile(x, y)
        local ch = pen and pen.ch or 0
        chars[#chars + 1] = (ch > 31 and ch < 127) and string.char(ch) or ' '
    end
    local line = table.concat(chars)
    local from = 1
    while true do
        local i = line:find(text, from, true)
        if not i then break end
        seen = seen + 1
        if seen == want then
            local x = i - 1 + #text // 2
            gps.mouse_x, gps.mouse_y = x, y
            gps.precise_mouse_x = x * gps.tile_pixel_x + gps.tile_pixel_x // 2
            gps.precise_mouse_y = y * gps.tile_pixel_y + gps.tile_pixel_y // 2
            gui.simulateInput(dfhack.gui.getDFViewscreen(true), '_MOUSE_L')
            print(('clicked "%s" at %d,%d'):format(text, x, y))
            return
        end
        from = i + 1
    end
end
qerror(('"%s" not on screen'):format(text))
