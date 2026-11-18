-- /flow export: your character and the route Flow suggests, as lines a
-- script can read.
--
-- "Build a graph yourself of what you think my optimal path should be, and
-- as I play determine if Flow is suggesting the same path ... make it so you
-- can export quests / skills / etc so that you can read it, and export the
-- path it is currently suggesting" (0.35.196).
--
-- The lines go into the diagnostics snapshot (written at every /reload),
-- where tools\route-check.ps1 reads them, plans a route of its own over the
-- same steps, and says where the two differ and what is missing.
--
-- One line a record: E^<kind>^key=value^key=value ... (text last). The
-- fields are split by "^": the game reads "|" in a chat line as the start of
-- a colour or link code. No "^" inside a value. Kinds:
--   export  the version of this format, the game time, Flow's version
--   you     level, xp, where you are, money, bag room, hearthstone
--   opt     how the route is set (order, what it includes)
--   quest   a quest in your log;   obj  one of its objectives
--   skill   a profession and its rank
--   goal    every step Flow knows of: on the route, locked or hidden (state), its kind (step), with
--           its main spot (map and world yards) and what it waits for
--   plan    the route, in order: key, yards from the step before, total
--   flight  a flight path you know;  fm  a flight master Flow can find
--   gate    a way between maps you've learned;  ride  someone who carries you
--   improve a line of Flow Improvements
-- Nothing personal is in it but your character's name and class.

local _, ns = ...
local X = {}
ns.export = X
X.VERSION = 1
X.MAX_FM = 40   -- flight masters listed at most

-- Pure: a value as text with nothing that breaks a line or a field.
function X.Clean(v)
    if v == nil then return "" end
    if type(v) == "boolean" then return v and "1" or "0" end
    if type(v) == "number" then
        if v == math.floor(v) then return string.format("%d", v) end
        return string.format("%.1f", v)
    end
    local s = tostring(v)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("[|%^\r\n]", " "):gsub("%s+", " ")
    return s
end

