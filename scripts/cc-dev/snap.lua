-- Dev helper: snapshot scalar UI state under game.main_interface and diff it,
-- to discover which fields the game flips when a panel/menu opens.
-- Usage:
--   cc-dev/snap save     take a snapshot
--   cc-dev/snap diff     print fields that changed since the snapshot (and re-snapshot)

local args = {...}

local MAX_DEPTH = 4

local function walk(obj, path, depth, out)
    local ok, iter_err = pcall(function()
        for k, v in pairs(obj) do
            local key = path .. '.' .. tostring(k)
            local t = type(v)
            if t == 'number' or t == 'boolean' or t == 'string' then
                out[key] = v
            elseif t == 'userdata' and depth < MAX_DEPTH then
                local kind = v._kind
                if kind == 'container' then
                    local okn, n = pcall(function() return #v end)
                    out[key .. '#'] = okn and n or -1
                elseif kind == 'struct' or kind == 'bitfield' then
                    walk(v, key, depth + 1, out)
                end
            end
        end
    end)
    if not ok then out[path .. '!err'] = tostring(iter_err) end
end

local function take()
    local out = {}
    walk(df.global.game.main_interface, 'mi', 0, out)
    out['cursor'] = ('%d,%d,%d'):format(df.global.cursor.x, df.global.cursor.y, df.global.cursor.z)
    out['focus'] = table.concat(dfhack.gui.getCurFocus(true), ' | ')
    return out
end

if args[1] == 'save' then
    last_snapshot = take()
    local n = 0
    for _ in pairs(last_snapshot) do n = n + 1 end
    print(('snapshot saved (%d fields)'):format(n))
elseif args[1] == 'diff' then
    if not last_snapshot then qerror('no snapshot; run cc-dev/snap save first') end
    local now = take()
    local keys = {}
    for k, v in pairs(now) do
        if last_snapshot[k] ~= v then keys[#keys + 1] = k end
    end
    for k in pairs(last_snapshot) do
        if now[k] == nil then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        if not k:find('hover') and not k:find('last_tick') then
            print(('%s: %s -> %s'):format(k, tostring(last_snapshot[k]), tostring(now[k])))
        end
    end
    print(('%d field(s) changed'):format(#keys))
    last_snapshot = now
else
    qerror('usage: cc-dev/snap save|diff')
end
