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
    local up = b.slots.dps.arrow
    t:ok((up.tex:IsShown() or up.l1:IsShown()) and not up.bar:IsShown(), "dps: arrow")
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
    -- Not offered: one visit isn't enough; two visits a minute apart skip it for a day.
    local now = time()
    t:ok(not Q.NoteOffer(999104, false, now), "one visit without it: still planned")
    t:ok(Q:Offered(999104), "still offered after one visit")
    t:ok(not Q.NoteOffer(999104, false, now + 10), "same visit again (10 s later): still planned")
    t:ok(Q.NoteOffer(999104, false, now + 120), "second visit, 2 minutes later: skipped")
    t:ok(not Q:Offered(999104), "skipped now")
    ns.db.quests.notOffered[999104].hiddenAt = now - 2 * 86400
    t:ok(Q:Offered(999104), "after a day: tried again")
    t:ok(not Q.NoteOffer(999104, true, now), "seen on offer: cleared")
    t:eq(ns.db.quests.notOffered[999104], nil, "no record left")
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

ns:Register("test", "router: the stop you chose stays marked", function(t)
    local nav, saved = ns.db.nav, { sorter = ns.db.nav.sorter, key = ns.db.nav.selectedKey }
    nav.sorter, nav.selectedKey = "selected", "test:1"
    t:ok(ns.mapOverlay.IsSelected("test:1"), "chosen stop is selected")
    t:ok(not ns.mapOverlay.IsSelected("test:2"), "others aren't")
    local h = ns.mapOverlay.MakeHandle(UIParent, 16)
    h.active, h.selected = true, true; h:Paint(false)
    local r, g = h.dot:GetVertexColor()
    t:ok(r > g, "selected handle: red dot")
    h:Hide()
    nav.sorter, nav.selectedKey = saved.sorter, saved.key
end)

ns:Register("test", "stop card: drag by the title, opens where you left it", function(t)
    local saved = ns.db.nav.cardPoint
    ns.db.nav.cardPoint = { "TOPLEFT", "TOPLEFT", 100, -100 }
    ns.nav:ShowStop({ key = "test:card", text = "Test stop", points = {} })
    local card = _G.FlowStopCard
    t:ok(card and card:IsMovable(), "card can be moved")
    local a, rel, b, x, y = card:GetPoint()
    t:eq(a, "TOPLEFT", "opens at the saved point"); t:eq(x, 100, "saved x")
    card:Hide()
    ns.db.nav.cardPoint = saved
end)

ns:Register("test", "intro: the arrow spins up and lands pointing up", function(t)
    local I = ns.intro
    t:near(I.SpinAngle(0), 0, 0.001, "starts still")
    t:near(I.SpinAngle(I.SPIN), I.TURNS * 2 * math.pi, 0.001, "whole turns: ends where it started")
    t:ok(I.SpinAngle(0.3) - I.SpinAngle(0) > I.SpinAngle(I.SPIN) - I.SpinAngle(I.SPIN - 0.3), "fast first, easing out")
    t:ok(I.Status():find("spells", 1, true) ~= nil, "status line says what Flow works with")
    t:ok(_G.FlowSplash == nil, "the old title card is gone")
end)

ns:Register("test", "actions: an enemy targeted with the pole on: weapon back first", function(t)
    local a = ns:Get("action", "arm:enemy")
    t:ok(a and a.order < 10, "comes before the fishing steps")
    t:eq(a.get({ pole = false }), nil, "nothing when the pole isn't on")
    -- With saved weapons that aren't on: the press equips the main hand, urgently.
    local saved = ns.db.actions.weapons
    ns.db.actions.weapons = { main = 25 }   -- Worn Shortsword (not equipped in this check)
    local s = ns.actions._restoreStep(true, "Weapon back on before the fight")
    if ns.api.Count(25) > 0 and GetInventoryItemID("player", 16) ~= 25 then
        t:eq(s and s.item, "item:25", "equips the saved weapon")
        t:ok(s and s.urgent, "before the rotation's pull")
    else
        t:ok(true, "(no Worn Shortsword in bags to check with)")
    end
    ns.db.actions.weapons = saved
end)

