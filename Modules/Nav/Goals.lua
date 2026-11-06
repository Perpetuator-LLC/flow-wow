-- Navigation goals from your quest log.
--   finished quest      -> go to the NPC (or object) that takes it
--   kill objective      -> nearest spawn of that mob
--   collect objective   -> nearest mob/object that drops the item
--   use/click objective -> nearest spawn of that object
-- Locations come from Questie + QuestieDB (read at runtime, see QuestData.lua).
-- Without them, the game's own quest waypoint is used where the client has one.

local _, ns = ...

local MAX_POINTS = 80   -- spawns per goal

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

local function npcSpawns(db, points, id)
    local npc = call(db, "GetNPC", id)
    if npc then addSpawns(points, npc.spawns) end
    return npc and npc.name
end

local function objectSpawns(db, points, id)
    local obj = call(db, "GetObject", id)
    if obj then addSpawns(points, obj.spawns) end
    return obj and obj.name
end

ns:Register("navGoal", "questie", {
    collect = function()
        local db = ns.quests.QuestieDB and ns.quests.QuestieDB()
        if not db then return nil end
        local goals = {}
        for _, q in ipairs(questLog()) do
            local quest = call(db, "GetQuest", q.id)
            if quest then
                -- Where the quest is handed in. For unfinished quests this is a
                -- later stop that the planner puts after the objectives
                -- (deps), so it can decide "finish, then turn in on the way".
                local turnPoints, who = {}, nil
                for _, id in ipairs(quest.Finishes and quest.Finishes.NPC or {}) do
                    who = npcSpawns(db, turnPoints, id) or who
                end
                for _, id in ipairs(quest.Finishes and quest.Finishes.GameObject or {}) do
                    who = objectSpawns(db, turnPoints, id) or who
                end
                local turnIn = {
                    key = q.id .. ":done", weight = 0.8, points = turnPoints, level = quest.level,
                    title = q.title,
                    text = "Turn in: " .. (q.title or "quest"),
                    details = { (q.complete and "Quest complete. " or "After the objectives. ")
                        .. "Hand it in to " .. (who or "the quest giver") .. "." },
                    deps = {},
                }
                goals[#goals + 1] = turnIn
                if not q.complete then
                    for i, obj in ipairs(q.objectives) do
                        local od = quest.ObjectiveData and quest.ObjectiveData[i]
                        if not obj.finished and od then
                            local points, verb, what, elite = {}, nil, nil, false
                            if od.Type == "monster" then
                                what = npcSpawns(db, points, od.Id); verb = "Kill"
                                -- Elite mobs (Questie rank 1+): flagged and planned later; bring a friend.
                                local npcRaw = call(db, "GetNPC", od.Id)
                                if npcRaw and (npcRaw.rank or 0) >= 1 then elite = true end
                            elseif od.Type == "object" then
                                what = objectSpawns(db, points, od.Id); verb = "Use"
                            elseif od.Type == "item" then
                                local item = call(db, "GetItem", od.Id)
                                verb = "Collect"; what = item and item.name
                                for _, npcId in ipairs(item and item.npcDrops or {}) do
                                    npcSpawns(db, points, npcId)
                                    local npcRaw = call(db, "GetNPC", npcId)
                                    if npcRaw and (npcRaw.rank or 0) >= 1 then elite = true end
                                end
                                for _, objId in ipairs(item and item.objectDrops or {}) do objectSpawns(db, points, objId) end
                            end
                            if verb and #points > 0 then
                                table.insert(turnIn.deps, q.id .. ":" .. i)
                                goals[#goals + 1] = {
                                    key = q.id .. ":" .. i, points = points, title = q.title, level = quest.level,
                                    weight = elite and 1.6 or nil, elite = elite or nil,
                                    text = (elite and "[Elite] " or "") .. (q.title and (q.title .. ": ") or "") .. (obj.text or (verb .. " " .. (what or ""))),
                                    details = (function()
                                        local d = { "Quest: " .. (q.title or "?"), "Objective: " .. (obj.text or "?") }
                                        if elite then d[#d + 1] = "Elite: hard to solo at this level. Group up or come back stronger." end
                                        if verb == "Collect" and what then d[#d + 1] = "Drops from mobs/objects near the arrow: " .. what end
                                        return d
                                    end)(),
                                }
                            end
                        end
                    end
                    -- An unfinished objective Flow can't locate (e.g. an event):
                    -- don't plan the turn-in yet, it could come too early.
                    local unfinished = 0
                    for _, obj in ipairs(q.objectives) do if not obj.finished then unfinished = unfinished + 1 end end
                    if unfinished > #turnIn.deps then turnIn.points = {} end
                end
            end
        end
        return goals
    end,
})

-- Spawn table -> map points (shared by pickups below).
local function spawnPoints(spawns)
    local points = {}
    addSpawns(points, spawns)
    return points
end

-- Quests you haven't picked up yet that are still worth doing (from the
-- missed-quests scan: zones you've quested in, doable, not done).
ns:Register("navGoal", "pickups", {
    collect = function()
        local list = ns.quests:Missed()
        if not list then return nil end
        -- Quest log full: picking up more is pointless.
        if ns.quests.FreeSlots and ns.quests:FreeSlots() == 0 then return nil end
        local level = UnitLevel("player")
        local goals = {}
        for _, q in ipairs(list) do
            if (q.level or 0) >= level - 4 and q.starter and q.starter.spawns then
                goals[#goals + 1] = {
                    key = "pickup:" .. q.id, weight = 0.9, level = q.level,
                    points = spawnPoints(q.starter.spawns),
                    title = q.name,
                    text = "Accept: " .. (q.name or "quest"),
                    details = { string.format("Level %d quest from %s.", q.level or 0, q.starter.name or "?"),
                                "You haven't done it yet and it's still worth the XP." },
                }
            end
        end
        return goals
    end,
})

-- Errands: trainers to visit. Professions you planned but haven't learned,
-- professions that hit their cap, and your class trainer when there are
-- spells waiting. Locations from Places (learned spots + Questie).
ns:Register("navGoal", "errands", {
    collect = function()
        local goals = {}
        local d = ns:ClassData()
        local wanted = {}
        local A = ns.api
        -- "Include professions" (map panel, /flow nav professions on|off).
        local includeProfs = ns.db.nav.professions ~= false

        for _, p in ipairs(includeProfs and ns:ProfessionPlan() or {}) do
            local rank, max = A.Skill(p.name)
            local why
            if not rank then why = "Learn " .. p.name
            elseif max > 0 and rank >= max and max < 300 then why = "Train the next " .. p.name .. " tier" end
            if why then
                for _, npc in ipairs(ns.places:TrainersFor(p.name)) do wanted[#wanted + 1] = npc end
                goals[#goals + 1] = { profession = p.name, optional = p.optional, why = why }
            end
        end
        if ns.quests.NPCsByName then ns.quests:NPCsByName(wanted) end  -- start lookup once

        local out = {}
        for _, g in ipairs(goals) do
            local points = {}
            local names = ns.places:TrainersFor(g.profession)
            for _, npc in ipairs(names) do
                for _, pt in ipairs(ns.places:Points(npc)) do points[#points + 1] = pt end
            end
            if #points > 0 then
                out[#out + 1] = {
                    key = "train:" .. g.profession, weight = g.optional and 1.4 or 1.0, optional = g.optional, points = points,
                    title = g.why, text = g.why .. " (" .. table.concat(names, " / ") .. ")",
                    details = { g.why .. " at " .. table.concat(names, " or ") .. ".",
                                g.optional and "Optional, so the arrow only picks it when you're close by." or nil },
                }
            end
        end

        -- Skill-ups: gathering/fishing for planned professions that are behind
        -- your level. Optional stops, so the planner only routes you there
        -- when it's on the way (or nothing else is left).
        local target = A.ProfessionTarget(UnitLevel("player"))
        local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local db = ns.quests.QuestieDB and ns.quests.QuestieDB()
        for _, p in ipairs(includeProfs and ns:ProfessionPlan() or {}) do
            local rank, max = A.Skill(p.name)
            if rank and rank + 10 < target and rank < max then
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
                        out[#out + 1] = {
                            key = "skill:" .. p.name, optional = true, weight = 1.5, points = points,
                            title = spot.text, text = string.format("%s (%s %d, aim for %d)", spot.text, p.name, rank, target),
                            details = { string.format("%s is behind your level: %d now, about %d is right for level %d.",
                                p.name, rank, target, UnitLevel("player")),
                                "Optional: only planned when it's roughly on the way." },
                        }
                    end
                end
            end
        end

        -- Class trainer, when spells are waiting (appears by itself when you
        -- level up into new spells). The trainer you last used, else the
        -- known class trainers for your class (Places.lua data + Questie).
        local waiting = 0
        local ok, items = pcall(ns:Get("advisor", "trainer").check)
        if ok and items then waiting = #items end
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
                out[#out + 1] = {
                    key = "train:class", weight = 1.0, points = points,
                    title = "Class training",
                    text = string.format("Train %d spell(s) at your class trainer", waiting),
                    details = { "New spells or ranks are waiting: " .. table.concat(names, " / ") .. "." },
                }
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
