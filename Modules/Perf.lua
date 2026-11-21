-- How much of your computer Flow uses: time spent in each of its update
-- loops (arrow, rotation, route planning, map, tracker) and its memory.
-- /flow perf shows it; the diagnostics snapshot saves it, so a slow spot
-- shows up in tools\read-diag.ps1 without anyone having to notice it.

local _, ns = ...
local P = { stats = {}, since = nil }
ns.perf = P

local clock = debugprofilestop

-- fn wrapped so each call's time is added to `name`. Errors pass through
-- (callers keep their own pcall).
-- Own time only: when a timed function calls another timed one (the arrow
-- update planning the route), the inner one's time and memory count for
-- the inner one alone, so no time is counted twice and the total is true.
local depth, childMs, childKb = 0, {}, {}
function P.Wrap(name, fn)
    if not clock then return fn end
    local st = P.stats[name] or { calls = 0, total = 0, max = 0, kb = 0 }
    P.stats[name] = st
    return function(...)
        depth = depth + 1
        local lvl = depth
        childMs[lvl], childKb[lvl] = 0, 0
        local m0, t0 = collectgarbage("count"), clock()
        local ok, a, b, c, d = pcall(fn, ...)
        local ms, made = clock() - t0, collectgarbage("count") - m0
        depth = lvl - 1
        if depth > 0 then
            childMs[depth] = childMs[depth] + ms
            if made > 0 then childKb[depth] = childKb[depth] + made end
        end
        local own, ownKb = ms - childMs[lvl], made - childKb[lvl]
        st.calls, st.total = st.calls + 1, st.total + own
        if own > st.max then st.max = own end
        -- Memory it made (garbage to clean up later): the cleaner's work is
        -- CPU too, and a big number here is what swells "memory".
        if ownKb > 0 then st.kb = st.kb + ownKb end
        if not ok then error(a, 0) end
        return a, b, c, d
    end
end
P._depth = function() return depth end   -- (tests)

-- Time inside one timed function, split by part (Flow Actions by step):
-- the report names the costliest parts under its row, so a slow entry says
-- which part of it to look at. Cheap enough to run on every call (one clock
-- read per part, no memory count).
function P.AddPart(name, part, ms)
    local st = P.stats[name]
    if not (st and part and ms) then return end
    local parts = st.parts or {}
    st.parts = parts
    local pt = parts[part] or { total = 0, max = 0, n = 0 }
    parts[part] = pt
    pt.total, pt.n = pt.total + ms, pt.n + 1
    if ms > pt.max then pt.max = ms end
end

-- What a row's parts are, said in the report ("refreshed after" for the
-- route: each refresh's cause, how often, and what those refreshes cost).
function P.PartsLabel(name, label, n)
    local st = P.stats[name]
    if st then st.partsLabel, st.partsShown = label, n end
end