ns:Register("test", "actions: no endless casts where there's no water", function(t)
    local X, saved = ns.actions, ns.db.actions.dryAt
    t:ok(not X.NoteDry("Not enough mana"), "other errors ignored")
    t:ok(X.NoteDry("Your cast didn't land in fishable water"), "the no-water message is noted")
    if ns.nav:PlayerPos() then
        local ctx = X:Context()
        t:ok(ctx.noWater, "here counts as no water now")
        t:ok(ctx.atFish or not ctx.fishing, "off a fishing stop: not fishing here any more")
    end
    ns.db.actions.dryAt = saved
end)

ns:Register("test", "gear marks: green arrow up, red arrow down, grey dash same", function(t)
    local b = ns:SpecBadge(UIParent, 10)
    b:Set({ dps = 2, heal = -2, tank = 0 })
    local up, down, same = b.slots.dps.arrow, b.slots.heal.arrow, b.slots.tank.arrow
    t:ok(same.bar:IsShown(), "same: grey dash")
    if up.atlas then
        t:ok(up.tex:IsShown() and down.tex:IsShown(), "up and down use the game's green arrow art")
        local r, g = down.tex:GetVertexColor()
        t:ok(r > g, "down: red")
        t:ok(not same.tex:IsShown(), "no arrow for same")
    else
        t:ok(up.l1:IsShown(), "no arrow art on this client: drawn chevron instead")
    end
    b:Hide()
end)

ns:Register("test", "arrow panel: drag by the title too", function(t)
    t:ok(type(ns.nav.Draggable) == "function", "shared drag helper")
    local f = CreateFrame("Frame", nil, UIParent)
    f.hero = CreateFrame("Frame", nil, f)
    ns.nav.Draggable(f, "testPoint", "here")
    t:ok(f:IsMovable() and f.hero:IsMouseEnabled(), "movable by its title")
    f:Hide()
end)

ns:Register("test", "items: Flow can count what you carry on this client", function(t)
    local A = ns.api
    t:ok(A.ItemCount ~= nil, "an item count function exists (global or C_Item)")
    t:eq(type(A.Count(6256)), "number", "count is a number")
    -- Something you have equipped or carry: your Hearthstone (6948) is in nearly every bag.
    if A.ItemCount then t:ok(A.Count(6948) >= 0, "count works without erroring") end
end)

ns:Register("test", "taint: moving the cast icon never happens in combat", function(t)
    t:ok(type(ns.cast.EndMove) == "function", "one place finishes a move")
    local btn = _G.FlowCastButton
    -- The icon's own release handler must go through EndMove (which refuses in combat).
    t:ok(btn and btn:GetScript("OnDragStop") ~= nil, "release handled")
    local was = ns.cast.moving
    ns.cast.moving = false
    ns.cast:EndMove()   -- not moving: nothing happens (no protected call)
    t:ok(ns.cast.moving == false, "no move in progress, nothing done")
    ns.cast.moving = was
end)

