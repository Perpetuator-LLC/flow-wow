-- XP-first route sorting (the default; "Shortest path" switches it off).
-- The planner minimises sum(distance x weight). This scales each quest
-- stop's weight by how much it's worth to you right now:
--   more XP              -> lighter (worth walking further for)
--   quest above you      -> heavier (slower kills, more deaths): 3+ levels up
--                           costs a lot, so level-appropriate quests come first
--   quest about to grey  -> a little lighter (do it before its XP drops)
-- Same stops, same shortest-path planner: it just stops treating a level-10
-- quest at level 7 the same as a level-6 one next door.
-- Every quest stop's tooltip gets an XP line.

local _, ns = ...
local X = {}
ns.xpValue = X

-- Rough full quest XP by quest level (classic-style curve). Real numbers
-- from your quest log are used where the client gives them.
function X.Estimate(level)
    level = math.max(1, level or 1)
    if level <= 10 then return 80 + 55 * level end
    return 630 + 95 * (level - 10)
end

-- Share of XP you still get, by how far below you the quest is.
local DECAY = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }
function X.Share(questLevel, myLevel)
    local below = myLevel - questLevel
    if below <= 5 then return 1 end
    return DECAY[below] or 0.1
end

local function logXP(questID)
    if not GetQuestLogRewardXP then return nil end
    local ok, xp = pcall(GetQuestLogRewardXP, questID)
    if ok and type(xp) == "number" and xp > 0 then return xp end
end

local function questOf(goal)
    local k = goal.key
    local id = k:match("^pickup:(%d+)$") or k:match("^(%d+):done$") or k:match("^(%d+):%d+$")
    return id and tonumber(id), k:find("^pickup:") ~= nil
end

-------------------------------------------------------------------------------
-- What the route optimises for: a registry, so the route can aim at anything
-- (most XP, shortest walk, or one day "fishing only", "first to 300 Mining").
-- The planner itself never changes: it minimises sum(distance x weight) over
-- the stops it's given. An objective only (1) scales each stop's weight and
-- (2) optionally says which stops count at all.
--
--   ns:Register("routeObjective", "<key>", {
--       label = "Most XP", tip = "shown on hover",
--       color = { r, g, b },                    -- optional route colour
--       weigh = function(goal, ctx) return m end,   -- optional: weight x m
--                                                -- (< 1 = worth a longer walk)
--       keep  = function(goal, ctx) return bool end, -- optional: route only these
--   })
--   ctx = { level = your level, ref = typical quest XP at your level }
-- Goals already carry what an objective needs: key, kind, prof (gathering /
-- fishing stops), xp, level, levelsAbove, share, optional, milestone...
-- Pick one with /flow nav sort <key> (or the Flow Router's radios for the
-- built-in ones). Example, not built in:
--   ns:Register("routeObjective", "fishing", { label = "Fishing only",
--       keep = function(g) return ns.actions.GoalProf(g) == "Fishing" or g.kind == "merchant" end })
-------------------------------------------------------------------------------

ns:Register("routeObjective", "xp", {
    label = "Most XP",
    tip = "Shortest path, with quests weighed by XP and level: more XP is worth a longer walk; quests 3+ levels above you wait.",
    weigh = function(g, ctx)
        if not g.xp then return nil end
        local m = math.sqrt(ctx.ref / math.max(g.xp, 1))
        m = math.max(0.6, math.min(1.6, m))
        local above = g.levelsAbove or 0
        if above >= 3 then m = m * (1 + 0.4 * (above - 2))
        elseif above == 2 then m = m * 1.15 end
        if above <= -3 and g.share == 1 then m = m * 0.9 end   -- do it before its XP drops
        return m
    end,
})
ns:Register("routeObjective", "distance", {
    label = "Shortest", tip = "Shortest path: nearest stops first, XP ignored.",
})

-- Route states (map list, arrow right-click, /flow nav xp|distance|custom|sort):
--   any routeObjective key ("xp" by default, "distance", ...): optimised
--   "custom"  Custom route: you picked the next stop (its ^ in the Flow Router,
--             or "Go here first"). The route goes there first, then carries on
--             planned with your last objective ("base"), and stays Custom
--             (orange) until you pick an objective again. ("selected" is its
--             older name, in old saves.)
local function known(m) return m and ns:Get("routeObjective", m) ~= nil end
function X:Mode()
    local m = ns.db.nav.sorter or "xp"
    return m == "selected" and "custom" or m
end
function X:IsCustom() return self:Mode() == "custom" end
function X:Base()
    local b = ns.db.nav.baseSorter
    return known(b) and b or "xp"
end
-- The objective in effect now (key, definition).
function X:Objective()
    -- Completionist route: every quest counts the same, so XP doesn't reorder it.
    if ns.nav and ns.nav.Mode and ns.nav:Mode() == "complete" then return "distance", ns:Get("routeObjective", "distance") end
    local m = self:Mode()
    if not known(m) then m = self:Base() end   -- custom: planned with your last objective
    return m, ns:Get("routeObjective", m)
end
function X:On() return (self:Objective()) == "xp" end
function X:SetMode(m)
    if m == "custom" or m == "selected" then
        -- Custom route starts by picking a stop; the radio alone can't.
        if not self:IsCustom() then
            ns:Print("Custom route: pick your next stop with its ^ in the Flow Router (or right-click a stop: Go here next).")
        end
        return
    end
    if not known(m) then ns:Print("no route objective called '" .. tostring(m) .. "'") return end
    ns.db.nav.sorter, ns.db.nav.baseSorter = m, m
    ns.nav:ClearSelection()
    ns.nav:Collect()
end
function X:Set(on) self:SetMode(on and "xp" or "distance") end  -- older callers

-- Adds XP to quest stops (tooltips), then lets the objective weigh and pick
-- stops. Returns the stops to route (all of them unless it has `keep`).
function X:Apply(goals)
    local me = UnitLevel("player")
    local ref = X.Estimate(me)
    for _, g in ipairs(goals) do
        local id, isPickup = questOf(g)
        if id and g.level then
            local xp = (not isPickup) and logXP(id) or nil
            local share = X.Share(g.level, me)
            local real = xp ~= nil
            xp = xp or math.floor(X.Estimate(g.level) * share + 0.5)
            local above = g.level - me
            local note
            if above >= 3 then note = string.format("%d levels above you: slower and riskier", above)
            elseif above == 2 then note = "2 levels above you"
            elseif share < 1 then note = string.format("%d%% XP: going grey", share * 100)
            elseif me - g.level >= 3 then note = "full XP for now; it starts to drop at level " .. (g.level + 6)
            else note = "full XP" end
            g.details = g.details or {}
            table.insert(g.details, string.format("XP: %s%d (%s)", real and "" or "about ", xp, note))
            g.xp, g.levelsAbove, g.share = xp, above, share
        end
    end
    local _, obj = self:Objective()
    if not obj then return goals end
    local ctx = { level = me, ref = ref }
    local out = goals
    if obj.keep then
        out = {}
        for _, g in ipairs(goals) do
            local ok, keep = pcall(obj.keep, g, ctx)
            if ok and keep then out[#out + 1] = g end
        end
    end
    if obj.weigh then
        for _, g in ipairs(out) do
            local ok, m = pcall(obj.weigh, g, ctx)
            if ok and type(m) == "number" and m > 0 then g.weight = (g.weight or 1) * m end
        end
    end
    return out
end

-- /flow nav sort <key>: pick any registered objective; no key lists them.
function X:List()
    local out = {}
    for key, o in ns:Each("routeObjective") do out[#out + 1] = { key = key, label = o.label or key } end
    return out
end
