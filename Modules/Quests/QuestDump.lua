-------------------------------------------------------------------------------
-- Flow - Quests/QuestDump.lua
-- What the quest data says about the quests Flow can't place (0.35.382).
--
-- "Can we do something with these quests? Something must be known ... figure
-- out how we add objectives or waypoints to complete them, not have 13
-- blocking quest objectives." Before a fix: the facts. For every quest with
-- a step Flow lists as "doesn't know where", this prints the quest's record
-- as the quest data has it (its objectives and what each is, the items it
-- needs first, the spots it marks for the quest as a whole), what each item
-- named there is said to come from, and what you carry for the quest. It's
-- in the diagnostics ("quest data") and on /flow questdata [quest number].
-- Reading only: nothing here changes the route.
-------------------------------------------------------------------------------

local _, ns = ...
local QD = {}
ns.questDump = QD

QD.MAX = 8   -- quests per dump

-- Pure: how many entries a table has (nil: 0).
function QD.Count(t)
    local n = 0
    for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
    return n
end

-- Pure: the quest numbers of the steps Flow couldn't place, in order, once each.
--   goals: { { key, blockedBy } }; questOf(key) -> number or nil
function QD.Unknown(goals, questOf, max)
    local out, seen = {}, {}
    for _, g in ipairs(goals or {}) do
        local id = type(g.blockedBy) == "string" and g.blockedBy:find("Flow doesn't know where", 1, true) and questOf(g.key) or nil
        if id and not seen[id] and #out < (max or QD.MAX) then seen[id] = true; out[#out + 1] = id end
    end
    return out
end

local function call(db, fname, id)
    local fn = db and db[fname]
    if type(fn) ~= "function" then return nil end
    local ok, r = pcall(fn, id)
    if ok and type(r) == "table" then return r end
    ok, r = pcall(fn, db, id)
    if ok and type(r) == "table" then return r end
    return nil
end

