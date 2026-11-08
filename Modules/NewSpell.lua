-- A spell you just learned gets a small card for 10 seconds (it waits while
-- your mouse is on it, or while you drag or bind):
--
--   [icon]  New spell: Moonfire        drag the icon onto any bar slot
--   [Put it on my bar]  [Bind a key...]  [Not on my bars]
--
--   * Put it on my bar: the first empty slot (main bar first), and says where.
--   * Drag the icon: put it exactly where you want it.
--   * Bind a key...: press the key you want for it. Flow shows what that key
--     does now (and warns if it moves you) and changes nothing until you
--     click "Yes, bind it". The key casts the spell directly; it doesn't
--     need to be on a bar.
--   * Not on my bars: Flow stops asking you to put it on your bars (the
--     "Put X on your action bars" advice).
-- Rank upgrades of a spell you already have on a bar or a key, passive
-- spells and spells learned in combat (they wait until it ends) don't ask.
-- Setting: "New spells: offer to place or bind them" (/flow settings).

local _, ns = ...
local NS = {}
ns.newSpell = NS

local SHOW = 10
local queue = {}
local card
local MODIFIERS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, LMETA = 1, RMETA = 1 }
local MOVEMENT = { MOVEFORWARD = 1, MOVEBACKWARD = 1, TURNLEFT = 1, TURNRIGHT = 1, STRAFELEFT = 1,
                   STRAFERIGHT = 1, JUMP = 1, TOGGLEAUTORUN = 1 }

function NS.Enabled() return ns.db.spellbar.offer ~= false end
function NS.Muted(spell) return spell and ns.db.spellbar.muted[spell] == true end

-- A spell on any action bar slot (by id or name).
function NS.OnBar(id, name)
    for slot = 1, 120 do
        if HasAction(slot) then
            local kind, actionId = GetActionInfo(slot)
            if kind == "spell" and (actionId == id or (name and ns.api.SpellInfo(actionId) == name)) then return slot end
        end
    end
end

-- A key bound straight to it ("SPELL Moonfire").
function NS.KeyFor(name)
    return name and GetBindingKey and GetBindingKey("SPELL " .. name) or nil
end

-- The "put it on your bars" advice leaves it alone: you said no, or a key casts it.
function NS.Covered(name)
    return NS.Muted(name) or NS.KeyFor(name) ~= nil
end

-- First empty slot: main bar, then bottom left, bottom right, right, right 2.
local SLOT_ORDER = { { 1, 12 }, { 61, 72 }, { 49, 60 }, { 25, 36 }, { 37, 48 } }
local BAR_NAME = { [1] = "Action Bar 1", [61] = "Bottom Left Bar", [49] = "Bottom Right Bar", [25] = "Right Bar", [37] = "Right Bar 2" }
function NS.EmptySlot(has)
    has = has or HasAction
    for _, r in ipairs(SLOT_ORDER) do
        for slot = r[1], r[2] do
            if not has(slot) then return slot, BAR_NAME[r[1]], slot - r[1] + 1 end
        end
    end
end

local function pickup(id)
    local p = (C_Spell and C_Spell.PickupSpell) or PickupSpell
    if p then p(id) end
end

-- Full key name with modifiers held: "SHIFT-F".
local function withMods(key)
    local s = ""
    if IsAltKeyDown() then s = s .. "ALT-" end
    if IsControlKeyDown() then s = s .. "CTRL-" end
    if IsShiftKeyDown() then s = s .. "SHIFT-" end
    return s .. key
end

-- What a key does now, in words ("" if nothing), and whether it moves you.
function NS.KeyNow(key)
    local action = GetBindingAction and GetBindingAction(key, true) or ""
    if action == "" then return "", false end
    local name = (GetBindingName and GetBindingName(action)) or action
    return name, MOVEMENT[action] ~= nil
end

-------------------------------------------------------------------------------
-- The card
-------------------------------------------------------------------------------

local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    return b
end

local show   -- (defined below)

local function finish(msg)
    if msg then ns:Print(msg) end
    if card then
        card:EnableKeyboard(false)
        card.capturing, card.pending = false, nil
        card:Hide()
    end
    C_Timer.After(0.3, show)   -- the next new spell, if any
end

local function setMode(mode)
    -- "choose": the three buttons; "capture": press a key; "confirm": yes / cancel.
    card.mode = mode
    card.place:SetShown(mode == "choose"); card.bind:SetShown(mode == "choose"); card.no:SetShown(mode == "choose")
    card.yes:SetShown(mode == "confirm"); card.cancel:SetShown(mode ~= "choose")
end

