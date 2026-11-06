-- Cast button: click the suggestion icon, or press your Flow key, to cast
-- what Flow suggests.
--
-- WoW's rule: in combat, addons can't change what a button casts. So:
--   * out of combat the button always casts exactly what the icon shows
--     (buffs, seals, your pull, heals between fights);
--   * when combat starts it locks in one spell for the fight: Blizzard's own
--     one-button assistant spell if this client has one (it is allowed to
--     change itself), otherwise whatever Flow suggested at the pull;
--   * while locked, a small "key:" icon shows what your key will cast, so the
--     big icon (Flow's live advice) and the key never get confused.
-- Move it: hold Shift and drag (out of combat).

local _, ns = ...
local A, E = ns.api, ns.rotation
local C = {}
ns.cast = C

local btn, keyText, lockIcon
local macro, lockedSpell = nil, nil

local function macroFor(s)
    if not s then return "" end
    if s.spell == "Attack" or s.spell == "Auto Attack" then return "/startattack" end
    if s.kind == "heal" or s.kind == "emergency" then return "/cast [@player] " .. s.spell end
    return "/cast " .. s.spell
end

-- Points the secure button at the suggestion, as the "spell" button type:
-- Forever ignores macro-type secure buttons (the fight records showed every
-- press arriving with the right macro, and nothing cast). Attack too: Flow
-- only suggests it while you're not swinging, so the press turns it on.
local function setMacro(text, spell)
    if InCombatLockdown() or text == macro then return end
    if spell then
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", spell)
        -- Heals always on you: "player" as the unit.
        local heal = text:find("@player", 1, true) or ns.rotation.current and ns.rotation.current.kind == "heal"
        btn:SetAttribute("unit", heal and "player" or nil)
    else
        btn:SetAttribute("type", nil)
        btn:SetAttribute("spell", nil)
    end
    macro, lockedSpell = text, spell
end

-- Blizzard's single-button assistant, if this client has one.
local function assistantSpell()
    if not (C_AssistedCombat and C_AssistedCombat.GetActionSpell) then return nil end
    local ok, id = pcall(C_AssistedCombat.GetActionSpell)
    if ok and id then return (A.SpellInfo(id)) end
end

function C:KeyLabel()
    local key = ns.db.cast.key
    if not key then return "" end
    return (GetBindingText and GetBindingText(key, "KEY_", true)) or key
end

local function refreshLabels()
    if not keyText then return end
    keyText:SetText(C:KeyLabel())
    -- In combat, show what the key is locked to when it differs from the advice.
    local live = E.current and E.current.spell
    if InCombatLockdown() and lockedSpell and live and lockedSpell ~= live then
        local _, tex = A.SpellInfo(lockedSpell)
        lockIcon.tex:SetTexture(tex)
        lockIcon:Show()
    else
        lockIcon:Hide()
    end
end

local function build(cfg)
    btn = CreateFrame("Button", "FlowCastButton", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(52, 52)
    btn:SetFrameStrata("HIGH")
    local p = cfg.point
    if p then btn:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else btn:SetPoint("CENTER", UIParent, "CENTER", 0, -160) end
    -- Listen for both press and release: the secure button itself acts on the
    -- one matching your "cast on key down" setting. (Registering only one
    -- made key presses do nothing on some clients.)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", "")
    -- Shift + drag moves it; make shift-clicks do nothing so moving never casts.
    btn:SetAttribute("shift-type1", "macro")
    btn:SetAttribute("shift-macrotext1", "")
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, b, x, y = self:GetPoint()
        cfg.point = { a, b, x, y }
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Flow: click to cast the suggestion")
        local key = C:KeyLabel()
        GameTooltip:AddLine(key ~= "" and ("Key: " .. key) or "No key yet: /flow settings", 1, 1, 1)
        GameTooltip:AddLine("In combat the key stays on the spell it had when the fight started.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Hold Shift: a handle appears; drag it to move the icon.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- The visible icon sits on top of the secure button.
    local icon = E.icon
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", btn, "CENTER")
        keyText = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        keyText:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -2, -2)
        lockIcon = CreateFrame("Frame", nil, icon)
        lockIcon:SetSize(22, 22)
        lockIcon:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 8, -8)
        lockIcon.tex = lockIcon:CreateTexture(nil, "OVERLAY")
        lockIcon.tex:SetAllPoints()
        lockIcon.label = lockIcon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lockIcon.label:SetPoint("RIGHT", lockIcon, "LEFT", -2, 0)
        lockIcon.label:SetText("key:")
        lockIcon:Hide()
    end
end

-------------------------------------------------------------------------------
-- Key binding. Uses an override binding: your own key bindings are never
-- changed, and clearing Flow's key gives the key back to whatever it did.
-------------------------------------------------------------------------------

local owner = CreateFrame("Frame")
local pendingKey = false

function C:ApplyKey()
    if InCombatLockdown() then pendingKey = true return end
    pendingKey = false
    ClearOverrideBindings(owner)
    local key = ns.db.cast.key
    if key then SetOverrideBindingClick(owner, true, key, "FlowCastButton", "LeftButton") end
    refreshLabels()
end

-- What else uses this key: friendly name, or nil if it's free (or Flow's).
function C:Conflict(key)
    local action = GetBindingAction and GetBindingAction(key)
    if not action or action == "" or action:find("FlowCastButton", 1, true) then return nil end
    return _G["BINDING_NAME_" .. action] or action, action