-- Pure: one value on a line, short.
function QD.Short(v, depth)
    depth = depth or 0
    if type(v) ~= "table" then return tostring(v) end
    if depth >= 2 then return "{...}" end
    local parts, n = {}, 0
    for k, x in pairs(v) do
        n = n + 1
        if n <= 8 then parts[#parts + 1] = (type(k) == "number" and "" or (tostring(k) .. "=")) .. QD.Short(x, depth + 1) end
    end
    return "{" .. table.concat(parts, ", ") .. (n > 8 and string.format(", +%d more", n - 8) or "") .. "}"
end

-- What the data says an item comes from.
local function itemLine(db, id)
    local item = call(db, "GetItem", id)
    if not item then return string.format("item %s: not in the quest data; you carry %d", tostring(id), ns.api.Count(id)) end
    return string.format("item %d %s: from %d kind(s) of mob, %d kind(s) of object, %d item(s) that hold it, %d vendor(s); class %s; you carry %d",
        id, tostring(item.name), QD.Count(item.npcDrops), QD.Count(item.objectDrops), QD.Count(item.itemDrops), QD.Count(item.vendors),
        tostring(item.class), ns.api.Count(id))
        .. (QD.Count(item.itemDrops) > 0 and ("; held by item(s) " .. QD.Short(item.itemDrops)) or "")
end

-- One quest's record, as lines.
function QD.Quest(id)
    local out = {}
    local db = ns.quests and ns.quests.QuestieDB and ns.quests.QuestieDB()
    local quest = db and call(db, "GetQuest", id)
    if not quest then return { string.format("quest %s: the quest data has no record of it", tostring(id)) } end
    out[#out + 1] = string.format("quest %d %s (level %s): %d objective(s) in the data", id, tostring(quest.name), tostring(quest.level), QD.Count(quest.ObjectiveData))
    for i, od in pairs(type(quest.ObjectiveData) == "table" and quest.ObjectiveData or {}) do
        out[#out + 1] = string.format("  objective %s: type %s, id %s, text %s", tostring(i), tostring(od.Type), tostring(od.Id), tostring(od.Text))
        if od.Type == "item" and type(od.Id) == "number" then out[#out + 1] = "    " .. itemLine(db, od.Id) end
        if od.Type == "monster" and type(od.Id) == "number" then
            local npc = call(db, "GetNPC", od.Id)
            out[#out + 1] = string.format("    npc %d %s: spawns in %d zone(s), waypoints in %d", od.Id, tostring(npc and npc.name), QD.Count(npc and npc.spawns), QD.Count(npc and npc.waypoints))
        end
    end
    for _, field in ipairs({ "requiredSourceItems", "sourceItemId", "triggerEnd", "extraObjectives", "objectives", "preQuestSingle", "preQuestGroup", "questFlags", "specialFlags" }) do
        local v = quest[field]
        if v ~= nil and not (type(v) == "table" and next(v) == nil) and v ~= 0 then out[#out + 1] = string.format("  %s: %s", field, QD.Short(v)) end
    end
    for _, itemId in ipairs(ns.quests.SourceItems and ns.quests.SourceItems(quest) or {}) do out[#out + 1] = "  needs first: " .. itemLine(db, itemId) end
    if type(quest.sourceItemId) == "number" and quest.sourceItemId > 0 then out[#out + 1] = "  given with it: " .. itemLine(db, quest.sourceItemId) end
    local nSpecial, nSpots = 0, 0
    for _, so in pairs(type(quest.SpecialObjectives) == "table" and quest.SpecialObjectives or {}) do
        nSpecial = nSpecial + 1
        for _, entry in pairs(type(so) == "table" and type(so.spawnList) == "table" and so.spawnList or {}) do
            if type(entry) == "table" and type(entry.Spawns) == "table" and next(entry.Spawns) then nSpots = nSpots + 1 end
        end
        out[#out + 1] = string.format("  special objective: type %s, id %s, %s", tostring(type(so) == "table" and so.Type), tostring(type(so) == "table" and so.Id),
            tostring(type(so) == "table" and (so.Description or so.Text)))
    end
    out[#out + 1] = string.format("  spots marked for the quest as a whole: %d special objective(s), %d with places", nSpecial, nSpots)
    -- The game's own marker and what you carry.
    local okW, wx, wy = pcall(function()
        if C_QuestLog and C_QuestLog.GetNextWaypoint then return select(2, C_QuestLog.GetNextWaypoint(id)) end
    end)
    out[#out + 1] = string.format("  the game's own marker: %s", okW and wx and string.format("%.1f, %.1f", (ns.api.Safe(wx) or 0) * 100, (ns.api.Safe(wy) or 0) * 100) or "none")
    local learned = 0
    for i = 1, 6 do
        local pts = ns.learnedSpots and ns.learnedSpots.Points and ns.learnedSpots.Points(id, i)
        if pts and #pts > 0 then learned = learned + 1 end
    end
    out[#out + 1] = string.format("  objectives Flow has learned a place for from you: %d", learned)
    return out
end

function QD.Lines(arg)
    local id = tonumber(arg)
    if id then return QD.Quest(id) end
    local N = ns.nav
    local list = QD.Unknown(N and N.blockedGoals or {}, function(key) return ns.focus and ns.focus.QuestOf(key) end)
    local out = { string.format("quests with a step Flow can't place: %d (the quest data's record of each)", #list) }
    for _, q in ipairs(list) do
        local ok, lines = pcall(QD.Quest, q)
        if ok then for _, l in ipairs(lines) do out[#out + 1] = "  " .. l end
        else out[#out + 1] = string.format("  quest %d: reading it failed: %s", q, tostring(lines)) end
    end
    return out
end

ns.commands.questdata = function(arg)
    for i, l in ipairs(QD.Lines(arg)) do if i == 1 then ns:Print(l) else print(l) end end
    print("  /flow questdata <quest number>")
end
