-------------------------------------------------------------------------------
-- Flow - Nav/Overlap.lua
-- Pick up the quests that are done in the same place first (0.35.428).
--
-- "I was down here doing the Stormhide quest ... and then I got close enough
-- to one of the other NPCs where they gave me a quest that's called Field to
-- Clear, and I have to kill the same exact mobs. So something in our
-- algorithm is not considering that it would be more efficient to go get
-- that quest first before I start killing the Stormhides ... it needs to
-- plan to get all the quests to do the thing in the area so we don't have to
-- come back and do it again later. That's what is inefficient, not just the
-- distance calculations."
--
-- The planner orders steps by the trip between them. To it "Accept: Field to
-- Clear" was one more spot to visit, and whether it came before or after the
-- Stormhides of Chen's Empty Keg was whatever made the walk shorter. It had
-- no idea the two quests are done on the same mobs.
--
-- So, before the route is planned:
--   * for each quest you could pick up whose giver is near a step of a quest
--     in your log, Flow works out where that new quest's own objectives are
--     (the same way it places a quest in your log);
--   * where those spots lie among the spots of your step, the pickup is put
--     before the step: the step waits for it (in order only: when the pickup
--     leaves the route, the step doesn't wait), and the pickup always makes
--     the plan;
--   * both say so on their cards.
-- Only worth it when the giver is close (O.GIVER yards from your step): a
-- quest given across the zone isn't fetched for this.
--
-- This goes by where things are, so it catches the same mobs and also
-- different mobs in the same field. It only reads the quest data.
-------------------------------------------------------------------------------

local _, ns = ...
local O = {}
ns.overlap = O

O.RADIUS = 150      -- yards: two spots this close are "the same place"
O.GIVER = 700       -- yards from your step to the giver: further isn't fetched for this
O.MAX_POINTS = 12   -- spots of a step or a quest looked at
O.PER_STEP = 2      -- pickups put before one step
O.MAX_LINKS = 6     -- in one plan

function O.On() return not (ns.db and ns.db.nav and ns.db.nav.overlapFirst == false) end

local function dist(a, b)
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return math.sqrt(dx * dx + dy * dy)
end

-- Pure: the least distance between two lists of spots ({ cont, wx, wy }), or nil.
function O.Least(a, b, max)
    local best
    for i, p in ipairs(a or {}) do
        if max and i > max then break end
        for j, q in ipairs(b or {}) do
            if max and j > max then break end
            if p.wx and q.wx and p.cont == q.cont then
                local d = dist(p, q)
                if not best or d < best then best = d end
            end
        end
    end
    return best
end

-- Pure: how many of a quest's spots lie within `radius` of any of a step's spots.
function O.Near(questPts, stepPts, radius, max)
    local n = 0
    for i, p in ipairs(questPts or {}) do
        if max and i > max then break end
        for j, q in ipairs(stepPts or {}) do
            if max and j > max then break end
            if p.wx and q.wx and p.cont == q.cont and dist(p, q) <= radius then n = n + 1 break end
        end
    end
    return n
end

-- Pure: is a quest done in the same place as a step? Two of its spots among
-- the step's (one, when it only has one or two spots).
function O.Shares(questPts, stepPts, radius, max)
    local have = math.min(#(questPts or {}), max or O.MAX_POINTS)
    if have == 0 then return false end
    return O.Near(questPts, stepPts, radius or O.RADIUS, max or O.MAX_POINTS) >= math.min(2, have)
end

-- Pure: which pickups go before which steps.
--   pickups: { { key, giver = { spots }, spots() -> the quest's objective spots (asked only when the giver is near) } }
--   steps:   { { key, points = { spots } } } the steps of quests in your log, on your route
-- -> { { pickup = key, step = key } }, at most O.PER_STEP a step and O.MAX_LINKS in all
function O.Links(pickups, steps, radius, reach)
    local out, perStep = {}, {}
    for _, s in ipairs(steps or {}) do
        for _, p in ipairs(pickups or {}) do
            if #out >= O.MAX_LINKS then return out end
            if (perStep[s.key] or 0) < O.PER_STEP then
                local d = O.Least(p.giver, s.points, O.MAX_POINTS)
                if d and d <= (reach or O.GIVER) then
                    p.cache = p.cache or p.spots() or {}
                    if O.Shares(p.cache, s.points, radius or O.RADIUS, O.MAX_POINTS) then
                        out[#out + 1] = { pickup = p.key, step = s.key }
                        perStep[s.key] = (perStep[s.key] or 0) + 1
                    end
                end
            end
        end
    end
    return out
end

-- Where a quest you don't have yet is done: the spots of its objectives, as
-- Flow would place them were it in your log. Kept: the quest data doesn't change.
local spotsOf = {}
function O.SpotsOf(id)
    local have = spotsOf[id]
    if have then return have end
    local out = {}
    spotsOf[id] = out
    local Q, N = ns.quests, ns.nav
    local db = Q and Q.QuestieDB and Q.QuestieDB()
    local quest = db and Q:QuestieGet("GetQuest", id)
    if not (quest and Q.QuestGoals and N) then return out end
    local objectives = {}
    for i = 1, #(type(quest.ObjectiveData) == "table" and quest.ObjectiveData or {}) do
        objectives[i] = { text = "", finished = false }
    end
    if #objectives == 0 then return out end
    local goals = {}
    local ok = pcall(Q.QuestGoals, db, { id = id, title = quest.name, complete = false, objectives = objectives }, goals, {})
    if not ok then return out end
    for _, g in ipairs(goals) do
        if type(g.key) == "string" and not g.key:find(":done$") then
            for _, pt in ipairs(g.points or {}) do
                if #out >= O.MAX_POINTS * 3 then break end
                local wx, wy, cont = pt.wx, pt.wy, pt.cont
                if not wx and pt.map then cont, wx, wy = N:ToWorld(pt.map, pt.x, pt.y) end
                if wx then out[#out + 1] = { cont = cont, wx = wx, wy = wy } end
            end
        end
    end
    return out
end

-- A goal's spots with world yards (the route's goals mostly have them already).
local function worldPoints(g)
    local N, out = ns.nav, {}
    for i, pt in ipairs(g.points or {}) do
        if i > O.MAX_POINTS then break end
        local cont, wx, wy = pt.cont, pt.wx, pt.wy
        if not wx and pt.map and N then cont, wx, wy = N:ToWorld(pt.map, pt.x, pt.y) end
        if wx then out[#out + 1] = { cont = cont, wx = wx, wy = wy } end
    end
    return out
end

-- Pure: is this one of your log's objective steps, on the route and doable?
function O.IsStep(g)
    return type(g) == "table" and type(g.key) == "string" and g.key:find("^%d+:") ~= nil and not g.key:find(":done$")
        and not g.blockedBy and not g.helping and g.points ~= nil and #g.points > 0
end

-- Puts the pickups that share a place before the steps (see the top).
-- goals: the route's steps, after the filters. Changes them in place.
function O.Apply(goals)
    O.last = {}
    if not O.On() then return 0 end
    local byKey, pickups, steps = {}, {}, {}
    for _, g in ipairs(goals or {}) do
        byKey[g.key] = g
        local id = type(g.key) == "string" and tonumber(g.key:match("^pickup:(%d+)$"))
        if id and not g.blockedBy and g.points and #g.points > 0 then
            pickups[#pickups + 1] = { key = g.key, giver = worldPoints(g), spots = function() return O.SpotsOf(id) end }
        elseif O.IsStep(g) then
            steps[#steps + 1] = { key = g.key, points = worldPoints(g) }
        end
    end
    if #pickups == 0 or #steps == 0 then return 0 end
    local links = O.Links(pickups, steps)
    for _, l in ipairs(links) do
        local p, s = byKey[l.pickup], byKey[l.step]
        -- The step waits for the pickup, in order only (a list of its own: deps may be shared).
        local deps = {}
        for _, d in ipairs(s.deps or {}) do deps[#deps + 1] = d end
        deps[#deps + 1] = p.key
        s.deps = deps
        s.softDeps = s.softDeps or {}
        s.softDeps[p.key] = true
        p.keep = true   -- (it always makes the plan: the step it's before is on it)
        p.overlap = s.title or s.text
        p.overlapKey = s.key   -- (Areas.lua: it's of that step's group)
        if type(p.details) == "table" then
            table.insert(p.details, 1, string.format("Take it first: it's done in the same place as %s, which is on your route.", tostring(s.title or s.text)))
        end
        if type(s.details) == "table" then
            s.details[#s.details + 1] = string.format("After you pick up %s: it's done in the same place.", tostring(p.title or p.text))
        end
        O.last[#O.last + 1] = string.format("%s before %s", tostring(p.text or p.key), tostring(s.text or s.key))
    end
    return #links
end

-- /flow overlap: what was put first in the last plan (on | off).
function O.Lines()
    local out = { string.format("Flow: quests picked up first because they're done where a step of yours is: %s; %d in the last plan",
        O.On() and "on" or "off", #(O.last or {})) }
    for _, l in ipairs(O.last or {}) do out[#out + 1] = "  " .. l end
    return out
end
ns.commands.overlap = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.nav.overlapFirst = (arg == "on")
        if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("overlap " .. arg) end
    end
    for i, l in ipairs(O.Lines()) do if i == 1 then ns:Print((l:gsub("^Flow: ", ""))) else print(l) end end
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "quests",
        label = "Pick up quests done in the same place first",
        note = "(before the step they share a place with)",
        tip = "When a quest you could pick up is done where a step of your route is (the same mobs, the same field) and its giver is close by, "
            .. "Flow has you pick it up before that step, so one visit does both.",
        get = function() return O.On() end,
        set = function(on)
            ns.db.nav.overlapFirst = on and true or false
            if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("pick up quests done in the same place first") end
        end,
    })
end
