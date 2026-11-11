-- Spells you just learned go into one Flow Spells list (see "The Flow Spells
-- list" below): a row each, with
--   * the icon: drag it exactly where you want it;
--   * Bar: the first empty slot (main bar first), and says where;
--   * Key: press the key you want for it. Flow shows what that key does now
--     (and warns if it moves you) and changes nothing until you click "Yes,
--     bind it". The key casts the spell directly; it needn't be on a bar;
--   * Skip: Flow stops asking you to put it on your bars (the "Put X on your
--     action bars" advice);
-- and "Place all on bar" for every one that isn't on a bar or a key yet.
-- Rank upgrades of a spell you already have on a bar or a key, passive
-- spells and spells learned in combat (they wait until it ends) don't ask.
-- Setting: "New spells: offer to place or bind them" (/flow settings).

local _, ns = ...
local NS = {}
ns.newSpell = NS

local SHOW = 30   -- seconds the Flow Spells list stays (it waits while you use it)
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
-- The Flow Spells list: every spell you just learned, in one window (0.35.141;
-- each used to get a card of its own for 10 s, the next replacing it):
--
--   Flow Spells: 3 new spells                                       [X]
--   [icon] Moonfire        not on a bar              [Bar] [Key] [Skip]
--   [icon] Thorns          Action Bar 1, slot 5            [Key] [Skip]
--   (what happened)
--   [Place all on bar]          all keys: hover to bind       [Close]
--
-- Drag an icon onto any bar slot, or: Bar = the first empty slot, Key =
-- press the key you want (Flow shows what it does now and changes nothing
-- until "Yes, bind it"), Skip = not on your bars (Flow stops asking). It
-- stays while you use it, then closes by itself after half a minute.
-------------------------------------------------------------------------------

local ROWS, ROW_H = 12, 30
local list = {}   -- { id, name, slot, key, skipped }

local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    return b
end

-- The spells still wanting a bar slot: not on a bar, no key, not skipped.
function NS.Placeable(entries)
    local out = {}
    for _, e in ipairs(entries or {}) do
        if not (e.slot or e.key or e.skipped) then out[#out + 1] = e end
    end
    return out
end
-- What a row says about where the spell is.
function NS.RowWhere(e)
    if e.key then return "key: " .. e.key end
    if e.slot then return NS.SlotName(e.slot) end
    if e.skipped then return "not on your bars" end
    return "|cff999999not on a bar yet|r"
end

local refresh, show   -- (defined below)

local function setStatus(text) if card then card.status:SetText(text or "") end end

local function setMode(mode)
    -- "choose": the rows' buttons and Place all; "capture": press a key;
    -- "confirm": yes / cancel.
    card.mode = mode
    card.placeAll:SetShown(mode == "choose"); card.close2:SetShown(mode == "choose")
    card.yes:SetShown(mode == "confirm"); card.cancel:SetShown(mode ~= "choose")
    refresh()
end

-- Puts e in the first empty slot. Returns true, or false and why.
local function place(e)
    if InCombatLockdown() then return false, "Not in combat: try again after the fight." end
    local slot, bar, pos = NS.EmptySlot()
    if not slot then return false, "Your bars are full: drag an icon onto a slot to replace one." end
    ClearCursor(); pickup(e.id); PlaceAction(slot); ClearCursor()
    e.slot = slot
    return true, string.format("%s is on %s, slot %d.", e.name, bar, pos)
end

local function build()
    local f = CreateFrame("Frame", "FlowNewSpell", UIParent)
    f:SetSize(440, 120)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.head = ns.theme:TitleBar(f, "Flow Spells", "Interface\\Icons\\INV_Misc_Book_09")
    ns:MakeMovable(f, {}, true)   -- (Ctrl-drag; it opens in the same place each time)
    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", 2, 2)
    x:SetScript("OnClick", function() NS:Close() end)
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(420, ROW_H - 2)
        r:SetPoint("TOPLEFT", 10, -30 - (i - 1) * ROW_H)
        -- The spell's icon: drag it onto any bar slot.
        r.icon = CreateFrame("Button", nil, r)
        r.icon:SetSize(26, 26); r.icon:SetPoint("LEFT")
        r.icon.tex = r.icon:CreateTexture(nil, "ARTWORK"); r.icon.tex:SetAllPoints()
        r.icon:RegisterForDrag("LeftButton")
        r.icon:SetScript("OnDragStart", function()
            if InCombatLockdown() or not r.e then return end
            ClearCursor(); pickup(r.e.id)
        end)
        r.icon:SetScript("OnEnter", function(self)
            if not r.e then return end
            ns.Tip(self, "ANCHOR_LEFT")
            if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(r.e.id) end
            GameTooltip:AddLine("Drag it onto any action bar slot.", 0.6, 1, 0.6)
            GameTooltip:Show()
        end)
        r.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0); r.name:SetWidth(130); r.name:SetJustifyH("LEFT")
        r.where = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.where:SetPoint("LEFT", r.name, "RIGHT", 4, 0); r.where:SetWidth(130); r.where:SetJustifyH("LEFT")
        r.skip = button(r, "Skip", 46); r.skip:SetPoint("RIGHT")
        r.key = button(r, "Key", 46); r.key:SetPoint("RIGHT", r.skip, "LEFT", -3, 0)
        r.bar = button(r, "Bar", 46); r.bar:SetPoint("RIGHT", r.key, "LEFT", -3, 0)
        r.bar:SetScript("OnClick", function()
            local _, msg = place(r.e)
            setStatus(msg); refresh()
        end)
        r.skip:SetScript("OnClick", function()
            ns.db.spellbar.muted[r.e.name] = true
            r.e.skipped = true
            if ns.advisor and ns.advisor.Refresh then pcall(ns.advisor.Refresh, ns.advisor) end
            setStatus(r.e.name .. ": not on your bars. Flow won't ask again (it's in your spellbook, P).")
            refresh()
        end)
        r.key:SetScript("OnClick", function()
            if InCombatLockdown() then setStatus("Key bindings can't change in combat.") return end
            f.target = r.e
            setMode("capture")
            setStatus("Press the key you want for " .. r.e.name .. " (with Shift, Ctrl or Alt if you like). Esc cancels.")
            f:EnableKeyboard(true)
            if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(false) end
        end)
        f.rows[i] = r
    end
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetWidth(420); f.status:SetJustifyH("LEFT")
    f.placeAll = button(f, "Place all on bar", 140)
    f.placeAll:SetPoint("BOTTOMLEFT", 10, 10)
    f.placeAll:SetScript("OnClick", function() NS:PlaceAll() end)
    f.close2 = button(f, "Close", 80)
    f.close2:SetPoint("BOTTOMRIGHT", -10, 10)
    f.close2:SetScript("OnClick", function() NS:Close() end)
    f.yes = button(f, "Yes, bind it", 120)
    f.yes:SetPoint("BOTTOMLEFT", 10, 10)
    f.cancel = button(f, "Cancel", 90)
    f.cancel:SetPoint("BOTTOMRIGHT", -10, 10)
    -- Hover-to-bind for everything else, one click away.
    f.more = CreateFrame("Button", nil, f)
    f.more:SetSize(150, 14)
    f.more:SetPoint("BOTTOM", 0, 14)
    f.more.text = f.more:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.more.text:SetAllPoints()
    f.more.text:SetText("all keys: hover to bind")
    f.more:SetScript("OnClick", function() NS:Close(); if ns.bind then ns.bind:Start() end end)
    -- The time left, a thin bar along the bottom (it waits while you use it).
    f.timer = CreateFrame("StatusBar", nil, f)
    f.timer:SetPoint("BOTTOMLEFT"); f.timer:SetPoint("BOTTOMRIGHT"); f.timer:SetHeight(3)
    f.timer:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local o = ns.theme.arrow
    f.timer:SetStatusBarColor(o[1], o[2], o[3])
    f.timer:SetMinMaxValues(0, SHOW)

    f:SetScript("OnKeyDown", function(self, key)
        if self.mode ~= "capture" then return end
        if key == "ESCAPE" then
            self:EnableKeyboard(false); setMode("choose"); setStatus("Cancelled: no key changed.")
            return
        end
        if MODIFIERS[key] then return end
        local full = withMods(key)
        self:EnableKeyboard(false)
        self.pending = full
        local now, moves = NS.KeyNow(full)
        setMode("confirm")
        setStatus(string.format("Bind %s to %s?%s", full, self.target.name,
            now ~= "" and string.format("\n%s does now: %s%s", full, now, moves and "  |cffff6060(it moves you!)|r" or "")
            or "\n(that key isn't used yet)"))
    end)
    f.yes:SetScript("OnClick", function()
        if InCombatLockdown() then setStatus("Key bindings can't change in combat.") return end
        local key, e = f.pending, f.target
        f.pending = nil
        if key and e and SetBindingSpell then
            SetBindingSpell(key, e.name)
            if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
            e.key = key
            setStatus(string.format("%s now casts %s.", key, e.name))
        end
        setMode("choose")
    end)
    f.cancel:SetScript("OnClick", function()
        f:EnableKeyboard(false); f.pending = nil
        setMode("choose")
        setStatus("No key changed.")
    end)

    f:SetScript("OnUpdate", function(self, dt)
        -- Waiting for a key never holds your keyboard for long: 15 s, then cancelled.
        if self.mode == "capture" then
            self.captureLeft = (self.captureLeft or 15) - dt
            if self.captureLeft <= 0 then
                self.captureLeft = nil
                self:EnableKeyboard(false); setMode("choose"); setStatus("No key pressed: nothing changed.")
            end
            return
        end
        self.captureLeft = nil
        -- Waits while you're on it, dragging a spell, or choosing a key.
        local cursor = GetCursorInfo and GetCursorInfo()
        if self.mode ~= "choose" or self:IsMouseOver() or cursor == "spell" then return end
        self.left = self.left - dt
        self.timer:SetValue(math.max(0, self.left))
        if self.left <= 0 then NS:Close() end
    end)
    f:Hide()
    return f
end

refresh = function()
    if not card then return end
    local n = math.min(#list, ROWS)
    local choosing = card.mode == "choose"
    for i, r in ipairs(card.rows) do
        local e = list[i]
        r.e = e
        if e then
            local _, icon = ns.api.SpellInfo(e.id)
            r.icon.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.name:SetText(e.name)
            r.where:SetText(NS.RowWhere(e))
            r.bar:SetShown(choosing and not (e.slot or e.key or e.skipped))
            r.key:SetShown(choosing and not (e.key or e.skipped))
            r.skip:SetShown(choosing and not (e.slot or e.key or e.skipped))
            r:Show()
        else
            r:Hide()
        end
    end
    card.status:ClearAllPoints()
    card.status:SetPoint("TOPLEFT", 10, -34 - n * ROW_H)
    card.placeAll:SetEnabled(#NS.Placeable(list) > 0)
    card.head.text:SetText(#list == 1 and "Flow Spells: a new spell" or string.format("Flow Spells: %d new spells", #list))
    card:SetHeight(30 + n * ROW_H + 70)
end

-- Every spell in the list that isn't on a bar or a key yet: the first empty
-- slots, main bar first.
function NS:PlaceAll()
    local placed, why = 0, nil
    for _, e in ipairs(NS.Placeable(list)) do
        local ok, msg = place(e)
        if not ok then why = msg break end
        placed = placed + 1
    end
    setStatus((placed > 0 and string.format("%d spell%s placed on your bars.", placed, placed == 1 and "" or "s") or "")
        .. (why and ((placed > 0 and " " or "") .. why) or ""))
    refresh()
end

function NS:Close()
    if card then
        card:EnableKeyboard(false)
        card.target, card.pending = nil, nil
        card:Hide()
    end
    wipe(list)
end

show = function()
    if #queue == 0 then return end
    if InCombatLockdown() then return end   -- (PLAYER_REGEN_ENABLED shows it)
    -- Everything learned meanwhile joins the one list.
    while #queue > 0 do
        local e = table.remove(queue, 1)
        local dup = false
        for _, l in ipairs(list) do if l.name == e.name then dup = true end end
        if not dup and #list < ROWS then list[#list + 1] = e end
    end
    card = card or build()
    card.left = SHOW
    card.timer:SetValue(SHOW)
    local wasShown = card:IsShown()
    if not wasShown then card.mode = "choose"; setStatus("Drag an icon onto any bar slot, or:") end
    setMode(card.mode or "choose")
    card:Show()
end
NS._list = function() return list end   -- (tests)

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

-- /flow keys: the keys that cast a spell straight away, not from a bar (the
-- game's Key Bindings window doesn't list those: it shows only its own
-- commands), and Flow's own key. names: { [spell name] = true }; keyFor(name)
-- -> up to two keys. Sorted by key.
function NS.DirectKeys(names, keyFor)
    local out = {}
    for name in pairs(names or {}) do
        local k1, k2 = keyFor(name)
        if k1 then out[#out + 1] = { key = k1, name = name } end
        if k2 then out[#out + 1] = { key = k2, name = name } end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end
ns.commands.keys = function()
    local spells = NS.DirectKeys(ns.api.KnownSpells and ns.api.KnownSpells() or {},
        function(n) if GetBindingKey then return GetBindingKey("SPELL " .. n) end end)
    if #spells == 0 then
        ns:Print("no key casts a spell directly: they all go through your bars.")
    else
        ns:Print("keys that cast a spell directly (not from a bar):")
        for _, e in ipairs(spells) do print("  " .. e.key .. ": " .. e.name) end
    end
    local C = ns.cast
    local keys = C and C.KeysOf and C.KeysOf(ns.db.cast) or {}
    if #keys > 0 then
        print("  Flow key: " .. table.concat(keys, ", ") .. "  (Shift + it: your heal; Ctrl + it: on your target; Alt + it: healthstone or potion)")
    end
    print("  Change them: Key on the Flow Spells list, or /flow bind (hover a bar button, press a key).")
end
