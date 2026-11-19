-- Dev helper: walk the game's build menu and print every entry with the
-- hotkeys that reach it.
-- Usage (from the bare map): cc-dev/build-tree

local gui = require('gui')

local mi = df.global.game.main_interface
local con = mi.construction

local function feed(key)
    gui.simulateInput(dfhack.gui.getDFViewscreen(true), key)
end

local function key_name(code)
    return df.interface_key[code] or tostring(code)
end

-- Esc closes the whole build menu whatever the depth, so every category is
-- reached from a fresh menu
local function open_path(path)
    if mi.bottom_mode_selected ~= -1 then feed('LEAVESCREEN') end
    feed('D_BUILDING')
    for _, key in ipairs(path) do feed(key) end
end

local function walk(path, depth)
    open_path(path)
    local page = con.page[#con.page - 1]
    if #con.page ~= #path + 1 then
        print(('!! expected %d pages, have %d'):format(#path + 1, #con.page))
        return
    end
    local entries = {}
    for _, b in ipairs(page.bb_button) do
        entries[#entries + 1] = {
            str=b.str, hotkey=b.hotkey, category=b.category,
            type=b.type, subtype=b.subtype, custom=b.custom_building_id,
        }
    end
    for _, e in ipairs(entries) do
        local indent = string.rep('  ', depth)
        if e.category >= 0 then
            print(('%sCATEGORY %s (%s) [%s]'):format(indent, e.str,
                df.construction_category_type[e.category], key_name(e.hotkey)))
            local sub = copyall(path)
            sub[#sub + 1] = e.hotkey
            walk(sub, depth + 1)
        else
            print(('%s%s | %s %d %d | %s'):format(indent, e.str,
                tostring(df.building_type[e.type] or e.type), e.subtype, e.custom, key_name(e.hotkey)))
        end
    end
end

walk({}, 0)
feed('LEAVESCREEN')
print('focus after: ' .. table.concat(dfhack.gui.getCurFocus(true), ' , '))