local function build()
    local f = CreateFrame("Frame", "FlowNewSpell", UIParent)
    f:SetSize(380, 112)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.head = ns.theme:TitleBar(f, "Flow Spells", "Interface\\Icons\\INV_Misc_Book_09")
    -- The spell's icon: drag it onto any bar slot.
    f.icon = CreateFrame("Button", nil, f)
    f.icon:SetSize(40, 40)
    f.icon:SetPoint("TOPLEFT", 12, -32)
    f.icon.tex = f.icon:CreateTexture(nil, "ARTWORK"); f.icon.tex:SetAllPoints()
    f.icon:RegisterForDrag("LeftButton")
    f.icon:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        ClearCursor(); pickup(f.spellId)
    end)
    f.icon:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_LEFT")
        if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(f.spellId) end
        GameTooltip:AddLine("Drag it onto any action bar slot.", 0.6, 1, 0.6)
        GameTooltip:Show()
    end)
    f.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -2)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
    f.status:SetWidth(300); f.status:SetJustifyH("LEFT")
    f.place = button(f, "Put it on my bar", 128)
    f.place:SetPoint("BOTTOMLEFT", 10, 10)
    f.bind = button(f, "Bind a key...", 110)
    f.bind:SetPoint("LEFT", f.place, "RIGHT", 6, 0)
    f.no = button(f, "Not on my bars", 112)
    f.no:SetPoint("LEFT", f.bind, "RIGHT", 6, 0)
    f.yes = button(f, "Yes, bind it", 120)
    f.yes:SetPoint("BOTTOMLEFT", 10, 10)
    f.cancel = button(f, "Cancel", 90)
    f.cancel:SetPoint("BOTTOMRIGHT", -10, 10)
    -- The time left, a thin bar along the bottom (it waits while you're on the card).
    f.timer = CreateFrame("StatusBar", nil, f)
    f.timer:SetPoint("BOTTOMLEFT"); f.timer:SetPoint("BOTTOMRIGHT"); f.timer:SetHeight(3)
    f.timer:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local o = ns.theme.arrow
    f.timer:SetStatusBarColor(o[1], o[2], o[3])
    f.timer:SetMinMaxValues(0, SHOW)

    f.place:SetScript("OnClick", function()
        if InCombatLockdown() then f.status:SetText("Not in combat: try again after the fight.") return end
        local slot, bar, pos = NS.EmptySlot()
        if not slot then f.status:SetText("Your bars are full: drag the icon onto a slot to replace one.") return end
        ClearCursor(); pickup(f.spellId); PlaceAction(slot); ClearCursor()
        finish(string.format("%s is on %s, slot %d.", f.spellName, bar, pos))
    end)
    f.no:SetScript("OnClick", function()
        ns.db.spellbar.muted[f.spellName] = true
        if ns.advisor and ns.advisor.Refresh then pcall(ns.advisor.Refresh, ns.advisor) end
        finish(f.spellName .. ": not on your bars. Flow won't ask again (it's in your spellbook, P).")
    end)
    f.bind:SetScript("OnClick", function()
        if InCombatLockdown() then f.status:SetText("Key bindings can't change in combat.") return end
        setMode("capture")
        f.status:SetText("Press the key you want for " .. f.spellName .. " (with Shift, Ctrl or Alt if you like). Esc cancels.")
        f:EnableKeyboard(true)
        if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(false) end
    end)
    f:SetScript("OnKeyDown", function(self, key)
        if self.mode ~= "capture" then return end
        if key == "ESCAPE" then
            self:EnableKeyboard(false); setMode("choose"); self.status:SetText("Cancelled: no key changed.")
            return
        end
        if MODIFIERS[key] then return end
        local full = withMods(key)
        self:EnableKeyboard(false)
        self.pending = full
        local now, moves = NS.KeyNow(full)
        setMode("confirm")
        self.status:SetText(string.format("Bind %s to %s?%s", full, self.spellName,
            now ~= "" and string.format("\n%s does now: %s%s", full, now, moves and "  |cffff6060(it moves you!)|r" or "")
            or "\n(that key isn't used yet)"))
    end)
    f.yes:SetScript("OnClick", function()
        if InCombatLockdown() then f.status:SetText("Key bindings can't change in combat.") return end
        local key = f.pending
        if not (key and SetBindingSpell) then finish() return end
        SetBindingSpell(key, f.spellName)
        if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
        finish(string.format("%s now casts %s.", key, f.spellName))
    end)
    f.cancel:SetScript("OnClick", function()
        f:EnableKeyboard(false); f.pending = nil
        setMode("choose")
        f.status:SetText("No key changed.")
    end)
    -- Hover-to-bind for everything else, one click away.
    f.more = CreateFrame("Button", nil, f)
    f.more:SetSize(120, 14)
    f.more:SetPoint("TOPRIGHT", -8, -30)
    f.more.text = f.more:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.more.text:SetAllPoints(); f.more.text:SetJustifyH("RIGHT")
    f.more.text:SetText("all keys: hover to bind")
    f.more:SetScript("OnClick", function() finish(); if ns.bind then ns.bind:Start() end end)

    f:SetScript("OnUpdate", function(self, dt)
        -- Waiting for a key never holds your keyboard for long: 15 s, then cancelled.
        if self.mode == "capture" then
            self.captureLeft = (self.captureLeft or 15) - dt
            if self.captureLeft <= 0 then
                self.captureLeft = nil
                self:EnableKeyboard(false); setMode("choose"); self.status:SetText("No key pressed: nothing changed.")
            end
            return
        end
        self.captureLeft = nil
        -- Waits while you're on it, dragging its spell, or choosing a key.
        local cursor = GetCursorInfo and GetCursorInfo()
        if self.mode ~= "choose" or self:IsMouseOver() or cursor == "spell" then return end
        self.left = self.left - dt
        self.timer:SetValue(math.max(0, self.left))
        if self.left <= 0 then finish() end
    end)
    f:Hide()
    return f
end

show = function()
    if (card and card:IsShown()) or #queue == 0 then return end
    if InCombatLockdown() then return end   -- (PLAYER_REGEN_ENABLED shows it)
    local e = table.remove(queue, 1)
    card = card or build()
    card.spellId, card.spellName = e.id, e.name
    local _, icon = ns.api.SpellInfo(e.id)
    card.icon.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    card.name:SetText(e.name)
    -- The game may have put it on a bar already: say where (it can still be
    -- dragged elsewhere or given a key).
    local where = e.slot and NS.SlotName(e.slot)
    card.status:SetText(where and ("The game put it on " .. where .. ". Drag the icon to move it, or:")
        or "Drag the icon onto any bar slot, or:")
    card.left = SHOW
    card.timer:SetValue(SHOW)
    setMode("choose")
    if e.slot then card.place:Hide() end
    card:Show()
end

-- "Action Bar 1, slot 5" for an action slot.
function NS.SlotName(slot)
    for _, r in ipairs(SLOT_ORDER) do
        if slot >= r[1] and slot <= r[2] then return string.format("%s, slot %d", BAR_NAME[r[1]], slot - r[1] + 1) end
    end
    return "slot " .. tostring(slot)
end

-- Should a newly learned spell ask? Not passive, not muted, not already on a
-- bar or a key (a new rank of one you have), and the setting is on.
function NS.ShouldAsk(id, name, passive, onBar, key, muted, enabled)
    return enabled and name ~= nil and not passive and not onBar and not key and not muted
end

-- A brand-new spell (a name you didn't know before) asks even when the game
-- put it on a bar by itself: you see where, and can bind a key.
function NS.ShouldAskNew(name, passive, key, muted, enabled)
    return enabled and name ~= nil and not passive and not key and not muted
end

-- Spells you learn are found by comparing your spellbook with the last look:
-- new names get the card (new ranks of spells you have don't). The event this
-- used ("LEARNED_SPELL_IN_TAB") doesn't exist on this client (it's
-- "LEARNED_SPELL_IN_SKILL_LINE" there), so the card never showed.
local knownNames, checkPending

function NS.NewNames(before, now)
    local out = {}
    for name in pairs(now or {}) do if not before[name] then out[#out + 1] = name end end
    table.sort(out)
    return out
end

local function offerNew(name)
    local spellName, _, _, id = ns.api.SpellInfo(name)
    if not id then return end
    local passive = (C_Spell and C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(id))
        or (IsPassiveSpell and IsPassiveSpell(id)) or false
    local slot, key = NS.OnBar(id, spellName), NS.KeyFor(spellName)
    if not NS.ShouldAskNew(spellName, passive, key, NS.Muted(spellName), NS.Enabled()) then
        ns:Log("newspell", string.format("learned %s: no card (%s)", spellName,
            not NS.Enabled() and "setting off" or passive and "passive" or key and ("key " .. key) or "you said not on your bars"))
        return
    end
    for _, q in ipairs(queue) do if q.name == spellName then return end end
    queue[#queue + 1] = { id = id, name = spellName, slot = slot }
    ns:Log("newspell", string.format("learned %s: card%s", spellName, slot and (" (already on " .. NS.SlotName(slot) .. ")") or ""))
    show()
end

-------------------------------------------------------------------------------
-- New ranks on your bars: when you learn a higher rank of a spell, every bar
-- slot with an older rank of it gets the new one (out of combat: bars can't
-- change in a fight). Only at the moment you learn the rank, so a lower rank
-- you put back on purpose (to save mana) stays until the next one.
-- Setting: "Upgrade spell ranks on your bars" (/flow settings).
-------------------------------------------------------------------------------

local knownIds          -- [name] = the spell ID of the rank you know (the highest)
local upgradeWaiting = {}

-- Names whose spell ID changed: a new rank. before, now: { [name] = id }.
function NS.RankUps(before, now)
    local out = {}
    for name, id in pairs(now or {}) do
        if before[name] and before[name] ~= id then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

-- The bar slots holding an older rank of `name`. actions: { [slot] = spell ID }.
function NS.OldRankSlots(actions, name, newId, nameOf)
    local out = {}
    for slot, id in pairs(actions) do
        if id ~= newId and nameOf(id) == name then out[#out + 1] = slot end
    end
    table.sort(out)
    return out
end

local function idsOf(names)
    local ids = {}
    for name in pairs(names) do
        local _, _, _, id = ns.api.SpellInfo(name)
        if id then ids[name] = id end
    end
    return ids
end

local function upgradeBars(name)
    if ns.db.spellbar.upgradeRanks == false then return end
    if InCombatLockdown() then upgradeWaiting[name] = true return end
    local _, _, _, newId = ns.api.SpellInfo(name)
    if not newId then return end
    local actions = {}
    for slot = 1, 120 do
        if HasAction(slot) then
            local kind, id = GetActionInfo(slot)
            if kind == "spell" and id then actions[slot] = id end
        end
    end
    local slots = NS.OldRankSlots(actions, name, newId, function(id) return (ns.api.SpellInfo(id)) end)
    for _, slot in ipairs(slots) do
        ClearCursor(); pickup(newId); PlaceAction(slot); ClearCursor()
    end
    if #slots > 0 then
        ns:Log("newspell", string.format("%s: new rank put on %d bar slot(s) (%s)", name, #slots, table.concat(slots, ", ")))
        ns:Print(string.format("%s: the new rank is on your bars now (%d slot(s)).", name, #slots))
    end
end

ns:On("PLAYER_REGEN_ENABLED", function()
    C_Timer.After(1, function()
        for name in pairs(upgradeWaiting) do upgradeWaiting[name] = nil; pcall(upgradeBars, name) end
    end)
end)

local function checkNew()
    checkPending = false
    local now = ns.api.KnownSpells and ns.api.KnownSpells() or {}
    local nowIds = idsOf(now)
    if not knownNames then knownNames, knownIds = now, nowIds return end   -- the first look: what you know already
    for _, name in ipairs(NS.NewNames(knownNames, now)) do pcall(offerNew, name) end
    for _, name in ipairs(NS.RankUps(knownIds or {}, nowIds)) do pcall(upgradeBars, name) end
    knownNames, knownIds = now, nowIds
end
-- (A second after a change: the game may put the spell on a bar by itself first.)
local function scheduleCheck()
    if checkPending then return end
    checkPending = true
    C_Timer.After(1, checkNew)
end
ns:On("PLAYER_ENTERING_WORLD", function()
    knownNames, checkPending = nil, true
    C_Timer.After(3, checkNew)
end)
ns:On("SPELLS_CHANGED", function() if knownNames then scheduleCheck() end end)
ns:On("LEARNED_SPELL_IN_SKILL_LINE", scheduleCheck)
ns:On("LEARNED_SPELL_IN_TAB", scheduleCheck)

-- The card for a spell you already know (the link on "Put X on your action
-- bars" in Flow's improvements list): place it, drag it or bind a key.
function NS:Offer(name)
    local spellName, _, _, id = ns.api.SpellInfo(name)
    if not (spellName and id) then ns:Print("Flow can't find the spell " .. tostring(name) .. " in your spellbook.") return end
    for _, q in ipairs(queue) do if q.name == spellName then show() return end end
    queue[#queue + 1] = { id = id, name = spellName }
    show()
end

ns:On("PLAYER_REGEN_ENABLED", function() C_Timer.After(1, show) end)

ns:OnLoad(function(saved)
    saved.spellbar = saved.spellbar or {}
    saved.spellbar.muted = saved.spellbar.muted or {}
end)
ns:PerCharacter("spellbar.muted")   -- your spells, your bars

ns.commands.newspell = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then ns.db.spellbar.offer = (arg == "on") end
    if arg == "reset" then wipe(ns.db.spellbar.muted) end
    ns:Print("new spells: offer to place or bind them " .. (NS.Enabled() and "on" or "off")
        .. "  (/flow newspell on|off|reset)")
end
