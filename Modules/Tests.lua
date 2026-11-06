-- Self-tests: /flow test runs every registered test in game and prints a
-- summary (failures in full). They also run on every /reload as part of the
-- diagnostics snapshot, so Claude can read the results from disk
-- (tools\read-diag.ps1, "--- tests").
--
-- Add tests next to the feature or here:
--   ns:Register("test", "area: what it checks", function(t)
--       t:eq(actual, expected, "message")
--       t:ok(condition, "message")
--       t:near(a, b, tolerance, "message")
--   end)
-- Tests check Flow's own logic with made-up inputs; they never change your
-- settings (anything they touch is put back).

local _, ns = ...

local T = {}
T.__index = T

function T:ok(cond, msg)
    self.n = self.n + 1
    if not cond then self.fails[#self.fails + 1] = msg or "expected true" end
end

function T:eq(a, b, msg)
    self:ok(a == b, string.format("%s: got %s, expected %s", msg or "eq", tostring(a), tostring(b)))
end

function T:near(a, b, tol, msg)
    self:ok(type(a) == "number" and math.abs(a - b) <= (tol or 1e-6),
        string.format("%s: got %s, expected %s", msg or "near", tostring(a), tostring(b)))
end

local function run(filter)
    local passed, failed, checks, out = 0, 0, 0, {}
    for name, fn in ns:Each("test") do
        if not filter or filter == "" or name:lower():find(filter:lower(), 1, true) then
            local t = setmetatable({ n = 0, fails = {} }, T)
            local ok, err = pcall(fn, t)
            if not ok then t.fails[#t.fails + 1] = "error: " .. tostring(err) end
            checks = checks + t.n
            if #t.fails == 0 then
                passed = passed + 1
            else
                failed = failed + 1
                out[#out + 1] = "FAIL " .. name
                for _, f in ipairs(t.fails) do out[#out + 1] = "    " .. f end
            end
        end
    end
    return passed, failed, checks, out
end

ns.commands.test = function(arg)
    local passed, failed, checks, out = run(arg)
    ns:Print(string.format("tests: %d passed, %d failed (%d checks)", passed, failed, checks))
    for _, l in ipairs(out) do print(l) end
end

-------------------------------------------------------------------------------
-- Tests
-------------------------------------------------------------------------------

local function with(tbl, key, value, fn)
    local old = tbl[key]
    tbl[key] = value
    local ok, err = pcall(fn)
    tbl[key] = old
    if not ok then error(err, 0) end
end

ns:Register("test", "core: registry keeps order and finds by key", function(t)
    local list = {}
    for k in ns:Each("profGuide") do list[#list + 1] = k end
    t:ok(#list >= 4, "profession guides registered")
    t:ok(ns:Get("profGuide", "Blacksmithing") ~= nil, "Blacksmithing guide")
    local ok = pcall(ns.Register, ns, "profGuide", "Blacksmithing", {})
    t:ok(not ok, "registering the same key twice is an error")
end)

ns:Register("test", "skill plan: reads 'raise your skill' objectives", function(t)
    local P = ns.skillPlan.ParseObjective
    local a, n = P("Raise your blacksmithing skill to 20")
    t:eq(a, "Blacksmithing", "profession"); t:eq(n, 20, "target")
    a, n = P("Raise your first aid skill to 40: 0/1")
    t:eq(a, "First Aid", "two-word profession"); t:eq(n, 40, "target")
    t:eq(P("Kill 10 Kobold Vermin"), nil, "not a skill objective")
    t:eq(P(nil), nil, "nil text")
end)

ns:Register("test", "skill plan: most skill per material", function(t)
    local g = ns:Get("profGuide", "Blacksmithing")
    local crafts, order, reaches = ns.skillPlan._simulate("Blacksmithing__test", g.steps, 1, 20)
    t:ok(reaches, "guide reaches 20")
    t:eq(order[1] and order[1].recipe, "Rough Sharpening Stone", "starts with sharpening stones")
    local total = 0
    for _, s in ipairs(order) do total = total + crafts[s] end
    t:ok(total >= 19 and total <= 25, "about one craft per point while orange (" .. total .. ")")
    crafts, order = ns.skillPlan._simulate("Blacksmithing__test", g.steps, 30, 50)
    for _, s in ipairs(order) do t:ok(s.recipe ~= "Coarse Sharpening Stone", "no coarse stones below 65") end
end)

ns:Register("test", "xp: share and estimate", function(t)
    local X = ns.xpValue
    t:eq(X.Share(6, 7), 1, "1 level below: full")
    t:eq(X.Share(2, 7), 1, "5 below: full")
    t:eq(X.Share(1, 7), 0.8, "6 below: 80%")
    t:eq(X.Share(1, 20), 0.1, "far below: 10%")
    t:ok(X.Estimate(10) > X.Estimate(6), "higher quests give more XP")
end)

ns:Register("test", "xp: weights favour your level, add tooltip lines", function(t)
    local me = UnitLevel("player")
    local goals = {
        { key = "pickup:999001", level = me, weight = 1, details = {} },
        { key = "pickup:999002", level = me + 3, weight = 1, details = {} },
    }
    with(ns.db.nav, "sorter", "xp", function() ns.xpValue:Apply(goals) end)
    t:ok(goals[2].weight > goals[1].weight, "3 levels above weighs more than your level")
    t:ok(goals[1].details[1] and goals[1].details[1]:find("^XP: "), "XP line added")
    local plain = { { key = "pickup:999003", level = me + 3, weight = 1, details = {} } }
    with(ns.db.nav, "sorter", "distance", function() ns.xpValue:Apply(plain) end)
    t:eq(plain[1].weight, 1, "shortest path leaves weights alone")
end)

ns:Register("test", "route colour follows the order mode", function(t)
    local want = { xp = "A335EE", distance = "0070DD", selected = "FF8000" }
    local palette = ns.theme.palette
    ns.theme:UsePalette("standard")
    for mode, hex in pairs(want) do
        with(ns.db.nav, "sorter", mode, function() ns.theme:UpdateRoute() end)
        t:eq(ns.theme.route.hex, hex, mode)
    end
    ns.theme:UsePalette(palette)
end)

ns:Register("test", "planner: nearest first, turn-in after its objective", function(t)
    local function goal(key, x, extra)
        local g = { key = key, text = key, points = { { cont = 0, wx = x, wy = 0 } } }
        for k, v in pairs(extra or {}) do g[k] = v end
        return g
    end
    local p = { cont = 0, wx = 0, wy = 0 }
    local plan = ns.planner:Plan(p, { goal("far", 300), goal("near", 20), goal("mid", 120) }, {})
    t:eq(plan and plan[1].goal.key, "near", "nearest first")
    t:eq(plan and plan[3].goal.key, "far", "farthest last")
    -- The turn-in is right next to you, but its objective is further away.
    plan = ns.planner:Plan(p, { goal("1:done", 5, { deps = { "1:1" } }), goal("1:1", 200) }, {})
    t:eq(plan and plan[1].goal.key, "1:1", "objective before its turn-in")
end)

ns:Register("test", "blocked stops: label and reason", function(t)
    local text, why = ns.nav:FormatBlocked({ text = "Buy a Mining Pick", blockedBy = "needs 16c (you have 6c)" })
    t:ok(text:find("Buy a Mining Pick", 1, true) ~= nil, "text kept")
    t:ok(why:find("needs 16c", 1, true) ~= nil, "reason shown")
end)

ns:Register("test", "buffs: remembered casts stand in for hidden auras", function(t)
    local A = ns.api
    local saved = {}
    for k, v in pairs(A._castMemory) do saved[k] = v end
    wipe(A._castMemory)
    A.RememberCast("Seal of Righteousness")
    local up, left = A._fromMemory(function(n) return n:find("^Seal of") end)
    t:ok(up, "seal remembered"); t:ok(left > 25 and left <= 30, "about 30 s left")
    A.RememberCast("Devotion Aura")
    A.RememberCast("Retribution Aura")
    t:ok(not A._fromMemory("Devotion Aura"), "a new aura replaces the old one")
    t:ok(A._fromMemory("Retribution Aura"), "new aura active")
    wipe(A._castMemory)
    for k, v in pairs(saved) do A._castMemory[k] = v end
end)

ns:Register("test", "gear: shields are never Retribution upgrades", function(t)
    if select(2, UnitClass("player")) ~= "PALADIN" then t:ok(true) return end
    local item = { equipLoc = "INVTYPE_SHIELD", stats = { RESISTANCE0_NAME = 500 } }
    local scores = ns.gear:Score(item)
    local diff = ns.gear:RoleDiff(item, "dps", scores)
    t:ok(diff <= 0, "dps diff not positive (" .. tostring(diff) .. ")")
end)

ns:Register("test", "menu: one choice ticked per group", function(t)
    local items = ns.menu:RouteItems()
    local group, ticked = nil, {}
    for _, it in ipairs(items) do
        if it.title then group = it.text; ticked[group] = 0 end
        if it.radio and it.checked then ticked[group] = ticked[group] + 1 end
    end
    t:eq(ticked.Route, 1, "route")
    t:eq(ticked.Order, 1, "order")
end)

ns:Register("test", "tooltip: stop details render", function(t)
    local tt = _G.FlowTestTooltip or CreateFrame("GameTooltip", "FlowTestTooltip", UIParent, "GameTooltipTemplate")
    tt:SetOwner(UIParent, "ANCHOR_NONE")
    local ok, err = pcall(ns.nav.FillTooltip, ns.nav, tt,
        { key = "pickup:999004", title = "Test quest", text = "Accept: Test quest", level = 5,
          details = { "XP: about 355 (full XP)" } }, "footer")
    t:ok(ok, "no error: " .. tostring(err))
    t:ok(tt:NumLines() >= 4, "title, task, details and footer")
    tt:Hide()
end)

ns:Register("test", "ways to improve: no quests to accept", function(t)
    local items = ns:Get("advisor", "missedQuests").check() or {}
    for _, it in ipairs(items) do
        t:ok(not (it.goalKey and it.goalKey:find("^pickup:")), "no pickup advice: " .. tostring(it.text))
    end
    t:ok(true)
end)
