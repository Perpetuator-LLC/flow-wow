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

local function setMacro(text, spell)
    if InCombatLockdown() or text == macro then return end
    btn:SetAttribute("macrotext", text)
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
    local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    btn:RegisterForClicks(down and "AnyDown" or "AnyUp")
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
