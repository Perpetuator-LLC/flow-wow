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

-- Pure: has the game marked a quest failed? isFailed: what C_QuestLog.IsFailed
-- gave; isComplete: the older quest log's sixth value (-1 = failed).
-- (0.35.418: Flow read only "complete or not". With the escort of Free From
-- the Hold gone, the route went on pointing at the end of the escort.)
function ns.quests.Failed(isFailed, isComplete)
    return isFailed == true or isComplete == -1
end
-- The game's word on one quest log line, by either way of asking.
local function readFailed(index, questID)
    local ok, failed = pcall(function()
        local a = C_QuestLog and C_QuestLog.IsFailed and C_QuestLog.IsFailed(questID)
        local b = GetQuestLogTitle and select(6, GetQuestLogTitle(index))
        return ns.quests.Failed(a, b)
    end)
    return ok and failed == true
end
-- Your quest log: { { id, title, complete, failed, objectives = { {text, finished} } } }
local function questLog()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local q = { id = info.questID, title = info.title, objectives = {} }
                q.complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false
                q.failed = readFailed(i, info.questID)
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
                local q = { id = id, title = title, complete = isComplete == 1, failed = ns.quests.Failed(nil, isComplete), objectives = {} }
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
    -- Who gives the quest, and where: for a failed quest, and for an escort.
    local startSpawns, starter = {}, nil
    local starts = type(quest.Starts) == "table" and quest.Starts or {}
    for _, id in ipairs(starts.NPC or {}) do starter = npcSpawns(db, startSpawns, id) or starter end
    for _, id in ipairs(starts.GameObject or {}) do starter = objectSpawns(db, startSpawns, id) or starter end
    -- Failed (the escort died or vanished, the time ran out): nothing in it
    -- can be done or handed in any more. One step instead of its objectives
    -- and its hand-in: abandon it, and take it again where it's given.
    if q.failed and not opts.who then
        local key = prefix .. q.id .. ":failed"
        if not skip(key) then
            local pts = pointsFrom(startSpawns)
            goals[#goals + 1] = {
                key = key, points = pts, npcs = starter and { starter } or nil, title = title, level = quest.level,
                kind = "use", failed = true,
                text = ns.quests.FailedText(title),
                details = ns.quests.FailedLines(title, starter),
                blockedBy = #pts == 0 and ("Flow doesn't know where " .. (starter or "its giver") .. " stands. Abandon it in your quest log and take it again.") or nil,
                blockedShort = #pts == 0 and ns.nav.NO_SPOT or nil,
            }
        end
        return
    end
    opts.starter = starter   -- (the escort note below)
    -- Where the quest is handed in. For unfinished quests this is a later
    -- step that the planner puts after the objectives (deps), so it can
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
    -- Finished, and its items sit in your bags: the hand-in frees those slots
    -- (QuestBags.lua). With nearly full bags it stays on the route and comes early.
    if q.complete and not opts.who and ns.questBags then pcall(ns.questBags.MarkTurnIn, turnIn, q.id) end
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
    local inBank = {}   -- objectives whose things lie in your bank: { id, name, n }
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
        -- (What it collects lies in your bank: you have it. No step to go and
        -- collect it again, 0.35.351; Flow Banker brings it out when the
        -- quest can go on.)
        -- (0.35.400: the counts from the objective's own words where the game gives
        -- no numbers: without them one in the bank counted as enough of five, and
        -- the step said "take 1" of each.)
        local haveN, needN = ns.quests.Counts(obj)
        local banked = od and od.Type == "item" and not opts.who and ns.questBags and ns.questBags.InBank(od.Id, needN, haveN)
        -- (0.35.398: and a step to go and take it out, so the hand-in can be planned.)
        if banked and not obj.finished then
            local it = call(db, "GetItem", od.Id)
            inBank[#inBank + 1] = { id = od.Id, name = it and it.name or "what it asks for",
                n = ns.quests.FromBank(needN, haveN) }
        end
        if not obj.finished and od and not skillObj and not banked then
            local spawns, verb, what, elite = {}, nil, nil, false
            local targets = {}  -- mob / NPC names (the arrow finds their nameplates in the area)
            local givers = {}   -- who hands the thing over, when nothing drops it
            local mobs = {}     -- { name, min, max, rate }: their levels, and how often they drop it (0.35.232)
            if od.Type == "monster" then
                local npcRaw
                what, npcRaw = npcSpawns(db, spawns, od.Id); verb = "Kill"
                if what then targets[#targets + 1] = what end
                if what then mobs[#mobs + 1] = { name = what, min = npcRaw and npcRaw.minLevel, max = npcRaw and npcRaw.maxLevel } end
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
                    if dropper then
                        mobs[#mobs + 1] = { name = dropper, min = npcRaw and npcRaw.minLevel, max = npcRaw and npcRaw.maxLevel,
                                            rate = ns.quests.DropRate(db, od.Id, npcId) }
                    end
                    if npcRaw and (npcRaw.rank or 0) >= 1 then anyElite = true else anyNormal = true end
                end
                elite = anyElite and not anyNormal
                for _, objId in ipairs(item and item.objectDrops or {}) do objectSpawns(db, spawns, objId) end
                -- Nothing drops it and nothing holds it, but the quest data lists who
                -- has it (0.35.387: The Warsong Reports' three "updates" are handed
                -- over by the scout, the runner and the outrider, whom the data files
                -- as the items' vendors): that's where to go.
                if #spawns == 0 then
                    for _, npcId in ipairs(ns.quests.Givers(item)) do
                        local giver = npcSpawns(db, spawns, npcId)
                        if giver then targets[#targets + 1] = giver; givers[#givers + 1] = giver end
                    end
                end
            end
            local points, known = pointsFrom(spawns)
            -- A quest 3+ levels above you (orange or red): its mobs hit hard.
            -- Planned later, like elites, so the easier ones come first.
            local myLevel = opts.level or UnitLevel("player")
            local hard = (quest.level or 0) - myLevel >= ns.quests.HardAbove()
            -- Solo, these stay off the route (listed, locked) until you can do
            -- them; in a group, or with holding turned off, they're routed.
            --   hard: until you're within 2 levels (at 18, a level-21 quest's
            --         mobs kill you over and over); not held when every mob it
            --         needs is known and within 2 levels of you.
            --   elite: until you're ELITE_SOLO_ABOVE levels above its mobs (or
            --         the quest, when their levels aren't known).
            local held
            if (hard or elite) and #points > 0 and ns.quests.HoldHard() then
                local mobMax
                for _, m in ipairs(mobs) do
                    if not m.max then mobMax = nil; break end
                    mobMax = math.max(mobMax or 0, m.max)
                end
                local grouped = opts.grouped
                if grouped == nil then grouped = opts.who ~= nil or (IsInGroup ~= nil and IsInGroup()) end
                if not grouped then
                    if hard and not (mobMax and mobMax - myLevel < ns.quests.HardAbove()) then
                        held = (quest.level or 0) - ns.quests.HardAbove() + 1
                    end
                    if elite then
                        local soloAt = (mobMax or quest.level or 0) + ns.quests.ELITE_SOLO_ABOVE
                        if myLevel < soloAt then held = math.max(held or 0, soloAt) end
                    end
                end
            end
            if verb and #points > 0 then
                table.insert(turnIn.deps, key)
                -- A party member's objective has no text of its own: "Kill X 3/10".
                local objText = obj.text or string.format("%s %s%s", verb, what or "",
                    obj.need and string.format(" %d/%d", obj.have or 0, obj.need) or "")
                if not skip(key) then
                    goals[#goals + 1] = {
                        key = key, points = points, known = known, title = title, level = quest.level,
                        weight = (elite or hard) and 1.6 or (ns.quests.IsSpread(#points) and ns.quests.SPREAD_WEIGHT) or nil,
                        spread = ns.quests.IsSpread(#points) or nil,
                        elite = elite or nil, hard = hard or nil, helping = opts.who,
                        npcs = #targets > 0 and targets or nil, area = true, target = what,
                        -- (How many are still to get: the planner sizes its visits by it.)
                        left = obj.need and math.max(0, obj.need - (obj.have or 0)) or nil,
                        -- (The item it collects: a step to get a thing that lies in your bank isn't one, QuestBags.lua.)
                        item = (od.Type == "item") and od.Id or nil,
                        kind = isDaily(quest) and "daily" or (verb == "Kill" and "kill") or (verb == "Collect" and "collect") or "use",
                        text = whose .. (elite and "[Elite] " or "") .. (title and (title .. ": ") or "") .. ns.ProgressText(objText),
                        details = (function()
                            local d = { "Quest: " .. (title or "?"), "Objective: " .. (ns.ProgressText(objText) or "?") }
                            if opts.who then d[#d + 1] = opts.who .. "'s quest: you're helping them (kill credit is shared in a party)." end
                            if #givers > 0 then d[#d + 1] = "You get it from " .. ns.quests.AndList(givers) .. ": talk to them." end
                            if held then d[#d + 1] = string.format("%s Held off the route until level %d, or until you're in a group (setting: Hold hard and elite quests while solo).",
                                    elite and "Elite: hard to solo at this level." or string.format("Level %d: above your limit for quest levels (Flow menu, Quest levels), so its mobs hit hard.", quest.level), held)
                            elseif elite then d[#d + 1] = "Elite: hard to solo at this level. Group up or come back stronger." end
                            if hard and not held then d[#d + 1] = string.format("Level %d: above your limit for quest levels (Flow menu, Quest levels), so its mobs hit hard. Flow plans it after the easier ones; bring a friend or come back a level or two later.", quest.level) end
                            for _, l in ipairs(ns.quests.DropLines(verb == "Collect" and what or nil, ns.quests.MobLines(mobs, verb == "Collect"))) do d[#d + 1] = l end
                            -- (Seen for sale at the auction house: it can be bought, QuestBuy.lua.)
                            if od.Type == "item" and ns.questBuy and not opts.who then
                                local okB, line = pcall(ns.questBuy.LineFor, od.Id, what, ns.questBuy.LeftOf(q.id, i))
                                if okB and line then d[#d + 1] = line end
                            end
                            if ns.quests.IsSpread(#points) then d[#d + 1] = "Found all over the area: Flow plans the exact spots near it first, and you get these on the way." end
                            return d
                        end)(),
                        blockedBy = held and string.format("%s: back on the route at level %d (or in a group)",
                            elite and "elite, hard to solo" or string.format("level %d quest", quest.level), held) or nil,
                        blockedShort = held and ("at level " .. held) or nil,
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
    -- What the quest asks for is in your bank (0.35.398). "I have a bunch of
    -- quest items in my bank ... it keeps telling me to come out here to do
    -- these quests, and I don't need to. Those should have been taken out of
    -- the bank and turned in." The steps to collect them were already left out
    -- (0.35.351), but nothing took their place, so the hand-in counted as
    -- waiting on an objective Flow couldn't place and was never planned. Now
    -- there's a step at a banker to take them out, and the hand-in follows it.
    -- And what the quest needs FIRST, when that lies in your bank (0.35.401:
    -- Stalk With The Earthmother wants a Raw Brilliant Smallfish to fillet, and
    -- 32 of them were in the bank): fetched at the same step.
    local bankKey
    if not opts.who then
        for _, itemId in ipairs(ns.quests.SourceItems(quest)) do
            -- (0.35.416: one for each objective still to do, less what you carry. The
            -- Angry Scytheclaws uses a Sunscale Feather at each of three nests: with
            -- one in your bags and nine in the bank, Flow asked for none, or for one.)
            local carried = ns.api.Count and ns.api.Count(itemId) or 0
            local banked = ns.db.bank and ns.db.bank.items and ns.db.bank.items[itemId] or 0
            local take = ns.quests.SourceFromBank(ns.quests.Unfinished(q.objectives), carried, banked)
            if take > 0 then
                local it = call(db, "GetItem", itemId)
                inBank[#inBank + 1] = { id = itemId, name = it and it.name or "what it needs first", n = take, source = true }
            end
        end
    end
    if #inBank > 0 and not opts.who then
        local key = prefix .. q.id .. ":bank"
        bankKey = key
        local pts, names = {}, {}
        if ns.skillPlan and ns.skillPlan.BankerPoints then
            local okB, p, nm = pcall(ns.skillPlan.BankerPoints)
            if okB then pts, names = p or {}, nm or {} end
        end
        local fetch, words = {}, {}
        for _, b in ipairs(inBank) do
            fetch[b.id] = b.n
            words[#words + 1] = string.format("%d %s", b.n, b.name)
            -- (A thing needed first isn't an objective: the hand-in doesn't count it.)
            if not b.source then table.insert(turnIn.deps, key) end
        end
        if not skip(key) then
            goals[#goals + 1] = {
                key = key, points = pts, npcs = #names > 0 and names or nil, title = title, level = quest.level, kind = "merchant",
                fetch = fetch,
                text = (title and (title .. ": ") or "") .. "take " .. ns.quests.AndList(words) .. " out of your bank",
                details = { "Quest: " .. (title or "?"),
                    "You already have what this quest asks for: it's in your bank, where the quest log doesn't count it. Take it out and the quest is ready to hand in.",
                    "Flow Banker's To sell list has a Take out button for it while the bank is open." },
                blockedBy = #pts == 0 and "What it asks for is in your bank, and Flow knows no banker to send you to yet (talk to one once)." or nil,
                blockedShort = #pts == 0 and "in your bank" or nil,
            }
        end
    end
    -- Something the quest needs you to have before the rest can be done
    -- (0.35.281). "Trial of the Lake asks me to find a Shrine Bauble in the
    -- lake and take it to the shrine, and the arrow just takes me to the
    -- shrine: it should take me to the lake first." The quest data lists such
    -- an item apart from the objectives (its "required source items"), and
    -- Flow planned only the objectives. Now, while you don't carry it, getting
    -- it is a step of its own where it's found, and the quest's other steps
    -- wait for it.
    local noSpotNeeds = {}   -- what it needs first that Questie can't place either (names)
    if not opts.who then
        local needKeys = {}
        for _, itemId in ipairs(ns.quests.SourceItems(quest)) do
            if ns.quests.StillToGet(itemId, ns.api.Count and ns.api.Count(itemId) or 0)
                and not (ns.questBags and ns.questBags.InBank(itemId)) then
                local item = call(db, "GetItem", itemId)
                local spawns, targets = {}, {}
                for _, npcId in ipairs(item and item.npcDrops or {}) do
                    local dropper = npcSpawns(db, spawns, npcId)
                    if dropper then targets[#targets + 1] = dropper end
                end
                for _, objId in ipairs(item and item.objectDrops or {}) do objectSpawns(db, spawns, objId) end
                local points, known = pointsFrom(spawns)
                local key = prefix .. q.id .. ":item:" .. itemId
                local name = item and item.name or "what it needs"
                if #points > 0 and not skip(key) then
                    goals[#goals + 1] = {
                        key = key, points = points, known = known, title = title, level = quest.level, kind = "collect", area = true,
                        npcs = #targets > 0 and targets or nil, target = item and item.name, item = itemId,
                        text = (title and (title .. ": ") or "") .. "Get " .. name,
                        details = { "Quest: " .. (title or "?"),
                            "You need " .. name .. " before the rest of this quest can be done: it's found here. The quest's other steps come after." },
                    }
                    needKeys[#needKeys + 1] = key
                elseif #points == 0 then
                    -- (It comes out of something you carry: say so. 0.35.387: Warsong
                    -- Report is in the Bundle of Reports the quest gave you.)
                    local holder = ns.quests.HeldIn(item, function(id) return ns.api.Count and ns.api.Count(id) or 0 end,
                        function(id) local it = call(db, "GetItem", id) return it and it.name end)
                    if holder then name = string.format("%s (open %s in your bags)", name, holder) end
                    cant(string.format("it needs %s first, and Questie has no spot for where that's found", name))
                    noSpotNeeds[#noSpotNeeds + 1] = name
                end
            end
        end
        if #needKeys > 0 then
            local mine = prefix .. q.id .. ":"
            for _, other in ipairs(goals) do
                if type(other.key) == "string" and other.key:sub(1, #mine) == mine and not other.key:find(":item:", 1, true) then
                    other.deps = other.deps or {}
                    for _, k in ipairs(needKeys) do table.insert(other.deps, k) end
                end
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
        -- No marker of the game's: the spots the quest data marks for the quest
        -- as a whole, apart from its objectives (0.35.358: The Warsong Reports'
        -- three "updates" are handed over by people the quest data lists that
        -- way, and Flow said "doesn't know where").
        local extra = {}
        if not wp then
            local okE, tables = pcall(ns.quests.ExtraSpawns, quest)
            if okE and #tables > 0 then extra = (pointsFrom(tables)) end
        end
        -- Several people marked for the quest: a step at each, named for who
        -- they are and what they hand over (0.35.389, QuestGivers.lua:
        -- Traditions of the Bluff was one step, "go to this area").
        local giverKeys = {}
        if not wp and ns.questGivers then
            local okG, steps = pcall(ns.questGivers.StepsFor, quest, q.id)
            if not okG then cant("its people couldn't be read: " .. tostring(steps)) end
            for _, s in ipairs(okG and steps or {}) do
                local pts = pointsFrom({ s.entry.spawns })
                local gkey = prefix .. q.id .. ":giver:" .. tostring(s.entry.id or s.entry.name)
                if #pts > 0 then
                    giverKeys[#giverKeys + 1] = gkey
                    if not skip(gkey) then
                        goals[#goals + 1] = {
                            key = gkey, points = pts, title = title, level = quest.level, kind = "use",
                            npcs = s.entry.name and { s.entry.name } or nil, item = s.item and s.item.id or nil,
                            text = (title and (title .. ": ") or "") .. s.text,
                            details = { "Quest: " .. (title or "?"), s.why },
                        }
                    end
                end
            end
            for _, k in ipairs(giverKeys) do table.insert(turnIn.deps, k) end
        end
        -- The quest's own words name whoever takes it ("fillet it in front of
        -- Boarton Shadetotem"): the objective is done there (0.35.401).
        local atFinisher = false
        -- (0.35.409: only where the words say it's done "in front of" them, and
        -- never for a dungeon's quest. Nearly every quest's words name who takes
        -- it, "bring the gems to Nara Wildmane", so naming alone sent Leaders of
        -- the Fang's four gems to Nara in Thunder Bluff instead of Wailing Caverns.)
        if not wp and #extra == 0 and who and #turnIn.points > 0 and ns.questGivers
            and not (ns.dungeons and ns.dungeons.Of and ns.dungeons.Of(q.id))
            and ns.quests.DoneAt(ns.questGivers.Text(quest), who) then
            extra, atFinisher = turnIn.points, true
        end
        if wp or #extra > 0 then
            local key = prefix .. q.id .. ":wp"
            for _ = 1, #missing do table.insert(turnIn.deps, key) end
            if not skip(key) then
                local d = { "Quest: " .. (title or "?") }
                for _, m in ipairs(missing) do d[#d + 1] = "Objective: " .. (ns.ProgressText(m.text) or "?") end
                d[#d + 1] = wp and "Flow's quest data has no place for this: the arrow goes to the game's own marker for the quest."
                    or (atFinisher and ("The quest says it's done by " .. tostring(who) .. ": the arrow goes there.")
                        or "The quest data doesn't say where each objective is done, but it marks these spots for the quest: the arrow goes to the nearest.")
                if #giverKeys > 0 then d[#d + 1] = "It comes after the people this quest sends you to." end
                local first = {}
                for _, k in ipairs(giverKeys) do first[#first + 1] = k end
                if bankKey then first[#first + 1] = bankKey; d[#d + 1] = "First take what it needs out of your bank." end
                goals[#goals + 1] = {
                    key = key, points = wp and { wp } or extra, title = title, level = quest.level, kind = "use", area = true,
                    deps = #first > 0 and first or nil,
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
                    m.needs = #noSpotNeeds > 0 and noSpotNeeds or nil
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
-- A step whose mobs or items are spread all over an area (many spots) is
-- planned a little later than a step at one exact place nearby: "you have
-- me focus on ones that are all over the area first; wouldn't it be better
-- to go to the specific ones, and on the way I'll probably get the others?"
-- (0.35.233) Its legs cost more, so the planner puts it where you're
-- passing through anyway.
ns.quests.SPREAD_SPOTS = 20     -- this many spots or more: spread out
ns.quests.SPREAD_WEIGHT = 1.3
function ns.quests.IsSpread(spots) return (spots or 0) >= ns.quests.SPREAD_SPOTS end

-- How often a mob drops an item, in percent, or nil (the quest data's own
-- figure: QuestieDB.GetItemDroprate -> { rate, source }).
function ns.quests.DropRate(db, itemId, npcId)
    local fn = db and db.GetItemDroprate
    if type(fn) ~= "function" then return nil end
    local ok, r = pcall(fn, itemId, npcId)
    if ok and type(r) == "table" and tonumber(r[1]) then return tonumber(r[1]) end
    return nil
end
-- Pure: the lines for a step's mobs: each one's level, and for a drop how
-- often it gives the item, best first ("can we show the percent drops per
-- level ... what levels are in what areas for my objective", 0.35.232).
--   mobs: { { name, min, max, rate } }; drops: it's an item they drop.
ns.quests.MOB_LINES = 6
-- Pure: the "drops from" heading and its lines, the heading only when there
-- are lines under it (0.35.412: Counterattack!'s banner comes from a warlord
-- the quest data doesn't list, and the step read "Piece of Krom'zar's Banner
-- drops from (level): chance" with nothing after it).
--   what: the item's name (nil: not something you collect); lines: ns.quests.MobLines
function ns.quests.DropLines(what, lines)
    local out = {}
    if what and #(lines or {}) > 0 then out[1] = what .. " drops from (level): chance" end
    for _, l in ipairs(lines or {}) do out[#out + 1] = l end
    return out
end
function ns.quests.MobLines(mobs, drops, max)
    local list, seen = {}, {}
    for _, m in ipairs(mobs or {}) do
        if m.name and not seen[m.name] then
            seen[m.name] = true
            list[#list + 1] = m
        end
    end
    table.sort(list, function(a, b)
        if (a.rate or -1) ~= (b.rate or -1) then return (a.rate or -1) > (b.rate or -1) end
        if (a.min or 0) ~= (b.min or 0) then return (a.min or 0) < (b.min or 0) end
        return a.name < b.name
    end)
    local out = {}
    max = max or ns.quests.MOB_LINES
    for i, m in ipairs(list) do
        if i > max then
            out[#out + 1] = string.format("- and %d more", #list - max)
            break
        end
        -- One short line a mob, as a bullet, so nothing wraps (0.35.295: "see how
        -- the tooltip wraps text and is hard to read?"): "- Name (16-17): 100%".
        local level = ""
        if m.min and m.min > 0 then
            level = (m.max and m.max > m.min) and string.format(" (%d-%d)", m.min, m.max) or string.format(" (%d)", m.min)
        end
        local rate = ""
        if drops and m.rate then
            rate = m.rate >= 10 and string.format(": %d%%", math.floor(m.rate + 0.5)) or string.format(": %.1f%%", m.rate)
        elseif drops then
            rate = ": chance not known"
        end
        if level ~= "" or rate ~= "" then out[#out + 1] = "- " .. m.name .. level .. rate end
    end
    return out
end

-- A step the quest data doesn't place: where you did it before (LearnedSpots),
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
    -- It needs something first that nobody can place either (0.35.309: the
    -- row said "no known spot" for Stalk With The Earthmother, which waits on
    -- a Raw Brilliant Smallfish): the row names what to get.
    local needs = m and m.needs
    if needs and #needs > 0 then
        g.blockedBy = string.format("Flow doesn't know where: first you need %s, and Questie has no spot for %s. Your quest log says how. Flow learns the spot when you do it.",
            ns.quests.AndList(needs), #needs == 1 and "where that's found" or "where those are found")
        g.blockedShort = #needs == 1 and ("needs " .. needs[1]) or string.format("needs %d things first", #needs)
        table.insert(g.details, "First you need: " .. ns.quests.AndList(needs) .. ".")
        return "unknown"
    end
    g.blockedBy = "Flow doesn't know where: " .. tostring(m and m.why or "no spot") .. ". Your quest log says how. Flow learns the spot when you do it."
    g.blockedShort = ns.nav.NO_SPOT
    return "unknown"
end

-- Pure: how many of a quest's objectives are still to do.
function ns.quests.Unfinished(objectives)
    local n = 0
    for _, o in ipairs(objectives or {}) do if not o.finished then n = n + 1 end end
    return n
end
-- Pure: how many of a thing a quest needs first to take out of the bank: one
-- for each objective still to do (it may be used up at each), less what you
-- carry, and no more than the bank holds.
function ns.quests.SourceFromBank(unfinished, carried, banked)
    local want = math.max(1, tonumber(unfinished) or 1) - (tonumber(carried) or 0)
    return math.max(0, math.min(want, tonumber(banked) or 0))
end
-- Pure: do a quest's words (lower case) say the thing is done at this person
-- ("... fillet it in front of Boarton Shadetotem")? Being named isn't enough:
-- the one you hand a quest in to is named in almost every quest.
ns.quests.AT_WORDS = { "in front of ", "in the presence of ", "while standing before ", "while standing next to " }
function ns.quests.DoneAt(words, name)
    if type(words) ~= "string" or type(name) ~= "string" or name == "" then return false end
    local who = name:lower()
    for _, lead in ipairs(ns.quests.AT_WORDS) do
        if words:find(lead .. who, 1, true) then return true end
    end
    return false
end
-- Pure: do a quest's words (lower case) name this person?
function ns.quests.Names(words, name)
    if type(words) ~= "string" or type(name) ~= "string" or name == "" then return false end
    return words:find(name:lower(), 1, true) ~= nil
end
-- Pure: an objective's have and need: its numbers, else read from its words ("0/5 Savannah Lion Tusk").
function ns.quests.Counts(obj)
    if type(obj) ~= "table" then return nil, nil end
    local have, need = tonumber(obj.have), tonumber(obj.need)
    if not need and type(obj.text) == "string" then
        local h, n = obj.text:match("(%d+)%s*/%s*(%d+)")
        have, need = have or tonumber(h), tonumber(n)
    end
    return have, need
end
-- Pure: how many of a thing to take out of the bank for an objective (what's
-- still missing from your bags; at least one).
function ns.quests.FromBank(need, have)
    return math.max(1, (tonumber(need) or 1) - (tonumber(have) or 0))
end
-- Pure: who has an item that nothing drops: the NPCs the quest data lists as
-- selling it ({ ids }; none: {}).
function ns.quests.Givers(item)
    local out = {}
    for _, id in ipairs(type(item) == "table" and type(item.vendors) == "table" and item.vendors or {}) do
        if type(id) == "number" then out[#out + 1] = id end
    end
    return out
end
-- Pure: the name of something you carry that this item comes out of, or nil.
--   count(id) -> how many you carry; nameOf(id) -> its name
function ns.quests.HeldIn(item, count, nameOf)
    for _, id in ipairs(type(item) == "table" and type(item.itemDrops) == "table" and item.itemDrops or {}) do
        if type(id) == "number" and (count(id) or 0) > 0 then return nameOf(id) or "what holds it" end
    end
    return nil
end

-- Pure: { "A", "B", "C" } -> "A, B and C".
function ns.quests.AndList(list)
    local n = #(list or {})
    if n == 0 then return "" end
    if n == 1 then return tostring(list[1]) end
    return table.concat(list, ", ", 1, n - 1) .. " and " .. tostring(list[n])
end

-- Pure: the step text for a quest the game has marked failed.
function ns.quests.FailedText(title)
    return "Failed: abandon " .. (title or "this quest") .. " and take it again"
end
-- Pure: its tooltip lines.
function ns.quests.FailedLines(title, giver)
    return {
        "Quest: " .. (title or "?"),
        "The game has marked it failed: nothing in it can be finished or handed in now.",
        "Abandon it in your quest log (Flow doesn't abandon quests for you), then take it again from "
            .. (giver or "whoever gave it") .. ": the arrow goes there.",
    }
end
-- Pure: is one of a quest's objectives still to do an escort ("Escort Gilthares
-- Firebough back to Ratchet")? Read from the objective's words, so English only.
function ns.quests.IsEscort(objectives)
    for _, o in ipairs(objectives or {}) do
        if not o.finished and type(o.text) == "string" and o.text:find("^%s*Escort ") then return true end
    end
    return false
end
-- Pure: what an escort's step says about losing them.
function ns.quests.EscortLine(giver)
    return "An escort: it starts with " .. (giver or "the quest giver")
        .. ". If they're gone (dead, or vanished), abandon the quest and take it again from them."
end
-- An escort's steps say what to do when the escort is lost: the game doesn't
-- always mark the quest failed, and the step itself points at the end.
do
    local build = questGoals
    questGoals = function(db, q, goals, opts)
        opts = opts or {}
        local from = #goals + 1
        build(db, q, goals, opts)   -- (sets opts.starter)
        if q.failed or q.complete or not ns.quests.IsEscort(q.objectives) then return end
        for i = from, #goals do
            local g = goals[i]
            if g.kind ~= "turnin" and g.kind ~= "daily" and type(g.details) == "table" then
                g.escort = true
                g.details[#g.details + 1] = ns.quests.EscortLine(opts.starter)
            end
        end
    end
end
ns.quests.QuestGoals = questGoals   -- (Party.lua, tests)

-- A class quest in your log that leads to a spell you don't have (Bear Form,
-- "Moonglade"): its steps are milestones, so the route doesn't leave them
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
ns.quests.SpawnPoints = spawnPoints   -- (Focus.lua: the next quest of a custom route's line)

-- Pure: the spawn tables the quest data marks for a quest as a whole (its
-- "special objectives": who to talk to, where to use a thing), apart from
-- its numbered objectives. quest: the quest as the data gives it.
--   -> { spawns, ... }, each { [zone] = { { x, y }, ... } }
function ns.quests.ExtraSpawns(quest)
    local out = {}
    local special = type(quest) == "table" and quest.SpecialObjectives or nil
    for _, so in pairs(type(special) == "table" and special or {}) do
        for _, entry in pairs(type(so) == "table" and type(so.spawnList) == "table" and so.spawnList or {}) do
            if type(entry) == "table" and type(entry.Spawns) == "table" and next(entry.Spawns) then out[#out + 1] = entry.Spawns end
        end
    end
    return out
end

-- Quests you haven't picked up yet that are still worth doing (from the
-- missed-quests scan: zones you've quested in, doable, not done).
-- Class quests that teach a spell (Bear Form): the part of the chain you can
-- pick up now is always a step, whatever the zone and level rules below say
-- about it (QuestData.lua Q:ClassQuestSteps). Pure: adds to `goals` (or marks
-- the step that's there). points(spawns) -> map points.
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
        -- (0.35.419: an NPC's repeatable hand-ins have a tick of their own, so
        -- they can be on your route with both of those off, or off with them on.)
        local reps = ns.nav:Includes("repeatables")
        if not (new or low or reps) then return nil end
        local floor = low and -math.huge or level - ns.nav.LOW_QUEST_BELOW
        -- And not ones above you that are hard (orange or red, 3+ levels up):
        -- they come back as you level. (A level-5 tauren was offered level-8
        -- quests and found them very hard; a level-1 one was sent 700 yd for one.)
        local ceiling = level + ns.quests.HardAbove() - 1
        local goals = {}
        -- Repeatable hand-ins aren't quests to pick up: an NPC's are one optional
        -- step (0.35.411, Repeatables.lua: Mangletooth's six were six steps).
        local RP = ns.repeatables
        local ordinary, repeats = list or {}, {}
        if RP then
            local okS, o, r = pcall(RP.Split, list, RP.Is, RP.Takes)
            if okS then ordinary, repeats = o, r end
        end
        for _, q in ipairs(ordinary) do
            if (new or low) and (q.level or 0) >= floor and (q.level or 0) <= ceiling and q.starter and q.starter.spawns
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
        if RP then RP.last, RP.skipped = {}, {} end
        if RP and reps then
            local role = ns:LevelingRole()
            for _, grp in ipairs(repeats) do
                local inLevel = false
                for _, q in ipairs(grp.quests) do
                    if (q.level or 0) >= floor and (q.level or 0) <= ceiling then inLevel = true end
                end
                if inLevel and grp.spawns then
                    grp.points = spawnPoints(grp.spawns)
                    local okG, step = pcall(RP.Step, grp,
                        function(id) return ns.api.Count and ns.api.Count(id) or 0 end,
                        function(id) local items = ns.db.bank and ns.db.bank.items return items and items[id] or 0 end,
                        role, function(id) return ns:Get("repeatBuff", id) end,
                        function(id) local it = ns.quests:QuestieGet("GetItem", id) return it and it.name end)
                    if okG and step and #step.points > 0 then
                        goals[#goals + 1] = step
                        RP.last[#RP.last + 1] = step
                    elseif okG then
                        RP.skipped[#RP.skipped + 1] = tostring(grp.who)
                    end
                end
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
        -- once you're stuck. SkillPlan builds the step; it skips the
        -- professions planned here so there's one "train:" step each.
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
        -- your level. Optional steps, so the planner only routes you there
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
        -- (Nav.lua remembers skipped steps and brings them back by itself).
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
        local coin = ns.Money
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
                    -- quest step. It still fits around the quests on the way there.
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
                -- The ones that wait: say so, and when a step on the route
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
-- The kinds of step you can tick in the route menu ("Route includes";
-- Nav.lua: N.Kinds, N:Includes). A step takes the first kind that matches,
-- lowest order first. Add a kind for a new step source the same way.
-------------------------------------------------------------------------------

local function pickup(g) return type(g.key) == "string" and g.key:find("^pickup:") ~= nil end
local function low(g, level) return (g.level or 0) < (level or 0) - ns.nav.LOW_QUEST_BELOW end

-- Battleground quests (0.35.357). "In the Route includes dropdown we should
-- add battlegrounds as one of the checkboxes. That should remove all the
-- battleground quests that are being planned into the routes if it's
-- disabled." They sat among the ordinary quests: the ones in your log as
-- steps Flow can't place ("from battlegrounds"), the ones to pick up as trips
-- to a battlemaster. Now they're a kind of their own, off until you tick it.
--   A quest is one when the quest data files it under a battleground or
--   under "Battlegrounds", or when the step itself asks for a Mark of Honor.
ns.quests.BG_ZONES = { [2597] = "Alterac Valley", [3277] = "Warsong Gulch", [3358] = "Arathi Basin" }
ns.quests.BG_SORT = -25   -- the quest data's "Battlegrounds" heading
-- Pure: raw: the quest's data ({ zoneOrSort }); text: a step's words.
function ns.quests.IsBattleground(raw, text)
    local z = type(raw) == "table" and tonumber(raw.zoneOrSort) or nil
    if z and (ns.quests.BG_ZONES[z] or z == ns.quests.BG_SORT) then return true end
    return type(text) == "string" and text:lower():find("mark of honor", 1, true) ~= nil
end
local bgMemo = {}
local function battleground(g)
    if type(g) ~= "table" or type(g.key) ~= "string" then return false end
    if g.blockedShort == "from battlegrounds" then return true end
    local id = tonumber(g.key:match("^pickup:(%d+)$") or g.key:match("^(%d+):"))
    if not id then return false end
    local known = bgMemo[id]
    if known == nil then
        local raw = ns.quests.QuestieGet and ns.quests:QuestieGet("GetQuest", id) or nil
        known = ns.quests.IsBattleground(raw, nil)
        if raw then bgMemo[id] = known end   -- (quest data not in yet: asked again)
    end
    return known or ns.quests.IsBattleground(nil, g.text)
end
ns.quests.GoalIsBattleground = battleground

-- A quest to pick up far enough under your level is the low kind, else new.
ns:Register("routeKind", "lowQuests", { order = 30, default = false, custom = "lines",
    label = "Low-level quests (grey ones too; shortest order)", short = "low-level quests",
    tip = "Quests to pick up that are 4 or more levels under you, grey ones too: for doing every quest in a zone. "
        .. "While this is ticked the route goes by the shortest path, since XP would always leave them for last.",
    match = function(g, level) return pickup(g) and low(g, level) and not battleground(g) end })

-- (After the others in the menu; the quest kinds above leave its steps to it.)
ns:Register("routeKind", "battlegrounds", { order = 68, default = false, custom = "lines",
    label = "Battlegrounds (their quests)", short = "battlegrounds",
    tip = "Quests done in a battleground or handed in for its marks (Warsong Gulch, Arathi Basin, Alterac Valley): the ones in your log, and the ones to pick up. "
        .. "Off: they're left out of your route and its lists. On: hover one for the XP it gives at your level.",
    match = function(g) return battleground(g) end })

ns:Register("routeKind", "quests", { order = 10, default = true, custom = "lines",
    label = "Current quests", short = "current quests",
    tip = "The quests in your log: their objectives, then their turn-ins.",
    match = function(g)
        if battleground(g) then return false end
        return g.provider == "questie" or g.provider == "native"   -- (no source: a quest step made by hand, as tests do)
            or (g.provider == nil and type(g.key) == "string" and g.key:find("^%d+:") ~= nil)
    end })

ns:Register("routeKind", "newQuests", { order = 20, default = true, custom = "lines",
    label = "New quests", short = "new quests",
    tip = "Quests to pick up that are still worth the XP at your level (and not above your limit: Quest levels, below).",
    match = function(g, level) return pickup(g) and not low(g, level) and not battleground(g) end })

-- (0.35.419: "that recent fix for repeatable quests, perhaps we make that a
-- toggle in the Route includes?" The step of 0.35.411 belonged to no kind, so
-- nothing could turn it off.)
ns:Register("routeKind", "repeatables", { order = 25, default = true,
    label = "Repeatable hand-ins (when you carry what they take)", short = "repeatable hand-ins",
    tip = "One step at an NPC with repeatable hand-ins (Mangletooth's Blood Shard blessings), only while you carry or bank what they take and it's on your way. "
        .. "Off: they're left out of your route and its lists.",
    match = function(g) return g.repeatable == true or (type(g.key) == "string" and g.key:find("^repeat:") ~= nil) end })

ns:Register("routeKind", "training", { order = 40, default = true,
    label = "Class trainer, weapon skills, riding", short = "training",
    tip = "Your class trainer when spells are waiting, a weapon master when a weapon in your bags would be an upgrade, and riding.",
    match = function(g) return g.key == "train:class" or g.provider == "weaponskill" or g.provider == "mount" end })

ns:Register("routeKind", "professions", { order = 50, default = true, custom = false,
    label = "Professions", short = "professions",
    tip = "Profession trainers, and gathering, fishing and crafting stops when a skill is behind your level. "
        .. "On the route with everything else, or on their own faint arrow (the line below).",
    match = function(g) return g.provider == "skillplan" or (g.provider == "errands" and g.key ~= "train:class") end })

ns:Register("routeKind", "town", { order = 60, default = true,
    label = "Repair, selling, hearthstone (when needed)", short = "town errands",
    tip = "A repairer when your gear is worn, a vendor when your bags fill, an innkeeper when your hearthstone should move.",
    match = function(g) return g.provider == "repair" or g.provider == "merchant" or g.provider == "hearth" end })
