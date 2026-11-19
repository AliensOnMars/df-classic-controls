-- Dev helper: a one-tile throwaway stockpile to test stockpile screens on,
-- so that the player's own stockpiles are never the test subject.
-- Usage:
--   cc-dev/test-pile make     build it on a free floor tile and open its panel
--   cc-dev/test-pile open     open its panel again
--   cc-dev/test-pile remove   delete it and put the building counter back
--   cc-dev/test-pile dump     print its settings flags and container limits

local mi = df.global.game.main_interface
local args = {...}

-- a second argument names another pile ("cc-dev/test-pile make b"), for
-- tests that need two, such as links
local STATE = dfhack.getDFPath() .. '/dfhack-config/cc-test-pile' .. (args[2] or '') .. '.txt'

local function saved()
    local f = io.open(STATE)
    if not f then return end
    local id, next_id = f:read('n', 'n')
    f:close()
    return id, next_id
end

local function free_floor()
    local map = df.global.world.map
    for z = map.z_count - 1, 0, -1 do
        for y = 5, map.y_count - 6 do
            for x = 5, map.x_count - 6 do
                local tt = dfhack.maps.getTileType(x, y, z)
                local des, occ = dfhack.maps.getTileFlags(x, y, z)
                if tt and des and occ
                    and df.tiletype.attrs[tt].shape == df.tiletype_shape.FLOOR
                    and df.tiletype.attrs[tt].material ~= df.tiletype_material.CONSTRUCTION
                    and occ.building == df.tile_building_occ.None
                    and not des.hidden and des.flow_size == 0 and not des.outside
                    and not dfhack.buildings.findAtTile(x, y, z)
                    and #(dfhack.buildings.findCivzonesAt(xyz2pos(x, y, z)) or {}) == 0
                then
                    return xyz2pos(x, y, z)
                end
            end
        end
    end
end

local function open_panel(bld)
    mi.stockpile.cur_bld = bld
    mi.bottom_mode_selected = df.main_bottom_mode_type.STOCKPILE
end

local cmd = args[1]
if cmd == 'make' then
    if saved() then qerror('a test pile already exists; remove it first') end
    local pos = free_floor() or qerror('no free indoor floor tile found')
    local next_id = df.global.building_next_id
    local bld, err = dfhack.buildings.constructBuilding{
        type=df.building_type.Stockpile, abstract=true, pos=pos, width=1, height=1,
    }
    if not bld then qerror('could not build: ' .. tostring(err)) end
    local f = io.open(STATE, 'w')
    f:write(bld.id, ' ', next_id, '\n')
    f:close()
    open_panel(bld)
    print(('test pile %d at %d,%d,%d'):format(bld.id, pos.x, pos.y, pos.z))
elseif cmd == 'open' then
    local id = saved() or qerror('no test pile')
    open_panel(df.building.find(id) or qerror('test pile is gone'))
elseif cmd == 'remove' then
    local id, next_id = saved()
    if not id then qerror('no test pile') end
    local bld = df.building.find(id)
    if mi.stockpile.cur_bld == bld then
        mi.custom_stockpile.open = false
        mi.stockpile.cur_bld = nil
        mi.bottom_mode_selected = df.main_bottom_mode_type.NONE
    end
    if bld then dfhack.buildings.deconstruct(bld) end
    if df.global.building_next_id == id + 1 then df.global.building_next_id = next_id end
    os.remove(STATE)
    print('removed; stockpiles now', #df.global.world.buildings.other.STOCKPILE,
          'next building id', df.global.building_next_id)
elseif cmd == 'dump' then
    local id = saved() or qerror('no test pile')
    local bld = df.building.find(id) or qerror('test pile is gone')
    local on = {}
    for name, value in pairs(bld.settings.flags) do
        if value == true then on[#on + 1] = name end
    end
    table.sort(on)
    print('groups: ' .. table.concat(on, ' '))
    print(('barrels %d bins %d wheelbarrows %d'):format(
        bld.storage.max_barrels, bld.storage.max_bins, bld.storage.max_wheelbarrows))
    local misc = {}
    for name, value in pairs(bld.settings.misc) do
        misc[#misc + 1] = name .. '=' .. tostring(value)
    end
    table.sort(misc)
    print('misc: ' .. table.concat(misc, ' '))
else
    qerror('usage: cc-dev/test-pile make | open | remove | dump')
end
