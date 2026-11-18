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

-- The step to open for a leftover (0.35.296: "if it could show me a little
-- link to where on the map I can go and use them"): the quest that uses it
-- when you can pick that up now, else the part of its chain in your log
-- (what you finish first). Pure: from where the chain stands.
--   now: "accept" | "inlog"; firstId: the quest to do now
function L.KeyFor(now, firstId)
    if not firstId then return nil end
    if now == "accept" then return "pickup:" .. firstId end
    if now == "inlog" then return firstId .. ":done" end
    return nil
end
function L.StepKey(itemId)
    local ok, related = pcall(L.Related, itemId)
    for _, q in ipairs(ok and related or {}) do
        if not q.done then
            local key = L.KeyFor(q.now, q.firstId)
            if key then return key end
        end
    end
    return nil
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
                text = L.ImproveText(it), goalKey = L.StepKey(it.id) }
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

-- Pure: when the quest opens ("; it comes after Echeyakee, in your log").
-- q.now: where its chain stands ("accept": you can pick it up; "inlog": an
-- earlier part is in your log), q.first: that earlier quest's name.
function L.AfterText(q)
    if q.now == "accept" and q.first and q.first ~= q.name then return "; first pick up \"" .. q.first .. "\"" end
    if q.now == "accept" then return "; you can pick it up now" end
    if q.now == "inlog" and q.first then return "; it comes after \"" .. q.first .. "\", in your log" end
    return ""
end

-- Pure: what to do with a leftover. related: { { name, level, done } } the
-- quests the quest data ties the item to (none known: {}); price: copper a
-- vendor pays (0: won't buy).
function L.Advice(related, price)
    local open
    for _, q in ipairs(related or {}) do
        if not q.done and (not open or (q.level or 99) < (open.level or 99)) then open = q end
    end
    if open then
        return "keep", string.format("no quest in your log uses it, but one you haven't done does: %s%s%s",
            tostring(open.name), open.level and string.format(" (level %d)", open.level) or "", L.AfterText(open))
    end
    -- No quest known for it at all: Flow doesn't know enough to say sell or
    -- destroy (0.35.270: it said "destroy" of Sunscale Feathers, which a quest
    -- you get next uses). Kept, and it says to read the item first.
    if #(related or {}) == 0 then
        return "keep", "no quest in your log uses it, and Flow knows no quest for it: read its tooltip before you let it go"
    end
    local why = "left over from a quest you've done"
    if (price or 0) > 0 then return "sell", why .. ": sell it" end
    return "destroy", why .. ", and vendors won't take it: destroy it for the slot"
end

-- The quests the quest data ties an item to.
-- The quest data's own list for an item is often empty, so Flow also looks
-- through every quest for the item (as something it gives you, needs or has
-- as an objective): a few hundred quests a frame, once per item, kept for
-- the session. L.scan[itemId] = { [questId] = true } when done.
local needsAt, needsIds, needsTexts = -100, nil, nil   -- (L.LogNeeds, below)
L.SCAN_CHUNK = 250
L.scan, L.scanning = {}, nil
function L.StartScan(itemId)
    if L.scan[itemId] or (L.scanning and L.scanning.want[itemId]) then return end
    local Q = ns.quests
    local src = Q and Q.Source and Q:Source()
    if not (src and src.allIds) then L.scan[itemId] = {} return end
    if L.scanning then L.scanning.want[itemId] = {} return end
    local ok, ids = pcall(src.allIds)
    if not ok or type(ids) ~= "table" then L.scan[itemId] = {} return end
    L.scanning = { ids = ids, i = 1, want = { [itemId] = {} } }
    local function step()
        local sc = L.scanning
        if not sc then return end
        local last = math.min(#sc.ids, sc.i + L.SCAN_CHUNK - 1)
        for k = sc.i, last do
            local qid = sc.ids[k]
            local uses = L.AddQuest({}, Q:QuestieGet("GetQuest", qid))
            for want, found in pairs(sc.want) do
                if uses[want] then found[qid] = true end
            end
        end
        sc.i = last + 1
        if sc.i <= #sc.ids then C_Timer.After(0, step) return end
        for want, found in pairs(sc.want) do L.scan[want] = found end
        L.scanning = nil
        needsAt = -100
        if ns.disposition and ns.disposition.Invalidate then ns.disposition:Invalidate() end
    end
    C_Timer.After(0, step)
end
-- Pure: one list of quest ids from the quest data's own and the scan's.
function L.MergeIds(own, scanned)
    local seen, out = {}, {}
    for _, qid in pairs(type(own) == "table" and own or {}) do
        if type(qid) == "number" and not seen[qid] then seen[qid] = true; out[#out + 1] = qid end
    end
    for qid in pairs(scanned or {}) do
        if not seen[qid] then seen[qid] = true; out[#out + 1] = qid end
    end
    table.sort(out)
    return out
end

function L.Related(itemId)
    local Q = ns.quests
    local out = {}
    local item = Q and Q.QuestieGet and Q:QuestieGet("GetItem", itemId)
    if not L.scan[itemId] then pcall(L.StartScan, itemId) end
    local ids = L.MergeIds(item and item.relatedQuests, L.scan[itemId])
    for _, qid in pairs(ids) do
        if type(qid) == "number" then
            local raw = Q:QuestieGet("GetQuest", qid)
            local entry = { id = qid, name = raw and raw.name or ("quest " .. qid), level = raw and tonumber(raw.level) or nil,
                            done = Q.IsCompleted and Q:IsCompleted(qid) and true or false }
            if not entry.done and Q.ChainNow then
                local okC, state, first = pcall(Q.ChainNow, Q, qid)
                if okC then
                    entry.now, entry.first = state, type(first) == "table" and first.name or nil
                    entry.firstId = type(first) == "table" and first.id or nil
                end
            end
            out[#out + 1] = entry
        end
    end
    return out
end

-- What your quest log uses (item ids, and its objective texts and titles):
-- read at most every few seconds, the bag rules ask for every slot.
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
    local related = L.Related(id)
    if #related == 0 and not L.scan[id] then
        return "keep", "no quest in your log uses it; Flow is looking through the quest data for one"
    end
    return L.Advice(related, price)
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
