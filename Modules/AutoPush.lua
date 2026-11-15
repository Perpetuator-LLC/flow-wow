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
        ns.Tip(self, "ANCHOR_TOP")
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
ns:PerCharacter("autopush.seen")   -- your action bars
ns:PerCharacter("autopush.bars")   -- which bar each of your forms shows
ns:PerCharacter("autopush.moved")  -- what Flow moved to a form's bar

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

-------------------------------------------------------------------------------
-- A form's spell goes on that form's bar (0.35.265)
-------------------------------------------------------------------------------
-- "Can the auto-place be smart enough to place the spells on the action bar
-- for that shape or form?" The game drops a new spell into the first empty
-- slot of whichever bar is showing: learn Maul in caster form and it lands on
-- your caster bar, where it can't be cast. Flow now moves it, out of a fight:
--   * which form a spell needs is read from the spell's own tooltip
--     ("Requires Bear Form"), so it works for stances and stealth too;
--   * which bar a form shows is learned the first time you're in the form
--     (the game says so then), and kept per character; a druid's two are
--     known from the start;
--   * it goes to the first empty slot of that bar. A full bar: left where
--     the game put it, and Flow says so.
-- Setting: "Put a form's new spells on that form's bar" (Flow Settings, New
-- spells and professions); /flow autoplace lists what was moved.

-- Each form's bar: slots 73-84 for the game's bar offset 1, 85-96 for 2...
AP.PAGES, AP.PER_BAR = 6, 12
-- Pure: the action slots of the bar a form shows (offset: the game's bonus
-- bar number for the form, 1 or more), or nil.
function AP.FormSlots(offset)
    offset = tonumber(offset)
    if not offset or offset < 1 then return nil end
    local first = (AP.PAGES + offset - 1) * AP.PER_BAR + 1
    return first, first + AP.PER_BAR - 1
end
-- Pure: the form a spell needs, from its tooltip's lines ({ left = text }):
-- one of `forms` (names) named in a "Requires ..." line. The longest name
-- wins ("Dire Bear Form" before "Bear Form").
function AP.FormOf(lines, forms)
    local best
    for _, l in ipairs(lines or {}) do
        local text = type(l.left) == "string" and l.left or ""
        if text:find("^Requires ") then
            for _, form in ipairs(forms or {}) do
                if text:find(form, 1, true) and (not best or #form > #best) then best = form end
            end
        end
    end
    return best
end
-- Pure: the first slot of first..last that's empty (taken(slot) -> bool), or nil.
function AP.FirstEmpty(first, last, taken)
    if not (first and last) then return nil end
    for slot = first, last do
        if not taken(slot) then return slot end
    end
    return nil
end
-- Pure: is a slot already on that form's bar?
function AP.OnBar(slot, first, last) return first ~= nil and slot >= first and slot <= last end

-- What Flow knows from the start (classic's numbers); the game's own answer,
-- read whenever you're in a form, replaces it.
AP.KNOWN_BARS = { DRUID = { ["Cat Form"] = 1, ["Bear Form"] = 3, ["Dire Bear Form"] = 3 } }

function AP.On() return ns.db.autopush.formBars ~= false end
local function barsDb()
    ns.db.autopush.bars = ns.db.autopush.bars or {}
    return ns.db.autopush.bars
end
function AP.BarOf(form)
    local seen = barsDb()[form]
    if seen then return seen end
    local _, class = UnitClass("player")
    local known = AP.KNOWN_BARS[ns.api.Safe(class) or ""]
    return known and known[form] or nil
end
-- You're in a form: note which bar the game shows for it.
local function noteForm()
    if not (GetBonusBarOffset and ns.api.StanceSpells) then return end
    local offset = ns.api.Safe(GetBonusBarOffset())
    if type(offset) ~= "number" or offset < 1 then return end
    for _, s in ipairs(ns.api.StanceSpells()) do
        if s.active then barsDb()[s.name] = offset end
    end
end
ns:On("UPDATE_SHAPESHIFT_FORM", function() pcall(noteForm) end)
ns:On("UPDATE_BONUS_ACTIONBAR", function() pcall(noteForm) end)

local function formNames()
    local out = {}
    for _, s in ipairs(ns.api.StanceSpells and ns.api.StanceSpells() or {}) do out[#out + 1] = s.name end
    return out
end
local function spellLines(spellID)
    if not (ns.gear and ns.gear.TooltipLines) then return {} end
    local ok, lines = pcall(ns.gear.TooltipLines, ns.gear, "spell:" .. tostring(spellID))
    return ok and lines or {}
end

-- Moves the spell the game just put in `slot`. -> "moved" (and where), or why not.
local waiting = {}
function AP:Move(spellID, slot, name)
    if not AP.On() then return "off" end
    local form = AP.FormOf(spellLines(spellID), formNames())
    if not form then return "no form" end
    local first, last = AP.FormSlots(AP.BarOf(form))
    if not first then return "bar unknown", form end
    if AP.OnBar(slot, first, last) then return "already there", form end
    if InCombatLockdown() then
        waiting[#waiting + 1] = { spellID = spellID, slot = slot, name = name }
        return "in a fight", form
    end
    local dest = AP.FirstEmpty(first, last, function(s) return HasAction(s) and true or false end)
    if not dest then
        ns:Print(string.format("%s needs %s, but your %s bar is full: it stays where the game put it", name, form, form))
        return "full", form
    end
    PickupAction(slot)
    PlaceAction(dest)
    ClearCursor()
    local moved = ns.db.autopush.moved or {}
    ns.db.autopush.moved = moved
    moved[#moved + 1] = { spell = name, form = form, pos = dest - first + 1, when = date("%b %d") }
    while #moved > 40 do table.remove(moved, 1) end
    ns:Print(string.format("%s needs %s: moved to your %s bar, slot %d", name, form, form, dest - first + 1))
    return "moved", form, dest
end
ns:On("PLAYER_REGEN_ENABLED", function()
    local list = waiting
    waiting = {}
    for _, w in ipairs(list) do pcall(AP.Move, AP, w.spellID, w.slot, w.name) end
end)
ns:On("SPELL_PUSHED_TO_ACTIONBAR", function(spellID, slot)
    if not slot then return end
    local name = ns.api.SpellInfo(spellID) or ("spell " .. tostring(spellID))
    local ok, what = pcall(AP.Move, AP, spellID, slot, name)
    if not ok then ns:Log("bars", "moving " .. name .. " failed: " .. tostring(what)) end
end)

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "learn",
        label = "Put a form's new spells on that form's bar",
        note = "(Bear Form, Cat Form, stances)",
        tip = "When the game drops a new spell on your bars and the spell needs a form (its tooltip says \"Requires Bear Form\"), "
            .. "Flow moves it to the first empty slot of the bar that form shows. Out of a fight only. A full bar is left alone.",
        get = function() return AP.On() end,
        set = function(on) ns.db.autopush.formBars = on and true or false end,
    })
end
