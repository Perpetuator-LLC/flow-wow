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
            out[#out + 1] = { id = r.id, name = r.name, count = r.count or 1, sell = r.sell }
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

-- Flow Improvements' line for a leftover: what the bags say, in a sentence.
function L.ImproveText(it)
    local ok, _, why = pcall(L.For, it.id, it.name, it.sell)
    if ok and why then return string.format("%s in your bags: %s.", tostring(it.name), why) end
    return string.format("%s in your bags isn't for any quest in your log: probably left over.", tostring(it.name))
end

ns:Register("advisor", "leftovers", {
    check = function()
        local out = {}
        local ok, list = pcall(L.Now)
        for i, it in ipairs(ok and list or {}) do
            if i > 3 then break end
            out[#out + 1] = { importance = 25, improves = { "Bag space" },
                text = L.ImproveText(it) }
        end
        return out
    end,
})

function L.Lines()
    local list, could = L.Now()
    if not could then return { "leftover quest items: Flow needs its quest data (Questie) to check" } end
    local out = { string.format("leftover quest items: %d in your bags that no quest in your log asks for", #list) }
    for _, it in ipairs(list) do
        local okA, what, why = pcall(L.For, it.id, it.name, it.sell)
        out[#out + 1] = string.format("  %d x %s [%d]: %s", it.count, tostring(it.name), it.id, okA and what and (what .. ": " .. tostring(why)) or "no advice")
        local okR, related = pcall(L.Related, it.id)
        for _, q in ipairs(okR and related or {}) do
            out[#out + 1] = string.format("      the quest data ties it to: %s [%d]%s, %s", tostring(q.name), q.id,
                q.level and (" level " .. q.level) or "", q.done and "done" or "not done")
        end
    end
    return out
end
ns.commands.leftovers = function()
    for i, l in ipairs(L.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end

-------------------------------------------------------------------------------
-- One answer for a leftover, in the bags and in Flow Improvements (0.35.266)
-------------------------------------------------------------------------------
-- "Flow says keep, it's a quest item, even though the improvement says I'm
-- not on the quest that needs it. Be consistent, and figure out what I
-- should do with it." The bag rule called anything of the game's Quest kind
-- "quest item: keep" without looking at your log. Both now go by the same
-- check, and by what the quest data says the item is for:
--   keep     a quest you haven't done uses it (named, so you can go get it)
--   sell     nothing left uses it and a vendor pays for it
--   destroy  nothing left uses it and vendors won't take it (Flow never
--            destroys anything: it says so and leaves it to you)

-- Pure: what to do with a leftover. related: { { name, level, done } } the
-- quests the quest data ties the item to (none known: {}); price: copper a
-- vendor pays (0: won't buy).
function L.Advice(related, price)
    local open
    for _, q in ipairs(related or {}) do
        if not q.done and (not open or (q.level or 99) < (open.level or 99)) then open = q end
    end
    if open then
        return "keep", string.format("no quest in your log uses it, but one you haven't done does: %s%s",
            tostring(open.name), open.level and string.format(" (level %d)", open.level) or "")
    end
    local why = (#(related or {}) > 0) and "left over from a quest you've done" or "no quest in your log uses it, and none Flow knows of"
    if (price or 0) > 0 then return "sell", why .. ": sell it" end
    return "destroy", why .. ", and vendors won't take it: destroy it for the slot"
end

-- The quests the quest data ties an item to.
function L.Related(itemId)
    local Q = ns.quests
    local out = {}
    local item = Q and Q.QuestieGet and Q:QuestieGet("GetItem", itemId)
    local ids = item and item.relatedQuests
    if type(ids) ~= "table" then return out end
    for _, qid in pairs(ids) do
        if type(qid) == "number" then
            local raw = Q:QuestieGet("GetQuest", qid)
            out[#out + 1] = { id = qid, name = raw and raw.name or ("quest " .. qid), level = raw and tonumber(raw.level) or nil,
                              done = Q.IsCompleted and Q:IsCompleted(qid) and true or false }
        end
    end
    return out
end

-- What your quest log uses (item ids, and its objective texts and titles):
-- read at most every few seconds, the bag rules ask for every slot.
local needsAt, needsIds, needsTexts = -100, nil, nil
function L.LogNeeds()
    if needsIds and GetTime() - needsAt < 5 then return needsIds, needsTexts end
    local Q = ns.quests
    if not (Q and Q.Source and Q:Source()) then return nil end
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
    needsAt, needsIds, needsTexts = GetTime(), ids, texts
    return ids, texts
end

-- For one item of the game's Quest kind: nil when a quest in your log uses
-- it (or Flow can't check); else what to do and why.
function L.For(id, name, price)
    local ids, texts = L.LogNeeds()
    if not ids then return nil end
    if L.Wanted({ id = id, name = name }, ids, texts) then return nil end
    local Q = ns.quests
    local item = Q:QuestieGet("GetItem", id)
    if item ~= nil and type(item.startQuest) == "number" and item.startQuest > 0 then return nil end
    return L.Advice(L.Related(id), price)
end

-- The bags' answer: before the plain "quest item: keep" (and before "vendors
-- won't buy it"), so a leftover reads the same there as in Flow Improvements.
ns:Register("disposition", "leftover", { order = 1.5, check = function(i)
    if i.classID ~= 12 or not i.id then return nil end
    local ok, what, why = pcall(L.For, i.id, i.name, i.sellPrice)
    if not ok or not what then return nil end
    if what == "sell" then return { action = "sell", reason = why } end
    return { action = "keep", reason = why }
end })
