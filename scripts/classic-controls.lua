-- Classic (pre-Steam) keyboard controls for the Steam version of Dwarf Fortress.
--@ module = true
--
-- Everything here is a DFHack overlay on the fortress-mode screen. It never
-- edits interface.txt: it intercepts key presses before the game sees them and
-- either translates them to the game's own actions or drives the new UI's
-- panels directly. Disable the overlay ("overlay disable classic-controls.keys")
-- and the game is back to stock behaviour.

local gui = require('gui')
local guidm = require('gui.dwarfmode')
local overlay = require('plugins.overlay')
local utils = require('utils')
local widgets = require('gui.widgets')
local dialogs = require('gui.dialogs')

local gps = df.global.gps
local mi = df.global.game.main_interface
local vs = mi.view_sheets
local con = mi.construction
local buildreq = df.global.buildreq

local BOTTOM = df.main_bottom_mode_type

-- how far (in tiles) q and v will reach to snap to a building / unit
local SNAP_RANGE = 10

---------------------------------------------------------------------------
-- key tables (47.05 key -> what it does in the new UI)
---------------------------------------------------------------------------

-- Each entry is a sequence of the game's own interface keys to feed, in order.

-- active on the bare fortress map (focus dwarfmode/Default)
local TOP_KEYS = {
    CUSTOM_D = {'D_DESIGNATE_DIG'},      -- d: designations (starts on mine, as before)
    CUSTOM_I = {'D_CIVZONE'},            -- i: zones
    CUSTOM_J = {'D_JOBLIST'},            -- j: job list
    CUSTOM_A = {'D_ANNOUNCE'},           -- a: announcements
    CUSTOM_W = {'D_BURROWS'},            -- w: burrows
    CUSTOM_H = {'D_HAULING'},            -- h: hauling
    CUSTOM_L = {'D_LOCATIONS'},          -- l: locations
    CUSTOM_S = {'D_SQUADS'},             -- s: squads
    CUSTOM_M = {'D_SQUADS'},             -- m: military
    CUSTOM_C = {'D_WORLD'},              -- c: civilisations / world
    CUSTOM_Z = {'D_STOCKS'},             -- z: status (stocks is the closest surviving piece)
    CUSTOM_SHIFT_L = {'D_ARTLIST'},      -- L: artifacts
    CUSTOM_SHIFT_J = {'D_JUSTICE'},      -- J: justice (displaced from j)
}

local DIG, SMOOTH = 'D_DESIGNATE_DIG', 'D_DESIGNATE_SMOOTH'

-- active in any designation tool (focus dwarfmode/Designate/*): the old "d" menu
local DESIGNATE_KEYS = {
    CUSTOM_D = {DIG, 'DESIGNATE_DIG'},
    CUSTOM_H = {DIG, 'DESIGNATE_CHANNEL'},
    CUSTOM_U = {DIG, 'DESIGNATE_STAIR_UPDOWN'},
    CUSTOM_J = {DIG, 'DESIGNATE_STAIR_UPDOWN'},
    CUSTOM_I = {DIG, 'DESIGNATE_STAIR_UPDOWN'},
    CUSTOM_R = {DIG, 'DESIGNATE_RAMP'},
    CUSTOM_Z = {DIG, 'DESIGNATE_DIG_REMOVE_STAIRS_RAMPS'},
    CUSTOM_T = {'D_DESIGNATE_CHOP'},
    CUSTOM_P = {'D_DESIGNATE_GATHER'},
    CUSTOM_S = {SMOOTH, 'DESIGNATE_SMOOTH'},
    CUSTOM_E = {SMOOTH, 'DESIGNATE_ENGRAVE'},
    CUSTOM_A = {SMOOTH, 'DESIGNATE_FORTIFY'},
    CUSTOM_SHIFT_F = {SMOOTH, 'DESIGNATE_FORTIFY'},
    CUSTOM_SHIFT_T = {SMOOTH, 'DESIGNATE_TRACK'},
    CUSTOM_X = {'D_DESIGNATE_ERASE'},
    CUSTOM_B = {'D_DESIGNATE_ITEMS'},
    CUSTOM_O = {'D_DESIGNATE_TRAFFIC'},
}

-- inside d-b (item properties)
local ITEM_KEYS = {
    CUSTOM_C = {'DESIGNATE_CLAIM'},
    CUSTOM_F = {'DESIGNATE_UNCLAIM'},
    CUSTOM_M = {'DESIGNATE_MELT'},
    CUSTOM_SHIFT_M = {'DESIGNATE_NO_MELT'},
    CUSTOM_D = {'DESIGNATE_DUMP'},
    CUSTOM_SHIFT_D = {'DESIGNATE_NO_DUMP'},
    CUSTOM_H = {'DESIGNATE_HIDE'},
    CUSTOM_SHIFT_H = {'DESIGNATE_NO_HIDE'},
}

-- inside d-o (traffic)
local TRAFFIC_KEYS = {
    CUSTOM_H = {'DESIGNATE_TRAFFIC_HIGH'},
    CUSTOM_N = {'DESIGNATE_TRAFFIC_NORMAL'},
    CUSTOM_L = {'DESIGNATE_TRAFFIC_LOW'},
    CUSTOM_R = {'DESIGNATE_TRAFFIC_RESTRICTED'},
}

local ITEM_DESIGNATIONS = utils.invert{
    'CLAIM', 'UNCLAIM', 'MELT', 'NO_MELT', 'DUMP', 'NO_DUMP', 'HIDE', 'NO_HIDE',
}
local TRAFFIC_DESIGNATIONS = utils.invert{
    'DESIGNATE_TRAFFIC_HIGH', 'DESIGNATE_TRAFFIC_NORMAL',
    'DESIGNATE_TRAFFIC_LOW', 'DESIGNATE_TRAFFIC_RESTRICTED',
}

-- rows of {key, label, the designation tools it stands for...}
local DESIGNATE_LEGEND = {
    {{'d', 'mine', 'DIG_DIG'}, {'h', 'channel', 'DIG_CHANNEL'},
     {'i', 'stairs', 'DIG_STAIR_UPDOWN', 'DIG_STAIR_UP', 'DIG_STAIR_DOWN'}},
    {{'r', 'ramp', 'DIG_RAMP'}, {'z', 'remove stairs/ramps', 'DIG_REMOVE_STAIRS_RAMPS'}},
    {{'t', 'chop', 'CHOP'}, {'p', 'gather plants', 'GATHER'}},
    {{'s', 'smooth', 'SMOOTH'}, {'e', 'engrave', 'ENGRAVE'}, {'a', 'fortify', 'FORTIFY'}},
    {{'T', 'track', 'TRACK'}, {'x', 'remove designation', 'ERASE'}},
    {{'b', 'item properties'}, {'o', 'traffic'}},
}
local ITEM_LEGEND = {
    {{'c', 'claim', 'CLAIM'}, {'f', 'forbid', 'UNCLAIM'}},
    {{'d', 'dump', 'DUMP'}, {'D', 'undump', 'NO_DUMP'}},
    {{'m', 'melt', 'MELT'}, {'M', 'unmelt', 'NO_MELT'}},
    {{'h', 'hide', 'HIDE'}, {'H', 'unhide', 'NO_HIDE'}},
}
local TRAFFIC_LEGEND = {
    {{'h', 'high', 'DESIGNATE_TRAFFIC_HIGH'}, {'n', 'normal', 'DESIGNATE_TRAFFIC_NORMAL'}},
    {{'l', 'low', 'DESIGNATE_TRAFFIC_LOW'}, {'r', 'restricted', 'DESIGNATE_TRAFFIC_RESTRICTED'}},
}

---------------------------------------------------------------------------
-- build menu tables (the old "b" list and its submenus)
---------------------------------------------------------------------------

local BUILD_KEY_PREFIX = 'HOTKEY_BUILDING_'

-- Where each building lives in the game's own build menu: the category
-- hotkeys to press, in order, before the building's own hotkey. All names are
-- interface keys without their HOTKEY_BUILDING_ prefix. The game kept the old
-- key *names* and only moved the keys around, which is what makes this table
-- possible. Run cc-dev/build-tree to regenerate it after a game update.
local NATIVE_BUILD_MENU = {
    {path={}, leaves={'TRADEDEPOT'}},
    {path={'FURNITURE'}, leaves={
        'BED', 'CHAIR', 'TABLE', 'BOX', 'CABINET', 'COFFIN', 'SLAB', 'STATUE',
        'TRACTION_BENCH', 'BOOKCASE', 'DISPLAY_FURNITURE', 'OFFERING_PLACE', 'INSTRUMENT',
    }},
    {path={'PORTALS'}, leaves={'DOOR', 'HATCH'}},
    {path={'CONSTRUCTION'}, leaves={
        'CONSTRUCTION_WALL', 'CONSTRUCTION_FLOOR', 'CONSTRUCTION_RAMP',
        'CONSTRUCTION_STAIR_UPDOWN', 'BRIDGE', 'ROAD_PAVED', 'ROAD_DIRT',
        'CONSTRUCTION_FORTIFICATION', 'GRATE_WALL', 'GRATE_FLOOR', 'BARS_VERTICAL',
        'BARS_FLOOR', 'WINDOW_GLASS', 'WINDOW_GEM', 'SUPPORT', 'CONSTRUCTION_TRACK',
        'CONSTRUCTION_TRACK_STOP',
    }},
    {path={'MACHINE'}, leaves={
        'TRAP_LEVER', 'WELL', 'FLOODGATE', 'MACHINE_SCREW_PUMP', 'MACHINE_WATER_WHEEL',
        'MACHINE_WINDMILL', 'MACHINE_GEAR_ASSEMBLY', 'MACHINE_AXLE_HORIZONTAL',
        'MACHINE_AXLE_VERTICAL', 'WORKSHOP_MILLSTONE', 'MACHINE_ROLLERS',
    }},
    {path={'CAGES_CHAINS'}, leaves={'CHAIN', 'CAGE', 'ANIMALTRAP'}},
    {path={'TRAP'}, leaves={
        'TRAP_TRIGGER', 'TRAP_STONE', 'TRAP_WEAPON', 'TRAP_CAGE', 'TRAP_SPIKE',
    }},
    {path={'MILITARY'}, leaves={
        'ARCHERYTARGET', 'WEAPONRACK', 'ARMORSTAND', 'SIEGEENGINE_BALLISTA',
        'SIEGEENGINE_CATAPULT',
    }},
    {path={'WORKSHOP'}, leaves={
        'WORKSHOP_ASHERY', 'WORKSHOP_BOWYER', 'WORKSHOP_CARPENTER', 'WORKSHOP_CRAFTSMAN',
        'WORKSHOP_JEWELER', 'WORKSHOP_LAVAMILL', 'WORKSHOP_MECHANIC', 'WORKSHOP_METALSMITH',
        'WORKSHOP_SIEGE', 'WORKSHOP_MASON',
    }},
    {path={'WORKSHOP', 'WORKSHOPS_CLOTHING_LEATHER'}, leaves={
        'WORKSHOP_LEATHER', 'WORKSHOP_LOOM', 'WORKSHOP_CLOTHES', 'WORKSHOP_DYER',
    }},
    {path={'WORKSHOP', 'FARMING'}, leaves={
        'FARMPLOT', 'WORKSHOP_STILL', 'WORKSHOP_BUTCHER', 'WORKSHOP_TANNER',
        'WORKSHOP_FISHERY', 'WORKSHOP_KITCHEN', 'WORKSHOP_FARMER', 'WORKSHOP_QUERN',
        'KENNEL', 'NEST_BOX', 'HIVE',
    }},
    {path={'WORKSHOP', 'FURNACE'}, leaves={
        'FURNACE_GLASS', 'FURNACE_KILN', 'FURNACE_GLASS_LAVA', 'FURNACE_KILN_LAVA',
        'FURNACE_SMELTER_LAVA', 'FURNACE_SMELTER', 'FURNACE_WOOD',
    }},
}

local NATIVE_BUILD_PATH = {}
for _, group in ipairs(NATIVE_BUILD_MENU) do
    for _, leaf in ipairs(group.leaves) do
        NATIVE_BUILD_PATH[leaf] = group.path
    end
end

-- The 0.47.05 build menu: its keys, its order and its submenus. Each entry is
-- {keys, label, building} or {keys, label, submenu=id}. Keys are written as
-- the player types them: 'a', 'A' (shift), 'Alt+a'; several separated by
-- spaces all do the same thing. `native` is the page of the game's own menu
-- to show alongside a submenu.
local CLASSIC_BUILD = {
    top = {
        title='Building',
        {'a', 'Armor stand', 'ARMORSTAND'},
        {'b', 'Bed', 'BED'},
        {'c', 'Seat', 'CHAIR'},
        {'n', 'Burial receptacle', 'COFFIN'},
        {'d', 'Door', 'DOOR'},
        {'x', 'Floodgate', 'FLOODGATE'},
        {'H', 'Floor hatch', 'HATCH'},
        {'W', 'Wall grate', 'GRATE_WALL'},
        {'G', 'Floor grate', 'GRATE_FLOOR'},
        {'B', 'Vertical bars', 'BARS_VERTICAL'},
        {'Alt+b', 'Floor bars', 'BARS_FLOOR'},
        {'f', 'Cabinet', 'CABINET'},
        {'h', 'Container', 'BOX'},
        {'k', 'Kennels', 'KENNEL'},
        {'p', 'Farm plot', 'FARMPLOT'},
        {'r', 'Weapon rack', 'WEAPONRACK'},
        {'s', 'Statue', 'STATUE'},
        {'Alt+s', 'Slab', 'SLAB'},
        {'t', 'Table', 'TABLE'},
        {'o', 'Paved road', 'ROAD_PAVED'},
        {'O', 'Dirt road', 'ROAD_DIRT'},
        {'g', 'Bridge', 'BRIDGE'},
        {'l', 'Well', 'WELL'},
        {'i', 'Siege engines', submenu='i'},
        {'w', 'Workshops', submenu='w'},
        {'e', 'Furnaces', submenu='e'},
        {'y', 'Glass window', 'WINDOW_GLASS'},
        {'Y', 'Gem window', 'WINDOW_GEM'},
        {'C', 'Wall/floor/stairs/track', submenu='C'},
        {'D', 'Trade depot', 'TRADEDEPOT'},
        {'T', 'Traps/levers', submenu='T'},
        {'M', 'Machine components', submenu='M'},
        {'S', 'Support', 'SUPPORT'},
        {'m', 'Animal trap', 'ANIMALTRAP'},
        {'v', 'Restraint', 'CHAIN'},
        {'j', 'Cage', 'CAGE'},
        {'A', 'Archery target', 'ARCHERYTARGET'},
        {'R', 'Traction bench', 'TRACTION_BENCH'},
        {'N', 'Nest box', 'NEST_BOX'},
        {'Alt+h', 'Hive', 'HIVE'},
        {'Alt+a', 'Offering place', 'OFFERING_PLACE'},
        {'Alt+c', 'Bookcase', 'BOOKCASE'},
        {'F', 'Display furniture', 'DISPLAY_FURNITURE'},
        {'I', 'Instrument', 'INSTRUMENT'},
    },
    i = {
        title='Siege engines', native={'MILITARY'},
        {'b', 'Ballista', 'SIEGEENGINE_BALLISTA'},
        {'c', 'Catapult', 'SIEGEENGINE_CATAPULT'},
        -- new in the Steam version and without a hotkey there: reached by
        -- clicking its name in the game's own menu
        {'t', 'Bolt thrower', click='Bolt thrower', path={'MILITARY'}, new=true},
    },
    w = {
        title='Workshops', native={'WORKSHOP'},
        {'e', 'Leather works', 'WORKSHOP_LEATHER'},
        {'q', 'Quern', 'WORKSHOP_QUERN'},
        {'M', 'Millstone', 'WORKSHOP_MILLSTONE'},
        {'o', 'Loom', 'WORKSHOP_LOOM'},
        {'k', "Clothier's shop", 'WORKSHOP_CLOTHES'},
        {'b', "Bowyer's workshop", 'WORKSHOP_BOWYER'},
        {'c', "Carpenter's workshop", 'WORKSHOP_CARPENTER'},
        {'f', "Metalsmith's forge", 'WORKSHOP_METALSMITH'},
        {'v', 'Magma forge', 'WORKSHOP_LAVAMILL'},
        {'j', "Jeweler's workshop", 'WORKSHOP_JEWELER'},
        {'m', "Mason's workshop", 'WORKSHOP_MASON'},
        {'u', "Butcher's shop", 'WORKSHOP_BUTCHER'},
        {'n', "Tanner's shop", 'WORKSHOP_TANNER'},
        {'d', "Dyer's shop", 'WORKSHOP_DYER'},
        {'r', "Craftsdwarf's workshop", 'WORKSHOP_CRAFTSMAN'},
        {'s', 'Siege workshop', 'WORKSHOP_SIEGE'},
        {'t', "Mechanic's workshop", 'WORKSHOP_MECHANIC'},
        {'l', 'Still', 'WORKSHOP_STILL'},
        {'w', "Farmer's workshop", 'WORKSHOP_FARMER'},
        {'z', 'Kitchen', 'WORKSHOP_KITCHEN'},
        {'h', 'Fishery', 'WORKSHOP_FISHERY'},
        {'y', 'Ashery', 'WORKSHOP_ASHERY'},
    },
    e = {
        title='Furnaces', native={'WORKSHOP', 'FURNACE'},
        {'w', 'Wood furnace', 'FURNACE_WOOD'},
        {'s', 'Smelter', 'FURNACE_SMELTER'},
        {'g', 'Glass furnace', 'FURNACE_GLASS'},
        {'k', 'Kiln', 'FURNACE_KILN'},
        {'l', 'Magma smelter', 'FURNACE_SMELTER_LAVA'},
        {'a', 'Magma glass furnace', 'FURNACE_GLASS_LAVA'},
        {'n', 'Magma kiln', 'FURNACE_KILN_LAVA'},
    },
    C = {
        title='Wall/floor/stairs/track', native={'CONSTRUCTION'},
        {'w', 'Wall', 'CONSTRUCTION_WALL'},
        {'W', 'Reinforced wall', click='Reinforced Wall', path={'CONSTRUCTION'}, new=true},
        {'f', 'Floor', 'CONSTRUCTION_FLOOR'},
        {'r', 'Ramp', 'CONSTRUCTION_RAMP'},
        -- the game has a single stair construction now
        {'u d x', 'Stairs', 'CONSTRUCTION_STAIR_UPDOWN'},
        {'F', 'Fortification', 'CONSTRUCTION_FORTIFICATION'},
        {'T', 'Track', 'CONSTRUCTION_TRACK'},
        {'S', 'Track stop', 'CONSTRUCTION_TRACK_STOP'},
    },
    T = {
        title='Traps/levers', native={'TRAP'},
        {'s', 'Stone-fall trap', 'TRAP_STONE'},
        {'w', 'Weapon trap', 'TRAP_WEAPON'},
        {'l', 'Lever', 'TRAP_LEVER'},
        {'p', 'Pressure plate', 'TRAP_TRIGGER'},
        {'c', 'Cage trap', 'TRAP_CAGE'},
        {'S', 'Upright spear/spike', 'TRAP_SPIKE'},
    },
    M = {
        title='Machine components', native={'MACHINE'},
        {'s', 'Screw pump', 'MACHINE_SCREW_PUMP'},
        {'w', 'Water wheel', 'MACHINE_WATER_WHEEL'},
        {'m', 'Windmill', 'MACHINE_WINDMILL'},
        {'g', 'Gear assembly', 'MACHINE_GEAR_ASSEMBLY'},
        {'h', 'Horizontal axle', 'MACHINE_AXLE_HORIZONTAL'},
        {'v', 'Vertical axle', 'MACHINE_AXLE_VERTICAL'},
        {'r', 'Rollers', 'MACHINE_ROLLERS'},
    },
}

-- 'a' -> CUSTOM_A, 'A' -> CUSTOM_SHIFT_A, 'Alt+a' -> CUSTOM_ALT_A
local function typed_key_code(spec)
    local alt = spec:match('^Alt%+(%a)$')
    if alt then return 'CUSTOM_ALT_' .. alt:upper() end
    if spec:match('^%u$') then return 'CUSTOM_SHIFT_' .. spec end
    return 'CUSTOM_' .. spec:upper()
end

-- Turn the tables above into ready-to-use entries, dropping (with a warning)
-- anything the running game no longer has rather than failing later.
for id, menu in pairs(CLASSIC_BUILD) do
    local kept = {}
    for _, raw in ipairs(menu) do
        local entry = {keys=raw[1], label=raw[2], leaf=raw[3], submenu=raw.submenu, codes={},
                       click=raw.click, path=raw.path, new=raw.new}
        local ok = true
        for spec in entry.keys:gmatch('%S+') do
            local code = typed_key_code(spec)
            ok = ok and df.interface_key[code] ~= nil
            entry.codes[#entry.codes + 1] = code
        end
        if entry.leaf then
            ok = ok and NATIVE_BUILD_PATH[entry.leaf] ~= nil
                and df.interface_key[BUILD_KEY_PREFIX .. entry.leaf] ~= nil
        end
        if ok then
            kept[#kept + 1] = entry
        else
            dfhack.printerr(('classic-controls: build menu entry "%s" is not available in this version; ignoring it')
                :format(entry.label))
        end
    end
    for i = #menu, 1, -1 do menu[i] = nil end
    for i, entry in ipairs(kept) do menu[i] = entry end
end

---------------------------------------------------------------------------
-- stockpile and zone tables
---------------------------------------------------------------------------

-- {keys, label, ...extra fields} -> entry with the interface key codes worked out
local function make_entries(raw_list)
    local entries = {}
    for _, raw in ipairs(raw_list) do
        local entry = {keys=raw[1], label=raw[2], codes={}}
        for k, v in pairs(raw) do
            if type(k) == 'string' then entry[k] = v end
        end
        for spec in entry.keys:gmatch('%S+') do
            entry.codes[#entry.codes + 1] = typed_key_code(spec)
        end
        entries[#entries + 1] = entry
    end
    return entries
end

local function pressed_entry(entries, keys)
    for _, entry in ipairs(entries) do
        for _, code in ipairs(entry.codes) do
            if keys[code] then return entry end
        end
    end
end

-- The old "p" menu. `preset` is the label of the game's own type button, which
-- is what gets clicked; two_line marks the labels the game wraps onto two rows.
local CLASSIC_STOCKPILES = make_entries{
    {'a', 'Animal', preset='Animals'},
    {'f', 'Food', preset='Food'},
    {'u', 'Furniture/Siege ammo', preset='Furniture'},
    {'y', 'Graveyard', preset='Corpses'},
    {'r', 'Refuse', preset='Refuse'},
    {'s', 'Stone', preset='Stone'},
    {'w', 'Wood', preset='Wood'},
    {'e', 'Gem', preset='Gem'},
    {'b', 'Bar/Block', preset='Bars and', two_line=true},
    {'h', 'Cloth', preset='Cloth'},
    {'l', 'Leather', preset='Leather'},
    {'z', 'Ammo', preset='Ammo'},
    {'n', 'Coins', preset='Coins'},
    {'g', 'Finished goods', preset='Finished', two_line=true},
    {'p', 'Weapons', preset='Weapons'},
    {'d', 'Armor', preset='Armor'},
    {'S', 'Sheet', preset='Sheets'},
    {'A', 'All', preset='All', new=true},
    {'c t', 'Custom settings', preset='Custom', custom=true},
}

-- The old "i" zone flags, which are separate zone types now, followed by the
-- zone types 0.47.05 did not have (rooms were made from furniture then).
-- `zone` is a df.civzone_type name.
local CLASSIC_ZONES = make_entries{
    {'w', 'Water source', zone='WaterSource'},
    {'f', 'Fishing', zone='FishingArea'},
    {'g', 'Gather/pick fruit', zone='PlantGathering'},
    {'d', 'Garbage dump', zone='Dump'},
    {'n', 'Pen/pasture', zone='Pen'},
    {'p', 'Pit/pond', zone='Pond'},
    {'s', 'Sand', zone='SandCollection'},
    {'c', 'Clay', zone='ClayCollection'},
    {'m', 'Meeting area', zone='MeetingHall'},
    {'t', 'Animal training', zone='AnimalTraining'},
    {'b', 'Bedroom', zone='Bedroom', new=true},
    {'D', 'Dining hall', zone='DiningHall', new=true},
    {'o', 'Office', zone='Office', new=true},
    {'y', 'Dormitory', zone='Dormitory', new=true},
    {'B', 'Barracks', zone='Barracks', new=true},
    {'a', 'Archery range', zone='ArcheryRange', new=true},
    {'j', 'Dungeon', zone='Dungeon', new=true},
    {'T', 'Tomb', zone='Tomb', new=true},
}
for i = #CLASSIC_ZONES, 1, -1 do
    if df.civzone_type[CLASSIC_ZONES[i].zone] == nil then
        dfhack.printerr(('classic-controls: zone type "%s" is not available in this version; ignoring it')
            :format(CLASSIC_ZONES[i].label))
        table.remove(CLASSIC_ZONES, i)
    end
end

---------------------------------------------------------------------------
-- unit panel tables (the old v keys)
---------------------------------------------------------------------------

-- One page of the unit panel: the main tab's index and label and, for tabs
-- that have sub-tabs, the view_sheets field holding the sub-tab, the value
-- wanted and that sub-tab's label. Labels are what gets clicked.
local function unit_page(tab, label, sub_field, sub, sub_label)
    return {tab=tab, label=label, sub_field=sub_field, sub=sub, sub_label=sub_label}
end

local HEALTH, SKILL, LABOR = 'unit_health_active_tab', 'unit_skill_active_tab', 'unit_labor_active_tab'
local MILITARY, THOUGHTS, PERSONALITY = 'unit_military_active_tab', 'thoughts_active_tab', 'personality_active_tab'

local UNIT_PAGE = {
    overview = unit_page(0, 'Overview'),
    items = unit_page(1, 'Items'),
    health_status = unit_page(2, 'Health', HEALTH, 0, 'Status'),
    health_wounds = unit_page(2, 'Health', HEALTH, 1, 'Wounds'),
    health_treatment = unit_page(2, 'Health', HEALTH, 2, 'Treatment'),
    health_history = unit_page(2, 'Health', HEALTH, 3, 'History'),
    health_description = unit_page(2, 'Health', HEALTH, 4, 'Description'),
    skills_labor = unit_page(3, 'Skills', SKILL, 0, 'Labor'),
    skills_combat = unit_page(3, 'Skills', SKILL, 1, 'Combat'),
    skills_social = unit_page(3, 'Skills', SKILL, 2, 'Social'),
    skills_other = unit_page(3, 'Skills', SKILL, 3, 'Other skills'),
    skills_knowledge = unit_page(3, 'Skills', SKILL, 4, 'Knowledge'),
    rooms = unit_page(4, 'Rooms'),
    labor_details = unit_page(5, 'Labor', LABOR, 0, 'Work details'),
    labor_workshops = unit_page(5, 'Labor', LABOR, 1, 'Workshops'),
    labor_locations = unit_page(5, 'Labor', LABOR, 2, 'Locations'),
    labor_animals = unit_page(5, 'Labor', LABOR, 3, 'Work animals'),
    relations = unit_page(6, 'Relations'),
    groups = unit_page(7, 'Groups'),
    military_squad = unit_page(8, 'Military', MILITARY, 0, 'Squad'),
    military_uniform = unit_page(8, 'Military', MILITARY, 1, 'Uniform'),
    military_kills = unit_page(8, 'Military', MILITARY, 2, 'Kills'),
    thoughts_recent = unit_page(9, 'Thoughts', THOUGHTS, 0, 'Recent thoughts'),
    thoughts_memories = unit_page(9, 'Thoughts', THOUGHTS, 1, 'Memories'),
    traits = unit_page(10, 'Personality', PERSONALITY, 0, 'Traits'),
    values = unit_page(10, 'Personality', PERSONALITY, 1, 'Values'),
    preferences = unit_page(10, 'Personality', PERSONALITY, 2, 'Preferences'),
    needs = unit_page(10, 'Personality', PERSONALITY, 3, 'Needs'),
}

-- The old v keys. A key goes to the first of its pages; pressed again while
-- on one of them, it steps to the next. The old game showed general info with
-- skills under g, and thoughts with personality under z, hence the groupings.
local UNIT_KEYS
do
    local p = UNIT_PAGE
    UNIT_KEYS = make_entries{
        {'g', 'general / skills', pages={p.overview, p.skills_labor, p.skills_combat, p.skills_social,
                                         p.skills_other, p.skills_knowledge}},
        {'b', 'labor skills', pages={p.skills_labor}},
        {'c', 'combat skills', pages={p.skills_combat}},
        {'m', 'other skills', pages={p.skills_other}},
        {'i', 'inventory', pages={p.items}},
        {'p', 'labor', pages={p.labor_details, p.labor_workshops, p.labor_locations, p.labor_animals}},
        {'l', 'work details', pages={p.labor_details}},
        {'a', 'work animals', pages={p.labor_animals}},
        {'o', 'occupation', pages={p.labor_locations}},
        {'w', 'wounds / health', pages={p.health_wounds, p.health_status, p.health_treatment,
                                        p.health_history, p.health_description}},
        {'h', 'health', pages={p.health_status}},
        {'d', 'description', pages={p.health_description}},
        {'z', 'thoughts / personality', pages={p.thoughts_recent, p.thoughts_memories, p.traits,
                                               p.values, p.preferences, p.needs}},
        {'r', 'relationships / groups', pages={p.relations, p.groups}},
        {'k', 'kills / military', pages={p.military_kills, p.military_squad, p.military_uniform}},
        {'R', 'rooms', pages={p.rooms}},
    }
end

-- which scroll position each unit tab uses (Military depends on its sub-tab)
local UNIT_SCROLL_FIELDS = {
    [1]='scroll_position_inventory',
    [2]='scroll_position_unit_health',
    [3]='scroll_position_unit_skill',
    [4]='scroll_position_unit_room',
    [5]='scroll_position_unit_labor',
    [6]='scroll_position_relations',
    [7]='scroll_position_groups',
    [9]='scroll_position_thoughts',
    [10]='scroll_position_personality',
}

---------------------------------------------------------------------------
-- workshop task hotkeys
---------------------------------------------------------------------------

-- The game no longer gives workshop tasks hotkeys, so these are the 0.47.05
-- ones (its HOTKEY_<WORKSHOP>_<TASK> bindings), attached to today's task
-- buttons by what the button does. Each rule is {key, ...conditions}; a
-- button gets the key of the first rule whose conditions all hold:
--   job       df.job_type name of the task
--   text      Lua pattern found in the task's label, lower-cased
--   reaction  the task's reaction code
--   material  the button's material number (meal size, for the kitchen)
-- Tasks the old game had no key for stay without one: use - = and Enter.
local FURNITURE_KEYS = {
    {'a', job='ConstructArmorStand'}, {'d', job='ConstructDoor'},
    {'l', job='ConstructFloodgate'}, {'H', job='ConstructHatchCover'},
    {'G', job='ConstructGrate'}, {'f', job='ConstructCabinet'},
    {'h', job='ConstructChest'}, {'t', job='ConstructTable'},
    {'w', job='ConstructWeaponRack'},
}

local function with_furniture(rules)
    for _, rule in ipairs(FURNITURE_KEYS) do rules[#rules + 1] = rule end
    return rules
end

local FORGE_KEYS = {
    {'w', text='^weapons'}, {'a', text='^armor'}, {'f', text='^furniture'},
    {'p', text='^siege'}, {'t', text='^trap'}, {'o', text='^other'},
    {'n', text='^metal clothing'},
}
local SMELTER_KEYS = {{'o', job='MeltMetalObject'}}
local GLASS_KEYS = with_furniture{
    {'s', job='CollectSand'}, {'c', job='CollectClay'},
    {'e', text='green glass'}, {'c', text='clear glass'}, {'k', text='crystal glass'},
    {'g', job='MakeRawGlass'}, {'o', job='ConstructCoffin'}, {'Alt+g', job='MakeGoblet'},
    {'z', job='MakeToy'}, {'u', job='ConstructStatue'}, {'j', job='MakeCage'},
    {'r', job='ConstructThrone'}, {'b', job='ConstructBlocks'}, {'q', job='MakeFlask'},
    {'i', job='MakeWindow'},
}
local MILL_KEYS = {{'p', job='MillPlants'}}

local TASK_KEYS = {
    ['Workshop/Carpenters'] = with_furniture{
        {'v', job='MakeBarrel'}, {'o', job='ConstructBlocks'}, {'e', job='MakeBucket'},
        {'p', job='MakeAnimalTrap'}, {'j', job='MakeCage'}, {'b', job='ConstructBed'},
        {'c', job='ConstructThrone'}, {'k', job='ConstructCoffin'}, {'n', job='ConstructBin'},
    },
    ['Workshop/Masons'] = with_furniture{
        {'b', job='ConstructBlocks'}, {'c', job='ConstructThrone'}, {'p', job='ConstructCoffin'},
        {'u', job='ConstructStatue'}, {'q', job='ConstructQuern'}, {'m', job='ConstructMillstone'},
        {'Alt+s', job='ConstructSlab'},
    },
    ['Workshop/Craftsdwarfs'] = {
        {'g', text='^rock %('}, {'w', text='^wood %('}, {'b', text='^bone %('}, {'s', text='^shell %('},
        {'B', text='^decorate with bone'}, {'S', text='^decorate with shell'},
        {'I', text='^decorate with ivory'}, {'N', text='^decorate with horn'},
        {'P', text='^decorate with pearl'}, {'t', job='MakeTotem'},
        {'h', text='^make cloth crafts'}, {'k', text='^make silk crafts'}, {'y', text='^make yarn crafts'},
        {'i', text='^make ivory/tooth crafts'}, {'n', text='^make horn crafts'},
        {'p', text='^make pearl crafts'}, {'l', text='^make leather crafts'},
        -- inside a material's menu
        {'c', job='MakeCrafts'}, {'Alt+g', job='MakeGoblet'}, {'z', job='MakeToy'},
    },
    ['Workshop/Still'] = {
        {'b', reaction='BREW_DRINK_FROM_PLANT'}, {'e', job='ExtractFromPlants'},
    },
    ['Workshop/Kitchen'] = {
        {'a', job='PrepareMeal', material=2}, {'b', job='PrepareMeal', material=3},
        {'c', job='PrepareMeal', material=4}, {'f', reaction='RENDER_FAT'},
    },
    ['Workshop/Farmers'] = {
        {'p', job='ProcessPlants'}, {'v', job='ProcessPlantsVial'}, {'l', job='ProcessPlantsBarrel'},
        {'c', job='MakeCheese'}, {'m', job='MilkCreature'}, {'s', job='ShearCreature'},
        {'S', job='SpinThread'},
    },
    ['Workshop/Quern'] = MILL_KEYS,
    ['Workshop/Millstone'] = MILL_KEYS,
    ['Workshop/Kennels'] = {{'a', job='CatchLiveLandAnimal'}, {'t', job='TameVermin'}},
    ['Workshop/Fishery'] = {
        {'p', job='PrepareRawFish'}, {'e', job='ExtractFromRawFish'}, {'f', job='CatchLiveFish'},
    },
    ['Workshop/Butchers'] = {
        {'b', job='ButcherAnimal'}, {'e', job='ExtractFromLandAnimal'}, {'a', job='CatchLiveLandAnimal'},
    },
    ['Workshop/Tanners'] = {{'t', job='TanAHide'}},
    ['Workshop/Dyers'] = {{'t', job='DyeThread'}, {'c', job='DyeCloth'}},
    ['Workshop/Jewelers'] = {
        {'c', job='CutGems'}, {'f', job='EncrustWithGems', text='furniture'},
        {'g', job='EncrustWithGems', text='finished goods'}, {'a', job='EncrustWithGems', text='ammo'},
    },
    ['Workshop/Mechanics'] = {{'t', job='ConstructMechanisms'}, {'R', job='ConstructTractionBench'}},
    ['Workshop/Ashery'] = {
        {'l', job='MakeLye'}, {'p', job='MakePotashFromLye'}, {'a', job='MakePotashFromAsh'},
    },
    ['Workshop/Siege'] = {{'b', job='ConstructBallistaParts'}, {'c', job='ConstructCatapultParts'}},
    ['Workshop/Loom'] = {
        {'c', job='CollectWebs'}, {'s', job='WeaveCloth', text='silk'}, {'y', job='WeaveCloth', text='yarn'},
        {'a', job='WeaveCloth', text='metal'}, {'w', job='WeaveCloth'},
    },
    ['Workshop/Leatherworks'] = {
        {'n', job='ConstructBag'}, {'q', job='MakeFlask'}, {'t', text='^make leather shirt'},
        {'k', text='^make leather cloak'}, {'r', job='MakeBackpack'}, {'v', job='MakeQuiver'},
        {'i', job='SewImage'},
    },
    ['Workshop/Clothiers'] = {
        {'s', text='^silk %('}, {'y', text='^yarn %('}, {'w', text='^cloth %('},
        {'t', text=' shirt$'}, {'k', text=' cloak$'}, {'b', job='ConstructBag'},
        {'n', job='MakeChain'}, {'i', job='SewImage'},
    },
    ['Workshop/MetalsmithsForge'] = FORGE_KEYS,
    ['Workshop/MagmaForge'] = FORGE_KEYS,
    ['Furnace/WoodFurnace'] = {{'a', job='MakeAsh'}, {'c', job='MakeCharcoal'}},
    ['Furnace/Smelter'] = SMELTER_KEYS,
    ['Furnace/MagmaSmelter'] = SMELTER_KEYS,
    ['Furnace/GlassFurnace'] = GLASS_KEYS,
    ['Furnace/MagmaGlassFurnace'] = GLASS_KEYS,
    ['Furnace/Kiln'] = GLASS_KEYS,
    ['Furnace/MagmaKiln'] = GLASS_KEYS,
}

-- Dev aid: with key_log_enabled set, every key press that reaches the overlay
-- is recorded as the list of interface keys the game reported for it. One
-- physical key usually arrives as several codes, and which ones depends on the
-- player's keybindings, so this is how to see what a real key press is.
--   :lua reqscript('classic-controls').key_log_enabled = true
--   :lua for _, l in ipairs(reqscript('classic-controls').key_log) do print(l) end
key_log_enabled = key_log_enabled or false
key_log = key_log or {}

function log_keys(keys)
    local names = {}
    for code, value in pairs(keys) do
        if code == '_STRING' then
            names[#names + 1] = ('_STRING=%d'):format(value)
        elseif type(code) == 'string' and not code:find('^STRING_A') then
            names[#names + 1] = code
        end
    end
    table.sort(names)
    key_log[#key_log + 1] = table.concat(names, ' ')
    if #key_log > 200 then table.remove(key_log, 1) end
end

-- for cc-dev/test-build
function get_classic_build_menus()
    return CLASSIC_BUILD
end

-- drop any key the running game does not know, so one renamed binding in a
-- future version cannot break the whole table
local function validate_keymap(name, keymap)
    for key, seq in pairs(keymap) do
        local ok = df.interface_key[key] ~= nil
        for _, k in ipairs(seq) do
            ok = ok and df.interface_key[k] ~= nil
        end
        if not ok then
            dfhack.printerr(('classic-controls: %s[%s] refers to an unknown key; ignoring it'):format(name, key))
            keymap[key] = nil
        end
    end
end
validate_keymap('TOP_KEYS', TOP_KEYS)
validate_keymap('DESIGNATE_KEYS', DESIGNATE_KEYS)
validate_keymap('ITEM_KEYS', ITEM_KEYS)
validate_keymap('TRAFFIC_KEYS', TRAFFIC_KEYS)

---------------------------------------------------------------------------
-- helpers: game state
---------------------------------------------------------------------------

local function df_screen()
    return dfhack.gui.getDFViewscreen(true)
end

-- Deliberately not dfhack.gui.matchFocusString: that answers from a per-frame
-- cache, so a second key press landing in the same frame as a mode change
-- would be judged against the old context.
local function current_focus()
    return dfhack.gui.getFocusStrings(df_screen())
end

local function focus_has(focus, prefix)
    for _, fs in ipairs(focus) do
        if fs:startswith(prefix) then return true end
    end
    return false
end

local function focus_is(prefix)
    return focus_has(current_focus(), prefix)
end

local function designating()
    return mi.main_designation_selected ~= df.main_designation_type.NONE
end

local function current_designation()
    return df.main_designation_type[mi.main_designation_selected]
end

local function viewed_building()
    if vs.open and vs.active_sheet == df.view_sheet_type.BUILDING then
        return df.building.find(vs.viewing_bldid)
    end
end

local function viewed_unit()
    if vs.open and vs.active_sheet == df.view_sheet_type.UNIT then
        return df.unit.find(vs.active_id)
    end
end

local function is_workshop(bld)
    return bld and (df.building_workshopst:is_instance(bld) or df.building_furnacest:is_instance(bld))
end

-- the game's own "add task" list is showing for the viewed building
local function add_task_list_open()
    return viewed_building() and #mi.building.button > 0
end

local function clear_sheet_lists()
    vs.viewing_unid:resize(0)
    vs.viewing_itid:resize(0)
end

local function set_sheet_pos(pos)
    vs.viewing_x, vs.viewing_y, vs.viewing_z = pos.x, pos.y, pos.z
end

-- If a building panel was closed while its "add task" list was showing, the
-- game leaves the old list behind and only clears it when it opens the next
-- panel itself. We open panels without going through that code, so drop the
-- stale list here or it would be shown (and pressed) for the wrong building.
-- The button objects are deliberately not freed: we do not own them.
local function drop_stale_task_list()
    mi.building.button:resize(0)
    mi.building.press_button:resize(0)
    mi.building.filtered_button:resize(0)
end

local function open_building_sheet(bld)
    clear_sheet_lists()
    drop_stale_task_list()
    vs.active_sheet = df.view_sheet_type.BUILDING
    vs.active_id = bld.id
    vs.viewing_bldid = bld.id
    set_sheet_pos(xyz2pos(bld.centerx, bld.centery, bld.z))
    vs.active_sub_tab = 0
    vs.scroll_position_building_job = 0
    vs.open = true
end

local function open_unit_sheet(unit)
    clear_sheet_lists()
    drop_stale_task_list()
    vs.viewing_unid:insert('#', unit.id)
    vs.active_sheet = df.view_sheet_type.UNIT
    vs.active_id = unit.id
    vs.viewing_bldid = -1
    set_sheet_pos(xyz2pos(dfhack.units.getPosition(unit)))
    vs.active_sub_tab = 0
    vs.open = true
end

local function open_item_sheet(item)
    clear_sheet_lists()
    drop_stale_task_list()
    vs.viewing_itid:insert('#', item.id)
    vs.active_sheet = df.view_sheet_type.ITEM
    vs.active_id = item.id
    vs.viewing_bldid = -1
    set_sheet_pos(xyz2pos(dfhack.items.getPosition(item)))
    vs.active_sub_tab = 0
    vs.open = true
end

local NO_SHEET_BUILDINGS = {
    [df.building_type.Stockpile] = true,
    [df.building_type.Civzone] = true,
}

local function nearest_building(pos, range)
    local best, best_d2 = nil, (range + 1) ^ 2
    for _, bld in ipairs(df.global.world.buildings.all) do
        if bld.z == pos.z and not NO_SHEET_BUILDINGS[bld:getType()] then
            local dx = math.max(bld.x1 - pos.x, 0, pos.x - bld.x2)
            local dy = math.max(bld.y1 - pos.y, 0, pos.y - bld.y2)
            local d2 = dx * dx + dy * dy
            if d2 < best_d2 then
                best, best_d2 = bld, d2
            end
        end
    end
    return best
end

local function unit_is_visible(unit)
    return dfhack.units.isActive(unit) and not dfhack.units.isHidden(unit)
end

local function nearest_unit(pos, range)
    local best, best_d2 = nil, (range + 1) ^ 2
    for _, unit in ipairs(df.global.world.units.active) do
        local ux, uy, uz = dfhack.units.getPosition(unit)
        if uz == pos.z and unit_is_visible(unit) then
            local d2 = (ux - pos.x) ^ 2 + (uy - pos.y) ^ 2
            if d2 < best_d2 then
                best, best_d2 = unit, d2
            end
        end
    end
    return best
end

local function units_at(pos)
    local found = {}
    for _, unit in ipairs(dfhack.units.getUnitsInBox(pos.x, pos.y, pos.z, pos.x, pos.y, pos.z)) do
        if unit_is_visible(unit) then
            found[#found + 1] = unit
        end
    end
    return found
end

local function items_at(pos)
    local found = {}
    local block = dfhack.maps.getTileBlock(pos)
    if not block then return found end
    for _, item_id in ipairs(block.items) do
        local item = df.item.find(item_id)
        if item and item.flags.on_ground and same_xyz(item.pos, pos) then
            found[#found + 1] = item
        end
    end
    return found
end

local function tile_is_hidden(pos)
    local flags = dfhack.maps.getTileFlags(pos)
    return not flags or flags.hidden
end

local function tile_caption(pos)
    local tt = dfhack.maps.getTileType(pos)
    if not tt then return 'outside the map' end
    local caption = df.tiletype.attrs[tt].caption
    if caption and #caption > 0 then return caption end
    return df.tiletype[tt] or 'unknown'
end

local function item_name(item)
    return dfhack.items.getReadableDescription(item)
end

local function job_name(job)
    return dfhack.job.getName(job)
end

---------------------------------------------------------------------------
-- helpers: driving the native UI
---------------------------------------------------------------------------

-- find a piece of text on the interface grid; returns x, y of its first
-- character. `bounds` ({x1, y1, x2, y2}, any of them optional) limits where
-- the text may start.
local function find_screen_text(text, bounds)
    local w, h = dfhack.screen.getWindowSize()
    bounds = bounds or {}
    local x_first = math.max(0, bounds.x1 or 0)
    local x_last = math.min(w - #text, bounds.x2 or w)
    local first = text:byte(1)
    for y = math.max(0, bounds.y1 or 0), math.min(h - 1, bounds.y2 or h) do
        local x = x_first
        while x <= x_last do
            local pen = dfhack.screen.readTile(x, y)
            if pen and pen.ch == first then
                local matched = true
                for i = 2, #text do
                    local p = dfhack.screen.readTile(x + i - 1, y)
                    if not p or p.ch ~= text:byte(i) then
                        matched = false
                        break
                    end
                end
                if matched then return x, y end
            end
            x = x + 1
        end
    end
end

-- left-click an interface grid cell, then put the mouse back where it was
local function click_screen(x, y)
    local saved = {gps.mouse_x, gps.mouse_y, gps.precise_mouse_x, gps.precise_mouse_y}
    gps.mouse_x, gps.mouse_y = x, y
    gps.precise_mouse_x = x * gps.tile_pixel_x + gps.tile_pixel_x // 2
    gps.precise_mouse_y = y * gps.tile_pixel_y + gps.tile_pixel_y // 2
    gui.simulateInput(df_screen(), '_MOUSE_L')
    gps.mouse_x, gps.mouse_y, gps.precise_mouse_x, gps.precise_mouse_y = table.unpack(saved)
end

local function click_label(text, bounds)
    local x, y = find_screen_text(text, bounds)
    if not x then return false end
    click_screen(x + #text // 2, y)
    return true
end

-- Mark a row of one of the game's own lists as selected: an arrow at x, and
-- the text for `width` cells after it recoloured in place.
local function mark_row(x, y, width)
    local pen = {fg=COLOR_YELLOW, bg=COLOR_BLACK}
    dfhack.screen.paintString(pen, x, y, string.char(16))
    for tx = x + 1, x + width do
        local tile = dfhack.screen.readTile(tx, y)
        if tile and tile.ch and tile.ch > 32 then
            dfhack.screen.paintString(pen, tx, y, string.char(tile.ch))
        end
    end
end

local function button_text(button)
    local str = df.new('string')
    button:text(str)
    local text = str.value
    str:delete()
    return text
end

---------------------------------------------------------------------------
-- add-task list: the game's own "add task" buttons, with the old hotkeys
---------------------------------------------------------------------------

-- - is up a list and = (or +) is down it. By the character typed as well as
-- by binding, since = is not bound to anything in every keymap.
local function list_step(keys)
    local ch = keys._STRING
    if keys.SECONDSCROLL_DOWN or ch == string.byte('=') or ch == string.byte('+') then return 1 end
    if keys.SECONDSCROLL_UP or ch == string.byte('-') then return -1 end
end

local function workshop_kind(bld)
    if df.building_workshopst:is_instance(bld) then
        return 'Workshop/' .. tostring(df.workshop_type[bld.type])
    elseif df.building_furnacest:is_instance(bld) then
        return 'Furnace/' .. tostring(df.furnace_type[bld.type])
    end
end

-- buttons come in several classes with different fields, hence the pcall
local function button_field(button, field)
    local ok, value = pcall(function() return button[field] end)
    if ok then return value end
end

local function task_rule_matches(rule, button, text)
    if rule.job and df.job_type[button_field(button, 'jobtype') or -1] ~= rule.job then return false end
    if rule.text and not text:find(rule.text) then return false end
    if rule.reaction and button_field(button, 'mstring') ~= rule.reaction then return false end
    if rule.material and button_field(button, 'material') ~= rule.material then return false end
    return true
end

-- the old hotkey, if it had one, for each of the task buttons on show
local function task_hotkeys(bld, buttons)
    local rules = bld and TASK_KEYS[workshop_kind(bld) or ''] or {}
    local by_idx, taken = {}, {}
    for idx, button in ipairs(buttons) do
        local text = button_text(button):lower()
        for _, rule in ipairs(rules) do
            local key = rule[1]
            if not taken[key] and task_rule_matches(rule, button, text) then
                by_idx[idx] = key
                taken[key] = true
                break
            end
        end
    end
    return by_idx
end

-- filtered_button is the list in the order the game displays it, and the one
-- the game itself draws. A button that opens a submenu (press()) replaces
-- `button` but, pressed from here rather than by a click, leaves
-- filtered_button holding the buttons of the list before, which the game has
-- already freed: asking one of those for its text crashes the game, and so
-- does the game's own next redraw of the list. So a stale filtered list is
-- rebuilt from `button` on the spot, as a click would have left it.
local function task_buttons()
    local all = mi.building.button
    local filtered = mi.building.filtered_button
    if #filtered == 0 then return all end
    local live = {}
    for i = 0, #all - 1 do
        local _, addr = all[i]:sizeof()
        live[addr] = true
    end
    local stale = #filtered > #all
    for i = 0, #filtered - 1 do
        local _, addr = filtered[i]:sizeof()
        if not live[addr] then stale = true end
    end
    if not stale then return filtered end
    filtered:resize(0)
    for i = 0, #all - 1 do
        filtered:insert('#', all[i])
    end
    return all
end

local TASK_KEY_W = 6

TaskPicker = defclass(TaskPicker, gui.ZScreen)
TaskPicker.ATTRS{
    focus_path='classic-controls/add-task',
    pass_movement_keys=false,
    on_close=DEFAULT_NIL,
}

-- the labels chosen, level by level, for the last task added at each kind of
-- workshop: the list opens on them again, so that a again and Enter adds
-- another of the same
TaskPicker.memory = TaskPicker.memory or {}

function TaskPicker:init()
    self.depth, self.path = 1, {}
    self:addviews{
        widgets.Window{
            frame={l=3, t=5, w=62, h=40},
            frame_title='Add task',
            resizable=true,
            subviews={
                widgets.List{
                    view_id='list',
                    frame={t=0, l=0, r=0, b=2},
                    on_submit=self:callback('on_submit'),
                },
                widgets.Label{
                    frame={b=0, l=0},
                    text={
                        {text='key', pen=COLOR_LIGHTGREEN}, ': add  ',
                        {text='- =', pen=COLOR_LIGHTGREEN}, ': select  ',
                        {text='Enter', pen=COLOR_LIGHTGREEN}, ': add  ',
                        {text='Esc', pen=COLOR_LIGHTGREEN}, ': back',
                    },
                },
            },
        },
    }
    self:refresh()
end

function TaskPicker:refresh()
    local buttons = task_buttons()
    local hotkeys = task_hotkeys(viewed_building(), buttons)
    local list = self.subviews.list
    local choices = {}
    for idx, button in ipairs(buttons) do
        local text = button_text(button)
        local key = hotkeys[idx] or ''
        local objection = button_field(button, 'objection')
        local blocked = objection and #objection > 0
        -- Every token carries its own colour, which switches off the list's
        -- own highlighting, so the selected row is marked here: an arrow in
        -- front and the label in yellow.
        local row = #choices + 1
        local function selected() return list:getSelected() == row end
        local tokens = {
            {text=function() return selected() and string.char(16) or ' ' end, pen=COLOR_YELLOW},
            {text=key .. string.rep(' ', TASK_KEY_W - #key), pen=COLOR_LIGHTGREEN},
            {text=text, pen=function()
                return selected() and COLOR_YELLOW or (blocked and COLOR_GREY or COLOR_WHITE)
            end},
        }
        if blocked then
            tokens[#tokens + 1] = {text=' ' .. objection, pen=COLOR_RED}
        end
        choices[#choices + 1] = {
            text=tokens, button_idx=idx, code=hotkeys[idx] and typed_key_code(hotkeys[idx]) or nil,
            label=text,
        }
    end
    -- where to start: the entry this level was left by, else the one the
    -- last task added here went through
    local remembered = self.path[self.depth]
        or (TaskPicker.memory[workshop_kind(viewed_building()) or ''] or {})[self.depth]
    local start = 1
    for i, choice in ipairs(choices) do
        if remembered and choice.label == remembered then start = i end
    end
    -- The row is chosen once the list knows how many rows it shows: before
    -- its first layout it scrolls the selected row out of sight instead.
    self.subviews.list:setChoices(choices, 1)
    self.start_on = start > 1 and start or nil
    self:select_start()
end

function TaskPicker:select_start()
    local list = self.subviews.list
    if self.start_on and (list.page_size or 0) > 1 then
        list:setSelected(self.start_on)
        self.start_on = nil
    end
end

function TaskPicker:onRenderFrame(dc, rect)
    TaskPicker.super.onRenderFrame(self, dc, rect)
    self:select_start()
end

function TaskPicker:on_submit(_, choice)
    if not choice then return end
    local button = task_buttons()[choice.button_idx]
    if not button then
        self:dismiss()
        return
    end
    -- press() runs the game's own handler: it queues the job, or swaps the
    -- button list for a submenu (material / category selectors)
    local kind = workshop_kind(viewed_building()) or ''
    self.path[self.depth] = choice.label
    button:press()
    task_buttons()   -- (puts the game's own list right before it is drawn again)
    if #mi.building.button > 0 then
        self.depth = self.depth + 1
        self:refresh()
    else
        TaskPicker.memory[kind] = self.path
        self:dismiss()
    end
end

function TaskPicker:onInput(keys)
    if keys.LEAVESCREEN or keys._MOUSE_R then
        -- out of a submenu to the list it was opened from (the game's
        -- "Back"), and out of that list altogether
        if self.depth > 1 and click_label('Back', {x1=gps.dimx // 3}) then
            self.depth = self.depth - 1
            self:refresh()
        else
            self:dismiss()
        end
        return true
    end
    local list = self.subviews.list
    -- a task's hotkey queues it straight away, as it used to
    for _, choice in ipairs(list.choices) do
        if choice.code and keys[choice.code] then
            self:on_submit(nil, choice)
            return true
        end
    end
    local step = list_step(keys)
    if step then
        local count = #list.choices
        if count > 0 then
            list:setSelected(((list:getSelected() or 1) - 1 + step) % count + 1)
        end
        return true
    end
    return TaskPicker.super.onInput(self, keys)
end

function TaskPicker:onDismiss()
    -- still showing means the player backed out; close the native list too
    -- (inside a submenu its button is "Back", then "Cancel")
    for _ = 1, 4 do
        if not add_task_list_open() then break end
        if not (click_label('Cancel') or click_label('Back', {x1=gps.dimx // 3})) then break end
    end
    if self.on_close then self.on_close() end
end

---------------------------------------------------------------------------
-- the overlay
---------------------------------------------------------------------------

local MODE_TITLES = {
    look='Look',
    query='Query building',
    items='Building items',
    unit='View unit',
}

ClassicKeysOverlay = defclass(ClassicKeysOverlay, overlay.OverlayWidget)
ClassicKeysOverlay.ATTRS{
    desc='Classic (pre-Steam) keyboard controls: q/k/v/t cursor modes and old menu keys.',
    default_pos={x=1, y=1},
    default_enabled=true,
    fullscreen=true,
    viewscreens='dwarfmode',
    -- wide enough for the panel to sit under the minimap on the widest
    -- screens; the framework trims it to the screen
    frame={w=400, h=100},
}

function ClassicKeysOverlay:init()
    self.mode = nil        -- nil | 'look' | 'query' | 'unit'
    self.cursor = nil      -- map position of our cursor
    self.target_id = nil   -- id of the building / unit the current mode has open
    self.job_idx = 0       -- selected job in the viewed workshop
    self.build_menu = nil  -- which classic build list is showing: nil | 'top' | 'w' | ...
    self.mat_idx = 0       -- selected row on the pick-materials list
    self.last_bottom = BOTTOM.NONE
    self.last_req = -1
    self.simulating = false
    self.panel_key = nil

    -- for the cc-dev tools: reqscript('classic-controls').overlay_instance
    overlay_instance = self

    self:addviews{
        widgets.Panel{
            view_id='panel',
            -- clear of the top bar and the alert icons down the left edge
            frame={t=4, l=6, w=46, h=4},
            frame_style=gui.FRAME_MEDIUM,
            frame_background=gui.CLEAR_PEN,
            visible=false,
            subviews={
                widgets.Label{view_id='body', frame={t=0, l=0}, text=''},
            },
        },
    }
end

-- feed the game its own keys without our onInput seeing them again
function ClassicKeysOverlay:feed(...)
    self.simulating = true
    local ok, err = pcall(gui.simulateInput, df_screen(), ...)
    self.simulating = false
    if not ok then dfhack.printerr('classic-controls: ' .. tostring(err)) end
end

function ClassicKeysOverlay:run_sequence(seq)
    -- a top-level key (D_...) only works from the bare map, so leave the
    -- current designation tool first
    if seq[1]:startswith('D_') and designating() then
        self:feed('LEAVESCREEN')
    end
    for _, key in ipairs(seq) do
        self:feed(key)
    end
end

---------------------------------------------------------------------------
-- info panel
---------------------------------------------------------------------------

local function hint(key, desc)
    return {{text=key, pen=COLOR_LIGHTGREEN}, ': ' .. desc}
end

local PANEL_TEXT_W = 44

-- where our panel goes: normally the top-left corner, but the stockpile and
-- zone screens put the game's own panel there, so ours sits beside it
local PANEL_LEFT = 6
local PANEL_TOP = 4
-- beside the info window: the strip under the minimap, below the alerts
local INFO_PANEL_W, INFO_PANEL_TOP = 24, 24
local PANEL_LEFT_BESIDE_NATIVE = 48

function ClassicKeysOverlay:show_panel(title, lines, text_width, left, top)
    local text = {{text=title, pen=COLOR_YELLOW}, NEWLINE}
    for _, line in ipairs(lines) do
        if type(line) == 'table' then
            for _, token in ipairs(line) do
                if type(token) == 'table' and not token.text then
                    -- a nested hint() result
                    for _, t in ipairs(token) do text[#text + 1] = t end
                else
                    text[#text + 1] = token
                end
            end
        else
            text[#text + 1] = line
        end
        text[#text + 1] = NEWLINE
    end
    local panel = self.subviews.panel
    self.subviews.body:setText(text)
    panel.frame.h = #lines + 3
    panel.frame.w = (text_width or PANEL_TEXT_W) + 2
    panel.frame.l = left or PANEL_LEFT
    panel.frame.t = top or PANEL_TOP
    panel.visible = true
    self:updateLayout()
end

function ClassicKeysOverlay:hide_panel()
    self.subviews.panel.visible = false
end

local function clip(str, width)
    if #str <= width then return str end
    return str:sub(1, width - 1) .. '~'
end

local BUILD_COL_W = 30
local BUILD_KEY_W = 6

-- lay a classic key list out in columns, in the old menu's order. Submenus
-- and the current choice are yellow; entries the old game did not have, cyan.
local function build_menu_lines(menu, rows_per_col, selected)
    local cols = math.ceil(#menu / rows_per_col)
    local rows = math.ceil(#menu / cols)
    local lines = {}
    for r = 1, rows do
        local line = {}
        for c = 0, cols - 1 do
            local entry = menu[c * rows + r]
            if entry then
                local label = entry.label .. (entry.submenu and ' >' or '')
                line[#line + 1] = {
                    text=entry.keys .. string.rep(' ', math.max(1, BUILD_KEY_W - #entry.keys)),
                    pen=COLOR_LIGHTGREEN,
                }
                line[#line + 1] = {
                    text=label .. string.rep(' ', math.max(1, BUILD_COL_W - BUILD_KEY_W - #label)),
                    pen=((entry.submenu or entry == selected) and COLOR_YELLOW)
                        or (entry.new and COLOR_LIGHTCYAN) or COLOR_WHITE,
                }
            end
        end
        lines[#lines + 1] = line
    end
    return lines, cols * BUILD_COL_W
end

-- everything on a tile that has a panel of its own, creatures first
local function look_things(pos)
    local things = {}
    if tile_is_hidden(pos) then return things end
    for _, unit in ipairs(units_at(pos)) do
        things[#things + 1] = {kind='unit', obj=unit, pen=COLOR_LIGHTCYAN,
                               label=dfhack.units.getReadableName(unit)}
    end
    local bld = dfhack.buildings.findAtTile(pos)
    if bld then
        things[#things + 1] = {kind='building', obj=bld, pen=COLOR_LIGHTMAGENTA,
                               label=utils.getBuildingName(bld)}
    end
    for _, item in ipairs(items_at(pos)) do
        things[#things + 1] = {kind='item', obj=item, pen=COLOR_WHITE, label=item_name(item)}
    end
    return things
end

local LOOK_LIST_ROWS = 10

-- What a tile is, with what it is made of: "limonite wall" where the game's
-- own caption says "vein wall", "kaolinite cavern floor" for "stone floor".
do
local MATERIAL = df.tiletype_material

local function solid_name(mat_type, mat_index)
    local info = dfhack.matinfo.decode(mat_type, mat_index)
    return info and info.material.state_name.Solid
end

-- a vein or cluster: the last mineral event of the block that covers the tile
local function vein_stone(block, pos)
    local found
    for _, event in ipairs(block.block_events) do
        if df.block_square_event_mineralst:is_instance(event)
            and dfhack.maps.getTileAssignment(event.tile_bitmask, pos.x % 16, pos.y % 16)
        then
            found = event.inorganic_mat
        end
    end
    return found
end

-- layer stone or soil: the tile's layer in the geology of its biome
local function layer_stone(pos, des)
    local rx, ry = dfhack.maps.getTileBiomeRgn(pos)
    local biome = rx and dfhack.maps.getRegionBiome(rx, ry)
    local geology = biome and df.world_geo_biome.find(biome.geo_index)
    local layer = geology and geology.layers[des.geolayer_index]
    return layer and layer.mat_index
end

local function tile_material_name(pos, material)
    local block = dfhack.maps.getTileBlock(pos)
    local des = dfhack.maps.getTileFlags(pos)
    if not block or not des then return end
    if material == MATERIAL.MINERAL then
        local stone = vein_stone(block, pos)
        return stone and solid_name(0, stone)
    elseif material == MATERIAL.STONE or material == MATERIAL.SOIL then
        local stone = layer_stone(pos, des)
        return stone and solid_name(0, stone)
    elseif material == MATERIAL.CONSTRUCTION then
        local built = dfhack.constructions.findAtTile(pos)
        return built and solid_name(built.mat_type, built.mat_index)
    elseif material == MATERIAL.TREE or material == MATERIAL.PLANT or material == MATERIAL.MUSHROOM then
        local plant = dfhack.maps.getPlantAtTile(pos)
        local raw = plant and df.plant_raw.find(plant.material)
        return raw and raw.name
    end
end

-- the generic word in the game's caption that the material's name replaces
local GENERIC = {
    [MATERIAL.MINERAL]='vein', [MATERIAL.STONE]='stone', [MATERIAL.SOIL]='soil',
}

function ClassicKeysOverlay.tile_name(pos)
    local tt = dfhack.maps.getTileType(pos)
    if not tt then return 'outside the map' end
    local attrs = df.tiletype.attrs[tt]
    local caption = attrs.caption
    if not caption or #caption == 0 then return df.tiletype[tt] or 'unknown' end
    local ok, name = pcall(tile_material_name, pos, attrs.material)
    if not ok or not name or #name == 0 then return caption end
    name = name:lower()
    local des = dfhack.maps.getTileFlags(pos)
    local generic = GENERIC[attrs.material]
    if generic then
        if caption:find(generic, 1, true) then
            caption = caption:gsub(generic, (name:gsub('%%', '%%%%')), 1)
        else
            caption = name .. ' ' .. caption          -- "boulder"
        end
        -- a natural floor underground is a cavern floor, as the game's own
        -- hover text has it
        if attrs.shape == df.tiletype_shape.FLOOR and attrs.special == df.tiletype_special.NORMAL
            and des and des.subterranean
        then
            caption = caption:gsub(' floor$', ' cavern floor')
        end
        return caption
    elseif attrs.material == MATERIAL.CONSTRUCTION then
        return (caption:gsub('constructed', 'constructed ' .. name:gsub('%%', '%%%%'), 1))
    end
    -- a tree or a plant: its kind, then what part of it this is
    if caption:find(name, 1, true) then return caption end
    return name .. ': ' .. caption
end

end -- of the tile name block

function ClassicKeysOverlay:look_lines()
    local pos = self.cursor
    local lines = {}
    if tile_is_hidden(pos) then
        lines[#lines + 1] = 'unexplored'
    else
        local things = look_things(pos)
        self.look_idx = math.max(1, math.min(self.look_idx or 1, #things))
        -- a window of the list that keeps the selection in view
        local first = math.max(1, math.min(self.look_idx - LOOK_LIST_ROWS // 2, #things - LOOK_LIST_ROWS + 1))
        for i = first, math.min(#things, first + LOOK_LIST_ROWS - 1) do
            local thing = things[i]
            local selected = i == self.look_idx
            lines[#lines + 1] = {
                {text=selected and string.char(16) or ' ', pen=COLOR_YELLOW},
                {text=clip(thing.label, PANEL_TEXT_W - 1), pen=selected and COLOR_YELLOW or thing.pen},
            }
        end
        if #things > LOOK_LIST_ROWS then
            lines[#lines + 1] = {{text=('%d of %d'):format(self.look_idx, #things), pen=COLOR_GREY}}
        end
        lines[#lines + 1] = {{text=clip(ClassicKeysOverlay.tile_name(pos), PANEL_TEXT_W), pen=COLOR_GREY}}
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = {hint('- =', 'select  '), hint('Enter', 'open  '), hint('Esc', 'done')}
    return lines
end

-- The task list itself is the game's own panel; the selected task is marked
-- there (see render_job_marker), so this only needs the name and the keys.
function ClassicKeysOverlay:workshop_lines(bld)
    local lines = {{{text=clip(utils.getBuildingName(bld), PANEL_TEXT_W), pen=COLOR_LIGHTMAGENTA}}}
    local n = #bld.jobs
    if n == 0 then
        lines[#lines + 1] = {{text='no tasks', pen=COLOR_GREY}}
    else
        local job = bld.jobs[math.min(self.job_idx, n - 1)]
        lines[#lines + 1] = clip(('task %d/%d: %s'):format(self.job_idx + 1, n, job_name(job)), PANEL_TEXT_W)
    end
    lines[#lines + 1] = {hint('a', 'add task  '), hint('- =', 'select task')}
    lines[#lines + 1] = {hint('r', 'repeat  '), hint('s', 'suspend  '), hint('n', 'do now')}
    lines[#lines + 1] = {hint('c', 'cancel task  '), hint('t', 'items  '), hint('Esc', 'done')}
    lines[#lines + 1] = {hint('d', 'task details  '), ClassicKeysOverlay.removal_hint(bld)}
    local suspend = ClassicKeysOverlay.suspend_hint(bld)
    if suspend then lines[#lines + 1] = {suspend} end
    return lines
end

-- A designation list as panel lines, 12 columns to an entry as the old menu
-- had it, with the tool in use picked out in yellow.
function ClassicKeysOverlay.legend_lines(legend, current)
    local lines = {}
    for _, row in ipairs(legend) do
        local line = {}
        for i, entry in ipairs(row) do
            local chosen = false
            for j = 3, #entry do
                if entry[j] == current then chosen = true end
            end
            local label = entry[2]
            if i < #row then
                local width = math.ceil((#label + 1) / 12) * 12 - 2
                label = label .. string.rep(' ', width - #label)
            end
            line[#line + 1] = {text=entry[1] .. ' ', pen=chosen and COLOR_YELLOW or COLOR_LIGHTGREEN}
            line[#line + 1] = {text=label, pen=chosen and COLOR_YELLOW or COLOR_WHITE}
        end
        lines[#lines + 1] = line
    end
    return lines
end

-- x on a building, as it was: mark it for removal, call the removal off
-- again, or cancel a building that has not been started.
function ClassicKeysOverlay.removal_job(bld)
    for _, job in ipairs(bld.jobs) do
        if job.job_type == df.job_type.DestroyBuilding then return job end
    end
end

function ClassicKeysOverlay.removal_hint(bld)
    if ClassicKeysOverlay.removal_job(bld) then
        return hint('x', 'stop the removal')
    elseif bld:getBuildStage() < bld:getMaxBuildStage() then
        return hint('x', bld:getBuildStage() == 0 and 'cancel construction' or 'remove (unfinished)')
    end
    return hint('x', 'remove building')
end

-- the job that builds a building not finished yet
function ClassicKeysOverlay.construction_job(bld)
    if bld:getBuildStage() >= bld:getMaxBuildStage() then return end
    for _, job in ipairs(bld.jobs) do
        if job.job_type == df.job_type.ConstructBuilding then return job end
    end
end

-- s on a building being built: suspend its construction, or let it go on
-- (the game's own "Suspend construction" button does the same)
function ClassicKeysOverlay.toggle_construction_suspend(bld)
    local job = ClassicKeysOverlay.construction_job(bld)
    if not job then return false end
    job.flags.suspend = not job.flags.suspend
    return true
end

function ClassicKeysOverlay.suspend_hint(bld)
    local job = ClassicKeysOverlay.construction_job(bld)
    if job then
        return hint('s', job.flags.suspend and 'resume construction (suspended)' or 'suspend construction')
    end
end

function ClassicKeysOverlay:toggle_building_removal(bld)
    local job = ClassicKeysOverlay.removal_job(bld)
    if job then
        dfhack.job.removeJob(job)
        return
    end
    if bld:getBuildStage() == 0 then
        -- Not started: it goes at once. The game's panel must not be left
        -- showing a building that no longer exists.
        self:close_sheet()
        dfhack.buildings.deconstruct(bld)
        self.target_id = nil
        if self.mode then self:retarget() end
    else
        dfhack.buildings.deconstruct(bld)
    end
end

-- The game's panel at the top left while a building is placed or its
-- material chosen (the material choice, "Keep building after placement",
-- warnings) is as tall as it needs: the key list goes beside it, one column
-- clear of its right-hand border, found on the border row above its first
-- line of text.
function ClassicKeysOverlay.beside_native_panel()
    local first_x, first_y
    -- (TOP_ROWS is defined further down the file: 4, the top bar)
    for y = 4, 8 do
        for x = 2, 20 do
            local tile = dfhack.screen.readTile(x, y)
            if tile and tile.ch and tile.ch > 32 then
                first_x, first_y = x, y
                break
            end
        end
        if first_x then break end
    end
    if first_x then
        local border = first_y - 1
        local right
        for x = first_x, math.min(gps.dimx - 1, first_x + 120) do
            local tile = dfhack.screen.readTile(x, border)
            if not tile or not tile.tile or tile.tile == 0 then break end
            right = x
        end
        if right and right > first_x + 10 then return right + 2 end
    end
    return 61
end

function ClassicKeysOverlay:refresh_panel()
    local bottom = mi.bottom_mode_selected
    -- the unit list fills the left of the screen, top included; keep off it
    if focus_is('dwarfmode/UnitSelector') then
        self:hide_panel()
        return
    elseif ClassicKeysOverlay.detail_window() then
        local title, lines = self:detail_window_lines()
        self:show_panel(title, lines, INFO_PANEL_W, gps.dimx - INFO_PANEL_W - 3, INFO_PANEL_TOP)
        return
    elseif focus_is('dwarfmode/Announcements') then
        self:show_panel('Announcements', self:announcement_lines(), INFO_PANEL_W,
            gps.dimx - INFO_PANEL_W - 3, INFO_PANEL_TOP)
        return
    elseif mi.location_selector.open or focus_is('dwarfmode/SquadSelector') then
        local title, lines = self:zone_chooser_lines()
        self:show_panel(title, lines, 40, gps.dimx // 2 + 20)
        return
    end
    if mi.squads.open and (mi.create_squad.open
        or (mi.assign_uniform.open and not mi.squad_equipment.open))
    then
        self:show_panel(mi.create_squad.open and 'New squad: which kind' or 'New squad: which uniform', {
            {hint('- =', 'select  '), hint('Enter', 'choose  '), hint('Esc', 'cancel')},
        })
        return
    elseif mi.squads.open and mi.patrol_routes.open then
        if mi.patrol_routes.entering_new_route_name then
            self:show_panel('Route name', {
                {{text='Type the name', pen=COLOR_GREY}},
                {hint('Enter', 'done')},
            })
        elseif mi.patrol_routes.adding_new_route then
            self:show_panel('Patrol route', {
                {hint('Enter', 'add a point at the cursor')},
                {hint('- =', 'select point  '), hint('x', 'remove it')},
                {hint('n', 'name  '), hint('Shift+Enter', 'save')},
                {hint('Esc', 'cancel')},
            })
        else
            self:show_panel('Patrol routes', {
                {hint('- =', 'select  '), hint('Enter', 'patrol it')},
                {hint('a', 'add  '), hint('e', 'edit  '), hint('d', 'delete')},
                {hint('Esc', 'cancel')},
            })
        end
        return
    elseif mi.squads.open and mi.burrow_selector.open then
        self:show_panel('Defend burrows', {
            {hint('- =', 'select  '), hint('x', 'tick')},
            {hint('Enter', 'defend  '), hint('Esc', 'cancel')},
        })
        return
    elseif mi.squads.open and mi.squad_equipment.open then
        -- the uniform picker opens in the top-left corner, where our panel sits
        self:show_panel('Squad equipment', self:equipment_lines(), nil,
            mi.assign_uniform.open and PANEL_LEFT_BESIDE_NATIVE or nil)
        return
    elseif mi.squads.open and mi.squad_schedule.open then
        if mi.squads.editing_squad_schedule_id ~= -1 then
            self:show_panel('Schedule orders', self:order_editor_lines())
        elseif mi.squad_schedule.viewing_months_squad_id ~= -1 then
            self:show_panel('Monthly schedule', self:month_lines())
        elseif mi.squad_schedule.editing_routines then
            if mi.squad_schedule.entering_routine_name then
                self:show_panel('Routine name', {
                    {{text='Type the name', pen=COLOR_GREY}},
                    {hint('Enter', 'done  '), hint('Esc', 'leave it')},
                })
            elseif mi.squad_schedule.deleting_routine_id ~= -1 then
                self:show_panel('Delete the routine?', {
                    {hint('Enter', 'delete  '), hint('Esc', 'keep it')},
                })
            else
                self:show_panel('Routines', {
                    {hint('- =', 'select  '), hint('c', 'add  '), hint('d', 'delete')},
                    {hint('N', 'name  '), hint('Esc', 'back to the schedule')},
                })
            end
        else
            self:show_panel('Squad schedules', self:schedule_lines())
        end
        return
    elseif mi.squads.open and mi.squads.disband_confirmation then
        self:show_panel('Disband the squad?', {
            {hint('Enter', 'disband  '), hint('Esc', 'keep it')},
        })
        return
    elseif mi.squads.open and mi.squads.entering_squad_nickname then
        self:show_panel('Squad name', {
            {{text='Type the name', pen=COLOR_GREY}},
            {hint('Enter', 'done')},
        })
        return
    elseif mi.squads.open and mi.squads.viewing_squad_index ~= -1 and not self.order then
        self:show_panel('Squad positions', {
            {hint('- =', 'select  '), hint('Enter', 'assign / replace')},
            {hint('x', 'tick soldier  '), hint('a-j', 'tick by position')},
            {{text='Orders for the ticked soldiers:', pen=COLOR_GREY}},
            {hint('m', 'move  '), hint('k', 'kill  '), hint('o', 'cancel orders')},
            {hint('r', 'patrol  '), hint('w', 'defend burrow  '), hint('t', 'train')},
            {hint('N', 'name squad  '), hint('Esc', 'back to squads')},
        })
        return
    elseif mi.squads.open then
        self:show_panel('Squads', self:squad_lines())
        return
    elseif mi.trade.open or mi.assign_trade.open then
        local title, lines = self:trade_lines()
        self:show_panel(title, lines, INFO_PANEL_W, gps.dimx - INFO_PANEL_W - 3, INFO_PANEL_TOP)
        return
    elseif mi.info.open or mi.create_work_order.open then
        -- the info window fills the screen bar the strip under the minimap
        local title, lines = self:info_lines()
        if title then
            self:show_panel(title, lines, INFO_PANEL_W, gps.dimx - INFO_PANEL_W - 3, INFO_PANEL_TOP)
        else
            self:hide_panel()
        end
        return
    elseif bottom == BOTTOM.HAULING then
        local title, lines, aside = self:hauling_lines()
        if aside then
            -- a window fills the middle of the screen: under the minimap
            self:show_panel(title, lines, INFO_PANEL_W, gps.dimx - INFO_PANEL_W - 3, INFO_PANEL_TOP)
        else
            self:show_panel(title, lines, nil, ClassicKeysOverlay.hauling_panel_x())
        end
        return
    elseif bottom == BOTTOM.BUILDING then
        local id = self.build_menu or 'top'
        local menu = CLASSIC_BUILD[id]
        -- leave room for the game's own build menu along the bottom
        local rows_per_col = math.max(8, math.min(22, gps.dimy - 36))
        local lines, width = build_menu_lines(menu, rows_per_col)
        lines[#lines + 1] = {hint('Esc', id == 'top' and 'done' or 'back')}
        self:show_panel(menu.title, lines, width)
        return
    elseif bottom == BOTTOM.BUILDING_PLACEMENT then
        self:show_panel('Place building', {
            {hint('arrows', 'move  '), hint('Enter', 'place')},
            {hint('Esc', 'back to the build list')},
        }, nil, ClassicKeysOverlay.beside_native_panel())
        return
    elseif bottom == BOTTOM.BUILDING_PICK_MATERIALS then
        self:show_panel('Choose material', {
            {hint('+-', 'select  '), hint('Enter', 'use one')},
            {hint('Shift+Enter', 'use for all needed')},
            {hint('Esc', 'back to the build list')},
        }, nil, ClassicKeysOverlay.beside_native_panel())
        return
    elseif bottom == BOTTOM.STOCKPILE_PAINT then
        local lines, width = build_menu_lines(CLASSIC_STOCKPILES, 10, self.sp_type)
        lines[#lines + 1] = {
            {text=self.sp_type and ('type: ' .. self.sp_type.label) or 'type: choose after placing', pen=COLOR_YELLOW},
        }
        lines[#lines + 1] = {hint('Enter', 'corner (twice)  '), hint('x', 'remove pile under cursor')}
        lines[#lines + 1] = {hint('Esc', 'done')}
        self:show_panel('Stockpiles', lines, width, PANEL_LEFT_BESIDE_NATIVE)
        return
    elseif bottom == BOTTOM.STOCKPILE then
        local pile = mi.stockpile.cur_bld
        if pile and mi.custom_stockpile.open then
            -- the settings fill the screen bar the strip under the minimap
            self:show_panel('Pile settings', self:pile_settings_lines(), INFO_PANEL_W,
                gps.dimx - INFO_PANEL_W - 3, INFO_PANEL_TOP)
        elseif pile and self.sp_pending_id == pile.id then
            local lines, width = build_menu_lines(CLASSIC_STOCKPILES, 10)
            lines[#lines + 1] = {hint('Esc', 'leave it without a type')}
            self:show_panel('New stockpile: choose its type', lines, width, PANEL_LEFT_BESIDE_NATIVE)
        elseif pile and mi.stockpile_link.open then
            -- right of the game's links window
            self:show_panel('Stockpile links', self:link_lines(), 34, PANEL_LEFT_BESIDE_NATIVE + 42)
        elseif pile then
            self:show_panel('Stockpile', {
                {hint('E R', ('max barrels %d'):format(pile.storage.max_barrels))},
                {hint('C V', ('max bins %d'):format(pile.storage.max_bins))},
                {hint('w W', ('wheelbarrows %d'):format(pile.storage.max_wheelbarrows))},
                {hint('g', 'give to  '), hint('t', 'take from  '), hint('d', 'delete link')},
                {hint('a', pile.stockpile_flag.use_links_only and 'takes from links only'
                           or 'takes from anywhere')},
                {hint('s', 'settings  '), hint('x', 'remove it  '), hint('Esc', 'done')},
            }, nil, PANEL_LEFT_BESIDE_NATIVE)
        else
            self:hide_panel()
        end
        return
    elseif bottom == BOTTOM.ZONE then
        if self.mode == 'query' or mi.civzone.cur_bld then
            local lines = {
                {hint('a', 'assign animals / owner / squads')},
                {hint('l', 'location  '), hint('s', 'suspend  '), hint('n', 'name')},
            }
            local zone = mi.civzone.cur_bld
            if zone and zone.location_id ~= -1 then
                lines[2] = {hint('l', 'change location  '), hint('d', 'its details')}
                lines[3] = {hint('s', 'suspend  '), hint('n', 'name')}
            end
            for _, setting in ipairs(zone and ClassicKeysOverlay.zone_settings(zone) or {}) do
                lines[#lines + 1] = {hint(setting[1], setting[2])}
            end
            local beside = ClassicKeysOverlay.dfhack_room_box_bottom()
            if beside then lines[#lines + 1] = {hint('S', 'autoassign to a role (DFHack box above)')} end
            lines[#lines + 1] = {hint('X', 'remove zone  '), hint('Esc', 'done')}
            self:show_panel('Zone', lines, nil, PANEL_LEFT_BESIDE_NATIVE, beside and beside + 1)
        else
            local lines, width = build_menu_lines(CLASSIC_ZONES, 9)
            lines[#lines + 1] = {hint('X', 'remove selected zone  '), hint('Esc', 'done')}
            self:show_panel('Zones: choose a type to place', lines, width, PANEL_LEFT_BESIDE_NATIVE)
        end
        return
    elseif bottom == BOTTOM.ZONE_PAINT then
        local label = '?'
        for _, entry in ipairs(CLASSIC_ZONES) do
            if df.civzone_type[entry.zone] == mi.civzone.adding_new_type then label = entry.label end
        end
        local anchored = self.paint and self.paint.anchor
        self:show_panel('Zone: ' .. label, {
            {{text=anchored and 'first corner set; move to the other one' or 'move to the first corner',
              pen=COLOR_GREY}},
            {hint('arrows', 'move  '), hint('Enter', 'corner (twice)')},
            {hint('Esc', anchored and 'forget the corner' or 'back to the zone list')},
        }, nil, PANEL_LEFT_BESIDE_NATIVE)
        return
    end

    local bld = viewed_building()
    local unit = viewed_unit()
    if self.mode and unit then
        -- a creature's panel is up (v, or Enter in look mode): the old v keys
        self:show_panel(MODE_TITLES.unit, self:unit_lines(unit))
    elseif self.mode == 'look' then
        self:show_panel(MODE_TITLES.look, self:look_lines())
    elseif ClassicKeysOverlay.is_farm(bld) and (self.mode or focus_is('dwarfmode/ViewSheets/BUILDING/FarmPlot')) then
        self:show_panel(self.mode and MODE_TITLES[self.mode] or 'Farm plot', self:farm_lines(bld))
    elseif bld and self:listing_building_items(bld) then
        self:show_panel(MODE_TITLES[self.mode], self:building_item_lines(bld))
    elseif is_workshop(bld) and (self.mode or focus_is('dwarfmode/ViewSheets/BUILDING')) then
        self.job_idx = math.max(0, math.min(self.job_idx, #bld.jobs - 1))
        self:show_panel(self.mode and MODE_TITLES[self.mode] or 'Workshop', self:workshop_lines(bld))
    elseif self.mode == 'query' or self.mode == 'items' then
        local lines = {}
        if bld then
            lines[1] = {{text=clip(utils.getBuildingName(bld), PANEL_TEXT_W), pen=COLOR_LIGHTMAGENTA}}
        else
            lines[1] = {{text='no building nearby', pen=COLOR_GREY}}
        end
        if bld and df.building_tradedepotst:is_instance(bld) then
            local flags = bld.trade_flags
            lines[#lines + 1] = {hint('r', flags.trader_requested and 'call off the trader' or 'request a trader')}
            lines[#lines + 1] = {hint('b', flags.anyone_can_trade and 'broker only' or 'anyone may trade')}
            lines[#lines + 1] = {hint('t', 'trade  '), hint('g', 'move goods  '),
                                 {text='(with merchants)', pen=COLOR_GREY}}
        end
        if bld then
            local suspend = ClassicKeysOverlay.suspend_hint(bld)
            if suspend then lines[#lines + 1] = {suspend} end
            lines[#lines + 1] = {ClassicKeysOverlay.removal_hint(bld), '  ', hint('Esc', 'done')}
        else
            lines[#lines + 1] = {hint('Esc', 'done')}
        end
        self:show_panel(MODE_TITLES[self.mode], lines)
    elseif self.mode == 'unit' then
        local unit = vs.open and vs.active_sheet == df.view_sheet_type.UNIT and df.unit.find(vs.active_id)
        local lines = {}
        if unit then
            lines[1] = {{text=clip(dfhack.units.getReadableName(unit), PANEL_TEXT_W), pen=COLOR_LIGHTCYAN}}
        else
            lines[1] = {{text='no creature nearby', pen=COLOR_GREY}}
        end
        lines[#lines + 1] = {hint('Esc', 'done')}
        self:show_panel(MODE_TITLES.unit, lines)
    elseif designating() then
        local desig = current_designation()
        local lines
        if ITEM_DESIGNATIONS[desig] then
            lines = ClassicKeysOverlay.legend_lines(ITEM_LEGEND, desig)
            lines[#lines + 1] = {hint('arrows', 'move  '), hint('Enter', 'corners  '), hint('Esc', 'back')}
            self:show_panel('Item properties', lines)
        elseif TRAFFIC_DESIGNATIONS[desig] then
            lines = ClassicKeysOverlay.legend_lines(TRAFFIC_LEGEND, desig)
            lines[#lines + 1] = {hint('arrows', 'move  '), hint('Enter', 'corners  '), hint('Esc', 'back')}
            self:show_panel('Traffic', lines)
        else
            lines = ClassicKeysOverlay.legend_lines(DESIGNATE_LEGEND, desig)
            lines[#lines + 1] = {hint('arrows', 'move  '), hint('Enter', 'corners  '), hint('- =', 'priority')}
            self:show_panel('Designations', lines)
        end
    elseif not self.mode and ClassicKeysOverlay.root_keys_on() and ClassicKeysOverlay.on_bare_map() then
        local lines, width = ClassicKeysOverlay.root_lines()
        self:show_panel('Dwarf Fortress', lines, width)
    else
        self:hide_panel()
    end
end

---------------------------------------------------------------------------
-- cursor modes
---------------------------------------------------------------------------

function ClassicKeysOverlay:enter_mode(mode)
    local vp = guidm.Viewport.get()
    if not self.cursor or not vp:isVisible(self.cursor) then
        self.cursor = vp:getCenter()
    end
    -- (the game is paused for as long as a mode is up: see hold_the_clock)
    self.mode = mode
    self.target_id = nil
    self.job_idx = 0
    self:retarget()
end

function ClassicKeysOverlay:exit_mode()
    self.mode = nil
    self.target_id = nil
end

-- As it used to be: anything other than the bare map stops the clock. A
-- cursor mode (k q t v), designating, the build, stockpile and zone menus,
-- squads, the info window, announcements, a creature's or building's panel,
-- one of the overlay's own windows: while any of them is up the game is
-- paused, and when the last of them closes it is set going again if it was
-- running when the first one opened. (Space still works in between, and a
-- game unpaused that way is left running.)
function ClassicKeysOverlay:hold_the_clock(focus)
    local busy = self.mode ~= nil
        or mi.bottom_mode_selected ~= BOTTOM.NONE
        or vs.open
        or #focus ~= 1 or focus[1] ~= 'dwarfmode/Default'
        or dfhack.gui.matchFocusString('dfhack/lua/classic-controls')
    if busy and not self.was_busy then
        self.resume_after = not df.global.pause_state
        df.global.pause_state = true
    elseif not busy and self.was_busy then
        if self.resume_after then df.global.pause_state = false end
        self.resume_after = nil
    end
    self.was_busy = busy
end

-- A zone or stockpile whose panel the game has just opened by itself (Enter
-- on it in the Places list): carry on as if q had found it, so that its own
-- keys work rather than the keys that place a new one.
function ClassicKeysOverlay:query_opened_panel()
    local bottom = mi.bottom_mode_selected
    local bld = (bottom == BOTTOM.ZONE and mi.civzone.cur_bld)
        or (bottom == BOTTOM.STOCKPILE and mi.stockpile.cur_bld)
    if not bld or mi.info.open then return end
    self.cursor = xyz2pos(bld.centerx, bld.centery, bld.z)
    self.mode = 'query'
    self.target_id = bld.id
    self.job_idx = 0
    self:refresh_panel()
end

function ClassicKeysOverlay:close_sheet()
    if vs.open then
        self:feed('LEAVESCREEN')
    end
end

-- close the game's stockpile / zone / build panel, if one is up
function ClassicKeysOverlay:close_bottom_panel()
    for _ = 1, 3 do
        if mi.bottom_mode_selected == BOTTOM.NONE then return end
        self:feed('LEAVESCREEN')
    end
end

-- What q should show for the cursor: a building standing on the tile, else
-- the stockpile or zone the tile belongs to, else the nearest building.
local function query_target(pos)
    local here = dfhack.buildings.findAtTile(pos)
    if here and not NO_SHEET_BUILDINGS[here:getType()] then
        return 'building', here
    end
    if here and here:getType() == df.building_type.Stockpile then
        return 'stockpile', here
    end
    local zones = dfhack.buildings.findCivzonesAt(pos)
    if zones and zones[1] then
        return 'zone', zones[1]
    end
    local near = nearest_building(pos, SNAP_RANGE)
    if near then return 'building', near end
end

-- point the mode at whatever is nearest the cursor
function ClassicKeysOverlay:retarget()
    if self.mode == 'query' or self.mode == 'items' then
        local kind, bld = query_target(self.cursor)
        if self.mode == 'items' and kind ~= 'building' then
            -- t is about a building's items; stockpiles and zones have none
            kind, bld = nil, nil
        end
        if not bld or bld.id ~= self.target_id then
            self.item_idx = 1
        end
        local bottom = mi.bottom_mode_selected
        -- shut whichever of the game's panels the new target does not use
        if kind ~= 'building' and vs.open then self:close_sheet() end
        if (kind ~= 'stockpile' and bottom == BOTTOM.STOCKPILE)
            or (kind ~= 'zone' and bottom == BOTTOM.ZONE)
        then
            self:close_bottom_panel()
        end
        if kind == 'building' then
            if bld.id ~= self.target_id or viewed_building() ~= bld then
                open_building_sheet(bld)
                self.job_idx = 0
            end
        elseif kind == 'stockpile' then
            mi.stockpile.cur_bld = bld
            mi.stockpile.erasing = false
            mi.stockpile.repainting = false
            mi.bottom_mode_selected = BOTTOM.STOCKPILE
        elseif kind == 'zone' then
            mi.civzone.cur_bld = bld
            mi.civzone.erasing = false
            mi.civzone.repainting = false
            mi.bottom_mode_selected = BOTTOM.ZONE
        end
        self.target_id = bld and bld.id or nil
    elseif self.mode == 'unit' then
        local unit = nearest_unit(self.cursor, SNAP_RANGE)
        if unit then
            if unit.id ~= self.target_id or not vs.open then
                self:show_unit(unit)
            end
            self.target_id = unit.id
        else
            if self.target_id then self:close_sheet() end
            self.target_id = nil
        end
    end
end

function ClassicKeysOverlay:move_cursor(dx, dy, dz)
    local pos = xyz2pos(self.cursor.x + dx, self.cursor.y + dy, self.cursor.z + dz)
    if not dfhack.maps.isValidTilePos(pos) then return end
    self.cursor = pos
    self:retarget()
end

-- interface columns hidden on the right: an open unit/building panel plus the
-- minimap column beside it, or just the minimap column
local SHEET_COLS = 98
local MINIMAP_COLS = 38
-- alert icons down the left edge, toolbar along the bottom, top bar
local LEFT_COLS, BOTTOM_ROWS, TOP_ROWS = 6, 4, 4
-- width of the game's stockpile / zone panel on the left
local NATIVE_PANEL_COLS = 47

-- Scroll the map just enough that the cursor sits in the part of the screen
-- nothing is drawn over. The new UI floats its panels over the map, so simply
-- keeping the cursor inside the viewport would leave it hidden under them.
function ClassicKeysOverlay:keep_cursor_clear()
    local cursor = self.cursor
    local tile_w, tile_h = gps.tile_pixel_x, gps.tile_pixel_y
    if dfhack.screen.inGraphicsMode() then
        tile_w = gps.viewport_zoom_factor // 4
        tile_h = tile_w
    end
    local panel = self.subviews.panel
    local top_rows = panel.visible and (panel.frame.t + panel.frame.h) or TOP_ROWS
    local right_cols = gps.dimx - (vs.open and SHEET_COLS or MINIMAP_COLS)
    local left_cols = LEFT_COLS
    local bottom = mi.bottom_mode_selected
    if mi.squads.open and mi.patrol_routes.open then
        -- the route editor's window stands left of the squads panel, further
        -- left still when it was opened from a schedule's orders
        local x = find_screen_text('Point', {x1=60}) or find_screen_text('Click the map', {x1=60})
        if x then right_cols = x - 4 end
    end
    if bottom == BOTTOM.STOCKPILE or bottom == BOTTOM.ZONE then
        -- the game's stockpile / zone panel fills the top-left of the screen
        left_cols = NATIVE_PANEL_COLS
        -- and a stockpile's links window stands beside it
        if mi.stockpile_link.open then left_cols = NATIVE_PANEL_COLS + 42 end
    end

    -- the clear rectangle, in map tiles from the viewport's top-left corner
    local x1 = math.ceil(left_cols * gps.tile_pixel_x / tile_w) + 1
    local x2 = math.max(x1, math.floor(right_cols * gps.tile_pixel_x / tile_w) - 2)
    local y1 = math.ceil(top_rows * gps.tile_pixel_y / tile_h) + 1
    local y2 = math.max(y1, math.floor((gps.dimy - BOTTOM_ROWS) * gps.tile_pixel_y / tile_h) - 2)

    local wx, wy = df.global.window_x, df.global.window_y
    local sx, sy = cursor.x - wx, cursor.y - wy
    if sx < x1 then wx = cursor.x - x1 elseif sx > x2 then wx = cursor.x - x2 end
    if sy < y1 then wy = cursor.y - y1 elseif sy > y2 then wy = cursor.y - y2 end
    df.global.window_x, df.global.window_y, df.global.window_z = wx, wy, cursor.z
end

-- mark the selected task on the game's own task list
function ClassicKeysOverlay:render_job_marker(bld)
    if #bld.jobs == 0 or vs.active_sub_tab ~= 0 then return end
    -- the list is located once per panel by finding its "Tasks" tab on screen
    local anchor_key = ('%d/%d/%d'):format(bld.id, gps.dimx, gps.dimy)
    if self.anchor_key ~= anchor_key then
        local x, y = find_screen_text('Tasks')
        if not x then return end
        self.anchor = {x=x, y=y}
        self.anchor_key = anchor_key
    end
    -- tasks start 4 rows under the tab label and take 3 rows each
    local first_row = self.anchor.y + 4
    local row = first_row + 3 * (self.job_idx - vs.scroll_position_building_job)
    if row >= first_row and row < gps.dimy - BOTTOM_ROWS then
        mark_row(self.anchor.x - 2, row, 34)
    end
end

-- Enter in look mode: open the panel of the thing selected in the tile's list
function ClassicKeysOverlay:open_under_cursor()
    local things = look_things(self.cursor)
    local thing = things[math.max(1, math.min(self.look_idx or 1, #things))]
    if not thing then return end
    if thing.kind == 'unit' then
        open_unit_sheet(thing.obj)
    elseif thing.kind == 'item' then
        open_item_sheet(thing.obj)
    elseif thing.obj:getType() == df.building_type.Stockpile then
        -- a stockpile's panel is the q one; carry on as if q had been pressed
        self.mode = 'query'
        self:retarget()
    elseif not NO_SHEET_BUILDINGS[thing.obj:getType()] then
        open_building_sheet(thing.obj)
    end
end

-- - and + are "keyboard cursor up/down a level" in the game's keymap. The old
-- game changed level with < and > only and used - and + to move through
-- lists, so those two codes never count as movement here.
local LIST_KEYS_NOT_MOVES = utils.invert{'KEYBOARD_CURSOR_UP_Z', 'KEYBOARD_CURSOR_DOWN_Z'}

-- One physical key usually arrives as several movement codes at once (the
-- arrow keys are bound to both the camera and the keyboard cursor); the first
-- match is enough, so a press moves the cursor exactly once: 1 tile, or 10
-- with Shift, as it always was. < and > change level whatever they are bound
-- to, by the character typed.
-- a letter, with or without Shift / Alt (but not Ctrl, which is DFHack's)
local function letter_key_pressed(keys)
    for code in pairs(keys) do
        if type(code) == 'string'
            and (code:match('^CUSTOM_%u$') or code:match('^CUSTOM_SHIFT_%u$') or code:match('^CUSTOM_ALT_%u$'))
        then
            return true
        end
    end
    return false
end

local function get_move(keys)
    -- Letters are commands here, never movement. Keymaps put the camera on
    -- letters (w a s d by default, Shift+w a s d and Shift+e c for the fast
    -- and level moves), so without this a press of A or S or W or C would be
    -- taken as "move" and never reach the key it is meant to be.
    if letter_key_pressed(keys) then return end
    for code in pairs(keys) do
        if not LIST_KEYS_NOT_MOVES[code] then
            local dx, dy, dz = guidm.get_movement_delta(code, 1, 10)
            if dx then return dx, dy, dz end
        end
    end
    local ch = keys._STRING
    if ch == string.byte('<') then return 0, 0, 1 end
    if ch == string.byte('>') then return 0, 0, -1 end
end

local function sign(n)
    return n > 0 and 1 or n < 0 and -1 or 0
end

-- get_move, minus one artefact of real keyboards: if Shift is let go a moment
-- before the arrow key, the game reports the arrow a second time without
-- Shift. That stray single step straight after a 10-tile one is dropped.
function ClassicKeysOverlay:take_move(keys)
    local dx, dy, dz = get_move(keys)
    if not dx then return end
    local now = dfhack.getTickCount()
    if math.abs(dx) > 1 or math.abs(dy) > 1 then
        self.last_fast_move = {at=now, sx=sign(dx), sy=sign(dy)}
    else
        local last = self.last_fast_move
        self.last_fast_move = nil
        if last and dz == 0 and now - last.at < 200 and sign(dx) == last.sx and sign(dy) == last.sy then
            return 0, 0, 0
        end
    end
    return dx, dy, dz
end

-- Move the game's own keyboard cursor (designations, building placement).
-- Left to itself the game would also scroll the camera for the same key
-- press when both are bound to the arrows, dragging the cursor along, and its
-- Shift step is 20. Taking the key here gives the old 1 and 10.
function ClassicKeysOverlay:on_native_cursor_input(keys)
    local dx, dy, dz = self:take_move(keys)
    if not dx then return false end
    local from = guidm.getCursorPos() or guidm.Viewport.get():getCenter()
    local pos = xyz2pos(from.x + dx, from.y + dy, from.z + dz)
    if dfhack.maps.isValidTilePos(pos) then
        guidm.setCursorPos(pos)
        local own_cursor = self.cursor
        self.cursor = pos
        self:keep_cursor_clear()
        self.cursor = own_cursor
    end
    return true
end

---------------------------------------------------------------------------
-- workshop keys
---------------------------------------------------------------------------

function ClassicKeysOverlay:open_task_picker(tries_left)
    tries_left = tries_left or 3
    if not add_task_list_open() and not click_label('Add new task') then
        -- the button is found by reading the screen, so a panel opened this
        -- very frame has not been drawn yet; look again shortly
        if tries_left > 0 then
            dfhack.timeout(2, 'frames', function()
                if is_workshop(viewed_building()) then
                    self:open_task_picker(tries_left - 1)
                end
            end)
        else
            dfhack.printerr('classic-controls: could not find the "Add new task" button')
        end
        return
    end
    if #mi.building.button == 0 then return end
    TaskPicker{on_close=function() self:refresh_panel() end}:show()
end

-- The trade depot, with the old q-on-a-depot keys: r asks for a trader or
-- calls that off, b switches between the broker and anyone, t trades and g
-- moves goods to the depot. All are buttons on the game's panel, found by
-- their text below the "Trade Depot" title; the last two are only there
-- while merchants are at the depot.
function ClassicKeysOverlay:on_depot_input(keys, bld)
    -- (the sheet is 60 columns wide at the right, whatever the screen's width)
    local bounds = {y1=TOP_ROWS + 4, x1=gps.dimx - SHEET_COLS - 2}
    local flags = bld.trade_flags
    if keys.CUSTOM_R then
        if flags.trader_requested then
            click_label('No trader needed', bounds)
        else
            click_label(flags.anyone_can_trade and 'Anyone requested' or 'Broker requested', bounds)
        end
    elseif keys.CUSTOM_B then
        click_label(flags.anyone_can_trade and 'Broker requested' or 'Anyone requested', bounds)
    elseif keys.CUSTOM_T then
        return click_label('Trade', bounds) and true or false
    elseif keys.CUSTOM_G then
        return click_label('Move goods', bounds) and true or false
    else
        return false
    end
    return true
end

function ClassicKeysOverlay:on_workshop_input(keys, bld)
    -- only on the Tasks tab; the Workers and Work orders tabs keep stock keys
    if vs.active_sub_tab ~= 0 then return false end
    if keys.CUSTOM_A then
        self:open_task_picker()
        return true
    end
    local n = #bld.jobs
    -- + and - by bound action or, failing that, by the character typed: the
    -- "+" binding in particular varies between keyboard layouts
    local ch = keys._STRING
    if keys.SECONDSCROLL_DOWN or ch == string.byte('+') or ch == string.byte('=') then
        if n > 0 then self.job_idx = (self.job_idx + 1) % n end
        return true
    elseif keys.SECONDSCROLL_UP or ch == string.byte('-') then
        if n > 0 then self.job_idx = (self.job_idx - 1) % n end
        return true
    end
    local job = n > 0 and bld.jobs[math.min(self.job_idx, n - 1)] or nil
    if keys.CUSTOM_R then
        if job then job.flags['repeat'] = not job.flags['repeat'] end
        return true
    elseif keys.CUSTOM_S then
        if job then job.flags.suspend = not job.flags.suspend end
        return true
    elseif keys.CUSTOM_N then
        if job then job.flags.do_now = not job.flags.do_now end
        return true
    elseif keys.CUSTOM_C then
        if job then
            dfhack.job.removeJob(job)
            self.job_idx = math.max(0, math.min(self.job_idx, #bld.jobs - 1))
        end
        return true
    elseif keys.CUSTOM_D then
        -- the task's details (what it is made of...): the magnifier on its
        -- row, which only tasks with something to choose have
        if job and self.anchor then
            self.rows_idx = 0
            click_screen(gps.dimx - 47,
                self.anchor.y + 4 + 3 * (self.job_idx - vs.scroll_position_building_job))
        end
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- input
---------------------------------------------------------------------------

-- a building's items (the old t, and q on anything that is not a workshop) ---

-- Is the item list what - and = act on for this building? Always in t; in q
-- only where there is no task list to select from instead (a coffin, a door).
function ClassicKeysOverlay:listing_building_items(bld)
    return self.mode == 'items' or (self.mode == 'query' and not is_workshop(bld))
end

local ITEM_LIST_ROWS = 10

-- the items a building is made of and holds, in the game's order
local function building_items(bld)
    local items = {}
    for _, contained in ipairs(bld.contained_items) do
        items[#items + 1] = contained.item
    end
    return items
end

function ClassicKeysOverlay:building_item_lines(bld)
    local lines = {{{text=clip(utils.getBuildingName(bld), PANEL_TEXT_W), pen=COLOR_LIGHTMAGENTA}}}
    local items = building_items(bld)
    if #items == 0 then
        lines[#lines + 1] = {{text='no items', pen=COLOR_GREY}}
    end
    self.item_idx = math.max(1, math.min(self.item_idx or 1, #items))
    local first = math.max(1, math.min(self.item_idx - ITEM_LIST_ROWS // 2, #items - ITEM_LIST_ROWS + 1))
    for i = first, math.min(#items, first + ITEM_LIST_ROWS - 1) do
        local item = items[i]
        local selected = i == self.item_idx
        local flags = (item.flags.forbid and 'F' or ' ') .. (item.flags.dump and 'D' or ' ')
        lines[#lines + 1] = {
            {text=selected and string.char(16) or ' ', pen=COLOR_YELLOW},
            {text=flags .. ' ', pen=COLOR_LIGHTRED},
            {text=clip(item_name(item), PANEL_TEXT_W - 4), pen=selected and COLOR_YELLOW or COLOR_WHITE},
        }
    end
    if #items > ITEM_LIST_ROWS then
        lines[#lines + 1] = {{text=('%d of %d'):format(self.item_idx, #items), pen=COLOR_GREY}}
    end
    lines[#lines + 1] = {hint('- =', 'select  '), hint('Enter', 'view  '), hint('f', 'forbid  '), hint('d', 'dump')}
    local suspend = ClassicKeysOverlay.suspend_hint(bld)
    if suspend then lines[#lines + 1] = {suspend} end
    lines[#lines + 1] = {ClassicKeysOverlay.removal_hint(bld), '  ', hint('Esc', 'done')}
    return lines
end

function ClassicKeysOverlay:on_building_items_input(keys, bld)
    local items = building_items(bld)
    local step = list_step(keys)
    if step then
        if #items > 0 then
            self.item_idx = ((self.item_idx or 1) - 1 + step) % #items + 1
        end
        return true
    end
    local item = items[math.max(1, math.min(self.item_idx or 1, #items))]
    if keys.SELECT then
        if item then
            -- Esc from the item's panel comes back here (see on_mode_input)
            self.return_bld_id = bld.id
            open_item_sheet(item)
        end
        return true
    elseif keys.CUSTOM_F then
        if item then item.flags.forbid = not item.flags.forbid end
        return true
    elseif keys.CUSTOM_D then
        if item then item.flags.dump = not item.flags.dump end
        return true
    end
    return false
end

-- < and > ---------------------------------------------------------------------

-- Change level by the character typed. The cursor modes do this for their own
-- cursor (see get_move); this covers everywhere else, the bare map above all.
-- If the game itself reports a level key for the press, it is already
-- handling it and this stays out of the way.
function ClassicKeysOverlay:on_level_keys(keys)
    if keys.CURSOR_UP_Z or keys.CURSOR_DOWN_Z or keys.CURSOR_UP_Z_AUX or keys.CURSOR_DOWN_Z_AUX then
        return false
    end
    local ch = keys._STRING
    if ch == string.byte('<') then
        self:feed('CURSOR_UP_Z')
        return true
    elseif ch == string.byte('>') then
        self:feed('CURSOR_DOWN_Z')
        return true
    end
    return false
end

-- build menu ---------------------------------------------------------------

-- Open the game's build menu at a given page. Esc closes that menu outright
-- whatever its depth, so every page is reached from a fresh menu.
function ClassicKeysOverlay:open_native_build_menu(path)
    if mi.bottom_mode_selected ~= BOTTOM.NONE then
        self:feed('LEAVESCREEN')
    end
    self:feed('D_BUILDING')
    for _, name in ipairs(path or {}) do
        self:feed(BUILD_KEY_PREFIX .. name)
    end
end

function ClassicKeysOverlay:show_build_menu(id)
    self:open_native_build_menu(CLASSIC_BUILD[id].native)
    self.build_menu = id
end

function ClassicKeysOverlay:start_building(entry)
    if entry.click then
        -- no hotkey in the game: open its page of the game's menu and click
        -- the building's name there once the page has been drawn
        self:open_native_build_menu(entry.path)
        dfhack.timeout(10, 'frames', function()
            if mi.bottom_mode_selected == BOTTOM.BUILDING
                and click_label(entry.click, {y1=gps.dimy // 2})
                and mi.bottom_mode_selected == BOTTOM.BUILDING_PLACEMENT
            then
                self.build_menu = nil
            end
        end)
        return
    end
    self:open_native_build_menu(NATIVE_BUILD_PATH[entry.leaf])
    self:feed(BUILD_KEY_PREFIX .. entry.leaf)
    if mi.bottom_mode_selected ~= BOTTOM.BUILDING_PLACEMENT then
        dfhack.printerr(('classic-controls: could not start placing "%s"; the build menu may have changed (see cc-dev/build-tree)')
            :format(entry.label))
        self.build_menu = 'top'
        return
    end
    self.build_menu = nil
end

-- is this key press the hotkey of a raw-defined (custom) building on show?
local function custom_building_key_pressed(keys)
    for _, page in ipairs(con.page) do
        for _, button in ipairs(page.bb_button) do
            local name = df.interface_key[button.hotkey]
            if button.custom_building_id >= 0 and name and keys[name] then
                return true
            end
        end
    end
    return false
end

function ClassicKeysOverlay:on_build_menu_input(keys)
    local id = self.build_menu or 'top'
    if keys.LEAVESCREEN then
        if id ~= 'top' then
            self:show_build_menu('top')
            return true
        end
        self.build_menu = nil
        return false
    end
    for _, entry in ipairs(CLASSIC_BUILD[id]) do
        for _, code in ipairs(entry.codes) do
            if keys[code] then
                if entry.submenu then
                    self:show_build_menu(entry.submenu)
                else
                    self:start_building(entry)
                end
                return true
            end
        end
    end
    -- workshops defined in the raws (stock or modded) keep the key the raws
    -- give them, exactly as they did in the old menu
    if custom_building_key_pressed(keys) then return false end
    -- a letter with no classic meaning here does nothing, as before; without
    -- this it would fire whichever building or screen the new layout has
    -- put on that key
    return letter_key_pressed(keys)
end

function ClassicKeysOverlay:on_placement_input(keys)
    if keys.LEAVESCREEN then
        -- back to the build list, not all the way out to the map
        self:show_build_menu('top')
        return true
    end
    if self:on_native_cursor_input(keys) then return true end
    -- - and = do not change level here either
    return list_step(keys) ~= nil
end

-- pick-materials list ------------------------------------------------------

-- The list is located by its heading; rows start 7 below it, 3 rows apiece,
-- and scroll_position_item counts screen rows.
local MATERIAL_ROW_H = 3

function ClassicKeysOverlay:materials_anchor()
    local key = ('%d/%d'):format(gps.dimx, gps.dimy)
    if self.mat_anchor_key ~= key then
        local x, y = find_screen_text('Select materials for')
        if not x then return nil end
        self.mat_anchor = {x=x, first_row=y + 7}
        self.mat_anchor_key = key
    end
    return self.mat_anchor
end

function ClassicKeysOverlay:material_row(anchor)
    return anchor.first_row + MATERIAL_ROW_H * self.mat_idx - con.scroll_position_item
end

function ClassicKeysOverlay:scroll_material_into_view()
    local anchor = self:materials_anchor()
    if not anchor then return end
    local visible_rows = math.max(MATERIAL_ROW_H, gps.dimy - 8 - anchor.first_row)
    local top = MATERIAL_ROW_H * self.mat_idx
    local scroll = con.scroll_position_item
    if top < scroll then
        scroll = top
    elseif top + MATERIAL_ROW_H > scroll + visible_rows then
        scroll = top + MATERIAL_ROW_H - visible_rows
    end
    con.scroll_position_item = math.max(0, scroll)
end

-- columns to click on a row, counted from the heading's first character
local MATERIAL_NAME_DX = 20  -- the name: use one of this material
local MATERIAL_ALL_DX = 58   -- the "All" button: use it for everything needed

function ClassicKeysOverlay:pick_material(use_all, tries_left)
    tries_left = tries_left or 3
    local anchor = self:materials_anchor()
    if not anchor then
        -- the list was opened this very frame and is not drawn yet
        if tries_left > 0 then
            dfhack.timeout(2, 'frames', function()
                if mi.bottom_mode_selected == BOTTOM.BUILDING_PICK_MATERIALS then
                    self:pick_material(use_all, tries_left - 1)
                end
            end)
        end
        return
    end
    local n = #buildreq.choices
    if n == 0 then return end
    self.mat_idx = math.max(0, math.min(self.mat_idx, n - 1))
    self:scroll_material_into_view()
    click_screen(anchor.x + (use_all and MATERIAL_ALL_DX or MATERIAL_NAME_DX), self:material_row(anchor))
    if mi.bottom_mode_selected == BOTTOM.NONE then
        -- built; the old game went back to the build list for the next one
        self:show_build_menu('top')
    end
end

function ClassicKeysOverlay:on_pick_materials_input(keys)
    if keys.LEAVESCREEN then
        self:show_build_menu('top')
        return true
    end
    local ch = keys._STRING
    local step
    if keys.SECONDSCROLL_DOWN or keys.STANDARDSCROLL_DOWN or keys.KEYBOARD_CURSOR_DOWN
        or ch == string.byte('+') or ch == string.byte('=')
    then
        step = 1
    elseif keys.SECONDSCROLL_UP or keys.STANDARDSCROLL_UP or keys.KEYBOARD_CURSOR_UP
        or ch == string.byte('-')
    then
        step = -1
    elseif keys.STANDARDSCROLL_PAGEDOWN or keys.SECONDSCROLL_PAGEDOWN then
        step = 10
    elseif keys.STANDARDSCROLL_PAGEUP or keys.SECONDSCROLL_PAGEUP then
        step = -10
    end
    if step then
        local n = #buildreq.choices
        if n > 0 then
            self.mat_idx = math.max(0, math.min(n - 1, self.mat_idx + step))
            self:scroll_material_into_view()
        end
        return true
    end
    -- Shift+Enter arrives as SEC_SELECT / SELECT_ALL, usually alongside SELECT
    if keys.SEC_SELECT or keys.SELECT_ALL then
        self:pick_material(true)
        return true
    elseif keys.SELECT then
        self:pick_material(false)
        return true
    end
    return false
end

-- keyboard rectangles (stockpiles and zones) ---------------------------------
--
-- The game paints these with two mouse clicks, one per corner, and has no
-- keyboard path at all. We keep our own cursor, and on the second Enter click
-- both corners for the player and then the game's "Accept" button.

local function map_tile_size()
    if dfhack.screen.inGraphicsMode() then
        local size = gps.viewport_zoom_factor // 4
        return size, size
    end
    return gps.tile_pixel_x, gps.tile_pixel_y
end

function ClassicKeysOverlay:ensure_paint_state()
    if not self.paint then self.paint = {anchor=nil} end
    if not self.cursor or not guidm.Viewport.get():isVisible(self.cursor) then
        self.cursor = guidm.Viewport.get():getCenter()
        self:keep_cursor_clear()
    end
end

-- left-click a map tile, scrolling first if it is off screen or under a panel
function ClassicKeysOverlay:click_map_tile(pos)
    local own_cursor = self.cursor
    self.cursor = pos
    self:keep_cursor_clear()
    self.cursor = own_cursor

    local tile_w, tile_h = map_tile_size()
    local px = (pos.x - df.global.window_x) * tile_w + tile_w // 2
    local py = (pos.y - df.global.window_y) * tile_h + tile_h // 2
    local saved = {gps.mouse_x, gps.mouse_y, gps.precise_mouse_x, gps.precise_mouse_y}
    gps.precise_mouse_x, gps.precise_mouse_y = px, py
    gps.mouse_x, gps.mouse_y = px // gps.tile_pixel_x, py // gps.tile_pixel_y
    gui.simulateInput(df_screen(), '_MOUSE_L')
    gps.mouse_x, gps.mouse_y, gps.precise_mouse_x, gps.precise_mouse_y = table.unpack(saved)
end

function ClassicKeysOverlay:commit_rectangle(kind)
    local corner = xyz2pos(self.paint.anchor.x, self.paint.anchor.y, self.cursor.z)
    self.paint.anchor = nil
    self:click_map_tile(corner)
    self:click_map_tile(self.cursor)
    self:keep_cursor_clear()

    local made
    if kind == 'stockpile' then made = mi.stockpile.cur_bld else made = mi.civzone.cur_bld end
    if not made then
        dfhack.printerr('classic-controls: the game did not accept that rectangle (no usable tiles?)')
        return
    end
    if not click_label('Accept') then
        dfhack.printerr('classic-controls: could not find the "Accept" button')
        return
    end
    if kind == 'stockpile' then
        self.sp_pending_id = made.id
        if self.sp_type then
            self:apply_stockpile_preset(self.sp_type, 6)
        end
    end
end

function ClassicKeysOverlay:on_paint_input(keys, kind)
    self:ensure_paint_state()
    if keys.LEAVESCREEN then
        if self.paint.anchor then
            -- forget the first corner
            self.paint.anchor = nil
            return true
        end
        if kind == 'zone' then
            -- back to the zone list rather than out to the map
            self:close_bottom_panel()
            self:feed('D_CIVZONE')
            return true
        end
        return false
    end

    local dx, dy, dz = self:take_move(keys)
    if dx then
        local pos = xyz2pos(self.cursor.x + dx, self.cursor.y + dy, self.cursor.z + dz)
        if dfhack.maps.isValidTilePos(pos) then self.cursor = pos end
        return true
    end
    if list_step(keys) then return true end

    if keys.SELECT then
        if self.paint.anchor then
            self:commit_rectangle(kind)
        else
            self.paint.anchor = copyall(self.cursor)
        end
        return true
    end

    if kind == 'stockpile' then
        if keys.CUSTOM_X then
            local here = dfhack.buildings.findAtTile(self.cursor)
            if here and here:getType() == df.building_type.Stockpile then
                if mi.stockpile.cur_bld == here then mi.stockpile.cur_bld = nil end
                dfhack.buildings.deconstruct(here)
            end
            return true
        end
        local entry = pressed_entry(CLASSIC_STOCKPILES, keys)
        if entry then
            self.sp_type = entry
            return true
        end
    end
    -- stray letters do nothing rather than jumping to another screen
    return letter_key_pressed(keys)
end

-- stockpiles -----------------------------------------------------------------

-- The preset buttons are found by their labels. Each button is the icon to the
-- left of its label: 4 columns wide, starting 5 columns before the text.
function ClassicKeysOverlay:apply_stockpile_preset(entry, tries_left)
    if mi.bottom_mode_selected ~= BOTTOM.STOCKPILE or not mi.stockpile.cur_bld then return end
    local x, y = find_screen_text(entry.preset, {y1=TOP_ROWS + 1, x2=PANEL_LEFT_BESIDE_NATIVE - 6})
    if not x then
        -- the panel only appears on the frame after the stockpile is accepted
        if tries_left > 0 then
            dfhack.timeout(1, 'frames', function()
                self:apply_stockpile_preset(entry, tries_left - 1)
            end)
        else
            dfhack.printerr(('classic-controls: could not find the "%s" stockpile button'):format(entry.preset))
        end
        return
    end
    click_screen(x - 4, y + (entry.two_line and 1 or 0))
    self.sp_pending_id = nil
    if not entry.custom then
        -- carry on placing stockpiles of this type, as the old menu did
        self:close_bottom_panel()
        self:feed('D_STOCKPILES')
    end
end

-- detailed stockpile settings (s on a stockpile) --------------------------------
--
-- Three columns, as the old screen had: categories, the selected category's
-- sub-categories, and the items of the selected sub-category. Rows are 3
-- apart, 4 rows under the "All" / "None" buttons that head each column:
--   left pair    everything in the stockpile (not on a key)
--   middle pair  everything in the selected category     (old e / d)
--   right pair   every item in the list on the right     (old a / b)
-- A click on a category or on a sub-category that has a list only selects it;
-- a click on an item, or on a sub-category that is a plain yes / no, toggles
-- it. Columns are found from the three "All" labels.
--
-- (In a block of its own, like the info window further down: a Lua chunk may
-- hold 200 local names and this file's top level is close to that.)
do
local pile_ui = mi.custom_stockpile

local function pile_columns()
    local all, bounds = {}, {y1=TOP_ROWS, y2=TOP_ROWS + 4}
    while #all < 3 do
        local x, y = find_screen_text('All', bounds)
        if not x then break end
        all[#all + 1] = x
        bounds.x1, bounds.y1, bounds.y2 = x + 1, y, y
    end
    if #all == 0 then return end
    -- A category with no sub-categories (corpses: straight to a list of
    -- creatures) has no "All / None" over the middle column, so only two are
    -- found: the middle one is put where it was last seen. Giving up here
    -- would leave the screen without keys, with no way off the category.
    if #all == 3 then
        ClassicKeysOverlay.pile_middle = all[2] - all[1]
    elseif #all == 2 then
        all[3] = all[2]
        all[2] = all[1] + (ClassicKeysOverlay.pile_middle or 42)
    else
        all[2] = all[1] + (ClassicKeysOverlay.pile_middle or 42)
        all[3] = all[2] + 35
    end
    local first = bounds.y1 + 4
    return {
        all_row=bounds.y1, first=first,
        visible=math.max(1, (gps.dimy - 7 - first) // 3),
        x={all[1] + 5, all[2] - 1, all[3] - 1},
        all=all,
        none={all[1] + 6, all[2] + 7, all[3] + 7},
        organic=all[1] + 21, inorganic=all[1] + 26,
    }
end

local PILE_SCROLL = {'scroll_position_main', 'scroll_position_sub', 'scroll_position_spec'}

local function pile_count(col)
    if col == 1 then return #pile_ui.main_mode end
    if col == 2 then return #pile_ui.sub_mode end
    return pile_ui.counted_cur_spec_item_sz
end

-- a sub-category that is one yes / no setting rather than a list of items
local function pile_sub_is_switch(idx)
    return pile_ui.sub_mode_ptr_type[idx] ~= -1
end

local function pile_switch_on(idx)
    local ok, value = pcall(function() return pile_ui.sub_mode_ptr[idx].value end)
    return ok and value ~= 0
end

local function pile_item_on(idx)
    local ok, value = pcall(function() return pile_ui.spec_item[idx].set_pointer.value end)
    return ok and value ~= 0
end

-- Selecting a category makes the game switch that category's group on, with
-- nothing in it allowed; merely moving through the list must not leave that
-- behind, so the groups are put back as they were after a selecting click.
-- (the settings of a stockpile, or of a hauling stop, which has no building)
local function pile_settings()
    return (pile_ui.abd and pile_ui.abd.settings) or pile_ui.sp
end

local function pile_select_click(x, y)
    local settings = pile_settings()
    local groups = settings and settings.flags.whole
    click_screen(x, y)
    if settings then settings.flags.whole = groups end
end

-- The category and (list) sub-category selections are the game's own, so
-- they are read back from it: the screen may have been opened or clicked
-- with the mouse.
function ClassicKeysOverlay:pile_sync()
    self.pile_idx = self.pile_idx or {0, 0, 0}
    self.pile_col = self.pile_col or 1
    for i, mode in ipairs(pile_ui.main_mode) do
        if mode == pile_ui.cur_main_mode then self.pile_idx[1] = i end
    end
    local sub = self.pile_idx[2]
    if sub >= #pile_ui.sub_mode or not pile_sub_is_switch(sub) then
        for i, mode in ipairs(pile_ui.sub_mode) do
            if mode ~= -1 and mode == pile_ui.cur_sub_mode then self.pile_idx[2] = i end
        end
    end
end

-- the screen row of the selection in a column, scrolled into view
function ClassicKeysOverlay:pile_row(cols, col)
    local count = pile_count(col)
    if count == 0 then return end
    self.pile_idx = self.pile_idx or {0, 0, 0}
    local idx = math.max(0, math.min(self.pile_idx[col], count - 1))
    self.pile_idx[col] = idx
    local field = PILE_SCROLL[col]
    local scroll = math.max(0, pile_ui[field])
    if idx < scroll then
        scroll = idx
    elseif idx >= scroll + cols.visible then
        scroll = idx - cols.visible + 1
    end
    pile_ui[field] = scroll
    return cols.first + 3 * (idx - scroll), idx
end

function ClassicKeysOverlay:pile_move(cols, col, delta)
    self.pile_idx = self.pile_idx or {0, 0, 0}
    local before = self.pile_idx[col]
    self.pile_idx[col] = before + delta
    local row, idx = self:pile_row(cols, col)
    if not row or idx == before then return end
    if col == 1 then
        -- show this category's sub-categories and items
        pile_select_click(cols.x[1] + 2, row)
        self.pile_idx[2], self.pile_idx[3] = 0, 0
        pile_ui.scroll_position_sub, pile_ui.scroll_position_spec = 0, 0
    elseif col == 2 and not pile_sub_is_switch(idx) then
        pile_select_click(cols.x[2] + 2, row)
        self.pile_idx[3] = 0
        pile_ui.scroll_position_spec = 0
    end
end

-- The other half of pile_select_click: once something in the selected
-- category is allowed, its group has to be on for the stockpile to take it
-- (the game counts on the selecting click having done that).
local function pile_group_on()
    local settings = pile_settings()
    if settings then
        settings.flags.whole = settings.flags.whole | pile_ui.cur_main_mode_flag.whole
    end
end

-- allow or forbid whatever is selected, or flip it when `want` is nil
function ClassicKeysOverlay:pile_set(cols, col, want)
    local row, idx = self:pile_row(cols, col)
    local now_on = want
    if col == 1 then
        -- (a category with no sub-categories has only its items' All / None)
        local over = pile_count(2) == 0 and 3 or 2
        if want ~= nil then click_screen(want and cols.all[over] or cols.none[over], cols.all_row) end
    elseif not row then
        return
    elseif col == 2 then
        if pile_sub_is_switch(idx) then
            if want == nil or want ~= pile_switch_on(idx) then click_screen(cols.x[2] + 2, row) end
            now_on = pile_switch_on(idx)
        elseif want ~= nil then
            click_screen(want and cols.all[3] or cols.none[3], cols.all_row)
        end
    else
        if want == nil or want ~= pile_item_on(idx) then click_screen(cols.x[3] + 2, row) end
        now_on = pile_item_on(idx)
    end
    if now_on then pile_group_on() end
end

function ClassicKeysOverlay:on_pile_settings_input(keys)
    if pile_ui.entering_spec_filter then
        -- typing in the item filter: the game takes the keys, bar Esc
        if keys.LEAVESCREEN then
            pile_ui.entering_spec_filter = false
            return true
        end
        return false
    end
    if keys.LEAVESCREEN then
        pile_ui.open = false
        return true
    end
    local cols = pile_columns()
    if not cols then return letter_key_pressed(keys) end
    self:pile_sync()
    local col = self.pile_col
    if keys._STRING == 47 then
        -- "/" starts the item filter. (Checked before the movement keys: "/"
        -- also arrives as a page-down.) The filter box is right of the third
        -- "None" and has to be clicked: raising entering_spec_filter alone
        -- does not start the typing, and the letters that followed would go
        -- to the map's hotkeys.
        self.pile_col = 3
        self.pile_idx[3] = 0
        click_screen(cols.none[3] + 10, cols.all_row)
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx and dx ~= 0 and dy == 0 then
        local target = col + sign(dx)
        -- (a category with no sub-categories: straight across the empty
        -- middle column to its items, and back)
        if target == 2 and pile_count(2) == 0 then target = target + sign(dx) end
        target = math.max(1, math.min(3, target))
        if pile_count(target) > 0 then self.pile_col = target end
        return true
    elseif dx or step then
        self:pile_move(cols, col, (dy or 0) + (step or 0))
        return true
    end
    if keys.SELECT then
        if col == 1 or (col == 2 and not pile_sub_is_switch(self.pile_idx and self.pile_idx[2] or 0)) then
            if pile_count(col + 1) > 0 then self.pile_col = col + 1 end
        else
            self:pile_set(cols, col, nil)
        end
    elseif keys.CUSTOM_E then
        click_screen(cols.all[2], cols.all_row)
        pile_group_on()
    elseif keys.CUSTOM_D then
        click_screen(cols.none[2], cols.all_row)
    elseif keys.CUSTOM_A then
        click_screen(cols.all[3], cols.all_row)
        pile_group_on()
    elseif keys.CUSTOM_B then
        click_screen(cols.none[3], cols.all_row)
    elseif keys.CUSTOM_P then
        self:pile_set(cols, col, true)
    elseif keys.CUSTOM_F then
        self:pile_set(cols, col, false)
    elseif keys.CUSTOM_SHIFT_A then
        -- the whole stockpile: everything, or nothing
        click_screen(cols.all[1], cols.all_row)
    elseif keys.CUSTOM_SHIFT_N then
        click_screen(cols.none[1], cols.all_row)
    elseif keys.CUSTOM_U then
        click_screen(cols.organic, cols.all_row)
    elseif keys.CUSTOM_J then
        click_screen(cols.inorganic, cols.all_row)
    else
        -- nothing typed here may reach the map's hotkeys behind the screen
        return letter_key_pressed(keys) or keys._STRING ~= nil
    end
    return true
end

function ClassicKeysOverlay:pile_settings_lines()
    if pile_ui.entering_spec_filter then
        return {
            {{text='type to filter items', pen=COLOR_GREY}},
            {hint('Enter', 'done')},
        }
    end
    local settings = pile_settings()
    local misc = settings and settings.misc
    return {
        {hint('arrows', 'move')},
        {hint('- =', 'up / down')},
        {hint('Enter', 'toggle')},
        {hint('p', 'permit  '), hint('f', 'forbid')},
        {{text='category:', pen=COLOR_GREY}},
        {hint('e', 'enable  '), hint('d', 'disable')},
        {{text='item list:', pen=COLOR_GREY}},
        {hint('a', 'allow all')},
        {hint('b', 'block all')},
        {hint('/', 'filter')},
        {hint('A', 'take everything')},
        {hint('N', 'take nothing')},
        {hint('u', ('plant/animal %s'):format(misc and misc.allow_organic and 'on' or 'off'))},
        {hint('j', ('other %s'):format(misc and misc.allow_inorganic and 'on' or 'off'))},
        {hint('Esc', 'done')},
    }
end

function ClassicKeysOverlay:render_pile_marker()
    local cols = pile_columns()
    if not cols then return end
    self:pile_sync()
    local col = self.pile_col
    local row = self:pile_row(cols, col)
    if row then mark_row(cols.x[col] - 1, row, col == 3 and 40 or 24) end
end

-- stockpile links (the old t take from, g give to, d delete, a anywhere) -----
--
-- The game's links window opens beside the stockpile's panel: two buttons to
-- add a link (give to, 30 columns left of its "Done" button; take from, 26),
-- then the links, 3 rows apart from 6 rows under "Done", each with an X five
-- columns past it. Adding is a click on the other stockpile or workshop on
-- the map, here the cursor and Enter.
local link_ui = mi.stockpile_link

local function link_count(pile)
    local links = pile.links
    return #links.give_to_pile + #links.take_from_pile + #links.give_to_workshop + #links.take_from_workshop
end

local function link_window()
    return find_screen_text('Done', {x1=PANEL_LEFT_BESIDE_NATIVE - 4, x2=gps.dimx - 60, y2=TOP_ROWS + 6})
end

function ClassicKeysOverlay:link_row()
    local pile = df.building.find(link_ui.bld_id)
    local x, y = link_window()
    if not pile or not x then return end
    local count = link_count(pile)
    if count == 0 then return end
    local first = y + 6
    local visible = math.max(1, (gps.dimy - 28 - first) // 3)
    self.link_idx = math.max(0, math.min(self.link_idx or 0, count - 1))
    local scroll = math.max(0, link_ui.scroll_position_link_list)
    if self.link_idx < scroll then
        scroll = self.link_idx
    elseif self.link_idx >= scroll + visible then
        scroll = self.link_idx - visible + 1
    end
    link_ui.scroll_position_link_list = scroll
    return first + 3 * (self.link_idx - scroll), x
end

-- press the links window's "give to" or "take from" button and start aiming
function ClassicKeysOverlay:start_link(give)
    local function press()
        local x, y = link_window()
        if not x then return end
        click_screen(x + (give and -30 or -26), y)
        -- the cursor is borrowed for the aiming and put back afterwards (q
        -- keeps its own on the stockpile); see onRenderFrame
        self.aim = true
        self.aim_origin = self.cursor and copyall(self.cursor)
        if not self.cursor or not guidm.Viewport.get():isVisible(self.cursor) then
            self.cursor = guidm.Viewport.get():getCenter()
        end
    end
    if link_ui.open then
        press()
        return
    end
    -- the window is opened by the second of the two link icons, 18 columns
    -- right of and 3 rows under the panel's "Furniture" label
    local x, y = find_screen_text('Furniture', {y1=TOP_ROWS + 1, x2=PANEL_LEFT_BESIDE_NATIVE - 6})
    if not x then return end
    click_screen(x + 18, y + 3)
    self.link_idx = 0
    -- its buttons can be pressed once it has been drawn
    dfhack.timeout(10, 'frames', function()
        if link_ui.open and not link_ui.adding_new_link then press() end
    end)
end

function ClassicKeysOverlay:on_links_input(keys)
    if link_ui.adding_new_link then
        if keys.LEAVESCREEN then
            if not click_label('Cancel', {x1=PANEL_LEFT_BESIDE_NATIVE - 4, x2=gps.dimx - 60, y2=TOP_ROWS + 6}) then
                link_ui.adding_new_link = false
            end
            return true
        end
        self.aim = true
        self.cursor = self.cursor or guidm.Viewport.get():getCenter()
        local dx, dy, dz = self:take_move(keys)
        if dx then
            local pos = xyz2pos(self.cursor.x + dx, self.cursor.y + dy, self.cursor.z + dz)
            if dfhack.maps.isValidTilePos(pos) then self.cursor = pos end
            return true
        end
        if keys.SELECT then
            self:click_map_tile(self.cursor)
            if not link_ui.adding_new_link then self.link_idx = 100000 end
            return true
        end
        return letter_key_pressed(keys) or list_step(keys) ~= nil
    end
    if keys.LEAVESCREEN or keys.SELECT then
        if not click_label('Done', {x1=PANEL_LEFT_BESIDE_NATIVE - 4, x2=gps.dimx - 60, y2=TOP_ROWS + 6}) then
            link_ui.open = false
        end
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.link_idx = (self.link_idx or 0) + sign(dy or 0) + (step or 0)
        self:link_row()
        return true
    end
    if keys.CUSTOM_G then
        self:start_link(true)
    elseif keys.CUSTOM_T then
        self:start_link(false)
    elseif keys.CUSTOM_D or keys.CUSTOM_X then
        local row, x = self:link_row()
        if row then click_screen(x + 5, row) end
    else
        return letter_key_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:link_lines()
    if link_ui.adding_new_link then
        return {
            {{text='Put the cursor on the other', pen=COLOR_GREY}},
            {{text='stockpile or workshop', pen=COLOR_GREY}},
            {hint('Enter', 'link it  '), hint('Esc', 'cancel')},
        }
    end
    return {
        {hint('g', 'give to  '), hint('t', 'take from')},
        {hint('- =', 'select  '), hint('d', 'delete link')},
        {hint('Esc', 'done')},
    }
end

function ClassicKeysOverlay:render_link_marker()
    if link_ui.adding_new_link then return end
    local row, x = self:link_row()
    if row then mark_row(x - 25, row, 28) end
end

function ClassicKeysOverlay:on_stockpile_panel_input(keys)
    local pile = mi.stockpile.cur_bld
    if not pile then return false end
    if pile_ui.open then
        return self:on_pile_settings_input(keys)
    elseif link_ui.open then
        return self:on_links_input(keys)
    end

    if self.sp_pending_id == pile.id then
        -- just placed and still without a type: the type keys set it
        local entry = pressed_entry(CLASSIC_STOCKPILES, keys)
        if entry then
            if not entry.custom then self.sp_type = entry end
            self:apply_stockpile_preset(entry, 3)
            return true
        end
        if keys.LEAVESCREEN then return false end
        return letter_key_pressed(keys)
    end

    -- an existing stockpile: the old q-on-a-stockpile keys. Its type keys are
    -- deliberately not active here, since one stray press would replace
    -- settings the player may have customised.
    local area = (pile.x2 - pile.x1 + 1) * (pile.y2 - pile.y1 + 1)
    local function bump(field, delta)
        pile.storage[field] = math.max(0, math.min(area, pile.storage[field] + delta))
    end
    if keys.CUSTOM_SHIFT_E then
        bump('max_barrels', -1)
    elseif keys.CUSTOM_SHIFT_R then
        bump('max_barrels', 1)
    elseif keys.CUSTOM_SHIFT_C then
        bump('max_bins', -1)
    elseif keys.CUSTOM_SHIFT_V then
        bump('max_bins', 1)
    elseif keys.CUSTOM_W then
        bump('max_wheelbarrows', -1)
    elseif keys.CUSTOM_SHIFT_W then
        bump('max_wheelbarrows', 1)
    elseif keys.CUSTOM_S then
        local x, y = find_screen_text('Custom', {y1=TOP_ROWS + 1, x2=PANEL_LEFT_BESIDE_NATIVE - 6})
        if x then
            -- opening the settings of a stockpile that takes nothing makes
            -- the game switch its first category's group on: put it back
            local groups = pile.settings.flags.whole
            click_screen(x - 4, y)
            pile.settings.flags.whole = groups
            self.pile_col, self.pile_idx = 1, {0, 0, 0}
            -- start on the category the game opened on
            for i, mode in ipairs(pile_ui.main_mode) do
                if mode == pile_ui.cur_main_mode then self.pile_idx[1] = i end
            end
        end
    elseif keys.CUSTOM_G then
        self:start_link(true)
    elseif keys.CUSTOM_T then
        self:start_link(false)
    elseif keys.CUSTOM_D then
        -- the links, to delete one
        local x, y = find_screen_text('Furniture', {y1=TOP_ROWS + 1, x2=PANEL_LEFT_BESIDE_NATIVE - 6})
        if x then
            self.link_idx = 0
            click_screen(x + 18, y + 3)
        end
    elseif keys.CUSTOM_A then
        -- take from anywhere, or only from the stockpiles linked to this one
        pile.stockpile_flag.use_links_only = not pile.stockpile_flag.use_links_only
    elseif keys.CUSTOM_X then
        -- remove it, as p then x did. The panel is closed first and the
        -- game's pointers to the pile dropped: a panel left open on a
        -- removed building crashes the game.
        mi.stockpile.cur_bld = nil
        if pile_ui.abd == pile then pile_ui.abd = nil end
        mi.bottom_mode_selected = BOTTOM.NONE
        dfhack.buildings.deconstruct(pile)
        self.target_id = nil
    else
        return false
    end
    return true
end
end -- of the stockpile settings block

-- zones ----------------------------------------------------------------------

function ClassicKeysOverlay:on_zone_list_input(keys)
    if keys.CUSTOM_SHIFT_X then
        local zone = mi.civzone.cur_bld
        if zone then
            -- drop the game's references before the zone goes away
            mi.civzone.cur_bld = nil
            mi.civzone.list:resize(0)
            dfhack.buildings.deconstruct(zone)
            self.target_id = nil
        end
        return true
    end
    -- a zone being looked at (with q, or opened with the mouse or from the
    -- Places list): its own buttons
    if self.mode == 'query' or mi.civzone.cur_bld then
        -- DFHack's own box beside rooms (preserve-rooms) has keys of its own:
        -- S, the role whose holder gets the room, and R, clear a reservation
        if keys.CUSTOM_SHIFT_S or keys.CUSTOM_SHIFT_R then return false end
        if mi.civzone.cur_bld and self:on_zone_detail_input(keys) then return true end
        -- Esc: the game's own closes the panel
        if keys.LEAVESCREEN and self.mode ~= 'query' then return false end
        -- A letter with no use here must not reach the game: its own hotkeys
        -- still fire under the zone's panel (g starts a designation). The
        -- cursor-mode letters go on to change mode as usual.
        if self.mode == 'query' and (keys.CUSTOM_K or keys.CUSTOM_Q or keys.CUSTOM_T or keys.CUSTOM_V) then
            return false
        end
        return letter_key_pressed(keys)
    end

    local entry = pressed_entry(CLASSIC_ZONES, keys)
    if entry then
        mi.civzone.cur_bld = nil
        mi.civzone.list:resize(0)
        mi.civzone.adding_new_type = df.civzone_type[entry.zone]
        mi.bottom_mode_selected = BOTTOM.ZONE_PAINT
        return true
    end
    if keys.LEAVESCREEN then return false end
    return letter_key_pressed(keys)
end

-- unit panel -----------------------------------------------------------------

local function on_unit_page(page)
    return vs.active_sub_tab == page.tab and (not page.sub_field or vs[page.sub_field] == page.sub)
end

-- where the unit panel's two rows of tabs and its row of sub-tabs are drawn
local function unit_tab_bounds(y1, y2)
    return {x1=gps.dimx - SHEET_COLS, x2=gps.dimx - MINIMAP_COLS, y1=y1, y2=y2}
end
local UNIT_TAB_ROWS = {11, 16}
local UNIT_SUBTAB_ROWS = {17, 19}

-- Show a page of the unit panel. Tabs are switched by clicking their labels,
-- not by setting the tab fields: the game only fills in most tabs (skills,
-- health, relations, personality...) when it handles the click itself. A
-- sub-tab's label is only on screen once its tab has been drawn, so that
-- click follows a frame later.
function ClassicKeysOverlay:goto_unit_page(page, tries_left)
    tries_left = tries_left or 3
    if not viewed_unit() then return end
    local function retry()
        if tries_left > 0 then
            dfhack.timeout(1, 'frames', function() self:goto_unit_page(page, tries_left - 1) end)
        end
    end

    if vs.active_sub_tab ~= page.tab then
        if not click_label(page.label, unit_tab_bounds(UNIT_TAB_ROWS[1], UNIT_TAB_ROWS[2])) then
            return retry()
        end
        vs.unit_overview_customizing = false
        if page.sub_label then retry() end
        return
    end
    if page.sub_label and vs[page.sub_field] ~= page.sub then
        if not click_label(page.sub_label, unit_tab_bounds(UNIT_SUBTAB_ROWS[1], UNIT_SUBTAB_ROWS[2])) then
            return retry()
        end
    end
end

local function unit_scroll_field()
    if vs.active_sub_tab == UNIT_PAGE.military_kills.tab then
        return vs.unit_military_active_tab == UNIT_PAGE.military_kills.sub
            and 'scroll_position_unit_military_kills' or 'scroll_position_unit_military_assigned'
    end
    return UNIT_SCROLL_FIELDS[vs.active_sub_tab]
end

-- the text currently drawn in the body of a unit / building panel
local function sheet_body_text()
    local chars = {}
    for y = UNIT_SUBTAB_ROWS[2] + 1, gps.dimy - BOTTOM_ROWS - 2 do
        for x = gps.dimx - SHEET_COLS + 2, gps.dimx - MINIMAP_COLS - 4 do
            local tile = dfhack.screen.readTile(x, y)
            chars[#chars + 1] = string.char(tile and tile.ch or 0)
        end
    end
    return table.concat(chars)
end

local UNIT_SCROLL_STEP = 3

-- The game draws a list pinned at its end however far past it the scroll
-- position goes, but leaves the number as it is, so scrolling back would
-- first have to undo the overshoot. Scroll down, then let the next frame
-- (see check_scroll) put the number back if nothing on screen moved.
function ClassicKeysOverlay:scroll_unit_panel(direction)
    local field = unit_scroll_field()
    if not field then return end
    if direction > 0 then
        self.scroll_check = {field=field, before=vs[field], text=sheet_body_text(), unit_id=vs.active_id}
        vs[field] = vs[field] + UNIT_SCROLL_STEP
    else
        self.scroll_check = nil
        vs[field] = math.max(0, vs[field] - UNIT_SCROLL_STEP)
    end
end

function ClassicKeysOverlay:check_scroll()
    local check = self.scroll_check
    if not check then return end
    self.scroll_check = nil
    if vs.open and vs.active_id == check.unit_id and vs[check.field] > check.before
        and sheet_body_text() == check.text
    then
        vs[check.field] = check.before
    end
end

-- v again: the next creature near the cursor, nearest first
function ClassicKeysOverlay:next_unit()
    local near = {}
    for _, unit in ipairs(df.global.world.units.active) do
        local ux, uy, uz = dfhack.units.getPosition(unit)
        if uz == self.cursor.z and unit_is_visible(unit) then
            local d2 = (ux - self.cursor.x) ^ 2 + (uy - self.cursor.y) ^ 2
            if d2 <= SNAP_RANGE ^ 2 then
                near[#near + 1] = {unit=unit, d2=d2}
            end
        end
    end
    if #near < 2 then return end
    table.sort(near, function(a, b)
        if a.d2 ~= b.d2 then return a.d2 < b.d2 end
        return a.unit.id < b.unit.id
    end)
    local pick = near[1]
    for i, entry in ipairs(near) do
        if entry.unit.id == vs.active_id then
            pick = near[i % #near + 1]
            break
        end
    end
    self:show_unit(pick.unit)
end

-- open a creature's panel on the page the player was last looking at
function ClassicKeysOverlay:show_unit(unit)
    open_unit_sheet(unit)
    self.target_id = unit.id
    local page = self.unit_page
    if page and page ~= UNIT_PAGE.overview then
        dfhack.timeout(1, 'frames', function()
            if vs.active_id == unit.id then self:goto_unit_page(page) end
        end)
    end
end

local function can_slaughter(unit)
    return dfhack.units.isTame(unit) and dfhack.units.isFortControlled(unit)
        and not dfhack.units.isCitizen(unit) and not dfhack.units.isPet(unit)
end

-- A creature's Labor page: four lists (work details, workshops, locations,
-- work animals), rows 3 apart, each row ending in a tick box 51 columns past
-- the "Work details" tab label. - = select a row and Enter ticks it. The
-- arrows are left alone: with v they move to the next creature.
function ClassicKeysOverlay:unit_labor_list()
    local x, y = find_screen_text('Work details', {x1=gps.dimx - SHEET_COLS - 2, y1=TOP_ROWS + 6})
    if not x then return end
    -- every list starts 6 rows under the tabs (the work details have a line
    -- about "only assigned tasks" in between)
    local first = y + 6
    return {x=x + 2, first=first, click_x=x + 51, top_x=x, tabs_row=y,
            visible=math.max(1, (gps.dimy - 6 - first) // 3)}
end

function ClassicKeysOverlay:on_unit_labor_input(keys)
    local list = self:unit_labor_list()
    if not list then return false end
    local has_text = ClassicKeysOverlay.info_helpers.row_has_text
    local step = list_step(keys)
    if step then
        local idx = math.max(0, math.min(self.ul_idx or 0, list.visible - 1)) + step
        if idx < 0 then
            vs.scroll_position_unit_labor = math.max(0, vs.scroll_position_unit_labor - 1)
            idx = 0
        elseif idx >= list.visible or not has_text(list.x, list.first + 3 * idx) then
            if idx >= list.visible and has_text(list.x, list.first + 3 * (list.visible - 1)) then
                vs.scroll_position_unit_labor = vs.scroll_position_unit_labor + 1
            end
            idx = idx - 1
        end
        self.ul_idx = math.max(0, idx)
        return true
    end
    if keys.SELECT then
        local row = list.first + 3 * (self.ul_idx or 0)
        if has_text(list.x, row) then click_screen(list.click_x, row) end
        return true
    elseif keys.CUSTOM_T and vs.unit_labor_active_tab == 0 then
        -- "will only do assigned tasks", the button above the work details
        click_screen(list.top_x + 1, list.tabs_row + 3)
        return true
    end
    return false
end

function ClassicKeysOverlay:render_unit_labor_marker()
    local list = self:unit_labor_list()
    if not list then return end
    local helpers = ClassicKeysOverlay.info_helpers
    local idx = math.max(0, math.min(self.ul_idx or 0, list.visible - 1))
    while idx > 0 and not helpers.row_has_text(list.x, list.first + 3 * idx) do idx = idx - 1 end
    self.ul_idx = idx
    local start = helpers.row_text_start(list.first + 3 * idx, list.x, list.x + 30)
    if start then mark_row(start - 1, list.first + 3 * idx, 40) end
end

-- where the expel panel's first choice is drawn
function ClassicKeysOverlay:expel_rows()
    return find_screen_text('Expel', {x1=gps.dimx - SHEET_COLS, x2=gps.dimx - MINIMAP_COLS, y1=TOP_ROWS + 6})
end

-- The panel's second step lists who will leave, with "Expel" and "Cancel"
-- under them: where those two are, or nil while a destination is being chosen.
function ClassicKeysOverlay:expel_confirm()
    local sheet = {x1=gps.dimx - SHEET_COLS, x2=gps.dimx - MINIMAP_COLS, y1=TOP_ROWS + 6}
    local cancel_x, y = find_screen_text('Cancel', sheet)
    if not cancel_x then return end
    sheet.y1, sheet.y2 = y, y
    local expel_x = find_screen_text('Expel', sheet)
    if expel_x then return expel_x, cancel_x, y end
end

function ClassicKeysOverlay:on_unit_sheet_input(keys, unit)
    -- the old y screen: n nickname, p profession name. Once one of them is
    -- being typed the game takes the keyboard and none of this runs.
    if vs.unit_overview_customizing then
        if keys.LEAVESCREEN or keys.CUSTOM_Y then
            vs.unit_overview_customizing = false
            return true
        elseif keys.CUSTOM_N then
            vs.unit_overview_entering_str = unit.name.nickname
            vs.unit_overview_entering_nickname = true
            return true
        elseif keys.CUSTOM_P then
            vs.unit_overview_entering_str = unit.custom_profession
            vs.unit_overview_entering_profession_nickname = true
            return true
        end
        return letter_key_pressed(keys)
    end
    -- Expelling (E): the game's own panel, which lists where the creature
    -- can be sent ("Expel", then the fort's holdings), 3 rows apart, or says
    -- why it cannot go. - = choose, Enter does it, Esc closes the panel.
    if vs.unit_overview_expelling then
        local count = #vs.unit_overview_expel_dest_stid
        local step = list_step(keys)
        local expel_x, cancel_x, confirm_y = self:expel_confirm()
        if keys.LEAVESCREEN then
            -- in the second step the game's own Cancel, which closes the panel
            if cancel_x then
                click_screen(cancel_x + 2, confirm_y)
            else
                vs.unit_overview_expelling = false
            end
        elseif expel_x then
            -- who will go is listed: Enter again is the "Expel" under them
            if keys.SELECT then click_screen(expel_x + 2, confirm_y) end
        elseif step then
            self.expel_idx = math.max(0, math.min((self.expel_idx or 0) + step, count - 1))
        elseif keys.SELECT and count > 0 then
            local x, y = self:expel_rows()
            if x then click_screen(x + 2, y + 3 * (self.expel_idx or 0)) end
        else
            return letter_key_pressed(keys)
        end
        return true
    end
    if keys.LEAVESCREEN then return false end

    if keys.CUSTOM_SHIFT_E then
        -- the button under the "follow" camera at the sheet's top right
        self.expel_idx = 0
        click_screen(gps.dimx - 41, TOP_ROWS + 5)
        return true
    elseif keys.CUSTOM_SHIFT_S then
        -- squad: a list of the fort's squads to join, in a window of ours
        if dfhack.units.isCitizen(unit) then ClassicKeysOverlay.pick_squad(unit) end
        return true
    end

    if keys.CUSTOM_Y then
        if vs.active_sub_tab ~= UNIT_PAGE.overview.tab then
            self.unit_page = UNIT_PAGE.overview
            self:goto_unit_page(UNIT_PAGE.overview)
        end
        vs.unit_overview_customizing = true
        return true
    end

    -- Tab and Shift+Tab step through the sub-tabs of the tab on show (Health:
    -- status, wounds, treatment...), wrapping at either end
    if keys.CHANGETAB or keys.SEC_CHANGETAB then
        local subs = {}
        for _, page in pairs(UNIT_PAGE) do
            if page.tab == vs.active_sub_tab and page.sub_field then subs[#subs + 1] = page end
        end
        table.sort(subs, function(a, b) return a.sub < b.sub end)
        if #subs > 0 then
            local current, pos = vs[subs[1].sub_field], 1
            for i, page in ipairs(subs) do
                if page.sub == current then pos = i end
            end
            local target = subs[(pos - 1 + (keys.SEC_CHANGETAB and -1 or 1)) % #subs + 1]
            self.unit_page = target
            self:goto_unit_page(target)
        end
        return true
    end

    local entry = pressed_entry(UNIT_KEYS, keys)
    if entry then
        local page = entry.pages[1]
        for i, candidate in ipairs(entry.pages) do
            if on_unit_page(candidate) then
                page = entry.pages[i % #entry.pages + 1]
                break
            end
        end
        self.unit_page = page
        self:goto_unit_page(page)
        return true
    end

    if focus_is('dwarfmode/ViewSheets/UNIT/Labor') and self:on_unit_labor_input(keys) then
        return true
    end

    local ch = keys._STRING
    if keys.SECONDSCROLL_DOWN or ch == string.byte('+') or ch == string.byte('=') then
        self:scroll_unit_panel(1)
        return true
    elseif keys.SECONDSCROLL_UP or ch == string.byte('-') then
        self:scroll_unit_panel(-1)
        return true
    end

    if keys.CUSTOM_V then
        self:next_unit()
        return true
    elseif keys.CUSTOM_F then
        df.global.plotinfo.follow_unit = unit.id
        return true
    elseif keys.CUSTOM_S then
        if can_slaughter(unit) then
            unit.flags2.slaughter = not unit.flags2.slaughter
        end
        return true
    elseif keys.CUSTOM_X then
        if dfhack.units.isGeldable(unit) and can_slaughter(unit) then
            unit.flags3.marked_for_gelding = not unit.flags3.marked_for_gelding
        end
        return true
    end
    return false
end

function ClassicKeysOverlay:unit_lines(unit)
    local lines = {{{text=clip(dfhack.units.getReadableName(unit), PANEL_TEXT_W), pen=COLOR_LIGHTCYAN}}}
    if vs.unit_overview_customizing then
        lines[#lines + 1] = {hint('n', 'nickname  '), hint('p', 'profession name')}
        lines[#lines + 1] = {hint('Esc', 'back')}
        return lines
    end
    lines[#lines + 1] = {hint('g', 'general/skills  '), hint('i', 'inventory')}
    lines[#lines + 1] = {hint('p', 'labor  '), hint('w', 'wounds  '), hint('h', 'health  '), hint('d', 'describe')}
    lines[#lines + 1] = {hint('z', 'thoughts/personality  '), hint('r', 'relations')}
    lines[#lines + 1] = {hint('k', 'kills/military  '), hint('R', 'rooms')}
    lines[#lines + 1] = {hint('v', 'next  '), hint('f', 'follow  '), hint('y', 'name  '), hint('+-', 'scroll')}
    lines[#lines + 1] = {hint('Tab', 'next sub-tab (Shift+Tab back)')}
    lines[#lines + 1] = {hint('S', 'squad  '), hint('E', 'expel / send away')}
    if can_slaughter(unit) then
        local line = {hint('s', 'slaughter: ' .. (unit.flags2.slaughter and 'YES' or 'no') .. '  ')}
        if dfhack.units.isGeldable(unit) then
            line[#line + 1] = hint('x', 'geld: ' .. (unit.flags3.marked_for_gelding and 'YES' or 'no'))
        end
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = {{text='same key again: its next page', pen=COLOR_GREY}}
    lines[#lines + 1] = {hint('Esc', 'done')}
    return lines
end

-- squads (the old s menu) ------------------------------------------------------

local sq = mi.squads

-- rows from the top of the unit list's window to its first entry, which is
-- "Remove assignment"; the dwarves follow
local UNIT_SELECTOR_FIRST_ROW = 4

-- squads get the letters a-j, as they did; the other letters are orders
local SQUAD_LETTERS = 'abcdefghij'

local function squads_open()
    return sq.open
end

local function any_squad_selected()
    for _, selected in ipairs(sq.squad_selected) do
        if selected then return true end
    end
    return false
end

-- what an order would go to: the ticked squads, or inside one squad's
-- positions (where the game orders soldiers singly) the ticked soldiers
local function any_selection()
    if sq.viewing_squad_index ~= -1 then return #sq.squad_hfid_selected > 0 end
    return any_squad_selected()
end

local function squad_panel_bounds()
    return {x1=gps.dimx - MINIMAP_COLS - 4, y1=TOP_ROWS + 1}
end

-- The six order buttons are icons with no text: a row 3 above the "Equip"
-- label, 4 columns apart, starting 1 column in from it. In order: kill, move,
-- patrol, defend burrows, train, cancel orders.
local ORDER_ICON = {patrol=2, burrow=3, train=4, cancel=5}

local function click_order_icon(index)
    local x, y = find_screen_text('Equip', squad_panel_bounds())
    if not x then return false end
    click_screen(x + 1 + 4 * index, y - 3)
    return true
end

-- who a squad may be sent to kill from the keyboard: the game's own picker
-- refuses the fort's own people and animals, and so does this
local function can_be_kill_target(unit)
    return unit_is_visible(unit) and not dfhack.units.isFortControlled(unit)
        and not dfhack.units.isCitizen(unit)
end

local function is_dangerous(unit)
    local ok, danger = pcall(dfhack.units.isDanger, unit)
    return ok and danger
end

-- every creature on the map a squad could be sent after, the dangerous ones
-- first and then nearest to `origin` first
local function kill_candidates(origin)
    local found = {}
    for _, unit in ipairs(df.global.world.units.active) do
        if can_be_kill_target(unit) then
            local x, y, z = dfhack.units.getPosition(unit)
            found[#found + 1] = {
                unit=unit, danger=is_dangerous(unit), dz=z - origin.z,
                dist=math.max(math.abs(x - origin.x), math.abs(y - origin.y)),
            }
        end
    end
    table.sort(found, function(a, b)
        if a.danger ~= b.danger then return a.danger end
        local da, db = a.dist + 20 * math.abs(a.dz), b.dist + 20 * math.abs(b.dz)
        if da ~= db then return da < db end
        return a.unit.id < b.unit.id
    end)
    return found
end

-- The old l: choose kill targets from a list. x marks creatures; Enter sends
-- the squads after everything marked, or after the highlighted one if
-- nothing is.
TargetPicker = defclass(TargetPicker, gui.ZScreen)
TargetPicker.ATTRS{
    focus_path='classic-controls/kill-list',
    pass_movement_keys=false,
    origin=DEFAULT_NIL,
    on_attack=DEFAULT_NIL,
}

function TargetPicker:init()
    self.marked = {}
    self:addviews{
        widgets.Window{
            frame={l=3, t=5, w=66, h=40},
            frame_title='Kill: choose targets',
            resizable=true,
            subviews={
                widgets.List{
                    view_id='list',
                    frame={t=0, l=0, r=0, b=2},
                    on_submit=self:callback('attack'),
                },
                widgets.Label{
                    frame={b=0, l=0},
                    text={
                        {text='- =', pen=COLOR_LIGHTGREEN}, ': select  ',
                        {text='x', pen=COLOR_LIGHTGREEN}, ': mark  ',
                        {text='Enter', pen=COLOR_LIGHTGREEN}, ': attack  ',
                        {text='Esc', pen=COLOR_LIGHTGREEN}, ': back',
                    },
                },
            },
        },
    }
    local list = self.subviews.list
    local choices = {}
    for _, candidate in ipairs(kill_candidates(self.origin)) do
        local unit = candidate.unit
        local row = #choices + 1
        local function selected() return list:getSelected() == row end
        local where = ('%d away'):format(candidate.dist)
        if candidate.dz ~= 0 then
            where = where .. (', %d %s'):format(math.abs(candidate.dz), candidate.dz > 0 and 'up' or 'down')
        end
        choices[#choices + 1] = {
            unit_id=unit.id,
            text={
                {text=function() return selected() and string.char(16) or ' ' end, pen=COLOR_YELLOW},
                {text=function() return self.marked[unit.id] and '[x] ' or '[ ] ' end,
                 pen=function() return self.marked[unit.id] and COLOR_YELLOW or COLOR_GREY end},
                {text=clip(dfhack.units.getReadableName(unit), 40), pen=function()
                    return selected() and COLOR_YELLOW or (candidate.danger and COLOR_LIGHTRED or COLOR_WHITE)
                end},
                {text='  ' .. where, pen=COLOR_GREY},
            },
        }
    end
    list:setChoices(choices, 1)
end

function TargetPicker:attack()
    local ids = {}
    for _, choice in ipairs(self.subviews.list.choices) do
        if self.marked[choice.unit_id] then ids[#ids + 1] = choice.unit_id end
    end
    if #ids == 0 then
        local _, choice = self.subviews.list:getSelected()
        if choice then ids[1] = choice.unit_id end
    end
    self:dismiss()
    if #ids > 0 and self.on_attack then self.on_attack(ids) end
end

function TargetPicker:onInput(keys)
    if keys.LEAVESCREEN or keys._MOUSE_R then
        self:dismiss()
        return true
    end
    local list = self.subviews.list
    local step = list_step(keys)
    if step then
        local count = #list.choices
        if count > 0 then
            list:setSelected(((list:getSelected() or 1) - 1 + step) % count + 1)
        end
        return true
    end
    if keys.CUSTOM_X then
        local _, choice = list:getSelected()
        if choice then self.marked[choice.unit_id] = not self.marked[choice.unit_id] or nil end
        return true
    end
    return TargetPicker.super.onInput(self, keys)
end

function ClassicKeysOverlay:start_order(kind)
    if not any_selection() then return end
    sq.giving_move_order = kind == 'move'
    sq.giving_kill_order = kind == 'kill'
    sq.kill_unid:resize(0)
    self.order = kind
    self.order_rect, self.order_anchor, self.order_note = nil, nil, nil
    if not self.cursor or not guidm.Viewport.get():isVisible(self.cursor) then
        self.cursor = guidm.Viewport.get():getCenter()
    end
end

-- Send the ticked squads after these creatures. Targets are a plain list of
-- unit ids on the game's side; confirming is a button.
function ClassicKeysOverlay:issue_kill(unit_ids)
    sq.kill_unid:resize(0)
    for _, id in ipairs(unit_ids) do
        sq.kill_unid:insert('#', id)
    end
    if #unit_ids == 0 or not click_label('Confirm', squad_panel_bounds()) then
        sq.kill_unid:resize(0)
        return false
    end
    sq.kill_unid:resize(0)
    self.order, self.order_rect, self.order_anchor, self.order_note = nil, nil, nil, nil
    return true
end

function ClassicKeysOverlay:cancel_order()
    self.order = nil
    self.order_rect, self.order_anchor, self.order_note = nil, nil, nil
    if sq.giving_move_order or sq.giving_kill_order then
        if not click_label('Cancel', squad_panel_bounds()) then
            sq.giving_move_order = false
            sq.giving_kill_order = false
        end
    end
    sq.kill_unid:resize(0)
end

-- the creatures a squad could attack inside the box with these two corners
local function kill_targets_in_box(a, b)
    local ids = {}
    local units = dfhack.units.getUnitsInBox(
        math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z),
        math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
    for _, unit in ipairs(units) do
        if can_be_kill_target(unit) then ids[#ids + 1] = unit.id end
    end
    return ids
end

function ClassicKeysOverlay:on_order_input(keys)
    if keys.LEAVESCREEN then
        -- one step back at a time: the first corner, then rectangle mode,
        -- then the order itself
        if self.order_anchor then
            self.order_anchor = nil
        elseif self.order_rect then
            self.order_rect = nil
        else
            self:cancel_order()
        end
        self.order_note = nil
        return true
    end
    local dx, dy, dz = self:take_move(keys)
    if dx then
        local pos = xyz2pos(self.cursor.x + dx, self.cursor.y + dy, self.cursor.z + dz)
        if dfhack.maps.isValidTilePos(pos) then self.cursor = pos end
        return true
    end
    if keys.SELECT then
        self.order_note = nil
        if self.order == 'move' then
            -- the game takes the destination as a click on the map
            self:click_map_tile(self.cursor)
            self.order = nil
        elseif self.order_rect then
            if not self.order_anchor then
                self.order_anchor = copyall(self.cursor)
            else
                local ids = kill_targets_in_box(self.order_anchor, self.cursor)
                self.order_anchor = nil
                if #ids == 0 then
                    self.order_note = 'nothing to attack in that area'
                else
                    self:issue_kill(ids)
                end
            end
        else
            local target = units_at(self.cursor)[1] or nearest_unit(self.cursor, 2)
            if target and can_be_kill_target(target) then
                self:issue_kill({target.id})
            else
                self.order_note = 'no creature to attack there'
            end
        end
        return true
    end
    if self.order == 'kill' then
        if keys.CUSTOM_R then
            self.order_rect = not self.order_rect or nil
            self.order_anchor, self.order_note = nil, nil
            return true
        elseif keys.CUSTOM_L then
            self.order_rect, self.order_anchor, self.order_note = nil, nil, nil
            TargetPicker{
                origin=copyall(self.cursor),
                on_attack=function(ids) self:issue_kill(ids) end,
            }:show()
            return true
        end
    end
    return list_step(keys) ~= nil or letter_key_pressed(keys)
end

-- the unit standing in a squad's first filled position
local function squad_leader(squad)
    for _, position in ipairs(squad.positions) do
        local hf = df.historical_figure.find(position.occupant)
        local unit = hf and df.unit.find(hf.unit_id)
        if unit then return unit end
    end
end

-- squad schedules ---------------------------------------------------------------
--
-- The schedule screen is a grid: a column per routine, a row per ticked
-- squad, each cell holding that squad's orders under that routine. A squad
-- follows one routine at a time (squad.cur_routine_idx).

local sched = mi.squad_schedule
local ROUTINES_PER_PAGE = 4

local function schedule_open()
    return sq.open and sched.open
end

local function routines()
    return df.global.plotinfo.alerts.routines
end

-- Where the focused cell is on screen, all found from text: the grid's
-- "Add/edit routines" button gives the header row, the routine's name its
-- column, the squad's name its row. Buttons sit 3 rows under the cell text.
function ClassicKeysOverlay:schedule_cell()
    local focus = self.sched_focus or self:sync_schedule_focus()
    local routine = routines()[focus.col]
    local squad_id = sched.squad_id[focus.row]
    if not routine or not squad_id then return end
    local head_x, head_y = find_screen_text('Add/edit routines')
    if not head_x then return end
    local col_x = find_screen_text(routine.name, {x1=head_x + 20, y1=head_y, y2=head_y})
    local name = dfhack.military.getSquadName(squad_id)
    local _, row_y = find_screen_text(name:sub(1, 12), {x1=head_x, x2=head_x + 12, y1=head_y + 1})
    if not col_x or not row_y then return end
    return {x=col_x, y=row_y, head_x=head_x}
end

function ClassicKeysOverlay:sync_schedule_focus()
    local focus = self.sched_focus or {col=0, row=0}
    focus.col = math.max(0, math.min(focus.col, #routines() - 1))
    focus.row = math.max(0, math.min(focus.row, #sched.squad_id - 1))
    self.sched_focus = focus
    -- the grid shows a few routines at a time; turn to the focused one's page
    sched.routine_page = focus.col // ROUTINES_PER_PAGE
    return focus
end

-- squad equipment (E in the squads panel) --------------------------------------
--
-- A row per soldier of the ticked squads, and buttons along the top. The
-- game's Esc closes the whole squads panel from here too, so stepping back is
-- done by clearing the flag of whichever screen is in front.

local equip = mi.squad_equipment

local function equipment_open()
    return sq.open and equip.open
end

local function equipment_sub_screen()
    return mi.assign_uniform.open or equip.customizing_equipment
        or equip.setting_ammo or equip.setting_supplies
end

-- defined further down, used by the ammunition keys above it
local equipment_pick_list

-- soldiers are listed 4 rows under the "Assign uniform" button, 3 rows each
function ClassicKeysOverlay:equipment_row()
    local x, y = find_screen_text('Assign uniform')
    if not x then return end
    return {x=x, y=y + 4 + 3 * (self.equip_idx or 0)}
end

-- the n-th (0-based) row carrying a piece of text, for lists of identical buttons
local function find_nth_text(text, n, bounds)
    local search = copyall(bounds or {})
    for i = 0, n do
        local x, y = find_screen_text(text, search)
        if not x then return end
        if i == n then return x, y end
        search.y1 = y + 1
    end
end

local function typed(keys, char)
    return keys._STRING == string.byte(char)
end

-- supplies: the old u screen. - + water, / * food, as they were.
local WATER_NAMES = {[0]='no water', 'water', 'drink'}

function ClassicKeysOverlay:supplies_squad()
    local ids = equip.setting_supplies_squad_id
    self.supply_idx = math.max(0, math.min(self.supply_idx or 0, #ids - 1))
    return df.squad.find(ids[self.supply_idx] or -1)
end

function ClassicKeysOverlay:on_supplies_input(keys)
    local squad = self:supplies_squad()
    if not squad then return false end
    local dx, dy = self:take_move(keys)
    if dx then
        self.supply_idx = self.supply_idx + sign(dy)
        self:supplies_squad()
        return true
    end
    local supplies = squad.supplies
    local step = list_step(keys)
    if step then
        supplies.carry_water = math.max(0, math.min(2, supplies.carry_water + step))
    elseif typed(keys, '/') then
        supplies.carry_food = math.max(0, supplies.carry_food - 1)
    elseif typed(keys, '*') then
        supplies.carry_food = math.min(3, supplies.carry_food + 1)
    elseif keys.SELECT then
        click_label('Confirm', {y2=gps.dimy // 2})
    else
        return letter_key_pressed(keys)
    end
    return true
end

-- ammunition: the old f screen. - + amount, / * amount in big steps,
-- C combat, T training, c add, d delete, M material.
local AMMO_STEP, AMMO_BIG_STEP = 5, 25

function ClassicKeysOverlay:ammo_spec()
    local squad = df.squad.find(equip.setting_ammo_squad_id)
    if not squad then return end
    local specs = squad.ammo.ammunition
    self.ammo_idx = math.max(0, math.min(self.ammo_idx or 0, #specs - 1))
    return specs[self.ammo_idx], squad
end

-- Press a button on the selected ammunition's own row. Each ammunition is
-- followed by the items assigned to it, so a later one is usually off screen
-- and its row cannot be worked out from its number. With the list at its
-- top, the rows on screen are the first few ammunitions in order; scrolled
-- to its end, they are the last few. So the list is put at whichever end
-- shows the wanted row, and the press follows once that has been drawn.
function ClassicKeysOverlay:click_ammo_button(label, dx, retried)
    local _, squad = self:ammo_spec()
    if not squad then return end
    local idx, count = self.ammo_idx, #squad.ammo.ammunition
    -- up to, but not into, the squads panel on the right
    local rows, search = {}, {y2=gps.dimy - 6, x2=gps.dimx - 30}
    while true do
        local x, y = find_screen_text(label, search)
        if not x then break end
        rows[#rows + 1] = {x=x, y=y}
        search.y1 = y + 1
    end
    local at_top = equip.setting_ammo_scroll_position == 0
    local row
    if at_top then
        row = rows[idx + 1]
    else
        row = rows[#rows - (count - 1 - idx)]
    end
    if row then
        click_screen(row.x + dx, row.y)
    elseif not retried then
        equip.setting_ammo_scroll_position = at_top and 100000 or 0
        -- long enough for the scrolled list to be drawn: these frames are
        -- game-loop steps, several of which pass between redraws
        dfhack.timeout(10, 'frames', function()
            if equip.setting_ammo then self:click_ammo_button(label, dx, true) end
        end)
    end
end

function ClassicKeysOverlay:on_ammo_input(keys)
    -- choosing a new ammunition type or a material: the game's own lists.
    -- Letters are kept from the game there: its map-level hotkeys still fire
    -- under these lists and would close the screen.
    if equip.setting_ammo_new_type or equip.setting_ammo_mat then
        return self:on_pick_list_input(keys, equipment_pick_list())
    end
    local spec, squad = self:ammo_spec()
    if not squad then return false end
    local dx, dy = self:take_move(keys)
    if dx then
        self.ammo_idx = self.ammo_idx + sign(dy)
        self:ammo_spec()
        return true
    end
    local step = list_step(keys)
    local change = step and step * AMMO_STEP
        or typed(keys, '/') and -AMMO_BIG_STEP or typed(keys, '*') and AMMO_BIG_STEP
    local bounds = {y2=gps.dimy - 6, x2=gps.dimx - MINIMAP_COLS - 6}
    if change then
        if spec then
            spec.amount = math.max(0, spec.amount + change)
            -- have the game redo who carries what
            squad.ammo.update.ammo = true
        end
    elseif keys.CUSTOM_SHIFT_C then
        if spec then spec.flags.use_combat = not spec.flags.use_combat end
    elseif keys.CUSTOM_SHIFT_T then
        if spec then spec.flags.use_training = not spec.flags.use_training end
    elseif keys.CUSTOM_C then
        click_label('Add ammunition', bounds)
    elseif keys.CUSTOM_D then
        if spec then self:click_ammo_button('Delete', 2) end
    elseif keys.CUSTOM_SHIFT_M then
        if spec then
            self.pick_idx = 0
            self:click_ammo_button('Mat', 1)
        end
    elseif keys.SELECT then
        click_label('Confirm', {y2=gps.dimy // 2})
    else
        return letter_key_pressed(keys)
    end
    return true
end

-- Lists inside the equipment screens (what to add, which material, which
-- colour...) all share one layout: rows 3 apart starting on the row the
-- soldier list starts on, scrolled an entry at a time. `pick` describes the
-- one in front: how many entries and which field scrolls it.
local EQUIP_ROW_H = 3

-- A heading of each equipment screen, and how far right of its first letter
-- a click lands safely inside that screen's rows. The uniform picker comes
-- first: it opens beside the soldier list, whose own heading stays on screen.
local EQUIP_HEADINGS = {
    {'Choose a uniform', 9},
    {'Adding uniform', 13},
    {'Select ', 13},
    {'Assign uniform', 11},
    {'Confirm', -20},
}

function ClassicKeysOverlay:equipment_list_top()
    -- the ammunition type and material lists have no heading to find and sit
    -- where the soldier list does; the place last seen may be the uniform
    -- picker's, which is elsewhere
    if equip.setting_ammo_new_type or equip.setting_ammo_mat then
        return gps.dimx // 3 - 13, 24
    end
    for _, heading in ipairs(EQUIP_HEADINGS) do
        local x, y = find_screen_text(heading[1], {x2=gps.dimx // 2 + 10, y2=gps.dimy // 2})
        if x then
            self.equip_list_x, self.equip_list_top = x + heading[2] - 11, y + 4
            break
        end
    end
    -- some of the lists (ammunition types) have no heading to find; they sit
    -- where the others do, so fall back to the last place seen, or to where
    -- the equipment screens start on every layout tried
    return self.equip_list_x or (gps.dimx // 3 - 9), self.equip_list_top or 24
end

function equipment_pick_list()
    if mi.assign_uniform.open then
        -- every uniform the fort has, then "No uniform"
        return {count=#df.global.plotinfo.main.fortress_entity.uniforms + 1,
                owner=mi.assign_uniform, scroll='scroll_position'}
    elseif equip.setting_ammo_new_type then
        return {count=#equip.am_cand_type, owner=equip, scroll='setting_ammo_scroll_position_am'}
    elseif equip.setting_ammo_mat then
        return {count=#equip.am_cand_civ_mat, owner=equip, scroll='setting_ammo_scroll_position_am'}
    elseif not equip.customizing_equipment then
        return nil
    elseif equip.cs_adding_specific_item then
        return {count=#equip.cs_add_spec_id, owner=equip, scroll='scroll_position_cssub'}
    elseif equip.cs_adding_new_entry_category ~= -1 then
        return {count=#equip.cs_add_list_type, owner=equip, scroll='scroll_position_cssub'}
    elseif equip.cs_setting_material then
        return {count=#equip.cs_setting_material_mat, owner=equip, scroll='scroll_position_cssub'}
    elseif equip.cs_setting_color_pattern then
        return {count=#equip.cs_setting_color_pattern_index, owner=equip, scroll='scroll_position_cssub'}
    end
end

-- keep a list's selection on screen; returns the screen row it is on
function ClassicKeysOverlay:equipment_list_row(idx, owner, scroll_field)
    local x, top = self:equipment_list_top()
    if not top then return end
    local visible = math.max(1, (gps.dimy - 8 - top) // EQUIP_ROW_H)
    local scroll = owner[scroll_field]
    if idx < scroll then
        scroll = idx
    elseif idx >= scroll + visible then
        scroll = idx - visible + 1
    end
    owner[scroll_field] = math.max(0, scroll)
    return top + EQUIP_ROW_H * (idx - owner[scroll_field]), x
end

function ClassicKeysOverlay:on_pick_list_input(keys, pick)
    self.pick_idx = math.max(0, math.min(self.pick_idx or 0, pick.count - 1))
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        -- Shift+arrow moves ten: the material lists run to a thousand entries
        self.pick_idx = math.max(0, math.min(self.pick_idx + (dy or 0) + (step or 0), pick.count - 1))
        self:equipment_list_row(self.pick_idx, pick.owner, pick.scroll)
        return true
    end
    if keys.SELECT then
        local row, x = self:equipment_list_row(self.pick_idx, pick.owner, pick.scroll)
        if row and pick.count > 0 then
            click_screen(x + 11, row)
            self.pick_idx = 0
        end
        return true
    end
    return letter_key_pressed(keys)
end

-- A soldier's equipment (Enter on the soldier list; also the uniform editor).
-- The old keys: A H L G B S W add armour, helm, legwear, gloves, boots,
-- shield, weapon; M material and C colour of the selected piece; r uniform
-- over or instead of clothing; m exact matches.
local NEW_PIECE_KEYS = {
    CUSTOM_SHIFT_A='New bodywear', CUSTOM_SHIFT_H='New headwear', CUSTOM_SHIFT_L='New legwear',
    CUSTOM_SHIFT_G='New handwear', CUSTOM_SHIFT_B='New footwear', CUSTOM_SHIFT_S='New shield',
    CUSTOM_SHIFT_W='New weapon',
}

function ClassicKeysOverlay:on_details_input(keys)
    local pick = equipment_pick_list()
    if pick then return self:on_pick_list_input(keys, pick) end

    local last = #equip.cs_cat - 1
    self.detail_idx = math.max(0, math.min(self.detail_idx or 0, last))
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.detail_idx = math.max(0, math.min(self.detail_idx + sign(dy or 0) + (step or 0), last))
        self:equipment_list_row(self.detail_idx, equip, 'scroll_position_cs')
        return true
    end

    local row = self:equipment_list_row(self.detail_idx, equip, 'scroll_position_cs')
    for code, label in pairs(NEW_PIECE_KEYS) do
        if keys[code] then
            self.pick_idx = 0
            click_label(label)
            return true
        end
    end
    if keys.CUSTOM_X then
        -- the bin at the end of the selected piece's row, 9 columns past "Color"
        local x = row and last >= 0 and find_screen_text('Color', {y1=row, y2=row})
        if x then click_screen(x + 9, row) end
        return true
    end
    if keys.CUSTOM_SHIFT_M or keys.CUSTOM_SHIFT_C then
        -- the selected piece's own Mat / Color button, on its row
        local x = row and last >= 0 and find_screen_text(keys.CUSTOM_SHIFT_M and 'Mat' or 'Color', {y1=row, y2=row})
        if x then
            self.pick_idx = 0
            click_screen(x + 1, row)
        end
    elseif keys.CUSTOM_R then
        click_label('Uniform ', {y1=TOP_ROWS + 14, x1=PANEL_LEFT_BESIDE_NATIVE - 10})
    elseif keys.CUSTOM_M then
        click_label('match', {y1=TOP_ROWS + 14, x1=PANEL_LEFT_BESIDE_NATIVE - 10})
    elseif keys.CUSTOM_SHIFT_N then
        click_label('(enter name here)', {y2=gps.dimy // 2})
    elseif keys.SELECT then
        click_label('Confirm', {y2=gps.dimy // 2})
    else
        return letter_key_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:on_equipment_input(keys)
    -- an amount or a uniform's name is being typed
    if equip.setting_ammo_entering_amount or equip.customizing_squad_entering_uniform_nickname then
        return false
    end
    if keys.LEAVESCREEN then
        if mi.assign_uniform.open then
            mi.assign_uniform.open = false
        elseif equip.customizing_equipment and equip.cs_adding_specific_item then
            equip.cs_adding_specific_item = false
        elseif equip.customizing_equipment and equip.cs_adding_new_entry_category ~= -1 then
            equip.cs_adding_new_entry_category = -1
        elseif equip.customizing_equipment and equip.cs_setting_material then
            equip.cs_setting_material = false
        elseif equip.customizing_equipment and equip.cs_setting_color_pattern then
            equip.cs_setting_color_pattern = false
        elseif equip.customizing_equipment then
            equip.customizing_equipment = false
        elseif equip.setting_ammo_new_type then
            equip.setting_ammo_new_type = false
        elseif equip.setting_ammo_mat then
            equip.setting_ammo_mat = false
        elseif equip.setting_ammo then
            equip.setting_ammo = false
        elseif equip.setting_supplies then
            equip.setting_supplies = false
        else
            equip.open = false
        end
        return true
    end
    if equip.setting_supplies then
        return self:on_supplies_input(keys)
    elseif equip.setting_ammo then
        return self:on_ammo_input(keys)
    end
    if equip.customizing_equipment then
        return self:on_details_input(keys)
    end
    if mi.assign_uniform.open then
        -- d deletes and N renames the highlighted uniform, as on the old
        -- uniforms page. Each row ends in a bin, 26 columns past where a row
        -- is clicked to choose it; DFHack asks before the game deletes. The
        -- game has no way to rename, so the name is set directly.
        local uniforms = df.global.plotinfo.main.fortress_entity.uniforms
        if keys.CUSTOM_D or keys.CUSTOM_SHIFT_N then
            local idx = math.max(0, self.pick_idx or 0)
            local uniform = idx < #uniforms and uniforms[idx]
            if uniform and keys.CUSTOM_D then
                local row, x = self:equipment_list_row(idx, mi.assign_uniform, 'scroll_position')
                if row then click_screen(x + 37, row) end
            elseif uniform then
                local id = uniform.id
                dialogs.showInputPrompt('Uniform name', 'Type the new name, then Enter:', COLOR_WHITE,
                    uniform.name, function(text)
                        for _, candidate in ipairs(uniforms) do
                            if candidate.id == id and #text > 0 then candidate.name = text end
                        end
                    end)
            end
            return true
        end
        return self:on_pick_list_input(keys, equipment_pick_list())
    end
    if equipment_sub_screen() then return letter_key_pressed(keys) end

    local last = #equip.squad_pos - 1
    self.equip_idx = math.max(0, math.min(self.equip_idx or 0, last))
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.equip_idx = math.max(0, math.min(self.equip_idx + sign(dy or 0) + (step or 0), last))
        return true
    end

    if keys.SELECT or keys.CUSTOM_D then
        local row = self:equipment_row()
        local x = row and find_screen_text('Details', {y1=row.y, y2=row.y})
        if x then click_screen(x + 3, row.y) end
    elseif keys.CUSTOM_A then
        click_label('Assign uniform')
    elseif keys.CUSTOM_N then
        click_label('Add uniform')
    elseif keys.CUSTOM_F then
        click_label('Ammo', {y2=gps.dimy // 2})
    elseif keys.CUSTOM_U then
        click_label('Supplies', {y2=gps.dimy // 2})
    elseif keys.CUSTOM_SHIFT_U then
        click_label('Update equipment')
    else
        return letter_key_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:equipment_lines()
    if equip.setting_supplies then
        local squad = self:supplies_squad()
        local lines = {}
        if squad then
            lines[#lines + 1] = {{text=clip(dfhack.military.getSquadName(squad.id), PANEL_TEXT_W), pen=COLOR_LIGHTMAGENTA}}
            lines[#lines + 1] = {{text=('%d food, %s'):format(squad.supplies.carry_food,
                WATER_NAMES[squad.supplies.carry_water] or '?'), pen=COLOR_YELLOW}}
        end
        lines[#lines + 1] = {hint('- +', 'water  '), hint('/ *', 'food  '), hint('up down', 'squad')}
        lines[#lines + 1] = {hint('Enter', 'confirm  '), hint('Esc', 'back')}
        return lines
    elseif equip.setting_ammo and not (equip.setting_ammo_new_type or equip.setting_ammo_mat) then
        local spec = self:ammo_spec()
        local lines = {}
        if spec then
            lines[#lines + 1] = {{text=('ammunition %d: %d wanted%s%s'):format(self.ammo_idx + 1, spec.amount,
                spec.flags.use_combat and ', combat' or '', spec.flags.use_training and ', training' or ''),
                pen=COLOR_YELLOW}}
        else
            lines[#lines + 1] = {{text='no ammunition set', pen=COLOR_GREY}}
        end
        lines[#lines + 1] = {hint('- +', 'amount  '), hint('/ *', 'by 25  '), hint('up down', 'select')}
        lines[#lines + 1] = {hint('C', 'combat  '), hint('T', 'training  '), hint('M', 'material')}
        lines[#lines + 1] = {hint('c', 'add  '), hint('d', 'delete  '), hint('Enter', 'confirm  '), hint('Esc', 'back')}
        return lines
    elseif equipment_pick_list() then
        return {
            {hint('- =', 'select  '), hint('Enter', 'choose  '), hint('Esc', 'back')},
        }
    elseif equip.customizing_equipment then
        return {
            {hint('- =', 'select piece  '), hint('M', 'material  '), hint('C', 'colour  '), hint('x', 'remove')},
            {hint('A', 'armour  '), hint('H', 'helm  '), hint('L', 'legs  '), hint('G', 'gloves')},
            {hint('B', 'boots  '), hint('S', 'shield  '), hint('W', 'weapon')},
            {hint('r', 'over clothing  '), hint('m', 'exact matches  '), hint('N', 'name')},
            {hint('Enter', 'confirm  '), hint('Esc', 'cancel')},
        }
    elseif equipment_sub_screen() then
        return {{hint('Esc', 'back')}}
    end
    return {
        {hint('- =', 'select soldier  '), hint('Enter', 'details')},
        {hint('a', 'assign uniform  '), hint('n', 'add uniform')},
        {hint('f', 'ammunition  '), hint('u', 'supplies')},
        {hint('U', 'update equipment  '), hint('Esc', 'back to squads')},
    }
end

-- the order editor (e on a schedule cell) --------------------------------------

-- the months being edited: one, or all twelve when the routine is edited whole
local function editing_months()
    local squad = df.squad.find(sq.editing_squad_schedule_id)
    local routine = squad and squad.schedule.routine[sq.editing_squad_schedule_routine_index]
    if not routine then return {}, squad end
    if sq.editing_squad_schedule_month >= 0 then
        return {routine.month[sq.editing_squad_schedule_month]}, squad
    end
    local months = {}
    for _, month in ipairs(routine.month) do months[#months + 1] = month end
    return months, squad
end

-- The editor's order rows and buttons have no text of their own, so they are
-- placed from its "Minimum number of" label: orders start 4 rows under it,
-- 3 rows each, their remove buttons 36 columns right; the four add-order
-- buttons (station, patrol, defend burrow, train) run along the panel's
-- last-but-five row, 4 columns apart, starting 6 columns right.
local EDITOR_ADD = {station=0, patrol=1, burrow=2, train=3}

local function order_editor_anchor()
    local x, y = find_screen_text('Minimum number of', {x1=gps.dimx - 60})
    if x then return {x=x, y=y} end
end

local function click_editor_add(index)
    local anchor = order_editor_anchor()
    if anchor then click_screen(anchor.x + 6 + 4 * index, gps.dimy - 6) end
end

function ClassicKeysOverlay:on_order_editor_input(keys)
    -- a station order's destination is being picked on the map
    if sq.giving_move_order then
        if not self.order then
            self.order = 'move'
            self.cursor = self.cursor or guidm.Viewport.get():getCenter()
        end
        return self:on_order_input(keys)
    end
    self.order = nil
    -- a name for this set of orders is being typed: the game takes the keys,
    -- bar the Esc that would also open its options menu
    if sq.entering_cell_nickname then
        if keys.LEAVESCREEN then
            sq.entering_cell_nickname = false
            return true
        end
        return false
    end

    if keys.LEAVESCREEN or keys.SELECT then
        sq.editing_squad_schedule_id = -1
        return true
    end
    if keys.CUSTOM_SHIFT_N then
        -- the quill at the end of the name box, 7 columns before "Done editing"
        local x, y = find_screen_text('Done editing', {x1=gps.dimx - 60})
        if x then click_screen(x - 7, y) end
        return true
    end
    -- Who the next order is for: the whole squad, or the soldiers ticked in
    -- the list (the game keeps their position numbers). The letters are all
    -- taken here, so positions 1 to 10 are the number keys 1 to 9 and 0.
    local order_squad = df.squad.find(sq.editing_squad_schedule_id)
    local ticked = sq.editing_squad_schedule_pos_selected
    for i = 1, order_squad and math.min(10, #order_squad.positions) or 0 do
        if typed(keys, tostring(i % 10)) then
            local found
            for n, position in ipairs(ticked) do
                if position == i - 1 then found = n end
            end
            if found then ticked:erase(found) else ticked:insert('#', i - 1) end
            sq.editing_squad_schedule_whole_squad_selected = #ticked == 0
            return true
        end
    end
    if keys.CUSTOM_W then
        ticked:resize(0)
        sq.editing_squad_schedule_whole_squad_selected = true
        return true
    end

    local months, squad = editing_months()
    local first = months[1]
    if not first or not squad then return false end
    self.editor_idx = math.max(0, math.min(self.editor_idx or 0, #first.orders - 1))

    local dx, dy = self:take_move(keys)
    if dx then
        self.editor_idx = math.max(0, math.min(self.editor_idx + sign(dy), #first.orders - 1))
        return true
    end
    local step = list_step(keys)
    if step then
        -- how many soldiers the next order added will ask for
        sq.editing_squad_schedule_min_follow = math.max(1,
            math.min(#squad.positions, sq.editing_squad_schedule_min_follow + step))
        return true
    end

    if keys.CUSTOM_S then
        local mode = (first.sleep_mode + 1) % 3
        for _, month in ipairs(months) do month.sleep_mode = mode end
    elseif keys.CUSTOM_U then
        local mode = first.uniform_mode == 0 and 1 or 0
        for _, month in ipairs(months) do month.uniform_mode = mode end
    elseif keys.CUSTOM_T then
        click_editor_add(EDITOR_ADD.train)
    elseif keys.CUSTOM_M then
        click_editor_add(EDITOR_ADD.station)
    elseif keys.CUSTOM_P then
        click_editor_add(EDITOR_ADD.patrol)
    elseif keys.CUSTOM_D then
        click_editor_add(EDITOR_ADD.burrow)
    elseif keys.CUSTOM_X then
        local anchor = order_editor_anchor()
        if anchor and #first.orders > 0 then
            click_screen(anchor.x + 36, anchor.y + 4 + 3 * self.editor_idx - sq.scroll_position_orderp)
        end
    else
        return letter_key_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:order_editor_lines()
    if self.order == 'move' then
        return {
            {{text='Station: put the cursor where they should stand', pen=COLOR_GREY}},
            {hint('Enter', 'station there  '), hint('Esc', 'cancel')},
        }
    end
    local months, squad = editing_months()
    local routine = routines()[sq.editing_squad_schedule_routine_index]
    local lines = {}
    if squad and routine then
        lines[#lines + 1] = {{text=clip(('%s: %s'):format(dfhack.military.getSquadName(squad.id), routine.name),
                                        PANEL_TEXT_W), pen=COLOR_LIGHTMAGENTA}}
    end
    lines[#lines + 1] = {hint('t', 'train  '), hint('m', 'station  '), hint('p', 'patrol  '), hint('d', 'defend')}
    lines[#lines + 1] = {hint('- =', ('soldiers for the next order: %d'):format(sq.editing_squad_schedule_min_follow))}
    lines[#lines + 1] = {hint('up down', 'select order  '), hint('x', 'remove it')}
    lines[#lines + 1] = {hint('1-0', 'tick soldiers for it  '), hint('w', 'whole squad')}
    lines[#lines + 1] = {hint('s', 'sleep mode  '), hint('u', 'uniform mode  '), hint('N', 'name')}
    lines[#lines + 1] = {hint('Enter', 'done  '), hint('Esc', 'back')}
    return lines
end

-- the monthly schedule (v on the schedule grid) --------------------------------
--
-- One squad's year: a row per month, the same routine columns as the grid.
-- Rows are 6 screen rows apart and the list scrolls a month at a time
-- (squad_schedule.scroll_position_month).

local MONTHS = {
    'Granite', 'Slate', 'Felsite', 'Hematite', 'Malachite', 'Galena',
    'Limestone', 'Sandstone', 'Timber', 'Moonstone', 'Opal', 'Obsidian',
}
local MONTH_ROW_H = 6

function ClassicKeysOverlay:sync_month_focus()
    local focus = self.month_focus or {col=0, month=0}
    focus.col = math.max(0, math.min(focus.col, #routines() - 1))
    focus.month = math.max(0, math.min(focus.month, #MONTHS - 1))
    self.month_focus = focus
    sched.routine_page = focus.col // ROUTINES_PER_PAGE
    -- scroll so the focused month is among the ones on screen
    local visible = math.max(1, (gps.dimy - 26) // MONTH_ROW_H)
    if focus.month < sched.scroll_position_month then
        sched.scroll_position_month = focus.month
    elseif focus.month >= sched.scroll_position_month + visible then
        sched.scroll_position_month = focus.month - visible + 1
    end
    return focus
end

-- Where the focused month's cell is: the top visible month's name gives the
-- first row, the routine's name (in the header 3 rows above it) the column.
function ClassicKeysOverlay:month_cell()
    local focus = self.month_focus or self:sync_month_focus()
    local routine = routines()[focus.col]
    local top_month = MONTHS[sched.scroll_position_month + 1]
    if not routine or not top_month then return end
    local _, top_y = find_screen_text(top_month, {x2=60, y1=16})
    if not top_y then return end
    local col_x = find_screen_text(routine.name, {x1=50, y1=top_y - 3, y2=top_y - 3})
    if not col_x then return end
    return {x=col_x, y=top_y + MONTH_ROW_H * (focus.month - sched.scroll_position_month)}
end

function ClassicKeysOverlay:on_months_input(keys)
    if keys.LEAVESCREEN then
        sched.viewing_months_squad_id = -1
        return true
    end
    local focus = self:sync_month_focus()
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        focus.col = focus.col + sign(dx or 0)
        focus.month = focus.month + sign(dy or 0) + (step or 0)
        self:sync_month_focus()
        return true
    end
    local cell = self:month_cell()
    if keys.SELECT or keys.CUSTOM_E then
        -- as on the grid: the button is only pressed while it reads "Edit"
        local tile = cell and dfhack.screen.readTile(cell.x, cell.y + 3)
        if tile and tile.ch == string.byte('E') then
            click_screen(cell.x + 1, cell.y + 3)
        end
    elseif keys.CUSTOM_C then
        if cell then click_screen(cell.x + 8, cell.y + 3) end
    else
        return letter_key_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:month_lines()
    local focus = self:sync_month_focus()
    local routine = routines()[focus.col]
    return {
        {{text=clip(dfhack.military.getSquadName(sched.viewing_months_squad_id), PANEL_TEXT_W), pen=COLOR_LIGHTMAGENTA}},
        {{text=('cursor on: %s, %s'):format(MONTHS[focus.month + 1], routine and routine.name or '?'), pen=COLOR_YELLOW}},
        {hint('arrows', 'move  '), hint('- =', 'month')},
        {hint('Enter', 'edit this month  '), hint('c', 'copy/paste')},
        {hint('Esc', 'back to the grid')},
    }
end

-- the routine editor (a on the schedule grid) -----------------------------------
--
-- The fort's routines, 3 rows apart under the "Military routines" heading;
-- each row has a quill (rename) 23 columns and a bin (delete) 33 columns from
-- the heading's first letter, and "Add new routine" follows the last. The bin
-- asks first (squad_schedule.deleting_routine_id). The keys are the old alert
-- page's: c add, d delete, N name.
function ClassicKeysOverlay:routine_row()
    local x, y = find_screen_text('Military routines', {x2=gps.dimx - 40})
    local count = #routines()
    if not x or count == 0 then return end
    local first = y + 3
    local visible = math.max(1, (gps.dimy - 8 - first) // 3)
    self.routine_idx = math.max(0, math.min(self.routine_idx or 0, count - 1))
    -- the game leaves this below zero after adding a routine
    local scroll = math.max(0, sched.scroll_position_edit_routine)
    if self.routine_idx < scroll then
        scroll = self.routine_idx
    elseif self.routine_idx >= scroll + visible then
        scroll = self.routine_idx - visible + 1
    end
    sched.scroll_position_edit_routine = scroll
    return x, first + 3 * (self.routine_idx - scroll)
end

function ClassicKeysOverlay:on_routines_input(keys)
    if sched.deleting_routine_id ~= -1 then
        if keys.SELECT then
            click_label('Confirm', {x2=gps.dimx - 40})
        elseif keys.LEAVESCREEN then
            sched.deleting_routine_id = -1
        end
        return true
    end
    if keys.LEAVESCREEN or keys.SELECT then
        sched.editing_routines = false
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.routine_idx = (self.routine_idx or 0) + sign(dy or 0) + (step or 0)
        self:routine_row()
        return true
    end
    if keys.CUSTOM_C or keys.CUSTOM_A then
        if click_label('Add new routine', {x2=gps.dimx - 40}) then
            -- the new routine goes last
            self.routine_idx = #routines() + 1
        end
    elseif keys.CUSTOM_SHIFT_N or keys.CUSTOM_N then
        local x, row = self:routine_row()
        if x then click_screen(x + 23, row) end
    elseif keys.CUSTOM_D then
        local x, row = self:routine_row()
        if x then click_screen(x + 33, row) end
    else
        return letter_key_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:on_schedule_input(keys)
    -- typing a routine's name: the game takes the keys, bar the Esc that
    -- would also open its options menu
    if sched.entering_routine_name then
        if keys.LEAVESCREEN then
            sched.entering_routine_name = false
            return true
        end
        return false
    end
    -- the game's sub-screens: Esc steps out of them one at a time, where the
    -- game's own Esc would close the whole squads panel
    if sq.editing_squad_schedule_id ~= -1 then
        return self:on_order_editor_input(keys)
    elseif sched.viewing_months_squad_id ~= -1 then
        return self:on_months_input(keys)
    elseif sched.editing_routines then
        return self:on_routines_input(keys)
    end

    local focus = self:sync_schedule_focus()
    if keys.LEAVESCREEN then
        sched.open = false
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        focus.col = focus.col + sign(dx or 0)
        focus.row = focus.row + sign(dy or 0) + (step or 0)
        self:sync_schedule_focus()
        return true
    end
    if keys.SELECT then
        local squad = df.squad.find(sched.squad_id[focus.row] or -1)
        if squad then squad.cur_routine_idx = focus.col end
        return true
    end

    local cell = self:schedule_cell()
    if keys.CUSTOM_E then
        -- the first button reads "Edit", or "Clear" once a routine has monthly
        -- orders; only ever press it as Edit
        local tile = cell and dfhack.screen.readTile(cell.x, cell.y + 3)
        if tile and tile.ch == string.byte('E') then
            click_screen(cell.x + 1, cell.y + 3)
        end
    elseif keys.CUSTOM_C then
        if cell then click_screen(cell.x + 8, cell.y + 3) end
    elseif keys.CUSTOM_SHIFT_X then
        -- the same first button, when it reads "Clear": it wipes the squad's
        -- monthly orders under this routine, so ask first
        local tile = cell and dfhack.screen.readTile(cell.x, cell.y + 3)
        if tile and tile.ch == string.byte('C') then
            local x, y = cell.x + 1, cell.y + 3
            dialogs.showYesNoPrompt('Clear orders',
                "Clear this squad's monthly orders under this routine?", COLOR_WHITE,
                function() click_screen(x, y) end)
        end
    elseif keys.CUSTOM_V then
        if cell then click_screen(cell.head_x + 10, cell.y + 3) end
    elseif keys.CUSTOM_A then
        click_label('Add/edit routines')
    else
        return letter_key_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:schedule_lines()
    local focus = self:sync_schedule_focus()
    local squad = df.squad.find(sched.squad_id[focus.row] or -1)
    local routine = routines()[focus.col]
    local lines = {}
    if squad and routine then
        local active = routines()[squad.cur_routine_idx]
        lines[#lines + 1] = {{text=clip(dfhack.military.getSquadName(squad.id), PANEL_TEXT_W), pen=COLOR_LIGHTMAGENTA}}
        lines[#lines + 1] = {{text='follows: ' .. (active and active.name or '?'), pen=COLOR_WHITE}}
        lines[#lines + 1] = {{text='cursor on: ' .. routine.name, pen=COLOR_YELLOW}}
    end
    lines[#lines + 1] = {hint('arrows', 'move  '), hint('Enter', 'follow this routine')}
    lines[#lines + 1] = {hint('e', 'edit orders  '), hint('c', 'copy/paste  '), hint('v', 'months')}
    lines[#lines + 1] = {hint('a', 'routines  '), hint('X', 'clear monthly orders')}
    lines[#lines + 1] = {hint('Esc', 'back to squads')}
    return lines
end

-- creating a squad (C in the squads panel) -------------------------------------
--
-- Two lists in a row: which kind of squad (one per vacant or new captain
-- position), then which uniform. The squad exists once the uniform is chosen.
-- Both lists sit under a heading, rows 3 apart.

local function new_squad_step()
    if mi.create_squad.open then
        return {heading='Create which squad?', first_row=3, title='New squad: which kind',
                count=#mi.create_squad.cand_new_squad_appoint_epp,
                cancel=function() mi.create_squad.open = false end}
    elseif mi.assign_uniform.open and not equip.open then
        return {heading='Choose a uniform', first_row=4, title='New squad: which uniform',
                count=#df.global.plotinfo.main.fortress_entity.uniforms + 1,
                cancel=function() mi.assign_uniform.open = false end}
    end
end

function ClassicKeysOverlay:new_squad_row(step)
    local x, y = find_screen_text(step.heading)
    if not x then return end
    self.new_squad_idx = math.max(0, math.min(self.new_squad_idx or 0, step.count - 1))
    return x, y + step.first_row + 3 * self.new_squad_idx
end

function ClassicKeysOverlay:on_new_squad_input(keys, step)
    if keys.LEAVESCREEN then
        step.cancel()
        self.new_squad_idx = 0
        return true
    end
    local dx, dy = self:take_move(keys)
    local move = list_step(keys)
    if dx or move then
        self.new_squad_idx = (self.new_squad_idx or 0) + sign(dy or 0) + (move or 0)
        self:new_squad_row(step)
        return true
    end
    if keys.SELECT then
        local x, row = self:new_squad_row(step)
        if x and step.count > 0 then
            click_screen(x + 6, row)
            self.new_squad_idx = 0
        end
        return true
    end
    -- in the list of uniforms: d deletes and N renames the highlighted one,
    -- as in the same list on the equipment screen
    local uniforms = df.global.plotinfo.main.fortress_entity.uniforms
    local uniform = step.heading == 'Choose a uniform' and uniforms[self.new_squad_idx or 0]
    if uniform and (self.new_squad_idx or 0) < #uniforms then
        if keys.CUSTOM_D then
            local x, row = self:new_squad_row(step)
            if x then click_screen(x + 35, row) end
            return true
        elseif keys.CUSTOM_SHIFT_N then
            local id = uniform.id
            dialogs.showInputPrompt('Uniform name', 'Type the new name, then Enter:', COLOR_WHITE,
                uniform.name, function(text)
                    for _, candidate in ipairs(uniforms) do
                        if candidate.id == id and #text > 0 then candidate.name = text end
                    end
                end)
            return true
        end
    end
    return letter_key_pressed(keys)
end

-- choosing a dwarf for a squad position ---------------------------------------
--
-- The game's unit list. Its length is not readable from here, so the
-- selection is a row on screen: moving past the last row scrolls the list.
-- Letters are left alone: DFHack's own filters on this screen use them.
local UNIT_ROW_H = 3

local function unit_selector_open()
    return focus_is('dwarfmode/UnitSelector')
end

local function unit_selector_rows()
    local usel = mi.unit_selector
    local first = usel.offset_top + UNIT_SELECTOR_FIRST_ROW
    local visible = math.max(1, (gps.dimy + usel.offset_bottom - 4 - first) // UNIT_ROW_H)
    return first, visible, usel.offset_left + 10
end

function ClassicKeysOverlay:on_unit_selector_input(keys)
    local usel = mi.unit_selector
    local first, visible, x = unit_selector_rows()
    self.usel_idx = math.max(0, math.min(self.usel_idx or 0, visible - 1))
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        local idx = self.usel_idx + sign(dy or 0) + (step or 0)
        if idx < 0 then
            usel.scroll_position = math.max(0, usel.scroll_position - 1)
        elseif idx >= visible then
            usel.scroll_position = usel.scroll_position + 1
        end
        self.usel_idx = math.max(0, math.min(idx, visible - 1))
        return true
    end
    if keys.SELECT then
        if squads_open() then
            -- a squad position: a click on the name fills it, and the list
            -- starts again
            click_screen(x, first + UNIT_ROW_H * self.usel_idx)
            self.usel_idx = 0
        else
            -- a zone's animals or owner: the tick box, 39 columns into the
            -- list's window; the list stays where it is for the next one
            click_screen(usel.offset_left + 39, first + UNIT_ROW_H * self.usel_idx)
        end
        return true
    end
    if keys.LEAVESCREEN then
        -- Esc arrives as "leave" and "options" together; passed on whole, the
        -- list closes and the options menu opens behind it
        self:feed('LEAVESCREEN')
        return true
    end
    return false
end

-- a squad's positions (p in the squads panel) -----------------------------------
--
-- "Assign leader" and then one slot per position, 3 rows apart, 6 rows under
-- the "Back to squads" button. Enter on a slot opens the unit list for it.
local function positions_squad()
    return df.squad.find(sq.squad_id[sq.viewing_squad_index] or -1)
end

function ClassicKeysOverlay:position_row()
    local squad = positions_squad()
    local x, y = find_screen_text('Back to squads', squad_panel_bounds())
    if not squad or not x then return end
    local first = y + 6
    local visible = math.max(1, (gps.dimy - 11 - first) // 3)
    -- until a squad has its leader, the leader's slot is the only one offered
    local count = squad.positions[0].occupant == -1 and 1 or #squad.positions
    self.position_idx = math.max(0, math.min(self.position_idx or 0, count - 1))
    if self.position_idx < sq.scroll_position then
        sq.scroll_position = self.position_idx
    elseif self.position_idx >= sq.scroll_position + visible then
        sq.scroll_position = self.position_idx - visible + 1
    end
    -- the slots start 8 columns left of the button's text; the column before
    -- them, just inside the panel's border, is free
    return x - 9, first + 3 * (self.position_idx - sq.scroll_position)
end

-- Tick or untick the soldier in a position, as the box beside the name does;
-- orders given in this view go to the ticked soldiers only.
local function toggle_soldier(squad, idx)
    local position = squad and squad.positions[idx]
    if not position or position.occupant == -1 then return end
    for i, hfid in ipairs(sq.squad_hfid_selected) do
        if hfid == position.occupant then
            sq.squad_hfid_selected:erase(i)
            return
        end
    end
    sq.squad_hfid_selected:insert('#', position.occupant)
end

-- The squad's name box is 3 rows under "Back to squads"; the quill at its
-- right end, 13 columns past the button's text, starts typing a name.
local function click_name_quill()
    local x, y = find_screen_text('Back to squads', squad_panel_bounds())
    if not x then return false end
    click_screen(x + 13, y + 3)
    return true
end

function ClassicKeysOverlay:on_positions_input(keys)
    if keys.LEAVESCREEN then
        sq.viewing_squad_index = -1
        sq.scroll_position = 0
        sq.squad_hfid_selected:resize(0)
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.position_idx = (self.position_idx or 0) + sign(dy or 0) + (step or 0)
        self:position_row()
        return true
    end
    local squad = positions_squad()
    for i = 1, squad and math.min(#SQUAD_LETTERS, #squad.positions) or 0 do
        if keys['CUSTOM_' .. SQUAD_LETTERS:sub(i, i):upper()] then
            toggle_soldier(squad, i - 1)
            return true
        end
    end
    if keys.CUSTOM_X then
        toggle_soldier(squad, self.position_idx or 0)
        return true
    elseif keys.CUSTOM_SHIFT_N then
        click_name_quill()
        return true
    elseif self:on_order_key(keys) then
        return true
    end
    if keys.SELECT then
        local function open_slot()
            local x, row = self:position_row()
            if not x then return false end
            self.usel_idx = 0
            click_screen(x + 8, row)
            return true
        end
        -- Enter straight after p can arrive before the view has been drawn
        if not open_slot() then
            dfhack.timeout(10, 'frames', function()
                if sq.open and sq.viewing_squad_index ~= -1 and not unit_selector_open() then
                    open_slot()
                end
            end)
        end
        return true
    end
    return letter_key_pressed(keys)
end

-- the order keys shared by the squad list and a squad's positions
function ClassicKeysOverlay:on_order_key(keys)
    if keys.CUSTOM_M then
        self:start_order('move')
    elseif keys.CUSTOM_K then
        self:start_order('kill')
    elseif keys.CUSTOM_O then
        if any_selection() then click_order_icon(ORDER_ICON.cancel) end
    elseif keys.CUSTOM_R then
        if any_selection() then
            self.route_idx, self.route_point_idx = 0, 0
            click_order_icon(ORDER_ICON.patrol)
        end
    elseif keys.CUSTOM_W then
        if any_selection() then
            self.burrow_idx = 0
            click_order_icon(ORDER_ICON.burrow)
        end
    elseif keys.CUSTOM_T then
        if any_selection() then click_order_icon(ORDER_ICON.train) end
    else
        return false
    end
    return true
end

-- defending burrows (w) ---------------------------------------------------------
--
-- A window of the fort's burrows, each with a tick box, 3 rows apart under
-- its heading; "Confirm" and "Cancel" sit elsewhere on screen. The ticks are
-- burrow_selector.selected, set directly.
local burrow_ui = mi.burrow_selector
local PICKER_BOUNDS = {x1=60}

-- the row of entry `idx` in a picker whose entries start 3 rows under
-- `heading`, scrolling it so that the entry is on screen
local function picker_row(heading, idx, count, ui)
    local x, y = find_screen_text(heading, PICKER_BOUNDS)
    if not x or count == 0 then return end
    local first = y + 3
    local visible = math.max(1, (gps.dimy - 14 - first) // 3)
    idx = math.max(0, math.min(idx or 0, count - 1))
    if idx < ui.scroll_position then
        ui.scroll_position = idx
    elseif idx >= ui.scroll_position + visible then
        ui.scroll_position = idx - visible + 1
    end
    return x, first + 3 * (idx - ui.scroll_position), idx
end

function ClassicKeysOverlay:burrow_row()
    local x, row, idx = picker_row('Select which burrows', self.burrow_idx, #burrow_ui.burrow_id, burrow_ui)
    if not x then return end
    self.burrow_idx = idx
    -- names start 6 columns in, after the burrow's symbol
    return x + 4, row
end

function ClassicKeysOverlay:on_burrow_input(keys)
    if keys.LEAVESCREEN then
        if not click_label('Cancel', PICKER_BOUNDS) then
            burrow_ui.open = false
            sq.giving_burrow_order = false
        end
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.burrow_idx = (self.burrow_idx or 0) + sign(dy or 0) + (step or 0)
        self:burrow_row()
        return true
    end
    local count = #burrow_ui.burrow_id
    if keys.CUSTOM_X then
        if self:burrow_row() then
            burrow_ui.selected[self.burrow_idx] = not burrow_ui.selected[self.burrow_idx]
        end
        return true
    elseif keys.SELECT then
        local any = false
        for _, selected in ipairs(burrow_ui.selected) do
            any = any or selected
        end
        if not any and self:burrow_row() then
            burrow_ui.selected[self.burrow_idx] = true
            any = true
        end
        if any then click_label('Confirm', PICKER_BOUNDS) end
        return true
    end
    return letter_key_pressed(keys)
end

-- patrol routes (r) ---------------------------------------------------------------
--
-- First a list of the fort's routes (plotinfo.waypoints.routes), 3 rows apart
-- under its heading: a click on a name orders the patrol, and each row ends
-- with a magnifier (edit) and a bin (delete), 31 and 35 columns from the
-- name. Then the route editor (patrol_routes.adding_new_route): its points
-- are clicks on the map, listed as "Point n" with a bin each, under a name box
-- whose quill is in the bins' column. With no routes yet the editor opens
-- straight away, and confirming it sends the ticked squads on that route.
local routes_ui = mi.patrol_routes
local ROUTE_EDIT_COL, ROUTE_BIN_COL = 31, 35

local function fort_routes()
    return df.global.plotinfo.waypoints.routes
end

local function route_editor_open()
    return routes_ui.open and routes_ui.adding_new_route
end

function ClassicKeysOverlay:route_row()
    local x, row, idx = picker_row('Select or create a route', self.route_idx, #fort_routes(), routes_ui)
    if not x then return end
    self.route_idx = idx
    return x, row
end

-- where the selected point's row is in the editor, from the first point shown
function ClassicKeysOverlay:route_point_row()
    local count = #routes_ui.new_point.x
    local x, y = find_screen_text('Point', PICKER_BOUNDS)
    if not x or count == 0 then return end
    self.route_point_idx = math.max(0, math.min(self.route_point_idx or 0, count - 1))
    local visible = math.max(1, (gps.dimy - 17 - y) // 3)
    local scroll = routes_ui.scroll_position
    if self.route_point_idx < scroll then
        routes_ui.scroll_position = self.route_point_idx
    elseif self.route_point_idx >= scroll + visible then
        routes_ui.scroll_position = self.route_point_idx - visible + 1
    end
    return x, y + 3 * (self.route_point_idx - routes_ui.scroll_position)
end

local function close_route_picker()
    if not click_label('Cancel', PICKER_BOUNDS) then
        routes_ui.open = false
        sq.giving_patrol_order = false
    end
end

function ClassicKeysOverlay:on_route_editor_input(keys)
    if not self.order then
        self.order = 'route'
        self.route_point_idx = 0
        if not self.cursor or not guidm.Viewport.get():isVisible(self.cursor) then
            self.cursor = guidm.Viewport.get():getCenter()
        end
    end
    if keys.LEAVESCREEN then
        self.order = nil
        -- opened from the list, the editor has a "Back" button to return to
        -- it; "Back to squads" in the panel to the right is not that button
        if not click_label('Back', {x1=60, x2=gps.dimx - 30}) then
            close_route_picker()
        end
        return true
    end
    local dx, dy, dz = self:take_move(keys)
    if dx then
        local pos = xyz2pos(self.cursor.x + dx, self.cursor.y + dy, self.cursor.z + dz)
        if dfhack.maps.isValidTilePos(pos) then self.cursor = pos end
        return true
    end
    local step = list_step(keys)
    if step then
        self.route_point_idx = (self.route_point_idx or 0) + step
        self:route_point_row()
        return true
    end
    if keys.SEC_SELECT or keys.SELECT_ALL then
        if #routes_ui.new_point.x > 0 and click_label('Confirm', PICKER_BOUNDS) then
            self.order = nil
            self.route_idx = 0
        end
        return true
    elseif keys.SELECT then
        self:click_map_tile(self.cursor)
        self.route_point_idx = #routes_ui.new_point.x
        return true
    elseif keys.CUSTOM_X then
        local x, row = self:route_point_row()
        if x then click_screen(x + ROUTE_BIN_COL, row) end
        return true
    elseif keys.CUSTOM_N then
        -- the name box is the row above the points, or above the hint that
        -- stands in for them
        local x, y = find_screen_text('Point', PICKER_BOUNDS)
        if not x then x, y = find_screen_text('Click the map', PICKER_BOUNDS) end
        if x then click_screen(x + ROUTE_BIN_COL, y - 3) end
        return true
    end
    return letter_key_pressed(keys)
end

function ClassicKeysOverlay:on_patrol_input(keys)
    if routes_ui.entering_new_route_name then
        -- typing the route's name: the game takes the keys, bar the Esc that
        -- would also open its options menu
        if keys.LEAVESCREEN then
            routes_ui.entering_new_route_name = false
            return true
        end
        return false
    end
    if route_editor_open() then
        return self:on_route_editor_input(keys)
    end
    if self.order == 'route' then self.order = nil end
    if keys.LEAVESCREEN then
        close_route_picker()
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.route_idx = (self.route_idx or 0) + sign(dy or 0) + (step or 0)
        self:route_row()
        return true
    end
    if keys.SELECT then
        local x, row = self:route_row()
        if x then click_screen(x + 2, row) end
    elseif keys.CUSTOM_A then
        click_label('Create new route', PICKER_BOUNDS)
    elseif keys.CUSTOM_E then
        local x, row = self:route_row()
        if x then click_screen(x + ROUTE_EDIT_COL, row) end
    elseif keys.CUSTOM_D then
        local x, row = self:route_row()
        if x then click_screen(x + ROUTE_BIN_COL, row) end
    else
        return letter_key_pressed(keys)
    end
    return true
end

-- the six order buttons end with the bin that disbands, 12 columns past the
-- "Schedule" label; it asks "Disband / Cancel" before doing anything
function ClassicKeysOverlay:on_disband_prompt_input(keys)
    if keys.SELECT then
        click_label('Disband', squad_panel_bounds())
    elseif keys.LEAVESCREEN then
        if not click_label('Cancel', squad_panel_bounds()) then
            sq.disband_confirmation = false
        end
    end
    return true
end

function ClassicKeysOverlay:on_squads_input(keys)
    if unit_selector_open() then
        return self:on_unit_selector_input(keys)
    end
    local step = new_squad_step()
    if step then
        return self:on_new_squad_input(keys, step)
    end
    if sq.disband_confirmation then
        return self:on_disband_prompt_input(keys)
    end
    -- the two pickers open from the order buttons and from a schedule's orders
    if routes_ui.open then
        return self:on_patrol_input(keys)
    elseif burrow_ui.open then
        return self:on_burrow_input(keys)
    end
    if equipment_open() then
        return self:on_equipment_input(keys)
    elseif schedule_open() then
        return self:on_schedule_input(keys)
    end
    if sq.entering_squad_nickname then
        -- typing a squad's name: the game takes the keys, bar the Esc that
        -- would also open its options menu
        if keys.LEAVESCREEN then
            sq.entering_squad_nickname = false
            return true
        end
        return false
    end
    -- an order is being aimed, by us or after a click on the game's button
    if sq.giving_move_order or sq.giving_kill_order then
        if not self.order then
            self.order = sq.giving_move_order and 'move' or 'kill'
            self.cursor = self.cursor or guidm.Viewport.get():getCenter()
        end
        return self:on_order_input(keys)
    end
    self.order = nil
    if sq.viewing_squad_index ~= -1 then
        return self:on_positions_input(keys)
    end

    if keys.LEAVESCREEN then
        -- the game closes this panel with the key that opened it
        self:feed('D_SQUADS')
        return true
    end
    for i = 1, math.min(#SQUAD_LETTERS, #sq.squad_id) do
        if keys['CUSTOM_' .. SQUAD_LETTERS:sub(i, i):upper()] then
            sq.squad_selected[i - 1] = not sq.squad_selected[i - 1]
            return true
        end
    end
    if self:on_order_key(keys) then
        return true
    elseif keys.CUSTOM_SHIFT_N then
        -- the name is typed in the first ticked squad's positions view
        for i, selected in ipairs(sq.squad_selected) do
            if selected then
                sq.viewing_squad_index = i
                self.position_idx = 0
                -- the view has to be drawn before its quill can be clicked
                dfhack.timeout(10, 'frames', function()
                    if sq.open and sq.viewing_squad_index == i then click_name_quill() end
                end)
                break
            end
        end
    elseif keys.CUSTOM_SHIFT_B then
        -- the name builder: the quill on the first ticked squad's entry in
        -- the game's list, 2 rows above its name and 14 columns along
        for i, selected in ipairs(sq.squad_selected) do
            if selected then
                local name = dfhack.military.getSquadName(sq.squad_id[i])
                local x, y = find_screen_text(name:sub(1, 12), squad_panel_bounds())
                if x then
                    self.nm_pane = 0
                    click_screen(x + 14, y - 2)
                end
                break
            end
        end
    elseif keys.CUSTOM_Z then
        for i, selected in ipairs(sq.squad_selected) do
            local squad = selected and df.squad.find(sq.squad_id[i])
            local leader = squad and squad_leader(squad)
            if leader then
                dfhack.gui.revealInDwarfmodeMap(xyz2pos(dfhack.units.getPosition(leader)), true)
                break
            end
        end
    elseif keys.CUSTOM_S then
        if any_squad_selected() then click_label('Schedule', squad_panel_bounds()) end
    elseif keys.CUSTOM_SHIFT_E then
        if any_squad_selected() then click_label('Equip', squad_panel_bounds()) end
    elseif keys.CUSTOM_SHIFT_C then
        self.new_squad_idx = 0
        click_label('Create new squad', squad_panel_bounds())
    elseif keys.CUSTOM_P then
        -- the first ticked squad's positions
        for i, selected in ipairs(sq.squad_selected) do
            if selected then
                sq.viewing_squad_index = i
                self.position_idx = 0
                break
            end
        end
    elseif keys.CUSTOM_SHIFT_D then
        if any_squad_selected() then
            local x, y = find_screen_text('Schedule', squad_panel_bounds())
            if x then click_screen(x + 12, y) end
        end
    else
        -- stray letters do nothing; - and = have no list to move through here
        return letter_key_pressed(keys) or list_step(keys) ~= nil
    end
    return true
end

function ClassicKeysOverlay:squad_lines()
    if self.order == 'move' then
        return {
            {{text='Move: put the cursor where they should go', pen=COLOR_GREY}},
            {hint('Enter', 'station there  '), hint('Esc', 'cancel')},
        }
    elseif self.order == 'kill' then
        local lines
        if self.order_rect then
            lines = {
                {{text=self.order_anchor and 'Kill: now the opposite corner'
                      or 'Kill: put the cursor on one corner of the area', pen=COLOR_GREY}},
                {hint('Enter', self.order_anchor and 'attack everything inside  ' or 'set corner  '),
                 hint('Esc', 'back')},
            }
        else
            lines = {
                {{text='Kill: put the cursor on a creature', pen=COLOR_GREY}},
                {hint('Enter', 'attack it  '), hint('l', 'list  '), hint('r', 'rectangle')},
                {hint('Esc', 'cancel')},
            }
        end
        if self.order_note then
            lines[#lines + 1] = {{text=self.order_note, pen=COLOR_LIGHTRED}}
        end
        return lines
    end
    local lines = {}
    for i = 1, #sq.squad_id do
        local selected = sq.squad_selected[i - 1]
        local letter = i <= #SQUAD_LETTERS and SQUAD_LETTERS:sub(i, i) or ' '
        lines[#lines + 1] = {
            {text=letter .. ' ', pen=COLOR_LIGHTGREEN},
            {text=selected and '[x] ' or '[ ] ', pen=selected and COLOR_YELLOW or COLOR_GREY},
            {text=clip(dfhack.military.getSquadName(sq.squad_id[i - 1]), PANEL_TEXT_W - 6),
             pen=selected and COLOR_YELLOW or COLOR_WHITE},
        }
    end
    if #sq.squad_id == 0 then
        lines[#lines + 1] = {{text='no squads', pen=COLOR_GREY}}
    end
    lines[#lines + 1] = {hint('m', 'move  '), hint('k', 'kill  '), hint('o', 'cancel orders')}
    lines[#lines + 1] = {hint('r', 'patrol  '), hint('w', 'defend burrow  '), hint('t', 'train')}
    lines[#lines + 1] = {hint('s', 'schedule  '), hint('E', 'equip  '), hint('z', 'centre')}
    lines[#lines + 1] = {hint('p', 'positions  '), hint('N', 'name  '), hint('C', 'new squad')}
    lines[#lines + 1] = {hint('B', 'build a name  '), hint('D', 'disband  '), hint('Esc', 'done')}
    return lines
end

-- the info window: work orders (the old manager, j then m) and nobles (n) ------
--
-- Both are tabs of the game's big info window. Rows are 3 screen rows apart
-- and placed from the row of tabs along its top; buttons are icons with no
-- text, so columns are counted from whatever text a row does have.

do
local info = mi.info
local INFO_MODE = df.info_interface_mode_type
local wo_ui = info.work_orders
local cond_ui = wo_ui.conditions
local create_ui = mi.create_work_order
local admin_ui = info.administrators

-- The row the window's tabs end on, which the lists under them are counted
-- from. On a narrow screen the tabs wrap onto a second line, with the line
-- that holds the open tab nearest the content, and everything under them
-- moves down with it: so this is the lowest row any tab's label is on.
local INFO_TAB_NAMES = {'Creatures', 'Tasks', 'Places', 'Labor', 'Work orders',
                        'Nobles and administrators', 'Objects', 'Justice'}
local function info_tabs_row()
    local lowest
    for _, name in ipairs(INFO_TAB_NAMES) do
        local _, y = find_screen_text(name, {y2=12})
        if y then lowest = math.max(lowest or y, y) end
    end
    return lowest or 5
end
ClassicKeysOverlay.info_tabs_row = info_tabs_row

-- The letters that open the tabs from the map open them here too, so any tab
-- is one key from any other; m also opens the work orders, as it did from the
-- old job list (the manager was j then m). Shifted letters first: their key
-- codes can come with others.
-- (a field, not a local: this chunk is at Lua's limit of 200 locals)
ClassicKeysOverlay.INFO_TAB_KEYS = {
    {'CUSTOM_SHIFT_L', 'Objects'}, {'CUSTOM_SHIFT_J', 'Justice'},
    {'CUSTOM_U', 'Creatures'}, {'CUSTOM_J', 'Tasks'}, {'CUSTOM_L', 'Places'},
    {'CUSTOM_Y', 'Labor'}, {'CUSTOM_O', 'Work orders'}, {'CUSTOM_M', 'Work orders'},
    {'CUSTOM_N', 'Nobles and administrators'},
}
function ClassicKeysOverlay.info_tab_for_key(keys)
    for _, entry in ipairs(ClassicKeysOverlay.INFO_TAB_KEYS) do
        if keys[entry[1]] then return entry[2] end
    end
end

-- the line every tab's key list ends with, after Tab's own
function ClassicKeysOverlay.info_tab_hint()
    return {hint('u j l y m n L J', 'tabs')}
end

-- the rows the tab labels can be on, for clicking one
local function info_tabs_bounds()
    local highest
    for _, name in ipairs(INFO_TAB_NAMES) do
        local _, y = find_screen_text(name, {y2=12})
        if y then highest = math.min(highest or y, y) end
    end
    return {y1=highest or 5, y2=info_tabs_row() + 1}
end

local function row_text_start(y, x1, x2)
    for x = x1, x2 do
        local tile = dfhack.screen.readTile(x, y)
        if tile and tile.ch and tile.ch > 32 then return x end
    end
end

local function row_has_text(x, y)
    return row_text_start(y, x, x + 30) ~= nil
end

-- the number key pressed, 1 to 9, if one was
local function typed_digit(keys)
    local char = keys._STRING
    if char and char >= 49 and char <= 57 then return char - 48 end
end

-- a letter with or without Shift; Ctrl and Alt combinations are DFHack's
-- (its search and import / export keys live on these screens)
local function plain_letter_pressed(keys)
    for code in pairs(keys) do
        if type(code) == 'string' and (code:match('^CUSTOM_%u$') or code:match('^CUSTOM_SHIFT_%u$')) then
            return true
        end
    end
    return false
end

-- The lists these screens open are filtered by the game as a name is typed,
-- so their length cannot be read: the selection is a row on screen, and
-- moving past the last row scrolls. `list` says where the rows are (x of
-- their text, first row) and which field scrolls them.
local function list_visible(list)
    return list.visible or math.max(1, (gps.dimy - 4 - list.first) // 3)
end

function ClassicKeysOverlay:info_rows()
    local top = info_tabs_row()
    if create_ui.open then
        -- the tasks, right of the list of workshops; the tabs are hidden here
        local x
        for i = 0, 5 do
            x = x or row_text_start(10 + 3 * i, gps.dimx * 42 // 100, gps.dimx - 40)
        end
        return x and {x=x, first=10, owner=create_ui, scroll='scroll_position_job'}
    elseif info.current_mode == INFO_MODE.WORK_ORDERS and cond_ui.open then
        if cond_ui.change_type ~= -1 then
            return {x=6, first=top + 10, owner=cond_ui, scroll='scroll_position_change'}
        elseif cond_ui.selecting_order_condition then
            return {x=12, first=top + 10, owner=cond_ui, scroll='scroll_position_condition_wq'}
        end
    elseif info.current_mode == INFO_MODE.ADMINISTRATORS then
        if admin_ui.assigning_symbol then
            return {x=12, first=top + 8, owner=admin_ui, scroll='scroll_position_symbol',
                    click_x=gps.dimx - 36}
        elseif admin_ui.choosing_candidate then
            return {x=13, first=top + 4, owner=admin_ui, scroll='scroll_position_candidate'}
        end
    end
end

-- Returns true when the key moved the selection, 'chosen' when Enter clicked
-- a row, and nil when the key is not one of the list's.
function ClassicKeysOverlay:rows_input(keys, list)
    local visible = list_visible(list)
    local idx = math.max(0, math.min(self.rows_idx or 0, visible - 1))
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if (dx and dy ~= 0) or step then
        local scroll = list.owner[list.scroll]
        local target = idx + (dy or 0) + (step or 0)
        if target < 0 then
            list.owner[list.scroll] = math.max(0, scroll + target)
            target = 0
        elseif target >= visible then
            -- only when there is an entry on the last row can there be more
            if row_has_text(list.x, list.first + 3 * (visible - 1)) then
                list.owner[list.scroll] = scroll + target - visible + 1
            end
            target = visible - 1
        end
        while target > 0 and not row_has_text(list.x, list.first + 3 * target) do
            target = target - 1
        end
        self.rows_idx = target
        return true
    end
    if keys.SELECT then
        local row = list.first + 3 * idx
        if row_has_text(list.x, row) then
            click_screen(list.click_x or (list.x + 2), row)
            return 'chosen'
        end
        return true
    end
end

-- each frame: undo a scroll past the end of the list, keep the selection on
-- an entry, and mark it
function ClassicKeysOverlay:render_rows(list)
    local visible = list_visible(list)
    local scroll = list.owner[list.scroll]
    -- (some lists scroll by entry, others by screen row: 3 to an entry)
    if scroll > 0 and not row_has_text(list.x, list.first + 3 * (visible - 1)) then
        list.owner[list.scroll] = math.max(0, scroll - (list.unit or 1))
    end
    local idx = math.max(0, math.min(self.rows_idx or 0, visible - 1))
    while idx > 0 and not row_has_text(list.x, list.first + 3 * idx) do
        idx = idx - 1
    end
    self.rows_idx = idx
    -- the arrow goes just before the row's text: lists with headings indent
    -- their entries, behind an icon the arrow would be hidden under
    local start = row_text_start(list.first + 3 * idx, list.x, list.x + 30)
    if start then mark_row(start - 1, list.first + 3 * idx, 40) end
end

-- work orders ---------------------------------------------------------------------
--
-- A row per order. Left to right: its name, then icon buttons, then a label
-- ("Can use any shop" / "2 shops max"), three more buttons and the X that
-- removes it. Counted from the label's first letter: amount -36, move up -24,
-- move down -20, conditions -16, details -12, workshop limit +22, remove +43;
-- the button for a new order is 5 columns past the first row's X.
-- Where an order's buttons are. The row is laid out in thirds of the screen
-- width: the amount, the arrows, conditions and details start a third of the
-- way across; the workshop limit two thirds across; remove and new are a
-- fixed distance from the right edge. (Measured at grids of 174 and 240
-- columns, where these agree exactly.)
local function wo_button_x(which)
    local third = gps.dimx // 3
    local x = ({amount=third, up=third + 12, down=third + 16, conditions=third + 20,
                details=third + 24, shops=(2 * gps.dimx) // 3,
                remove=gps.dimx - 37, new=gps.dimx - 32})[which]
    return x
end

local function work_orders()
    return df.global.world.manager_orders.all
end

function ClassicKeysOverlay:wo_row()
    local count = #work_orders()
    if count == 0 then return end
    local first = info_tabs_row() + 4
    local visible = math.max(1, (gps.dimy - 9 - first) // 3)
    self.wo_idx = math.max(0, math.min(self.wo_idx or 0, count - 1))
    local scroll = math.max(0, math.min(wo_ui.scroll_position_work_orders, count - visible))
    if self.wo_idx < scroll then
        scroll = self.wo_idx
    elseif self.wo_idx >= scroll + visible then
        scroll = self.wo_idx - visible + 1
    end
    wo_ui.scroll_position_work_orders = scroll
    local row = first + 3 * (self.wo_idx - scroll)
    return row, row_text_start(row, gps.dimx // 2, gps.dimx - 50)
end

function ClassicKeysOverlay:click_wo_button(which)
    local row, label_x = self:wo_row()
    if not row or not label_x then return false end
    click_screen(wo_button_x(which), row)
    return true
end

-- Start a new order: the game's list of tasks, which filters as a name is
-- typed, like the old one. The button sits at the right end of the first
-- row, or where that would be when there are no orders yet.
function ClassicKeysOverlay:new_work_order()
    local first = info_tabs_row() + 4
    click_screen(wo_button_x('new'), first)
    self.rows_idx = 0
end

-- a number is being typed for an order (amount, workshop limit, a condition)
local function wo_entering_number()
    return wo_ui.entering_number or wo_ui.b_entering_number or cond_ui.entering_logic_number
end

function ClassicKeysOverlay:on_create_order_input(keys)
    local list = self:info_rows()
    -- counted before the click that makes the order, which happens at once
    local before = #work_orders()
    local moved = list and self:rows_input(keys, list)
    if moved == 'chosen' then
        -- The order is made with the game's default amount and the list
        -- closes. The old manager asked how many next, so go on to that.
        dfhack.timeout(10, 'frames', function()
            if create_ui.open or #work_orders() <= before then return end
            self.wo_idx = #work_orders() - 1
            self:wo_row()
            dfhack.timeout(10, 'frames', function()
                if info.open and info.current_mode == INFO_MODE.WORK_ORDERS and not cond_ui.open then
                    self:click_wo_button('amount')
                end
            end)
        end)
    end
    if moved then
        create_ui.entering_job_filter = false
        return true
    end
    if keys.LEAVESCREEN then
        if create_ui.entering_job_filter then
            create_ui.entering_job_filter = false
        else
            create_ui.open = false
        end
        return true
    end
    local dx, dy = self:take_move(keys)
    if dx and dx ~= 0 then
        -- left / right: the workshop whose tasks are listed
        local last = #create_ui.building - 1
        local idx = math.max(0, math.min(create_ui.selected_building_index + sign(dx), last))
        create_ui.selected_building_index = idx
        local visible = math.max(1, (gps.dimy - 4 - 7) // 3)
        if idx < create_ui.scroll_position_building then
            create_ui.scroll_position_building = idx
        elseif idx >= create_ui.scroll_position_building + visible then
            create_ui.scroll_position_building = idx - visible + 1
        end
        create_ui.scroll_position_job = 0
        self.rows_idx = 0
        return true
    end
    if keys._STRING then
        -- anything typed goes into the game's filter box, which is switched
        -- off again once the game has taken the key: while it is on, DFHack
        -- keeps overlays out and the next - = or arrow would not be ours
        create_ui.entering_job_filter = true
        self.rows_idx = 0
        create_ui.scroll_position_job = 0
        dfhack.timeout(1, 'frames', function() create_ui.entering_job_filter = false end)
    end
    return false
end

-- Conditions (c on an order). Item conditions come first, then conditions on
-- other orders, 3 rows apart from 7 rows under the tabs. An item condition's
-- buttons, in columns from the screen's right edge: number 70, inequality
-- 58, type 55, material 51, traits 46. Every row's X is 38 in, and an order
-- condition's one button 70. The three
-- buttons above the list (frequency, add item, add order) are 40, 36 and 32
-- in, on the row the orders start on.
function ClassicKeysOverlay:cond_row()
    local order = cond_ui.wq
    if not order then return end
    local count = #order.item_conditions + #order.order_conditions
    if count == 0 then return end
    local first = info_tabs_row() + 7
    local visible = math.max(1, (gps.dimy - 23 - first) // 3)
    self.cond_idx = math.max(0, math.min(self.cond_idx or 0, count - 1))
    local scroll = math.max(0, math.min(cond_ui.scroll_position_conditions, count - visible))
    if self.cond_idx < scroll then
        scroll = self.cond_idx
    elseif self.cond_idx >= scroll + visible then
        scroll = self.cond_idx - visible + 1
    end
    cond_ui.scroll_position_conditions = scroll
    return first + 3 * (self.cond_idx - scroll), self.cond_idx < #order.item_conditions
end

function ClassicKeysOverlay:on_conditions_input(keys)
    local list = self:info_rows()
    if list then
        local moved = self:rows_input(keys, list)
        if moved then
            if moved == 'chosen' then self.rows_idx = 0 end
            return true
        end
        if keys.LEAVESCREEN then
            if cond_ui.selecting_order_condition then
                cond_ui.selecting_order_condition = false
            else
                self:feed('LEAVESCREEN')
            end
            self.rows_idx = 0
            return true
        end
        -- the type, material and trait lists filter on whatever is typed
        if cond_ui.change_type ~= -1 then return false end
        return plain_letter_pressed(keys)
    end
    if keys.LEAVESCREEN then
        self:feed('LEAVESCREEN')
        return true
    end
    -- 1 to 9 add that one of the game's suggested conditions. Before the
    -- movement keys: number keys can also be bound to moving the cursor.
    local digit = typed_digit(keys)
    if digit then
        local x, y = find_screen_text('Suggested conditions', {x2=30})
        local line = x and y + 2 + 3 * (digit - 1)
        if line and row_has_text(x, line) then
            -- the new condition goes after the item conditions already there
            self.cond_idx = cond_ui.wq and #cond_ui.wq.item_conditions or 0
            click_screen(gps.dimx - 54, line)
        end
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.cond_idx = (self.cond_idx or 0) + sign(dy or 0) + (step or 0)
        self:cond_row()
        return true
    end
    local top = info_tabs_row() + 4
    local row, is_item = self:cond_row()
    -- "Type", "Mat" and "Adj" are drawn as pictures, not text, so an item
    -- condition's buttons are counted from the screen edge like the rest
    local type_x = row and is_item and gps.dimx - 56
    if keys.CUSTOM_A then
        self.cond_idx = cond_ui.wq and #cond_ui.wq.item_conditions or 0
        click_screen(gps.dimx - 36, top)
    elseif keys.CUSTOM_O then
        self.rows_idx = 0
        click_screen(gps.dimx - 32, top)
    elseif keys.CUSTOM_F then
        click_screen(gps.dimx - 40, top)
    elseif keys.CUSTOM_D then
        if row then click_screen(gps.dimx - 38, row) end
    elseif keys.CUSTOM_C then
        if row and not is_item then click_screen(gps.dimx - 70, row) end
    elseif keys.CUSTOM_N then
        if type_x then click_screen(type_x - 14, row) end
    elseif keys.CUSTOM_Q then
        if type_x then click_screen(type_x - 2, row) end
    elseif keys.CUSTOM_I or keys.CUSTOM_M or keys.CUSTOM_T then
        if type_x then
            self.rows_idx = 0
            click_screen(type_x + (keys.CUSTOM_I and 1 or keys.CUSTOM_M and 5 or 10), row)
        end
    else
        return plain_letter_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:on_work_orders_input(keys)
    if wo_entering_number() then
        -- a number is being typed: the game takes the keys, bar the Esc that
        -- would close the whole window
        if keys.LEAVESCREEN then
            wo_ui.entering_number = false
            wo_ui.b_entering_number = false
            cond_ui.entering_logic_number = false
            return true
        end
        return false
    end
    if cond_ui.open then
        return self:on_conditions_input(keys)
    end
    if keys.LEAVESCREEN then
        self:feed('LEAVESCREEN')
        return true
    end
    -- number keys can be bound to moving the cursor; a number typed here
    -- with no box open for it must not move the selection to another order
    if typed_digit(keys) or typed(keys, '0') then return true end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.wo_idx = (self.wo_idx or 0) + (dy or 0) + (step or 0)
        self:wo_row()
        return true
    end
    if keys.CUSTOM_Q then
        self:new_work_order()
    elseif keys.CUSTOM_R then
        self:click_wo_button('remove')
    elseif keys.CUSTOM_P then
        -- promote, as it was; P sends it back down
        if (self.wo_idx or 0) > 0 and self:click_wo_button('up') then
            self.wo_idx = self.wo_idx - 1
        end
    elseif keys.CUSTOM_SHIFT_P then
        if (self.wo_idx or 0) < #work_orders() - 1 and self:click_wo_button('down') then
            self.wo_idx = self.wo_idx + 1
        end
    elseif keys.CUSTOM_A then
        self:click_wo_button('amount')
    elseif keys.CUSTOM_T then
        self:click_wo_button('shops')
    elseif keys.CUSTOM_C then
        self.cond_idx = 0
        self:click_wo_button('conditions')
    elseif keys.CUSTOM_D then
        self.rows_idx = 0
        self:click_wo_button('details')
    else
        return plain_letter_pressed(keys)
    end
    return true
end

-- nobles ----------------------------------------------------------------------------
--
-- A row per post, from 7 rows under the tabs. The + that lists candidates
-- is 23 columns on from the post's name; the crown that lists symbols of
-- office is 9 columns left of the middle of the screen but never left of
-- column 68 (measured at grids of 128, 174 and 240 columns). The
-- bookkeeper's precision is set directly: a narrow screen has no room for
-- its buttons.
local function selected_post_code(idx)
    local assignment = admin_ui.spec_prof[idx]
    if not assignment then return end
    for _, position in ipairs(df.global.plotinfo.main.fortress_entity.positions.own) do
        if position.id == assignment.position_id then return position.code end
    end
end

function ClassicKeysOverlay:noble_row()
    local count = #admin_ui.noblelist
    if count == 0 then return end
    local first = info_tabs_row() + 7
    local visible = math.max(1, (gps.dimy - 8 - first) // 3)
    self.noble_idx = math.max(0, math.min(self.noble_idx or 0, count - 1))
    -- (clamped: a scroll the list no longer needs, after the window grew,
    -- is kept by the game but not drawn)
    local scroll = math.max(0, math.min(admin_ui.scroll_position_noblelist, count - visible))
    if self.noble_idx < scroll then
        scroll = self.noble_idx
    elseif self.noble_idx >= scroll + visible then
        scroll = self.noble_idx - visible + 1
    end
    admin_ui.scroll_position_noblelist = scroll
    return first + 3 * (self.noble_idx - scroll)
end

local NOBLE_NAME_X = 6

function ClassicKeysOverlay:on_nobles_input(keys)
    local list = self:info_rows()
    if list then
        local moved = self:rows_input(keys, list)
        if moved then
            if moved == 'chosen' and not admin_ui.assigning_symbol then self.rows_idx = 0 end
            return true
        end
        if admin_ui.assigning_symbol and keys.CUSTOM_X then
            -- x ticks a symbol as Enter does
            return self:rows_input({SELECT=true}, list) ~= nil
        end
        if keys.LEAVESCREEN then
            if not (admin_ui.assigning_symbol and click_label('Done', {x1=gps.dimx // 2, y2=12})) then
                self:feed('LEAVESCREEN')
            end
            self.rows_idx = 0
            return true
        end
        return plain_letter_pressed(keys)
    end
    if keys.LEAVESCREEN then
        self:feed('LEAVESCREEN')
        return true
    end
    -- s steps the bookkeeper's precision and 1 to 5 set it. The digits come
    -- first: number keys can also be bound to moving the cursor.
    local digit = typed_digit(keys)
    if (keys.CUSTOM_S or digit) and selected_post_code(self.noble_idx or 0) == 'BOOKKEEPER' then
        local row = self:noble_row()
        local level = digit and digit - 1 or (df.global.plotinfo.nobles.bookkeeper_settings + 1) % 5
        if row and level >= 0 and level <= 4 then
            -- set directly: on a narrow screen the game has no room to draw
            -- the five buttons at all
            df.global.plotinfo.nobles.bookkeeper_settings = level
        end
        return true
    elseif digit then
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.noble_idx = (self.noble_idx or 0) + (dy or 0) + (step or 0)
        self:noble_row()
        return true
    end
    local row = self:noble_row()
    if not row then return plain_letter_pressed(keys) end
    if keys.CUSTOM_R or keys.SELECT then
        self.rows_idx = 0
        click_screen(NOBLE_NAME_X + 23, row)
    elseif keys.CUSTOM_SHIFT_S then
        self.rows_idx = 0
        -- the symbols button is placed from the middle of the screen, but
        -- never closer in than column 68 (the names keep that much room)
        click_screen(math.max(gps.dimx // 2 - 9, 68), row)
    else
        return plain_letter_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:on_info_input(keys)
    if create_ui.open then
        return self:on_create_order_input(keys)
    end
    local mode = info.current_mode
    -- (not while one of a tab's own lists or boxes is open in front of it)
    local on_tab = not self:info_rows()
        and not (mode == INFO_MODE.WORK_ORDERS and (cond_ui.open or wo_entering_number()))
        and not ClassicKeysOverlay.editing_detail()
    if (keys.CHANGETAB or keys.SEC_CHANGETAB) and on_tab then
        -- Tab and Shift+Tab: the window's own tabs, in the order they are drawn
        local step = keys.SEC_CHANGETAB and -1 or 1
        click_label(INFO_TAB_NAMES[(mode + step) % #INFO_TAB_NAMES + 1], info_tabs_bounds())
        return true
    end
    local tab = on_tab and ClassicKeysOverlay.info_tab_for_key(keys)
    if tab then
        if tab ~= INFO_TAB_NAMES[mode + 1] then click_label(tab, info_tabs_bounds()) end
        return true
    end
    if mode == INFO_MODE.WORK_ORDERS then
        return self:on_work_orders_input(keys)
    elseif mode == INFO_MODE.ADMINISTRATORS then
        return self:on_nobles_input(keys)
    end
    return self:on_widget_list_input(keys)
end

function ClassicKeysOverlay:render_info_markers()
    if mi.job_details.open then return end
    local list = self:info_rows()
    if list then
        self:render_rows(list)
    elseif create_ui.open then
        return
    elseif info.current_mode == INFO_MODE.WORK_ORDERS then
        if cond_ui.open then
            local row = self:cond_row()
            if row then mark_row(5, row, 40) end
        else
            local row = self:wo_row()
            if row then mark_row(11, row, 38) end
        end
    elseif info.current_mode == INFO_MODE.ADMINISTRATORS then
        local row = self:noble_row()
        if row then mark_row(5, row, 28) end
    else
        self:render_widget_list_marker()
    end
end

function ClassicKeysOverlay:info_lines()
    if create_ui.open then
        return 'New order', {
            {{text='type to filter', pen=COLOR_GREY}},
            {hint('- =', 'select')},
            {hint('left right', 'workshop')},
            {hint('Enter', 'order it')},
            {hint('Esc', 'cancel')},
        }
    end
    local mode = info.current_mode
    if mode == INFO_MODE.WORK_ORDERS then
        if wo_entering_number() then
            return 'Number', {
                {{text='type it', pen=COLOR_GREY}},
                {hint('Enter', 'done')},
            }
        elseif cond_ui.open and cond_ui.change_type ~= -1 then
            return 'Choose', {
                {{text='type to filter', pen=COLOR_GREY}},
                {hint('- =', 'select')},
                {hint('Enter', 'choose')},
                {hint('Esc', 'back')},
            }
        elseif cond_ui.open and cond_ui.selecting_order_condition then
            return 'Which order', {
                {hint('- =', 'select')},
                {hint('Enter', 'choose')},
                {hint('Esc', 'back')},
            }
        elseif cond_ui.open then
            return 'Conditions', {
                {hint('- =', 'select')},
                {hint('a', 'add item')},
                {hint('o', 'add order')},
                {hint('1-9', 'add suggested')},
                {hint('f', 'frequency')},
                {{text='item condition:', pen=COLOR_GREY}},
                {hint('i', 'type  '), hint('m', 'material')},
                {hint('t', 'traits  '), hint('n', 'number')},
                {hint('q', 'at least / most')},
                {{text='order condition:', pen=COLOR_GREY}},
                {hint('c', 'done / active')},
                {hint('d', 'delete  '), hint('Esc', 'back')},
            }
        end
        return 'Work orders', {
            {hint('- =', 'select')},
            {hint('q', 'new order')},
            {hint('r', 'remove')},
            {hint('p P', 'move up / down')},
            {hint('a', 'amount')},
            {hint('t', 'max workshops')},
            {hint('c', 'conditions')},
            {hint('d', 'details')},
            {hint('Tab', 'next tab')},
            ClassicKeysOverlay.info_tab_hint(),
            {hint('Esc', 'close')},
        }
    elseif mode == INFO_MODE.ADMINISTRATORS then
        if admin_ui.assigning_symbol then
            return 'Symbols', {
                {hint('- =', 'select')},
                {hint('Enter', 'tick')},
                {hint('Esc', 'done')},
            }
        elseif admin_ui.choosing_candidate then
            return 'Candidates', {
                {hint('- =', 'select')},
                {hint('Enter', 'appoint')},
                {hint('Esc', 'back')},
            }
        end
        return 'Nobles', {
            {hint('- =', 'select')},
            {hint('r', 'replace')},
            {hint('S', 'symbols')},
            {hint('s', 'bookkeeping 1-5')},
            {hint('Tab', 'next tab')},
            ClassicKeysOverlay.info_tab_hint(),
            {hint('Esc', 'close')},
        }
    end
    return self:widget_list_lines()
end
-- for the trade block below: a chunk may hold 200 local names at once, the
-- names of an enclosing block included, so that block cannot sit inside this
-- one and takes what it shares from here
ClassicKeysOverlay.info_helpers = {
    list_visible=list_visible, row_has_text=row_has_text,
    row_text_start=row_text_start, plain_letter_pressed=plain_letter_pressed,
}
end -- of the info window block

-- trading (t on the depot) and moving goods to it (g) -----------------------------
--
do
local helpers = ClassicKeysOverlay.info_helpers
local list_visible, row_has_text = helpers.list_visible, helpers.row_has_text
local row_text_start, plain_letter_pressed = helpers.row_text_start, helpers.plain_letter_pressed
--
-- The trade screen: the merchants' goods on the left and the fort's on the
-- right, each a list of categories and items 3 rows apart with a tick box at
-- its right end (61 columns past the list's text); the lists scroll by screen
-- row, three to an entry. Under them, each side's totals and "Mark all" /
-- "Unmark all", then Seize, Trade and Offer as gift. With more than one
-- caravan in, a list of them comes first.
local trade_ui = mi.trade
local goods_ui = mi.assign_trade

local function trade_list(side)
    -- each side's totals start with a label two columns left of its list
    local x, y = find_screen_text(side == 0 and 'Merchants from' or 'Your fortress', {y1=gps.dimy // 2})
    if not x then return end
    local first = TOP_ROWS + 12
    return {x=x + 2, first=first, visible=math.max(1, (y - first) // 3), unit=3,
            owner=trade_ui.scroll_position_item, scroll=side, click_x=x + 63, bottom=y}
end

local function trade_entering_filter()
    return trade_ui.entering_item_filter[0] or trade_ui.entering_item_filter[1]
end

-- move the selection of a list that scrolls by screen row
local function rows_move(self, list, delta)
    local visible = list_visible(list)
    local idx = math.max(0, math.min(self.rows_idx or 0, visible - 1))
    local target = idx + delta
    local scroll = list.owner[list.scroll]
    if target < 0 then
        list.owner[list.scroll] = math.max(0, scroll + target * 3)
        target = 0
    elseif target >= visible then
        -- only when there is an entry on the last row can there be more
        if row_has_text(list.x, list.first + 3 * (visible - 1)) then
            list.owner[list.scroll] = scroll + (target - visible + 1) * 3
        end
        target = visible - 1
    end
    self.rows_idx = target
end

function ClassicKeysOverlay:on_trade_input(keys)
    if trade_ui.choosing_merchant then
        local x, y = find_screen_text('Select a merchant group', {y2=gps.dimy // 2})
        local count = #trade_ui.merlist
        self.trade_mer_idx = math.max(0, math.min(self.trade_mer_idx or 0, count - 1))
        local dx, dy = self:take_move(keys)
        local step = list_step(keys)
        if dx or step then
            self.trade_mer_idx = math.max(0, math.min(self.trade_mer_idx + sign(dy or 0) + (step or 0), count - 1))
        elseif keys.SELECT then
            if x then
                self.trade_side, self.rows_idx = 0, 0
                click_screen(x + 4, y + 3 + 3 * self.trade_mer_idx)
            end
        elseif keys.LEAVESCREEN then
            self:feed('LEAVESCREEN')
        else
            return plain_letter_pressed(keys)
        end
        return true
    end
    if trade_entering_filter() or trade_ui.entering_amount ~= 0 then
        -- typing: the game takes the keys, bar the Esc that would close all
        if keys.LEAVESCREEN then
            trade_ui.entering_item_filter[0] = false
            trade_ui.entering_item_filter[1] = false
            return true
        end
        return false
    end
    if keys.LEAVESCREEN then
        self:feed('LEAVESCREEN')
        return true
    end
    if trade_ui.counter_offer then
        -- the merchant's counter-offer is the game's own screen
        return plain_letter_pressed(keys)
    end
    self.trade_side = self.trade_side or 0
    local list = trade_list(self.trade_side)
    if not list then return plain_letter_pressed(keys) end
    if keys._STRING == 47 then
        -- "/" filters this side's list; its box is the row above the list
        self.rows_idx = 0
        click_screen(list.x + 10, list.first - 3)
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx and dx ~= 0 and dy == 0 then
        self.trade_side = dx > 0 and 1 or 0
        self.rows_idx = 0
        return true
    elseif dx or step then
        rows_move(self, list, (dy or 0) + (step or 0))
        return true
    end
    local row = list.first + 3 * (self.rows_idx or 0)
    local _, buttons_y = find_screen_text('Offer as gift', {y1=list.bottom})
    if keys.SELECT then
        if row_has_text(list.x, row) then click_screen(list.click_x, row) end
    elseif keys.CUSTOM_T then
        -- "Trade" is also the start of "Trader Profit" two rows up: look only
        -- on the buttons' own row, right of "Seize"
        local sx = buttons_y and find_screen_text('Seize', {y1=buttons_y, y2=buttons_y})
        if sx then click_label('Trade', {y1=buttons_y, y2=buttons_y, x1=sx + 6}) end
    elseif keys.CUSTOM_O then
        click_label('Offer as gift', {y1=list.bottom})
    elseif keys.CUSTOM_S then
        click_label('Seize', {y1=list.bottom})
    elseif keys.CUSTOM_M or keys.CUSTOM_U then
        local mine = find_screen_text('Your fortress', {y1=gps.dimy // 2})
        local bounds = {y1=list.bottom}
        if self.trade_side == 1 then bounds.x1 = mine else bounds.x2 = mine end
        click_label(keys.CUSTOM_M and 'Mark all' or 'Unmark all', bounds)
    elseif keys.CUSTOM_C then
        -- fold or unfold the category under the cursor (its name is a button;
        -- an item's name would tick the item instead)
        if row_text_start(row, list.x, list.x + 3) then click_screen(list.x + 2, row) end
    else
        return plain_letter_pressed(keys)
    end
    return true
end

-- Moving goods to the depot: kinds of item down the left, 3 rows apart from
-- 3 rows under the window's top; the selected kind's items on the right,
-- grouped, with a tick box 35 columns in from the screen's right edge. That
-- list scrolls by screen row. Above it: the filter box, then buttons 49, 45
-- and 41 columns in for "leave out what the merchants will not take",
-- "sort by distance" and "sort by value" (the last two are a pair: each
-- only switches its own order on). Ticks become hauling jobs when the screen
-- is closed.
local GOODS_FIRST = TOP_ROWS + 3

local function goods_list()
    return {x=55, first=GOODS_FIRST + 3, unit=3, owner=goods_ui, scroll='scroll_position_item',
            click_x=gps.dimx - 35}
end

function ClassicKeysOverlay:goods_type_row()
    local count = #goods_ui.filtered_type_list
    if count == 0 then return end
    local visible = math.max(1, (gps.dimy - 4 - GOODS_FIRST) // 3)
    if not self.goods_type_idx then
        -- start on the kind the game has open
        for i, kind in ipairs(goods_ui.filtered_type_list) do
            if kind == goods_ui.current_type then self.goods_type_idx = i end
        end
    end
    self.goods_type_idx = math.max(0, math.min(self.goods_type_idx or 0, count - 1))
    local scroll = math.max(0, goods_ui.scroll_position_type)
    if self.goods_type_idx < scroll then
        scroll = self.goods_type_idx
    elseif self.goods_type_idx >= scroll + visible then
        scroll = self.goods_type_idx - visible + 1
    end
    goods_ui.scroll_position_type = scroll
    return GOODS_FIRST + 3 * (self.goods_type_idx - scroll)
end

function ClassicKeysOverlay:on_goods_input(keys)
    if goods_ui.entering_item_filter then
        if keys.LEAVESCREEN then
            goods_ui.entering_item_filter = false
            return true
        end
        return false
    end
    if keys.LEAVESCREEN then
        self:feed('LEAVESCREEN')
        return true
    end
    self.goods_pane = self.goods_pane or 1
    if keys._STRING == 47 or keys.CUSTOM_S then
        self.goods_pane, self.rows_idx = 2, 0
        click_screen(60, GOODS_FIRST)
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx and dx ~= 0 and dy == 0 then
        self.goods_pane = dx > 0 and 2 or 1
        return true
    end
    if self.goods_pane == 1 then
        if dx or step then
            local before = self.goods_type_idx or 0
            self.goods_type_idx = before + (dy or 0) + (step or 0)
            local row = self:goods_type_row()
            if row and self.goods_type_idx ~= before then
                -- show this kind's items
                click_screen(10, row)
                self.rows_idx = 0
                goods_ui.scroll_position_item = 0
            end
            return true
        elseif keys.SELECT then
            self.goods_pane = 2
            return true
        end
    else
        local list = goods_list()
        if dx or step then
            rows_move(self, list, (dy or 0) + (step or 0))
            return true
        elseif keys.SELECT then
            local row = list.first + 3 * (self.rows_idx or 0)
            if row_has_text(list.x, row) then click_screen(list.click_x, row) end
            return true
        end
    end
    if keys.CUSTOM_M then
        click_screen(gps.dimx - 49, GOODS_FIRST)
    elseif keys.CUSTOM_D then
        -- two buttons, one for each order: by distance, or by value
        click_screen(gps.dimx - (goods_ui.sort_by_distance and 41 or 45), GOODS_FIRST)
    elseif keys.CUSTOM_A then
        -- tick (or untick) everything in the list on show
        click_screen(gps.dimx - 36, GOODS_FIRST)
    else
        return plain_letter_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:trade_lines()
    if goods_ui.open then
        if goods_ui.entering_item_filter then
            return 'Search', {{{text='type, then Enter', pen=COLOR_GREY}}}
        end
        return 'Move goods', {
            {hint('arrows', 'move')},
            {hint('- =', 'up / down')},
            {hint('Enter', 'tick / untick')},
            {hint('s', 'search')},
            {hint('m', 'tradeable only')},
            {hint('a', 'tick all shown')},
            {hint('d', goods_ui.sort_by_distance and 'sort by value' or 'sort by distance')},
            {hint('Esc', 'done')},
        }
    elseif trade_ui.choosing_merchant then
        return 'Trade with', {
            {hint('- =', 'select')},
            {hint('Enter', 'choose')},
            {hint('Esc', 'cancel')},
        }
    elseif trade_entering_filter() then
        return 'Search', {{{text='type, then Enter', pen=COLOR_GREY}}}
    elseif trade_ui.counter_offer then
        return 'Counter-offer', {{{text='use the mouse here', pen=COLOR_GREY}}}
    end
    return 'Trade', {
        {hint('up down', 'move')},
        {hint('left right', 'side')},
        {hint('Enter', 'mark / unmark')},
        {hint('t', 'trade')},
        {hint('o', 'offer as gift')},
        {hint('s', 'seize')},
        {hint('m', 'mark all  '), hint('u', 'none')},
        {hint('c', 'fold category')},
        {hint('/', 'search')},
        {hint('Esc', 'done')},
    }
end

function ClassicKeysOverlay:render_trade_markers()
    if goods_ui.open then
        if (self.goods_pane or 1) == 1 then
            local row = self:goods_type_row()
            if row then mark_row(7, row, 30) end
        else
            self:render_rows(goods_list())
        end
    elseif trade_ui.choosing_merchant then
        local x, y = find_screen_text('Select a merchant group', {y2=gps.dimy // 2})
        if x then mark_row(x - 1, y + 3 + 3 * (self.trade_mer_idx or 0), 40) end
    elseif not trade_ui.counter_offer then
        local list = trade_list(self.trade_side or 0)
        if list then self:render_rows(list) end
    end
end

end -- of the trade block

-- the other info tabs: creatures, labor, justice -------------------------------------
--
-- These tabs are built from the game's newer widgets, which carry names and
-- their place on screen: a tab bar (widget_tabs, cur_idx) holds the pages,
-- and a list is a widget_scroll_rows (scroll, num_visible) whose children are
-- the rows, each with its buttons as named children ("Unit sheet button",
-- "Recenter button"...). So nothing here is counted in columns: the lists on
-- show are found by walking the tab's widgets, and a button is clicked in the
-- middle of its own rectangle.
do
local helpers = ClassicKeysOverlay.info_helpers
local row_text_start, plain_letter_pressed = helpers.row_text_start, helpers.plain_letter_pressed
local info = mi.info
local MODE = df.info_interface_mode_type
local widget_children = dfhack.gui.getWidgetChildren

local function kind(widget)
    return tostring(widget._type):match('<type: (.-)>') or ''
end

local function kids(widget)
    local ok, list = pcall(widget_children, widget)
    return ok and list or {}
end

-- the lists on show under `widget` and the tab bars leading to them
local function walk(widget, found, depth)
    found = found or {lists={}, tabs={}, boxes={}}
    depth = depth or 0
    if depth > 12 then return found end
    local k = kind(widget)
    if k == 'widget_scroll_rows' then
        found.lists[#found.lists + 1] = {rows=widget}
        return found
    elseif k == 'widget_radio_rows' then
        -- a list where one row is the chosen one (selected_idx), with what
        -- is shown beside it depending on the choice
        found.lists[#found.lists + 1] = {rows=widget.rows, radio=widget}
        return found
    elseif k == 'widget_textbox' then
        -- a box to type in: a list's filter, or a name. Once clicked, the
        -- game takes the keyboard until Enter
        found.boxes[#found.boxes + 1] = widget
        return found
    end
    local list = kids(widget)
    if k == 'widget_tabs' then
        found.tabs[#found.tabs + 1] = widget
        local current = list[widget.cur_idx + 1]
        if current then walk(current, found, depth + 1) end
        return found
    end
    for _, child in ipairs(list) do
        -- a stack shows one of its children at a time
        if k ~= 'widget_stack' or child.flag.VISIBILITY_VISIBLE then
            walk(child, found, depth + 1)
        end
    end
    return found
end

local function survey(root)
    local found = walk(root)
    -- left to right, as they are on screen
    table.sort(found.lists, function(a, b) return a.rows.rect.x1 < b.rows.rect.x1 end)
    return found
end

local function widget_root()
    local mode = info.current_mode
    if mode == MODE.CREATURES then return info.creatures end
    if mode == MODE.LABOR then return info.labor end
    if mode == MODE.JUSTICE then return info.justice end
end

local function named_child(widget, name)
    for _, child in ipairs(kids(widget)) do
        if child.name == name then return child end
    end
end

local function click_widget(widget)
    local rect = widget.rect
    click_screen((rect.x1 + rect.x2) // 2, (rect.y1 + rect.y2) // 2)
end

-- The headings a list can be sorted by: the named labels above its rows
-- ("Name", "Job", "Stress"...), left to right. A click on one sorts by it and
-- a second click reverses the order.
local function sort_headers(rows)
    local out = {}
    local ok, tbl = pcall(function() return rows.parent end)
    if not ok or not tbl or kind(tbl) ~= 'widget_table' then return out end
    local function gather(widget, depth)
        for _, child in ipairs(kids(widget)) do
            if #child.name > 0 then
                out[#out + 1] = child
            elseif depth < 3 then
                gather(child, depth + 1)
            end
        end
    end
    local labels = kids(tbl)[1]
    if labels and kind(labels) == 'widget_columns_container' then gather(labels, 0) end
    table.sort(out, function(a, b) return a.rect.x1 < b.rect.x1 end)
    return out
end

-- The selected row of the list in front, scrolled into view. Selections are
-- kept per page (the tab indexes down to it) and per list on the page.
function ClassicKeysOverlay:wl_row(found)
    local key = tostring(info.current_mode)
    for _, tabs in ipairs(found.tabs) do key = key .. '/' .. tabs.cur_idx end
    if self.wl_key ~= key then
        self.wl_key, self.wl_pane, self.wl_idx = key, 1, {}
    end
    self.wl_pane = math.max(1, math.min(self.wl_pane or 1, #found.lists))
    local pane = found.lists[self.wl_pane]
    if not pane then return end
    local rows = pane.rows
    local list = kids(rows)
    if #list == 0 then return nil, rows, 0 end
    -- a list of choices starts on the game's own choice
    if pane.radio and not self.wl_idx[self.wl_pane] then
        self.wl_idx[self.wl_pane] = pane.radio.selected_idx
    end
    local idx = math.max(0, math.min(self.wl_idx[self.wl_pane] or 0, #list - 1))
    self.wl_idx[self.wl_pane] = idx
    local visible = math.max(1, rows.num_visible)
    if idx < rows.scroll then
        rows.scroll = idx
    elseif idx >= rows.scroll + visible then
        rows.scroll = idx - visible + 1
    end
    return list[idx + 1], rows, #list, pane.radio
end

-- choose the selected row of a list of choices, as a click on it does; the
-- row may only just have been scrolled into view, so its place is read again
-- once the list has been redrawn
function ClassicKeysOverlay:wl_choose(root)
    dfhack.timeout(10, 'frames', function()
        if not info.open or widget_root() ~= root then return end
        local row, _, _, radio = self:wl_row(survey(root))
        if row and radio and radio.selected_idx ~= self.wl_idx[self.wl_pane] then
            click_screen(row.rect.x1 + 4, row.rect.y1 + 1)
        end
    end)
end

local function switch_tab(tabs, delta, wrap)
    local count = #kids(tabs)
    if count == 0 then return end
    local idx = tabs.cur_idx + delta
    if wrap then idx = idx % count else idx = math.max(0, math.min(idx, count - 1)) end
    if idx == tabs.cur_idx then return end
    -- the page is filled in when its label is clicked; the labels are the
    -- pages' names, on the two rows the tab bar starts with
    local page = kids(tabs)[idx + 1]
    local bounds = {y1=tabs.rect.y1, y2=tabs.rect.y1 + 1}
    if not (page and #page.name > 0 and click_label(page.name, bounds)) then
        tabs.cur_idx = idx
    end
end

-- what Enter does on a row: open the creature's sheet where there is one,
-- otherwise click the row itself
local function activate_row(row)
    -- in a work detail's list of dwarves: the box that puts them on it
    local button = named_child(row, 'Selected') or named_child(row, 'Unit sheet button')
    if button then
        click_widget(button)
    else
        click_screen(row.rect.x1 + 12, row.rect.y1 + 1)
    end
end

-- The tabs and pages that are not built from widgets (tasks, places, objects,
-- and labor's standing orders and stone use): rows 3 apart under one or two
-- rows of tab labels. Where the game keeps the list's length the selection
-- is an entry and the list is scrolled to it; where it does not (standing
-- orders), the selection is a row on screen.
local function raw_plain_list()
    -- counted from the last line of the window's tabs (see info_tabs_row)
    local top = ClassicKeysOverlay.info_tabs_row()
    local mode = info.current_mode
    if mode == MODE.JOBS then
        -- A task's buttons: zoom to the job at column 32 and (with no
        -- worker) view its building at 35; for workshop jobs, take the
        -- worker off at 41, suspend at 44 and cancel at 47; the worker's own
        -- zoom and sheet at 89 and 92.
        return {title='Tasks', first=top + 4, x=6, count=#info.jobs.cri_job,
                owner=info.jobs, field='scroll_position_cri_job', zoom_x=32,
                base=function(idx)
                    local entry = info.jobs.cri_job[idx]
                    return entry and entry.un and 92 or 35
                end}
    elseif mode == MODE.BUILDINGS then
        local places = info.buildings
        return {title='Places', first=top + 6, x=13, count=#places.list[places.mode], places=true,
                owner=places.scrolling_position, field=places.mode, zoom_x=82, icons_found=true,
                tabs_row=top + 2, tab=places.mode,
                tabs={'Zones', 'Locations', 'Stockpiles', 'Workshops', 'Farm plots', 'Siege engines'}}
    elseif mode == MODE.ARTIFACTS then
        local objects = info.artifacts
        return {title='Objects', first=top + 6, x=13, count=#objects.list[objects.mode],
                owner=objects.scroll_position, field=objects.mode,
                tabs_row=top + 2, tab=objects.mode,
                tabs={'Artifacts', 'Symbols', 'Named objects', 'Written content'}}
    elseif mode == MODE.LABOR then
        local pages = kids(info.labor)[1]
        local page = pages and kids(pages)[pages.cur_idx + 1]
        if not page then return end
        if pages.cur_idx == 0 then
            -- A work detail's own editor (the gear beside its name) takes the
            -- place of its dwarves: "Done" and "Delete" above a list of the
            -- labors it covers, grouped under headings, 3 rows apart. The
            -- list has no scroll field; the game's page keys move it a row.
            local editor = kids(named_child(page, 'Right panel') or page)[2]
            if not (editor and editor.flag.VISIBILITY_VISIBLE) then return end
            local buttons = kids(editor)
            return {title='Detail labors', first=top + 9, x=39, toggles=true, feed_scroll=true,
                    back=buttons[1], delete=buttons[2], tab=0,
                    detail=function()
                        local chosen = named_child(page, 'Details')
                        return chosen and df.global.plotinfo.labor_info.work_details[chosen.selected_idx]
                    end}
        elseif pages.cur_idx == 1 then
            local tabs = {'Workshops', 'Hauling', 'Refuse', 'Forbidding', 'Petitions', 'Chores', 'Other'}
            if page.current_category == 5 then
                -- Chores: the fort's children on the left and the chores on
                -- the right, each row ending in a tick box, under the two
                -- "Children do / don't do chores" buttons. The page is split
                -- at the middle of the screen: the children's names start at
                -- column 13 and their tick boxes 17 left of the middle; the
                -- chores start 8 left of it and their tick boxes are 32 from
                -- the right edge (the same at grids of 174 and 240 columns).
                local middle = gps.dimx // 2
                local pane = ClassicKeysOverlay.chore_pane or 0
                if #page.unit == 0 then pane = 1 end
                local list = {toggles=true, first=top + 12, tabs_row=top + 4, tab=5, outer=pages,
                              tabs=tabs, owner=page, chores=pane, children=#page.unit}
                if pane == 0 then
                    list.title, list.x, list.enter_x = 'Chores: children', 13, middle - 17
                    list.count, list.field = #page.unit, 'scroll_position_units'
                else
                    list.title, list.x, list.enter_x = 'Chores', middle - 8, gps.dimx - 32
                    list.count, list.field = #page.labor_list, 'scroll_position_labor_list'
                end
                return list
            end
            return {title='Standing orders', first=top + 8, x=8, toggles=true,
                    tabs_row=top + 4, tab=page.current_category, outer=pages, tabs=tabs}
        elseif pages.cur_idx == 3 then
            local category = page.current_category
            return {title='Stone use', first=top + 10, x=13, toggles=true,
                    count=#page.stone_mg_index[category], owner=page.scroll_position, field=category,
                    tabs_row=top + 4, tab=category, outer=pages,
                    tabs={'Economic stone', 'Other stone'}}
        end
    end
end

local function plain_list()
    return ClassicKeysOverlay.fit_to_tabs(raw_plain_list())
end

-- the first tile on a row, from x on, that is a picture rather than the
-- row's own background or text
function ClassicKeysOverlay.first_picture_x(y, from)
    local plain
    for x = from, gps.dimx - 2 do
        local tile = dfhack.screen.readTile(x, y)
        if tile and (tile.ch or 0) <= 32 then
            if not plain then
                plain = tile.tile
            elseif tile.tile ~= plain then
                return x
            end
        end
    end
end

-- A list under a row of sub-tabs (Zones / Locations / ..., Workshops /
-- Hauling / ...): those wrap on a narrow screen too, so the rows they take
-- are found and the list moved down by as much.
function ClassicKeysOverlay.fit_to_tabs(list)
    if not list or not list.tabs or not list.tabs_row then return list end
    local lo, hi
    for _, name in ipairs(list.tabs) do
        local _, y = find_screen_text(name, {y1=list.tabs_row - 1, y2=list.tabs_row + 8, x2=gps.dimx - 30})
        if y then
            lo = math.min(lo or y, y)
            hi = math.max(hi or y, y)
        end
    end
    if lo then
        list.first = list.first + (hi - list.tabs_row)
        list.tabs_bounds = {y1=lo, y2=hi + 1}
    end
    return list
end

-- the screen row of the selection, scrolled into view
function ClassicKeysOverlay:plain_row(list)
    local key = list.title .. '/' .. tostring(list.tab)
    if self.pl_key ~= key then self.pl_key, self.pl_idx = key, 0 end
    local visible = math.max(1, (gps.dimy - 5 - list.first) // 3)
    local idx = math.max(0, self.pl_idx or 0)
    if list.count then
        if list.count == 0 then return end
        idx = math.min(idx, list.count - 1)
        local scroll = math.max(0, math.min(list.owner[list.field], list.count - visible))
        if idx < scroll then
            scroll = idx
        elseif idx >= scroll + visible then
            scroll = idx - visible + 1
        end
        list.owner[list.field] = scroll
        self.pl_idx = idx
        return list.first + 3 * (idx - scroll)
    end
    idx = math.min(idx, visible - 1)
    while idx > 0 and not row_text_start(list.first + 3 * idx, list.x, list.x + 30) do
        idx = idx - 1
    end
    self.pl_idx = idx
    return list.first + 3 * idx
end

function ClassicKeysOverlay:on_plain_list_input(keys, list)
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx and dx ~= 0 and dy == 0 then
        if math.abs(dx) > 1 and list.outer then
            -- Shift+Left / Right: labor's pages
            switch_tab(list.outer, sign(dx), false)
        elseif list.chores and ((dx > 0 and list.chores == 0)
            or (dx < 0 and list.chores == 1 and list.children > 0))
        then
            -- chores: from the children to the chores and back
            ClassicKeysOverlay.chore_pane = 1 - list.chores
        elseif list.tabs then
            local name = list.tabs[list.tab + 1 + sign(dx)]
            if name then
                -- arriving at the chores from the right lands on its right list
                if name == 'Chores' then ClassicKeysOverlay.chore_pane = dx > 0 and 0 or 1 end
                click_label(name, list.tabs_bounds or {y1=list.tabs_row, y2=list.tabs_row + 1})
            end
        end
        return true
    elseif dx or step then
        self:plain_row(list)
        local target = (self.pl_idx or 0) + (dy or 0) + (step or 0)
        if list.feed_scroll then
            -- no scroll field to set: ask the game to scroll, a row at a time
            local visible = math.max(1, (gps.dimy - 5 - list.first) // 3)
            for _ = 1, math.min(30, -target) do self:feed('STANDARDSCROLL_PAGEUP') end
            for _ = 1, math.min(30, target - visible + 1) do self:feed('STANDARDSCROLL_PAGEDOWN') end
        end
        self.pl_idx = target
        self:plain_row(list)
        return true
    end
    local row = self:plain_row(list)
    if not row or not row_text_start(row, list.x, list.x + 30) then
        return plain_letter_pressed(keys)
    end
    local base = list.base and list.base(self.pl_idx or 0)
    if keys.CUSTOM_I and list.detail then
        -- the next of the game's icons for a work detail
        local detail = list.detail()
        if detail and not detail.flags.no_modify then
            detail.icon = (detail.icon + 1) % (df.work_detail_icon_type._last_item + 1)
        end
    elseif keys.CUSTOM_SHIFT_D and list.delete then
        ClassicKeysOverlay.click_rect(list.delete)
    elseif base and (keys.SELECT or keys.CUSTOM_V) then
        click_screen(base, row)
    elseif base and keys.CUSTOM_S then
        click_screen(44, row)
    elseif base and keys.CUSTOM_X then
        click_screen(47, row)
    elseif base and keys.CUSTOM_R then
        click_screen(41, row)
    elseif base and keys.CUSTOM_P then
        -- repeat, for a workshop job: set on the job itself
        local entry = info.jobs.cri_job[self.pl_idx or 0]
        local job = entry and entry.jb
        local holder = job and dfhack.job.getHolder(job)
        if holder and (df.building_workshopst:is_instance(holder) or df.building_furnacest:is_instance(holder)) then
            job.flags['repeat'] = not job.flags['repeat']
        end
    elseif keys.CUSTOM_C and list.chores then
        -- whether children do chores at all: the button that is not lit
        local on = df.global.plotinfo.labor_info.flags.children_do_chores
        click_label(on and 'Children don' or 'Children do chores', {y1=list.first - 4, y2=list.first - 4})
    elseif list.chores and (keys.SELECT or keys.CUSTOM_V) then
        -- the row's tick box: the first picture after the name (it moves
        -- left when the list has a scroll bar)
        local x = ClassicKeysOverlay.first_picture_x(row, list.x + 1)
        if x then click_screen(x + 1, row) end
    elseif list.icons_found and (keys.SELECT or keys.CUSTOM_V or keys.CUSTOM_Z or keys.CUSTOM_C) then
        -- A place's two buttons (zoom, then open) are the first pictures on
        -- its row after the text; where they stand depends on the width of
        -- the screen, so they are found on the row.
        local zoom_x = ClassicKeysOverlay.first_picture_x(row, list.x + 20)
        if zoom_x then
            click_screen(zoom_x + ((keys.CUSTOM_Z or keys.CUSTOM_C) and 1 or 4), row)
            if keys.SELECT or keys.CUSTOM_V then
                -- a zone, location or stockpile opens its own panel on the map
                dfhack.timeout(2, 'frames', function() self:query_opened_panel() end)
            end
        end
    elseif keys.SELECT or keys.CUSTOM_V then
        click_screen(list.enter_x or (list.x + 2), row)
        if list.places then
            -- a zone, location or stockpile opens its own panel on the map
            dfhack.timeout(2, 'frames', function() self:query_opened_panel() end)
        end
    elseif (keys.CUSTOM_Z or keys.CUSTOM_C) and list.zoom_x then
        click_screen(list.zoom_x, row)
    else
        return plain_letter_pressed(keys)
    end
    return true
end

-- the kitchen: c and b switch cooking and brewing of the selected kind of
-- food, the two buttons at the end of its row; Left / Right step through the
-- categories with the arrows either side of the category's name
local function kitchen_page()
    if info.current_mode ~= MODE.LABOR then return end
    local pages = kids(info.labor)[1]
    if pages and pages.cur_idx == 2 then return kids(pages)[3] end
end

function ClassicKeysOverlay.kitchen_arrow(page, delta)
    local node = named_child(page, 'Table')
    for _, i in ipairs{1, 2, 1} do
        node = node and kids(node)[i]
    end
    local arrow = node and kids(node)[delta < 0 and 1 or 3]
    if arrow then click_widget(arrow) end
end

-- justice: i and c are the "Interrogate" and "Convict" buttons of the case
function ClassicKeysOverlay.justice_button(index)
    local pages = kids(info.justice)[1]
    local page = pages and kids(pages)[pages.cur_idx + 1]
    local node = page and named_child(page, 'Right panel')
    for _, i in ipairs{1, 2} do
        node = node and kids(node)[i]
    end
    local button = node and kids(node)[index]
    if button then click_widget(button) end
    return button ~= nil
end

-- The convict and interrogate lists take the place of the case's reports and
-- have no way back of their own (the game's Esc closes the whole window); a
-- click on the case they were opened from brings its reports back.
function ClassicKeysOverlay.justice_back()
    local pages = kids(info.justice)[1]
    local page = pages and kids(pages)[pages.cur_idx + 1]
    local stack = page and named_child(page, 'Right panel')
    local cases = page and named_child(page, 'Cases')
    if not stack or not cases or #kids(stack) < 2 then return false end
    local row = kids(cases.rows)[cases.selected_idx + 1]
    if not row then return false end
    click_screen(row.rect.x1 + 4, row.rect.y1 + 1)
    return true
end

-- a work detail's editor is open: its labor list is the list in front, not
-- the list of details still on show beside it
function ClassicKeysOverlay.editing_detail()
    local list = info.current_mode == MODE.LABOR and plain_list()
    return list ~= nil and list ~= false and list.back ~= nil
end

function ClassicKeysOverlay.click_rect(widget)
    local rect = widget.rect
    click_screen((rect.x1 + rect.x2) // 2, (rect.y1 + rect.y2) // 2)
end

function ClassicKeysOverlay:on_widget_list_input(keys)
    if keys.LEAVESCREEN then
        if info.current_mode == MODE.JUSTICE and ClassicKeysOverlay.justice_back() then
            self.wl_pane = 1
            return true
        end
        -- a work detail's editor closes with its own "Done"
        local editor = info.current_mode == MODE.LABOR and plain_list()
        if editor and editor.back then
            ClassicKeysOverlay.click_rect(editor.back)
            return true
        end
        self:feed('LEAVESCREEN')
        return true
    end
    local root = widget_root()
    local found = root and survey(root) or {lists={}, tabs={}, boxes={}}
    if #found.lists == 0 or ClassicKeysOverlay.editing_detail() then
        local list = plain_list()
        if list then return self:on_plain_list_input(keys, list) end
        return plain_letter_pressed(keys)
    end
    local row, rows, count, radio = self:wl_row(found)
    local kitchen = kitchen_page()
    if keys._STRING == 47 then
        -- "/" types into the list's filter box
        for _, box in ipairs(found.boxes) do
            if box.name == 'Filter box' then
                click_widget(box)
                break
            end
        end
        return true
    end
    -- work details: a adds one, n names the chosen one, 1 2 3 set who does it
    local details = info.current_mode == MODE.LABOR and found.tabs[1] and found.tabs[1].cur_idx == 0
    if details then
        local modes = {'Everybody does this', 'Only selected do this', 'Nobody does this'}
        local digit = keys._STRING and keys._STRING - 48
        if keys.CUSTOM_A then
            click_label('Add new work detail', {y2=gps.dimy // 2})
            return true
        elseif keys.CUSTOM_SHIFT_N then
            for _, box in ipairs(found.boxes) do
                if box.name ~= 'Filter box' then
                    click_widget(box)
                    break
                end
            end
            return true
        elseif digit and modes[digit] then
            click_label(modes[digit], {y2=gps.dimy // 2})
            return true
        elseif keys.CUSTOM_C then
            -- labors per dwarf, as they used to be (scripts/classic-labors.lua).
            -- (M on this page is DFHack's own "Labor automation" switch; L is
            -- the Objects tab.)
            local labors = reqscript('classic-labors')
            if labors.automation_running() then
                dialogs.showMessage('Classic labors',
                    "DFHack's labor automation is running (M on this page).\n"
                    .. 'Switch that off first: the two cannot both set labors.')
            elseif labors.is_on() then
                dialogs.showYesNoPrompt('Classic labors',
                    'Hand labors back to the work details?\n\n'
                    .. 'The game assigns them again the next time\na work detail is changed.',
                    COLOR_WHITE, function()
                        labors.switch_off()
                        self.classic_labors_on = false
                    end)
            else
                dialogs.showYesNoPrompt('Classic labors',
                    'Set the work details aside and leave each dwarf\n'
                    .. 'only the skilled labors it is at least a novice in?\n\n'
                    .. 'Hauling, cleaning, building and the other work\n'
                    .. 'that needs no skill is switched on for all.\n'
                    .. 'A labor nobody is a novice at ends up with\n'
                    .. 'nobody: give it to someone in Dwarf Therapist.',
                    COLOR_WHITE, function()
                        local dwarves, changes, empty = labors.switch_on()
                        self.classic_labors_on = true
                        dialogs.showMessage('Classic labors',
                            ('%d labor settings changed on %d dwarves.\n%d skilled labors now have nobody.')
                                :format(changes, dwarves, #empty))
                    end)
            end
            return true
        elseif keys.CUSTOM_E then
            -- the gear just past the detail's name box: its labors and icon
            for _, box in ipairs(found.boxes) do
                if box.name ~= 'Filter box' then
                    self.pl_idx = 0
                    click_screen(box.rect.x2 + 2, box.rect.y1 + 1)
                    break
                end
            end
            return true
        end
    end
    if keys.CUSTOM_T or keys.CUSTOM_SHIFT_T then
        -- t sorts by the next column heading; T by the same one again, which
        -- turns the order round
        local headers = rows and sort_headers(rows) or {}
        if #headers > 0 then
            local key = tostring(self.wl_key) .. '/' .. tostring(self.wl_pane)
            if self.sort_key ~= key then self.sort_key, self.sort_idx = key, 0 end
            if keys.CUSTOM_T then
                self.sort_idx = self.sort_idx % #headers + 1
            elseif self.sort_idx == 0 then
                self.sort_idx = 1
            end
            click_widget(headers[self.sort_idx])
            self.wl_idx[self.wl_pane] = 0
            rows.scroll = 0
        end
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx and math.abs(dx) > 1 and dy == 0 then
        -- Shift+Left / Right: the pages of the first row of tabs
        if found.tabs[1] then switch_tab(found.tabs[1], sign(dx), false) end
        return true
    elseif dx and dx ~= 0 and dy == 0 and kitchen then
        ClassicKeysOverlay.kitchen_arrow(kitchen, dx)
        return true
    elseif dx and dx ~= 0 and dy == 0 then
        if #found.lists > 1 then
            -- several lists side by side: move between them
            self.wl_pane = math.max(1, math.min(self.wl_pane + sign(dx), #found.lists))
        elseif #found.tabs > 0 then
            switch_tab(found.tabs[#found.tabs], sign(dx), false)
        end
        return true
    elseif dx or step then
        if rows then
            self.wl_idx[self.wl_pane] = (self.wl_idx[self.wl_pane] or 0) + (dy or 0) + (step or 0)
            local _, _, _, radio = self:wl_row(found)
            if radio then self:wl_choose(root) end
        end
        return true
    end
    if not row then return plain_letter_pressed(keys) end
    if kitchen and (keys.CUSTOM_C or keys.CUSTOM_B) then
        local buttons = kids(kids(row)[4] or row)
        local button = buttons[keys.CUSTOM_C and 1 or 2]
        if button then click_widget(button) end
    elseif info.current_mode == MODE.JUSTICE and (keys.CUSTOM_I or keys.CUSTOM_C) then
        ClassicKeysOverlay.justice_button(keys.CUSTOM_I and 1 or 2)
    elseif keys.SELECT and radio then
        -- already chosen by moving onto it: go on to the list beside it
        if #found.lists > 1 then self.wl_pane = self.wl_pane % #found.lists + 1 end
    elseif keys.SELECT and info.current_mode == MODE.JUSTICE then
        -- a report has nothing to open; in the convict and interrogate lists
        -- the row itself is the choice
        click_screen(row.rect.x1 + 12, row.rect.y1 + 1)
    elseif keys.SELECT then
        activate_row(row)
    elseif keys.CUSTOM_V then
        local button = named_child(row, 'Unit sheet button')
        if button then click_widget(button) end
    elseif keys.CUSTOM_Z or keys.CUSTOM_C then
        local button = named_child(row, 'Recenter button')
        if button then click_widget(button) end
    elseif keys.CUSTOM_S then
        local button = named_child(row, 'Specialization button')
        if button then click_widget(button) end
    else
        return plain_letter_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:widget_list_lines()
    local root = widget_root()
    local found = root and survey(root) or {lists={}, tabs={}, boxes={}}
    if #found.lists == 0 or ClassicKeysOverlay.editing_detail() then
        local list = plain_list()
        if not list then return end
        local lines = {{hint('- =', 'select')}}
        lines[#lines + 1] = {hint('Enter', list.toggles and 'switch' or 'open')}
        if list.zoom_x then lines[#lines + 1] = {hint('z', 'zoom to')} end
        if list.delete then lines[#lines + 1] = {hint('D', 'delete detail')} end
        if list.detail then lines[#lines + 1] = {hint('i', 'next icon')} end
        if list.base then
            lines[#lines + 1] = {hint('s', 'suspend job')}
            lines[#lines + 1] = {hint('x', 'cancel job')}
            lines[#lines + 1] = {hint('r', 'remove worker')}
            local idx = self.pl_idx or 0
            local entry = idx < #info.jobs.cri_job and info.jobs.cri_job[idx]
            local job = entry and entry.jb
            lines[#lines + 1] = {hint('p', job and job.flags['repeat'] and 'repeat: on' or 'repeat job')}
        end
        if list.chores then
            local on = df.global.plotinfo.labor_info.flags.children_do_chores
            lines[#lines + 1] = {hint('c', on and 'children: do chores' or 'children: no chores')}
            lines[#lines + 1] = {hint('left right', 'list / page')}
        elseif list.tabs then
            lines[#lines + 1] = {hint('left right', 'page')}
        end
        if list.outer then lines[#lines + 1] = {hint('Shift+l/r', 'section')} end
        lines[#lines + 1] = {hint('Tab', 'next tab')}
        lines[#lines + 1] = ClassicKeysOverlay.info_tab_hint()
        lines[#lines + 1] = {hint('Esc', 'close')}
        return list.title, lines
    end
    local lines = {
        {hint('- =', 'select')},
        {hint('Enter', 'open / tick')},
    }
    if kitchen_page() then
        lines = {
            {hint('- =', 'select')},
            {hint('c', 'cook  '), hint('b', 'brew')},
            {hint('left right', 'category')},
            {hint('Shift+l/r', 'section')},
            {hint('Tab', 'next tab')},
            ClassicKeysOverlay.info_tab_hint(),
            {hint('Esc', 'close')},
        }
        return 'Kitchen', lines
    elseif info.current_mode == MODE.JUSTICE then
        lines[#lines + 1] = {hint('i', 'interrogate')}
        lines[#lines + 1] = {hint('c', 'convict')}
    elseif info.current_mode == MODE.LABOR then
        lines[#lines + 1] = {hint('a', 'add detail')}
        lines[#lines + 1] = {hint('N', 'name it')}
        lines[#lines + 1] = {hint('1 2 3', 'all/some/none')}
        lines[#lines + 1] = {hint('e', 'its labors')}
        if self.classic_labors_on then
            lines[#lines + 1] = {{text='details set aside:', pen=COLOR_LIGHTRED}}
            lines[#lines + 1] = {hint('c', 'labors per dwarf')}
        else
            lines[#lines + 1] = {hint('c', 'classic labors')}
        end
    else
        lines[#lines + 1] = {hint('z', 'zoom to  '), hint('v', 'view')}
    end
    lines[#lines + 1] = {hint('/', 'search')}
    local _, rows = self:wl_row(found)
    local headers = rows and sort_headers(rows) or {}
    if #headers > 0 then
        local key = tostring(self.wl_key) .. '/' .. tostring(self.wl_pane)
        local current = self.sort_key == key and headers[self.sort_idx or 0]
        lines[#lines + 1] = {hint('t', current and ('sorted by ' .. current.name) or 'sort by column')}
        lines[#lines + 1] = {hint('T', 'reverse order')}
    end
    if #found.lists > 1 then
        lines[#lines + 1] = {hint('left right', 'list')}
        lines[#lines + 1] = {hint('Shift+l/r', 'page')}
    elseif #found.tabs > 1 then
        lines[#lines + 1] = {hint('left right', 'page')}
        lines[#lines + 1] = {hint('Shift+l/r', 'section')}
    elseif #found.tabs == 1 then
        lines[#lines + 1] = {hint('left right', 'page')}
    end
    lines[#lines + 1] = {hint('Tab', 'next tab')}
    lines[#lines + 1] = ClassicKeysOverlay.info_tab_hint()
    lines[#lines + 1] = {hint('Esc', 'close')}
    local titles = {[MODE.CREATURES]='Creatures', [MODE.LABOR]='Labor', [MODE.JUSTICE]='Justice'}
    return titles[info.current_mode] or 'List', lines
end

function ClassicKeysOverlay:render_widget_list_marker()
    local root = widget_root()
    local found = root and survey(root) or {lists={}, tabs={}, boxes={}}
    if #found.lists == 0 or ClassicKeysOverlay.editing_detail() then
        local list = plain_list()
        local y = list and self:plain_row(list)
        local start = y and row_text_start(y, list.x, list.x + 30)
        if start then mark_row(start - 1, y, 44) end
        return
    end
    local row = self:wl_row(found)
    if not row then return end
    local rect = row.rect
    for y = rect.y1, rect.y2 do
        local start = row_text_start(y, rect.x1, rect.x1 + 40)
        if start then
            mark_row(start - 1, y, 44)
            return
        end
    end
end

-- announcements (a) ------------------------------------------------------------------------
--
-- The game's own window: a row of category tabs over a list of announcements,
-- oldest first, each with a "zoom" button. It is the same kind of list as the
-- creatures tab, so it is worked the same way; it opens on the latest entry,
-- as the old screen did.
function ClassicKeysOverlay.announcement_widgets()
    local found = survey(mi.announcements.stack)
    local tabs = found.tabs[1]
    local rows = found.lists[1] and found.lists[1].rows
    return tabs, rows, rows and kids(rows) or {}
end

-- A click on a fight's announcement puts its report in front of the list: a
-- second child of the window's stack, whose lines are a list of their own.
-- That list is only held as a shared pointer, which is read as the address
-- it starts with.
function ClassicKeysOverlay.report_popup_rows()
    for _, child in ipairs(kids(mi.announcements.stack)) do
        if kind(child) == 'widget_report_popup' and child.flag.VISIBILITY_VISIBLE then
            local _, addr = child.texts:sizeof()
            local raw = df.reinterpret_cast('uint64_t', addr).value
            if raw ~= 0 then return df.reinterpret_cast(df.widget_scroll_rows, raw) end
        end
    end
end

-- the selected row, scrolled into view
function ClassicKeysOverlay:announcement_row()
    local tabs, rows, list = ClassicKeysOverlay.announcement_widgets()
    if not tabs or not rows then return end
    if self.an_tab ~= tabs.cur_idx then
        -- each category keeps its own place for as long as the window is open
        self.an_saved = self.an_saved or {}
        if self.an_tab then self.an_saved[self.an_tab] = self.an_idx end
        self.an_tab, self.an_idx = tabs.cur_idx, self.an_saved[tabs.cur_idx]
    end
    if #list == 0 then return nil, rows, tabs, 0 end
    local idx = math.max(0, math.min(self.an_idx or (#list - 1), #list - 1))
    self.an_idx = idx
    local visible = math.max(1, rows.num_visible)
    if idx < rows.scroll then
        rows.scroll = idx
    elseif idx >= rows.scroll + visible then
        rows.scroll = idx - visible + 1
    end
    return list[idx + 1], rows, tabs, #list
end

function ClassicKeysOverlay:on_announcements_input(keys)
    if keys.LEAVESCREEN then
        self:feed('LEAVESCREEN')
        return true
    end
    local text = ClassicKeysOverlay.report_popup_rows()
    if text then
        -- a fight's report: the keys scroll its text
        local visible = math.max(1, text.num_visible)
        local last = math.max(0, #kids(text) - visible)
        local to = text.scroll
        if keys.STANDARDSCROLL_PAGEDOWN and keys._STRING ~= 47 then
            to = to + visible - 1
        elseif keys.STANDARDSCROLL_PAGEUP then
            to = to - visible + 1
        elseif keys.CUSTOM_HOME then
            to = 0
        elseif keys.CUSTOM_END then
            to = last
        else
            local dx, dy = self:take_move(keys)
            local step = list_step(keys)
            if not dx and not step then return plain_letter_pressed(keys) end
            to = to + (dy or 0) + (step or 0)
        end
        text.scroll = math.max(0, math.min(to, last))
        return true
    end
    local row, rows, tabs, count = self:announcement_row()
    if not tabs then return plain_letter_pressed(keys) end
    local page = math.max(1, rows.num_visible - 1)
    -- (PgUp and PgDn also arrive as diagonal cursor moves: read them first)
    if keys.STANDARDSCROLL_PAGEDOWN and keys._STRING ~= 47 then
        self.an_idx = (self.an_idx or 0) + page
    elseif keys.STANDARDSCROLL_PAGEUP then
        self.an_idx = (self.an_idx or 0) - page
    elseif keys.CUSTOM_HOME then
        self.an_idx = 0
    elseif keys.CUSTOM_END then
        self.an_idx = count - 1
    elseif keys.CUSTOM_Z or keys.CUSTOM_C or keys.SELECT then
        -- the row's own zoom button; announcements with no place have none to show
        local function find_button(widget, depth)
            for _, child in ipairs(kids(widget)) do
                if kind(child) == 'widget_recenter_button' then return child end
                local inner = depth < 3 and find_button(child, depth + 1)
                if inner then return inner end
            end
        end
        local button = row and find_button(row, 0)
        if button and button.flag.VISIBILITY_VISIBLE then
            click_widget(button)
        elseif row and keys.SELECT then
            -- no place to zoom to: a fight's line has a button at its end
            -- that opens the fight's report instead
            for _, child in ipairs(kids(row)) do
                if kind(child) == 'widget' then
                    click_widget(child)
                    break
                end
            end
        end
        return true
    else
        local dx, dy = self:take_move(keys)
        local step = list_step(keys)
        if dx and dx ~= 0 and dy == 0 then
            -- Left / Right: the category tabs, round and round. A category
            -- with nothing in it cannot be opened, so it is stepped over.
            local pages = kids(tabs)
            local idx = tabs.cur_idx
            for _ = 1, #pages do
                idx = (idx + sign(dx)) % #pages
                local target = pages[idx + 1]
                if target and #target.name > 0 and #kids(target) > 0 then
                    click_label(target.name, {y1=TOP_ROWS, y2=rows.rect.y1 - 1, x2=tabs.rect.x2})
                    break
                end
            end
            return true
        elseif dx or step then
            self.an_idx = (self.an_idx or 0) + (dy or 0) + (step or 0)
        else
            return plain_letter_pressed(keys)
        end
    end
    self.an_idx = math.max(0, self.an_idx)
    self:announcement_row()
    return true
end

function ClassicKeysOverlay:render_announcement_marker()
    if ClassicKeysOverlay.report_popup_rows() then return end
    local row = self:announcement_row()
    if not row then return end
    -- an arrow only: the lines keep the colours the game gives them
    dfhack.screen.paintString({fg=COLOR_YELLOW, bg=COLOR_BLACK}, row.rect.x1 - 1, row.rect.y1, string.char(16))
end

function ClassicKeysOverlay:announcement_lines()
    if ClassicKeysOverlay.report_popup_rows() then
        return {
            {{text="a fight's report", pen=COLOR_WHITE}},
            {hint('- =', 'scroll')},
            {hint('Shift+up/down', 'by ten')},
            {hint('PgUp PgDn', 'by page')},
            {hint('Home End', 'start / end')},
            {hint('Esc', 'back to the list')},
        }
    end
    local _, _, tabs, count = self:announcement_row()
    local name = tabs and kids(tabs)[tabs.cur_idx + 1]
    return {
        {{text=('%s: %d of %d'):format(name and name.name or '?', count and count > 0 and (self.an_idx or 0) + 1 or 0,
            count or 0), pen=COLOR_WHITE}},
        {hint('- =', 'select')},
        {hint('Shift+up/down', 'by ten')},
        {hint('PgUp PgDn', 'by page')},
        {hint('Home End', 'first / last')},
        {hint('left right', 'category')},
        {hint('z', 'zoom to it')},
        {hint('Enter', 'zoom / report')},
        {hint('Esc', 'close')},
    }
end

end -- of the widget lists block

-- zone details (q on a zone) ----------------------------------------------------------
--
-- Every kind of zone has the same panel: its name with a quill at the right
-- end (column 42), and under it the kind's own row with "suspend" at column
-- 38. Below the quill, 6 rows down, is the button that assigns to the zone
-- (animals to a pen or pit, an owner to a bedroom, office, dining room or
-- tomb, squads to a barracks or range) and 9 rows down the one that attaches
-- the zone to a location. The first opens the game's unit list (or its squad
-- list), the second its location chooser.
do
local plain_letter_pressed = ClassicKeysOverlay.info_helpers.plain_letter_pressed
local location_ui = mi.location_selector
local ZONE_BUTTON_X = 42

function ClassicKeysOverlay:on_zone_detail_input(keys)
    local name_row = TOP_ROWS + 2
    if keys.CUSTOM_A then
        self.usel_idx, self.rows_idx = 0, 0
        click_screen(ZONE_BUTTON_X, name_row + 6)
    elseif keys.CUSTOM_L then
        -- With a location already, the button that chooses one stands a
        -- place to the left, and the one in its place shows the location.
        self.rows_idx = 0
        local has_location = mi.civzone.cur_bld.location_id ~= -1
        click_screen(has_location and ZONE_BUTTON_X - 4 or ZONE_BUTTON_X, name_row + 9)
    elseif keys.CUSTOM_D and mi.civzone.cur_bld.location_id ~= -1 then
        -- the location's own page: who may visit, its occupations
        self.ld_idx = 0
        click_screen(ZONE_BUTTON_X, name_row + 9)
    elseif keys.CUSTOM_S then
        click_screen(ZONE_BUTTON_X - 4, name_row + 3)
    elseif keys.CUSTOM_N then
        click_screen(ZONE_BUTTON_X, name_row)
    else
        return self:on_zone_setting_input(keys)
    end
    return true
end

-- A zone's own settings. The new game hides these behind small icon buttons;
-- the old one had a key for each on the zone's q page, so they are set
-- directly here, the way that page did, and shown in the overlay's panel.
function ClassicKeysOverlay.zone_settings(zone)
    local kind, set = zone.type, zone.zone_settings
    local T = df.civzone_type
    if kind == T.Pond then
        return {{'f', set.pond.flag.keep_filled and 'pond: kept filled with water' or 'pit: not filled',
                 function() set.pond.flag.keep_filled = not set.pond.flag.keep_filled end}}
    elseif kind == T.Tomb then
        return {
            {'c', set.tomb.flags.no_citizens and 'citizens: not buried here' or 'citizens: buried here',
             function() set.tomb.flags.no_citizens = not set.tomb.flags.no_citizens end},
            {'p', set.tomb.flags.no_pets and 'pets: not buried here' or 'pets: buried here',
             function() set.tomb.flags.no_pets = not set.tomb.flags.no_pets end},
        }
    elseif kind == T.ArcheryRange then
        local dirs = {{0, -1, 'north to south'}, {1, 0, 'east to west'},
                      {0, 1, 'south to north'}, {-1, 0, 'west to east'}}
        local current = 1
        for i, dir in ipairs(dirs) do
            if set.archery.dir_x == dir[1] and set.archery.dir_y == dir[2] then current = i end
        end
        return {{'d', 'shoot ' .. dirs[current][3], function()
            local dir = dirs[current % #dirs + 1]
            set.archery.dir_x, set.archery.dir_y = dir[1], dir[2]
        end}}
    elseif kind == T.PlantGathering then
        local flags = set.gather.flags
        return {
            {'t', 'pick trees: ' .. (flags.pick_trees and 'yes' or 'no'),
             function() flags.pick_trees = not flags.pick_trees end},
            {'b', 'pick shrubs: ' .. (flags.pick_shrubs and 'yes' or 'no'),
             function() flags.pick_shrubs = not flags.pick_shrubs end},
            {'f', 'gather fallen: ' .. (flags.gather_fallen and 'yes' or 'no'),
             function() flags.gather_fallen = not flags.gather_fallen end},
        }
    end
    return {}
end

-- DFHack's preserve-rooms box stands beside a bedroom's, dining hall's,
-- office's or tomb's panel ("Autoassign to holder of role"), and opens a
-- list of roles below itself when the mouse is over it; the key list goes
-- under all of that. Returns the last row it may use, or nil.
local ROOM_BOX_ZONES = {'dwarfmode/Zone/Some/Bedroom', 'dwarfmode/Zone/Some/DiningHall',
                        'dwarfmode/Zone/Some/Office', 'dwarfmode/Zone/Some/Tomb'}
function ClassicKeysOverlay.dfhack_room_box_bottom()
    local shown = false
    for _, focus in ipairs(ROOM_BOX_ZONES) do
        if focus_is(focus) then shown = true end
    end
    if not shown then return end
    local ok, bottom = pcall(function()
        local entry = overlay.get_state().db['preserve-rooms.reserved']
        local widget = entry and entry.widget
        local enabled = overlay.get_state().config['preserve-rooms.reserved']
        if not widget or not widget.frame_rect or (enabled and not enabled.enabled) then return end
        return widget.frame_rect.y2
    end)
    return ok and bottom or nil
end

function ClassicKeysOverlay:on_zone_setting_input(keys)
    local zone = mi.civzone.cur_bld
    if not zone then return false end
    for _, setting in ipairs(ClassicKeysOverlay.zone_settings(zone)) do
        if keys['CUSTOM_' .. setting[1]:upper()] then
            setting[3]()
            return true
        end
    end
    return false
end

-- The location chooser: five "New ..." buttons, then the fort's locations 3
-- rows apart from 15 rows under the top bar. "New temple" and "New
-- guildhall" go on to a list of deities or of trades, 3 apart from 5 rows
-- under the top bar. The game's own Esc steps back one list at a time.
local NEW_LOCATION = {
    CUSTOM_I='New inn/tavern', CUSTOM_T='New temple', CUSTOM_L='New library',
    CUSTOM_G='New guildhall', CUSTOM_H='New hospital',
}

local function location_list()
    local field = location_ui.choosing_temple_religious_practice and 'scroll_position_deity'
        or location_ui.choosing_craft_guild and 'scroll_position_guild'
    -- for a zone that has a location the list starts with a "Remove current
    -- location assignment" button, and everything under it stands 3 rows lower
    local removable = not field and find_screen_text('Remove current',
        {x1=PANEL_LEFT_BESIDE_NATIVE, x2=PANEL_LEFT_BESIDE_NATIVE + 20, y1=TOP_ROWS + 3, y2=TOP_ROWS + 7})
    local shift = removable and 3 or 0
    return {x=PANEL_LEFT_BESIDE_NATIVE + 6, first=TOP_ROWS + (field and 5 or 15) + shift,
            owner=location_ui, scroll=field or 'scroll_position_location', choosing=field and true or false,
            removable=removable and true or false}
end

function ClassicKeysOverlay:on_location_input(keys)
    if keys.LEAVESCREEN then
        self:feed('LEAVESCREEN')
        self.rows_idx = 0
        return true
    end
    local list = location_list()
    local moved = self:rows_input(keys, list)
    if moved then
        if moved == 'chosen' then self.rows_idx = 0 end
        return true
    end
    if not list.choosing then
        if keys.CUSTOM_R and list.removable then
            self.rows_idx = 0
            click_label('Remove current', {x1=PANEL_LEFT_BESIDE_NATIVE, y1=TOP_ROWS + 3, y2=TOP_ROWS + 7})
            return true
        end
        for code, label in pairs(NEW_LOCATION) do
            if keys[code] then
                self.rows_idx = 0
                click_label(label, {x1=PANEL_LEFT_BESIDE_NATIVE - 4, y2=TOP_ROWS + 17})
                return true
            end
        end
    elseif keys.CUSTOM_SHIFT_E then
        -- DFHack's "hide established" switch on these lists
        return false
    end
    return plain_letter_pressed(keys)
end

-- The squad list of a barracks or an archery range. Each squad's row ends in
-- four buttons, 4 columns apart from 78 columns into the list's window: sleep
-- here, train here, keep individual equipment here, keep squad equipment
-- here. The keys are the old barracks ones.
local SQUAD_USE = {CUSTOM_Z=78, CUSTOM_T=82, CUSTOM_I=86, CUSTOM_Q=90}

function ClassicKeysOverlay:on_squad_selector_input(keys)
    if keys.LEAVESCREEN then
        self:feed('LEAVESCREEN')
        return true
    end
    local list = {x=PANEL_LEFT_BESIDE_NATIVE + 6, first=TOP_ROWS + 5,
                  owner=mi.squad_selector, scroll='scroll_position'}
    for code, column in pairs(SQUAD_USE) do
        if keys[code] then
            local row = list.first + 3 * (self.rows_idx or 0)
            if ClassicKeysOverlay.info_helpers.row_has_text(list.x, row) then
                click_screen(PANEL_LEFT_BESIDE_NATIVE + column, row)
            end
            return true
        end
    end
    -- Enter has nothing to choose here: the four keys are the choices
    if keys.SELECT then return true end
    if self:rows_input(keys, list) then return true end
    return plain_letter_pressed(keys)
end

function ClassicKeysOverlay:render_zone_chooser_marker()
    if location_ui.open then
        self:render_rows(location_list())
    else
        self:render_rows({x=PANEL_LEFT_BESIDE_NATIVE + 6, first=TOP_ROWS + 5,
                          owner=mi.squad_selector, scroll='scroll_position'})
    end
end

function ClassicKeysOverlay:zone_chooser_lines()
    if location_ui.open and not location_list().choosing then
        local lines = {
            {hint('- =', 'select  '), hint('Enter', 'attach to it')},
            {hint('i', 'new inn  '), hint('t', 'temple  '), hint('l', 'library')},
            {hint('g', 'new guildhall  '), hint('h', 'hospital')},
        }
        if location_list().removable then
            lines[#lines + 1] = {hint('r', 'remove from its location')}
        end
        lines[#lines + 1] = {hint('Esc', 'cancel')}
        return 'Location', lines
    end
    if not location_ui.open then
        return 'Squads here', {
            {hint('- =', 'select squad')},
            {hint('z', 'sleep  '), hint('t', 'train')},
            {hint('i', 'own equipment  '), hint('q', 'squad equipment')},
            {hint('Esc', 'done')},
        }
    end
    return 'Choose', {
        {hint('- =', 'select  '), hint('Enter', 'choose  '), hint('Esc', 'back')},
    }
end

end -- of the zone details block

-- combat reports (the old r screen) ----------------------------------------------
--
-- The new game shows a fight in an announcement box and on a creature's own
-- sheet; the old one had a single list of every creature's combat, sparring
-- and hunting reports. The game still keeps what that list needs: each
-- creature has, per kind, the ids of its reports (unit.reports.log), and the
-- reports themselves (world.status.reports) carry their text, colour and
-- date until the game drops the oldest. So this is a window of our own: the
-- logs with the most recent first, and Enter to read one.
do
local MONTH_NAMES = {
    'Granite', 'Slate', 'Felsite', 'Hematite', 'Malachite', 'Galena',
    'Limestone', 'Sandstone', 'Timber', 'Moonstone', 'Opal', 'Obsidian',
}
local KIND_NAMES = {[0]='Combat', [1]='Sparring', [2]='Hunting'}

local function report_date(year, tick)
    local day = tick // 1200
    return ('%d %s %d'):format(day % 28 + 1, MONTH_NAMES[day // 28 + 1] or '?', year)
end

-- every creature's log of each kind that the game still holds lines of, the
-- one with the latest line first
local function gather_logs()
    local logs = {}
    for _, unit in ipairs(df.global.world.units.all) do
        for kind = 0, 2 do
            local ids = unit.reports.log[kind]
            if #ids > 0 then
                local lines = {}
                for _, id in ipairs(ids) do
                    local report = df.report.find(id)
                    if report then lines[#lines + 1] = report end
                end
                if #lines > 0 then
                    local last = lines[#lines]
                    logs[#logs + 1] = {unit=unit, kind=kind, lines=lines, year=last.year, time=last.time}
                end
            end
        end
    end
    table.sort(logs, function(a, b)
        if a.year ~= b.year then return a.year > b.year end
        return a.time > b.time
    end)
    return logs
end

local ReportsScreen = defclass(nil, gui.ZScreen)
ReportsScreen.ATTRS{
    focus_path='classic-controls/reports',
    pass_movement_keys=false,
}

function ReportsScreen:init()
    self:addviews{
        widgets.Window{
            frame={w=116, h=52},
            frame_title='Reports',
            resizable=true,
            subviews={
                widgets.List{
                    view_id='list',
                    frame={t=0, l=0, r=0, b=2},
                    on_submit=self:callback('open_log'),
                },
                widgets.Label{view_id='hints', frame={b=0, l=0}, text=''},
            },
        },
    }
    self.logs = gather_logs()
    self:show_logs()
end

local function hints(pairs_list)
    local text = {}
    for _, pair in ipairs(pairs_list) do
        text[#text + 1] = {text=pair[1], pen=COLOR_LIGHTGREEN}
        text[#text + 1] = ': ' .. pair[2] .. '  '
    end
    return text
end

function ReportsScreen:show_logs()
    self.viewing = nil
    local choices = {}
    for _, log in ipairs(self.logs) do
        choices[#choices + 1] = {
            text=('%-9s %-60s %s'):format(KIND_NAMES[log.kind] .. ':',
                dfhack.units.getReadableName(log.unit):sub(1, 60), report_date(log.year, log.time)),
            log=log,
        }
    end
    if #choices == 0 then
        choices[1] = {text='No combat, sparring or hunting reports are being kept.'}
    end
    self.subviews.list:setChoices(choices, self.list_pos or 1)
    self.subviews.hints:setText(hints{{'- =', 'select'}, {'Enter', 'read'}, {'z', 'zoom to creature'}, {'Esc', 'close'}})
end

-- one creature's log, oldest line first as the old screen had it, with a
-- line for the date whenever the day changes
function ReportsScreen:open_log(_, choice)
    local log = choice and choice.log
    if not log or self.viewing then return end
    self.list_pos = self.subviews.list:getSelected()
    self.viewing = log
    local width = math.max(20, self.subviews.list.frame_body.width - 2)
    local choices, day = {}, nil
    for _, report in ipairs(log.lines) do
        local this_day = report.year * 1000 + report.time // 1200
        if this_day ~= day then
            day = this_day
            choices[#choices + 1] = {text={{text=report_date(report.year, report.time), pen=COLOR_DARKGREY}}}
        end
        local pen = report.color + (report.bright and 8 or 0)
        local first = true
        for piece in report.text:wrap(width - 2):gmatch('[^\n]+') do
            choices[#choices + 1] = {text={{text=(first and '' or '  ') .. piece, pen=pen}}}
            first = false
        end
    end
    self.subviews.list:setChoices(choices, 1)
    self.subviews.hints:setText(hints{{'- = or arrows', 'scroll'}, {'Shift', 'by ten'}, {'PgUp PgDn', 'page'}, {'z', 'zoom'}, {'Esc', 'back to the list'}})
end

function ReportsScreen:onInput(keys)
    local list = self.subviews.list
    if keys.LEAVESCREEN or keys._MOUSE_R then
        if self.viewing then
            self:show_logs()
        else
            self:dismiss()
        end
        return true
    end
    local step = list_step(keys)
    if keys.KEYBOARD_CURSOR_UP_FAST or keys.CURSOR_UP_FAST then step = -10 end
    if keys.KEYBOARD_CURSOR_DOWN_FAST or keys.CURSOR_DOWN_FAST then step = 10 end
    if self.viewing then
        -- Reading a report: the text itself scrolls, a line at a time (ten
        -- with Shift, a page with PgUp / PgDn, the ends with Home / End).
        -- There is no selection to move: the lines carry their own colours,
        -- so a highlighted line would not show and the text would only
        -- start moving once it had reached the bottom of the page.
        if keys.KEYBOARD_CURSOR_UP or keys.STANDARDSCROLL_UP or keys.CURSOR_UP then step = step or -1 end
        if keys.KEYBOARD_CURSOR_DOWN or keys.STANDARDSCROLL_DOWN or keys.CURSOR_DOWN then step = step or 1 end
        local page = math.max(1, list.page_size - 1)
        if keys.STANDARDSCROLL_PAGEUP then step = -page end
        if keys.STANDARDSCROLL_PAGEDOWN then step = page end
        if keys.CUSTOM_HOME or keys.STANDARDSCROLL_HOME then step = -#list.choices end
        if keys.CUSTOM_END or keys.STANDARDSCROLL_END then step = #list.choices end
        if step then
            list:on_scrollbar(list.page_top + step)
            return true
        end
        if keys.SELECT then return true end
    elseif step then
        local count = #list.choices
        if count > 0 then
            list:setSelected(math.max(1, math.min(count, (list:getSelected() or 1) + step)))
        end
        return true
    end
    if keys.CUSTOM_Z then
        local _, choice = list:getSelected()
        local log = self.viewing or (choice and choice.log)
        if log then
            local x, y, z = dfhack.units.getPosition(log.unit)
            if x then
                dfhack.gui.revealInDwarfmodeMap(xyz2pos(x, y, z), true)
                self:dismiss()
            end
        end
        return true
    end
    return ReportsScreen.super.onInput(self, keys)
end

function ClassicKeysOverlay.show_reports()
    ReportsScreen{}:show()
end

end -- of the reports block

-- putting a dwarf in a squad from their sheet (S) -----------------------------------
--
-- The new game does this from the squad's side only (squads, p). The old one
-- let you do it from the dwarf, so this is a small window of our own: the
-- fort's squads with room, and Enter to join the highlighted one.
do
local SquadPicker = defclass(nil, gui.ZScreen)
SquadPicker.ATTRS{
    focus_path='classic-controls/squad-picker',
    pass_movement_keys=false,
    unit=DEFAULT_NIL,
}

function SquadPicker:init()
    self:addviews{
        widgets.Window{
            frame={w=76, h=24},
            frame_title='Squad: ' .. dfhack.units.getReadableName(self.unit):sub(1, 60),
            subviews={
                widgets.List{view_id='list', frame={t=0, l=0, r=0, b=2}, on_submit=self:callback('choose')},
                widgets.Label{frame={b=0, l=0}, text={
                    {text='- =', pen=COLOR_LIGHTGREEN}, ': select  ',
                    {text='Enter', pen=COLOR_LIGHTGREEN}, ': choose  ',
                    {text='Esc', pen=COLOR_LIGHTGREEN}, ': cancel',
                }},
            },
        },
    }
    local choices = {}
    local current = df.squad.find(self.unit.military.squad_id)
    if current then
        choices[1] = {text='Leave ' .. dfhack.military.getSquadName(current.id), leave=true}
    end
    for _, id in ipairs(df.global.plotinfo.main.fortress_entity.squads) do
        local squad = df.squad.find(id)
        if squad and squad ~= current then
            local free = 0
            for _, position in ipairs(squad.positions) do
                if position.occupant == -1 then free = free + 1 end
            end
            choices[#choices + 1] = {
                text=('%-50s %s'):format(dfhack.military.getSquadName(id):sub(1, 50),
                    free > 0 and (free .. ' free') or 'full'),
                squad=free > 0 and squad or nil,
            }
        end
    end
    if #choices == 0 then choices[1] = {text='The fort has no squads: s, then C, creates one.'} end
    self.subviews.list:setChoices(choices, 1)
end

function SquadPicker:choose(_, choice)
    if not choice then return end
    if choice.leave then
        dfhack.military.removeFromSquad(self.unit.id)
    elseif choice.squad then
        -- -1: the first free position
        dfhack.military.addToSquad(self.unit.id, choice.squad.id, -1)
    else
        return
    end
    self:dismiss()
end

function SquadPicker:onInput(keys)
    if keys.LEAVESCREEN or keys._MOUSE_R then
        self:dismiss()
        return true
    end
    local list = self.subviews.list
    local step = list_step(keys)
    if step then
        local count = #list.choices
        if count > 0 then
            list:setSelected(math.max(1, math.min(count, (list:getSelected() or 1) + step)))
        end
        return true
    end
    return SquadPicker.super.onInput(self, keys)
end

function ClassicKeysOverlay.pick_squad(unit)
    SquadPicker{unit=unit}:show()
end

end -- of the squad picker block

-- three more of the game's windows: a location's details, a task's or work
-- order's details, and the word-by-word name builder ------------------------------
--
-- None of them has a key of its own. Each is a list (or two) of rows 3 apart,
-- so the same - = and Enter work them, and their buttons are clicked at their
-- place beside the row or the window's corner.
do
local helpers = ClassicKeysOverlay.info_helpers
local row_text_start, plain_letter_pressed = helpers.row_text_start, helpers.plain_letter_pressed
local P = PANEL_LEFT_BESIDE_NATIVE

-- a location's details (from a zone with d, or the Places list) ----------------------
--
-- Under the name: a button for each rule on who may visit; lines of counts,
-- those the fort can change ending in "(Desired)" and followed by "#", "+"
-- and "-" buttons, 4 columns each; then the occupations, their text 6 columns
-- in, with the button that fills one at 26; the one that empties it, and the
-- name's quill at the top, stand 33 and 32 columns from the right edge.
local loc = mi.location_details

-- Where a count's three buttons start. How far along the row they stand
-- differs from one kind of location to the next, so they are found: the
-- first cells after the row's text that are not drawn as the row's own
-- background.
local function count_buttons(y)
    local label = find_screen_text('(Desired)', {x1=P, x2=P + 60, y1=y, y2=y})
    if not label then return end
    local last = label + 8
    for x = label + 9, label + 24 do
        local tile = dfhack.screen.readTile(x, y)
        if tile and tile.ch and tile.ch > 32 then last = x end
    end
    local plain = dfhack.screen.readTile(last + 1, y)
    if not plain then return end
    for x = last + 2, last + 40 do
        local tile = dfhack.screen.readTile(x, y)
        if tile and tile.tile ~= plain.tile then return x end
    end
end

-- a number key: never a move of the selection (the keypad's can be bound so)
local function digit_typed(keys)
    local char = keys._STRING
    return char ~= nil and char >= 48 and char <= 57
end

local function loc_layout()
    local counts, first = {}, nil
    for y = TOP_ROWS + 8, gps.dimy - 6 do
        if find_screen_text('(Desired)', {x1=P, x2=P + 60, y1=y, y2=y}) then
            counts[#counts + 1] = y
        elseif not first and row_text_start(y, P, P + 8) == P + 6 then
            first = y
        end
    end
    return {
        counts=counts, first=first,
        occupations=first and #loc.loc_occupation or 0,
        visible=first and math.max(1, (gps.dimy - 9 - first) // 3) or 0,
    }
end

-- the screen row of the selection, what kind of row it is, and its index
function ClassicKeysOverlay:loc_row(layout)
    local total = #layout.counts + layout.occupations
    if total == 0 then return end
    local idx = math.max(0, math.min(self.ld_idx or 0, total - 1))
    self.ld_idx = idx
    if idx < #layout.counts then return layout.counts[idx + 1], 'count', idx end
    local occ = idx - #layout.counts
    local scroll = math.max(0, loc.scroll_position_occupation)
    if occ < scroll then
        scroll = occ
    elseif occ >= scroll + layout.visible then
        scroll = occ - layout.visible + 1
    end
    loc.scroll_position_occupation = scroll
    return layout.first + 3 * (occ - scroll), 'occupation', occ
end

local function loc_access(ab)
    local flags = ab.flags
    if flags.VISITORS_ALLOWED then return 0 end
    if flags.NON_CITIZENS_ALLOWED then return 1 end
    if flags.MEMBERS_ONLY then return 3 end
    return 2
end

function ClassicKeysOverlay:on_location_details_input(keys)
    if keys.LEAVESCREEN then
        self:feed('LEAVESCREEN')
        return true
    end
    if digit_typed(keys) then return true end
    local layout = loc_layout()
    local y, what = self:loc_row(layout)
    local buttons = what == 'count' and count_buttons(y)
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if (dx and dy ~= 0) or step then
        self.ld_idx = (self.ld_idx or 0) + (dy or 0) + (step or 0)
        self:loc_row(layout)
        return true
    elseif dx then
        -- a count: Right is its "+" and Left its "-"
        if buttons and dx ~= 0 then click_screen(buttons + (dx > 0 and 5 or 9), y) end
        return true
    end
    local ab = loc.selected_ab
    if keys.SELECT then
        if what == 'count' then
            -- the "#": the game takes the number typed, up to Enter
            if buttons then click_screen(buttons + 1, y) end
        elseif what == 'occupation' then
            self.usel_idx = 0
            click_screen(P + 26, y)
        end
    elseif keys.CUSTOM_X then
        -- take the holder off the occupation: only a filled row has the button
        -- (its button is placed from the right edge of the screen)
        if what == 'occupation' and row_text_start(y, P + 30, P + 40) then click_screen(gps.dimx - 33, y) end
    elseif keys.CUSTOM_R and ab then
        -- who may visit: the next of the rules, round to the first
        local before = loc_access(ab)
        click_screen(P + 1 + 4 * ((before + 1) % 4), TOP_ROWS + 6)
        if loc_access(ab) == before then click_screen(P + 1, TOP_ROWS + 6) end
    elseif keys.CUSTOM_N then
        -- the quill: the name builder
        self.nm_pane = 0
        click_screen(gps.dimx - 32, TOP_ROWS + 2)
    else
        return plain_letter_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:render_location_details_marker()
    local y = self:loc_row(loc_layout())
    local start = y and row_text_start(y, P, P + 8)
    if start then mark_row(start - 1, y, 40) end
end

local function location_details_lines(self)
    if loc.entering_desired_number ~= nil then
        return 'Number', {{{text='type it', pen=COLOR_GREY}}, {hint('Enter', 'done')}}
    end
    local _, what = self:loc_row(loc_layout())
    local lines = {{hint('- =', 'select')}}
    if what == 'count' then
        lines[#lines + 1] = {hint('left right', 'fewer / more')}
        lines[#lines + 1] = {hint('Enter', 'type a number')}
    elseif what == 'occupation' then
        lines[#lines + 1] = {hint('Enter', 'choose who')}
        lines[#lines + 1] = {hint('x', 'remove holder')}
    end
    lines[#lines + 1] = {hint('r', 'who may visit')}
    lines[#lines + 1] = {hint('n', 'name')}
    lines[#lines + 1] = {hint('Esc', 'back')}
    return 'Location', lines
end

-- a task's or a work order's details (d) -------------------------------------------------
--
-- A job with more than one thing to settle (a dress: its cloth and its size)
-- opens on a list of them; one with a single thing goes straight to its list
-- of choices, under a box to filter it by. The window's place differs with
-- where it was opened from, so it is found by its title.
local jd = mi.job_details
local JD = df.job_details_option_type
local JD_LISTS = {
    [JD.MATERIAL]={scroll='scroll_position_material', filter='material_doing_filter'},
    [JD.CLOTHING_SIZE]={scroll='scroll_position_race', filter='clothing_size_race_doing_filter'},
    [JD.IMPROVEMENT_TYPE]={scroll='scroll_position_improvement'},
    [JD.DYE_OBJECT_COLOR]={scroll='scroll_position_dye_object', filter='dye_object_doing_filter'},
    [JD.MIX_DYE_COLOR]={scroll='scroll_position_mix_dye', filter='mix_dye_doing_filter'},
    [JD.PLANT]={scroll='scroll_position_plant', filter='plant_doing_filter'},
}

-- a filter box of the window is being typed in
function ClassicKeysOverlay.job_details_filtering()
    for _, entry in pairs(JD_LISTS) do
        if entry.filter and jd[entry.filter] then return true end
    end
    return false
end

local function jd_layout()
    local base, x
    for y = TOP_ROWS + 1, TOP_ROWS + 2 do
        x = row_text_start(y, 2, gps.dimx - 45)
        if x then
            base = y
            break
        end
    end
    if not base then return end
    if jd.current_option == JD.NONE then
        return {x=x, first=base + 3, owner=jd, scroll='scroll_position_option', options=true}
    end
    local entry = JD_LISTS[jd.current_option]
    if not entry then return end
    return {x=x, first=base + (entry.filter and 9 or 6), owner=jd, scroll=entry.scroll,
            filter=entry.filter, filter_row=base + 6}
end

function ClassicKeysOverlay:on_job_details_input(keys)
    if keys.LEAVESCREEN then
        if #jd.option > 1 and jd.current_option ~= JD.NONE then
            -- from one thing's choices back to the list of things
            jd.current_option = JD.NONE
        else
            self:feed('LEAVESCREEN')
        end
        self.rows_idx = 0
        return true
    end
    if digit_typed(keys) then return true end
    local list = jd_layout()
    if not list then return plain_letter_pressed(keys) end
    if keys._STRING == 47 or keys.CUSTOM_S then
        -- the filter box: the game takes what is typed, up to Enter
        if list.filter then
            self.rows_idx = 0
            click_screen(list.x + 6, list.filter_row)
        end
        return true
    end
    local moved = self:rows_input(keys, list)
    if moved then
        if moved == 'chosen' then self.rows_idx = 0 end
        return true
    end
    return plain_letter_pressed(keys)
end

function ClassicKeysOverlay:render_job_details_marker()
    if ClassicKeysOverlay.job_details_filtering() then return end
    local list = jd_layout()
    if list then self:render_rows(list) end
end

local function job_details_lines()
    if ClassicKeysOverlay.job_details_filtering() then
        return 'Search', {{{text='type to filter', pen=COLOR_GREY}}, {hint('Enter', 'done')}}
    end
    local list = jd_layout()
    local lines = {{hint('- =', 'select')}, {hint('Enter', 'choose')}}
    if list and list.filter then lines[#lines + 1] = {hint('/', 'search')} end
    lines[#lines + 1] = {hint('Esc', 'back')}
    return 'Details', lines
end

-- the name builder (the quill beside a squad's or a location's name) --------------------
--
-- Left, the seven parts a name is made of, each with "Random" and "Clear";
-- right, the words that fit the part chosen, under a box to filter them by;
-- "Random" (the whole name) and "Done" along the top. The old keys: r random,
-- c clear, e type (here: the filter).
local namer = mi.name_creator
local NAME_PARTS = 7

local function namer_layout()
    local done_x, top = find_screen_text('Done', {x1=P + 20, y1=TOP_ROWS, y2=TOP_ROWS + 6})
    if not done_x then return end
    local clear_x = find_screen_text('Clear', {x1=P, x2=done_x, y1=top + 2, y2=top + 30})
    if not clear_x then return end
    return {
        top=top, done_x=done_x, clear_x=clear_x, first=top + 5,
        word_x=clear_x + 9, word_first=top + 8,
        visible=math.max(1, (gps.dimy - 9 - (top + 8)) // 3),
    }
end

-- the screen row of the selected word, scrolled into view; a new part or a
-- new filter starts the list again
function ClassicKeysOverlay:namer_word_row(layout)
    local count = #namer.word_index
    if self.nm_count ~= count or self.nm_place ~= namer.cur_name_place then
        self.nm_count, self.nm_place, self.nm_word = count, namer.cur_name_place, 0
    end
    if count == 0 then return end
    local idx = math.max(0, math.min(self.nm_word or 0, count - 1))
    local scroll = math.max(0, namer.scroll_position_word)
    if idx < scroll then
        scroll = idx
    elseif idx >= scroll + layout.visible then
        scroll = idx - layout.visible + 1
    end
    namer.scroll_position_word = scroll
    self.nm_word = idx
    return layout.word_first + 3 * (idx - scroll)
end

function ClassicKeysOverlay:on_name_creator_input(keys)
    local layout = namer_layout()
    if keys.LEAVESCREEN then
        if layout then
            click_screen(layout.done_x + 1, layout.top)
        else
            self:feed('LEAVESCREEN')
        end
        self.nm_pane = 0
        return true
    end
    if not layout then return plain_letter_pressed(keys) end
    if digit_typed(keys) then return true end
    local part_row = layout.first + 3 * namer.cur_name_place
    if keys._STRING == 47 or keys.CUSTOM_E then
        -- the filter box: the game takes what is typed, up to Enter
        click_screen(layout.clear_x + 29, layout.top + 5)
        self.nm_pane = 1
        return true
    end
    local pane = self.nm_pane or 0
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx and dx ~= 0 and dy == 0 then
        self.nm_pane = dx > 0 and 1 or 0
        return true
    elseif dx or step then
        local move = (dy or 0) + (step or 0)
        if pane == 0 then
            local place = math.max(0, math.min(namer.cur_name_place + sign(move), NAME_PARTS - 1))
            click_screen(layout.clear_x - 26, layout.first + 3 * place)
        else
            self:namer_word_row(layout)
            self.nm_word = (self.nm_word or 0) + move
            self:namer_word_row(layout)
        end
        return true
    end
    if keys.SELECT then
        if pane == 0 then
            self.nm_pane = 1
        else
            local row = self:namer_word_row(layout)
            if row then click_screen(layout.word_x + 2, row) end
        end
    elseif keys.CUSTOM_R then
        click_screen(layout.clear_x - 6, part_row)
    elseif keys.CUSTOM_SHIFT_R then
        local x = find_screen_text('Random', {x1=layout.clear_x, y1=layout.top, y2=layout.top})
        if x then click_screen(x + 3, layout.top) end
    elseif keys.CUSTOM_C then
        click_screen(layout.clear_x + 2, part_row)
    else
        return plain_letter_pressed(keys)
    end
    return true
end

function ClassicKeysOverlay:render_name_creator_marker()
    if namer.entering_cull_str or namer.entering_first_name then return end
    local layout = namer_layout()
    if not layout then return end
    mark_row(layout.clear_x - 31, layout.first + 3 * namer.cur_name_place, 20)
    if (self.nm_pane or 0) == 1 then
        local row = self:namer_word_row(layout)
        if row then mark_row(layout.word_x - 1, row, 50) end
    end
end

local function name_creator_lines(self)
    if namer.entering_cull_str or namer.entering_first_name then
        return 'Search', {{{text='type to filter', pen=COLOR_GREY}}, {hint('Enter', 'done')}}
    end
    local ok, name = pcall(dfhack.translation.translateName, namer.name, true)
    local words = (self.nm_pane or 0) == 1
    return 'Name', {
        {{text=clip(ok and name or '', INFO_PANEL_W), pen=COLOR_WHITE}},
        {hint('- =', words and 'select word' or 'select part')},
        {hint('left right', 'part / words')},
        {hint('Enter', words and 'use the word' or 'to its words')},
        {hint('r', 'random word')},
        {hint('c', 'clear the part')},
        {hint('R', 'random name')},
        {hint('e', 'search words')},
        {hint('Esc', 'done')},
    }
end

-- which of the three is in front, for the key handler and the panel
function ClassicKeysOverlay.detail_window()
    if namer.open then return 'name' end
    if jd.open then return 'job' end
    if loc.open and not mi.location_selector.open then return 'location' end
end

function ClassicKeysOverlay:detail_window_lines()
    local window = ClassicKeysOverlay.detail_window()
    if window == 'name' then return name_creator_lines(self) end
    if window == 'job' then return job_details_lines() end
    if window == 'location' then return location_details_lines(self) end
end

end -- of the detail windows block

-- map-level keys -------------------------------------------------------------

local MODE_KEYS = {
    CUSTOM_K = 'look',
    CUSTOM_Q = 'query',
    CUSTOM_T = 'items',
    CUSTOM_V = 'unit',
}

local function lookup(keymap, keys)
    for key, seq in pairs(keymap) do
        if keys[key] then return seq end
    end
end

function ClassicKeysOverlay:on_mode_input(keys)
    -- Esc from an item opened out of a building's item list goes back to
    -- that building, not out to the map
    if keys.LEAVESCREEN and self.return_bld_id and vs.open
        and vs.active_sheet == df.view_sheet_type.ITEM
    then
        local back_to = df.building.find(self.return_bld_id)
        self.return_bld_id = nil
        if back_to then
            open_building_sheet(back_to)
            return true
        end
    end

    local unit = viewed_unit()
    if unit and self:on_unit_sheet_input(keys, unit) then
        return true
    end

    if keys.LEAVESCREEN then
        if not vs.open and mi.bottom_mode_selected == BOTTOM.NONE then
            -- nothing of the game's to close; swallow Esc so it does not
            -- open the options menu
            self:exit_mode()
            return true
        end
        -- look mode keeps its cursor after closing a panel opened with Enter;
        -- q and v are their panel, so closing it ends them
        if self.mode ~= 'look' then
            self:exit_mode()
        end
        return false
    end

    local bld = viewed_building()
    if bld and keys.CUSTOM_X and (self.mode == 'query' or self.mode == 'items') then
        self:toggle_building_removal(bld)
        return true
    end
    if bld and keys.CUSTOM_S and (self.mode == 'query' or self.mode == 'items')
        and ClassicKeysOverlay.toggle_construction_suspend(bld)
    then
        return true
    end
    if bld and self.mode == 'query' and ClassicKeysOverlay.is_farm(bld) then
        local handled = self:on_farm_input(keys, bld)
        if handled ~= nil then return handled end
    end
    if bld and df.building_tradedepotst:is_instance(bld) and self:on_depot_input(keys, bld) then
        return true
    end
    if bld and self:listing_building_items(bld) then
        if self:on_building_items_input(keys, bld) then return true end
    elseif is_workshop(bld) and self:on_workshop_input(keys, bld) then
        return true
    end

    local dx, dy, dz = self:take_move(keys)
    if dx then
        if dx ~= 0 or dy ~= 0 or dz ~= 0 then
            self.look_idx = 1
            self:move_cursor(dx, dy, dz)
        end
        return true
    end

    if self.mode == 'look' and not vs.open then
        -- - and = walk through the creatures, building and items on the tile
        local step = list_step(keys)
        if step then
            self.look_idx = (self.look_idx or 1) + step
            return true
        end
        if keys.SELECT then
            self:open_under_cursor()
            return true
        end
    end

    -- - and = never change level here, whatever the game binds them to
    return list_step(keys) ~= nil
end

-- keys that work anywhere the map is in charge: the bare map, or the map with
-- a unit / building / item panel open
-- farm plots (q on one, or its sheet opened with the mouse) ------------------------------
--
-- The game's sheet has a tab for each season and, under the chosen tab, a
-- list of what can be planted then ("Leave fallow" first), 3 rows to a crop,
-- with two tick boxes under it: fertilize, and fertilize every season. The
-- old keys: a b c d for the seasons, - = and Enter to choose the crop, z for
-- fallow, f and s for the two fertilizer settings.
do
local SEASONS = {'Spring', 'Summer', 'Autumn', 'Winter'}
local SEASON_KEYS = {CUSTOM_A=0, CUSTOM_B=1, CUSTOM_C=2, CUSTOM_D=3}

function ClassicKeysOverlay.is_farm(bld)
    return bld ~= nil and bld:getType() == df.building_type.FarmPlot
        and bld:getBuildStage() >= bld:getMaxBuildStage()
end

local function sheet_bounds()
    -- the building's sheet: 60 columns wide at the right, whatever the screen's width
    return {x1=gps.dimx - SHEET_COLS - 2, y1=TOP_ROWS, y2=gps.dimy - 4}
end

local function text_from(x, y, width)
    local chars = {}
    for tx = x, x + width do
        local tile = dfhack.screen.readTile(tx, y)
        local ch = tile and tile.ch or 0
        chars[#chars + 1] = (ch > 31 and ch < 127) and string.char(ch) or ' '
    end
    return (table.concat(chars):gsub('%s+$', ''))
end

local function click_season(season)
    local b = sheet_bounds()
    b.y2 = TOP_ROWS + 10
    local x, y = find_screen_text(SEASONS[season + 1], b)
    if x then click_screen(x + 2, y) end
    return x ~= nil
end

-- the crops on show: {x, rows={y...}, names={...}}
-- where the list starts: found by its first entry, "Leave fallow", and
-- remembered for when that has scrolled out of sight
local geometry

local function farm_list()
    local b = sheet_bounds()
    local x, first = find_screen_text('Leave fallow', b)
    if x then
        geometry = {x=x, first=first, width=gps.dimx, height=gps.dimy}
    elseif geometry and vs.scroll_position_displayed_items > 0
        and geometry.width == gps.dimx and geometry.height == gps.dimy
    then
        x, first = geometry.x, geometry.first
    else
        return
    end
    local _, stop = find_screen_text('Current amount', b)
    stop = stop and stop - 3 or gps.dimy - 6
    local list = {x=x, rows={}, names={}}
    for y = first, stop, 3 do
        local name = text_from(x, y, 30)
        if #name == 0 then break end
        list.rows[#list.rows + 1] = y
        list.names[#list.names + 1] = name
    end
    return list
end

local function season_now()
    return vs.active_sub_tab
end

local function crop_name(bld, season)
    local id = bld.plant_id[season]
    if id < 0 then return 'leave fallow' end
    local raw = df.plant_raw.find(id)
    return raw and raw.name_plural:lower() or ''
end

-- The selection is a row on screen; the list scrolls under it
-- (scroll_position_displayed_items, which the game does not stop at the end
-- of the list: it only stops drawing). It starts on the crop the season has,
-- when that is on show.
function ClassicKeysOverlay:farm_row(bld, list)
    local key = bld.id .. '/' .. season_now()
    if self.farm_key ~= key then
        self.farm_key, self.farm_idx = key, 1
        local current = crop_name(bld, season_now())
        for i, name in ipairs(list.names) do
            if name:lower() == current then self.farm_idx = i end
        end
    end
    self.farm_idx = math.max(1, math.min(self.farm_idx or 1, #list.rows))
    return list.rows[self.farm_idx]
end

function ClassicKeysOverlay:farm_move(bld, list, step)
    self:farm_row(bld, list)
    local target = self.farm_idx + step
    if target < 1 then
        if vs.scroll_position_displayed_items > 0 then
            vs.scroll_position_displayed_items = vs.scroll_position_displayed_items - 1
        end
    elseif target > #list.rows then
        -- one more down; if the top row is the same once it is drawn, the
        -- list had ended and the scroll is taken back (render_farm_marker)
        self.farm_scroll_check = {first=list.names[1], scroll=vs.scroll_position_displayed_items}
        vs.scroll_position_displayed_items = vs.scroll_position_displayed_items + 1
    else
        self.farm_idx = target
    end
end

-- A crop is chosen with the tick box at the end of its row (a click on the
-- name does nothing). Where the box is depends on whether the list has a
-- scroll bar, so it is found: the first tile after the name that is not
-- the row's own background.
local function tick_box_x(list, i)
    local y = list.rows[i]
    local after = list.x + #list.names[i] + 1
    local plain = dfhack.screen.readTile(after, y)
    if not plain then return end
    for x = after + 1, math.min(gps.dimx - 1, after + 70) do
        local tile = dfhack.screen.readTile(x, y)
        if tile and tile.tile ~= plain.tile then return x + 1 end
    end
end

local function tick(list, i)
    local x = list.rows[i] and tick_box_x(list, i)
    if x then click_screen(x, list.rows[i]) end
end

-- When the sheet opens the game shows the first tab without its list; the
-- tab of the season it is now is chosen, which fills it.
function ClassicKeysOverlay:farm_opened(bld)
    if self.farm_open_id == bld.id then return end
    self.farm_open_id = bld.id
    dfhack.timeout(3, 'frames', function()
        local now = viewed_building()
        if now and now.id == bld.id and not farm_list() then
            click_season(df.global.cur_season)
        end
    end)
end

function ClassicKeysOverlay:on_farm_input(keys, bld)
    for code, season in pairs(SEASON_KEYS) do
        if keys[code] then
            click_season(season)
            return true
        end
    end
    local b = sheet_bounds()
    if keys.CUSTOM_F then
        local x, y = find_screen_text('Current amount', b)
        if x then click_screen(x - 2, y - 1) end
        return true
    elseif keys.CUSTOM_S then
        local x, y = find_screen_text('every season', b)
        if x then click_screen(x - 2, y - 1) end
        return true
    end
    local list = farm_list()
    if not list then
        -- no list on show yet: a list key fills it first
        if list_step(keys) or keys.SELECT or keys.CUSTOM_Z then
            click_season(season_now())
            return true
        end
        return nil
    end
    local step = list_step(keys)
    if step then
        self:farm_move(bld, list, step)
        return true
    elseif keys.SELECT then
        self:farm_row(bld, list)
        tick(list, self.farm_idx)
        return true
    elseif keys.CUSTOM_Z then
        -- fallow is the first entry of the list
        vs.scroll_position_displayed_items = 0
        self.farm_idx = 1
        dfhack.timeout(2, 'frames', function()
            local fresh = farm_list()
            if fresh and fresh.names[1] == 'Leave fallow' then tick(fresh, 1) end
        end)
        return true
    end
    return nil
end

function ClassicKeysOverlay:render_farm_marker(bld)
    self:farm_opened(bld)
    local list = farm_list()
    if not list then return end
    local check = self.farm_scroll_check
    if check then
        self.farm_scroll_check = nil
        if list.names[1] == check.first then
            vs.scroll_position_displayed_items = check.scroll
        end
    end
    local row = self:farm_row(bld, list)
    if row then mark_row(list.x - 1, row, 30) end
end

function ClassicKeysOverlay:farm_lines(bld)
    local season = season_now()
    local lines = {{{text=('%s: %s'):format(SEASONS[season + 1] or '?', crop_name(bld, season)),
                     pen=COLOR_LIGHTGREEN}}}
    lines[#lines + 1] = {hint('a b c d', 'spring summer autumn winter')}
    lines[#lines + 1] = {hint('- =', 'select crop  '), hint('Enter', 'plant it  '), hint('z', 'fallow')}
    lines[#lines + 1] = {hint('f', 'fertilize  '),
                         hint('s', 'every season: ' .. (bld.farm_flags.seasonal_fertilize and 'yes' or 'no'))}
    lines[#lines + 1] = {ClassicKeysOverlay.removal_hint(bld), '  ', hint('Esc', 'done')}
    return lines
end

end -- of the farm plot block

-- hauling routes (h): routes, stops, departure conditions, links, minecarts ------
--
-- The game's panel at the top left lists each route with its stops under it,
-- 3 rows apart from 4 rows under "Add new route". A route's row ends in four
-- icon buttons (add a stop, assign a minecart, name, delete), a stop's in five
-- (the items it loads, its stockpile links, its departure conditions, name,
-- delete); they are 4 columns apart from the first picture on the row. A stop
-- is placed by clicking a map tile, here the cursor and Enter. The windows
-- its buttons open stand to the right of the panel: conditions (a text row
-- and a row of buttons, 7 rows to a condition), links (the stockpile links
-- window), a minecart list, and the item settings stockpiles use.
--
-- (Inside a function, not a do block: the file's top level is at Lua's limit
-- of 200 local names, and a function's locals are its own.)
;(function()
local haul = df.global.plotinfo.hauling
local cond_ui = mi.hauling_stop_conditions
local vehicle_ui = mi.assign_vehicle
local link_ui = mi.stockpile_link
local DAY = 1200          -- ticks in a day; the game's own +/- step
local PERCENT_STEP = 25   -- the game's own +/- step for "how full"
local DIRECTIONS = {'North', 'East', 'South', 'West'}   -- d goes round clockwise
local row_has_text = ClassicKeysOverlay.info_helpers.row_has_text

-- How many entries a list shows at once. These panels and windows are as
-- tall as the game makes them, whatever they hold, so this is measured down
-- to the bottom border: the first row, going down a column of plain
-- background beside the list, where the background stops.
local function rows_that_fit(x, first, spacing)
    local plain = (dfhack.screen.readTile(x, first) or {}).tile
    local y = first + 1
    while y < gps.dimy - 1 and (dfhack.screen.readTile(x, y) or {}).tile == plain do y = y + 1 end
    return math.max(1, (y - first) // spacing)
end

local function hauling_open()
    return mi.bottom_mode_selected == BOTTOM.HAULING
end
ClassicKeysOverlay.hauling_open = hauling_open

-- the route and stop a links or conditions window is for
local function window_stop(route_id, stop_id)
    for _, route in ipairs(haul.routes) do
        if route.id == route_id then
            for _, stop in ipairs(route.stops) do
                if stop.id == stop_id then return stop, route end
            end
            return nil, route
        end
    end
end

local function stop_links_open()
    return hauling_open() and link_ui.open and link_ui.bld_id == -1
end

-- where the list starts, and how many rows of it fit
local function list_geometry()
    local x, y = find_screen_text('Add new route', {x2=80, y2=TOP_ROWS + 8})
    if not x then return end
    local first = y + 4
    return {first=first, visible=rows_that_fit(5, first, 3), panel_right=x + 17}
end

function ClassicKeysOverlay:haul_row()
    local geo = list_geometry()
    local count = #haul.view_routes
    if not geo or count == 0 then return end
    self.haul_idx = math.max(0, math.min(self.haul_idx or 0, count - 1))
    local scroll = math.max(0, math.min(haul.scroll_position, count - geo.visible))
    if self.haul_idx < scroll then
        scroll = self.haul_idx
    elseif self.haul_idx >= scroll + geo.visible then
        scroll = self.haul_idx - geo.visible + 1
    end
    haul.scroll_position = scroll
    return geo.first + 3 * (self.haul_idx - scroll), geo
end

-- the selected route, and the selected stop (nil on a route's own row)
local function selected(self)
    local idx = self.haul_idx or 0
    if idx >= #haul.view_routes then return end
    return haul.view_routes[idx], haul.view_stops[idx]
end

-- Press the n-th icon button on the selected row, counted from the right:
-- the buttons end at the same column on every row, while what comes before
-- them varies (a stop shows its minecart and how full it is once the route
-- has one). The last button ends where the row's plain background resumes,
-- inside the panel's right-hand border.
local function press_row_button(self, n)
    local row, geo = self:haul_row()
    if not row then return false end
    local function tile(x) return (dfhack.screen.readTile(x, row) or {}).tile end
    local plain = tile(5)
    local x = geo.panel_right + 1
    while x > 8 and tile(x) ~= plain do x = x - 1 end
    -- (a long list has a scroll bar right of the buttons, narrower than a
    -- button; the buttons then stand two columns further left)
    while true do
        while x > 8 and tile(x) == plain do x = x - 1 end
        if x <= 8 then return false end
        local right = x
        while x > 8 and tile(x) ~= plain do x = x - 1 end
        if right - x >= 4 then
            x = right
            break
        end
    end
    click_screen(x - 4 * n + 2, row)
    return true
end
-- the buttons, counted from the right
local ROUTE_BUTTON = {add_stop=4, vehicle=3, name=2, delete=1}
local STOP_BUTTON = {items=5, links=4, conditions=3, name=2, delete=1}

-- select a route's own row, so that its buttons can be pressed
local function select_route_row(self, route)
    for i = 0, #haul.view_routes - 1 do
        if haul.view_routes[i] == route and not haul.view_stops[i] then
            self.haul_idx = i
            return true
        end
    end
end

-- The game says where a stop goes on the panel itself while it waits for it.
local function placing_stop()
    return find_screen_text('Click a tile to position', {x2=80, y2=TOP_ROWS + 8}) ~= nil
end
ClassicKeysOverlay.placing_stop = placing_stop

local function start_aiming(self)
    self.aim = true
    self.aim_origin = self.cursor and copyall(self.cursor)
    if not self.cursor or not guidm.Viewport.get():isVisible(self.cursor) then
        self.cursor = guidm.Viewport.get():getCenter()
    end
end

local function zoom_to(pos)
    if not pos then return end
    dfhack.gui.revealInDwarfmodeMap(pos, true)
    df.global.window_z = pos.z
end

function ClassicKeysOverlay:on_hauling_input(keys)
    -- the help the game shows the first time the panel is opened
    if focus_is('dwarfmode/Help') then
        if keys.SELECT or keys.LEAVESCREEN then click_label('Okay') end
        return true
    end
    if mi.custom_stockpile.open then return self:on_pile_settings_input(keys) end
    if cond_ui.open then return self:on_stop_conditions_input(keys) end
    if vehicle_ui.open then return self:on_vehicle_input(keys) end
    if stop_links_open() then return self:on_stop_links_input(keys) end

    if placing_stop() then
        -- the stop goes where the cursor is
        start_aiming(self)
        if keys.LEAVESCREEN then
            -- the game's own Esc calls it off and leaves the panel open
            self:feed('LEAVESCREEN')
            local route_id = self.haul_route_placing
            self.haul_route_placing = nil
            if route_id then
                for _, route in ipairs(haul.routes) do
                    if route.id == route_id then select_route_row(self, route) end
                end
            end
            return true
        end
        local dx, dy, dz = self:take_move(keys)
        if dx then
            local pos = xyz2pos(self.cursor.x + dx, self.cursor.y + dy, self.cursor.z + dz)
            if dfhack.maps.isValidTilePos(pos) then self.cursor = pos end
            return true
        end
        if keys.SELECT then
            local route_id = self.haul_route_placing
            local before = 0
            for _, route in ipairs(haul.routes) do
                if route.id == route_id then before = #route.stops end
            end
            self:click_map_tile(self.cursor)
            -- select the new stop: the last of its route
            for _, route in ipairs(haul.routes) do
                if route.id == route_id and #route.stops > before then
                    local stop = route.stops[#route.stops - 1]
                    dfhack.timeout(2, 'frames', function()
                        for i = 0, #haul.view_stops - 1 do
                            if haul.view_stops[i] == stop then self.haul_idx = i end
                        end
                    end)
                end
            end
            return true
        end
        return letter_key_pressed(keys) or list_step(keys) ~= nil
    end

    if keys.LEAVESCREEN then
        self:feed('LEAVESCREEN')
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.haul_idx = (self.haul_idx or 0) + (dy or 0) + (step or 0)
        self:haul_row()
        return true
    end
    local route, stop = selected(self)
    if keys.CUSTOM_R then
        if click_label('Add new route', {x2=80, y2=TOP_ROWS + 8}) then
            -- the new route is the last row
            self.haul_idx = 100000
        end
    elseif keys.CUSTOM_S and route then
        if select_route_row(self, route) and press_row_button(self, ROUTE_BUTTON.add_stop) then
            self.haul_route_placing = route.id
            start_aiming(self)
        end
    elseif keys.CUSTOM_V and route then
        if select_route_row(self, route) then
            self.vehicle_idx = 0
            press_row_button(self, ROUTE_BUTTON.vehicle)
        end
    elseif keys.CUSTOM_N and route then
        -- (the name changes as it is typed; Esc puts this one back)
        self.haul_naming = {obj=stop or route, name=(stop or route).name}
        press_row_button(self, stop and STOP_BUTTON.name or ROUTE_BUTTON.name)
    elseif keys.CUSTOM_X and route then
        press_row_button(self, stop and STOP_BUTTON.delete or ROUTE_BUTTON.delete)
    elseif (keys.SELECT or keys.CUSTOM_C) and stop then
        self.hcond_idx = 0
        press_row_button(self, STOP_BUTTON.conditions)
    elseif keys.CUSTOM_L and stop then
        self.haul_link_idx = 0
        press_row_button(self, STOP_BUTTON.links)
    elseif keys.CUSTOM_I and stop then
        self.pile_col, self.pile_idx = 1, {0, 0, 0}
        press_row_button(self, STOP_BUTTON.items)
    elseif keys.CUSTOM_Z and route then
        zoom_to((stop or route.stops[0] or {}).pos)
    else
        return letter_key_pressed(keys)
    end
    return true
end

-- departure conditions ------------------------------------------------------------

local function conditions_geometry()
    local x, y = find_screen_text('Set conditions for', {y2=TOP_ROWS + 8})
    if not x then return end
    local done_x = find_screen_text('Done', {x1=x, y1=y, y2=y})
    local first = y + 8
    return {x=x, y=y, done_x=done_x, first=first, visible=rows_that_fit(x - 1, first, 7)}
end

function ClassicKeysOverlay:cond_row_haul()
    local geo = conditions_geometry()
    local stop = window_stop(cond_ui.route_id, cond_ui.stop_id)
    if not geo or not stop then return end
    local count = #stop.conditions
    if count == 0 then return nil, geo, stop end
    self.hcond_idx = math.max(0, math.min(self.hcond_idx or 0, count - 1))
    local scroll = math.max(0, math.min(cond_ui.scroll_position, count - geo.visible))
    if self.hcond_idx < scroll then
        scroll = self.hcond_idx
    elseif self.hcond_idx >= scroll + geo.visible then
        scroll = self.hcond_idx - geo.visible + 1
    end
    cond_ui.scroll_position = scroll
    return geo.first + 7 * (self.hcond_idx - scroll), geo, stop
end

function ClassicKeysOverlay:on_stop_conditions_input(keys)
    local row, geo, stop = self:cond_row_haul()
    if keys.LEAVESCREEN or keys.SELECT then
        if not (geo and click_label('Done', {x1=geo.x, y1=geo.y, y2=geo.y})) then cond_ui.open = false end
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.hcond_idx = (self.hcond_idx or 0) + (dy or 0) + (step or 0)
        self:cond_row_haul()
        return true
    end
    if not geo then return letter_key_pressed(keys) end
    if keys.CUSTOM_N then
        -- the add button under the window's two lines of text
        local x = ClassicKeysOverlay.first_picture_x(geo.y + 3, geo.x - 2)
        if x then
            click_screen(x + 1, geo.y + 3)
            self.hcond_idx = 100000
        end
        return true
    end
    local cond = row and stop.conditions[self.hcond_idx]
    if not cond then return letter_key_pressed(keys) end
    if keys.CUSTOM_X then
        if geo.done_x then click_screen(geo.done_x + 5, row) end
    elseif keys.CUSTOM_T then
        cond.timeout = math.max(0, cond.timeout - DAY)
    elseif keys.CUSTOM_SHIFT_T then
        cond.timeout = cond.timeout + DAY
    elseif keys.CUSTOM_F then
        cond.load_percent = math.max(0, cond.load_percent - PERCENT_STEP)
    elseif keys.CUSTOM_SHIFT_F then
        cond.load_percent = math.min(100, cond.load_percent + PERCENT_STEP)
    elseif keys.CUSTOM_M then
        cond.flags.at_most = not cond.flags.at_most
    elseif keys.CUSTOM_L then
        cond.flags.desired = not cond.flags.desired
    elseif keys.CUSTOM_D then
        local now = df.stop_depart_condition.T_direction[cond.direction]
        for i, name in ipairs(DIRECTIONS) do
            if name == now then
                cond.direction = df.stop_depart_condition.T_direction[DIRECTIONS[i % #DIRECTIONS + 1]]
                break
            end
        end
    elseif keys.CUSTOM_P then
        cond.mode = (cond.mode + 1) % 3   -- push, ride, guide
    else
        return letter_key_pressed(keys)
    end
    return true
end

-- a stop's stockpile links --------------------------------------------------------
--
-- The same window as a stockpile's links, with a third add button: give to
-- (the cart unloads into the stockpile), take from (it loads from it), both.

local function link_window()
    return find_screen_text('Done', {x1=PANEL_LEFT_BESIDE_NATIVE - 4, x2=gps.dimx - 60, y2=TOP_ROWS + 6})
end

function ClassicKeysOverlay:stop_link_row()
    local stop = window_stop(link_ui.hr_id, link_ui.hs_id)
    local x, y = link_window()
    if not stop or not x then return end
    local count = #stop.stockpiles
    if count == 0 then return nil, x, stop end
    local first = y + 6
    local visible = math.max(1, (gps.dimy - 28 - first) // 3)
    self.haul_link_idx = math.max(0, math.min(self.haul_link_idx or 0, count - 1))
    local scroll = math.max(0, math.min(link_ui.scroll_position_link_list, count - visible))
    if self.haul_link_idx < scroll then
        scroll = self.haul_link_idx
    elseif self.haul_link_idx >= scroll + visible then
        scroll = self.haul_link_idx - visible + 1
    end
    link_ui.scroll_position_link_list = scroll
    return first + 3 * (self.haul_link_idx - scroll), x, stop
end

local LINK_BUTTON = {give=-30, take=-26, both=-22}

function ClassicKeysOverlay:on_stop_links_input(keys)
    if link_ui.adding_new_link then
        -- aiming at the stockpile: the stockpile links' own keys
        return self:on_links_input(keys)
    end
    if keys.LEAVESCREEN or keys.SELECT then
        if not click_label('Done', {x1=PANEL_LEFT_BESIDE_NATIVE - 4, x2=gps.dimx - 60, y2=TOP_ROWS + 6}) then
            link_ui.open = false
        end
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.haul_link_idx = (self.haul_link_idx or 0) + (dy or 0) + (step or 0)
        self:stop_link_row()
        return true
    end
    local row, x, stop = self:stop_link_row()
    local kind = (keys.CUSTOM_G and 'give') or (keys.CUSTOM_T and 'take') or (keys.CUSTOM_B and 'both')
    if kind and x then
        click_screen(x + LINK_BUTTON[kind], TOP_ROWS + 2)
        start_aiming(self)
        self.haul_link_idx = 100000
    elseif row and (keys.CUSTOM_X or keys.CUSTOM_D) then
        click_screen(x + 5, row)
    elseif row and keys.CUSTOM_M then
        -- take, give, both, round again
        local mode = stop.stockpiles[self.haul_link_idx].mode
        if mode.take and mode.give then
            mode.give = false
        elseif mode.take then
            mode.take, mode.give = false, true
        else
            mode.take, mode.give = true, true
        end
    else
        return letter_key_pressed(keys)
    end
    return true
end

-- the minecart list ------------------------------------------------------------------

function ClassicKeysOverlay:vehicle_row()
    local x, y = find_screen_text('Choose a vehicle', {y2=TOP_ROWS + 8})
    local count = #vehicle_ui.i_vehicle
    if not x or count == 0 then return end
    local first = y + 3
    local visible = rows_that_fit(x - 2, first, 3)   -- (down the window's left border)
    self.vehicle_idx = math.max(0, math.min(self.vehicle_idx or 0, count - 1))
    local scroll = math.max(0, math.min(vehicle_ui.scroll_position, count - visible))
    if self.vehicle_idx < scroll then
        scroll = self.vehicle_idx
    elseif self.vehicle_idx >= scroll + visible then
        scroll = self.vehicle_idx - visible + 1
    end
    vehicle_ui.scroll_position = scroll
    return first + 3 * (self.vehicle_idx - scroll), x
end

function ClassicKeysOverlay:on_vehicle_input(keys)
    if keys.LEAVESCREEN then
        vehicle_ui.open = false
        return true
    end
    local dx, dy = self:take_move(keys)
    local step = list_step(keys)
    if dx or step then
        self.vehicle_idx = (self.vehicle_idx or 0) + (dy or 0) + (step or 0)
        self:vehicle_row()
        return true
    end
    if keys.SELECT then
        -- a click on its name chooses it and closes the list
        local row, x = self:vehicle_row()
        if row then click_screen(x + 8, row) end
        return true
    end
    return letter_key_pressed(keys)
end

-- the key list and the selection marks -------------------------------------------------

local function row_label(y)
    local chars = {}
    for x = 4, 36 do
        local tile = dfhack.screen.readTile(x, y)
        local ch = tile and tile.ch or 0
        chars[#chars + 1] = (ch > 31 and ch < 127) and string.char(ch) or ' '
    end
    return (table.concat(chars):gsub('^%s+', ''):gsub('%s+$', ''))
end

-- title, lines, and where the list goes: beside the panel, or under the
-- minimap while one of the windows fills the middle of the screen
function ClassicKeysOverlay:hauling_lines()
    if focus_is('dwarfmode/Help') then
        return 'Hauling', {{hint('Enter', 'close the help')}}
    elseif mi.custom_stockpile.open then
        return 'Stop: items it loads', self:pile_settings_lines(), true
    elseif cond_ui.open then
        local _, _, stop = self:cond_row_haul()
        local cond = stop and stop.conditions[self.hcond_idx or 0]
        local lines = {
            {hint('- =', 'select')},
            {hint('n', 'new  '), hint('x', 'delete')},
            {hint('t T', 'days -/+')},
            {hint('f F', 'full % -/+')},
            {hint('m', cond and cond.flags.at_most and 'at most' or 'at least')},
            {hint('l', cond and cond.flags.desired and 'desired items' or 'any items')},
            {hint('d', 'direction')},
            {hint('p', 'push/ride/guide')},
            {hint('Esc', 'done')},
        }
        return 'Departure', lines, true
    elseif vehicle_ui.open then
        return 'Minecart', {
            {hint('- =', 'select')},
            {hint('Enter', 'assign')},
            {hint('Esc', 'cancel')},
        }, true
    elseif stop_links_open() then
        if link_ui.adding_new_link then
            return 'Link', {
                {{text='cursor on the stockpile', pen=COLOR_GREY}},
                {hint('Enter', 'link it')},
                {hint('Esc', 'cancel')},
            }, true
        end
        return 'Stop links', {
            {hint('t', 'take from pile')},
            {hint('g', 'give to pile')},
            {hint('b', 'both')},
            {hint('- =', 'select')},
            {hint('m', 'take/give/both')},
            {hint('x', 'delete link')},
            {hint('Esc', 'done')},
        }, true
    elseif haul.entering_nickname then
        return 'Name', {
            {{text='Type the name', pen=COLOR_GREY}},
            {hint('Enter', 'done  '), hint('Esc', 'cancel')},
        }
    elseif placing_stop() then
        return 'New stop', {
            {{text='Put the cursor where it goes', pen=COLOR_GREY}},
            {hint('arrows', 'move  '), hint('Enter', 'place it  '), hint('Esc', 'cancel')},
        }
    end
    local route, stop = selected(self)
    local row = self:haul_row()
    local lines = {}
    if route then
        lines[#lines + 1] = {{text=row and row_label(row) or '', pen=COLOR_LIGHTCYAN}}
    else
        lines[#lines + 1] = {{text='no routes yet', pen=COLOR_GREY}}
    end
    lines[#lines + 1] = {hint('- =', 'select  '), hint('r', 'new route')}
    if route then
        lines[#lines + 1] = {hint('s', 'new stop  '), hint('v', 'minecart  '), hint('n', 'name')}
    end
    if stop then
        lines[#lines + 1] = {hint('Enter', 'conditions  '), hint('l', 'links  '), hint('i', 'items')}
        lines[#lines + 1] = {hint('z', 'zoom  '), hint('x', 'delete stop')}
    elseif route then
        lines[#lines + 1] = {hint('z', 'zoom  '), hint('x', 'delete route')}
    end
    lines[#lines + 1] = {hint('Esc', 'done')}
    return 'Hauling', lines
end

function ClassicKeysOverlay:render_hauling_markers()
    if focus_is('dwarfmode/Help') then return end
    if mi.custom_stockpile.open then
        self:render_pile_marker()
    elseif cond_ui.open then
        local row, geo = self:cond_row_haul()
        if row then mark_row(geo.x - 2, row, 60) end
    elseif vehicle_ui.open then
        local row, x = self:vehicle_row()
        if row then mark_row(x + 3, row, 30) end
    elseif stop_links_open() then
        if not link_ui.adding_new_link then
            local row, x = self:stop_link_row()
            if row then mark_row(x - 25, row, 28) end
        end
    elseif not placing_stop() then
        local row = self:haul_row()
        if row then mark_row(4, row, 30) end
    end
end

-- Esc while a name is typed: the game's own Esc closes the whole panel and
-- leaves the typing switched on, with what was typed kept
function ClassicKeysOverlay:cancel_hauling_name()
    local naming = self.haul_naming
    if naming and naming.obj then naming.obj.name = naming.name end
    self.haul_naming = nil
    haul.entering_nickname = false
end

function ClassicKeysOverlay.hauling_panel_x()
    local geo = list_geometry()
    return geo and geo.panel_right + 2 or 61
end

-- the cursor is borrowed while a stop or a stop's link is being placed
function ClassicKeysOverlay.hauling_aiming()
    return hauling_open() and (placing_stop() or (link_ui.open and link_ui.adding_new_link))
end

end)()

-- the main menu (?) ------------------------------------------------------------------
--
-- The old game listed its top-level keys down the side of the map. Here the
-- same list, in the old menu's order, is a panel over the map's corner that ?
-- shows and hides. The choice is kept between sessions.
do
local json = require('json')
local settings = json.open('dfhack-config/classic-controls.json')

local ROOT_MENU = make_entries{
    {'a', 'Announcements'},
    {'b', 'Building', submenu=true},
    {'r', 'Reports'},
    {'c', 'World and civilizations'},
    {'d', 'Designations', submenu=true},
    {'o', 'Work orders (manager)'},
    {'u', 'Unit list'},
    {'j', 'Job list'},
    {'m', 'Military (or s: squads)'},
    {'w', 'Burrows'},
    {'h', 'Hauling'},
    {'p', 'Stockpiles', submenu=true},
    {'i', 'Zones', submenu=true},
    {'q', 'Building tasks / prefs'},
    {'t', 'Items in buildings'},
    {'v', 'View units'},
    {'k', 'Look'},
    {'H', 'Hot keys (F1 to F8)'},
    {'l', 'Locations'},
    {'n', 'Nobles'},
    {'z', 'Stocks'},
    {'y', 'Labor', new=true},
    {'L', 'Artifacts'},
    {'J', 'Justice'},
}

function ClassicKeysOverlay.root_keys_on()
    return settings.data.root_keys == true
end

function ClassicKeysOverlay.toggle_root_keys()
    settings.data.root_keys = not ClassicKeysOverlay.root_keys_on()
    pcall(function() settings:write() end)
end

-- the map with nothing of the game's or ours open over it
function ClassicKeysOverlay.on_bare_map()
    if mi.bottom_mode_selected ~= BOTTOM.NONE or vs.open then return false end
    local focus = dfhack.gui.getFocusStrings(dfhack.gui.getDFViewscreen(true))
    return #focus == 1 and focus[1] == 'dwarfmode/Default'
end

function ClassicKeysOverlay.root_lines()
    local lines, width = build_menu_lines(ROOT_MENU, 12)
    lines[#lines + 1] = {hint('< >', 'level  '), hint('arrows', 'scroll (Shift: ten tiles)')}
    lines[#lines + 1] = {hint('Space', 'pause  '), hint('.', 'one step  '), hint('Esc', 'options')}
    lines[#lines + 1] = {hint('?', 'hide this list')}
    return lines, width
end

end -- of the main menu block

function ClassicKeysOverlay:on_map_input(keys)
    if keys._STRING == 63 then
        -- ?: the list of top-level keys, on and off
        ClassicKeysOverlay.toggle_root_keys()
        return true
    end
    for key, mode in pairs(MODE_KEYS) do
        if keys[key] then
            if mode == 'look' then self:close_sheet() end
            self:enter_mode(mode)
            return true
        end
    end
    local seq = lookup(TOP_KEYS, keys)
    if seq then
        self:exit_mode()
        self:run_sequence(seq)
        return true
    end
    if keys.CUSTOM_R then
        -- the old reports screen: every creature's combat, sparring and
        -- hunting reports, the latest first
        self:exit_mode()
        ClassicKeysOverlay.show_reports()
        return true
    end
    -- on the map - and = do nothing: levels are < and >, as they were
    return list_step(keys) ~= nil
end

-- a new designation replaces the old one ---------------------------------------------
--
-- Left to itself the game replaces some designations with a new one laid
-- over them (channel over mine) but not others: stairs do not replace a
-- mining designation, and smoothing and digging are simply both kept on the
-- tile. Here the tile's old designations are taken off just before the game
-- applies the new box, and put back on every tile the new one did not take
-- (a tree in a mining box keeps its felling order).
--
-- The game does not show where it keeps a box's first corner, so both Enters
-- are given to it from here and the corner is remembered alongside.
do
local NO_DIG = df.tile_dig_designation.No
local REPLACING = utils.invert{
    'DIG_DIG', 'DIG_REMOVE_STAIRS_RAMPS', 'DIG_STAIR_UP', 'DIG_STAIR_UPDOWN', 'DIG_STAIR_DOWN',
    'DIG_RAMP', 'DIG_CHANNEL', 'CHOP', 'GATHER', 'SMOOTH', 'TRACK', 'ENGRAVE', 'FORTIFY',
    'REMOVE_CONSTRUCTION',
}
local TRACKS = {'carve_track_north', 'carve_track_south', 'carve_track_east', 'carve_track_west'}
-- jobs dwarves may already have taken for a designation that is then replaced
local WORK = {}
for _, name in ipairs{
    'Dig', 'CarveUpwardStaircase', 'CarveDownwardStaircase', 'CarveUpDownStaircase', 'CarveRamp',
    'DigChannel', 'FellTree', 'GatherPlants', 'RemoveConstruction', 'SmoothWall', 'SmoothFloor',
    'DetailWall', 'DetailFloor', 'CarveFortification', 'CarveTrack', 'RemoveStairs',
} do
    if df.job_type[name] then WORK[df.job_type[name]] = true end
end

local function tile_key(x, y, z)
    return x + y * 1000 + z * 1000000
end

-- the designation each kind of job was made from: {dig, smooth}. (Felling,
-- gathering and removing a construction or stairs are all the plain "dig"
-- flag on their tile, as they always were.)
local DIG = df.tile_dig_designation
local FROM_JOB = {}
for name, des in pairs{
    Dig={DIG.Default, 0}, CarveUpwardStaircase={DIG.UpStair, 0},
    CarveDownwardStaircase={DIG.DownStair, 0}, CarveUpDownStaircase={DIG.UpDownStair, 0},
    CarveRamp={DIG.Ramp, 0}, DigChannel={DIG.Channel, 0}, FellTree={DIG.Default, 0},
    GatherPlants={DIG.Default, 0}, RemoveConstruction={DIG.Default, 0}, RemoveStairs={DIG.Default, 0},
    SmoothWall={NO_DIG, 1}, SmoothFloor={NO_DIG, 1}, CarveFortification={NO_DIG, 1},
    DetailWall={NO_DIG, 2}, DetailFloor={NO_DIG, 2},
} do
    if df.job_type[name] then FROM_JOB[df.job_type[name]] = des end
end

function ClassicKeysOverlay.jobs_back_to_designations(from, to)
    local x1, x2 = math.min(from.x, to.x), math.max(from.x, to.x)
    local y1, y2 = math.min(from.y, to.y), math.max(from.y, to.y)
    local z1, z2 = math.min(from.z, to.z), math.max(from.z, to.z)
    local found = {}
    for _, job in utils.listpairs(df.global.world.jobs.list) do
        local p = job.pos
        if FROM_JOB[job.job_type] and p.x >= x1 and p.x <= x2 and p.y >= y1 and p.y <= y2
            and p.z >= z1 and p.z <= z2
        then
            found[#found + 1] = job
        end
    end
    for _, job in ipairs(found) do
        local p = job.pos
        local des = FROM_JOB[job.job_type]
        local x, y, z = p.x, p.y, p.z
        dfhack.job.removeJob(job)
        local flags = dfhack.maps.getTileFlags(x, y, z)
        if flags then
            if des[1] ~= NO_DIG then flags.dig = des[1] end
            if des[2] ~= 0 then flags.smooth = des[2] end
            local block = dfhack.maps.getTileBlock(x, y, z)
            if block then block.flags.designated = true end
        end
    end
end

function ClassicKeysOverlay:on_designation_corner()
    local pos = guidm.getCursorPos()
    local tool = current_designation()
    if not pos or not self.des_corner or self.des_tool ~= tool then
        self.des_corner, self.des_tool = pos, tool
        self:feed('SELECT')
        return true
    end
    local from = self.des_corner
    self.des_corner = nil
    if not REPLACING[tool] then
        self:feed('SELECT')
        return true
    end

    -- A designation a dwarf has already taken on is no longer on the tile:
    -- the game clears the tile's flag and keeps the order as a job, and it
    -- will not designate anything over a tile that has one. So the jobs in
    -- the box are turned back into the designations they came from (and are
    -- re-made by the game from whatever the tile ends up with).
    ClassicKeysOverlay.jobs_back_to_designations(from, pos)

    -- what is designated in the box now, taken off for the moment
    local saved = {}
    for z = math.min(from.z, pos.z), math.max(from.z, pos.z) do
        for y = math.min(from.y, pos.y), math.max(from.y, pos.y) do
            for x = math.min(from.x, pos.x), math.max(from.x, pos.x) do
                local des, occ = dfhack.maps.getTileFlags(x, y, z)
                if des and occ then
                    local tracks = occ.carve_track_north or occ.carve_track_south
                        or occ.carve_track_east or occ.carve_track_west
                    if des.dig ~= NO_DIG or des.smooth ~= 0 or tracks then
                        local old = {x=x, y=y, z=z, dig=des.dig, smooth=des.smooth,
                                     dig_marked=occ.dig_marked, dig_auto=occ.dig_auto}
                        for _, bit in ipairs(TRACKS) do
                            old[bit] = occ[bit]
                            occ[bit] = false
                        end
                        des.dig, des.smooth = NO_DIG, 0
                        occ.dig_marked, occ.dig_auto = false, false
                        saved[#saved + 1] = old
                    end
                end
            end
        end
    end

    self:feed('SELECT')

    -- where the new designation took, the old is gone; elsewhere it comes back
    local replaced, any = {}, false
    for _, old in ipairs(saved) do
        local des, occ = dfhack.maps.getTileFlags(old.x, old.y, old.z)
        local tracks = occ.carve_track_north or occ.carve_track_south
            or occ.carve_track_east or occ.carve_track_west
        if des.dig ~= NO_DIG or des.smooth ~= 0 or tracks then
            local same = des.dig == old.dig and des.smooth == old.smooth
            for _, bit in ipairs(TRACKS) do
                if occ[bit] ~= old[bit] then same = false end
            end
            if not same then
                replaced[tile_key(old.x, old.y, old.z)] = true
                any = true
            end
        else
            des.dig, des.smooth = old.dig, old.smooth
            occ.dig_marked, occ.dig_auto = old.dig_marked, old.dig_auto
            for _, bit in ipairs(TRACKS) do occ[bit] = old[bit] end
            local block = dfhack.maps.getTileBlock(old.x, old.y, old.z)
            if block then block.flags.designated = true end
        end
    end

    -- a dwarf already on the way to do the old work is called off
    if any then
        local stale = {}
        for _, job in utils.listpairs(df.global.world.jobs.list) do
            if WORK[job.job_type] and replaced[tile_key(job.pos.x, job.pos.y, job.pos.z)] then
                stale[#stale + 1] = job
            end
        end
        for _, job in ipairs(stale) do dfhack.job.removeJob(job) end
    end
    return true
end

end -- of the designation overwrite block

function ClassicKeysOverlay:onInput(keys)
    if self.simulating then return false end
    if key_log_enabled then log_keys(keys) end
    if keys._MOUSE_L or keys._MOUSE_R or keys._MOUSE_M then
        -- (a box started or finished with the mouse is not one we are following)
        self.des_corner = nil
        return false
    end
    -- the materials filter box is being typed in (the overlay framework
    -- already keeps us out of the game's other text fields)
    if con.entering_item_filter then return false end
    -- the game's word-by-word name builder, and names being typed for a
    -- squad or a patrol route (Esc there is still ours: see on_squads_input)
    if mi.name_creator.open and (mi.name_creator.entering_cull_str or mi.name_creator.entering_first_name) then
        return false
    end
    -- a filter of a task's details, or a count on a location's page
    if mi.job_details.open and ClassicKeysOverlay.job_details_filtering() then return false end
    if mi.location_details.open and mi.location_details.entering_desired_number ~= nil then return false end
    if not keys.LEAVESCREEN and ((mi.trade.open and (mi.trade.entering_item_filter[0]
            or mi.trade.entering_item_filter[1] or mi.trade.entering_amount ~= 0))
        or (mi.assign_trade.open and mi.assign_trade.entering_item_filter))
    then
        return false
    end
    if mi.bottom_mode_selected == BOTTOM.HAULING and df.global.plotinfo.hauling.entering_nickname then
        if keys.LEAVESCREEN then
            self:cancel_hauling_name()
            return true
        end
        return false
    end
    if squads_open() and not keys.LEAVESCREEN
        and (sq.entering_squad_nickname or routes_ui.entering_new_route_name
             or sq.entering_cell_nickname or sched.entering_routine_name)
    then
        return false
    end

    -- A handler that fails must not let its key through: the game would take
    -- it as one of its own hotkeys (and a letter there can start a
    -- designation or open another window). The key is dropped instead.
    local ok, handled = pcall(function()
        return self:dispatch(keys) or self:on_level_keys(keys)
    end)
    if not ok then
        dfhack.printerr('classic-controls: ' .. tostring(handled))
        handled = true
    end
    self:refresh_panel()
    if handled and (self.mode or self.paint or self.order or self.aim) and self.cursor then
        self:keep_cursor_clear()
    end
    return handled
end

function ClassicKeysOverlay:dispatch(keys)
    -- Esc backs out of the game's add-task list one level, as it used to,
    -- instead of closing the whole panel with the list still up
    if keys.LEAVESCREEN and add_task_list_open() and click_label('Cancel') then
        return true
    end

    -- the windows that open over anything else
    local window = ClassicKeysOverlay.detail_window()
    if window == 'name' then
        return self:on_name_creator_input(keys)
    elseif window == 'job' then
        return self:on_job_details_input(keys)
    elseif window == 'location' then
        -- (the list of dwarves for one of its occupations stands in front of it)
        if unit_selector_open() then return self:on_unit_selector_input(keys) end
        return self:on_location_details_input(keys)
    end

    if focus_is('dwarfmode/Announcements') then
        self:exit_mode()
        return self:on_announcements_input(keys)
    end
    if squads_open() then
        self:exit_mode()
        return self:on_squads_input(keys)
    end
    if mi.info.open or mi.create_work_order.open then
        self:exit_mode()
        return self:on_info_input(keys)
    end
    if mi.location_selector.open then
        return self:on_location_input(keys)
    elseif focus_is('dwarfmode/SquadSelector') then
        return self:on_squad_selector_input(keys)
    elseif unit_selector_open() then
        -- the unit list outside the squads screen: a zone's animals or owner
        return self:on_unit_selector_input(keys)
    end
    if mi.assign_trade.open then
        self:exit_mode()
        return self:on_goods_input(keys)
    elseif mi.trade.open then
        self:exit_mode()
        return self:on_trade_input(keys)
    end

    local bottom = mi.bottom_mode_selected
    if bottom == BOTTOM.HAULING then
        self:exit_mode()
        return self:on_hauling_input(keys)
    elseif bottom == BOTTOM.BUILDING then
        self:exit_mode()
        return self:on_build_menu_input(keys)
    elseif bottom == BOTTOM.BUILDING_PLACEMENT then
        return self:on_placement_input(keys)
    elseif bottom == BOTTOM.BUILDING_PICK_MATERIALS then
        return self:on_pick_materials_input(keys)
    elseif bottom == BOTTOM.STOCKPILE_PAINT then
        self:exit_mode()
        return self:on_paint_input(keys, 'stockpile')
    elseif bottom == BOTTOM.ZONE_PAINT then
        self:exit_mode()
        return self:on_paint_input(keys, 'zone')
    elseif bottom == BOTTOM.STOCKPILE or bottom == BOTTOM.ZONE then
        local handled
        if bottom == BOTTOM.STOCKPILE then
            handled = self:on_stockpile_panel_input(keys)
        else
            handled = self:on_zone_list_input(keys)
        end
        if handled then return true end
        -- q keeps its cursor while one of these panels is up
        return self.mode ~= nil and self:on_mode_input(keys)
    end

    if self.mode and self:on_mode_input(keys) then
        return true
    end

    local focus = current_focus()
    if designating() then
        local desig = current_designation()
        local keymap = (ITEM_DESIGNATIONS[desig] and ITEM_KEYS)
            or (TRAFFIC_DESIGNATIONS[desig] and TRAFFIC_KEYS)
            or DESIGNATE_KEYS
        local seq = lookup(keymap, keys)
        if seq then
            -- The game puts its cursor back in the middle of the view for
            -- each tool; the old one left it where it was.
            local pos = guidm.getCursorPos()
            self.des_corner = nil       -- a new tool starts a new box
            self:run_sequence(seq)
            if pos then
                local function restore()
                    if designating() then guidm.setCursorPos(pos) end
                end
                restore()
                dfhack.timeout(1, 'frames', restore)
            end
            return true
        end
        if keys.SELECT then return self:on_designation_corner() end
        if self:on_native_cursor_input(keys) then return true end
        -- - and + set the designation priority, as they did; they must not
        -- reach the game as "cursor up/down a level"
        local step = list_step(keys)
        if step then
            if keymap == DESIGNATE_KEYS then
                -- the game only takes its priority keys with this panel showing
                mi.designation.show_advanced_options = true
                self:feed(step > 0 and 'DESIGNATE_PRIORITY_UP' or 'DESIGNATE_PRIORITY_DOWN')
            end
            return true
        end
    elseif focus_has(focus, 'dwarfmode/Default') or focus_has(focus, 'dwarfmode/ViewSheets') then
        -- a workshop's own keys (a, r, s, n, c) win over the map-level ones,
        -- whether the panel was opened with q or with the mouse
        local bld = viewed_building()
        if not self.mode and bld and keys.CUSTOM_X and not add_task_list_open() then
            self:toggle_building_removal(bld)
            return true
        end
        if not self.mode and bld and keys.CUSTOM_S and not add_task_list_open()
            and ClassicKeysOverlay.toggle_construction_suspend(bld)
        then
            return true
        end
        if not self.mode and bld and ClassicKeysOverlay.is_farm(bld) then
            local handled = self:on_farm_input(keys, bld)
            if handled ~= nil then return handled end
        end
        if not self.mode and is_workshop(bld) and not add_task_list_open()
            and self:on_workshop_input(keys, bld)
        then
            return true
        end
        if not self.mode and bld and df.building_tradedepotst:is_instance(bld)
            and self:on_depot_input(keys, bld)
        then
            return true
        end
        -- a creature's sheet opened with the mouse takes the unit keys too
        local unit = viewed_unit()
        if not self.mode and unit and self:on_unit_sheet_input(keys, unit) then
            return true
        end
        return self:on_map_input(keys)
    end
    return false
end

---------------------------------------------------------------------------
-- rendering
---------------------------------------------------------------------------

-- The area a wall, floor, road, farm plot (anything sized with two corners)
-- will cover while it is being sized with the keyboard. The game draws this
-- only for a box dragged with the mouse; with the keys it shows nothing
-- between the first Enter and the second. The overlay draws it instead, with
-- the marks DFHack's own placement tools use: green where the tile looks
-- free, red where something is in the way (unexplored, solid rock, another
-- building). The game has the last word when the second Enter is pressed.
do
-- The marks' pictures are looked up when drawn, not once: the game reloads
-- its graphics with every save it loads and the numbers change, so a number
-- kept from an earlier save shows as a black square.
local GOOD, BAD
local function update_pens()
    local good = dfhack.screen.findGraphicsTile('CURSORS', 1, 2)
    if GOOD and GOOD.tile == good then return end
    GOOD = dfhack.pen.parse{ch='o', fg=COLOR_GREEN, tile=good}
    BAD = dfhack.pen.parse{ch='X', fg=COLOR_RED, tile=dfhack.screen.findGraphicsTile('CURSORS', 3, 0)}
end
local WALL = df.tiletype_shape_basic.Wall

local function looks_free(pos)
    local tt = dfhack.maps.getTileType(pos)
    local des = dfhack.maps.getTileFlags(pos)
    if not tt or not des or des.hidden then return false end
    local shape = df.tiletype.attrs[tt].shape
    if df.tiletype_shape.attrs[shape].basic_shape == WALL then return false end
    return dfhack.buildings.findAtTile(pos) == nil
end

-- Buildings of a fixed size (workshops, furnaces, the depot, siege engines,
-- pumps, wheels...) are previewed by the game at the mouse pointer, not at
-- the keyboard cursor where Enter puts them. Their footprint is drawn here at
-- the cursor instead, sized and centred as the game places it.
local NEEDS_FLOOR = {}
for _, name in ipairs{'Workshop', 'Furnace', 'TradeDepot', 'SiegeEngine'} do
    if df.building_type[name] then NEEDS_FLOOR[df.building_type[name]] = true end
end

local function footprint_ok(pos, floor_only)
    if not looks_free(pos) then return false end
    local tt = dfhack.maps.getTileType(pos)
    local basic = df.tiletype_shape.attrs[df.tiletype.attrs[tt].shape].basic_shape
    if floor_only and basic ~= df.tiletype_shape_basic.Floor then return false end
    local ok, free = pcall(dfhack.buildings.checkFreeTiles, pos, {x=1, y=1}, nil, false, false, false, false)
    return not ok or free
end

local function render_footprint(cursor)
    local ok, flexible, w, h, cx, cy = pcall(dfhack.buildings.getCorrectSize, 1, 1,
        buildreq.building_type, buildreq.building_subtype, buildreq.custom_type, buildreq.direction)
    -- (a building sized by its two corners shows nothing until the first)
    if not ok or flexible or (w <= 1 and h <= 1) then return end
    if cursor.z ~= df.global.window_z then return end
    local floor_only = NEEDS_FLOOR[buildreq.building_type]
    local x1, y1 = cursor.x - cx, cursor.y - cy
    guidm.renderMapOverlay(function(pos, is_cursor)
        if is_cursor then return end   -- the game's own cursor stays on top
        return footprint_ok(pos, floor_only) and GOOD or BAD
    end, {x1=x1, x2=x1 + w - 1, y1=y1, y2=y1 + h - 1})
end

function ClassicKeysOverlay.render_placement_ghost()
    local to = guidm.getCursorPos()
    if not to then return end
    update_pens()
    local from = buildreq.selection_pos
    if from.x < 0 then
        render_footprint(to)
        return
    end
    local z = df.global.window_z
    if z < math.min(from.z, to.z) or z > math.max(from.z, to.z) then return end
    guidm.renderMapOverlay(function(pos, is_cursor)
        if is_cursor then return end   -- the game's own cursor stays on top
        return looks_free(pos) and GOOD or BAD
    end, {x1=math.min(from.x, to.x), x2=math.max(from.x, to.x),
          y1=math.min(from.y, to.y), y2=math.max(from.y, to.y)})
end

end -- of the placement ghost block

function ClassicKeysOverlay:onRenderFrame(dc, rect)
    local focus = current_focus()
    local bottom = mi.bottom_mode_selected

    self:check_scroll()

    -- a mode only makes sense on the map, with one of the sheets we opened,
    -- or (for q) with a stockpile or zone panel up
    local query_panel = (self.mode == 'query' or self.mode == 'items')
        and (bottom == BOTTOM.STOCKPILE or bottom == BOTTOM.ZONE)
    if self.mode and (designating() or not (query_panel
        or focus_has(focus, 'dwarfmode/Default') or focus_has(focus, 'dwarfmode/ViewSheets')))
    then
        self:exit_mode()
    end

    -- keep the classic build / paint state in step with the game's
    if bottom == BOTTOM.BUILDING then
        self.build_menu = self.build_menu or 'top'
    else
        self.build_menu = nil
    end
    local painting = bottom == BOTTOM.STOCKPILE_PAINT or bottom == BOTTOM.ZONE_PAINT
    if painting then
        self:ensure_paint_state()
    else
        self.paint = nil
    end
    if bottom ~= BOTTOM.STOCKPILE then
        self.sp_pending_id = nil
    end
    local picking = bottom == BOTTOM.BUILDING_PICK_MATERIALS
    if bottom ~= self.last_bottom or (picking and buildreq.req_index ~= self.last_req) then
        -- a new materials list: start from its first row and find it afresh
        self.mat_idx = 0
        self.mat_anchor_key = nil
        self.last_bottom = bottom
        self.last_req = buildreq.req_index
    end

    local building = bottom == BOTTOM.BUILDING or bottom == BOTTOM.BUILDING_PLACEMENT or picking
    local piles_or_zones = painting or bottom == BOTTOM.STOCKPILE or bottom == BOTTOM.ZONE
    local squads = mi.squads.open
    if not squads then self.order = nil end
    -- aiming a stockpile link at its other end
    if not (bottom == BOTTOM.STOCKPILE and mi.stockpile_link.open and mi.stockpile_link.adding_new_link)
        and not ClassicKeysOverlay.hauling_aiming()
    then
        if self.aim and self.aim_origin then self.cursor = self.aim_origin end
        self.aim, self.aim_origin = nil, nil
    end
    local trading = not squads and (mi.trade.open or mi.assign_trade.open)
    local info_open = not squads and not trading and (mi.info.open or mi.create_work_order.open)
    -- One cursor, as there used to be: a designation or a building being
    -- placed starts where k / q / v (or the last designation or building)
    -- left it, if that is still in view, and leaves it where the next of
    -- them will start. (The game puts its own cursor back in the middle of
    -- the view each time; it is moved back here, and again a frame later.)
    local designating_now = designating()
    local native_cursor = designating_now or bottom == BOTTOM.BUILDING_PLACEMENT
    if native_cursor and not self.was_native_cursor then
        local start = self.cursor
        if start and guidm.Viewport.get():isVisible(start) then
            guidm.setCursorPos(start)
            dfhack.timeout(1, 'frames', function()
                if designating() or mi.bottom_mode_selected == BOTTOM.BUILDING_PLACEMENT then
                    guidm.setCursorPos(start)
                end
            end)
        end
    elseif native_cursor then
        local pos = guidm.getCursorPos()
        if pos then self.cursor = pos end
    end
    if not designating_now then self.des_corner = nil end
    self.was_native_cursor = native_cursor
    self.was_designating = designating_now

    self:hold_the_clock(focus)

    -- Typing a zone's or stockpile's name raises entering_building_name, and
    -- while it is up DFHack gives overlays no keys at all. Esc out of the
    -- typing closes the panel but leaves the flag up, which would leave the
    -- overlay deaf until some other name was typed. With no zone, stockpile
    -- or building panel open there is no name being typed, so it comes down.
    if mi.entering_building_name and bottom == BOTTOM.NONE and not vs.open then
        mi.entering_building_name = false
    end
    -- (the same for a hauling route's or stop's name)
    if df.global.plotinfo.hauling.entering_nickname and bottom ~= BOTTOM.HAULING then
        df.global.plotinfo.hauling.entering_nickname = false
    end

    self.labor_clock = (self.labor_clock or 299) + 1
    if self.labor_clock >= 300 then
        self.labor_clock = 0
        local ok, on = pcall(function()
            local labors = reqscript('classic-labors')
            labors.tick()
            return labors.is_on()
        end)
        self.classic_labors_on = ok and on or false
    end

    local detail_window = ClassicKeysOverlay.detail_window()
    local announcements = focus_has(focus, 'dwarfmode/Announcements')
    -- The window starts on its latest entry each time it is opened. (Closing
    -- a fight's report inside it reads as "closed" for a frame, so the
    -- selection is only forgotten once it has stayed shut for a moment.)
    if announcements then
        self.an_shut = 0
    elseif self.an_tab then
        self.an_shut = (self.an_shut or 0) + 1
        if self.an_shut > 20 then self.an_tab, self.an_idx, self.an_saved = nil, nil, nil end
    end
    local want_panel = self.mode
        or (ClassicKeysOverlay.root_keys_on() and ClassicKeysOverlay.on_bare_map())
        or announcements
        or detail_window
        or squads
        or info_open
        or trading
        or designating()
        or building
        or piles_or_zones
        or bottom == BOTTOM.HAULING
        or (focus_has(focus, 'dwarfmode/ViewSheets/BUILDING') and is_workshop(viewed_building()))
        or (focus_has(focus, 'dwarfmode/ViewSheets/BUILDING/FarmPlot'))
    -- (only read while its panel is open: the game leaves the pointer as it
    -- was, and after another save has been loaded it points at a building of
    -- that save, which fails every frame)
    local pile = bottom == BOTTOM.STOCKPILE and mi.stockpile.cur_bld or nil
    local key = table.concat({
        tostring(self.mode), tostring(want_panel and true), mi.main_designation_selected,
        vs.active_id, bottom, tostring(self.build_menu), gps.dimx, gps.dimy,
        tostring(self.sp_type and self.sp_type.label), tostring(self.sp_pending_id),
        mi.civzone.adding_new_type,
        (bottom == BOTTOM.STOCKPILE and pile) and pile.id or -1,
        (bottom == BOTTOM.ZONE and mi.civzone.cur_bld) and mi.civzone.cur_bld.id or -1,
        bottom == BOTTOM.ZONE and tostring(ClassicKeysOverlay.dfhack_room_box_bottom()) or '',
    }, '/')
    if want_panel then
        -- job lists change under us while the game runs, so rebuild every frame
        -- in the cases where the panel shows live data
        if self.panel_key ~= key or detail_window or announcements or squads or info_open or trading or mi.custom_stockpile.open
            or mi.stockpile_link.open or is_workshop(viewed_building()) or bottom == BOTTOM.HAULING
        then
            self:refresh_panel()
        end
    elseif self.subviews.panel.visible then
        self:hide_panel()
    end
    self.panel_key = key

    local bld = viewed_building()
    if is_workshop(bld) and not add_task_list_open() and not self:listing_building_items(bld) then
        self:render_job_marker(bld)
    end

    if bottom == BOTTOM.BUILDING_PLACEMENT then ClassicKeysOverlay.render_placement_ghost() end
    if focus_has(focus, 'dwarfmode/ViewSheets/BUILDING/FarmPlot') and ClassicKeysOverlay.is_farm(bld) then
        self:render_farm_marker(bld)
    end

    if picking and #buildreq.choices > 0 then
        local anchor = self:materials_anchor()
        if anchor then
            local row = self:material_row(anchor)
            if row >= anchor.first_row and row < gps.dimy - BOTTOM_ROWS then
                mark_row(anchor.x + 6, row, 44)
            end
        end
    end

    -- the selected row of a creature's Labor page
    if focus_has(focus, 'dwarfmode/ViewSheets/UNIT/Labor') then self:render_unit_labor_marker() end
    -- the selected choice of the expel panel
    if vs.open and vs.unit_overview_expelling and #vs.unit_overview_expel_dest_stid > 0 then
        local expel_x, _, confirm_y = self:expel_confirm()
        if expel_x then
            mark_row(expel_x - 1, confirm_y, 6)
        else
            local x, y = self:expel_rows()
            if x then mark_row(x - 1, y + 3 * (self.expel_idx or 0), 40) end
        end
    end
    if announcements then self:render_announcement_marker() end
    -- the selected row of the windows that open over the rest
    if not focus_has(focus, 'dwarfmode/UnitSelector') then
        if detail_window == 'name' then
            self:render_name_creator_marker()
        elseif detail_window == 'job' then
            self:render_job_details_marker()
        elseif detail_window == 'location' then
            self:render_location_details_marker()
        end
    end
    -- the selected row of the work order and nobles screens
    if info_open and not detail_window then self:render_info_markers() end
    if trading then self:render_trade_markers() end
    -- and of the detailed stockpile settings, or a stockpile's links
    if bottom == BOTTOM.HAULING then
        self:render_hauling_markers()
    elseif bottom == BOTTOM.STOCKPILE and mi.custom_stockpile.open then
        self:render_pile_marker()
    elseif bottom == BOTTOM.STOCKPILE and mi.stockpile_link.open then
        self:render_link_marker()
    end

    -- the rectangle being stretched from its first corner to the cursor
    -- the selected row of the unit list
    if mi.location_selector.open or focus_has(focus, 'dwarfmode/SquadSelector') then
        self:render_zone_chooser_marker()
    end
    if focus_has(focus, 'dwarfmode/UnitSelector') then
        local first, _, x = unit_selector_rows()
        mark_row(x - 6, first + UNIT_ROW_H * (self.usel_idx or 0), 40)
    end

    -- the selected position of the squad being looked at
    if squads and mi.squads.viewing_squad_index ~= -1 and not mi.squads.disband_confirmation
        and not (mi.squad_equipment.open or mi.squad_schedule.open or mi.create_squad.open
                 or mi.assign_uniform.open or focus_has(focus, 'dwarfmode/UnitSelector')
                 or mi.patrol_routes.open or mi.burrow_selector.open)
    then
        local x, row = self:position_row()
        if x then mark_row(x, row, 22) end
    end

    -- the selected row of the burrow and patrol route pickers
    if squads and mi.burrow_selector.open then
        local x, row = self:burrow_row()
        if x then mark_row(x, row, 30) end
    elseif squads and mi.patrol_routes.open then
        local x, row
        if mi.patrol_routes.adding_new_route then
            x, row = self:route_point_row()
        else
            x, row = self:route_row()
        end
        if x then mark_row(x - 1, row, 28) end
    end

    -- the selected row of the two new-squad lists
    if squads and (mi.create_squad.open or (mi.assign_uniform.open and not mi.squad_equipment.open)) then
        local step = new_squad_step()
        local x, row = self:new_squad_row(step)
        if x and step.count > 0 then mark_row(x + 1, row, 34) end
    end

    -- the selected soldier on the equipment screen
    if squads and mi.squad_equipment.open and self.equip_idx
        and not (mi.assign_uniform.open or mi.squad_equipment.customizing_equipment
                 or mi.squad_equipment.setting_ammo or mi.squad_equipment.setting_supplies)
    then
        local row = self:equipment_row()
        if row and row.y < gps.dimy - 6 then mark_row(row.x + 7, row.y, 24) end
    end

    -- the selected row of a soldier's equipment, or of a list opened from it
    if squads and mi.squad_equipment.open
        and (mi.squad_equipment.customizing_equipment or mi.squad_equipment.setting_ammo_new_type
             or mi.squad_equipment.setting_ammo_mat or mi.assign_uniform.open)
    then
        local pick = equipment_pick_list()
        local row, x
        if pick then
            row, x = self:equipment_list_row(self.pick_idx or 0, pick.owner, pick.scroll)
        elseif #mi.squad_equipment.cs_cat > 0 then
            row, x = self:equipment_list_row(self.detail_idx or 0, mi.squad_equipment, 'scroll_position_cs')
        end
        if row and row < gps.dimy - 6 then mark_row(x + 3, row, 30) end
    end

    -- the focused cell of the schedule grid, unless one of its sub-screens is up
    if squads and not mi.squad_equipment.open and mi.squad_schedule.open and mi.squads.editing_squad_schedule_id == -1
        and mi.squad_schedule.viewing_months_squad_id == -1 and not mi.squad_schedule.editing_routines
    then
        local cell = self:schedule_cell()
        if cell then mark_row(cell.x - 1, cell.y, 18) end
    end
    -- the selected routine in the routine editor
    if squads and not mi.squad_equipment.open and mi.squad_schedule.open and mi.squad_schedule.editing_routines
        and mi.squads.editing_squad_schedule_id == -1 and mi.squad_schedule.viewing_months_squad_id == -1
    then
        local x, row = self:routine_row()
        if x then mark_row(x - 1, row, 23) end
    end
    -- the focused cell of the monthly schedule
    if squads and not mi.squad_equipment.open and mi.squad_schedule.open
        and mi.squad_schedule.viewing_months_squad_id ~= -1 and mi.squads.editing_squad_schedule_id == -1
    then
        local cell = self:month_cell()
        if cell then mark_row(cell.x - 1, cell.y, 18) end
    end
    -- the selected order in the order editor
    if squads and mi.squad_schedule.open and mi.squads.editing_squad_schedule_id ~= -1
        and not mi.squads.giving_move_order and self.editor_idx
    then
        local months = editing_months()
        local has_orders = months[1] and #months[1].orders > 0
        local x, y = find_screen_text('Minimum number of', {x1=gps.dimx - 60})
        local row = y and (y + 4 + 3 * self.editor_idx - mi.squads.scroll_position_orderp)
        if has_orders and row and row > y + 3 and row < gps.dimy - 8 then
            mark_row(x + 4, row, 22)
        end
    end

    local anchor = (self.paint and self.paint.anchor) or (self.order and self.order_anchor)
    if anchor and self.cursor.z == df.global.window_z then
        local a, c = anchor, self.cursor
        local tile = dfhack.screen.findGraphicsTile('CURSORS', 0, 0)
        guidm.renderMapOverlay(function()
            return COLOR_YELLOW, 'X', tile
        end, gui.mkdims_xy(math.min(a.x, c.x), math.min(a.y, c.y), math.max(a.x, c.x), math.max(a.y, c.y)))
    end

    if (self.mode or self.paint or self.order or self.aim) and self.cursor
        and self.cursor.z == df.global.window_z
    then
        local cursor = self.cursor
        -- no blinking while stretching a rectangle: the cursor is its corner
        local blink_on = anchor or (dfhack.getTickCount() // 300) % 3 ~= 0
        if blink_on then
            local tile = dfhack.screen.findGraphicsTile('CURSORS', 0, 0)
            guidm.renderMapOverlay(function(pos)
                if pos.x == cursor.x and pos.y == cursor.y then
                    return COLOR_YELLOW, 'X', tile
                end
            end, gui.mkdims_xy(cursor.x, cursor.y, cursor.x, cursor.y))
        end
    end

    ClassicKeysOverlay.super.onRenderFrame(self, dc, rect)
end

OVERLAY_WIDGETS = {keys=ClassicKeysOverlay}

if dfhack_flags.module then
    return
end

print('classic-controls runs as an overlay. Useful commands:')
print('  overlay enable classic-controls.keys')
print('  overlay disable classic-controls.keys')