end

local MOVEMENT = {
    MOVEFORWARD = true, MOVEBACKWARD = true, TURNLEFT = true, TURNRIGHT = true,
    STRAFELEFT = true, STRAFERIGHT = true, JUMP = true, TOGGLEAUTORUN = true,
}
function C:IsMovement(action) return MOVEMENT[action] == true end

function C:SetKey(key)
    ns.db.cast.key = key
    self:ApplyKey()
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------

-- In-game key binding menu entry (Bindings.xml).
BINDING_HEADER_FLOW = "Flow"
_G["BINDING_NAME_CLICK FlowCastButton:LeftButton"] = "Cast Flow's suggestion"

ns:OnLoad(function(saved)
    saved.cast = saved.cast or {}
    build(saved.rotation)
    C:ApplyKey()

    local acc = 0
    btn:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        if not InCombatLockdown() then
            local s = E.current
            setMacro(macroFor(s), s and s.spell)
            -- Hidden when there's nothing to press, so it never blocks clicks
            -- on the world. (Can only change out of combat.)
            local want = s ~= nil or not ns.db.rotation.locked
            if want ~= btn:IsShown() then btn:SetShown(want) end
        end
        refreshLabels()
    end)
end)

-- Last moment before combat lockdown: lock in the spell for this fight.
ns:On("PLAYER_REGEN_DISABLED", function()
    if btn and not btn:IsShown() then btn:Show() end  -- key must work all fight
    local helper = assistantSpell()
    if helper then
        setMacro("/cast " .. helper, helper)
    else
        -- The key can't change during the fight, so lock it to something worth
        -- pressing all fight: the class decides (pullLock), never nothing.
        local s = E.current
        local def = E:Definition()
        local spell = def and def.pullLock and def.pullLock(s, E) or (s and s.spell)
        if spell and s and spell == s.spell then setMacro(macroFor(s), spell)
        elseif spell then setMacro("/cast " .. spell, spell) end
    end
end)

ns:On("PLAYER_REGEN_ENABLED", function()
    if pendingKey then C:ApplyKey() end
end)

-- Re-apply the key once the game has loaded its own bindings.
ns:On("PLAYER_ENTERING_WORLD", function() C:ApplyKey() end)
ns:On("UPDATE_BINDINGS", function()
    if not InCombatLockdown() and ns.db.cast.key and GetBindingAction(ns.db.cast.key, true) == "" then
        C:ApplyKey()
    end
end)

