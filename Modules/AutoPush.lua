-- Spells the game places on your bars by itself. When you learn a spell, WoW
-- drops it into an empty slot (normally on your main bar). Flow:
--   * says so in chat ("the game put Holy Strike on Action Bar 1, slot 4")
--   * remembers which bars/slots it used, and shows a small marker on each
--     bar that has received spells this way; hover it to see which ones
--   * offers to turn auto-placing off in /flow setup, where the client has
--     that setting
-- Value: no more "where did that come from?" when a button appears.

local _, ns = ...
local AP = {}
ns.autopush = AP

-- Action slot -> which bar and button it is shown on (default bar layout).
local BAR_OF_SLOT = {
    { 1, 12, "ActionButton", "Action Bar 1" },
    { 25, 36, "MultiBarRightButton", "Right Bar" },
    { 37, 48, "MultiBarLeftButton", "Right Bar 2" },
    { 49, 60, "MultiBarBottomRightButton", "Bottom Right Bar" },
    { 61, 72, "MultiBarBottomLeftButton", "Bottom Left Bar" },
}

local function where(slot)
    for _, b in ipairs(BAR_OF_SLOT) do
        if slot >= b[1] and slot <= b[2] then return b[3], b[4], slot - b[1] + 1 end
    end
    return nil, "action slot " .. slot, slot
end

local markers = {}

local function markerFor(prefix)
    local first = _G[prefix .. "1"]
    if not first then return nil end
    if markers[prefix] then return markers[prefix] end
    local m = CreateFrame("Frame", nil, first)
    m:SetSize(14, 14)
    m:SetPoint("BOTTOMRIGHT", first, "TOPLEFT", 2, -2)
    m:SetFrameLevel(first:GetFrameLevel() + 20)
    m.icon = m:CreateTexture(nil, "OVERLAY")
    m.icon:SetAllPoints()
    m.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    m:EnableMouse(true)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("The game auto-places new spells on this bar")
        for _, e in ipairs(self.entries or {}) do
            GameTooltip:AddLine(string.format("%s  (slot %d, %s)", e.spell, e.pos, e.when), 1, 1, 1)
        end
        GameTooltip:AddLine("Turn it off in /flow setup if your client allows it.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    markers[prefix] = m
    return m
end

function AP:Refresh()
    local byBar = {}
    for _, e in ipairs(ns.db.autopush.seen) do
        local prefix = where(e.slot)
        if prefix then
            byBar[prefix] = byBar[prefix] or {}
            local _, _, pos = where(e.slot)
            table.insert(byBar[prefix], { spell = e.spell, pos = pos, when = e.when })
        end
    end
    for prefix, m in pairs(markers) do if not byBar[prefix] then m:Hide() end end
    for prefix, entries in pairs(byBar) do
        local m = markerFor(prefix)
        if m then m.entries = entries; m:Show() end
    end
end

ns:OnLoad(function(saved)
    saved.autopush = saved.autopush or {}
    saved.autopush.seen = saved.autopush.seen or {}
end)

-- (spellID, slotIndex, slotPos) on clients that have this event.
ns:On("SPELL_PUSHED_TO_ACTIONBAR", function(spellID, slot)
    local name = ns.api.SpellInfo(spellID) or ("spell " .. tostring(spellID))
    if not slot then return end
    local seen = ns.db.autopush.seen
    seen[#seen + 1] = { spell = name, slot = slot, when = date("%b %d") }
    while #seen > 40 do table.remove(seen, 1) end
    local _, barName, pos = where(slot)
    ns:Print(string.format("the game put %s on %s, slot %d (hover the book icon on that bar for the list)", name, barName, pos))
    AP:Refresh()
end)

ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, function() pcall(AP.Refresh, AP) end) end)

ns.commands.autoplace = function(arg)
    if (arg or ""):lower() == "forget" then
        wipe(ns.db.autopush.seen); AP:Refresh(); ns:Print("forgot auto-placed spells")
        return
    end
    local seen = ns.db.autopush.seen
    ns:Print(#seen == 0 and "no auto-placed spells seen yet" or "spells the game placed on your bars:")
    for _, e in ipairs(seen) do
        local _, barName, pos = where(e.slot)
        print(string.format("  %s -> %s slot %d (%s)", e.spell, barName, pos, e.when))
    end
end
