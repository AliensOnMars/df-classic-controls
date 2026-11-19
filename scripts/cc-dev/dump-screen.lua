-- Dev helper: print the text currently on DF's screen grid, one line per row.
-- Usage: cc-dev/dump-screen [<lua pattern>] [<x1> <x2>]
--   pattern: only rows matching are printed ('.' for all)
--   x1 x2:   only this column range is printed

local args = {...}
local filter = args[1]
if filter == '.' then filter = nil end
local w, h = dfhack.screen.getWindowSize()
local x1 = tonumber(args[2]) or 0
local x2 = tonumber(args[3]) or (w - 1)

for y = 0, h - 1 do
    local chars = {}
    for x = x1, x2 do
        local pen = dfhack.screen.readTile(x, y)
        local ch = pen and pen.ch or 0
        if ch <= 32 or ch > 126 then
            chars[#chars + 1] = ' '
        else
            chars[#chars + 1] = string.char(ch)
        end
    end
    local line = table.concat(chars):gsub('%s+$', '')
    if #line > 0 and (not filter or line:find(filter)) then
        print(('%3d|%s'):format(y, line))
    end
end
