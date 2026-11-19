-- Dev helper: print the widget tree of one of the info window's newer tabs.
-- Usage: cc-dev/widgets creatures|labor|justice [max depth, default 4]
-- Rows of a list are not printed, only their count; pages of a tab bar other
-- than the current one are named but not opened.

local info = df.global.game.main_interface.info
local args = {...}
local root = info[args[1] or 'creatures'] or qerror('no such tab')
local max_depth = tonumber(args[2]) or 4
local children = dfhack.gui.getWidgetChildren

local function kind(w)
    return tostring(w._type):match('<type: (.-)>') or '?'
end

local function show(w, depth)
    local ok, kids = pcall(children, w)
    if not ok or not kids then return end
    local parent_kind = kind(w)
    for i, c in ipairs(kids) do
        local k = kind(c)
        local note = ''
        if k == 'widget_tabs' then note = ' cur=' .. c.cur_idx end
        if k == 'widget_scroll_rows' then
            note = (' rows=%d scroll=%d visible=%d'):format(#children(c), c.scroll, c.num_visible)
        end
        local r = c.rect
        print(('%s%d %s [%s] %d,%d-%d,%d%s'):format(string.rep('  ', depth), i, k:gsub('^widget_', ''),
            tostring(c.name), r.x1, r.y1, r.x2, r.y2, note))
        local current = parent_kind ~= 'widget_tabs' or i == w.cur_idx + 1
        if depth < max_depth and k ~= 'widget_scroll_rows' and current then
            show(c, depth + 1)
        end
    end
end

show(root, 0)
