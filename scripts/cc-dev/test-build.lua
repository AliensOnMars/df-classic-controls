-- Dev helper: press every classic build-menu key through the overlay and
-- report which building the game ends up placing.
-- Usage (from the bare map, classic-controls overlay enabled): cc-dev/test-build

local gui = require('gui')

local mi = df.global.game.main_interface
local con = mi.construction
local BOTTOM = df.main_bottom_mode_type

local menus = reqscript('classic-controls').get_classic_build_menus()

local function press(...)
    local keys = {}
    for _, code in ipairs({...}) do keys[code] = true end
    gui.simulateInput(dfhack.gui.getCurViewscreen(true), keys)
end

local function to_map()
    for _ = 1, 4 do
        if mi.bottom_mode_selected == BOTTOM.NONE then return end
        -- straight to the game, bypassing the overlay's "Esc goes back one level"
        gui.simulateInput(dfhack.gui.getDFViewscreen(true), 'LEAVESCREEN')
    end
end

local function placing()
    local t = con.bb_placement_type
    return ('%s/%d/%d'):format(tostring(df.building_type[t] or t), con.bb_placement_subtype,
        con.bb_placement_custom_building_id)
end

local failures = 0
local function check(ok, msg)
    if not ok then
        failures = failures + 1
        print('  !! ' .. msg)
    end
end

local function run_menu(id, parent_code)
    for _, entry in ipairs(menus[id]) do
        if entry.submenu then
            run_menu(entry.submenu, entry.codes[1])
        elseif entry.click then
            -- reached by a click a few frames after the key (the game gives
            -- these no hotkey), which this same-frame check cannot follow
            print(('%-3s %-14s %-26s -> skipped (placed by a delayed click; check by hand)'):format(
                id, entry.codes[1]:gsub('CUSTOM_', ''), entry.label))
        else
            for _, code in ipairs(entry.codes) do
                to_map()
                press('D_BUILDING', 'CUSTOM_B')
                check(mi.bottom_mode_selected == BOTTOM.BUILDING, 'b did not open the build menu')
                if parent_code then press(parent_code) end
                press(code)
                local ok = mi.bottom_mode_selected == BOTTOM.BUILDING_PLACEMENT
                print(('%-3s %-14s %-26s -> %s'):format(id, code:gsub('CUSTOM_', ''), entry.label,
                    ok and placing() or 'NOT PLACING'))
                check(ok, 'no placement started')
                press('LEAVESCREEN')
                check(mi.bottom_mode_selected == BOTTOM.BUILDING, 'Esc from placement did not return to the build list')
            end
        end
    end
end

to_map()
run_menu('top', nil)
to_map()
print(('%d failure(s)'):format(failures))