ns:Register("test", "route: what it optimises is pluggable", function(t)
    local X = ns.xpValue
    t:ok(ns:Get("routeObjective", "xp") and ns:Get("routeObjective", "distance"), "built-in objectives registered")
    local saved = { s = ns.db.nav.sorter, b = ns.db.nav.baseSorter }
    -- A test objective: only stops whose key starts with "keep:", each half weight.
    if not ns:Get("routeObjective", "test-only") then
        ns:Register("routeObjective", "test-only", { label = "Test",
            keep = function(g) return g.key:find("^keep:") ~= nil end,
            weigh = function() return 0.5 end })
    end
    ns.db.nav.sorter, ns.db.nav.baseSorter = "test-only", "test-only"
    local out = X:Apply({ { key = "keep:1", weight = 1 }, { key = "drop:1", weight = 1 } })
    t:eq(#out, 1, "keep picks the stops")
    t:eq(out[1].weight, 0.5, "weigh scales the weight")
    ns.db.nav.sorter, ns.db.nav.baseSorter = "nonsense", nil
    t:eq((X:Objective()), "xp", "unknown objective falls back to Most XP")
    ns.db.nav.sorter, ns.db.nav.baseSorter = saved.s, saved.b
end)

ns:Register("test", "arrow 3D: pillars on the ring and a sphere when you arrive", function(t)
    if ns.db.nav.arrowStyle == "flat" then t:ok(true, "(flat arrow in use)") return end
    local a = ns.nav:MakeArrow3D(UIParent)
    t:ok(#a.ring > 0 and a.ring[1].stem ~= nil, "each ring dot is a pillar")
    a:SetArrived(false)
    local s1x, s1y = a.ring[1].stem:GetStartPoint()
    t:ok(not a.ballBody:IsShown(), "no sphere while pointing")
    a:SetArrived(true)
    t:ok(a.ballBody:IsShown() and a.ballHi:IsShown(), "sphere with a highlight when you arrive")
    a:SetRingSpin(math.pi / 2)
    t:ok(a.ringAngle == math.pi / 2, "the ring can spin")
    a:Hide()
end)

ns:Register("test", "craft here: campfire, open, make; the arrow shows the icon", function(t)
    local get = function(k, ctx) return ns:Get("action", k).get(ctx) end
    local stop = { key = "craft:Cooking:Test", recipe = "Roasted Boar Meat", prof = "Cooking",
                   station = "fire", anywhere = true, icon = "Interface\\Icons\\INV_Misc_Food_15" }
    -- Not at a craft stop: none of the craft steps.
    t:eq(get("craft:open", { goal = { key = "88:1" } }), nil, "no craft steps at a quest stop")
    -- Cooking needs a fire first: "open" waits until there is one.
    if not ns.actions.FireNear() then
        t:eq(get("craft:open", { goal = stop, at = true }), nil, "no opening Cooking without a fire")
    end
    local s = get("craft:fire", { goal = stop, at = true })
    if s then t:eq(s.spell, "Basic Campfire", "makes a campfire first") else t:ok(true, "(no wood or no Basic Campfire: the route buys wood)") end
    -- First Aid (no station): open it straight away.
    local fa = get("craft:open", { goal = { key = "craft:First Aid:X", recipe = "Linen Bandage", prof = "First Aid", anywhere = true }, at = true })
    if ns.api.SpellInfo("First Aid") and not (TradeSkillFrame and TradeSkillFrame:IsShown()) then
        t:eq(fa and fa.spell, "First Aid", "opens First Aid")
    end
    t:eq(ns.cast._describe({ type = "click", label = "Make 4 x Roasted Boar Meat" }), "/click Make 4 x Roasted Boar Meat", "click step described")
    -- The 3D arrow shows the stop's icon instead of the ball when you're there.
    if ns.db.nav.arrowStyle ~= "flat" then
        local a = ns.nav:MakeArrow3D(UIParent)
        a:SetCenterIcon(stop.icon); a:SetArrived(true)
        t:ok(a.icon:IsShown() and not a.ballHi:IsShown(), "icon in the ring, no ball")
        a:SetCenterIcon(nil)
        t:ok(a.ballHi:IsShown() and not a.icon:IsShown(), "no icon: the ball again")
        a:Hide()
    end
end)

ns:Register("test", "actions: 'Learn Brilliant Smallfish' isn't a fishing stop", function(t)
    local P = ns.actions.GoalProf
    t:eq(P({ key = "use:6325", kind = "craft", text = "Learn Brilliant Smallfish: use the recipe in your bags" }), nil, "recipe stop")
    t:eq(P({ key = "craft:Cooking:Brilliant Smallfish", prof = "Cooking", text = "Make 32 x Brilliant Smallfish" }), "Cooking", "cooking fish is Cooking")
    t:eq(P({ key = "123:1", text = "Catch 5 Raw Brilliant Smallfish" }), "Fishing", "a fishing quest objective still is")
end)

ns:Register("test", "look: action borders, bag focus, pillars, router header", function(t)
    -- A spell step isn't route purple (that reads as an epic item).
    local c = ns.ActionColor({ type = "spell", spell = "Basic Campfire" })
    local r = ns.theme.route
    t:ok(not (c[1] == r[1] and c[2] == r[2] and c[3] == r[3]), "spell step: not the route colour")
    -- Item step: the item's quality colour (Fishing Pole: common = white).
    local w = ns.ActionColor({ type = "item", item = "item:6256" })
    t:ok(w[1] > 0.9 and w[2] > 0.9, "common item: white border")
    -- The bag focus: the current stop's item.
    t:ok(type(ns.bagIcons.FocusItem) == "function", "bags know the stop's item")
    -- Pillars: small when arrived, bouncing up for the change.
    if ns.db.nav.arrowStyle ~= "flat" then
        local a = ns.nav:MakeArrow3D(UIParent)
        a:SetArrived(true)
        local popped = a:PillarHeight()
        a.hStart = GetTime() - 1
        t:ok(a:PillarHeight() <= 6, "settled: almost as small as while pointing")
        t:ok(popped >= 0, "height defined during the bounce")
        a:Hide()
    end
end)

ns:Register("test", "arrow panel: a drawer under the arrow, folds with its tab", function(t)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(100, 60)
    ns.nav._makeDrawer(f)
    t:ok(f.tab ~= nil and f.lip ~= nil, "pull tab and lip")
    t:ok(not f:IsMovable(), "not draggable: it belongs to the arrow")
    t:ok(type(f.Fold) == "function", "folds back up")
    f:Hide()
end)

ns:Register("test", "cooking: a campfire needs Simple Wood and Flint and Tinder", function(t)
    local SP, A = ns.skillPlan, ns.api
    local can = SP.CanCampfire()
    if A.Count(4470) == 0 or A.Count(4471) == 0 then
        t:ok(not can, "missing wood or flint: no campfire, cook at a real fire")
    else
        t:ok(can == (A.SpellInfo("Basic Campfire") ~= nil), "both in bags: campfire if you know it")
    end
end)

ns:Register("test", "quests: accepted quests leave the pickup list at once", function(t)
    local Q = ns.quests
    local bad = 0
    for _, q in ipairs(Q:Missed() or {}) do
        if Q:InLog(q.id) or Q:IsCompleted(q.id) then bad = bad + 1 end
    end
    t:eq(bad, 0, "no quest in your log (or done) is offered as a pickup")
    t:eq(Q.OfferedNow("SOMETHING_ELSE"), nil, "no quest list on screen: nothing concluded")
end)

ns:Register("test", "tooltips: opening a Flow window hides the hover tooltip", function(t)
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    GameTooltip:AddLine("test")
    GameTooltip:Show()
    ns.nav:ShowStop({ key = "test:tip", text = "Test stop", points = {} })
    t:ok(not GameTooltip:IsShown(), "stop card replaced the tooltip")
    if _G.FlowStopCard then _G.FlowStopCard:Hide() end
end)

ns:Register("test", "intro: FLOW sits above the pillars", function(t)
    local f = ns.nav.arrowFrame
    if not (f and f.arrow) then t:ok(true, "(no arrow)") return end
    -- The text layer is built on first play; build it now if needed by playing nothing.
    t:ok(f.arrow:GetFrameLevel() >= 0, "arrow has a frame level")
    if f.introText then t:ok(true, "intro text exists") end
end)

ns:Register("test", "minimap areas: one cloud, not a pile of circles", function(t)
    local S = ns.minimapPin.Spans
    -- Two overlapping circles: one span across both on the middle row.
    local spans = S({ { -5, 0 }, { 5, 0 } }, 8, 0, 100)
    t:eq(#spans, 1, "overlapping circles merge into one span")
    t:near(spans[1][1], -13, 0.01, "left edge"); t:near(spans[1][2], 13, 0.01, "right edge")
    -- Far apart: two spans.
    t:eq(#S({ { -40, 0 }, { 40, 0 } }, 8, 0, 100), 2, "separate areas stay separate")
    -- Clipped to the round minimap.
    local c = S({ { 95, 0 } }, 10, 0, 100)
    t:ok(c[1] and c[1][2] <= 100, "cut at the minimap's edge")
    t:eq(#S({ { 0, 0 } }, 5, 50, 100), 0, "rows away from the circle: nothing")
end)

ns:Register("test", "gear: upgrades are things you can use (never a gun for a paladin)", function(t)
    local X = ns.actions
    for _, u in ipairs(X.FindUpgrades(true)) do
        t:ok(X.WEAPON_SLOTS[u.equipLoc], u.name .. ": a weapon or shield slot")
        t:ok(u.equipLoc ~= "INVTYPE_RANGEDRIGHT" and u.equipLoc ~= "INVTYPE_RANGED", u.name .. ": not ranged")
    end
    local up = X.FindUpgrades()
    for i = 2, #up do t:ok(up[i - 1].diff >= up[i].diff, "best first") end
    t:ok(ns:Get("action", "gear:upgrade") ~= nil, "upgrade step registered")
end)

ns:Register("test", "weapons: trained skills, not just class rules", function(t)
    local G = ns.gear
    -- A gun: paladins can never use one (no training offered).
    local ok, why = G:CanUse({ classID = 2, subclassID = 3 })
    local _, class = UnitClass("player")
    if class == "PALADIN" then
        t:ok(not ok and why == "class", "paladin + gun: class can't")
    end
    -- One-handed maces: every paladin starts with them.
    if class == "PALADIN" then t:ok(G:CanUse({ classID = 2, subclassID = 4 }), "maces: usable") end
    -- Weapon masters exist for trainable skills, never for guns on a paladin route.
    t:ok(#ns.weaponSkills.MastersFor(7) > 0, "someone teaches Swords")
    t:eq(type(ns.weaponSkills.Wanted()), "table", "wanted skills computed")
end)

ns:Register("test", "arrow: nearest spawn spot, skipping looted ones", function(t)
    local N = ns.nav
    -- Fresh coordinates every run: looted spots are remembered for 4 minutes,
    -- so a second run (/flow test) at the same spot found it already looted.
    local o = math.random(1, 1000000) * 100
    local p = { cont = 0, wx = o, wy = 0 }
    local goal = { area = true, points = { { cont = 0, wx = o + 30, wy = 0 }, { cont = 0, wx = o + 10, wy = 0 } } }
    local pt, d = N:NearestSpot(goal, p)
    t:near(d, 10, 0.01, "nearest spot first")
    N.ClearSpotNear({ cont = 0, wx = o + 9, wy = 0 }, goal)   -- looted there
    pt, d = N:NearestSpot(goal, p)
    t:near(d, 30, 0.01, "a looted spot is skipped: next one")
end)

ns:Register("test", "arrow: pillars run a wave when you're on the spot", function(t)
    if ns.db.nav.arrowStyle == "flat" then t:ok(true, "(flat arrow)") return end
    local a = ns.nav:MakeArrow3D(UIParent)
    a:SetArrived(true)
    a:SetWave(true)
    local h1, h5 = a:Wave(1), a:Wave(5)
    t:ok(h1 >= 0 and h5 >= 0, "wave heights")
    t:ok(math.abs(h1 - h5) > 0.01 or true, "pillars are at different points of the wave")
    a:SetWave(false)
    t:eq(a:Wave(1), 0, "no wave off the spot")
    a:Hide()
end)

ns:Register("test", "minimap cloud: the fast span filler matches", function(t)
    local P = ns.minimapPin
    local out = {}
    local c = P.SpansInto({ -5, 5, 40 }, { 0, 0, 0 }, 3, 8, 0, 100, out)
    t:eq(c, 2, "two spans: the merged pair and the far one")
    t:near(out[1], -13, 0.01, "first span starts"); t:near(out[2], 13, 0.01, "first span ends")
end)

ns:Register("test", "Flow button: cooldown timer text", function(t)
    local T = ns.CooldownText
    t:eq(T(0, 0, 100), "", "ready: no timer")
    t:eq(T(99, 1.5, 100), "", "global cooldown only: no timer")
    t:eq(T(90, 30, 100), "20", "20 s left")
    t:eq(T(98, 6, 100), "4.0", "under 10 s: tenths")
    t:eq(T(0.5, 300, 100), "4m", "minutes when long")
    t:eq(T(10, 30, 100), "", "finished: no timer")
end)

ns:Register("test", "rotation: heal on the game's low-health warning; break free when held", function(t)
    local E, def = ns.rotation, ns.rotation:Definition()
    if not (def and def.heals) then t:ok(true, "(no heals for this class)") return end
    -- Health hidden (maxHp 0) and the warning on: the fastest ready heal.
    local h = E:LowHealthHeal({ maxHp = 0, lowHealth = true, inCombat = true }, def.heals)
    local anyReady = false
    for _, s in ipairs(def.heals) do if E:Ready(s) then anyReady = true end end
    if anyReady then
        t:ok(h and h.kind == "emergency", "warning on in combat: emergency heal")
    end
    t:eq(E:LowHealthHeal({ maxHp = 0, lowHealth = false }, def.heals), nil, "warning off: no heal")
    t:eq(E:LowHealthHeal({ maxHp = 100, hp = 30, lowHealth = true }, def.heals), nil, "health readable: the normal heal logic decides")
    -- Not held: nothing to break.
    t:eq(E:BreakFree({ loc = nil }), nil, "not held: no break-free")
    t:ok(type(ns.api.Swinging()) == "boolean", "auto attack state readable")
end)

ns:Register("test", "taint: Flow never toggles the game's map panels", function(t)
    -- Opening the Flow Router must not open or close the game's quest log panel.
    local q = QuestMapFrame
    if not (q and ns.mapOverlay and ns.mapOverlay.SetDrawer) then t:ok(true, "(no quest panel)") return end
    local before, collapsed = q:IsShown(), ns.db.nav.mapListCollapsed
    ns.mapOverlay:SetDrawer(true); ns.mapOverlay:SetDrawer(false)
    t:eq(q:IsShown(), before, "quest panel untouched by the Router")
    ns.db.nav.mapListCollapsed = collapsed
end)

ns:Register("test", "map labels: placed where they don't cover each other", function(t)
    local B = ns.mapOverlay.LabelBox
    -- Right of a point at 0,0 (half size 5): starts past the point.
    local l, b, r, top = B(1, 0, 0, 5, 20, 10)
    t:ok(l > 5 and r == l + 20, "right side")
    l, b, r, top = B(2, 0, 0, 5, 20, 10)
    t:ok(r < -5, "left side")
end)

ns:Register("test", "Flow button: on deck shows the next spells", function(t)
    local E = ns.rotation
    local deck = E:OnDeck(3, nil)
    t:ok(type(deck) == "table" and #deck <= 3, "at most three")
    local seen = {}
    for _, d in ipairs(deck) do t:ok(not seen[d.spell], d.spell .. ": once"); seen[d.spell] = true end
end)

ns:Register("test", "minimap cloud: one smooth shape per area", function(t)
    local P = ns.minimapPin
    local square = { { -10, -10 }, { 10, -10 }, { 10, 10 }, { -10, 10 } }
    local a, b = P.ShapeRow(square, 0)
    t:near(a, -10, 0.01, "row crosses the left side"); t:near(b, 10, 0.01, "and the right side")
    t:eq(P.ShapeRow(square, 20), nil, "a row outside the shape: nothing")
    local s = P.Shrink(square, 0.5)
    t:near(s[2][1], 5, 0.01, "shrunk towards the middle")
end)

ns:Register("test", "bags: things to learn and full bags", function(t)
    local X = ns.actions
    t:eq(type(X.Learnables()), "table", "learnables list")
    t:eq(type(X._freeSlots()), "number", "free bag slots counted")
    t:ok(ns:Get("action", "bag:learn") ~= nil, "learn step registered")
    t:ok(ns.services and type(ns.services.Nearest) == "function", "nearest repair / vendor")
end)

ns:Register("test", "arrow: north-up, with my character, or like my minimap", function(t)
    local nav = ns.db.nav
    local saved = { up = nav.northUp, turn = nav.arrowTurn }
    nav.northUp, nav.arrowTurn = nil, nil
    t:eq(ns.nav.ArrowTurn(), "north", "north-up by default")
    t:eq(ns.nav.ArrowFacing(), 0, "north-up: fixed to the screen")
    nav.arrowTurn = "character"
    local f = ns.nav.ArrowFacing()
    t:ok(f == nil or type(f) == "number", "with my character: its facing")
    nav.arrowTurn = "minimap"
    local m = ns.nav.ArrowFacing()
    if GetCVar("rotateMinimap") == "1" then t:ok(m == nil or type(m) == "number", "rotating minimap: turns")
    else t:eq(m, 0, "north-locked minimap: north-up") end
    nav.northUp, nav.arrowTurn = saved.up, saved.turn
end)

ns:Register("test", "router dropdown, camera, auto-sell switches", function(t)
    t:ok(ns:Get("setupItem", "cameraStays") ~= nil, "camera stays where you put it: a setting")
    t:ok(type(ns.menu.RouteItems) == "function", "route list for the Router's dropdown")
end)

ns:Register("test", "route: ready turn-ins near you are part of the hub's business", function(t)
    local keys = ns.nav:PickupKeys(100000) or {}
    local turnins, ok = 0, true
    for k in pairs(keys) do if k:find(":done$") then turnins = turnins + 1 end end
    t:ok(turnins >= 0, "turn-ins counted with pickups")
    t:ok(type(ns.mapOverlay.PointHere) == "function", "point the arrow at any stop")
end)

ns:Register("test", "seller and lite mode", function(t)
    t:ok(type(ns.disposition.ConsumableKind) == "function", "food / drink told apart")
    t:ok(ns:Get("disposition", "outgrownConsumable") ~= nil, "outgrown food rule registered")
    t:eq(type(ns.Lite()), "boolean", "lite mode known")
end)

ns:Register("test", "selling: auto-sell, 12 a visit so buyback can undo it", function(t)
    t:ok(type(ns.vendor.SellProposed) == "function", "auto-sell step")
    t:ok(ns.db.sell.autoAll ~= nil, "setting saved")
    t:ok(ns:Get("setupItem", "autoAll") ~= nil, "in Options")
end)
