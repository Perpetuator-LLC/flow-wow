-------------------------------------------------------------------------------
-- Flow - Nav/Areas.lua
-- Steps done in the same area are one group: planned together, shown together
-- (0.35.431).
--
-- "Maybe we need to start grouping objectives that are in the same area ...
-- there's four different quest items I need to do [here] ... if it starts to
-- group them into multiple objectives that are happening in this one area,
-- then maybe that becomes a single item that can be used in the graph as a
-- stopping point ... the most important thing is that you're doing this in a
-- generic way, so it works for all classes, all zones, all areas."
--
-- The planner ordered single steps by the trips between them. Four steps in
-- one field usually came out next to each other, because they're near each
-- other; nothing made sure of it, and nothing said they belong together.
--
-- So, before the route is planned, the objective steps of the quests in your
-- log are sorted into groups by where they're done:
--   * two steps are in the same area when two of one's spots lie within
--     AR.RADIUS yards of the other's (the test Overlap.lua uses);
--   * areas join up (A with B, B with C), but only while the whole group
--     stays within AR.SPAN yards across: a chain of mobs along a whole zone
--     isn't one area;
--   * a quest to pick up that Overlap.lua put before one of those steps is
--     in its group too.
-- Nothing here names a zone, a quest or a class: it's only where things are.
--
-- A group then counts as one stop of the route:
--   * the planner keeps its steps together (Planner: P.Together): once the
--     route reaches a group it does all of it before going on, in the order
--     the planner found, a pickup before the step it's for. A step that has
--     to wait for something outside the group stays where it was.
--   * the Flow Tracker and the map show the whole group while its first
--     step is your next step, whatever "Steps on the map" is set to;
--   * each of its lines ends "(this area: 4 steps)", and its card names the
--     others.
-- Every mob of every quest in your log is marked anyway (QuestMarks.lua), so
-- while you're in the area everything that counts is marked.
--
-- Flow Settings, Finding your way; /flow areas (on | off) lists the groups.
-------------------------------------------------------------------------------

local _, ns = ...
local AR = {}
ns.areas = AR

AR.RADIUS = 150     -- yards: two spots this close are the same place
AR.SPAN = 900       -- yards: a group isn't wider than this
AR.MAX_POINTS = 12  -- spots of a step looked at

function AR.On() return not (ns.db and ns.db.nav and ns.db.nav.areaGroups == false) end

local function bounds(points)
    local b
    for _, p in ipairs(points or {}) do
        if p.wx then
            if not b then b = { cont = p.cont, x1 = p.wx, x2 = p.wx, y1 = p.wy, y2 = p.wy }
            elseif p.cont == b.cont then
                if p.wx < b.x1 then b.x1 = p.wx end
                if p.wx > b.x2 then b.x2 = p.wx end
                if p.wy < b.y1 then b.y1 = p.wy end
                if p.wy > b.y2 then b.y2 = p.wy end
            end
        end
    end
    return b
end
local function span(a, b)
    local dx = math.max(a.x2, b.x2) - math.min(a.x1, b.x1)
    local dy = math.max(a.y2, b.y2) - math.min(a.y1, b.y1)
    return math.sqrt(dx * dx + dy * dy)
end

