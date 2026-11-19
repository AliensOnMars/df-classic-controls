-- Labors as they used to be: set per dwarf, and a dwarf starts with only the
-- skilled work it can already do.
--
-- The new game hands labors out through work details, and any labor that no
-- work detail restricts is done by everybody. With this switched on for a
-- fort, work details are set aside (the same switch Dwarf Therapist's "Allow
-- labor changes" uses) and every adult is given:
--
--   * the core labors, which need no skill, always on: hauling of every kind
--     (stone, wood, items, furniture, food, refuse, water, trade goods,
--     animals, burial), pushing and hauling vehicles, cleaning, pulling
--     levers, construction, construction removal, road building, recovering
--     the wounded and feeding patients and prisoners;
--   * each skilled labor in which it is at least a novice;
--   * and no other labor. A labor at which nobody in the fort is a novice
--     ends up with nobody: that is reported, so it can be given to someone.
--
-- Two special cases:
--
--   * mining, woodcutting and hunting each need a tool and exclude one
--     another, so a dwarf skilled in more than one gets the one it is best
--     at (hunting goes by the ambusher skill, as in Dwarf Therapist);
--   * a dwarf holding a hospital post (chief medical dwarf, doctor,
--     diagnostician, surgeon, bone doctor) keeps its medical labors as they
--     are, skilled or not, so that the hospital keeps working.
--
-- After that pass a dwarf's labors are changed only by you (Dwarf Therapist
-- is the tool for it); a newcomer, or a child coming of age, gets the same
-- defaults once.
--
-- DFHack has labor automation of its own (autolabor and labormanager, switched
-- with M on the work details page), which keeps re-assigning labors as the
-- fort's needs change. This is the plain alternative: defaults once, then
-- hands off. The two are not run together.
--
-- Usage:
--   classic-labors            say whether it is on for this fort
--   classic-labors preview    show what "on" / "apply" would change, and change nothing
--   classic-labors on         switch it on and give every adult the defaults
--   classic-labors apply      give every adult the defaults again
--   classic-labors off        hand labors back to the work details
--
-- The setting is kept in the fort's save.

--@module = true

local KEY = 'classic-labors'
local LABOR = df.unit_labor

-- always on. 76 is "construction removal", which DFHack's list has no name for
local CORE = {}
for _, labor in ipairs{
    LABOR.HAUL_STONE, LABOR.HAUL_WOOD, LABOR.HAUL_BODY, LABOR.HAUL_FOOD, LABOR.HAUL_REFUSE,
    LABOR.HAUL_ITEM, LABOR.HAUL_FURNITURE, LABOR.HAUL_ANIMALS, LABOR.HAUL_TRADE, LABOR.HAUL_WATER,
    LABOR.HANDLE_VEHICLES, LABOR.CLEAN, LABOR.PULL_LEVER, LABOR.BUILD_CONSTRUCTION, 76,
    LABOR.BUILD_ROAD, LABOR.RECOVER_WOUNDED, LABOR.FEED_WATER_CIVILIANS,
} do
    CORE[labor] = true
end

local TOOL_LABORS = {LABOR.MINE, LABOR.CUTWOOD, LABOR.HUNT}
local IS_TOOL = {}
for _, labor in ipairs(TOOL_LABORS) do IS_TOOL[labor] = true end

local MEDICAL = {}
for _, labor in ipairs{LABOR.DIAGNOSE, LABOR.SURGERY, LABOR.BONE_SETTING, LABOR.SUTURING, LABOR.DRESSING_WOUNDS} do
    MEDICAL[labor] = true
end

-- labor -> the skills that count for it
local SKILLS = {}
for skill in ipairs(df.job_skill) do
    local attrs = df.job_skill.attrs[skill]
    local labor = attrs and attrs.labor
    if labor and labor ~= LABOR.NONE and not CORE[labor] then
        SKILLS[labor] = SKILLS[labor] or {}
        table.insert(SKILLS[labor], skill)
    end
