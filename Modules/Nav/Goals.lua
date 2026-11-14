-- Navigation goals from your quest log.
--   finished quest      -> go to the NPC (or object) that takes it
--   kill objective      -> nearest spawn of that mob
--   collect objective   -> nearest mob/object that drops the item
--   use/click objective -> nearest spawn of that object
-- Locations come from Questie + QuestieDB (read at runtime, see QuestData.lua).
-- Without them, the game's own quest waypoint is used where the client has one.

local _, ns = ...

local MAX_POINTS = 80   -- spawns per goal

-- Daily quest? (Questie quest flags; 0x1000 is the daily flag.)
local function isDaily(quest)
    return quest and quest.questFlags and bit and bit.band(quest.questFlags, 0x1000) ~= 0 or false
end

-- Your quest log: { { id, title, complete, objectives = { {text, finished} } } }
local function questLog()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local q = { id = info.questID, title = info.title, objectives = {} }
                q.complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false
                for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                    q.objectives[#q.objectives + 1] = { text = o.text, finished = o.finished }
                end
                out[#out + 1] = q
            end
        end
    elseif GetNumQuestLogEntries then
        for i = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
            if not isHeader and id then
                local q = { id = id, title = title, complete = isComplete == 1, objectives = {} }
                for j = 1, GetNumQuestLeaderBoards(i) do
                    local text, _, finished = GetQuestLogLeaderBoard(j, i)
                    q.objectives[#q.objectives + 1] = { text = text, finished = finished }
                end
                out[#out + 1] = q
            end
        end
    end
    return out
end

-- Questie modules use a mix of "." and ":" calls; try both.
local function call(db, fname, id)
    local fn = db[fname]
    if type(fn) ~= "function" then return nil end
    local ok, r = pcall(fn, id)
    if ok and type(r) == "table" then return r end
    ok, r = pcall(fn, db, id)
    if ok and type(r) == "table" then return r end
end

-- Questie spawn tables are { [areaId] = { {x, y}, ... } } in 0-100 coords.
local function addSpawns(points, spawns, cap, onlyMap)
    for areaId, list in pairs(spawns or {}) do
        local map = ns.quests:UiMapForArea(areaId)
        if map and (not onlyMap or map == onlyMap) then
            for _, c in ipairs(list) do
                if #points >= (cap or MAX_POINTS) then return end
                if c[1] and c[1] >= 0 and c[2] and c[2] >= 0 then
                    points[#points + 1] = { map = map, x = c[1] / 100, y = c[2] / 100 }
                end
            end
        end
    end
end

-- Spawn tables -> at most MAX_POINTS spots, spread over all of them with the
-- ones on your map first (ns.quests.SpreadPoints): every mob that drops the
-- item gets its share, not just the first one listed.
local function pointsFrom(tables)
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    local pts, _, known = ns.quests.SpreadPoints(tables, MAX_POINTS, { map = map })
    return pts, known
end

-- Adds the NPC's / object's spawn table to `tables`; returns its name (and the NPC).
local function npcSpawns(db, tables, id)
    local npc = call(db, "GetNPC", id)
    if npc and npc.spawns then tables[#tables + 1] = npc.spawns end
    return npc and npc.name, npc
end

local function objectSpawns(db, tables, id)
    local obj = call(db, "GetObject", id)
    if obj and obj.spawns then tables[#tables + 1] = obj.spawns end
    return obj and obj.name
end
ns.quests.LogEntries = questLog  -- shared with SkillPlan.lua

-- The goals for one quest: its turn-in, and (while unfinished) a goal per
-- objective you still need. Used for your own log and for a party member's
-- quests (Party.lua: "help Bob").
--   q    = { id, title, complete, objectives = { { text, finished, have, need } } }
--   opts = { prefix = "help:" (key prefix), who = "Bob" (shown in the text),
--            skip = function(key) -> true to leave a goal out,
--            unplaced = {} (gets { id, title, why } for what can't be placed) }
-- Appends to `goals`. A quest Flow can't place used to drop off the route
-- without a word ("Dirt-stained Map"); `unplaced` says which and why, for
-- /flow nav why and the diagnostics.
local function questGoals(db, q, goals, opts)
    opts = opts or {}
    local prefix, skip = opts.prefix or "", opts.skip or function() return false end
    local whose = opts.who and (opts.who .. ": ") or ""
    local function cant(why)
        if opts.unplaced then opts.unplaced[#opts.unplaced + 1] = { id = q.id, title = q.title, why = why } end
    end
    -- The game's own marker for one of your quests ({ map, x, y } or nil):
    -- where Flow goes when its quest data has no place (opts.waypoint: tests).
    local waypoint = opts.waypoint or ns.quests.GameWaypoint or function() return nil end
    local missing = {}   -- unfinished objectives with no place: { key, text, why, kind }
    local quest = call(db, "GetQuest", q.id)
    if not quest then
        cant("Questie doesn't know this quest (a WoW: Forever one?), so Flow has no place for it")
        -- Still on your route: at the game's marker, else listed with the reason.
        local key = prefix .. q.id .. ":wp"
        if not opts.who and not skip(key) then
            local wp = waypoint(q.id)
            goals[#goals + 1] = {
                key = key, points = wp and { wp } or {}, title = q.title, kind = q.complete and "turnin" or "use",
                area = (wp and not q.complete) or nil,
                text = (q.complete and "Turn in: " or "") .. (q.title or "a quest"),
                details = { "Quest: " .. (q.title or "?"),
                            wp and "Flow's quest data doesn't have this quest: the arrow goes to the game's own marker for it."
                                or "Flow's quest data doesn't have this quest." },
                blockedBy = (not wp) and "Flow doesn't know where: its quest data doesn't have this quest (a WoW: Forever one?). Your quest log says how." or nil,
                blockedShort = (not wp) and ns.nav.NO_SPOT or nil,
            }
        end
        return
    end
    local title = q.title or quest.name
    -- Where the quest is handed in. For unfinished quests this is a later
    -- stop that the planner puts after the objectives (deps), so it can
    -- decide "finish, then turn in on the way".
    local turnSpawns, who = {}, nil
    local fin = ns.quests.FinisherOf(quest)
    for _, id in ipairs(fin.NPC or {}) do
        who = npcSpawns(db, turnSpawns, id) or who
    end
    for _, id in ipairs(fin.GameObject or {}) do
        who = objectSpawns(db, turnSpawns, id) or who
    end
    local turnIn = {
        key = prefix .. q.id .. ":done", weight = 0.8, points = pointsFrom(turnSpawns), level = quest.level,
        npcs = who and { who } or nil,
        kind = isDaily(quest) and "daily" or "turnin",
        title = title, helping = opts.who,
        text = whose .. "Turn in: " .. (title or "quest"),
        details = { (q.complete and "Quest complete. " or "After the objectives. ")
            .. "Hand it in to " .. (who or "the quest giver") .. "." },
        deps = {},
    }
    if not skip(turnIn.key) then goals[#goals + 1] = turnIn end
    -- Nowhere in the quest data: where it was handed in before (LearnedSpots).
    if #turnIn.points == 0 and ns.learnedSpots then
        local pts = ns.learnedSpots.Points(q.id, "done")
        if pts then
            turnIn.points = pts
            table.insert(turnIn.details, "Flow's quest data has no place for it: this is where it was handed in before.")
        end
    end
    if #turnIn.points == 0 then
        cant("Flow doesn't know where it's handed in (" .. (who or "no NPC or object in Questie") .. ")")
        -- A finished quest with nowhere known to hand it in: the game's own
        -- marker, else listed with the reason ("Searching for the Lost Satchel").
        if q.complete and not opts.who then
            local wp = waypoint(q.id)
            if wp then
                turnIn.points = { wp }
                table.insert(turnIn.details, "Flow's quest data has no place for it: the arrow goes to the game's own marker.")
            else
                turnIn.blockedBy = "Flow doesn't know where it's handed in" .. (who and (" (" .. who .. ")") or "") .. ". Your quest log says who to."
                turnIn.blockedShort = ns.nav.NO_SPOT
                local inside = ns.dungeons and ns.dungeons.Of and ns.dungeons.Of(q.id)
                if inside then
                    turnIn.blockedBy = "Handed in inside " .. inside .. (who and (" (" .. who .. ")") or "") .. ": a dungeon, so it isn't on your route. The dungeon run brings you there."
                    turnIn.blockedShort = "in " .. inside
                end
            end
        end
    end
    if q.complete then return end
    for i, obj in ipairs(q.objectives) do
        local od = quest.ObjectiveData and quest.ObjectiveData[i]
        -- "Raise your X skill to N": planned by SkillPlan.lua (gather,
        -- smelt, craft), not by walking to the trainer.
        local skillObj = obj.text and ns.skillPlan and ns.skillPlan.ParseObjective(obj.text)
        local key = prefix .. q.id .. ":" .. i
        if not obj.finished and not od and not skillObj then
            cant(string.format("objective %d (%s): Questie has no data for it", i, tostring(obj.text or "?")))
            missing[#missing + 1] = { key = key, text = obj.text, why = "Questie has no data for it", kind = "use" }
        end
        if not obj.finished and od and not skillObj then
            local spawns, verb, what, elite = {}, nil, nil, false
            local targets = {}  -- mob / NPC names (the arrow finds their nameplates in the area)
            if od.Type == "monster" then
                local npcRaw
                what, npcRaw = npcSpawns(db, spawns, od.Id); verb = "Kill"
                if what then targets[#targets + 1] = what end
                -- Elite mobs (Questie rank 1+): flagged and planned later; bring a friend.
                if npcRaw and (npcRaw.rank or 0) >= 1 then elite = true end
            elseif od.Type == "object" then
                what = objectSpawns(db, spawns, od.Id); verb = "Use"
            elseif od.Type == "event" and type(od.Coordinates) == "table" then
                -- "Cleanse the Thunderhorn Water Well": something to do at a
                -- place. Questie has the place (the quest's trigger spot).
                spawns[#spawns + 1] = od.Coordinates
                verb, what = "Go to", od.Text or obj.text
            elseif od.Type == "item" then
                local item = call(db, "GetItem", od.Id)
                verb = "Collect"; what = item and item.name
                -- Elite only if EVERY mob that drops it is elite (one elite
                -- among normal kobolds doesn't make the objective elite).
                local anyNormal, anyElite = false, false
                for _, npcId in ipairs(item and item.npcDrops or {}) do
                    local dropper, npcRaw = npcSpawns(db, spawns, npcId)
                    if dropper then targets[#targets + 1] = dropper end
                    if npcRaw and (npcRaw.rank or 0) >= 1 then anyElite = true else anyNormal = true end
                end
                elite = anyElite and not anyNormal
                for _, objId in ipairs(item and item.objectDrops or {}) do objectSpawns(db, spawns, objId) end
            end
            local points, known = pointsFrom(spawns)
            -- A quest 3+ levels above you (orange or red): its mobs hit hard.
            -- Planned later, like elites, so the easier ones come first.
            local hard = (quest.level or 0) - (opts.level or UnitLevel("player")) >= ns.quests.HARD_ABOVE
            if verb and #points > 0 then
                table.insert(turnIn.deps, key)
                -- A party member's objective has no text of its own: "Kill X 3/10".
                local objText = obj.text or string.format("%s %s%s", verb, what or "",
                    obj.need and string.format(" %d/%d", obj.have or 0, obj.need) or "")
                if not skip(key) then
                    goals[#goals + 1] = {
                        key = key, points = points, known = known, title = title, level = quest.level,
                        weight = (elite or hard) and 1.6 or nil, elite = elite or nil, hard = hard or nil, helping = opts.who,
                        npcs = #targets > 0 and targets or nil, area = true, target = what,
                        kind = isDaily(quest) and "daily" or (verb == "Kill" and "kill") or (verb == "Collect" and "collect") or "use",
                        text = whose .. (elite and "[Elite] " or "") .. (title and (title .. ": ") or "") .. ns.ProgressText(objText),
                        details = (function()
                            local d = { "Quest: " .. (title or "?"), "Objective: " .. (ns.ProgressText(objText) or "?") }
                            if opts.who then d[#d + 1] = opts.who .. "'s quest: you're helping them (kill credit is shared in a party)." end
                            if elite then d[#d + 1] = "Elite: hard to solo at this level. Group up or come back stronger." end
                            if hard then d[#d + 1] = string.format("Level %d: 3 or more levels above you, so its mobs hit hard. Flow plans it after the easier ones; bring a friend or come back a level or two later.", quest.level) end
                            if verb == "Collect" and what then d[#d + 1] = "Drops from mobs/objects near the arrow: " .. what end
                            return d
                        end)(),
                    }
                end
            elseif verb then
                local why = string.format("Questie has no spot for %s", tostring(what or "it"))
                cant(string.format("objective %d (%s): %s", i, tostring(obj.text or "?"), why))
                missing[#missing + 1] = { key = key, text = obj.text, why = why, kind = verb == "Collect" and "collect" or "use" }
            elseif od then
                local why = string.format("it's a kind Flow can't place (%s)", tostring(od.Type))
                cant(string.format("objective %d (%s): a kind Flow can't place (%s)", i, tostring(obj.text or "?"), tostring(od.Type)))
                missing[#missing + 1] = { key = key, text = obj.text, why = why, kind = "use" }
            end
        end
    end
    -- Objectives Flow couldn't place still belong on your route ("I don't see
    -- Thunderhorn Cleansing in my route but I have it", 0.35.174): at the
    -- game's own marker for the quest where it has one, else listed with the
    -- lock and the reason, so the quest never just isn't there. (Your own
    -- quests only: a party member's has no marker of yours.)
    if #missing > 0 and not opts.who then
        local wp = waypoint(q.id)
        if wp then
            local key = prefix .. q.id .. ":wp"
            for _ = 1, #missing do table.insert(turnIn.deps, key) end
            if not skip(key) then
                local d = { "Quest: " .. (title or "?") }
                for _, m in ipairs(missing) do d[#d + 1] = "Objective: " .. (ns.ProgressText(m.text) or "?") end
                d[#d + 1] = "Flow's quest data has no place for this: the arrow goes to the game's own marker for the quest."
                goals[#goals + 1] = {
                    key = key, points = { wp }, title = title, level = quest.level, kind = "use", area = true,
                    text = (title and (title .. ": ") or "") .. (ns.ProgressText(missing[1].text) or "see your quest log"),
                    details = d,
                }
            end
        else
            for _, m in ipairs(missing) do
                if not skip(m.key) then
                    local g = {
                        key = m.key, points = {}, title = title, level = quest.level, kind = m.kind,
                        text = (title and (title .. ": ") or "") .. (ns.ProgressText(m.text) or "an objective"),
                        details = { "Quest: " .. (title or "?"), "Objective: " .. (ns.ProgressText(m.text) or "?") },
                    }
                    goals[#goals + 1] = g
                    ns.quests.Unplaced(g, q.id, tonumber(m.key:match(":(%d+)$")), m)
                end
            end
        end
    end
    -- An unfinished objective Flow can't locate (e.g. an event): don't plan
    -- the turn-in yet, it could come too early.
    local unfinished = 0
    for _, obj in ipairs(q.objectives) do if not obj.finished then unfinished = unfinished + 1 end end
    if unfinished > #turnIn.deps then
        if #turnIn.points > 0 then cant("waits for an objective Flow can't place, so the turn-in isn't planned yet") end
        turnIn.points = {}
    end
end
-- A stop the quest data doesn't place: where you did it before (LearnedSpots),
-- else off the route with the reason: inside a dungeon, a battleground's
-- reward, or simply not known. index: the objective's; m: { text, why }.
-- Pure but for the two lookups, which the tests can pass in.
function ns.quests.Unplaced(g, questID, index, m, learned, dungeon)
    if learned == nil and ns.learnedSpots and index then learned = ns.learnedSpots.Points(questID, index) end
    if learned and #learned > 0 then
        g.points, g.area = learned, true
        table.insert(g.details, "Flow's quest data has no place for this: the arrow goes where it was done before.")
        return "learned"
    end
    if dungeon == nil then dungeon = ns.dungeons and ns.dungeons.Of and ns.dungeons.Of(questID) end
    local text = (m and m.text or ""):lower()
    if dungeon then
        g.blockedBy = "Inside " .. dungeon .. ": a dungeon, so it isn't on your route. The dungeon run (Flow menu, Dungeons) brings you there."
        g.blockedShort = "in " .. dungeon
        return "dungeon"
    elseif text:find("mark of honor", 1, true) then
        g.blockedBy = "From winning or losing battlegrounds: not a place on your route."
        g.blockedShort = "from battlegrounds"
        return "battleground"
    end
    g.blockedBy = "Flow doesn't know where: " .. tostring(m and m.why or "no spot") .. ". Your quest log says how. Flow learns the spot when you do it."
    g.blockedShort = ns.nav.NO_SPOT
    return "unknown"
end
ns.quests.QuestGoals = questGoals   -- (Party.lua, tests)

-- A class quest in your log that leads to a spell you don't have (Bear Form,
-- "Moonglade"): its stops are milestones, so the route doesn't leave them
-- for last because they're far or in another zone ("the Flow Tracker isn't
-- having me go there", 0.35.175). Pure: marks the goals of those quests.
--   steps: Q:ClassQuestSteps() ({ spell, state, quest = { id } })
local function markClassQuests(goals, steps)
    local spellOf = {}
    for _, e in ipairs(steps or {}) do
        if e.state == "inlog" and e.quest and e.quest.id then spellOf[e.quest.id] = e.spell end
    end
    if not next(spellOf) then return goals end
    for _, g in ipairs(goals) do
        local id = type(g.key) == "string" and tonumber(g.key:match("^(%d+):"))
        local spell = id and spellOf[id]
        if spell then
            g.milestone, g.classQuest = true, spell
            g.weight = math.min(g.weight or 1, 0.6)
            g.details = g.details or {}
            table.insert(g.details, 1, string.format("Your class quest: it leads to %s.", spell))
        end
    end
    return goals
end
ns.quests.MarkClassQuests = markClassQuests   -- (tests)

ns:Register("navGoal", "questie", {
    collect = function()
        local db = ns.quests.QuestieDB and ns.quests.QuestieDB()
        if not db then return nil end
        local goals, unplaced = {}, {}
        for _, q in ipairs(questLog()) do questGoals(db, q, goals, { unplaced = unplaced }) end
        ns.quests.unplaced = unplaced   -- (/flow nav why)
        if ns.quests.ClassQuestSteps then
            local ok, steps = pcall(ns.quests.ClassQuestSteps, ns.quests)
            if ok then markClassQuests(goals, steps) end
        end
        return goals
    end,
})

-- Spawn table -> map points (shared by pickups below).
local function spawnPoints(spawns)
    return (pointsFrom({ spawns }))
end

-- Quests you haven't picked up yet that are still worth doing (from the
-- missed-quests scan: zones you've quested in, doable, not done).
-- Class quests that teach a spell (Bear Form): the part of the chain you can
-- pick up now is always a stop, whatever the zone and level rules below say
-- about it (QuestData.lua Q:ClassQuestSteps). Pure: adds to `goals` (or marks
-- the stop that's there). points(spawns) -> map points.
local function addClassQuests(goals, steps, points)
    for _, e in ipairs(steps or {}) do
        local q = e.quest
        if e.state == "accept" and q and q.id then
            local key, found = "pickup:" .. q.id, nil
            for _, g in ipairs(goals) do if g.key == key then found = g end end
            local why = string.format("Your class quest: it leads to %s.", e.spell)
            if found then
                found.weight, found.classQuest = 0.7, e.spell
                table.insert(found.details, 1, why)
            else
                local who = q.starter and q.starter.name
                local pts = q.starter and q.starter.spawns and points(q.starter.spawns) or {}
                goals[#goals + 1] = {
                    key = key, weight = 0.7, level = q.level, classQuest = e.spell,
                    npcs = who and { who } or nil, kind = "accept", points = pts, title = q.name,
                    text = "Accept: " .. (q.name or "your class quest") .. " (" .. e.spell .. ")",
                    details = { why, string.format("Level %d quest from %s.", q.level or 0, who or "its giver") },
                    blockedBy = #pts == 0 and ("Flow doesn't know where " .. (who or "its giver") .. " stands") or nil,
                    blockedShort = #pts == 0 and ns.nav.NO_SPOT or nil,
                }
            end
        end
    end
    return goals
end
ns.quests.AddClassQuests = addClassQuests   -- (tests)

ns:Register("navGoal", "pickups", {
    collect = function()
        local list = ns.quests:Missed()
        -- Quest log full: picking up more is pointless.
        if ns.quests.FreeSlots and ns.quests:FreeSlots() == 0 then return nil end
        local level = UnitLevel("player")
        -- "New quests" (the route menu): the ones still worth the XP, down to
        -- 4 levels below you. "Low-level quests": the ones under that too
        -- (grey ones included). Neither ticked: nothing to pick up.
        local new, low = ns.nav:Includes("newQuests"), ns.nav:Includes("lowQuests")
        if not (new or low) then return nil end
        local floor = low and -math.huge or level - ns.nav.LOW_QUEST_BELOW
        -- And not ones above you that are hard (orange or red, 3+ levels up):
        -- they come back as you level. (A level-5 tauren was offered level-8
        -- quests and found them very hard; a level-1 one was sent 700 yd for one.)
        local ceiling = level + ns.quests.HARD_ABOVE - 1
        local goals = {}
        for _, q in ipairs(list or {}) do
            if (q.level or 0) >= floor and (q.level or 0) <= ceiling and q.starter and q.starter.spawns
                and not (ns.dungeons and ns.dungeons:Claims(q.id)) then
                local g = {
                    key = "pickup:" .. q.id, weight = 0.9, level = q.level,
                    npcs = q.starter.name and { q.starter.name } or nil,
                    kind = isDaily(q.raw) and "daily" or "accept",
                    points = spawnPoints(q.starter.spawns),
                    title = q.name,
                    text = "Accept: " .. (q.name or "quest"),
                    details = { string.format("Level %d quest from %s.", q.level or 0, q.starter.name or "?"),
                                "You haven't done it yet and it's still worth the XP." },
                }
                -- Where the giver is, whether it's an escort (they may be away
                -- with someone else), and what they want you to have first
                -- (Modules/Quests/QuestNeeds.lua).
                if ns.quests.PickupNeed then ns.quests:PickupNeed(g, q.id, q.raw, q.starter.name) end
                goals[#goals + 1] = g
            end
        end
        if ns.quests.ClassQuestSteps then
            local ok, steps = pcall(ns.quests.ClassQuestSteps, ns.quests)
            if ok then
                ns.quests.classSteps = steps   -- (/flow nav why)
                addClassQuests(goals, steps, spawnPoints)
            end
        end
        -- (Nothing worked out yet and no class quest: no answer, as before.)
        if not list and #goals == 0 then return nil end
        return goals
    end,
})

-- Errands: trainers to visit. Professions you planned but haven't learned,
-- professions that hit their cap, and your class trainer when there are
-- spells waiting. Locations from Places (learned spots + Questie).
ns:Register("navGoal", "errands", {
    collect = function()
        local goals = {}
        local _ = ns:ClassData()
        local wanted = {}
        local A = ns.api
        -- "Professions" (the route menu, /flow nav professions on|off).
        local includeProfs = ns.nav:Includes("professions")

        local out = {}
        -- The next tier of a profession you have: on the route from 25 below
        -- the cap (when the trainer, book or quest can teach it), not only
        -- once you're stuck. SkillPlan builds the stop; it skips the
        -- professions planned here so there's one "train:" stop each.
        local SP = ns.skillPlan
        local level = UnitLevel("player")
        for _, p in ipairs(includeProfs and ns:ProfessionPlan() or {}) do
            local rank = A.Skill(p.name)
            if not rank then
                for _, npc in ipairs(ns.places:TrainersFor(p.name)) do wanted[#wanted + 1] = npc end
                goals[#goals + 1] = { profession = p.name, optional = p.optional, why = "Learn " .. p.name }
            elseif SP and SP.TierGoal then
                local ok, tg = pcall(SP.TierGoal, p.name, level, p.optional)
                if ok and tg and tg.points and #tg.points > 0 then
                    tg.details = tg.details or {}
                    if p.optional then tg.details[#tg.details + 1] = "Optional, so the arrow only picks it when you're close by." end
                    out[#out + 1] = tg
                end
            end
        end
        if ns.quests.NPCsByName then ns.quests:NPCsByName(wanted) end  -- start lookup once

        for _, g in ipairs(goals) do
            local points = {}
            local names = ns.places:TrainersFor(g.profession)
            for _, npc in ipairs(names) do
                for _, pt in ipairs(ns.places:Points(npc)) do points[#points + 1] = pt end
            end
            if #points > 0 then
                out[#out + 1] = {
                    key = "train:" .. g.profession, weight = g.optional and 1.4 or 1.0, optional = g.optional, points = points,
                    npcs = names,
                    title = g.why, text = g.why .. " (" .. table.concat(names, " / ") .. ")",
                    details = { g.why .. " at " .. table.concat(names, " or ") .. ".",
                                g.optional and "Optional, so the arrow only picks it when you're close by." or nil },
                }
            end
        end

        -- Skill-ups: gathering/fishing for planned professions that are behind
        -- your level. Optional stops, so the planner only routes you there
        -- when it's on the way (or nothing else is left).
        local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local db = ns.quests.QuestieDB and ns.quests.QuestieDB()
        local toolAdded = {}
        for _, p in ipairs(includeProfs and ns:ProfessionPlan() or {}) do
            local rank, max = A.Skill(p.name)
            local target = ns.skillPlan and ns.skillPlan.Pace(p.name, level) or A.ProfessionTarget(level)
            if rank and rank + 10 < target and rank < max and not (ns.skillPlan and ns.skillPlan:Handles(p.name)) then
                for _, spot in ipairs(ns.places:SpotsFor(p.name)) do
                    local points = {}
                    for _, npc in ipairs(spot.npcs or {}) do
                        for _, pt in ipairs(ns.places:Points(npc)) do points[#points + 1] = pt end
                    end
                    for _, o in ipairs(spot.objects or {}) do
                        if db and rank >= o.skill then
                            local obj = ns.quests:QuestieGet("GetObject", o.id)
                            if obj then addSpawns(points, obj.spawns, 400, here) end
                        end
                    end
                    if #points > 0 then
                        -- No pole (pick, ...) yet: buying one comes first.
                        local tool, missing
                        if ns.skillPlan and ns.skillPlan.ToolGoal then tool, missing = ns.skillPlan:ToolGoal(p.name) end
                        if tool and not toolAdded[tool.key] then
                            toolAdded[tool.key] = true
                            tool.optional, tool.weight = true, 1.2
                            out[#out + 1] = tool
                        end
                        -- A lure too (Shiny Bauble), from the same kind of vendor.
                        local lure = ns.skillPlan and ns.skillPlan.LureGoal and ns.skillPlan:LureGoal(p.name)
                        if lure and not toolAdded[lure.key] then
                            toolAdded[lure.key] = true
                            out[#out + 1] = lure
                        end
                        local guide = ns:Get("profGuide", p.name)
                        local details = { string.format("%s is behind your level: %d now, about %d is right for level %d.",
                                p.name, rank, target, UnitLevel("player")),
                                "Optional: only planned when it's roughly on the way." }
                        if guide and guide.tip then details[#details + 1] = guide.tip end
                        out[#out + 1] = {
                            key = "skill:" .. p.name, prof = p.name, optional = true, weight = 1.5, points = points,
                            title = spot.text, text = string.format("%s (%s %d, aim for %d)", spot.text, p.name, rank, target),
                            details = details,
                            blockedBy = missing and ("needs a " .. missing) or nil,
                        }
                    end
                end
            end
        end

        -- Class trainer, when spells are waiting (appears by itself when you
        -- level up into new spells). The trainer you last used, else the
        -- known class trainers for your class (Places.lua data + Questie).
        -- Cost: what you can pay for, cheapest first. If you can't afford any
        -- of it, the goal carries `cost` and the route skips it until you can
        -- (Nav.lua remembers skipped stops and brings them back by itself).
        local waiting, costs, unknownCost = 0, {}, false
        local ok, items = pcall(ns:Get("advisor", "trainer").check)
        -- Only spells you can train now count (0.35.142): a spell waiting on
        -- another (Demoralizing Roar on Bear Form, from a class quest) and a
        -- class quest's own spell aren't a reason to go to the trainer.
        local later, laterFor = {}, {}
        if ok and items then
            for _, it in ipairs(items) do
                if it.waitsFor then
                    later[it.waitsFor] = later[it.waitsFor] or {}
                    local name = it.text:match("^(.-): after ") or it.text
                    table.insert(later[it.waitsFor], name)
                    laterFor[#laterFor + 1] = it.waitsFor
                elseif it.goalKey == "train:class" then
                    waiting = waiting + 1
                    if it.cost then costs[#costs + 1] = it.cost else unknownCost = true end
                end
            end
        end
        table.sort(costs)
        local money = GetMoney and GetMoney() or 0
        local canPay, spend = 0, 0
        for _, c in ipairs(costs) do
            if spend + c <= money then canPay, spend = canPay + 1, spend + c end
        end
        local total = 0
        for _, c in ipairs(costs) do total = total + c end
        local coin = function(c) return GetCoinTextureString and GetCoinTextureString(c) or (c .. "c") end
        if waiting > 0 then
            local _, class = UnitClass("player")
            local names = ns.db.trainer and ns.db.trainer.npc and { ns.db.trainer.npc }
                or ns.places:TrainersFor("class:" .. class)
            if ns.quests.NPCsByName then ns.quests:NPCsByName(names) end
            local points = {}
            for _, n in ipairs(names) do
                for _, pt in ipairs(ns.places:Points(n)) do points[#points + 1] = pt end
            end
            if #points > 0 then
                local text = string.format("Train %d spell(s) at your class trainer", waiting)
                if not unknownCost and canPay < waiting and canPay > 0 then
                    text = string.format("Train %d of %d spell(s) at your class trainer (money for %d)", canPay, waiting, canPay)
                end
                out[#out + 1] = {
                    -- A milestone: new ranks make every fight after it faster, so it
                    -- always makes the route and costs half as much "distance" as a
                    -- quest stop. It still fits around the quests on the way there.
                    key = "train:class", weight = 0.5, milestone = true, points = points,
                    npcs = names,
                    title = "Class training",
                    text = text,
                    -- Nothing affordable (and every cost known): the cheapest is what it takes.
                    cost = (not unknownCost and canPay == 0 and #costs > 0) and costs[1] or nil,
                    details = { "New spells or ranks are waiting: " .. table.concat(names, " / ") .. ".",
                                #costs > 0 and ("Cost: " .. coin(total) .. (unknownCost and " plus spells Flow hasn't seen priced" or "")) or nil },
                }
                local g = out[#out]
                -- The ones that wait: say so, and when a stop on the route
                -- teaches what they wait for (the Bear Form quest), train after
                -- it so one trip does it all (soft: never blocks training).
                for need, list in pairs(later) do
                    g.details[#g.details + 1] = string.format("After %s: %s.", need, table.concat(list, ", "))
                end
                local seen = {}
                for _, need in ipairs(laterFor) do
                    if not seen[need] and not need:find("^something") then   -- (a spell, not "something first")
                        seen[need] = true
                        g.needs = g.needs or {}
                        g.needs[#g.needs + 1] = { "spell:" .. need, soft = true }
                    end
                end
            end
        end
        return out
    end,
})

-- Game's own waypoints (clients that have them), used when Questie isn't installed.
ns:Register("navGoal", "native", {
    collect = function()
        if ns.quests:Source() and ns.quests:Source().label == "Questie" then return nil end
        if not (C_QuestLog and C_QuestLog.GetNextWaypoint) then return nil end
        local goals = {}
        for _, q in ipairs(questLog()) do
            local ok, map, x, y = pcall(C_QuestLog.GetNextWaypoint, q.id)
            if ok and map and x and y then
                goals[#goals + 1] = {
                    key = q.id .. ":wp", title = q.title,
                    text = (q.complete and "Turn in: " or "") .. (q.title or "quest"),
                    points = { { map = map, x = x, y = y } },
                    details = { "Quest: " .. (q.title or "?") },
                }
            end
        end
        return goals
    end,
})

-------------------------------------------------------------------------------
-- The kinds of stop you can tick in the route menu ("Route includes";
-- Nav.lua: N.Kinds, N:Includes). A stop takes the first kind that matches,
-- lowest order first. Add a kind for a new stop source the same way.
-------------------------------------------------------------------------------

local function pickup(g) return type(g.key) == "string" and g.key:find("^pickup:") ~= nil end
local function low(g, level) return (g.level or 0) < (level or 0) - ns.nav.LOW_QUEST_BELOW end

-- A quest to pick up far enough under your level is the low kind, else new.
ns:Register("routeKind", "lowQuests", { order = 30, default = false,
    label = "Low-level quests (grey ones too; shortest order)", short = "low-level quests",
    tip = "Quests to pick up that are 4 or more levels under you, grey ones too: for doing every quest in a zone. "
        .. "While this is ticked the route goes by the shortest path, since XP would always leave them for last.",
    match = function(g, level) return pickup(g) and low(g, level) end })

ns:Register("routeKind", "quests", { order = 10, default = true,
    label = "Current quests", short = "current quests",
    tip = "The quests in your log: their objectives, then their turn-ins.",
    match = function(g)
        return g.provider == "questie" or g.provider == "native"   -- (no source: a quest stop made by hand, as tests do)
            or (g.provider == nil and type(g.key) == "string" and g.key:find("^%d+:") ~= nil)
    end })

ns:Register("routeKind", "newQuests", { order = 20, default = true,
    label = "New quests", short = "new quests",
    tip = "Quests to pick up that are still worth the XP at your level (not 3 or more levels above you).",
    match = function(g, level) return pickup(g) and not low(g, level) end })

ns:Register("routeKind", "training", { order = 40, default = true,
    label = "Class trainer, weapon skills, riding", short = "training",
    tip = "Your class trainer when spells are waiting, a weapon master when a weapon in your bags would be an upgrade, and riding.",
    match = function(g) return g.key == "train:class" or g.provider == "weaponskill" or g.provider == "mount" end })

ns:Register("routeKind", "professions", { order = 50, default = true,
    label = "Professions", short = "professions",
    tip = "Profession trainers, and gathering, fishing and crafting stops when a skill is behind your level. "
        .. "On the route with everything else, or on their own faint arrow (the line below).",
    match = function(g) return g.provider == "skillplan" or (g.provider == "errands" and g.key ~= "train:class") end })

ns:Register("routeKind", "town", { order = 60, default = true,
    label = "Repair, selling, hearthstone (when needed)", short = "town errands",
    tip = "A repairer when your gear is worn, a vendor when your bags fill, an innkeeper when your hearthstone should move.",
    match = function(g) return g.provider == "repair" or g.provider == "merchant" or g.provider == "hearth" end })
