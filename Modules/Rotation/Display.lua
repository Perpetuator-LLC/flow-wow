-- Shows the suggestion: a movable icon near the middle of the screen, plus a
-- pulsing glow on whichever action bar button holds that spell.

local _, ns = ...
local A, E = ns.api, ns.rotation

local COLORS = {
    -- No red: red reads as "can't". Gold means "heal now".
    damage    = { 0.2, 1.0, 0.2 },    -- green
    buff      = { 0.35, 0.75, 1.0 },  -- light blue
    heal      = { 1.0, 0.8, 0.2 },    -- gold, steady pulse
    emergency = { 1.0, 0.85, 0.1 },   -- bright gold, fast pulse
    held      = { 0.55, 0.55, 0.55 }, -- grey: what the key still does mid-fight (nothing new to press)
    key       = { 0.2, 1.0, 0.2 },    -- green: the key's spell for this fight, with better advice in the corner
}

local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton",
    "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local icon, glows, current
local buttonsBySpell = {}
local buttonsByItem = {}   -- item ID -> buttons (a healthstone, a bandage)

-- A coloured frame made of plain colour textures. Works on every client
-- (no dependency on Blizzard art files).
-- outside: the frame goes round the parent (as the self button's blue edge
-- does) and leaves all of the parent's own area clear; else it lies on the
-- parent's own outer few pixels.
ns.ICON_EDGE = 3   -- the coloured edge round Flow's icon and round the self button
local function makeBorder(parent, thickness, inset, outside)
    local b = { edges = {}, outside = outside and thickness or 0 }
    local o = b.outside
    local OUT = { TOPLEFT = { -o, o }, TOPRIGHT = { o, o }, BOTTOMLEFT = { -o, -o }, BOTTOMRIGHT = { o, -o } }
    local function edge(p1, p2, horizontal)
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetPoint(p1, parent, p1, OUT[p1][1], OUT[p1][2])
        t:SetPoint(p2, parent, p2, OUT[p2][1], OUT[p2][2])
        if horizontal then t:SetHeight(thickness) else t:SetWidth(thickness) end
        b.edges[#b.edges + 1] = t
    end
    edge("TOPLEFT", "TOPRIGHT", true)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPLEFT", "BOTTOMLEFT", false)
    edge("TOPRIGHT", "BOTTOMRIGHT", false)
    b.fill = parent:CreateTexture(nil, "OVERLAY", nil, 6)
    b.fill:SetColorTexture(1, 1, 1, 1)
    b.fill:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
    b.fill:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
    function b:SetColor(r, g, bl)
        for _, t in ipairs(self.edges) do t:SetVertexColor(r, g, bl, 1) end
        self.fill:SetVertexColor(r, g, bl, 0.25)
    end
    return b
end

-------------------------------------------------------------------------------
-- Suggestion icon
-------------------------------------------------------------------------------

local function buildIcon(cfg)
    local f = CreateFrame("Frame", "FlowRotationIcon", UIParent)
    f:SetSize(52, 52)
    f:SetFrameStrata("MEDIUM")   -- (under the game's own windows: the game menu, Settings; 0.35.163)
    ns.RestorePlace(f, cfg, 0, -160)  -- the cast button then puts it on top of itself

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Round the icon, not on it (0.35.256): the same 52 of picture inside a
    -- 3 pixel edge as the self button, so the two are one size, and the cast
    -- bar along the bottom lies inside the edge on both.
    f.border = makeBorder(f, ns.ICON_EDGE, nil, true)
    f.border.fill:Hide()  -- keep the spell icon clear

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    -- Flow draws its own countdown (below), so the game's numbers stay off.
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    -- The cooldown timer: seconds left, big in the middle of the icon, above
    -- the cooldown's dark sweep. The global cooldown (1.5 s after every cast)
    -- isn't counted: only real cooldowns.
    f.timerLayer = CreateFrame("Frame", nil, f)
    f.timerLayer:SetAllPoints()
    f.timerLayer:SetFrameLevel(f.cd:GetFrameLevel() + 2)
    f.timer = f.timerLayer:CreateFontString(nil, "OVERLAY")
    f.timer:SetFont(STANDARD_TEXT_FONT, 18, "THICKOUTLINE")
    f.timer:SetPoint("CENTER", 0, 0)
    f.timer:SetTextColor(1, 0.95, 0.7)
    -- Auto attack on: a crossed-swords badge on the RIGHT of the button (the
    -- queue has the left side since 0.35.188), gently pulsing while swinging.
    f.swing = CreateFrame("Frame", nil, f.timerLayer)
    f.swing:SetSize(24, 24)
    f.swing:SetPoint("LEFT", f, "RIGHT", 8, 0)
    f.swing.back = f.swing:CreateTexture(nil, "BACKGROUND")
    f.swing.back:SetPoint("TOPLEFT", -1, 1); f.swing.back:SetPoint("BOTTOMRIGHT", 1, -1)
    f.swing.back:SetColorTexture(0, 0, 0, 0.85)
    f.swing.tex = f.swing:CreateTexture(nil, "ARTWORK")
    f.swing.tex:SetAllPoints()
    f.swing.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local _, swingIcon = A.SpellInfo("Auto Attack")
    f.swing.tex:SetTexture(swingIcon or "Interface\\Icons\\INV_Sword_04")
    -- Its edge wears the colour of the weapon in your main hand (0.35.327).
    f.swing.edge = f.swing:CreateTexture(nil, "BACKGROUND", nil, -2)
    f.swing.edge:SetPoint("TOPLEFT", -2, 2); f.swing.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    f.swing.edge:SetColorTexture(0, 0, 0, 0)
    -- On: a ring round it that pulses with Flow's other "this is live" marks
    -- (ns.pulse: one colour, one beat), the picture itself steady. (0.35.327
    -- drew a soft glow from one of the game's textures: it didn't show.
    -- "It doesn't show the flashing; you do it already on a couple of the
    -- other icons, so do that same thing when auto attack is enabled.")
    -- 0.35.337: on the INSIDE, as the game does it. "That's actually supposed
    -- to go on the inside: a glow from the borders inward that fades as it
    -- goes inward. Look at any of the other icons when they're toggled on."
    -- Seen on the action bar's own Attack button: it's the game's highlight
    -- for a button that's switched on (ns.SWING_CHECKED), laid over the
    -- picture and added to it. Flow's pulse still breathes it.
    f.swing.glow = f.swing:CreateTexture(nil, "OVERLAY")
    f.swing.glow:SetAllPoints(f.swing.tex)
    f.swing.glow:SetTexture(ns.SWING_CHECKED)
    f.swing.glowInside = f.swing.glow:GetTexture() ~= nil
    if f.swing.glowInside then
        f.swing.glow:SetBlendMode("ADD")
    else
        -- (A game without that picture: the ring round it, as in 0.35.335.)
        f.swing.glow:SetDrawLayer("BACKGROUND", -3)
        f.swing.glow:ClearAllPoints()
        f.swing.glow:SetPoint("TOPLEFT", -ns.SWING_RING, ns.SWING_RING)
        f.swing.glow:SetPoint("BOTTOMRIGHT", ns.SWING_RING, -ns.SWING_RING)
        f.swing.glow:SetColorTexture(ns.pulse.COLOR[1], ns.pulse.COLOR[2], ns.pulse.COLOR[3], 1)
    end
    f.swing.glow:Hide()
    f.swing:Hide()
    -- Hover: what it is. (A click on it toggles auto attack: ClickSlots.lua
    -- lays a button of the game's kind over it.)
    f.swing:EnableMouse(true)
    f.swing:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Auto-Attack", 1, 0.82, 0)
        GameTooltip:AddLine(A.Swinging() and "On: you're swinging at your target." or "Off.", 1, 1, 1, true)
        GameTooltip:AddLine("Click to turn it on or off.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    f.swing:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- A swing spell waiting for your next swing (Maul): the game's action
    -- bar blinks its button red until it goes off, and now Flow's does too
    -- (0.35.318: "it preps it for the next hit ... the action bar shows kind
    -- of like a red glowing effect ... the target button doesn't do that").
    -- The same red, blinking at the bar's beat; the queued spell's own small
    -- picture at the top right when the button shows another spell.
    f.queued = CreateFrame("Frame", nil, f)
    f.queued:SetAllPoints()
    f.queued:SetFrameLevel(f.cd:GetFrameLevel() + 1)
    f.queued.flash = f.queued:CreateTexture(nil, "OVERLAY")
    f.queued.flash:SetAllPoints()
    f.queued.flash:SetTexture("Interface\\Buttons\\UI-QuickslotRed")
    if not f.queued.flash:GetTexture() then f.queued.flash:SetColorTexture(1, 0.1, 0.1, 0.4) end
    f.queued.mini = f.queued:CreateTexture(nil, "OVERLAY", nil, 2)
    f.queued.mini:SetSize(18, 18)
    f.queued.mini:SetPoint("CENTER", f, "TOPRIGHT", -1, -1)
    f.queued.mini:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.queued:SetScript("OnUpdate", function(self, dt)
        self.t = (self.t or 0) + dt
        if self.t < E.QUEUE_BLINK then return end
        self.t = 0
        self.on = not self.on
        local a = self.on and 1 or E.QUEUE_LOW
        self.flash:SetAlpha(a)
        self.mini:SetAlpha(a)
    end)
    f.queued:Hide()
    -- In a fight: a small crossed-swords mark at the icon's top left corner
    -- ("it should show a small in-combat icon", 0.35.227).
    f.combat = f.timerLayer:CreateTexture(nil, "OVERLAY")
    f.combat:SetSize(16, 16)
    f.combat:SetPoint("CENTER", f, "TOPLEFT", 1, -1)
    f.combat:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    f.combat:SetTexCoord(0.5, 1.0, 0, 0.484375)
    f.combat:Hide()
    -- The queue (left of the button since 0.35.188; it ran off to the right
    -- before): what your key casts with Ctrl, Shift
    -- and Alt held (Queue.lua; Cast.lua has them set), each a little smaller
    -- than the last, its modifier written above it. Greyed while cooling
    -- down, red out of range; the one Flow advises pulses gold, the one
    -- whose modifier you hold is ringed green.
    f.deck = {}
    local SIZES = { 36, 30, 25, 22 }
    local MODS = { "SHIFT", "CTRL", "ALT", "C+S" }   -- (in Queue.lua's Q.ORDER; C+S: Ctrl and Shift together, "more")
    local prev
    for i, sz in ipairs(SIZES) do
        local d = CreateFrame("Frame", nil, f)
        d:SetSize(sz, sz)
        -- (Out to the LEFT of the big icon, nearest first: CTRL, then SHIFT, then ALT.)
        if prev then d:SetPoint("BOTTOMRIGHT", prev, "BOTTOMLEFT", -6, 0) else d:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -10, 0) end
        d.ring = d:CreateTexture(nil, "BACKGROUND", nil, -2)
        d.ring:SetPoint("TOPLEFT", -3, 3); d.ring:SetPoint("BOTTOMRIGHT", 3, -3)
        d.ring:SetColorTexture(1, 0.82, 0.1, 1)
        d.ring:Hide()
        d.ring.pulse = d.ring:CreateAnimationGroup()
        d.ring.pulse:SetLooping("BOUNCE")
        local ringFade = d.ring.pulse:CreateAnimation("Alpha")
        ringFade:SetFromAlpha(1); ringFade:SetToAlpha(0.25); ringFade:SetDuration(0.4)
        d.back = d:CreateTexture(nil, "BACKGROUND", nil, -1)
        d.back:SetPoint("TOPLEFT", -1, 1); d.back:SetPoint("BOTTOMRIGHT", 1, -1)
        d.back:SetColorTexture(0, 0, 0, 0.85)
        d.tex = d:CreateTexture(nil, "ARTWORK")
        d.tex:SetAllPoints(); d.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        d.timer = d:CreateFontString(nil, "OVERLAY")
        d.timer:SetFont(STANDARD_TEXT_FONT, math.max(9, math.floor(sz * 0.42)), "OUTLINE")
        d.timer:SetPoint("CENTER")
        ns.AddCooldown(d, d.timer)
        d.mod = d:CreateFontString(nil, "OVERLAY")
        d.mod:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(sz * 0.3)), "OUTLINE")
        d.mod:SetPoint("BOTTOM", d, "TOP", 0, 2)
        d.mod:SetText(MODS[i])
        d.mod:SetTextColor(0.85, 0.85, 0.85)
        -- Hover: that spell's (or item's) own tooltip, the press that casts it, and why.
        d:EnableMouse(true)
        d:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            ns.Tip(self, "ANCHOR_BOTTOM")
            local id = e.spell and select(4, A.SpellInfo(e.spell))
            local item = e.item and tonumber(tostring(e.item):match("(%d+)"))
            if id and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(id); GameTooltip:AddLine(" ")
            elseif item and GameTooltip.SetItemByID then GameTooltip:SetItemByID(item); GameTooltip:AddLine(" ") end
            local held = (i == 4) and "CTRL + SHIFT" or MODS[i]
            GameTooltip:AddLine(string.format("%s + your key: %s", held, tostring(e.spell or e.label or "your item")), 1, 0.82, 0)
            if e.reason then GameTooltip:AddLine(e.reason, 1, 1, 1, true) end
            GameTooltip:AddLine("Hold " .. held .. ": the big icon shows it. In a fight it's set at the pull.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        d:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d:Hide()
        f.deck[i] = d
        prev = d
    end
    -- A flash over the big icon when a modifier swaps its spell in.
    f.flash = f.timerLayer:CreateTexture(nil, "OVERLAY")
    f.flash:SetAllPoints(f)
    f.flash:SetColorTexture(1, 1, 1, 1)
    f.flash:SetAlpha(0)
    f.flash.anim = f.flash:CreateAnimationGroup()
    local flashFade = f.flash.anim:CreateAnimation("Alpha")
    flashFade:SetFromAlpha(0.55); flashFade:SetToAlpha(0); flashFade:SetDuration(0.25)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -4)

    -- "SHIFT+" beside the icon while you hold Shift: the icon then shows
    -- what Shift + your key casts (your heal), pulsing so it's noticed.
    f.shiftTag = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- (On the left, right above the modifier names: it says which of them
    -- you're holding. It was to the right of the key's bind for one version.)
    f.shiftTag:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", -10, 0)
    f.shiftTag:SetText("SHIFT+")
    f.shiftTag:SetTextColor(0.4, 1, 0.4)
    f.shiftTag.pulse = f.shiftTag:CreateAnimationGroup()
    f.shiftTag.pulse:SetLooping("BOUNCE")
    local shiftFade = f.shiftTag.pulse:CreateAnimation("Alpha")
    shiftFade:SetFromAlpha(1); shiftFade:SetToAlpha(0.35); shiftFade:SetDuration(0.45)
    f.shiftTag:Hide()

    -- Position and moving are handled by the secure cast button underneath
    -- (Modules/Rotation/Cast.lua): the icon is anchored to it.
    f:EnableMouse(false)
    f:Hide()
    return f
end

-------------------------------------------------------------------------------
-- Action button glow
-------------------------------------------------------------------------------

local function glowFor(btn)
    glows = glows or {}
    local g = glows[btn]
    if g then return g end
    g = CreateFrame("Frame", nil, btn)
    g:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
    g:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
    g:SetFrameStrata(btn:GetFrameStrata())
    g:SetFrameLevel(btn:GetFrameLevel() + 10)
    g.border = makeBorder(g, 3, 3)
    local ag = g:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.45)
    g.anim, g.fade = ag, fade
    g:Hide()
    glows[btn] = g
    return g
end

local function scanButtons()
    wipe(buttonsBySpell); wipe(buttonsByItem)
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do
            local btn = _G[prefix .. i]
            if btn and btn:IsVisible() then
                local slot = btn.action
                if not slot and btn.GetAttribute then slot = btn:GetAttribute("action") end
                if slot and HasAction(slot) then
                    local kind, id = GetActionInfo(slot)
                    if kind == "spell" and id then
                        local name = A.SpellInfo(id)
                        if name then
                            buttonsBySpell[name] = buttonsBySpell[name] or {}
                            table.insert(buttonsBySpell[name], btn)
                            glowFor(btn)  -- build now, out of combat
                        end
                    elseif kind == "item" and id then
                        buttonsByItem[id] = buttonsByItem[id] or {}
                        table.insert(buttonsByItem[id], btn)
                        glowFor(btn)
                    end
                end
            end
        end
    end
    -- Stance bar (paladin auras): button i holds stance form i.
    for _, s in ipairs(A.StanceSpells()) do
        local btn = _G["StanceButton" .. s.index] or _G["ShapeshiftButton" .. s.index]
        if btn and btn:IsVisible() then
            buttonsBySpell[s.name] = buttonsBySpell[s.name] or {}
            table.insert(buttonsBySpell[s.name], btn)
            glowFor(btn)
        end
    end
end

-------------------------------------------------------------------------------
-- A swing spell queued (0.35.318): Maul (or Heroic Strike...) goes off on
-- your next swing, not at the press. While it waits, the target button
-- blinks red, as the game's action bar does. The spells are the class's
-- (`nextSwing` in its rotation registration, Classes/<Class>/Rotation.lua).
-------------------------------------------------------------------------------

E.QUEUE_BLINK = 0.4   -- seconds on, then off (the action bar's beat)
E.QUEUE_LOW = 0.2     -- how faint it gets between blinks

-- Pure: the first of these spells that's waiting for your swing, or nil.
--   isCurrent(spell) -> true while it's queued (A.IsCurrent)
function E.QueuedSpell(list, isCurrent)
    for _, spell in ipairs(list or {}) do
        if isCurrent(spell) then return spell end
    end
    return nil
end

-- Shows or puts away the red blink. shown: the spell the button shows now.
function E.UpdateQueued(shown)
    local q = icon and icon.queued
    if not q then return nil end
    local _, class = UnitClass("player")
    local rot = class and ns:Get("rotation", class)
    local spell = (rot and rot.nextSwing) and E.QueuedSpell(rot.nextSwing, A.IsCurrent) or nil
    E.queued = spell
    if spell and icon:IsShown() then
        if not q:IsShown() then
            q.t, q.on = 0, true
            q.flash:SetAlpha(1)
            q.mini:SetAlpha(1)
            q:Show()
        end
        local _, tex = A.SpellInfo(spell)
        q.mini:SetTexture(tex)
        q.mini:SetShown(tex ~= nil and spell ~= shown)
    elseif q:IsShown() then
        q:Hide()
    end
    return spell
end

local function clearGlows()
    if not glows then return end
    for _, g in pairs(glows) do
        ns.pulse.Remove(g)
        g:Hide()
    end
end

-- Is this item on one of your action bars? (In a fight the key is locked, so
-- an item is only worth suggesting where you can press it: BuffItems.lua.)
function ns.ItemOnBar(id)
    local list = id and buttonsByItem[tonumber(id)]
    return list ~= nil and #list > 0
end

-- The buttons holding a suggestion: its spell, or its item.
local function buttonsOf(s)
    if s.spell then return buttonsBySpell[s.spell] or {} end
    local id = s.item and tonumber(tostring(s.item):match("(%d+)"))
    return id and buttonsByItem[id] or {}
end

local function showGlows(s, color, kind)
    clearGlows()
    for _, btn in ipairs(buttonsOf(s)) do
        local g = glowFor(btn)
        -- One colour and one beat for everything Flow suggests (Pulse.lua).
        local c = ns.pulse.COLOR
        g.border:SetColor(c[1], c[2], c[3])
        g:Show()
        ns.pulse.Add(g)
    end
end

-------------------------------------------------------------------------------
-- Update loop
-------------------------------------------------------------------------------


-- Cooldown of what the button does: a spell, or an item (a lure, a recipe).
-- (BuffButton.lua draws its own sweep the same way: ns.SetCooldownFrame, set below.)
local function cooldownOf(s)
    if s.spell then return A.CooldownRaw(s.spell) end
    local id = s.item and tonumber(tostring(s.item):match("(%d+)"))
    if id then
        local get = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
        if get then
            local ok, start, dur = pcall(get, id)
            if ok then return start, dur end
        end
    end
    return 0, 0
end

-- The cooldown sweep on the icon. WoW: Forever hides spell cooldowns from
-- add-ons in fights ("secret" values: A.CooldownRaw turns them into 0, so the
-- button showed no cooldown at all). The cooldown frame itself can still
-- draw them: from the game's duration object where the client has one, else
-- from the hidden values as they are. Then the game's own countdown numbers
-- go on (Flow can't count down a hidden time). Returns how it drew it, for
-- the diagnostics: "readable", "duration", "hidden" or "none".
local function setCooldown(cd, s)
    local start, dur = cooldownOf(s)
    local readable = (start or 0) > 0 and (dur or 0) > 0
    if s.spell and not readable then
        local CS = C_Spell
        if CS and CS.GetSpellCooldownDuration and cd.SetCooldownFromDurationObject then
            local ok, d = pcall(CS.GetSpellCooldownDuration, s.spell)
            if ok and d and pcall(cd.SetCooldownFromDurationObject, cd, d, true) then
                if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
                return "duration", 0, 0
            end
        end
        local c = CS and CS.GetSpellCooldown and CS.GetSpellCooldown(s.spell)
        local rs, rd = c and c.startTime, c and c.duration
        if rs ~= nil and A.Safe(rs) == nil and pcall(cd.SetCooldown, cd, rs, rd) then
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
            return "hidden", 0, 0
        end
    end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end   -- Flow's own timer
    cd:SetCooldown(start or 0, dur or 0)
    return readable and "readable" or "none", start, dur
end
ns.SetCooldownFrame = setCooldown   -- (the self button's sweep: BuffButton.lua)

-- Like an action button: grey when you can't cast it now (not enough mana,
-- or the game says it isn't usable), red when your target is out of its
-- range, else as it is. Unknown (nil) never greys it out.
function ns.ButtonTint(usable, noMana, inRange)
    if noMana == true or usable == false then return "grey" end
    if inRange == false then return "red" end
    return nil
end
local TINT = { grey = { 0.55, 0.55, 0.55, true }, red = { 1, 0.35, 0.35, false } }
local function tintOf(s)
    if not (s and s.spell) or s.kind == "held" then return nil end
    local usable, noMana = A.Usable(s.spell)
    local inRange
    local onYou = ns.cast and ns.cast.UnitFor and ns.cast.UnitFor(s)
    if not onYou and UnitExists("target") and UnitCanAttack("player", "target") then
        inRange = A.InRange(s.spell, "target")
    end
    return ns.ButtonTint(usable, noMana, inRange), noMana == true
end

-- Out of mana for it: about how long until you have enough (Yang: a timer
-- for that too, like a cooldown's). Seconds, or nil when Flow can't tell
-- (mana hidden in a fight, no regeneration) or you have enough.
function ns.ManaWaitSeconds(cost, mana, regen)
    if not (cost and mana and regen) or regen <= 0 or mana >= cost then return nil end
    return math.ceil((cost - mana) / regen)
end
function ns.ManaWait(spell)
    local cost
    local get = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    local ok, costs = pcall(get, spell)
    for _, c in ipairs(ok and type(costs) == "table" and costs or {}) do
        if c.type == 0 or c.name == "MANA" then cost = A.Safe(c.cost) end
    end
    local mana = A.Safe(UnitPower("player", 0))
    local okR, idle = pcall(GetPowerRegen)
    return ns.ManaWaitSeconds(cost, mana, okR and A.Safe(idle) or nil)
end

-- The timer's text for a cooldown: "" when ready or only the global
-- cooldown; "1m" / "12" / "4.2" otherwise.
local GCD = 1.6
function ns.CooldownText(start, dur, now)
    start, dur = ns.api.Safe(start), ns.api.Safe(dur)
    if not (start and dur) or start == 0 or dur <= GCD then return "" end
    local left = start + dur - now
    if left <= 0 then return "" end
    if left >= 60 then return string.format("%dm", math.ceil(left / 60)) end
    if left >= 10 then return string.format("%d", math.floor(left + 0.5)) end
    return string.format("%.1f", left)
end

-- A small icon's status (0.35.273): "each of the icons next to the easy
-- button should show the cooldown if it's been cast, and any other status,
-- like if it can't be cast." Flow's own modifier icons had this for spells;
-- the self button's icons had none, and items (a potion, a bandage) had no
-- cooldown on either. One function for all of them:
--   -> the timer's text, and the tint ({ r, g, b, grey? } or nil: as it is)
function ns.StepStatus(s, now)
    if not s then return "", nil end
    local txt = ""
    if s.spell then
        local start, dur = A.CooldownRaw(s.spell)
        txt = ns.CooldownText(start, dur, now)
    elseif s.item then
        local id = tonumber(tostring(s.item):match("(%d+)"))
        local get = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
        if id and get then
            local ok, start, dur = pcall(get, id)
            if ok then txt = ns.CooldownText(start, dur, now) end
        end
        -- (None left in your bags: it can't be used.)
        if id and A.Count and A.Count(id) == 0 then return txt, TINT.grey end
    end
    local okT, tint = pcall(tintOf, s)
    return txt, okT and TINT[tint] or nil
end
-- Pure: did the game draw the countdown itself (from a time Flow can't read)?
function ns.GameCounts(how) return how == "duration" or how == "hidden" end
-- A small icon's cooldown frame, with the icon's own timer text kept on top of it.
function ns.AddCooldown(icon, timer)
    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    icon.cd = cd
    if timer then
        local host = CreateFrame("Frame", nil, icon)
        host:SetAllPoints()
        host:SetFrameLevel(cd:GetFrameLevel() + 2)
        timer:SetParent(host)
        icon.timerHost = host
    end
    return cd
end
-- Pure: how the picture is drawn for a status: grey it? and its colour.
function ns.StatusLook(txt, tv)
    local grey = (txt ~= "" or (tv ~= nil and tv[4] == true)) and true or false
    if tv then return grey, tv[1], tv[2], tv[3] end
    return grey, 1, 1, 1
end
-- Puts a step's status on an icon's picture and its timer text.
-- cd: the icon's cooldown frame (0.35.288). In a fight the game hides
-- cooldown times from add-ons, so Flow's own number has nothing to count:
-- the small icons showed no cooldown at all there. The game's cooldown frame
-- can still draw a hidden time (the sweep, and its own countdown number), as
-- Flow's big icon does: each small icon has one now.
function ns.PaintStatus(tex, timer, s, now, cd)
    local txt, tv = ns.StepStatus(s, now)
    if cd and s then
        local ok, how = pcall(setCooldown, cd, s)
        -- (Drawn by the game from a hidden time: its number is the timer.)
        if ok and ns.GameCounts(how) then txt = "" end
        if not ok then pcall(cd.SetCooldown, cd, 0, 0) end
    end
    if timer then timer:SetText(txt) end
    local grey, r, g, b = ns.StatusLook(txt, tv)
    tex:SetDesaturated(grey)
    tex:SetVertexColor(r, g, b)
    return txt, tv
end

-- The buff timer: when Flow suggests re-casting a buff that's still on but
-- running out, the seconds it has left (under 30), in aqua (BUFF_TIMER: the
-- mana wait is blue). "" when it's gone, lasts longer, or never runs out.
local BUFF_SHOW = 30
local BUFF_TIMER = { 0.55, 1.0, 0.85 }
function ns.BuffTimerText(left)
    left = ns.api.Safe(left)
    if type(left) ~= "number" or left <= 0 or left >= BUFF_SHOW then return "" end
    if left >= 10 then return string.format("%d", math.floor(left + 0.5)) end
    return string.format("%.1f", left)
end

-- Seconds left on the buff a suggestion re-casts (on whoever it's for).
local function buffLeft(s)
    if s.kind ~= "buff" or not s.spell then return nil end
    local ok, up, left = pcall(A.Buff, s.unit or "player", s.spell)
    if ok and up then return left end
    return nil
end

-- Border for a Flow Action (equip the pole, make a campfire...): not the
-- route purple, which reads as "epic item". Spells use the spell colour
-- (light blue, like buffs); items their own quality colour (white, green...).
local function actionColor(s)
    local id = s.item and tonumber(tostring(s.item):match("(%d+)"))
    if id then
        local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
        local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if c then return { c.r, c.g, c.b } end
        return { 1, 1, 1 }
    end
    if s.type == "interact" or s.type == "clear" or s.type == "click" or s.type == "sit" or s.type == "wait" then return { 0.85, 0.85, 0.85 } end
    return COLORS.buff
end
ns.ActionColor = actionColor  -- (tests)
-- What the icon shows: what a press of your key casts now.
--   s: the advice; held: what the key was set to at the pull (in a fight it
--   can't change). In a fight, when the advice is something else, the icon
--   shows the held spell and the advice goes to the corner (press it on your
--   bar, or Shift + key for your heal). Returns view, advice.
function ns.KeyView(s, held, inCombat)
    if not (inCombat and held) then return s, nil end
    if s and s.spell == held.spell then return s, nil end
    if not s then return held, nil end   -- (nothing new to press: greyed, as before)
    return { spell = held.spell, kind = "key", label = held.label, held = true }, s
end
-- The words over Flow's icon (0.35.287). While you hold a modifier it used
-- to read "CTRL + key: Moonfire" there; the modifier is already written by
-- the key bind ("CTRL +"), and the picture says the spell, so that line is
-- gone. A Flow Action still says what the press does, and a buff for
-- someone says who it's for. Pure:
-- 0.35.292: the spell's name is always there ("the title of the target spell
-- is not always shown above it as I expect it to always be, and update if a
-- modifier is pressed"): what the press casts now, by name; while you hold a
-- modifier, that modifier's spell (without "CTRL + key:" in front, which
-- the key bind already says). Who it's for follows the name.
function ns.IconWords(s, debug)
    if not s then return "" end
    local name
    if s.mod or s.shift then
        name = s.words or s.spell
    else
        name = s.label or s.spell
    end
    local who = s.target and ("on " .. s.target) or nil
    if name and who then return name .. " " .. who end
    return name or who or (debug and s.reason) or ""
end

-- Holding Shift: Shift + your key's spell (your heal) swaps in, while the
-- key would do anything at all (the button is there: in a fight, or with
-- something to press).
function ns.ShiftView(view, healSpell, shiftDown, inCombat)
    if not (healSpell and shiftDown and (view or inCombat)) then return view, false end
    return { spell = healSpell, kind = "heal", label = "Shift + key: " .. healSpell, words = healSpell, shift = true }, true
end

-- Is the self button set to dock under Flow's icon (and switched on)? Then
-- Flow's own labels take their docked places.
function ns.DockLayout()
    local BB = ns.buffButton
    return (BB ~= nil and BB.Docked ~= nil and BB.Docked() and BB.On()) and true or false
end

-- Is the self button docked under Flow's icon and showing, with its own
-- modifier icons (CareKeys.lua)? Then the two are drawn as one block.
function ns.DockedNow()
    local BB, K = ns.buffButton, ns.careKeys
    return (BB ~= nil and BB.Docked ~= nil and BB.Docked() and BB.On() and BB.Shown()
        and K ~= nil and K.Active ~= nil and K.Active()) and true or false
end

-- Docked: the auto-attack badge is as tall as the key bind's letters and
-- sits at the icon's bottom right, under the bind ("CTRL +" over "Q / MB5"
-- over the badge, 0.35.239). On its own: 24 wide, at the middle of the right.
ns.SWING_SIZE, ns.SWING_DOCKED = 24, 14
-- Which way a button's small icons run (0.35.324): "if we move them to the
-- right, they should go off to the right; on the left-hand side of the
-- screen, off to the left." A button in the right half of the screen has its
-- modifier icons to its right, biggest nearest, bottoms level; in the left
-- half, to its left. What sat on the other side (the key's name when docked,
-- the auto-attack badge) swaps over, so nothing lies under the icons.
-- Docked, the self button follows the target button's side: one mirrored
-- block. On their own, each button goes by where it is.
-- Pure: "left" or "right" for a button whose middle is at centerX.
function ns.SideFor(centerX, screenW)
    if not (centerX and screenW) then return "left" end
    return centerX > screenW / 2 and "right" or "left"
end
function ns.ButtonSide(frame)
    if not (frame and frame.GetCenter) then return "left" end
    local x = frame:GetCenter()
    if not x then return "left" end
    return ns.SideFor(x * (frame:GetEffectiveScale() or 1), (UIParent:GetWidth() or 0) * (UIParent:GetEffectiveScale() or 1))
end
-- The self button's side: the target button's when docked to it.
function ns.SelfSide()
    local BB = ns.buffButton
    if BB and BB.Docked and BB.Docked() and E.icon then return ns.ButtonSide(E.icon) end
    return ns.ButtonSide(_G.FlowBuffButton)
end
-- The target button's small icons, out to `side`, nearest first.
function ns.PlaceDeck(icon, side)
    local prev
    for _, d in ipairs(icon and icon.deck or {}) do
        d:ClearAllPoints()
        if side == "right" then
            if prev then d:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", 6, 0) else d:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 0) end
        else
            if prev then d:SetPoint("BOTTOMRIGHT", prev, "BOTTOMLEFT", -6, 0) else d:SetPoint("BOTTOMRIGHT", icon, "BOTTOMLEFT", -10, 0) end
        end
        prev = d
    end
end
-- (side: the side the small icons run to; the badge sits on the other.)
function ns.SwingPlace(joined, side)
    if side == "right" then
        if joined then return ns.SWING_DOCKED, "BOTTOMRIGHT", "BOTTOMLEFT", -6, 0 end
        return ns.SWING_SIZE, "RIGHT", "LEFT", -8, 0
    end
    if joined then return ns.SWING_DOCKED, "BOTTOMLEFT", "BOTTOMRIGHT", 6, 0 end
    return ns.SWING_SIZE, "LEFT", "RIGHT", 8, 0
end
function ns.PlaceSwing(frame, anchor, joined, side)
    local size, point, rel, x, y = ns.SwingPlace(joined, side)
    frame.side = side or "left"
    frame:ClearAllPoints()
    frame:SetSize(size, size)
    frame:SetPoint(point, anchor, rel, x, y)
    frame.joined = joined and true or false
end
-- Pure: the held modifier's tag: "CTRL +" on its own line above the bind
-- when docked; "CTRL+" on the bind's line otherwise.
function ns.ModTag(name, joined)
    if joined then return name .. " +" end
    return (name:gsub(" ", "")) .. "+"
end

-- The auto-attack badge: how far its pulsing ring stands out past the badge
-- (past the weapon-coloured edge, which is 2), and how dim the badge is when
-- auto attack is off.
ns.SWING_RING, ns.SWING_OFF_ALPHA = 4, 0.4
-- The game's own highlight for a button that's switched on (the action bar's
-- Attack while you swing): a glow inside the border that fades inward.
ns.SWING_CHECKED = "Interface\\Buttons\\CheckButtonHilight"
-- Pure: does the badge's ring pulse? Only while auto attack is on.
function ns.SwingPulses(badge) return badge == "on" end
-- Pure: the badge's picture: the game's own for Attack (it follows your
-- shape), else the weapon in your main hand, else nil (as it is).
function ns.SwingPicture(attackTexture, weaponTexture)
    return attackTexture or weaponTexture or nil
end
-- Pure: which of the game's answers to use: the bar slot's picture when
-- Attack is on a bar (exactly what the action bar shows), else the spell's.
function ns.AttackPicture(slotTexture, spellTexture)
    return slotTexture or spellTexture or nil
end
-- The game's picture for Attack now. Where Attack sits on your bars is
-- looked up at most every few seconds (120 slots); its picture each time.
local attackSlot, attackSlotAt
function ns.AttackTexture(now)
    local S = ns.clickSlots
    if S and S.AttackSlot and (not attackSlotAt or now - attackSlotAt > 3) then
        attackSlotAt = now
        local ok, slot = pcall(S.AttackSlot)
        attackSlot = ok and slot or nil
    end
    local slotTex
    if attackSlot and GetActionTexture then
        local ok, tex = pcall(GetActionTexture, attackSlot)
        slotTex = ok and A.Safe(tex) or nil
    end
    local spellTex
    if not slotTex then
        local spell = S and S.AttackSpell and S.AttackSpell() or nil
        spellTex = spell and select(2, A.SpellInfo(spell)) or nil
    end
    return ns.AttackPicture(slotTex, spellTex)
end
-- Pure: the edge's colour for an item quality (nil: none worn, no edge).
--   colors: the game's table, { [quality] = { r, g, b } }
function ns.QualityColor(quality, colors)
    local c = quality and colors and colors[quality]
    if not c then return 0, 0, 0, 0 end
    return c.r or 1, c.g or 1, c.b or 1, 1
end
-- Pure: the auto-attack badge beside the icon: "on" while you swing, "off"
-- (dim) in a fight or with an enemy targeted while you don't, nil otherwise.
function ns.SwingBadge(shown, swinging, inCombat, hostile)
    if not shown then return nil end
    if swinging then return "on" end
    if inCombat or hostile then return "off" end
    return nil
end

-- The tag beside the icon: "held" while Shift is down (the icon shows what
-- Shift + key casts); "press" while Flow advises a heal in a fight that your
-- key can't cast (it's locked to another spell) and Shift + key heals.
-- (Death 6: a heal advised 65 times in 80 s, Shift + key pressed 0 times;
-- the small corner icon wasn't enough to say "Shift heals".)
function ns.ShiftCue(advice, healSpell, shifted, inCombat)
    if shifted then return "held" end
    if inCombat and healSpell and advice and (advice.kind == "heal" or advice.kind == "emergency") then return "press" end
    return nil
end

local function render(s, cfg, glow)
    -- New to Flow: the icon comes in at your first enemy (Reveal.lua). The
    -- key still casts the suggestion meanwhile.
    if ns.reveal and not ns.reveal:Shown("icon") then
        current = nil
        clearGlows()
        icon:Hide()
        return
    end
    if not s then
        current = nil
        clearGlows()
        if cfg.locked then icon:Hide() else
            icon.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            icon.text:SetText("Ctrl-drag me")
            icon:Show()
        end
        return
    end

    local color = COLORS[s.kind] or actionColor(s)
    local tex = s.icon
    if not tex and s.spell then tex = select(2, A.SpellInfo(s.spell)) end
    icon.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon.border:SetColor(color[1], color[2], color[3])
    -- Flow Actions always say what the press does ("Equip your Fishing Pole").
    -- A buff for someone in your group says who it's for.
    icon.text:SetText(ns.IconWords(s, cfg.debug))
    local how, start, dur = setCooldown(icon.cd, s)
    E.cooldownShown = how
    icon.timer:SetTextColor(1, 0.95, 0.7)
    icon.timer:SetText(ns.CooldownText(start, dur, GetTime()))
    -- Grey: can't cast it now (mana, or not usable); red: out of range.
    local okT, tint, oom = pcall(tintOf, s)
    local tv = okT and TINT[tint]
    E.buttonTint = okT and tint or nil
    -- Waiting for mana (no cooldown to count down): about how long, in blue.
    if okT and oom and (icon.timer:GetText() or "") == "" then
        local okW, wait = pcall(ns.ManaWait, s.spell)
        if okW and wait then
            icon.timer:SetText("|cff7fb2ff" .. (wait >= 60 and string.format("%dm", math.ceil(wait / 60)) or tostring(wait)) .. "|r")
        end
    end
    -- A buff Flow suggests re-casting while it's still on: its last 30
    -- seconds, in aqua (not the mana blue). Only when nothing else counts
    -- down there, the game's own cooldown numbers included.
    -- Counting down to Well Fed while you eat (E.WellFedView): aqua seconds.
    if s.countdown then
        icon.timer:SetTextColor(BUFF_TIMER[1], BUFF_TIMER[2], BUFF_TIMER[3])
        icon.timer:SetText(tostring(math.ceil(s.countdown)))
    elseif how == "none" and (icon.timer:GetText() or "") == "" then
        local bt = ns.BuffTimerText(buffLeft(s))
        if bt ~= "" then
            icon.timer:SetTextColor(BUFF_TIMER[1], BUFF_TIMER[2], BUFF_TIMER[3])
            icon.timer:SetText(bt)
        end
    end
    icon.tex:SetDesaturated(tv and tv[4] or (s.kind == "held"))
    if tv then icon.tex:SetVertexColor(tv[1], tv[2], tv[3])
    elseif s.kind == "held" then icon.tex:SetVertexColor(0.7, 0.7, 0.7)
    else icon.tex:SetVertexColor(1, 1, 1) end
    -- What it's waiting for: a bar of your mana, rage or energy against its cost (PowerBar.lua).
    if ns.PaintPower then pcall(ns.PaintPower, icon, s) end
    icon:Show()

    -- What lights up on your action bars: `glow`, the advice (in a fight,
    -- the spell to press on your bar while the icon shows the key's).
    local key = tostring(s.spell or s.item or s.type) .. s.kind .. "|" .. tostring(glow and (glow.spell or glow.item))
    if key ~= current then
        current = key
        -- (A held spell isn't advice: no glow on your action bars.)
        if glow and (glow.spell or glow.item) and glow.kind ~= "held" and glow.kind ~= "key" then
            showGlows(glow, COLORS[glow.kind] or actionColor(glow), glow.kind)
        else
            clearGlows()
        end
    end
end

-------------------------------------------------------------------------------
-- The queue's icons (beside the button): see Queue.lua.
-------------------------------------------------------------------------------
local EMPTY = {}

-- A step's icon: its own, its spell's, or its item's.
local function stepIcon(s)
    if s.icon then return s.icon end
    if s.spell then
        local _, tex = A.SpellInfo(s.spell)
        return tex
    end
    local id = s.item and tonumber(tostring(s.item):match("(%d+)"))
    return id and A.ItemIcon and A.ItemIcon(id) or nil
end

-- Would this slot only repeat the big icon? The same item, or the same
-- spell (the same heal on Shift as on the key). Not "the same on your
-- target": that's a different press.
function ns.QueueDup(e, view)
    if not (e and view) then return false end
    if e.item then return e.item == view.item end
    if not e.spell or e.spell ~= view.spell then return false end
    return not (e.unit == "target" and e.kind ~= "damage")
end

-- One slot's icon, cooldown, tint and ring. state: "advised" (Flow says
-- press it now: gold, pulsing), "held" (its modifier is down: green), nil.
local function drawSlot(slot, e, now, state)
    slot.tex:SetTexture(stepIcon(e) or "Interface\\Icons\\INV_Misc_QuestionMark")
    -- Its cooldown; grey: cooling down, can't be cast now, or none left; red: out of range.
    ns.PaintStatus(slot.tex, slot.timer, e, now, slot.cd)
    if state ~= slot.state then
        slot.state = state
        if state == "advised" then
            local c = ns.pulse.COLOR
            slot.ring:SetColorTexture(c[1], c[2], c[3], 1); slot.ring:Show(); ns.pulse.Add(slot.ring)
            slot.mod:SetTextColor(c[1], c[2], c[3])
        elseif state == "held" then
            ns.pulse.Remove(slot.ring); slot.ring:SetColorTexture(0.4, 1, 0.4, 1); slot.ring:Show()
            slot.mod:SetTextColor(0.4, 1, 0.4)
        else
            ns.pulse.Remove(slot.ring); slot.ring:Hide()
            slot.mod:SetTextColor(0.85, 0.85, 0.85)
        end
    end
end

-- Timed apart for /flow perf, so a slow tick says which part costs: picking
-- the spell, Flow Actions, or showing it on the key ("rotation: showing it").
-- (They look E.Evaluate and ns.actions up at each call: Actions.lua loads
-- after this file, and tests stand in for both.)
local timedEvaluate = ns.perf.Wrap("rotation: choosing the spell", function() return E:Evaluate() end)
local timedActions = ns.perf.Wrap("flow actions", function() return ns.actions:Current() end)

local elapsed = 0
-- Ten times a second (the frame-by-frame wait is outside the timing, so
-- /flow perf counts real ticks).
local function tick()
    local cfg = ns.db.rotation
    if not cfg.enabled then
        E.shown = nil
        if icon:IsShown() then icon:Hide(); clearGlows(); current = nil end
        return
    end

    local ok, s = pcall(timedEvaluate)
    if not ok then
        -- Keep the error for /flow rot why; print it at most every 5s in debug.
        local now = GetTime()
        if cfg.debug and s ~= E.lastError and now - (E.lastErrorAt or 0) > 5 then
            ns:Print("rotation error: " .. tostring(s))
        end
        if s ~= E.lastError then ns:Log("rotation", s) end
        E.lastError, E.lastErrorAt = s, now
        s = nil
    end
    -- Out of combat, a Flow Action (equip the pole, cast Fishing...) when
    -- there's no spell to suggest, or before it when it's urgent (reel in).
    if not InCombatLockdown() and ns.actions then
        local okA, a = pcall(timedActions)
        if okA and a and (a.urgent or not s) then s = a end
    end
    E.shown = s   -- what the key does out of a fight (Cast.lua sets it)
    -- The icon shows what a press of your key casts now (ns.KeyView): in a
    -- fight, what it was set to at the pull, with the advice it can't do in
    -- the corner (E.advice, Cast.lua: press it on your bar, where it glows).
    -- Mid-fight with nothing new to press: the held spell, greyed.
    local inCombat = InCombatLockdown()
    local held = inCombat and ns.cast and ns.cast.Held and ns.cast:Held() or nil
    local view, advice = ns.KeyView(s, held, inCombat)
    E.advice = advice
    -- Eating Well Fed food the key gave you: count down to the buff (shown
    -- only; the key keeps doing what it does).
    E.NoteKeyShown(s, GetTime())
    if not inCombat and (not s or s.wellFed) and E.WellFedWatch(GetTime()) then
        local okF, fed = pcall(E.WellFedView, GetTime())
        if okF and fed then view = fed end
    end
    -- The queue: what Ctrl, Shift and Alt + your key cast (Cast.lua has them
    -- set; Queue.lua decides). Holding one swaps its spell into the big
    -- icon, with the modifier's name beside it ("CTRL+").
    local Q = ns.queue
    local slots = ns.cast and ns.cast.Slots and ns.cast:Slots() or EMPTY
    local mod = Q and Q.HeldMod(IsControlKeyDown(), IsShiftKeyDown(), IsAltKeyDown()) or nil
    local swapped
    if Q then view, swapped = Q.ModView(view, slots, mod, inCombat) end
    if swapped and not view.icon then view.icon = stepIcon(view) end
    -- Which press does what Flow advises now (in a fight): its slot pulses,
    -- and the corner icon stays away (Cast.lua).
    E.adviceSlot = (inCombat and advice and Q) and Q.AdviceSlot(advice, slots) or nil
    -- The tag beside the icon: the modifier you hold, in green; or "Heal:
    -- SHIFT+" in gold while Flow advises a heal in a fight and your key
    -- holds another spell (ns.ShiftCue).
    local healSpell = ns.cast and ns.cast.HealSpell and ns.cast:HealSpell()
    local cue = ns.ShiftCue(advice, healSpell, swapped ~= nil, inCombat)
    local tag = (swapped and ns.ModTag(Q.NAME[swapped], icon.joined)) or (cue == "press" and "Heal: SHIFT+") or nil
    if tag ~= icon.shiftTag.cue then
        icon.shiftTag.cue = tag
        icon.shiftTag:SetShown(tag ~= nil)
        if tag then
            icon.shiftTag:SetText(tag)
            -- (Held: steady green. A heal to press: the suggestion's orange, on the beat.)
            if swapped then
                icon.shiftTag:SetTextColor(0.4, 1, 0.4)
                ns.pulse.Remove(icon.shiftTag)
            else
                local c = ns.pulse.COLOR
                icon.shiftTag:SetTextColor(c[1], c[2], c[3])
                ns.pulse.Add(icon.shiftTag)
            end
        else
            ns.pulse.Remove(icon.shiftTag)
        end
    end
    -- A flash when a modifier swaps a spell in: the big icon became it.
    if swapped ~= icon.swapped then
        icon.swapped = swapped
        if swapped then icon.flash.anim:Stop(); icon.flash.anim:Play() end
    end
    -- What the big icon shows, for the press audit (Audit.lua): the spell or
    -- item, or nil when a modifier has swapped another in or it counts down.
    E.iconShows = (view and not swapped and not view.countdown) and (view.spell or view.item) or nil
    local okR, err = pcall(render, view, cfg, advice or (not swapped and view) or nil)
    if not okR then E.lastError, E.lastErrorAt = "display: " .. tostring(err), GetTime() end
    pcall(E.UpdateQueued, view and view.spell)
    -- Swords badge while auto attack is on.
    -- (Also there, dim, in a fight or with an enemy targeted while it's off:
    -- so there's something to point at and click, 0.35.227.)
    local swinging = icon:IsShown() and A.Swinging()
    local badge = ns.SwingBadge(icon:IsShown(), swinging, inCombat, E.lastCtx and E.lastCtx.hostile)
    if badge ~= icon.swingState then
        icon.swingState = badge
        icon.swing:SetShown(badge ~= nil)
        local live = ns.SwingPulses(badge)
        icon.swing.glow:SetShown(live)
        if live then ns.pulse.Add(icon.swing.glow) else ns.pulse.Remove(icon.swing.glow) end
        if badge == "on" then icon.swing:SetAlpha(1)
        elseif badge == "off" then icon.swing:SetAlpha(ns.SWING_OFF_ALPHA) end
    end
    local fighting = icon:IsShown() and inCombat and true or false
    if fighting ~= icon.combat:IsShown() then icon.combat:SetShown(fighting) end
    -- The badge wears the weapon in your main hand ("can the auto-attack icon
    -- show the currently equipped weapon", 0.35.228).
    -- The game's own picture for Attack comes first (0.35.338): on your
    -- action bar it changes with your shape (your weapon as yourself, the
    -- cat's or the bear's own attack in a form), and the badge shows the
    -- same. (0.35.327 used Claw's and Maul's pictures for a cat and a bear:
    -- as a cat that's the very picture on the target button, so the badge
    -- looked like a second copy of it. "Why does the auto attack show my
    -- target icon instead of the auto attack icon for that form?")
    local weapon = GetInventoryItemTexture and A.Safe(GetInventoryItemTexture("player", 16)) or nil
    local attack = ns.AttackTexture(GetTime())
    local art = ns.SwingPicture(attack, weapon)
    if art and art ~= icon.swing.weapon then
        icon.swing.weapon = art
        icon.swing.tex:SetTexture(art)
    end
    local quality = GetInventoryItemQuality and A.Safe(GetInventoryItemQuality("player", 16)) or nil
    if quality ~= icon.swing.quality or icon.swing.edgeSet == nil then
        icon.swing.quality, icon.swing.edgeSet = quality, true
        icon.swing.edge:SetColorTexture(ns.QualityColor(quality, _G.ITEM_QUALITY_COLORS))
    end
    -- The self button docked under this icon (BuffButton.lua): this icon's
    -- spell name goes below both, and the modifier names are written once,
    -- between the rows (the self button's own).
    local docked = ns.DockedNow()
    if docked ~= icon.docked then
        icon.docked = docked
        for _, d in ipairs(icon.deck) do d.mod:SetShown(not docked) end
    end
    -- Docked (the setting, whether or not the self button shows right now, so
    -- nothing jumps about): this icon's spell name above it, its key at its
    -- bottom right. On its own: as it always was (name below, key above).
    local joined = ns.DockLayout()
    -- (Which way the small icons run: by the half of the screen it's in.
    -- Looked at out of a fight; a button isn't dragged across the screen in one.)
    local side = icon.side or "left"
    if not inCombat or not icon.side then side = ns.ButtonSide(icon) end
    if joined ~= icon.joined or side ~= icon.side then
        icon.joined, icon.side = joined, side
        ns.PlaceDeck(icon, side)
        icon.text:ClearAllPoints()
        if joined then
            -- (Its name starts over the corner away from the small icons.)
            if side == "right" then
                icon.text:SetPoint("BOTTOMRIGHT", icon, "TOPRIGHT", 0, 2)
                icon.text:SetJustifyH("RIGHT")
            else
                icon.text:SetPoint("BOTTOMLEFT", icon, "TOPLEFT", 0, 2)
                icon.text:SetJustifyH("LEFT")
            end
        else
            icon.text:SetPoint("TOP", icon, "BOTTOM", 0, -4)
            icon.text:SetJustifyH("CENTER")
        end
        if ns.cast and ns.cast.LayoutLabels then ns.cast.LayoutLabels(joined, side) end
        if icon.swing then ns.PlaceSwing(icon.swing, icon, joined, side) end
    end
    -- The queue's three icons: in a fight, with an enemy targeted, while you
    -- heal up, or while you hold a modifier (Q.Shows).
    local ctx = E.lastCtx
    local show = icon:IsShown() and cfg.deck ~= false and Q ~= nil
        and Q.Shows(s, inCombat, ctx and ctx.hostile, mod)
    local now = GetTime()
    for i, slot in ipairs(icon.deck) do
        local name = Q and Q.ORDER[i]
        local e = show and slots[name] or nil
        -- (Not twice: a slot that casts what the big icon already shows.)
        if e and swapped ~= name and ns.QueueDup(e, view) then e = nil end
        slot.entry = e
        if e then
            local okS, errS = pcall(drawSlot, slot, e, now, (swapped == name and "held") or (E.adviceSlot == name and "advised") or nil)
            if not okS then E.lastError, E.lastErrorAt = "queue icon: " .. tostring(errS), GetTime() end
            slot:Show()
        else
            if slot.state then ns.pulse.Remove(slot.ring); slot.ring:Hide(); slot.state = nil end
            slot:Hide()
        end
    end
end

-------------------------------------------------------------------------------
-- Status icons: a small row above Flow's icon for things to sort out between
-- fights (worn gear, what your group can add to the camp...), instead of
-- chat lines. Hidden in fights. Hover one: what it means; click: its fix.
-- ns:Register("status", key, { order = n, get = function() return
--     { icon = tex, text = "25%", color = { r, g, b }, tip = "...", click = fn } end })
-------------------------------------------------------------------------------

local PIP = 20
local pips = {}

-- The status entries to show now, in order: { key, icon, text, color, tip, click }.
function E.StatusList()
    local out = {}
    for key, def in ns:Each("status") do
        local ok, st = pcall(def.get)
        if ok and type(st) == "table" then
            st.key, st.order = key, def.order or 50
            out[#out + 1] = st
        end
    end
    table.sort(out, function(a, b) return a.order < b.order end)
    return out
end

local function pipAt(i)
    if pips[i] then return pips[i] end
    local p = CreateFrame("Button", nil, UIParent)
    p:SetSize(PIP, PIP)
    p:SetFrameStrata("MEDIUM")   -- (under the game's own windows: the game menu, Settings; 0.35.163)
    p:SetPoint("BOTTOMLEFT", icon, "TOPLEFT", (i - 1) * (PIP + 4), 6)
    p.back = p:CreateTexture(nil, "BACKGROUND")
    p.back:SetPoint("TOPLEFT", -1, 1); p.back:SetPoint("BOTTOMRIGHT", 1, -1)
    p.tex = p:CreateTexture(nil, "ARTWORK")
    p.tex:SetAllPoints(); p.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.text = p:CreateFontString(nil, "OVERLAY")
    p.text:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    p.text:SetPoint("BOTTOM", p, "BOTTOM", 0, -1)
    p:SetScript("OnEnter", function(self)
        local st = self.status
        if not st then return end
        ns.Tip(self, "ANCHOR_TOP")
        GameTooltip:AddLine(st.tip or "", 1, 1, 1, true)
        if st.click then GameTooltip:AddLine("Click: " .. (st.clickText or "fix it"), 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p:SetScript("OnClick", function(self)
        local st = self.status
        if st and st.click then pcall(st.click) end
    end)
    pips[i] = p
    return p
end

local function renderStatus()
    local cfg = ns.db.rotation
    local list = {}
    if cfg.enabled and cfg.statusIcons ~= false and not InCombatLockdown() and icon
        and not (ns.reveal and not ns.reveal:Shown("icon")) then
        list = E.StatusList()
    end
    E.status = list   -- (for the Flow key's tooltip)
    for i = 1, math.max(#list, #pips) do
        local st = list[i]
        if st then
            local p = pipAt(i)
            local c = st.color or { 1, 0.82, 0 }
            p.status = st
            p.tex:SetTexture(st.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            p.back:SetColorTexture(c[1], c[2], c[3], 0.95)
            p.text:SetText(st.text or "")
            p.text:SetTextColor(c[1], c[2], c[3])
            p:Show()
        elseif pips[i] then
            pips[i].status = nil
            pips[i]:Hide()
        end
    end
end

local statusElapsed = 1
local timedStatus = ns.perf.Wrap("status icons (1/s)", renderStatus)   -- (/flow perf)
ns:OnLoad(function(saved)
    icon = buildIcon(saved.rotation)
    E.icon = icon  -- for the cast button (Cast.lua)
    local driver = CreateFrame("Frame")
    local timedTick = ns.perf.Wrap("rotation: showing it (10/s)", tick)
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        elapsed = 0
        timedTick()
    end)
    local status = CreateFrame("Frame")
    status:SetScript("OnUpdate", function(_, dt)
        statusElapsed = statusElapsed + dt
        if statusElapsed < 1 then return end
        statusElapsed = 0
        local ok, err = pcall(timedStatus)
        if not ok then E.lastError, E.lastErrorAt = "status: " .. tostring(err), GetTime() end
    end)
end)
ns:On("PLAYER_REGEN_DISABLED", function() statusElapsed = 1 end)
ns:On("PLAYER_REGEN_ENABLED", function() statusElapsed = 1 end)

local function rescan()
    scanButtons()
    current = nil  -- force glows to re-apply to the new buttons
end

-- For /flow rot why: which action buttons hold this spell?
function E:ButtonsFor(spell)
    return buttonsBySpell[spell] or {}
end
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED",
                      "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
                      "UPDATE_SHAPESHIFT_FORMS", "SPELLS_CHANGED" }) do
    ns:On(ev, rescan)
end
