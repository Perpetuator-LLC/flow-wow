-- Quest items in your bags that no quest in your log asks for.
--
-- "Are you or the improvements able to check my bags for quest items I have
-- that I don't need or are not on the quest, and flag it?" (0.35.217)
--
-- A quest item stays in your bags after its quest is dropped (and sometimes
-- after it's handed in), where it takes a slot for good: vendors won't buy
-- it. Flow lists such an item in Flow Improvements, to look at and destroy
-- yourself. Flow never destroys anything.
--
-- An item counts as wanted when a quest in your log: has it as an objective,
-- gave it to you or needs it to be done (the quest data's source items),
-- names it in an objective or its title, or has it as the quest's own
-- usable item. Items that start a quest are never flagged. With no quest
-- data loaded (no Questie) only the names can be checked, so Flow says
-- nothing rather than guess.
--
-- /flow leftovers lists them (also in the diagnostics).

local _, ns = ...
local L = {}
ns.leftovers = L

-- Pure: is this quest item wanted? item: { id, name }; ids: { [itemID] =
-- true } for what your quests use; texts: lower-case objective texts and
-- titles.
function L.Wanted(item, ids, texts)
    if not item then return true end
    if item.id and ids and ids[item.id] then return true end
    local name = type(item.name) == "string" and item.name:lower() or nil
    if name and name ~= "" then
        for _, t in ipairs(texts or {}) do
            if t:find(name, 1, true) then return true end
        end
    end
    return false
end

-- Pure: the quest items nothing wants. rows: the inventory's ({ id, name,
-- kind, count }); starts(id) -> true when the item starts a quest.
function L.Pick(rows, ids, texts, starts)
    local out = {}
    for _, r in ipairs(rows or {}) do
        if type(r.kind) == "string" and r.kind:find("^Quest") and r.id
            and not (starts and starts(r.id)) and not L.Wanted(r, ids, texts) then
            out[#out + 1] = { id = r.id, name = r.name, count = r.count or 1 }
        end
    end
    table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return out
end

-- Pure: adds what one quest uses to ids. raw: the quest data's entry.
function L.AddQuest(ids, raw)
    if type(raw) ~= "table" then return ids end
    local function add(v)
        if type(v) == "number" and v > 0 then ids[v] = true
        elseif type(v) == "table" then for _, x in pairs(v) do add(x) end end
    end
    add(raw.sourceItemId)
    add(raw.requiredSourceItems)
    for _, od in ipairs(type(raw.ObjectiveData) == "table" and raw.ObjectiveData or {}) do
        if type(od) == "table" and od.Type == "item" then add(od.Id) end
    end
    return ids
end

-- What's left over right now, and whether Flow could check at all.
function L.Now()
    local Q, D = ns.quests, ns.disposition
    if not (Q and D and D.Inventory and Q.Source and Q:Source()) then return {}, false end
    local ids, texts = {}, {}
    for id in pairs(Q:LogIds() or {}) do
        L.AddQuest(ids, Q:QuestieGet("GetQuest", id))
        if C_QuestLog and C_QuestLog.GetQuestObjectives then
            local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
            for _, o in ipairs(ok and objs or {}) do
                local text = ns.api.Safe(o.text)
                if type(text) == "string" then texts[#texts + 1] = text:lower() end
            end
        end
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local ok, title = pcall(C_QuestLog.GetTitleForQuestID, id)
            if ok and type(title) == "string" then texts[#texts + 1] = title:lower() end
        end
    end
    local ok, rows = pcall(D.Inventory, D)
    if not ok then return {}, false end
    local function starts(id)
        local item = Q:QuestieGet("GetItem", id)
        return item ~= nil and type(item.startQuest) == "number" and item.startQuest > 0
    end
    return L.Pick(rows, ids, texts, starts), true
end

ns:Register("advisor", "leftovers", {
    check = function()
        local out = {}
        local ok, list = pcall(L.Now)
        for i, it in ipairs(ok and list or {}) do
            if i > 3 then break end
            out[#out + 1] = { importance = 25, improves = { "Bag space" },
                text = string.format("%s in your bags isn't for any quest in your log: probably left over. Look at it, then destroy it for the slot.", tostring(it.name)) }
        end
        return out
    end,
})

function L.Lines()
    local list, could = L.Now()
    if not could then return { "leftover quest items: Flow needs its quest data (Questie) to check" } end
    local out = { string.format("leftover quest items: %d in your bags that no quest in your log asks for", #list) }
    for _, it in ipairs(list) do out[#out + 1] = string.format("  %d x %s [%d]", it.count, tostring(it.name), it.id) end
    return out
end
ns.commands.leftovers = function()
    for i, l in ipairs(L.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end