-- "      most in: gear:upgrade 2.10 ms/s (3613x, worst 15.9 ms), ..." for one
-- row, or nil. (P.PartsLabel gives a row its own word for "most in".)
function P.PartsLine(st, secs, n)
    if not st.parts then return nil end
    local list = {}
    for part, pt in pairs(st.parts) do
        if pt.total > 0 then list[#list + 1] = { part = part, pt = pt } end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.pt.total > b.pt.total end)
    local bits = {}
    for i = 1, math.min(n or st.partsShown or 4, #list) do
        local e = list[i]
        bits[#bits + 1] = string.format("%s %.2f ms/s (%dx, worst %.1f ms)", e.part, e.pt.total / secs, e.pt.n or 0, e.pt.max)
    end
    return "      " .. (st.partsLabel or "most in") .. ": " .. table.concat(bits, ", ")
end

function P:Reset()
    for _, st in pairs(self.stats) do st.calls, st.total, st.max, st.kb, st.parts = 0, 0, 0, 0, nil end
    self.since = GetTime()
end

local function memoryKB()
    local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
    local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if not (update and get) then return nil end
    pcall(update)
    local ok, kb = pcall(get, "Flow")
    return ok and kb or nil
end

-- Lines for /flow perf and the snapshot. `quick` (the snapshot) skips the
-- full garbage clean-up and the second memory scan: a full clean-up walks
-- every addon's memory in one frame, a hitch you can feel.
function P:Report(quick)
    local secs = math.max(GetTime() - (self.since or GetTime()), 1)
    local out, rows, sum = {}, {}, 0
    for name, st in pairs(self.stats) do
        if st.calls > 0 then rows[#rows + 1] = { name = name, st = st }; sum = sum + st.total end
    end
    table.sort(rows, function(a, b) return a.st.total > b.st.total end)
    local kb = memoryKB()
    local kept
    if not quick then
        -- What Flow really keeps: after a full clean-up of the garbage.
        collectgarbage("collect")
        kept = memoryKB()
    end
    out[#out + 1] = string.format("over %d s: Flow used %.2f ms per second (%.2f%% of one CPU core), memory %s (%s)",
        secs, sum / secs, sum / secs / 10, kb and string.format("%.1f MB", kb / 1024) or "?",
        quick and "/flow perf for what's kept after clean-up"
            or ((kept and string.format("%.1f MB", kept / 1024) or "?") .. " kept after clean-up"))
    for _, r in ipairs(rows) do
        local st = r.st
        out[#out + 1] = string.format("  %-32s %6.2f ms/s  avg %5.2f ms  worst %6.1f ms  makes %6.1f KB/s  (%d calls)",
            r.name, st.total / secs, st.total / st.calls, st.max, (st.kb or 0) / secs, st.calls)
        local parts = P.PartsLine(st, secs)
        if parts then out[#out + 1] = parts end
    end
    -- One frame at 60 fps is ~16 ms: anything near that is a hitch you'd feel.
    for _, r in ipairs(rows) do
        if r.st.max > 16 then
            out[#out + 1] = string.format("  ! %s once took %.0f ms (a visible hitch)", r.name, r.st.max)
        end
    end
    return out
end

ns:On("PLAYER_LOGIN", function() P.since = GetTime() end)

ns.commands.perf = function(arg)
    arg = (arg or ""):lower()
    if arg == "reset" then P:Reset(); ns:Print("perf counters reset") return end
    ns:Print("performance:")
    print("  lite mode: " .. ((ns.Lite() and ("on (" .. tostring(ns.liteWhy) .. ")")) or "off") .. (ns.loginFrames.last and ("; " .. ns.loginFrames.last) or ""))
    for _, line in ipairs(P:Report(arg == "quick")) do print(line) end
    print("  /flow perf reset")
end

-- Lite mode: inside a dungeon or raid, or during a boss fight, Flow eases off
-- the parts you don't need there (route planning, the arrow and minimap at
-- full speed, map and tracker refreshes) so it never adds to lag in a boss
-- fight. The rotation, the Flow key and bags keep running as normal.
-- 0.35.373: a raid group counts wherever you are, and so do battlegrounds
-- and arenas ("can we detect when in raid mode and then disable parts of the
-- system?"). What eases off: the route is gathered at most every 20 seconds,
-- the arrow and minimap run at 2 a second, the world map and tracker refresh
-- every 2 s, the meters once a second, trips aren't timed, and the self-tests
-- never run. What stays: the rotation, both buttons, the meters, bags.
-- Pure: why lite mode is on (a few words), or nil when it isn't.
function ns.LiteWhy(inInstance, kind, boss, inRaid, setting)
    if setting == false then return nil end
    if boss then return "a boss fight" end
    if inInstance and kind == "raid" then return "in a raid" end
    if inInstance and kind == "party" then return "in a dungeon" end
    if inInstance and (kind == "pvp" or kind == "arena") then return "in a battleground" end
    if inRaid then return "in a raid group" end
    return nil
end
local liteAt, liteVal = 0, false
function ns.Lite()
    local now = GetTime()
    if now - liteAt < 1 then return liteVal end
    liteAt = now
    local inInstance, kind = false, nil
    if IsInInstance then inInstance, kind = IsInInstance() end
    local boss = IsEncounterInProgress and IsEncounterInProgress() or false
    local inRaid = IsInRaid and IsInRaid() and true or false
    ns.liteWhy = ns.LiteWhy(inInstance, kind, boss, inRaid, ns.db and ns.db.perf and ns.db.perf.lite)
    liteVal = ns.liteWhy ~= nil
    return liteVal
end
ns:On("GROUP_ROSTER_UPDATE", function() liteAt = 0 end)
ns:OnLoad(function(saved)
    saved.perf = saved.perf or {}
    -- (Here, not at file level: this file loads before Flow Settings does.)
    if not (ns.settings and ns.settings.AddCheck) then return end
    ns.settings:AddCheck({
        group = "group",
        label = "Ease off in raids, dungeons and battlegrounds",
        note = "(lite mode)",
        tip = "In a raid group, inside a dungeon, raid or battleground, and in a boss fight, Flow stops the work you don't need there so it never adds to lag: "
            .. "the route is gathered far less often, the arrow, map and tracker refresh slower, trips aren't timed. Your buttons, the rotation and the meters run as always. "
            .. "/flow perf says whether it's on right now.",
        get = function() return not (ns.db.perf and ns.db.perf.lite == false) end,
        set = function(on) ns.db.perf.lite = (not on) and false or nil end,
    })
end)
ns:On("ENCOUNTER_START", function() liteAt = 0 end)
ns:On("ENCOUNTER_END", function() liteAt = 0 end)
ns:On("PLAYER_ENTERING_WORLD", function() liteAt = 0 end)

-------------------------------------------------------------------------------
-- Long frames right after login (0.35.336). "Every time the game loads,
-- between 2 and 10 seconds afterwards, there's a freezing moment: look at
-- what is happening right there." Whatever causes one (Flow, another add-on,
-- the game streaming the world in), a frame that took far too long is noted
-- with when it happened, for the first 40 seconds, and the log says so. It
-- doesn't say whose fault a frame was; /flow perf's "once took" lines do
-- that for Flow's own work.
-------------------------------------------------------------------------------
local LF = { WATCH = 40, LONG = 0.15, SKIP = 1.5, KEEP = 5 }
ns.loginFrames = LF
-- Pure: adds a long frame to the list (the longest KEEP are kept, longest first).
function LF.Note(list, at, seconds, keep)
    list[#list + 1] = { at = at, ms = seconds * 1000 }
    table.sort(list, function(a, b) return a.ms > b.ms end)
    for i = #list, (keep or LF.KEEP) + 1, -1 do list[i] = nil end
    return list
end
-- Pure: the log's line.
function LF.Text(list, count, watch)
    if #list == 0 then return string.format("after login: no frame over %d ms in the first %d s", LF.LONG * 1000, watch or LF.WATCH) end
    local parts = {}
    for _, f in ipairs(list) do parts[#parts + 1] = string.format("%.0f ms at %.1f s", f.ms, f.at) end
    return string.format("after login: %d long frame(s) in the first %d s; the longest: %s", count, watch or LF.WATCH, table.concat(parts, ", "))
end
ns:On("PLAYER_LOGIN", function()
    local watcher, since, list, count = CreateFrame("Frame"), 0, {}, 0
    watcher:SetScript("OnUpdate", function(self, dt)
        since = since + dt
        -- (The first frames after the loading screen are the game's own.)
        if since > LF.SKIP and dt >= LF.LONG then
            count = count + 1
            LF.Note(list, since, dt)
        end
        if since >= LF.WATCH then
            self:SetScript("OnUpdate", nil)
            LF.last = LF.Text(list, count)
            ns:Log("perf", LF.last)
        end
    end)
end)
