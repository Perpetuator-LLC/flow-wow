-- Quest data layer. Flow ships no quest database of its own (licensing:
-- see docs/ARCHITECTURE.md). It asks registered quest sources, best first:
--   questie : Questie + QuestieDB, if you have them installed (read at runtime,
--             nothing copied), full quest/NPC data for Forever's classic content
--   native  : the game's own API; always there, but only knows completed quests
--             and your quest log
--
-- Add a source:
--   ns:Register("questSource", key, { order = n, available = fn() -> bool,
--       get = fn(id) -> quest, allIds = fn() -> list, doable = fn(id) -> bool|nil })
-- quest = { id, name, level, minLevel, zoneId, starter = { name, zoneId } }

local _, ns = ...
local Q = {}
ns.quests = Q

-------------------------------------------------------------------------------
-- Native game API: completed quests and quest log (always works)
-------------------------------------------------------------------------------

local completed = {}
local inLog = {}

local function loadCompleted()
    wipe(completed)
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        for _, id in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do completed[id] = true end
    elseif GetQuestsCompleted then
        local t = GetQuestsCompleted()
        for id in pairs(t or {}) do completed[id] = true end
    end
end

local function loadLog()
    wipe(inLog)
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then inLog[info.questID] = true end
        end
    elseif GetNumQuestLogEntries then
        for i = 1, GetNumQuestLogEntries() do
            local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if not isHeader and id then inLog[id] = true end
        end
    end
end

function Q:IsCompleted(id)
    if completed[id] then return true end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(id) == true
    end
    return false
end

function Q:InLog(id) return inLog[id] == true end
function Q:LogIds() return inLog end  -- { [questID] = true }
function Q:CompletedIds() return completed end

ns:On("PLAYER_LOGIN", function() loadCompleted(); loadLog() end)
ns:On("QUEST_LOG_UPDATE", loadLog)
ns:On("QUEST_TURNED_IN", function(id) if id then completed[id] = true end end)

-------------------------------------------------------------------------------
-- Questie + QuestieDB (optional). Questie's internals aren't a stable API,
-- so every call is guarded; if anything is missing the source reports
-- itself unavailable instead of erroring.
-------------------------------------------------------------------------------

local function questieDB()
    if not QuestieLoader or not QuestieLoader.ImportModule then return nil end
    local ok, db = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    -- ImportModule makes an empty module if Questie hasn't loaded it yet.
    if ok and db and type(db.GetQuest) == "function" then return db end
end

local function questieReady()
    if Questie and Questie.API and Questie.API.isReady ~= nil then
        return Questie.API.isReady == true
    end
    return questieDB() ~= nil
end

-- Shared with navigation: the raw QuestieDB module (or nil), and Questie's
-- zone (areaId) to map (uiMapID) conversion.
Q.QuestieDB = questieDB

-- Find NPCs by name in Questie's data (e.g. profession trainers). The scan
-- runs once in the background; until it's done, returns nil.
-- Returns { [name] = { id, spawns } } for the names found.
local npcByName, npcScanState = {}, nil
function Q:NPCsByName(wanted)
    local db = questieDB()
    if not db or not db.NPCPointers then return nil end
    local missing = false
    for _, name in ipairs(wanted) do if npcByName[name] == nil then missing = true end end
    if not missing then return npcByName end
    if npcScanState == "running" then return nil end
    npcScanState = "running"
    local want = {}
    for _, name in ipairs(wanted) do want[name] = true end
    local co = coroutine.create(function()
        local n = 0
        for id in pairs(db.NPCPointers) do
            local npc = Q:QuestieGet("GetNPC", id)
            if npc and npc.name and want[npc.name] and not npcByName[npc.name] then
                npcByName[npc.name] = { id = id, spawns = npc.spawns }
            end
            n = n + 1
            if n % 300 == 0 then coroutine.yield() end
        end
        for name in pairs(want) do if npcByName[name] == nil then npcByName[name] = false end end
    end)
    local function step()
        if InCombatLockdown and InCombatLockdown() then C_Timer.After(1, step) return end
        local ok = coroutine.resume(co)
        if ok and coroutine.status(co) ~= "dead" then C_Timer.After(0, step)
        else npcScanState = "done" end
    end
    step()
    return nil