-- Pure: one record. fields: { { "key", value }, ... } in order; nil values
-- are left out.
function X.Line(kind, fields)
    local parts = { "E", kind }
    for _, f in ipairs(fields) do
        if f[2] ~= nil then parts[#parts + 1] = f[1] .. "=" .. X.Clean(f[2]) end
    end
    return table.concat(parts, "^")
end

-- Pure: a record back into a table (for the tests, and as the format's proof).
function X.Parse(line)
    if type(line) ~= "string" or line:sub(1, 2) ~= "E^" then return nil end
    local out, first = {}, true
    for part in line:sub(3):gmatch("[^%^]+") do
        if first then out.kind, first = part, false
        else
            local k, v = part:match("^([%w_]+)=(.*)$")
            if k then out[k] = v end
        end
    end
    return out
end

local function world(pt)
    if not pt then return nil end
    if pt.wx and pt.cont then return pt.cont, pt.wx, pt.wy end
    local N = ns.nav
    if not (N and pt.map and pt.x) then return nil end
    local ok, cont, wx, wy = pcall(N.ToWorld, N, pt.map, pt.x, pt.y)
    if ok and cont and wx then return cont, wx, wy end
    return nil
end

local function spot(fields, pt)
    if not pt then return end
    local cont, wx, wy = world(pt)
    fields[#fields + 1] = { "map", pt.map }
    fields[#fields + 1] = { "x", pt.x and pt.x * 100 or nil }
    fields[#fields + 1] = { "y", pt.y and pt.y * 100 or nil }
    fields[#fields + 1] = { "cont", cont }
    fields[#fields + 1] = { "wx", wx }
    fields[#fields + 1] = { "wy", wy }
end

function X.BagsFree()
    local free = 0
    local get = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if not get then return nil end
    for bag = 0, 4 do
        local ok, n = pcall(get, bag)
        if ok and type(n) == "number" then free = free + n end
    end
    return free
end

-- Every line of the export, as it is right now.
function X.Lines()
    local out = {}
    local function add(kind, fields) out[#out + 1] = X.Line(kind, fields) end
    local N, A = ns.nav, ns.api
    add("export", { { "v", X.VERSION }, { "at", time and time() or 0 }, { "flow", ns.Version and ns.Version() or "?" } })

    -- You.
    local p = N and N:PlayerPos()
    local _, class = UnitClass("player")
    local you = {
        { "name", UnitName("player") }, { "class", class }, { "faction", UnitFactionGroup and UnitFactionGroup("player") },
        { "level", UnitLevel("player") }, { "xp", A.Safe(UnitXP and UnitXP("player")) }, { "xpmax", A.Safe(UnitXPMax and UnitXPMax("player")) },
        { "money", GetMoney and GetMoney() }, { "bagsfree", X.BagsFree() }, { "speed", N and N.TravelSpeed and N.TravelSpeed() },
        { "zone", GetZoneText and GetZoneText() }, { "hearth", GetBindLocation and GetBindLocation() },
    }
    local H = ns.hearth
    if H then
        local okC, left = pcall(H.CooldownLeft, H)
        you[#you + 1] = { "hearthleft", okC and left or nil }
        local okB, bp = pcall(H.BindPoint, H)
        if okB and bp then
            local cont, wx, wy = world(bp)
            you[#you + 1] = { "hcont", cont }; you[#you + 1] = { "hwx", wx }; you[#you + 1] = { "hwy", wy }
        end
    end
    spot(you, p)
    add("you", you)

    -- How the route is set.
    if N then
        local okK, kinds = pcall(function() return N.KindsSummary and N.KindsSummary() end)
        add("opt", {
            { "order", ns.xpValue and ns.xpValue.Mode and ns.xpValue:Mode() },
            { "zonefirst", ns.db.nav.zoneFirst ~= false }, { "areafirst", ns.db.nav.areaFirst == true },
            { "zonesfirst", ns.db.nav.zonesFirst == true },
            { "zones", ns.db.nav.zonesOn and N.ZoneNames and N.ZoneNames(ns.db.nav.zonesOn) or "not picked yet" },
            { "trails", N.TrailsOn and N.TrailsOn() }, { "note", N.zoneNote },
            { "includes", okK and type(kinds) == "string" and kinds or nil },
        })
    end

    -- Your quest log.
    local log = ns.quests and ns.quests.LogEntries and ns.quests.LogEntries() or {}
    for _, q in ipairs(log) do
        add("quest", { { "id", q.id }, { "complete", q.complete and true or false }, { "n", #(q.objectives or {}) }, { "title", q.title } })
        for i, o in ipairs(q.objectives or {}) do
            add("obj", { { "quest", q.id }, { "i", i }, { "done", o.finished and true or false }, { "text", o.text } })
        end
    end

    -- Your professions.
    for _, pr in ipairs(A.Professions and A.Professions() or {}) do
        add("skill", { { "rank", pr.rank }, { "max", pr.max }, { "unsure", pr.unsure and true or nil }, { "name", pr.name } })
    end

    -- Every step Flow knows of.
    local planned = {}
    for i, s in ipairs(N and N.plan or {}) do planned[s.goal.key] = { i = i, point = s.point } end
    local function goals(list, state)
        for _, g in ipairs(list or {}) do
            local at = planned[g.key]
            local pt = (at and at.point) or (N.Spot and select(2, pcall(N.Spot, N, g))) or (g.points and g.points[1])
            if type(pt) ~= "table" then pt = g.points and g.points[1] end
            local fields = {
                { "key", g.key }, { "state", at and "route" or state }, { "stop", N.StopKind and N:StopKind(g) or g.kind },
                { "provider", g.provider }, { "level", g.level }, { "weight", g.weight },
                { "milestone", g.milestone and true or nil }, { "optional", g.optional and true or nil },
                { "cost", g.cost }, { "n", g.points and #g.points or 0 }, { "area", g.area and true or nil },
                { "deps", g.deps and #g.deps > 0 and table.concat(g.deps, ",") or nil },
                { "blocked", g.blockedBy },
            }
            spot(fields, pt)
            fields[#fields + 1] = { "text", g.text or g.title }
            add("goal", fields)
        end
    end
    if N then
        goals(N:Goals(), "off")       -- (collected, but not on the route as planned: dropped or waiting)
        goals(N.blockedGoals, "locked")
        goals(N.hiddenGoals, "hidden")
        -- The route, in order.
        for i, s in ipairs(N.plan or {}) do
            local fields = { { "i", i }, { "key", s.goal.key }, { "leg", s.leg }, { "cum", s.cum } }
            spot(fields, s.point)
            add("plan", fields)
        end
    end

    -- Ways to travel.
    for name, f in pairs(ns.db.flights or {}) do
        add("flight", { { "cont", f.cont }, { "wx", f.wx }, { "wy", f.wy }, { "name", name } })
    end
    local S = ns.services
    if S and S.All and p then
        local okS, list = pcall(S.All, S, "flight", X.MAX_FM)
        for _, f in ipairs(okS and list or {}) do
            local fields = { { "known", ns.db.flights and ns.db.flights[f.name] ~= nil }, { "src", f.learned or "data" }, { "yards", f.yards } }
            spot(fields, f)
            fields[#fields + 1] = { "name", f.name }
            add("fm", fields)
        end
    end
    for _, g in ipairs(ns.db.nav and ns.db.nav.gates or {}) do
        add("gate", { { "a", g.a }, { "b", g.b }, { "cont", g.cont }, { "wx", g.wx }, { "wy", g.wy } })
    end
    if ns.rides and ns.rides.List then
        for _, r in ipairs(ns.rides.List()) do
            add("ride", { { "from", r.from }, { "to", r.to }, { "class", r.class }, { "faction", r.faction }, { "name", r.name } })
        end
    end

    -- What Flow thinks would make you stronger.
    local Adv = ns.advisor
    if Adv and Adv.Shown then
        local okA, shown = pcall(Adv.Shown, Adv)
        for _, it in ipairs(okA and shown or {}) do
            add("improve", { { "importance", it.importance }, { "goal", it.goalKey }, { "source", it.source }, { "text", it.text } })
        end
    end
    add("end", { { "lines", #out + 1 } })
    return out
end

-- /flow export: says how much there is (the lines themselves go into the
-- diagnostics); /flow export dump prints them.
ns.commands.export = function(arg)
    local ok, lines = pcall(X.Lines)
    if not ok then ns:Print("export failed: " .. tostring(lines)) return end
    if (arg or ""):lower():find("dump") then
        for _, l in ipairs(lines) do print(l) end
        return
    end
    ns:Print(string.format("export: %d lines (your quests, skills and Flow's route). They're saved with the diagnostics at your next /reload; tools\\route-check.ps1 reads them.", #lines))
end

ns:Register("help", "export", { order = 95, title = "Export for checking the route", lines = {
    "/flow export: your quests, skills and the route Flow suggests, written into the diagnostics at the next /reload.",
    "tools\\route-check.ps1 plans a route of its own over the same steps and says where the two differ.",
} })
