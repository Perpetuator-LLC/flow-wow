-------------------------------------------------------------------------------
-- Flow - Quests/QuestGivers.lua
-- The people a quest sends you round to, each as a step (0.35.389).
--
-- "There's a bunch of little sub-quests when I'm doing Traditions of the
-- Bluff: a bundle of herbs from Nida, cedar twigs from Nada, sinew thread
-- from Mahu, flint and tinder from Nal. It would have been really nice if
-- those were all objectives instead of just 'go to this area' ... figure out
-- an algorithm to do it in a general way."
--
-- What the quest data has for such a quest: no place for the objective
-- itself ("Incense created"), a list of things it needs first (its source
-- items) that nothing drops, and, apart from the objectives, several spots
-- marked for the quest as a whole, each a person with a name. Flow used to
-- fold those spots into one step that pointed at the nearest. Now:
--   1. each marked person is a step of its own, at that person;
--   2. a person is matched with the thing they hand over where the data
--      allows: their mark's own words name the item, or the quest's text
--      says "<item> from <their name>". Then the step reads "Get Bundle of
--      Herbs from Nida" and is done once you carry it;
--   3. a person no item can be matched to is "Talk to <name>", done once
--      you've talked to them (the game says who you're talking to);
--   4. the objective itself comes after them.
-- It applies to any quest with two or more marked people and an objective
-- the data can't place. /flow questdata <number> shows what the data has.
-------------------------------------------------------------------------------

local _, ns = ...
local QG = {}
ns.questGivers = QG

-- Pure: the people marked for a quest as a whole: { { id, name, spawns, desc } },
-- in a steady order. quest: as the quest data gives it.
function QG.Entries(quest)
    local out = {}
    local special = type(quest) == "table" and quest.SpecialObjectives or nil
    for _, so in pairs(type(special) == "table" and special or {}) do
        for id, entry in pairs(type(so) == "table" and type(so.spawnList) == "table" and so.spawnList or {}) do
            if type(entry) == "table" and type(entry.Spawns) == "table" and next(entry.Spawns) then
                out[#out + 1] = { id = entry.Id or id, name = entry.Name, spawns = entry.Spawns, desc = so.Description or so.Text }
            end
        end
    end
    table.sort(out, function(a, b) return tostring(a.name or a.id) < tostring(b.name or b.id) end)
    return out
end

-- Pure: the quest's own words, as one lower-case string.
function QG.Text(quest)
    local parts = {}
    for _, field in ipairs({ "objectivesText", "Description" }) do
        local v = type(quest) == "table" and quest[field] or nil
        if type(v) == "string" then parts[#parts + 1] = v
        elseif type(v) == "table" then
            for _, line in ipairs(v) do if type(line) == "string" then parts[#parts + 1] = line end end
        end
    end
    return table.concat(parts, " "):lower()
end

-- Pure: the needed item this person hands over, or nil.
--   items: { { id, name } }; text: QG.Text(quest)
function QG.ItemOf(entry, items, text)
    local desc = type(entry.desc) == "string" and entry.desc:lower() or nil
    local first = type(entry.name) == "string" and entry.name:lower():match("^(%S+)") or nil
    for _, it in ipairs(items or {}) do
        local name = type(it.name) == "string" and it.name:lower() or nil
        if name then
            if desc and desc:find(name, 1, true) then return it end
            if text and first and text:find(name .. " from " .. first, 1, true) then return it end
        end
    end
    return nil
end

-- Pure: the steps still to do: { { entry, item, text, why } }.
--   carried(id) -> you have that item; talked(name) -> you've talked to them
function QG.Steps(entries, items, text, carried, talked)
    local out = {}
    if #(entries or {}) < 2 then return out end      -- (one spot: the single step there already says it)
    for _, e in ipairs(entries) do
        local item = QG.ItemOf(e, items, text)
        local who = tostring(e.name or "them")
        if item then
            if not carried(item.id) then
                out[#out + 1] = { entry = e, item = item, text = string.format("Get %s from %s", tostring(item.name), who),
                    why = string.format("%s hands over %s, which this quest needs: talk to them. Done once it's in your bags.", who, tostring(item.name)) }
            end
        elseif not (e.name and talked(e.name)) then
            out[#out + 1] = { entry = e, text = (type(e.desc) == "string" and e.desc ~= "" and e.desc) or ("Talk to " .. who),
                why = string.format("The quest data marks %s for this quest: talk to them. Done once you have.", who) }
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- In the game
-------------------------------------------------------------------------------
QG.names = {}   -- [npc name] = { [quest] = true }: who Flow is waiting for you to talk to

local function talkedTo(questID, name)
    local t = ns.db and ns.db.quests and ns.db.quests.giverTalked
    return t ~= nil and t[questID] ~= nil and t[questID][name] == true
end

-- The steps for a quest in your log (Goals.lua asks as it builds the route).
function QG.StepsFor(quest, questID)
    local entries = QG.Entries(quest)
    if #entries < 2 then return {} end
    local Q = ns.quests
    local db = Q.QuestieDB and Q.QuestieDB()
    local items = {}
    for _, id in ipairs(Q.SourceItems and Q.SourceItems(quest) or {}) do
        local it = db and Q.QuestieGet and Q:QuestieGet("GetItem", id)
        items[#items + 1] = { id = id, name = it and it.name }
    end
    for _, e in ipairs(entries) do
        if e.name then
            QG.names[e.name] = QG.names[e.name] or {}
            QG.names[e.name][questID] = true
        end
    end
    return QG.Steps(entries, items, QG.Text(quest),
        function(id) return (ns.api.Count and ns.api.Count(id) or 0) > 0 end,
        function(name) return talkedTo(questID, name) end)
end

-- You're talking to someone: if a quest was waiting on that, it's noted.
function QG.Talked(name)
    local quests = name and QG.names[name]
    if not (quests and ns.db and ns.db.quests) then return false end
    ns.db.quests.giverTalked = ns.db.quests.giverTalked or {}
    local new = false
    for questID in pairs(quests) do
        local t = ns.db.quests.giverTalked[questID] or {}
        ns.db.quests.giverTalked[questID] = t
        if not t[name] then t[name] = true; new = true end
    end
    if new and ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("talked to " .. tostring(name)) end
    return new
end
local function onTalk()
    local name = UnitName and UnitName("npc")
    name = ns.api and ns.api.Safe and ns.api.Safe(name) or name
    if type(name) == "string" then pcall(QG.Talked, name) end
end
for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "MERCHANT_SHOW" }) do
    ns:On(event, onTalk)
end
ns:OnLoad(function(saved)
    saved.quests = saved.quests or {}
    saved.quests.giverTalked = saved.quests.giverTalked or {}
end)
ns:PerCharacter("quests.giverTalked")