-- Pure: the groups.
--   steps: { { key, points = { { cont, wx, wy } } } }
--   shares(a, b) -> true when the spots of a lie among the spots of b (Overlap's O.Shares)
-- -> groupOf = { [key] = group id }, groups = { { id, keys = { ... } } } (only groups of two or more)
function AR.Groups(steps, shares, maxSpan)
    maxSpan = maxSpan or AR.SPAN
    local parent, box = {}, {}
    for i, s in ipairs(steps or {}) do
        parent[i] = i
        box[i] = bounds(s.points)
    end
    local function find(i)
        while parent[i] ~= i do
            parent[i] = parent[parent[i]]
            i = parent[i]
        end
        return i
    end
    for i = 1, #(steps or {}) do
        for j = i + 1, #steps do
            local a, b = find(i), find(j)
            if a ~= b and box[a] and box[b] and box[a].cont == box[b].cont and span(box[a], box[b]) <= maxSpan
                and (shares(steps[i].points, steps[j].points) or shares(steps[j].points, steps[i].points)) then
                parent[b] = a
                box[a] = { cont = box[a].cont, x1 = math.min(box[a].x1, box[b].x1), x2 = math.max(box[a].x2, box[b].x2),
                           y1 = math.min(box[a].y1, box[b].y1), y2 = math.max(box[a].y2, box[b].y2) }
            end
        end
    end
    local byRoot, groups, groupOf = {}, {}, {}
    for i, s in ipairs(steps or {}) do
        local r = find(i)
        local g = byRoot[r]
        if not g then g = { keys = {} }; byRoot[r] = g end
        g.keys[#g.keys + 1] = s.key
    end
    for _, g in pairs(byRoot) do
        if #g.keys >= 2 then
            table.sort(g.keys)
            g.id = "area:" .. g.keys[1]
            groups[#groups + 1] = g
            for _, k in ipairs(g.keys) do groupOf[k] = g.id end
        end
    end
    table.sort(groups, function(a, b) return a.id < b.id end)
    return groupOf, groups
end

-- Pure: how many of the plan's first steps are one group with its very first
-- step (1: the first step is in no group, or alone at the front).
--   plan: { { goal = { areaGroup } } }
function AR.Lead(plan)
    local first = plan and plan[1] and plan[1].goal
    local g = first and first.areaGroup
    if not g then return 1 end
    local n = 1
    for i = 2, #plan do
        if plan[i].goal and plan[i].goal.areaGroup == g then n = n + 1 else break end
    end
    return n
end

-- Pure: a group's words on one of its steps' card.
function AR.CardLine(others)
    local n = #(others or {})
    if n == 0 then return nil end
    local shown = {}
    for i = 1, math.min(3, n) do shown[i] = tostring(others[i]) end
    return string.format("In this area with %s%s: Flow has you do them together, then move on.",
        table.concat(shown, "; "), n > 3 and string.format(" and %d more", n - 3) or "")
end

local function worldPoints(g)
    local N, out = ns.nav, {}
    for i, pt in ipairs(g.points or {}) do
        if i > AR.MAX_POINTS then break end
        local cont, wx, wy = pt.cont, pt.wx, pt.wy
        if not wx and pt.map and N then cont, wx, wy = N:ToWorld(pt.map, pt.x, pt.y) end
        if wx then out[#out + 1] = { cont = cont, wx = wx, wy = wy } end
    end
    return out
end

-- Sorts the route's steps into groups (see the top). Changes the goals:
-- areaGroup (the id), areaSize, and a line on the card.
function AR.Apply(goals)
    AR.last = {}
    local O = ns.overlap
    if not (AR.On() and O and O.IsStep) then return 0 end
    local steps, byKey = {}, {}
    for _, g in ipairs(goals or {}) do
        byKey[g.key] = g
        g.areaGroup, g.areaSize = nil, nil
        if O.IsStep(g) then steps[#steps + 1] = { key = g.key, points = worldPoints(g) } end
    end
    if #steps < 2 then return 0 end
    local groupOf, groups = AR.Groups(steps, function(a, b) return O.Shares(a, b, AR.RADIUS, AR.MAX_POINTS) end)
    -- A quest to pick up that goes before one of the steps (Overlap.lua) is of its group.
    for _, g in ipairs(goals or {}) do
        local id = g.overlapKey and groupOf[g.overlapKey]
        if id then
            groupOf[g.key] = id
            for _, grp in ipairs(groups) do
                if grp.id == id then grp.keys[#grp.keys + 1] = g.key end
            end
        end
    end
    for _, grp in ipairs(groups) do
        local names = {}
        for _, k in ipairs(grp.keys) do
            local g = byKey[k]
            g.areaGroup, g.areaSize = grp.id, #grp.keys
            names[#names + 1] = tostring(g.text or g.title or k)
        end
        for i, k in ipairs(grp.keys) do
            local g, others = byKey[k], {}
            for j, name in ipairs(names) do if j ~= i then others[#others + 1] = name end end
            local line = AR.CardLine(others)
            if line and type(g.details) == "table" then g.details[#g.details + 1] = line end
        end
        AR.last[#AR.last + 1] = string.format("%d steps: %s", #grp.keys, table.concat(names, "; "))
    end
    return #groups
end

-- /flow areas: the groups of the last plan (on | off).
function AR.Lines()
    local out = { string.format("Flow: steps grouped by area: %s; %d group(s) in the last plan", AR.On() and "on" or "off", #(AR.last or {})) }
    for _, l in ipairs(AR.last or {}) do out[#out + 1] = "  " .. l end
    local plan = ns.nav and ns.nav.plan
    if plan and #plan > 0 then out[#out + 1] = string.format("  your next step leads a group of %d", AR.Lead(plan)) end
    return out
end
ns.commands.areas = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.nav.areaGroups = (arg == "on")
        if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("area groups " .. arg) end
    end
    for i, l in ipairs(AR.Lines()) do if i == 1 then ns:Print((l:gsub("^Flow: ", ""))) else print(l) end end
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "route",
        label = "Do everything in an area together",
        note = "(steps done in the same place are one stop)",
        tip = "Steps of your quests that are done in the same place (the same field, the same camp) are one group: the route does all of it before going on, "
            .. "and the Flow Tracker and the map show the whole group while it's next.",
        get = function() return AR.On() end,
        set = function(on)
            ns.db.nav.areaGroups = on and true or false
            if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("do everything in an area together") end
        end,
    })
end
