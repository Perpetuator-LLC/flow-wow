-- The quest's own item on its Flow Tracker row, clickable.
--
-- "Flow Tracker should show the quest item if there is one and make it
-- clickable to use" (0.35.185). A quest that hands you something to use (a
-- totem for a well, dust for a stone) gets that item's icon at the right end
-- of its row in the Flow Tracker: click it and the item is used.
--
-- Using an item is a protected action, so the icon is a secure button, and
-- the game's rules for those shape this file:
--   * It is NOT a child of the tracker and not anchored to it (that would make
--     the tracker itself protected, and the tracker moves and resizes in a
--     fight). It belongs to the screen and is laid over the row's right end.
--   * It can only be placed, shown, hidden or given another item out of a
--     fight. In a fight it stays as it was at the pull; when the fight ends
--     it's brought up to date.
-- Which item: the game's own "quest item" for the quest where the client has
-- that, else the item the quest data says the quest gives or needs (read from
-- Questie as it runs), when it's in your bags and has a use.

local _, ns = ...
local QI = {}
ns.questItems = QI

QI.MAX = 8      -- buttons (the tracker has no more rows than this with an item at once)
QI.KEEP = 2     -- seconds a quest's answer is kept (the tracker refreshes often)

-- Pure: the quest a step belongs to, from its key ("758:1", "6002:done",
-- "6002:wp"). Not a pickup, not a party member's.
function QI.QuestOf(key)
    return type(key) == "string" and tonumber(key:match("^(%d+):")) or nil
end

