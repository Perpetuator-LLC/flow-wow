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

-- Points the secure button at the suggestion. Spells use the "spell" button
-- type: Forever ignores macro-type secure buttons (the fight record showed
-- every key press arriving with the right macro, and nothing cast). Only
-- Attack still goes through a macro (/startattack never toggles it off).
local function setMacro(text, spell)
    if InCombatLockdown() or text == macro then return end
    if spell and spell ~= "Attack" and spell ~= "Auto Attack" then
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", spell)
        btn:SetAttribute("unit", text:find("@player", 1, true) and "player" or nil)
    elseif spell then
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", text)
        btn:SetAttribute("unit", nil)
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
        GameTooltip:AddLine("Shift-drag to move.", 0.7, 0.7, 0.7)
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
        local s = E.current
        setMacro(macroFor(s), s and s.spell)
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
    ns:Log("cast", string.format("fight end (%.0f s): button got %d click(s) (%d key-down), %d spell(s) cast, suggested %s; nothing %d of %d ticks; last error %s",
        GetTime() - fight.at, fight.clicks, fight.downs, fight.casts or 0, #seen > 0 and table.concat(seen, ", ") or "nothing",
        fight.empty, fight.ticks, tostring(E.lastError)))
    fight = nil
end)

ns:OnLoad(function()
    if not btn then return end
    btn:HookScript("PostClick", function(_, button, down)
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
local function complain(what)
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