-- /flow key test: what your key does right now.
function C:Test()
    local key = ns.db.cast.key
    ns:Print("cast key check:")
    print("  key: " .. (key and (self:KeyLabel() .. " (" .. key .. ")") or "not set (/flow settings)"))
    if key then
        print("  key is bound to: " .. tostring(GetBindingAction(key, true)))
    end
    print("  button shown: " .. tostring(btn and btn:IsShown()) .. ", casts: "
        .. (macro and macro ~= "" and macro or "nothing right now (no suggestion)"))
    print("  in combat: " .. tostring(InCombatLockdown()) .. ", cast on key down: "
        .. tostring(GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")))
end

-------------------------------------------------------------------------------
-- Fight record for the diagnostics ("[cast]" lines in the log): what was
-- suggested at the pull, what the key was set to, whether the button got
-- your clicks / key presses, and what Flow suggested during the fight.
-------------------------------------------------------------------------------

local fight
local afterUntil = 0   -- the after-fight heal window is recorded too (15 s after a fight)
ns:On("PLAYER_REGEN_DISABLED", function()
    local key = ns.db.cast.key
    fight = { at = GetTime(), ticks = 0, empty = 0, seen = {}, clicks = 0, downs = 0 }
    ns:Log("cast", string.format("fight start: suggestion %s, key %s -> %s, button %s, macro %q, keydown %s",
        tostring(E.current and E.current.spell), tostring(key),
        tostring(key and GetBindingAction(key, true)), tostring(btn and btn:IsShown()),
        tostring(macro), tostring(GetCVarBool and GetCVarBool("ActionButtonUseKeyDown"))))
end)

ns:On("PLAYER_REGEN_ENABLED", function()
    if not fight then return end
    local seen = {}
    for spell, n in pairs(fight.seen) do seen[#seen + 1] = spell .. " x" .. n end
    ns:Log("cast", string.format("fight end (%.0f s): key pressed %d time(s), button got %d click(s) (%d key-down), %d spell(s) cast, suggested %s; nothing %d of %d ticks; last error %s",
        GetTime() - fight.at, fight.keys or 0, fight.clicks, fight.downs, fight.casts or 0, #seen > 0 and table.concat(seen, ", ") or "nothing",
        fight.empty, fight.ticks, tostring(E.lastError)))
    fight = nil
end)

ns:OnLoad(function()
    if not btn then return end
    btn:HookScript("PostClick", function(_, button, down)
        if not fight and GetTime() < afterUntil then
            ns:Log("cast", string.format("after-fight press: %s down=%s spell %s unit %s", tostring(button), tostring(down),
                tostring(btn:GetAttribute("spell")), tostring(btn:GetAttribute("unit"))))
        end
        if fight then
            fight.clicks = fight.clicks + 1
            if down then fight.downs = fight.downs + 1 end
            if fight.clicks == 1 then
                ns:Log("cast", string.format("first press in fight: %s down=%s macro %q", tostring(button), tostring(down), tostring(macro)))
            end
        end
    end)
    local acc = 0
    local sampler = CreateFrame("Frame")
    sampler:SetScript("OnUpdate", function(_, dt)
        if not fight then return end
        acc = acc + dt
        if acc < 0.5 then return end
        acc = 0
        fight.ticks = fight.ticks + 1
        local s = E.current
        if s then fight.seen[s.spell] = (fight.seen[s.spell] or 0) + 1 else fight.empty = fight.empty + 1 end
    end)
end)

-- During a fight, the game's own complaints (out of range, not ready, no
-- target...) and failed casts go into the fight record too (first few).
-- (afterUntil: declared with `fight` above)
ns:On("PLAYER_REGEN_ENABLED", function() afterUntil = GetTime() + 15 end)
local function complain(what)
    if not fight and GetTime() < afterUntil then ns:Log("cast", "after fight, game said: " .. tostring(what)) return end
    if not fight then return end
    fight.errors = (fight.errors or 0) + 1
    if fight.errors <= 5 then ns:Log("cast", "game said: " .. tostring(what)) end
end
ns:On("UI_ERROR_MESSAGE", function(_, msg) complain(ns.api.Safe(msg)) end)
ns:On("UNIT_SPELLCAST_FAILED", function(unit, _, spellID)
    if unit == "player" then complain("cast failed: " .. tostring(ns.api.SpellInfo(ns.api.Safe(spellID) or 0))) end
end)
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not fight then return end
    fight.casts = (fight.casts or 0) + 1
end)

-------------------------------------------------------------------------------
-- Moving the icon: hold Shift (out of combat) and a "drag to move" handle
-- appears over it. Dragging the secure button itself didn't work reliably
-- (it takes the mouse press as a click), so the handle moves it instead.
-------------------------------------------------------------------------------

local handle
local function buildHandle()
    handle = CreateFrame("Frame", nil, UIParent)
    handle:SetFrameStrata("DIALOG")
    handle:EnableMouse(true)
    handle.bg = handle:CreateTexture(nil, "BACKGROUND")
    handle.bg:SetAllPoints()
    handle.bg:SetColorTexture(0, 0, 0, 0.35)
    handle.edge = {}
    local o = ns.theme.arrow
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                           { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = handle:CreateTexture(nil, "BORDER")
        t:SetPoint(pts[1]); t:SetPoint(pts[2])
        if i <= 2 then t:SetHeight(2) else t:SetWidth(2) end
        t:SetColorTexture(o[1], o[2], o[3], 1)
    end
    handle.text = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    handle.text:SetPoint("TOP", handle, "BOTTOM", 0, -2)
    handle.text:SetText("drag to move")
    handle:SetScript("OnMouseDown", function()
        if InCombatLockdown() then return end
        btn:StartMoving()
        handle.moving = true
    end)
    handle:SetScript("OnMouseUp", function()
        if not handle.moving then return end
        handle.moving = false
        btn:StopMovingOrSizing()
        local a, _, b, x, y = btn:GetPoint()
        ns.db.rotation.point = { a, b, x, y }
    end)
    handle:Hide()
end

local function showHandle()
    if not btn then return end
    local want = IsShiftKeyDown() and not InCombatLockdown() and btn:IsShown()
    if want and not handle then buildHandle() end
    if not handle then return end
    if want then
        handle:ClearAllPoints()
        handle:SetAllPoints(btn)
        handle:Show()
    elseif not handle.moving then
        handle:Hide()
    end
end
ns:On("MODIFIER_STATE_CHANGED", showHandle)
ns:On("PLAYER_REGEN_DISABLED", function() if handle then handle.moving = false; handle:Hide() end end)

-------------------------------------------------------------------------------
-- Key check: a listener that sees your Flow key go down (and passes it on
-- untouched), so the fight record can say, press by press, whether the key
-- arrived, what it was bound to right then, and whether the button then got
-- the click. ("Key does nothing" with the binding looking right otherwise.)
-------------------------------------------------------------------------------

local spy = CreateFrame("Frame", nil, UIParent)
local lastSpyAt, spyLogged = 0, 0
local clicksAtPress = 0
-- Only when keys can be passed on: a keyboard frame that can't would eat every key.
if spy.SetPropagateKeyboardInput then
    spy:SetPropagateKeyboardInput(true)
    spy:EnableKeyboard(true)
end
spy:SetScript("OnKeyDown", function(_, key)
    local mine = ns.db and ns.db.cast and ns.db.cast.key
    if not mine or key ~= mine:match("[^-]+$") then return end
    lastSpyAt = GetTime()
    clicksAtPress = fight and fight.clicks or 0
    if fight then fight.keys = (fight.keys or 0) + 1 end
    if spyLogged < 6 then
        spyLogged = spyLogged + 1
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        ns:Log("cast", string.format("key %s pressed: bound to %s, button %s, focus %s",
            tostring(key), tostring(GetBindingAction(mine, true)), btn and (btn:IsShown() and "shown" or "hidden") or "missing",
            focus and (focus:GetName() or "a text box") or "none"))
        C_Timer.After(0.3, function()
            if fight and fight.clicks == clicksAtPress then ns:Log("cast", "  ...and the button did NOT get the click") end
        end)
    end
end)
ns:On("PLAYER_REGEN_DISABLED", function() spyLogged = 0 end)
