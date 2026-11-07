-- How much of your computer Flow uses: time spent in each of its update
-- loops (arrow, rotation, route planning, map, tracker) and its memory.
-- /flow perf shows it; the diagnostics snapshot saves it, so a slow spot
-- shows up in tools\read-diag.ps1 without anyone having to notice it.

local _, ns = ...
local P = { stats = {}, since = nil }
ns.perf = P

local clock = debugprofilestop

-- fn wrapped so each call's time is added to `name`. Errors pass through
-- unchanged (callers keep their own pcall).
function P.Wrap(name, fn)
    if not clock then return fn end
    local st = P.stats[name] or { calls = 0, total = 0, max = 0, kb = 0 }
    P.stats[name] = st
    return function(...)
        local m0, t0 = collectgarbage("count"), clock()
        local a, b, c, d = fn(...)
        local ms = clock() - t0
        st.calls, st.total = st.calls + 1, st.total + ms
        if ms > st.max then st.max = ms end
        -- Memory it made (garbage to clean up later): the cleaner's work is
        -- CPU too, and a big number here is what swells "memory".
        local made = collectgarbage("count") - m0
        if made > 0 then st.kb = st.kb + made end
        return a, b, c, d
    end
end

function P:Reset()
    for _, st in pairs(self.stats) do st.calls, st.total, st.max, st.kb = 0, 0, 0, 0 end
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

-- Lines for /flow perf and the snapshot.
function P:Report()
    local secs = math.max(GetTime() - (self.since or GetTime()), 1)
    local out, rows, sum = {}, {}, 0
    for name, st in pairs(self.stats) do
        if st.calls > 0 then rows[#rows + 1] = { name = name, st = st }; sum = sum + st.total end
    end
    table.sort(rows, function(a, b) return a.st.total > b.st.total end)
    local kb = memoryKB()
    -- What Flow really keeps: after a full clean-up of the garbage.
    collectgarbage("collect")
    local kept = memoryKB()
    out[#out + 1] = string.format("over %d s: Flow used %.2f ms per second (%.2f%% of one CPU core), memory %s (%s kept after clean-up)",
        secs, sum / secs, sum / secs / 10, kb and string.format("%.1f MB", kb / 1024) or "?",
        kept and string.format("%.1f MB", kept / 1024) or "?")
    for _, r in ipairs(rows) do
        local st = r.st
        out[#out + 1] = string.format("  %-26s %6.2f ms/s  avg %5.2f ms  worst %6.1f ms  makes %6.1f KB/s  (%d calls)",
            r.name, st.total / secs, st.total / st.calls, st.max, (st.kb or 0) / secs, st.calls)
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
    if (arg or ""):lower() == "reset" then P:Reset(); ns:Print("perf counters reset") return end
    ns:Print("performance:")
    for _, line in ipairs(P:Report()) do print(line) end
    print("  /flow perf reset")
end