end
-- hunting is the ambusher's trade; the weapon skills also listed for it would
-- make a hunter of every marksdwarf
SKILLS[LABOR.HUNT] = {df.job_skill.SNEAK}

local NOVICE = 1    -- dabbling is 0

local function state()
    local data = dfhack.persistent.getSiteData(KEY, {})
    data.seen = data.seen or {}
    return data
end

local function save(data)
    dfhack.persistent.saveSiteData(KEY, data)
end

local function adults()
    local list = {}
    for _, unit in ipairs(dfhack.units.getCitizens()) do
        if dfhack.units.isAdult(unit) then list[#list + 1] = unit end
    end
    return list
end

-- the dwarf's best rating among the labor's skills
local function rating(unit, labor)
    local best = -1
    for _, skill in ipairs(SKILLS[labor]) do
        best = math.max(best, dfhack.units.getNominalSkill(unit, skill))
    end
    return best
end

-- unit ids holding a hospital post
local function medical_posts()
    local posts = {}
    local medical = {DOCTOR=true, DIAGNOSTICIAN=true, SURGEON=true, BONE_DOCTOR=true}
    for _, occupation in ipairs(df.global.world.occupations.all) do
        if medical[df.occupation_type[occupation.type] or ''] and occupation.unit_id ~= -1 then
            posts[occupation.unit_id] = true
        end
    end
    return posts
end

local function chief_medical(unit)
    for _, post in ipairs(dfhack.units.getNoblePositions(unit) or {}) do
        if post.position.code:find('MEDICAL') then return true end
    end
    return false
end

-- what each labor should be for one dwarf: labor -> true / false (a labor
-- left out is not to be touched)
local function wanted(unit, posts)
    local want = {}
    for labor in pairs(CORE) do want[labor] = true end
    local keep_medical = posts[unit.id] or chief_medical(unit)
    for labor in pairs(SKILLS) do
        if not IS_TOOL[labor] and not (MEDICAL[labor] and keep_medical) then
            want[labor] = rating(unit, labor) >= NOVICE
        end
    end
    -- one tool labor at most: the best skilled; on a tie, the one already on
    local best, best_rating
    for _, labor in ipairs(TOOL_LABORS) do
        local r = rating(unit, labor)
        if r >= NOVICE and (not best or r > best_rating
            or (r == best_rating and unit.status.labors[labor] and not unit.status.labors[best]))
        then
            best, best_rating = labor, r
        end
    end
    for _, labor in ipairs(TOOL_LABORS) do want[labor] = labor == best end
    return want
end

local function labor_name(labor)
    local name = LABOR[labor]
    if labor == 76 then return 'construction removal' end
    return name and name:lower():gsub('_', ' ') or tostring(labor)
end

-- Give one dwarf the defaults (or, with dry, only count what would change).
local function apply_to(unit, posts, dry, changes)
    local changed = 0
    for labor, on in pairs(wanted(unit, posts)) do
        if unit.status.labors[labor] ~= on then
            changed = changed + 1
            if changes then
                local entry = changes[labor] or {on=0, off=0}
                entry[on and 'on' or 'off'] = entry[on and 'on' or 'off'] + 1
                changes[labor] = entry
            end
            if not dry then unit.status.labors[labor] = on end
        end
    end
    return changed
end

-- skilled labors that nobody would have
local function unmanned(units, posts)
    local held = {}
    for _, unit in ipairs(units) do
        local want = wanted(unit, posts)
        for labor in pairs(SKILLS) do
            local on = want[labor]
            if on == nil then on = unit.status.labors[labor] end
            if on then held[labor] = true end
        end
    end
    local names = {}
    for labor in pairs(SKILLS) do
        if not held[labor] then names[#names + 1] = labor_name(labor) end
    end
    table.sort(names)
    return names
end

-- DFHack's own labor automation (autolabor / labormanager, the M key on the
-- work details page) sets labors itself: while it runs, this stands aside.
function automation_running()
    local ok, plugin = pcall(require, 'plugins.autolabor')
    return ok and plugin and plugin.isEnabled and plugin.isEnabled() or false
end

function is_on()
    if not dfhack.isMapLoaded() or not dfhack.world.isFortressMode() then return false end
    return state().on == true
end

local function hold_work_details_off()
    df.global.game.external_flag.automatic_professions_disabled = true
end

-- Returns: dwarves changed, settings changed, the names of the skilled labors
-- nobody has afterwards, and (for the report) per-labor counts of changes.
function apply_all(dry)
    local data = state()
    local units = adults()
    local posts = medical_posts()
    local empty = unmanned(units, posts)
    local dwarves, total, changes = 0, 0, {}
    for _, unit in ipairs(units) do
        local n = apply_to(unit, posts, dry, changes)
        if n > 0 then dwarves = dwarves + 1 end
        total = total + n
        if not dry then data.seen[tostring(unit.id)] = true end
    end
    if not dry then save(data) end
    return dwarves, total, empty, changes
end

function switch_on()
    local data = state()
    data.on = true
    save(data)
    hold_work_details_off()
    return apply_all()
end

function switch_off()
    local data = state()
    data.on = false
    save(data)
    df.global.game.external_flag.automatic_professions_disabled = false
end

-- Called now and then by the classic-controls overlay while a fort is up:
-- keeps the game from handing labors out again (the game forgets that switch
-- when a fort is loaded) and gives newcomers their defaults.
function tick()
    if not is_on() or automation_running() then return end
    hold_work_details_off()
    local data = state()
    local posts
    local newcomers = 0
    for _, unit in ipairs(adults()) do
        local id = tostring(unit.id)
        if not data.seen[id] then
            posts = posts or medical_posts()
            apply_to(unit, posts)
            data.seen[id] = true
            newcomers = newcomers + 1
        end
    end
    if newcomers > 0 then save(data) end
    return newcomers
end

if dfhack_flags.module then return end

if not dfhack.isMapLoaded() or not dfhack.world.isFortressMode() then
    qerror('classic-labors needs a fort to be loaded')
end

local function report(dwarves, total, empty, changes, dry)
    print(('%d labor settings %s on %d dwarves.'):format(total, dry and 'would change' or 'changed', dwarves))
    local lines = {}
    for labor, entry in pairs(changes) do
        local parts = {}
        if entry.on > 0 then parts[#parts + 1] = ('on for %d'):format(entry.on) end
        if entry.off > 0 then parts[#parts + 1] = ('off for %d'):format(entry.off) end
        lines[#lines + 1] = ('  %s: %s'):format(labor_name(labor), table.concat(parts, ', '))
    end
    table.sort(lines)
    for _, line in ipairs(lines) do print(line) end
    if #empty > 0 then
        print(('%d skilled labors %s nobody (no one is a novice at them):'):format(#empty, dry and 'would have' or 'have'))
        print('  ' .. table.concat(empty, ', '))
    end
end

local command = ({...})[1]
if (command == 'on' or command == 'apply') and automation_running() then
    qerror("DFHack's labor automation is running: switch it off first (M on the work details page, or 'autolabor disable')")
end
if command == 'on' then
    local dwarves, total, empty, changes = switch_on()
    print('Classic labors are on for this fort. Work details are set aside.')
    report(dwarves, total, empty, changes)
elseif command == 'off' then
    switch_off()
    print('Classic labors are off. The game assigns labors from the work details again;')
    print('it does so the next time a work detail is changed.')
elseif command == 'apply' then
    if not is_on() then qerror('classic labors are off for this fort: use "classic-labors on"') end
    report(apply_all())
elseif command == 'preview' then
    local dwarves, total, empty, changes = apply_all(true)
    report(dwarves, total, empty, changes, true)
elseif not command then
    print('Classic labors are ' .. (is_on() and 'ON' or 'off') .. ' for this fort.')
    if automation_running() then print("DFHack's labor automation is running and is the one setting labors.") end
    print("The game's work details are " ..
        (df.global.game.external_flag.automatic_professions_disabled and 'set aside.' or 'in charge.'))
else
    qerror('usage: classic-labors [preview | on | apply | off]')
end
