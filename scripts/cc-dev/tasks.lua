-- Dev helper: print the add-task entries the game offers for a workshop.
-- Usage:
--   cc-dev/tasks list            one line per workshop / furnace kind in the fort: "id kind"
--   cc-dev/tasks open <bld id>   open that building's panel (then wait a frame)
--   cc-dev/tasks dump            click "Add new task" on the open panel and print its entries
--   cc-dev/tasks press <n>       press entry n (0-based) and print the entries that follow

local gui = require('gui')

local gps = df.global.gps
local mi = df.global.game.main_interface
local vs = mi.view_sheets

local args = {...}

local function kind_name(bld)
    if df.building_workshopst:is_instance(bld) then
        return 'Workshop/' .. tostring(df.workshop_type[bld.type])
    end
    return 'Furnace/' .. tostring(df.furnace_type[bld.type])
end

local function find_text(text)
    local w, h = dfhack.screen.getWindowSize()
    for y = 0, h - 1 do
        for x = 0, w - #text do
            local ok = true
            for i = 1, #text do
                local p = dfhack.screen.readTile(x + i - 1, y)
                if not p or p.ch ~= text:byte(i) then ok = false break end
            end
            if ok then return x, y end
        end
    end
end

local function click(x, y)
    gps.mouse_x, gps.mouse_y = x, y
    gps.precise_mouse_x = x * gps.tile_pixel_x + gps.tile_pixel_x // 2
    gps.precise_mouse_y = y * gps.tile_pixel_y + gps.tile_pixel_y // 2
    gui.simulateInput(dfhack.gui.getDFViewscreen(true), '_MOUSE_L')
end

local function describe(button)
    local str = df.new('string')
    button:text(str)
    local text = str.value
    str:delete()
    local t = tostring(button._type):match('interface_button_building_(.-)st>') or '?'
    if t == 'new_job' then
        local extra = {}
        if button.itemtype >= 0 then extra[#extra + 1] = tostring(df.item_type[button.itemtype]) end
        if button.subtype >= 0 then extra[#extra + 1] = 'sub' .. button.subtype end
        if button.material >= 0 then extra[#extra + 1] = 'mat' .. button.material end
        if #button.mstring > 0 then extra[#extra + 1] = button.mstring end
        return ('%s [%s%s]'):format(text, tostring(df.job_type[button.jobtype]),
            #extra > 0 and (' ' .. table.concat(extra, ' ')) or '')
    elseif t == 'material_selector' then
        return ('%s [MATERIAL mat%d]'):format(text, button.material)
    elseif t == 'custom_category_selector' then
        return ('%s [CATEGORY %s]'):format(text, button.custom_category_token)
    end
    return ('%s [%s]'):format(text, t)
end

local function dump()
    local buttons = mi.building.filtered_button
    if #buttons == 0 then buttons = mi.building.button end
    local out = {}
    for i, button in ipairs(buttons) do
        out[#out + 1] = i .. ':' .. describe(button)
    end
    print(table.concat(out, ' | '))
end

local cmd = args[1]
if cmd == 'list' then
    local seen = {}
    for _, list in ipairs{df.global.world.buildings.other.WORKSHOP_ANY, df.global.world.buildings.other.FURNACE_ANY} do
        for _, bld in ipairs(list) do
            local kind = kind_name(bld)
            if not seen[kind] and bld:getBuildStage() == bld:getMaxBuildStage() then
                seen[kind] = true
                print(bld.id, kind)
            end
        end
    end
elseif cmd == 'open' then
    local bld = df.building.find(tonumber(args[2])) or qerror('no such building')
    vs.viewing_unid:resize(0)
    vs.viewing_itid:resize(0)
    mi.building.button:resize(0)
    mi.building.press_button:resize(0)
    mi.building.filtered_button:resize(0)
    vs.active_sheet = df.view_sheet_type.BUILDING
    vs.active_id = bld.id
    vs.viewing_bldid = bld.id
    vs.viewing_x, vs.viewing_y, vs.viewing_z = bld.centerx, bld.centery, bld.z
    vs.active_sub_tab = 0
    vs.open = true
elseif cmd == 'dump' then
    if #mi.building.button == 0 then
        local x, y = find_text('Add new task')
        if not x then qerror('no "Add new task" button on screen') end
        click(x + 3, y)
    end
    dump()
elseif cmd == 'press' then
    local buttons = mi.building.filtered_button
    if #buttons == 0 then buttons = mi.building.button end
    buttons[tonumber(args[2])]:press()
    dump()
else
    qerror('usage: cc-dev/tasks list | open <id> | dump | press <n>')
end
