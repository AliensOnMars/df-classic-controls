-- Dev helper: a one-tile throwaway zone to test zone screens on, so that the
-- player's own zones are never the test subject.
-- Usage:
--   cc-dev/test-zone make <type>   e.g. Pen, Bedroom, Pond, MeetingHall (df.civzone_type)
--   cc-dev/test-zone open          open its panel again
--   cc-dev/test-zone remove        delete it and put the building counter back

local mi = df.global.game.main_interface
local args = {...}
local STATE = dfhack.getDFPath() .. '/dfhack-config/cc-test-zone.txt'

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

local function open_panel(zone)
    mi.civzone.cur_bld = zone
    mi.civzone.list:resize(0)
    mi.civzone.list:insert('#', zone)
    mi.bottom_mode_selected = df.main_bottom_mode_type.ZONE
end

local cmd = args[1]
if cmd == 'make' then
    if saved() then qerror('a test zone already exists; remove it first') end
    local kind = df.civzone_type[args[2] or 'Pen'] or qerror('no such zone type')
    local pos = free_floor() or qerror('no free indoor floor tile found')
    local next_id = df.global.building_next_id
    local zone, err = dfhack.buildings.constructBuilding{
        type=df.building_type.Civzone, subtype=kind, abstract=true, pos=pos, width=1, height=1,
    }
    if not zone then qerror('could not build: ' .. tostring(err)) end
    local f = io.open(STATE, 'w')
    f:write(zone.id, ' ', next_id, '\n')
    f:close()
    open_panel(zone)
    print(('test zone %d (%s) at %d,%d,%d'):format(zone.id, df.civzone_type[kind], pos.x, pos.y, pos.z))
elseif cmd == 'open' then
    local id = saved() or qerror('no test zone')
    open_panel(df.building.find(id) or qerror('test zone is gone'))
elseif cmd == 'remove' then
    local id, next_id = saved()
    if not id then qerror('no test zone') end
    -- A chooser opened from the zone's panel (animals, owner, location) keeps
    -- a pointer to the zone: deleting the zone under it crashes the game.
    local focus = table.concat(dfhack.gui.getFocusStrings(dfhack.gui.getDFViewscreen(true)), ' ')
    if focus:find('Selector') or mi.location_selector.open then
        qerror('a chooser is still open on the zone; close it first (' .. focus .. ')')
    end
    local zone = df.building.find(id)
    if mi.civzone.cur_bld == zone then
        mi.civzone.cur_bld = nil
        mi.civzone.list:resize(0)
        mi.bottom_mode_selected = df.main_bottom_mode_type.NONE
    end
    if zone then dfhack.buildings.deconstruct(zone) end
    if df.global.building_next_id == id + 1 then df.global.building_next_id = next_id end
    os.remove(STATE)
    print('removed; zones now', #df.global.world.buildings.other.ACTIVITY_ZONE,
          'next building id', df.global.building_next_id)
else
    qerror('usage: cc-dev/test-zone make <type> | open | remove')
end