end

-- Q:QuestieGet("GetQuest" | "GetNPC" | "GetItem" | "GetObject", id) -> table or nil.
-- Questie mixes "." and ":" methods, so both call forms are tried.
function Q:QuestieGet(fname, id)
    local db = questieDB()
    local fn = db and db[fname]
    if type(fn) ~= "function" or not id then return nil end
    local ok, r = pcall(fn, id)
    if ok and type(r) == "table" then return r end
    ok, r = pcall(fn, db, id)
    if ok and type(r) == "table" then return r end
end

-- Fallback: find the map with the same name as the zone, among the zones of
-- the continent you're on. (For clients where Questie's zone table differs.)
local byName = {}
local function mapByZoneName(areaId)
    if not (C_Map and C_Map.GetAreaInfo and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
    local name = C_Map.GetAreaInfo(areaId)
    if not name then return nil end
    if byName[name] ~= nil then return byName[name] or nil end
    local map = C_Map.GetBestMapForUnit("player")
    local info = map and C_Map.GetMapInfo(map)
    -- Walk up to the continent.
    while info and info.mapType and Enum.UIMapType and info.mapType > Enum.UIMapType.Continent and info.parentMapID do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    local found = false
    if info and C_Map.GetMapChildrenInfo then
        for _, child in ipairs(C_Map.GetMapChildrenInfo(info.mapID, nil, true) or {}) do
            if child.name == name then found = child.mapID break end
        end
    end
    byName[name] = found
    return found or nil
end

function Q:UiMapForArea(areaId)
    if QuestieLoader then
        local ok, zdb = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
        if ok and zdb and type(zdb.GetUiMapIdByAreaId) == "function" then
            local ok2, map = pcall(zdb.GetUiMapIdByAreaId, zdb, areaId)
            if ok2 and map then return map end
        end
    end
    return mapByZoneName(areaId)
end

local function zoneIdOf(spawns)
    for zone in pairs(spawns or {}) do return zone end
end

ns:Register("questSource", "questie", {
    order = 10,
    label = "Questie",
    available = function() return questieDB() ~= nil and questieReady() end,
    get = function(id)
        local db = questieDB()
        local ok, q = pcall(db.GetQuest, id)
        if not ok or not q then return nil end
        local starter
        local npcs = q.Starts and q.Starts.NPC
        if npcs and npcs[1] and db.GetNPC then
            -- Questie mixes "." and ":" methods; try both forms.
            local okN, npc = pcall(db.GetNPC, npcs[1])
            if not (okN and type(npc) == "table") then okN, npc = pcall(db.GetNPC, db, npcs[1]) end
            if okN and type(npc) == "table" then
                starter = { id = npcs[1], name = npc.name, zoneId = zoneIdOf(npc.spawns), spawns = npc.spawns }
            end
        end
        return {
            id = id, name = q.name, level = q.level, minLevel = q.requiredLevel or 0,
            zoneId = (q.zoneOrSort and q.zoneOrSort > 0) and q.zoneOrSort or (starter and starter.zoneId),
            starter = starter, raw = q,
        }
    end,
    allIds = function()
        local db = questieDB()
        local ids = {}
        if db.QuestPointers then
            for id in pairs(db.QuestPointers) do ids[#ids + 1] = id end
        elseif db.GetAllQuestIds then
            local ok, list = pcall(db.GetAllQuestIds)
            if ok and list then for id in pairs(list) do ids[#ids + 1] = id end end
        end
        return ids
    end,
    -- Flow's own availability check (Questie's IsDoable doesn't work on every
    -- client), then Questie's if it answers.
    doable = function(id, q, levelSlack)
        q = q or Q:QuestieGet("GetQuest", id)
        if q and not Q:Available(q, levelSlack) then return false end
        local db = questieDB()
        if type(db.IsDoable) ~= "function" then return nil end
        local ok, r = pcall(db.IsDoable, id)
        if ok and r == false then return false end
        return true
    end,
})

-- Can you pick this quest up now? Level, race, class, and the quests that
-- must come first (all of preQuestGroup, any of preQuestSingle), and not
-- blocked by a mutually exclusive quest you've done or are on.
local band = bit and bit.band
function Q:Available(q, levelSlack)
    local level = UnitLevel("player")
    if (q.requiredLevel or 0) > level + (levelSlack or 0) then return false end
    if band then
        local _, _, raceID = UnitRace("player")
        local _, _, classID = UnitClass("player")
        if q.requiredRaces and q.requiredRaces ~= 0 and raceID
            and band(q.requiredRaces, 2 ^ (raceID - 1)) == 0 then return false end
        if q.requiredClasses and q.requiredClasses ~= 0 and classID
            and band(q.requiredClasses, 2 ^ (classID - 1)) == 0 then return false end
    end
    for _, pre in ipairs(q.preQuestGroup or {}) do
        if not completed[pre] then return false end
    end
    local single = q.preQuestSingle or {}
    if #single > 0 then
        local any = false
        for _, pre in ipairs(single) do if completed[pre] then any = true break end end
        if not any then return false end
    end
    for _, ex in ipairs(q.exclusiveTo or {}) do
        if completed[ex] or inLog[ex] then return false end
    end
    return true
end

-- Free quest log slots (the log has a limit; don't plan more pickups than fit).
function Q:FreeSlots()
    local max = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept())
        or MAX_QUESTLOG_QUESTS or 20
    local n = 0
    for _ in pairs(inLog) do n = n + 1 end
    return math.max(0, max - n), max
end

-- LibQuestDB-1.0 (MIT, also covers Forever-only quests by name/level).
-- PLACEHOLDER: wire up once we confirm its API in game.

-------------------------------------------------------------------------------
-- Picking a source
-------------------------------------------------------------------------------

function Q:Source()
    local best, bestOrder
    for _, src in ns:Each("questSource") do
        local ok, avail = pcall(src.available)
        if ok and avail and (not bestOrder or (src.order or 100) < bestOrder) then
            best, bestOrder = src, src.order or 100
        end
    end
    return best
end

function Q:ZoneName(zoneId)
    if not zoneId then return "?" end
    if C_Map and C_Map.GetAreaInfo then
        local name = C_Map.GetAreaInfo(zoneId)
        if name then return name end
    end
    return "zone " .. zoneId
end

-------------------------------------------------------------------------------
-- Missed quests: doable quests in zones you've already quested in, that you
-- haven't done and aren't on. Expensive (thousands of quests), so it's
-- computed out of combat and cached until a quest is turned in or you level.
-------------------------------------------------------------------------------

local missedCache      -- last finished result (kept while a new one is computed)
local dirty = true
local running = false
local BATCH = 150      -- quests checked per frame, so the game never freezes

-- Runs the scan in small batches across frames (pausing in combat).
local function scan(src)
    running = true
    local level = UnitLevel("player")
    local co = coroutine.create(function()
        local zones = {}
        local n = 0
        for id in pairs(completed) do
            local q = src.get(id)
            if q and q.zoneId then zones[q.zoneId] = true end
            n = n + 1
            if n % BATCH == 0 then coroutine.yield() end
        end
        local out = {}
        for i, id in ipairs(src.allIds()) do
            if not completed[id] and not inLog[id] then
                local q = src.get(id)
                if q and q.zoneId and zones[q.zoneId] and (q.minLevel or 0) <= level then
                    local doable = src.doable and src.doable(id, q.raw)
                    if doable ~= false then out[#out + 1] = q end
                end
            end
            if i % BATCH == 0 then coroutine.yield() end
        end
        table.sort(out, function(a, b) return (a.level or 0) > (b.level or 0) end)
        return out
    end)
    local function step()
        if InCombatLockdown and InCombatLockdown() then C_Timer.After(1, step) return end
        local ok, result = coroutine.resume(co)
        if not ok then
            running = false
            if ns.db.rotation.debug then ns:Print("missed quests: " .. tostring(result)) end
            return
        end
        if coroutine.status(co) == "dead" then
            missedCache, running = result, false
            if ns.advisor then pcall(ns.advisor.Refresh, ns.advisor) end
        else
            C_Timer.After(0, step)
        end
    end
    step()
end

-- Returns the last finished list (may be nil while the first scan runs) and
-- starts a fresh scan in the background if anything changed.
function Q:Missed()
    local src = self:Source()
    if not src then return nil end
    if dirty and not running then
        dirty = false
        scan(src)
    end
    return missedCache
end

function Q:MissedScanning() return running end

local function invalidate() dirty = true end
ns:On("QUEST_TURNED_IN", invalidate)
ns:On("QUEST_ACCEPTED", invalidate)
ns:On("PLAYER_LEVEL_UP", invalidate)

ns.commands.missed = function()
    local src = Q:Source()
    if not src then
        ns:Print("no quest database found. Install Questie and QuestieDB to spot missed quests.")
        return
    end
    local list = Q:Missed()
    if not list then
        ns:Print("checking your quest history in the background... try again in a few seconds.")
        return
    end
    ns:Print(string.format("%d quest(s) you skipped in zones you've quested in (source: %s):", #list, src.label))
    for i = 1, math.min(15, #list) do
        local q = list[i]
        print(string.format("  [%d] %s - %s%s", q.level or 0, q.name or ("quest " .. q.id),
            q.starter and q.starter.name or "?",
            q.starter and q.starter.zoneId and (", " .. Q:ZoneName(q.starter.zoneId)) or ""))
    end
end

-------------------------------------------------------------------------------
-- Items your quests need: for keep decisions in your bags.
--   now      : item objectives of quests in your log
--   upcoming : item objectives of quests you haven't done, can do within a
--              few levels, in zones you've quested in (or class quests)
-- Returns { [itemID] = { quest = name, level = n, inLog = bool } } (may be
-- incomplete while the background scan runs). Needs Questie for full data.
-------------------------------------------------------------------------------

local questItems, qiDirty, qiRunning = {}, true, false
local UPCOMING_LEVELS = 3

local function addItems(map, quest, id, inLog)
    for _, od in ipairs(quest.ObjectiveData or {}) do
        if od.Type == "item" and od.Id then
            local cur = map[od.Id]
            if not cur or (inLog and not cur.inLog) then
                map[od.Id] = { quest = quest.name, level = quest.level, inLog = inLog, questID = id }
            end
        end
    end
end

local function scanQuestItems()
    qiRunning = true
    local level = UnitLevel("player")
    local map = {}
    local co = coroutine.create(function()
        for id in pairs(inLog) do
            local q = Q:QuestieGet("GetQuest", id)
            if q then addItems(map, q, id, true) end
        end
        local src = Q:Source()
        if not (src and src.label == "Questie") then return end
        local zones, n = {}, 0
        for id in pairs(completed) do
            local q = src.get(id)
            if q and q.zoneId then zones[q.zoneId] = true end
            n = n + 1
            if n % 150 == 0 then coroutine.yield() end
        end
        for i, id in ipairs(src.allIds()) do
            if not completed[id] and not inLog[id] then
                local q = Q:QuestieGet("GetQuest", id)
                if q and (q.requiredLevel or 0) <= level + UPCOMING_LEVELS and q.ObjectiveData then
                    local zone = q.zoneOrSort and q.zoneOrSort > 0 and q.zoneOrSort
                    local classQuest = q.requiredClasses and q.requiredClasses ~= 0
                    if classQuest or (zone and zones[zone]) then
                        local doable = src.doable and src.doable(id, q, UPCOMING_LEVELS)
                        if doable ~= false then addItems(map, q, id, false) end
                    end
                end
            end
            if i % 150 == 0 then coroutine.yield() end
        end
    end)
    local function step()
        if InCombatLockdown and InCombatLockdown() then C_Timer.After(1, step) return end
        local ok = coroutine.resume(co)
        if ok and coroutine.status(co) ~= "dead" then
            C_Timer.After(0, step)
        else
            questItems, qiRunning = map, false
            if ns.disposition then ns.disposition:Invalidate() end
        end
    end
    step()
end

function Q:QuestItems()
    if qiDirty and not qiRunning then
        qiDirty = false
        scanQuestItems()
    end
    return questItems
end

for _, ev in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }) do
    ns:On(ev, function() qiDirty = true end)
end
