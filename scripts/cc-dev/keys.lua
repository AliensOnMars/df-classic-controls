-- Dev helper: feed interface keys to the DF viewscreen one at a time (through
-- the overlay, as real key presses go) and report UI state after each.
-- Usage: cc-dev/keys <KEY> [<KEY> ...]
--   a key may be several codes pressed together, joined with '+',
--   e.g. CUSTOM_S+D_SQUADS to mimic what one physical key produces

local gui = require('gui')

local mi = df.global.game.main_interface
local vs = mi.view_sheets

local function state()
    return ('focus=%s | desig=%s | sheet=%s id=%d open=%s | buttons=%d'):format(
        table.concat(dfhack.gui.getCurFocus(true), ' , '),
        tostring(df.main_designation_type[mi.main_designation_selected]),
        tostring(df.view_sheet_type[vs.active_sheet]), vs.active_id, tostring(vs.open),
        #mi.building.button)
end

for _, arg in ipairs({...}) do
    local keys = {}
    for code in arg:gmatch('[^+]+') do
        keys[code] = true
    end
    local ok, err = pcall(gui.simulateInput, dfhack.gui.getCurViewscreen(true), keys)
    print(('%-28s %s%s'):format(arg, state(), ok and '' or (' ERROR ' .. tostring(err))))
end
