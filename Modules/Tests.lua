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
    local crafts, order, reaches = ns.skillPlan._simulate("Blacksmithing__test", g.steps, 1, 20, {})
    t:ok(reaches, "guide reaches 20")
    t:eq(order[1] and order[1].recipe, "Rough Sharpening Stone", "starts with sharpening stones")
    local total = 0
    for _, s in ipairs(order) do total = total + crafts[s] end
    t:ok(total >= 19 and total <= 25, "about one craft per point while orange (" .. total .. ")")
    crafts, order = ns.skillPlan._simulate("Blacksmithing__test", g.steps, 30, 50, {})
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
    local item = { equipLoc = "INVTYPE_SHIELD", slots = { 17 }, stats = { RESISTANCE0_NAME = 500 } }
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
    if ticked.Party then t:eq(ticked.Party, 1, "party: your route or the party route") end
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

ns:Register("test", "planner: a quest's turn-in comes along with its objectives", function(t)
    local p = { cont = 0, wx = 0, wy = 0 }
    local goals = {}
    for i = 1, 16 do
        goals[#goals + 1] = { key = "near" .. i, text = "near", points = { { cont = 0, wx = i * 10, wy = 0 } } }
    end
    goals[#goals + 1] = { key = "7:1", text = "objective", points = { { cont = 0, wx = 5, wy = 5 } } }
    goals[#goals + 1] = { key = "7:done", text = "turn in", deps = { "7:1" }, points = { { cont = 0, wx = 900, wy = 0 } } }
    local plan = ns.planner:Plan(p, goals, {})
    local at = {}
    for i, s in ipairs(plan or {}) do at[s.goal.key] = i end
    t:ok(at["7:done"] ~= nil, "turn-in planned although it's the farthest stop")
    t:ok(at["7:1"] and at["7:done"] and at["7:1"] < at["7:done"], "after its objective")
end)

ns:Register("test", "spec badge: better / worse / same per spec", function(t)
    t:eq(ns.SpecTrend(1.2), "up", "better"); t:eq(ns.SpecTrend(-3), "down", "worse")
    t:eq(ns.SpecTrend(0.2), "same", "about the same"); t:eq(ns.SpecTrend(nil), nil, "no score")
    local b = ns:SpecBadge(UIParent, 10)
    b:Set({ dps = 2, heal = -2, tank = 0 })
    t:ok(b:IsShown(), "shown with scores")
    t:ok(b.slots.dps.arrow.l1:IsShown() and not b.slots.dps.arrow.bar:IsShown(), "dps: arrow")
    t:ok(b.slots.tank.arrow.bar:IsShown(), "tank: flat bar")
    b:Set(nil)
    t:ok(not b:IsShown(), "hidden without scores")
    b:Hide()
end)

ns:Register("test", "rotation: after-fight heal only when it can help", function(t)
    local E = ns.rotation
    if not (E:Knows("Holy Light") and E:Ready("Holy Light")) then t:ok(true) return end
    local def, now, old = E:Definition(), GetTime(), E.afterFight
    E.afterFight = now + 5
    local quiet = { inCombat = false, hostile = false }
    local h = E:AfterFightHeal(quiet, def, now)
    t:eq(h and h.kind, "heal", "offered right after a long fight")
    t:eq(E:AfterFightHeal({ inCombat = false, hostile = true }, def, now), nil, "not when you target an enemy (attacks first)")
    t:eq(E:AfterFightHeal({ inCombat = true, hostile = true }, def, now), nil, "not in combat")
    t:eq(E:AfterFightHeal(quiet, def, now + 6), nil, "gone after the window")
    E.afterFight = nil
    t:eq(E:AfterFightHeal(quiet, def, now), nil, "not without a long fight")
    E.afterFight = old
end)

ns:Register("test", "cast key: never locked to nothing for a fight", function(t)
    local E = ns.rotation
    local def = E:Definition()
    if not (def and def.pullLock) then t:ok(true) return end
    local main = E:Knows("Judgement") and "Judgement" or nil
    if main then
        t:eq(def.pullLock(nil, E), main, "no suggestion at the pull: main attack")
        t:eq(def.pullLock({ spell = "Blessing of Might", kind = "buff" }, E), main, "a blessing at the pull: main attack")
        t:eq(def.pullLock({ spell = "Attack", kind = "damage" }, E), main, "auto attack at the pull: main attack")
    end
    t:eq(def.pullLock({ spell = "Holy Strike", kind = "damage" }, E), "Holy Strike", "a real attack stays")
end)

ns:Register("test", "arrow: anywhere in a quest's area counts as arrived", function(t)
    local p = { cont = 0, wx = 0, wy = 0 }
    local goal = { area = true, points = { { cont = 0, wx = 300, wy = 0 }, { cont = 0, wx = 30, wy = 10 } } }
    t:ok(ns.nav:InArea(goal, p), "near one of the spawns")
    goal.points[2].wx = 200
    t:ok(not ns.nav:InArea(goal, p), "far from all spawns")
    t:ok(not ns.nav:InArea({ points = { { cont = 0, wx = 1, wy = 1 } } }, p), "single-spot stops use the normal arrival")
end)

ns:Register("test", "ways to improve: no 'choose professions' once two are learned", function(t)
    local main = 0
    for _, pr in ipairs(ns.api.Professions()) do
        if pr.primary then main = main + 1 end
    end
    local items = ns:Get("advisor", "choosePro").check()
    if main >= 2 then t:ok(items == nil, "not suggested") else t:ok(true) end
end)

ns:Register("test", "cast key: the after-fight heal never becomes the fight's key", function(t)
    local E = ns.rotation
    local def = E:Definition()
    if not (def and def.pullLock and E:Knows("Judgement")) then t:ok(true) return end
    t:eq(def.pullLock({ spell = "Holy Light", kind = "heal" }, E), "Judgement", "heal at the pull: main attack")
end)

ns:Register("test", "lists: quest stops show a quest icon", function(t)
    local s = ns.nav:FormatStop(1, { key = "60:1", kind = "collect", text = "Kobold Candles: 1/8 Large Candle" }, "1")
    t:ok(s:find("ActiveQuestIcon", 1, true) ~= nil, "objective: in-progress quest icon")
    s = ns.nav:FormatStop(1, { key = "pickup:85", kind = "accept", text = "Accept: Lost Necklace" }, "!1")
    t:ok(s:find("AvailableQuestIcon", 1, true) ~= nil, "accept: ! icon")
    s = ns.nav:FormatStop(1, { key = "buy:2901", kind = "merchant", text = "Buy a Mining Pick" }, "2")
    t:ok(s:find("QuestIcon", 1, true) == nil, "not a quest: no quest icon")
end)

ns:Register("test", "bags: profession materials name every profession that uses them", function(t)
    local rule = ns:Get("disposition", "professionMaterial")
    if not ns.api.Skill("Blacksmithing") then t:ok(true) return end
    local v = rule.check({ id = 2835, classID = 7, subclassID = 7 })  -- Rough Stone
    -- Your own profession window wins over the guide (Forever has its own recipes).
    t:ok(v and v.reason:find("for Blacksmithing", 1, true) ~= nil,
        "Rough Stone kept for Blacksmithing (" .. tostring(v and v.reason) .. ")")
end)

ns:Register("test", "quests: availability (level, events, not offered)", function(t)
    local Q = ns.quests
    local me = UnitLevel("player")
    t:ok(Q:Available({ Id = 999101, requiredLevel = 1 }), "low level, no requirements: available")
    t:ok(not Q:Available({ Id = 999102, requiredLevel = me + 5 }), "requires a higher level: not available")
    t:ok(not Q:Offered(999103, { zoneOrSort = -1003 }), "holiday quest with no event on: not offered")
    ns.db.quests.notOffered = ns.db.quests.notOffered or {}
    ns.db.quests.notOffered[999104] = time()
    t:ok(not Q:Offered(999104), "quest giver didn't offer it recently: skipped")
    ns.db.quests.notOffered[999104] = time() - 8 * 86400
    t:ok(Q:Offered(999104), "after a week: tried again")
    ns.db.quests.notOffered[999104] = nil
end)

ns:Register("test", "bags: sell decisions", function(t)
    local function rule(k, item) return ns:Get("disposition", k).check(item) end
    local v = rule("junk", { quality = 0, sellPrice = 5 })
    t:eq(v and v.action, "sell", "grey items: sell")
    v = rule("quest", { classID = 12 })
    t:eq(v and v.action, "keep", "quest items: keep")
    v = rule("unsellable", { quality = 1, sellPrice = 0 })
    t:eq(v and v.action, "keep", "vendors won't buy it: keep")
    ns.db.sell.never[999105] = true
    v = rule("neverSell", { id = 999105 })
    t:eq(v and v.action, "keep", "bought back once: never sold again")
    ns.db.sell.never[999105] = nil
    v = rule("unusedMaterial", { classID = 7, subclassID = 99, quality = 1, sellPrice = 10 })
    t:eq(v and v.action, "sell", "material nobody of yours uses: sell")
    v = rule("unusedMaterial", { classID = 7, subclassID = 99, quality = 2, sellPrice = 10 })
    t:eq(v and v.action, "ah", "better material: auction house")
end)

ns:Register("test", "gear: weapon speed tips the balance", function(t)
    local B = ns.gear.SpeedBonus
    t:ok(B(3.6, "slow") > 0, "slow weapon for a slow role: bonus")
    t:ok(B(1.8, "slow") < 0, "fast weapon for a slow role: penalty")
    t:ok(B(5, "slow") <= 1 and B(1, "slow") >= -1, "never more than one point")
    t:eq(B(2.6, nil), 0, "no preference: no change")
end)

ns:Register("test", "gear: only one-handers and off-hands pair up", function(t)
    t:eq(ns.gear:BestPartner({ equipLoc = "INVTYPE_2HWEAPON" }, "tank", {}), nil, "two-hander: no partner")
    t:eq(ns.gear:BestPartner({ equipLoc = "INVTYPE_WEAPON" }, "tank", {}), nil, "nothing in the bags: no partner")
    t:ok(ns.gear.MAIN_1H.INVTYPE_WEAPON and ns.gear.OFF.INVTYPE_SHIELD, "one-hander and shield are a pair")
end)

ns:Register("test", "caves: entrances are learned once per spot", function(t)
    local saved = ns.db.nav.entrances
    ns.db.nav.entrances = {}
    ns.nav:AddEntrance({ cont = 0, wx = 100, wy = 100, map = 1 })
    ns.nav:AddEntrance({ cont = 0, wx = 110, wy = 105, map = 1 })   -- same entrance, a few yards on
    ns.nav:AddEntrance({ cont = 0, wx = 400, wy = 100, map = 1 })   -- another one
    t:eq(#ns.db.nav.entrances, 2, "two entrances")
    ns.db.nav.entrances = saved
end)

ns:Register("test", "bags: profession tools are kept", function(t)
    local rule = ns:Get("disposition", "professionTool")
    if ns.api.Skill("Mining") then
        local v = rule.check({ id = 2901, name = "Mining Pick" })
        t:eq(v and v.action, "keep", "Mining Pick kept while you mine")
    end
    if ns.api.Skill("Blacksmithing") then
        local v = rule.check({ id = 99990, name = "Blacksmith Hammer" })
        t:eq(v and v.action, "keep", "a hammer by name too")
    end
    t:eq(rule.check({ id = 99991, name = "Rusty Sword" }), nil, "not a tool")
end)

ns:Register("test", "tools: any version of a tool counts", function(t)
    local D = ns.disposition
    t:eq(D:ToolProfession(2901, nil), "Mining", "classic Mining Pick by ID")
    t:eq(D:ToolProfession(987654, "Mining Pick"), "Mining", "another item ID, same name")
    t:eq(D:ToolProfession(987655, "Sturdy Blacksmith Hammer"), "Blacksmithing", "name contains the tool")
    t:eq(D:ToolProfession(987656, "Rusty Sword"), nil, "not a tool")
end)

-- Test-only setup rows: hidden except while this test runs (the registry has no remove).
local setupTestOn = false
ns:Register("setupItem", "zzTestNew", { order = 999, label = "Test row", suggested = true, isNew = true,
    available = function() return setupTestOn end, isOn = function() return false end, set = function() end })
ns:Register("setupItem", "zzTestOld", { order = 999, label = "Old row", suggested = true,
    available = function() return setupTestOn end, isOn = function() return false end, set = function() end })

ns:Register("test", "setup: a new suggestion is shown once to old installs", function(t)
    local S, db = ns.setup, ns.db.setup
    local savedSeen, savedDone = db.seen, db.done
    setupTestOn = true
    db.done, db.seen = true, nil
    local new = table.concat(S:Unseen(), ",")
    t:ok(new:find("Test row") ~= nil, "the new row is unseen")
    t:ok(new:find("Old row") == nil, "older rows count as seen")
    S:MarkSeen()
    t:eq(#S:Unseen(), 0, "nothing left after it's shown")
    setupTestOn = false
    db.seen, db.done = savedSeen, savedDone
end)

ns:Register("test", "cooking: meat you carry is used first, either meat will do", function(t)
    local SP = ns.skillPlan
    local g = ns:Get("profGuide", "Cooking")
    local crafts, order = SP._simulate("Cooking__test", g.steps, 1, 10, { [769] = 4 })
    t:eq(order[1] and order[1].recipe, "Roasted Boar Meat", "boar meat in bags goes first")
    local boar
    for _, s in ipairs(order) do if s.recipe == "Roasted Boar Meat" then boar = crafts[s] end end
    t:eq(boar, 4, "all 4 boar meat used, then wolf")
    local alts = SP.Alternatives(g.steps, 2672)
    t:eq(alts[1], 2672, "wolf meat first"); t:eq(alts[2], 769, "boar meat stands in")
    t:eq(#SP.Alternatives(g.steps, 99999), 1, "unknown item: just itself")
end)

ns:Register("test", "drops: rate moves from the guide's to yours", function(t)
    local SP = ns.skillPlan
    local saved = ns.db.crafting.drops
    ns.db.crafting.drops = {}
    t:near(SP.DropRate(2672), 0.35, 0.001, "no kills yet: the guide's rate")
    for i = 1, 5 do SP.RecordLoot("Young Wolf", "corpse" .. i, i == 1 and { [2672] = true } or {}) end
    SP.RecordLoot("Young Wolf", "corpse5", {})            -- same corpse looted again: not counted
    local r, kills = SP.DropRate(2672)
    t:eq(kills, 5, "five kills counted")
    t:near(r, (1 + 0.35 * 5) / 10, 0.001, "1 in 5 pulls the estimate down")
    SP.RecordLoot("Stonetusk Boar", "corpse6", { ["chunk of boar meat"] = true })
    t:eq(ns.db.crafting.drops[769].got, 1, "found by name too")
    ns.db.crafting.drops = saved
end)

ns:Register("test", "map areas: patches and their borders", function(t)
    local M = ns.mapOverlay
    local groups = M._clusters({ { 0, 0 }, { 5, 0 }, { 100, 100 }, { 104, 102 }, { 300, 0 } }, 20)
    t:eq(#groups, 3, "three separate patches")
    local edge = M._hull({ { 0, 0 }, { 10, 0 }, { 10, 10 }, { 0, 10 }, { 5, 5 } })
    t:eq(#edge, 4, "a square's border has 4 corners (the middle point is inside)")
end)

ns:Register("test", "stop card: tooltip text and route patch", function(t)
    local tt = ns.nav._textTooltip()
    ns.nav:FillTooltip(tt, { key = "test:card", title = "A Quest", text = "A Quest: Kill 5 Wolves", details = { "XP: 120" } })
    t:ok(#tt.lines >= 3, "card body has lines")
    t:ok(tt.lines[3]:find("Kill 5 Wolves") ~= nil, "third line is the task (the band shows it, the body skips it)")
    local found
    for _, l in ipairs(tt.lines) do if l:find("XP: 120") then found = true end end
    t:ok(found, "details come through")
    local groups = { { { 0, 0 }, { 5, 0 } }, { { 100, 100 } } }
    t:eq(ns.mapOverlay._routePatch(groups, 98, 99), 2, "the patch nearest the route's spot")
    t:eq(ns.mapOverlay._routePatch(groups, nil, nil), nil, "no route spot: all patches")
end)

ns:Register("test", "router: the selected stop is marked active", function(t)
    local db = ns.db.nav
    local sorter, key = db.sorter, db.selectedKey
    db.sorter, db.selectedKey = "selected", "123:1"
    t:ok(ns.mapOverlay.IsSelected("123:1"), "selected stop")
    t:ok(not ns.mapOverlay.IsSelected("123:2"), "other stops keep the ^")
    db.sorter = "xp"
    t:ok(not ns.mapOverlay.IsSelected("123:1"), "not in another order mode")
    db.sorter, db.selectedKey = sorter, key
end)

ns:Register("test", "recipes: learning one at a trainer clears its stop", function(t)
    local R = ns.recipes
    local p = R._patternFrom("You have learned how to create a new item: %s.")
    t:eq(("You have learned how to create a new item: Heavy Linen Bandage."):match(p), "Heavy Linen Bandage", "chat line parsed")
    local saved = ns.db.crafting["First Aid"]
    ns.db.crafting["First Aid"] = { rank = 40, seenAt = 0, recipes = { ["Linen Bandage"] = { reagents = {} } } }
    t:ok(R:MarkKnown("Heavy Linen Bandage"), "recipe from the First Aid guide")
    local known = R:Known("First Aid")
    t:ok(known["Heavy Linen Bandage"] ~= nil, "now known")
    t:ok(not R:MarkKnown("Not A Recipe"), "unknown names are ignored")
    ns.db.crafting["First Aid"] = saved
end)

ns:Register("test", "route: completionist mode keeps grey quests and ignores XP", function(t)
    local db = ns.db.nav
    local mode = db.mode
    db.mode = "complete"
    t:ok(not ns.xpValue:On(), "XP doesn't reorder a completionist route")
    ns.nav:SetMode("complete"); t:eq(db.mode, "complete", "mode kept")
    ns.nav:SetMode("nonsense"); t:eq(db.mode, "optimal", "unknown mode -> optimal")
    db.mode = mode
    ns.nav:Collect()
end)

ns:Register("test", "planner: a milestone always makes the cut", function(t)
    local P = ns.planner
    local p = { cont = 0, wx = 0, wy = 0 }
    local goals = {}
    for i = 1, 20 do goals[i] = { key = "near" .. i, points = { { cont = 0, wx = i * 10, wy = 0 } } } end
    goals[21] = { key = "train:class", milestone = true, weight = 0.5, points = { { cont = 0, wx = 5000, wy = 0 } } }
    local plan = P:Plan(p, goals, {})
    local found
    for _, s in ipairs(plan) do if s.goal.key == "train:class" then found = true end end
    t:ok(found, "class training is planned even though 20 stops are nearer")
end)

ns:Register("test", "mount: save, then riding, then the mount", function(t)
    local MT, r = ns.mounts, ns:Get("mountRule", "default")
    local L = r.level
    t:eq(MT.Next({ level = L - 10 }), nil, "too early: nothing")
    t:eq(MT.Next({ level = L - 2 }), "save", "a few levels before: save up")
    t:eq(MT.Next({ level = L }), "riding", "at riding level: learn riding")
    t:eq(MT.Next({ level = L, hasRiding = true }), "mount", "then buy the mount")
    t:eq(MT.Next({ level = L, hasRiding = true, classMount = "Summon Warhorse" }), nil, "class mount: nothing to buy")
    t:eq(MT.Next({ level = L + 5, hasRiding = true, hasMount = true }), nil, "done")
    t:eq(MT.Total({ classMount = "Summon Warhorse" }), r.ridingCost, "paladins save for riding only")
    t:eq(MT.Total({}), r.ridingCost + r.mountCost, "others: riding and the mount")
    local _, race = UnitRace("player")
    t:ok(ns:Get("mount", race) ~= nil, "your race has a riding trainer listed (" .. tostring(race) .. ")")
end)

ns:Register("test", "waypoint: pasted coordinates in every usual format", function(t)
    local P = ns.waypoint.Parse
    local zones = function(n) return ({ ["elwynn forest"] = 1429 })[n:lower()] end
    local p = P("45.2 63.1", zones)
    t:near(p.x, 0.452, 0.0001, "x"); t:near(p.y, 0.631, 0.0001, "y"); t:eq(p.map, nil, "your zone")
    p = P("(45.2, 63.1)", zones); t:near(p.y, 0.631, 0.0001, "brackets and comma")
    p = P("/way 45.2 63.1 Hogger", zones); t:eq(p.note, "Hogger", "pasted /way line with a note")
    p = P("/way Elwynn Forest 45.2 63.1 Hogger", zones); t:eq(p.map, 1429, "zone by name"); t:eq(p.note, "Hogger", "note after a zone")
    p = P("#1429 45 63", zones); t:eq(p.map, 1429, "map ID")
    p = P("0.452 0.631", zones); t:near(p.x, 0.452, 0.0001, "0-1 fractions")
    local none, why = P("Stormwind 45 63", zones); t:eq(none, nil, "unknown zone refused"); t:ok(why:find("Stormwind") ~= nil, "says which zone")
    t:eq((P("hello", zones)), nil, "no numbers")
    t:eq((P("145 63", zones)), nil, "out of range")
end)

ns:Register("test", "fishing: a pole comes first", function(t)
    local g = ns:Get("profGuide", "Fishing")
    t:eq(g.tool, 6256, "Fishing needs a Fishing Pole")
    t:ok(g.tip and g.tip:find("Shiny Bauble") ~= nil, "lure tip")
    local goal, missing = ns.skillPlan:ToolGoal("Fishing")
    if ns.disposition:HasTool("Fishing") then
        t:eq(goal, nil, "you have a pole: nothing to buy")
    else
        t:eq(goal and goal.text, "Buy a Fishing Pole", "no pole: buy one")
        t:eq(missing, "Fishing Pole", "and the fishing stop says why")
    end
    t:eq((ns.skillPlan:ToolGoal("Cooking")), nil, "no tool for Cooking")
end)

ns:Register("test", "3D arrow: perspective and turning", function(t)
    local P = ns.nav.Project3D
    local x, y, k = P(0, 26, 0)
    t:near(x, 0, 0.001, "straight ahead stays centred"); t:ok(y > 0, "ahead is up the screen")
    t:ok(k < 1, "the far tip is smaller")
    local _, yb, kb = P(0, -16, 0)
    t:ok(yb < 0 and kb > 1, "the near end is lower and bigger")
    t:ok(y < 26, "the ground leans away (foreshortened)")
    local xl = P(0, 26, math.pi / 2)
    t:ok(xl < -20, "a quarter turn counter-clockwise points left")
end)

ns:Register("test", "diag: blocked actions are logged for read-diag", function(t)
    local d = ns.db.diag
    -- Copy both lists: a full log drops its oldest line when one is added,
    -- so just removing the test's line wouldn't put things back.
    local function copy(list) local c = {} for i, v in ipairs(list or {}) do c[i] = v end return c end
    local savedLog, savedBlocked, hadBlocked = copy(d.log), copy(d.blocked), d.blocked ~= nil
    ns.diag._onBlocked("FORBIDDEN")("Flow", "TestProtectedFunction()")
    t:ok(d.log[#d.log]:find("%[blocked%] FORBIDDEN: Flow blamed for TestProtectedFunction") ~= nil, "logged with [blocked]")
    t:eq(d.blocked[#d.blocked].func, "TestProtectedFunction()", "kept in the blocked list")
    -- Don't leave the test's entry where read-diag would flag it.
    d.log = savedLog
    d.blocked = hadBlocked and savedBlocked or nil
    t:eq(d.log[#d.log], savedLog[#savedLog], "log restored")
end)

ns:Register("test", "taint: Flow never replaces the game's global tables", function(t)
    -- These globals must be Blizzard's own (written by secure code). If an
    -- add-on assigns them, every Blizzard popup/menu that reads them is tainted.
    for _, name in ipairs({ "StaticPopupDialogs", "UISpecialFrames", "SlashCmdList" }) do
        local secure, by = issecurevariable(name)
        t:ok(secure, name .. " is untainted" .. (by and (" (tainted by " .. by .. ")") or ""))
    end
end)

ns:Register("test", "settings: suggested WoW settings are all on Flow's page", function(t)
    local rows, toggles = ns.setup:Rows(), 0
    for _, r in ipairs(rows) do if r.item.isOn then toggles = toggles + 1 end end
    t:ok(toggles >= 5, "at least 5 suggested settings available here (" .. toggles .. ")")
end)

ns:Register("test", "cast: the key's button comes back out of combat", function(t)
    -- The update loop must not live on the button: it hides itself when
    -- there's nothing to press, and a hidden frame's OnUpdate never runs.
    local btn = _G.FlowCastButton
    t:ok(btn ~= nil, "cast button exists")
    if btn then t:ok(btn:GetScript("OnUpdate") == nil, "no update loop on the (hideable) button") end
    t:eq(ns.cast._describe({ type = "item", item = "item:6256" }), "/use item:6256", "item press described")
    t:eq(ns.cast._describe({ type = "item", item = "item:6529", targetSlot = 16 }), "/use item:6529 on slot 16", "lure on main hand")
    t:eq(ns.cast._describe({ spell = "Devotion Aura", kind = "buff" }), "/cast Devotion Aura", "spell press")
end)

ns:Register("test", "actions: fishing steps on the Flow key", function(t)
    local X = ns.actions
    t:ok(X.IsPole(6256), "Fishing Pole is a pole")
    t:ok(not X.IsPole(2901), "Mining Pick is not a pole")
    local get = function(k, ctx) return ns:Get("action", k).get(ctx) end
    -- Not at the fishing stop: no fishing steps.
    t:eq(get("fish:cast", { fishing = false, prof = "Fishing", pole = true }), nil, "no cast away from the spot")
    t:eq(get("fish:equip", { at = true, prof = "Mining", pole = false }), nil, "no pole at a mining stop")
    -- At the spot with the pole on: cast (when you know Fishing and aren't fishing yet).
    if ns.api.SpellInfo("Fishing") and not (UnitChannelInfo and UnitChannelInfo("player")) then
        local s = get("fish:cast", { fishing = true, atFish = true, prof = "Fishing", pole = true })
        t:eq(s and s.spell, "Fishing", "casts Fishing at the spot")
    end
    -- Nothing to put back when Flow didn't swap anything.
    local saved = ns.db.actions.weapons
    ns.db.actions.weapons = nil
    t:eq(get("fish:restore", { at = false }), nil, "no restore without saved weapons")
    ns.db.actions.weapons = saved
end)

ns:Register("test", "text: progress reads X -> N", function(t)
    t:eq(ns.Progress(9, 66), "9 -> 66", "Flow's own progress")
    t:eq(ns.ProgressText("Slimy Menace: 0/7 Murloc slain"), "Slimy Menace: 0 -> 7 Murloc slain", "game objective text")
    t:eq(ns.ProgressText("Murloc slain: 3 / 7"), "Murloc slain: 3 -> 7", "spaces around the slash")
    t:eq(ns.ProgressText(nil), nil, "nil stays nil")
end)

ns:Register("test", "skillplan: fishing feeds cooking", function(t)
    local SP = ns.skillPlan
    local g = ns:Get("profGuide", "Cooking")
    local step, fish, id = SP.FishAlternative(g.steps, 2672)
    t:eq(id, 6291, "wolf meat's stand-in from fishing: Raw Brilliant Smallfish")
    t:ok(step and step.recipeItem == 6325, "its recipe is bought")
    t:ok(fish and fish.share > 0, "share of catches")
    -- Catches still to come: only when Fishing is on the plan.
    t:eq(SP.PlannedCatch({}), 0, "no Fishing target, no fish")
    local rank = ns.api.Skill("Fishing")
    if rank then
        t:eq(SP.PlannedCatch({ Fishing = { target = rank + 10 } }), 10, "10 points to go: about 10 catches")
        t:eq(SP.PlannedCatch({ Fishing = { target = rank } }), 0, "at target: none")
    end
    -- The fish step is never preferred over meat you'd farm when you have no fish.
    local crafts = SP._simulate("Cooking", g.steps, 1, 10, {})
    t:ok(crafts[g.steps[3]] == nil, "no fish in bags: plan doesn't count on cooking fish")
end)

ns:Register("test", "perf: Flow's update loops are timed", function(t)
    local P = ns.perf
    local f = P.Wrap("test: wrapped", function(a, b) return a + b, "x" end)
    local s, x = f(2, 3)
    t:eq(s, 5, "wrapped function still returns its results"); t:eq(x, "x", "second result too")
    t:eq(P.stats["test: wrapped"].calls, 1, "call counted")
    P.stats["test: wrapped"] = nil
    t:ok(P.stats["arrow + minimap (10/s)"] ~= nil, "route arrow timed")
    t:ok(P.stats["route: order stops"] ~= nil, "planner timed")
    t:ok(#P:Report() >= 1, "report has a summary line")
    t:ok(ns.nav.Busy() == true or ns.nav.Busy() == false, "tracker can tell when the route is being redone")
end)

ns:Register("test", "actions: any fishing stop counts, not just the quest's", function(t)
    local P = ns.actions.GoalProf
    t:eq(P({ key = "skill:Fishing", text = "Fish at the lake (Fishing 20, aim for 58)" }), "Fishing", "skill errand (no prof field)")
    t:eq(P({ key = "skill:Fishing", prof = "Fishing", text = "Fish: 1 -> 20" }), "Fishing", "skill planner stop")
    t:eq(P({ key = "123:1", kind = "collect", text = "Catch 5 Raw Brilliant Smallfish" }), "Fishing", "fishing quest objective")
    t:eq(P({ key = "buy:6256", kind = "merchant", text = "Buy a Fishing Pole" }), nil, "buying the pole isn't fishing")
    t:eq(P({ key = "gather:Copper Vein", prof = "Mining" }), "Mining", "mining stop")
    t:eq(P({ key = "99128:1", text = "Slimy Menace: 0 -> 7 Murloc slain" }), nil, "a kill quest isn't fishing")
end)

ns:Register("test", "skillplan: fishing suggests a lure", function(t)
    local g = ns:Get("profGuide", "Fishing")
    t:eq(g.lure, 6529, "Shiny Bauble is Fishing's lure")
    local stop = ns.skillPlan:LureGoal("Fishing")
    if stop then
        t:eq(stop.key, "buy:6529", "buy stop for the bauble")
        t:ok(stop.optional, "optional: only when it's on the way")
    else
        t:ok(true, "no stop: you carry a lure, or no known vendor")
    end
    t:eq(ns.skillPlan:LureGoal("Mining"), nil, "no lure for Mining")
end)

ns:Register("test", "skillplan: Fishing paces with the water, crafting with your level", function(t)
    local SP = ns.skillPlan
    t:eq(SP.Pace("Fishing", 10), 25, "level 10: starting-zone water")
    t:eq(SP.Pace("Fishing", 20), 75, "level 20: next zones")
    t:ok(SP.Pace("Fishing", 8) < 25, "level 8: under 25, not 58")
    t:eq(SP.Pace("First Aid", 10), 75, "crafting keeps the general curve")
end)

ns:Register("test", "crafting: make exactly enough, and say what's next", function(t)
    local H = ns.craftHint
    t:ok(type(H.Craft) == "function", "Make N button can craft")
    t:eq(#H.CraftStops("No Such Profession"), 0, "no stops for an unknown profession")
    for _, g in ipairs(ns.skillPlan.lastStops or {}) do
        if g.recipe then
            t:ok(g.makeCount and g.makeCount > 0, g.recipe .. ": has a count")
            t:ok(g.target and g.planned, g.recipe .. ": knows its target and planned total")
            t:ok(g.text:find("|cffffd100", 1, true) ~= nil, g.recipe .. ": count highlighted")
        end
    end
end)

ns:Register("test", "actions: a selected NPC never blocks the Flow key", function(t)
    -- Flow's own spells cast on you, not your target (Lee Brown selected: cast failed).
    if ns.api.SpellInfo("Fishing") and not (UnitChannelInfo and UnitChannelInfo("player")) then
        local s = ns:Get("action", "fish:cast").get({ fishing = true, pole = true })
        t:eq(s and s.unit, "player", "Fishing casts with no target")
    end
    local c = ns.actions.ClearTargetStep("test")
    t:eq(c.type, "clear", "clear-target step")
    t:eq(ns.cast._describe(c), "/cleartarget", "described for the diagnostics")
    t:ok(c.icon:find("\\", 1, true) ~= nil, "icon path keeps its backslashes")
end)

ns:Register("test", "router: handle and help legend share one look", function(t)
    local M = ns.mapOverlay
    t:ok(type(M.MakeHandle) == "function", "one handle builder for rows and legend")
    local h = M.MakeHandle(UIParent, 16)
    h.active = true; h:Paint(false)
    t:ok(h.ring:IsShown() and not h.arms[1]:IsShown(), "active: (o) marker, no ^")
    h.active = false; h:Paint(false)
    t:ok(h.arms[1]:IsShown() and not h.ring:IsShown(), "others: ^ chevron")
    h:Hide()
end)
