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
local function makeBorder(parent, thickness, inset)
    local b = { edges = {} }
    local function edge(p1, p2, horizontal)
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetPoint(p1, parent, p1, 0, 0)
        t:SetPoint(p2, parent, p2, 0, 0)
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

    f.border = makeBorder(f, 3)
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
    -- Auto attack on: a crossed-swords badge on the LEFT of the button (the
    -- "active" side; on deck is on the right), gently pulsing while swinging.
    f.swing = CreateFrame("Frame", nil, f.timerLayer)
    f.swing:SetSize(24, 24)   -- the "active" side: left of the button
    f.swing:SetPoint("RIGHT", f, "LEFT", -8, 0)
    f.swing.back = f.swing:CreateTexture(nil, "BACKGROUND")
    f.swing.back:SetPoint("TOPLEFT", -1, 1); f.swing.back:SetPoint("BOTTOMRIGHT", 1, -1)
    f.swing.back:SetColorTexture(0, 0, 0, 0.85)
    f.swing.tex = f.swing:CreateTexture(nil, "ARTWORK")
    f.swing.tex:SetAllPoints()
    f.swing.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local _, swingIcon = A.SpellInfo("Auto Attack")
    f.swing.tex:SetTexture(swingIcon or "Interface\\Icons\\INV_Sword_04")
    local pulse = f.swing:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0.45); fade:SetDuration(0.6)
    f.swing.pulse = pulse
    f.swing:Hide()
    -- The queue (right of the button): what your key casts with Ctrl, Shift
    -- and Alt held (Queue.lua; Cast.lua has them set), each a little smaller
    -- than the last, its modifier written above it. Greyed while cooling
    -- down, red out of range; the one Flow advises pulses gold, the one
    -- whose modifier you hold is ringed green.
    f.deck = {}
    local SIZES = { 36, 30, 25 }
    local MODS = { "CTRL", "SHIFT", "ALT" }
    local prev
    for i, sz in ipairs(SIZES) do
        local d = CreateFrame("Frame", nil, f)
        d:SetSize(sz, sz)
        if prev then d:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", 6, 0) else d:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 10, 0) end
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
            GameTooltip:AddLine(string.format("%s + your key: %s", MODS[i], tostring(e.spell or e.label or "your item")), 1, 0.82, 0)
            if e.reason then GameTooltip:AddLine(e.reason, 1, 1, 1, true) end
            GameTooltip:AddLine("Hold " .. MODS[i] .. ": the big icon shows it. In a fight it's set at the pull.", 0.7, 0.7, 0.7, true)
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
    f.shiftTag:SetPoint("RIGHT", f, "LEFT", -6, 0)
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

local function clearGlows()
    if not glows then return end
    for _, g in pairs(glows) do
        g.anim:Stop()
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
        g.border:SetColor(color[1], color[2], color[3])
        g.fade:SetDuration(kind == "emergency" and 0.2 or 0.45)
        g:Show()
        g.anim:Play()
    end
end

-------------------------------------------------------------------------------
-- Update loop
-------------------------------------------------------------------------------


-- Cooldown of what the button does: a spell, or an item (a lure, a recipe).
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
-- Holding Shift: Shift + your key's spell (your heal) swaps in, while the
-- key would do anything at all (the button is there: in a fight, or with
-- something to press).
function ns.ShiftView(view, healSpell, shiftDown, inCombat)
    if not (healSpell and shiftDown and (view or inCombat)) then return view, false end
    return { spell = healSpell, kind = "heal", label = "Shift + key: " .. healSpell, shift = true }, true
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
    icon.text:SetText(s.label or (s.target and ("on " .. s.target)) or (cfg.debug and s.reason) or "")
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
    local txt = ""
    if e.spell then
        local start, dur = A.CooldownRaw(e.spell)
        txt = ns.CooldownText(start, dur, now)
    end
    slot.timer:SetText(txt)
    -- Grey: cooling down, or can't be cast now; red: out of range.
    local okT, tint = pcall(tintOf, e)
    local tv = okT and TINT[tint] or nil
    slot.tex:SetDesaturated((txt ~= "" or (tv and tv[4])) and true or false)
    if tv then slot.tex:SetVertexColor(tv[1], tv[2], tv[3]) else slot.tex:SetVertexColor(1, 1, 1) end
    if state ~= slot.state then
        slot.state = state
        if state == "advised" then
            slot.ring:SetColorTexture(1, 0.82, 0.1, 1); slot.ring:Show(); slot.ring.pulse:Play()
            slot.mod:SetTextColor(1, 0.82, 0.1)
        elseif state == "held" then
            slot.ring.pulse:Stop(); slot.ring:SetColorTexture(0.4, 1, 0.4, 1); slot.ring:Show()
            slot.mod:SetTextColor(0.4, 1, 0.4)
        else
            slot.ring.pulse:Stop(); slot.ring:Hide()
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
    local tag = (swapped and (Q.LABEL[swapped] .. "+")) or (cue == "press" and "Heal: SHIFT+") or nil
    if tag ~= icon.shiftTag.cue then
        icon.shiftTag.cue = tag
        icon.shiftTag:SetShown(tag ~= nil)
        if tag then
            icon.shiftTag:SetText(tag)
            if swapped then icon.shiftTag:SetTextColor(0.4, 1, 0.4) else icon.shiftTag:SetTextColor(1, 0.82, 0.1) end
            icon.shiftTag.pulse:Play()
        else
            icon.shiftTag.pulse:Stop()
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
    -- Swords badge while auto attack is on.
    local swinging = icon:IsShown() and A.Swinging()
    if swinging ~= icon.swing:IsShown() then
        icon.swing:SetShown(swinging)
        if swinging then icon.swing.pulse:Play() else icon.swing.pulse:Stop() end
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
            if slot.state then slot.ring.pulse:Stop(); slot.ring:Hide(); slot.state = nil end
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