-- Pure: the item a quest has you use.
--   special: the game's own quest item for it (an item ID), or nil
--   quest: the quest data ({ sourceItemId, requiredSourceItems }), or nil
--   has(id) -> how many are in your bags; usable(id) -> does using it do something
function QI.ItemOf(special, quest, has, usable)
    if special and has(special) > 0 then return special end
    local ids = {}
    if type(quest) == "table" then
        if type(quest.sourceItemId) == "number" and quest.sourceItemId > 0 then ids[#ids + 1] = quest.sourceItemId end
        if type(quest.requiredSourceItems) == "table" then
            for _, id in ipairs(quest.requiredSourceItems) do
                if type(id) == "number" and id > 0 then ids[#ids + 1] = id end
            end
        end
    end
    for _, id in ipairs(ids) do
        if has(id) > 0 and usable(id) then return id end
    end
    return nil
end

-- Pure: which buttons go where. rows: the tracker's rows in order, each
-- { key = step key or nil, shown = bool }; itemFor(questID) -> item ID or nil.
-- -> { { row = i, item = id, quest = questID } }, one per row with an item,
-- at most `max`; an item already on an earlier row isn't shown twice.
function QI.Plan(rows, itemFor, max)
    local out, seen = {}, {}
    for i, r in ipairs(rows) do
        local quest = r.shown and QI.QuestOf(r.key) or nil
        local item = quest and itemFor(quest) or nil
        if item and not seen[item] and #out < (max or QI.MAX) then
            seen[item] = true
            out[#out + 1] = { row = i, item = item, quest = quest }
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- The game side
-------------------------------------------------------------------------------

local function logIndex(questID)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local ok, i = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
        if ok and type(i) == "number" and i > 0 then return i end
    end
    if GetQuestLogIndexByID then
        local ok, i = pcall(GetQuestLogIndexByID, questID)
        if ok and type(i) == "number" and i > 0 then return i end
    end
    return nil
end

local function itemSpell(id)
    local get = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not get then return nil end
    local ok, name = pcall(get, id)
    return ok and name or nil
end

-- The game's own quest item for a quest in your log (an item ID), or nil.
function QI.Special(questID)
    local get = GetQuestLogSpecialItemInfo
    local i = get and logIndex(questID)
    if not i then return nil end
    local ok, link = pcall(get, i)
    return ok and link and tonumber(tostring(link):match("item:(%d+)")) or nil
end

local cache = {}
function QI.ItemFor(questID)
    local now = GetTime()
    local c = cache[questID]
    if c and now - c.at < QI.KEEP then return c.item or nil end
    local quest
    local Q = ns.quests
    if Q and Q.QuestieGet then
        local ok, q = pcall(Q.QuestieGet, Q, "GetQuest", questID)
        quest = ok and q or nil
    end
    local item = QI.ItemOf(QI.Special(questID), quest, ns.api.Count, function(id) return itemSpell(id) ~= nil end)
    cache[questID] = { at = now, item = item or false }
    return item
end
function QI._Forget() cache = {} end   -- (tests)

-- Pure: the plan with the travel step on its step's row. rows: { key,
-- shown }; act: N.travelAct ({ kind = "spell", spell } or { kind = "hearth" });
-- key: the step it takes you to. A row that already has a quest item keeps
-- that (one button a row).
function QI.WithTravel(plan, rows, act, key)
    if not (act and key) then return plan end
    for i, r in ipairs(rows or {}) do
        if r.key == key and r.shown then
            for _, w in ipairs(plan) do if w.row == i then return plan end end
            local out = {}
            for _, w in ipairs(plan) do out[#out + 1] = w end
            out[#out + 1] = { row = i, travel = act }
            return out
        end
    end
    return plan
end
-- Pure: what a button does for a plan entry: the attribute's kind ("item"
-- or "spell"), its value, and the icon (nil: the item's own).
QI.HEARTHSTONE = 6948
function QI.ButtonFor(w, spellIcon, itemIconOf)
    spellIcon = spellIcon or function(spell) return select(2, ns.api.SpellInfo(spell)) end
    itemIconOf = itemIconOf or function(id) return ns.api.ItemIcon and ns.api.ItemIcon(id) or nil end
    if w.travel then
        if w.travel.kind == "spell" then return "spell", w.travel.spell, spellIcon(w.travel.spell) end
        return "item", "item:" .. QI.HEARTHSTONE, itemIconOf(QI.HEARTHSTONE)
    end
    return "item", "item:" .. w.item, itemIconOf(w.item)
end

local buttons = {}
local shown = {}       -- what's on screen now (a QI.Plan list)
local wanted, rowsOf   -- what the tracker last asked for, and its row frames

local function build(i)
    local b = CreateFrame("Button", "FlowQuestItem" .. i, UIParent, "SecureActionButtonTemplate")
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(50)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.3)
    b:SetScript("OnEnter", function(self)
        if self.travel then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(self.travel.text, 1, 0.82, 0)
            GameTooltip:AddLine("It takes you to this step. Click to cast it (or press your Flow key).", 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.item) end
        GameTooltip:AddLine("Click to use it.", 1, 0.65, 0)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    buttons[i] = b
    return b
end

-- Lays the buttons over their rows. Out of a fight only (the caller checks).
local function apply(plan)
    local ui = UIParent:GetEffectiveScale()
    for i, w in ipairs(plan) do
        local row = rowsOf and rowsOf[w.row]
        local b = buttons[i] or build(i)
        local right, bottom, h = row and row:GetRight(), row and row:GetBottom(), row and row:GetHeight()
        if right and bottom and h and h > 0 then
            local s = row:GetEffectiveScale() / ui
            b:ClearAllPoints()
            b:SetSize(h * s, h * s)
            b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (right - h) * s, bottom * s)
            local kind, what, icon = QI.ButtonFor(w)
            b:SetAttribute("spell", nil)
            b:SetAttribute("item", nil)
            b:SetAttribute("type", kind)
            b:SetAttribute(kind, what)
            if kind == "spell" then b:SetAttribute("unit", "player") else b:SetAttribute("unit", nil) end
            b.item, b.travel = w.item, w.travel
            b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            b:Show()
        else
            b:Hide()
        end
    end
    for i = #plan + 1, #buttons do buttons[i]:Hide() end
    shown = plan
end

-- Called by the Flow Tracker each time it fills its rows.
--   rows: its row frames (each .key = its step's key, or nil), in order
--   visible: the tracker's body is open and on screen
-- -> { [row index] = item ID } for the rows that carry an item (the tracker
--    leaves room at their right end)
function QI:Layout(rows, visible)
    rowsOf = rows
    local list = {}
    for i, r in ipairs(rows) do
        list[i] = { key = r.key, shown = visible and r:IsVisible() and true or false }
    end
    wanted = QI.Plan(list, QI.ItemFor, QI.MAX)
    -- And the teleport or hearthstone that takes you to a step, on that
    -- step's row (Nav/TravelIcon.lua), the same way.
    local N = ns.nav
    if N and N.TravelOnTracker and N.TravelOnTracker() then
        wanted = QI.WithTravel(wanted, list, N.travelAct, N.travelKey)
    end
    local byRow = {}
    for _, w in ipairs(wanted) do byRow[w.row] = w.item or true end
    if InCombatLockdown() then
        QI.pending = true   -- (brought up to date when the fight ends)
        -- What's on screen is what you can click: the rows keep room for those.
        local now = {}
        for _, w in ipairs(shown) do now[w.row] = w.item or true end
        return now
    end
    QI.pending = nil
    -- (Placed again every time: the tracker may have moved.)
    apply(wanted)
    return byRow
end

ns:On("PLAYER_REGEN_ENABLED", function()
    if QI.pending and wanted and rowsOf then
        QI.pending = nil
        pcall(apply, wanted)
        if ns.routeTracker and ns.routeTracker.Refresh then pcall(ns.routeTracker.Refresh, ns.routeTracker) end
    end
end)
-- Your bags changed (the quest handed you its item, or you used it up).
ns:On("BAG_UPDATE_DELAYED", function() cache = {} end)

-- /flow questitems: what Flow found, for the diagnostics.
function QI.Lines()
    local out = { string.format("the game's own quest item call: %s; buttons on screen: %d%s",
        GetQuestLogSpecialItemInfo and "yes" or "no (Flow goes by the quest data)", #shown,
        QI.pending and " (waiting for the fight to end)" or "") }
    local Q = ns.quests
    for id in pairs(Q and Q.LogIds and Q:LogIds() or {}) do
        local item = QI.ItemFor(id)
        if item then
            out[#out + 1] = string.format("quest %d: use item %d (%d in your bags, special %s)", id, item, ns.api.Count(item),
                tostring(QI.Special(id)))
        end
    end
    for _, w in ipairs(shown) do
        out[#out + 1] = string.format("row %d: item %d (quest %d)", w.row, w.item, w.quest or 0)
    end
    return out
end
ns.commands.questitems = function()
    ns:Print("quest items on the Flow Tracker:")
    for _, l in ipairs(QI.Lines()) do print("  " .. l) end
end
