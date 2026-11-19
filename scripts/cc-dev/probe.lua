-- Dev helper: experiments for opening the new UI's panels from code.
-- Usage:
--   cc-dev/probe state                 print compact view-sheet state + focus
--   cc-dev/probe find-ws               list a few workshops with ids and centres
--   cc-dev/probe click-map <x> <y> <z> centre view on a map tile and click it
--   cc-dev/probe close                 close any open view sheet (LEAVESCREEN)

local gui = require('gui')
local guidm = require('gui.dwarfmode')

local gps = df.global.gps
local mi = df.global.game.main_interface
local vs = mi.view_sheets

local args = {...}
local cmd = args[1]

local function state()
    local unids, itids = {}, {}
    for _, id in ipairs(vs.viewing_unid) do unids[#unids + 1] = id end
    for _, id in ipairs(vs.viewing_itid) do itids[#itids + 1] = id end
    print(('open=%s sheet=%s active_id=%d bld=%d unids={%s} itids={%s} sub_tab=%d context=%s'):format(
        tostring(vs.open), tostring(df.view_sheet_type[vs.active_sheet] or vs.active_sheet),
        vs.active_id, vs.viewing_bldid, table.concat(unids, ','), table.concat(itids, ','),
        vs.active_sub_tab, tostring(vs.context)))
    print(('viewing=%d,%d,%d cursor=%d,%d,%d window=%d,%d,%d'):format(
        vs.viewing_x, vs.viewing_y, vs.viewing_z,
        df.global.cursor.x, df.global.cursor.y, df.global.cursor.z,
        df.global.window_x, df.global.window_y, df.global.window_z))
    print('focus: ' .. table.concat(dfhack.gui.getCurFocus(true), ' | '))
end

-- pixel centre of a map tile in the viewport
local function map_tile_to_pixels(pos)
    local map_tile_px = gps.viewport_zoom_factor // 4
    local px = (pos.x - df.global.window_x) * map_tile_px + map_tile_px // 2
    local py = (pos.y - df.global.window_y) * map_tile_px + map_tile_px // 2
    return px, py
end

local function click_map(pos)
    dfhack.gui.revealInDwarfmodeMap(pos, true)
    local px, py = map_tile_to_pixels(pos)
    gps.precise_mouse_x = px
    gps.precise_mouse_y = py
    gps.mouse_x = px // gps.tile_pixel_x
    gps.mouse_y = py // gps.tile_pixel_y
    gui.simulateInput(dfhack.gui.getDFViewscreen(true), '_MOUSE_L')
    print(('clicked map %d,%d,%d -> px %d,%d grid %d,%d; getMousePos says %s'):format(
        pos.x, pos.y, pos.z, px, py, gps.mouse_x, gps.mouse_y,
        (function() local p = dfhack.gui.getMousePos(); return p and ('%d,%d,%d'):format(p.x, p.y, p.z) or 'nil' end)()))
end

if cmd == 'state' then
    state()
elseif cmd == 'find-ws' then
    local n = 0
    for _, bld in ipairs(df.global.world.buildings.other.WORKSHOP_ANY) do
        print(('id=%d %s centre=%d,%d,%d jobs=%d'):format(bld.id,
            df.workshop_type[bld.type] or '?', bld.centerx, bld.centery, bld.z, #bld.jobs))
        n = n + 1
        if n >= 8 then break end
    end
elseif cmd == 'click-map' then
    click_map(xyz2pos(tonumber(args[2]), tonumber(args[3]), tonumber(args[4])))
    state()
elseif cmd == 'mouse' then
    -- cc-dev/probe mouse <KEY> <x> <y> <z>: put the mouse on a map tile (no
    -- recentring) and feed one mouse key, e.g. _MOUSE_L_DOWN or _MOUSE_L
    local pos = xyz2pos(tonumber(args[3]), tonumber(args[4]), tonumber(args[5]))
    local px, py = map_tile_to_pixels(pos)
    gps.precise_mouse_x, gps.precise_mouse_y = px, py
    gps.mouse_x, gps.mouse_y = px // gps.tile_pixel_x, py // gps.tile_pixel_y
    gui.simulateInput(dfhack.gui.getDFViewscreen(true), args[2])
    local s = df.global.selection_rect
    print(('%s at %d,%d,%d | sel %d,%d -> %d,%d | stockpile.doing_rectangle=%s cur_bld=%s'):format(
        args[2], pos.x, pos.y, pos.z, s.start_x, s.start_y, s.end_x, s.end_y,
        tostring(mi.stockpile.doing_rectangle), tostring(mi.stockpile.cur_bld)))
elseif cmd == 'close' then
    gui.simulateInput(dfhack.gui.getDFViewscreen(true), 'LEAVESCREEN')
    state()
else
    qerror('unknown subcommand')
end
