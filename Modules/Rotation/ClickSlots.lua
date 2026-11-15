-- Click to cast: the icons beside Flow's icon, and the auto-attack badge.
--
-- "Each of them should be click castable. Hovering over auto-attack should
-- say 'Auto-Attack' and they can click to toggle it." (0.35.227)
--
-- The little icons beside the big one are pictures (Display.lua): a picture
-- can't cast. So a button of the game's secure kind lies over each, set to
-- the same spell or item its modifier press casts (Cast.lua C:Slots), and a
-- click on the icon is a click on that button. One more lies over the
-- auto-attack badge and casts Attack, which turns your swing on and off.
--
-- Like everything the game lets cast, they're set out of a fight and stay
-- as they are during one; a change of form swaps their spells with the
-- key's (Cast.lua's form handler holds them too). They show only while
-- their icon shows: an unseen button beside your key would cast at a stray
-- click. They are children of Flow's own secure button, never of the game's
-- frames.
--
-- "Click the icons beside the Flow icon to cast" in Flow Settings (Your
-- easy key) turns them off. The second key's icons are clickable the same
-- way (CareKeys.lua makes its icons buttons itself).

local _, ns = ...
local C, A = ns.cast, ns.api
if not (C and A) then return end

local S = {}
ns.clickSlots = S

S.SIZES = { 36, 30, 25, 22 }   -- as the icons' own (Display.lua)
S.buttons = {}                 -- [slot] = its button
function S.On() return not (ns.db.cast and ns.db.cast.clickSlots == false) end

-- Pure: should a slot's button be up? on: the setting; has: the slot casts
-- something; iconShown: its icon is on screen.
function S.Wanted(on, has, iconShown)
    return (on and has and iconShown) and true or false
end

-- Pure: a step as text, to tell when a button must be set again.
function S.Text(kind, what, unit)
    if not kind then return "" end
    return kind .. ":" .. tostring(what) .. "@" .. tostring(unit)
end

-- The spell that toggles your swing on this client.
function S.AttackSpell()
    if A.SpellInfo("Attack") then return "Attack" end
    if A.SpellInfo("Auto Attack") then return "Auto Attack" end
    return nil
end

local function order() return (ns.queue and ns.queue.ORDER) or { "shift", "ctrl", "alt", "more" } end

local function build(btn, icon)
    local prev
    for i, slot in ipairs(order()) do
        local b = CreateFrame("Button", "FlowKeySlot" .. i, btn, "SecureActionButtonTemplate")
        local sz = S.SIZES[i] or S.SIZES[#S.SIZES]
        b:SetSize(sz, sz)
        if prev then b:SetPoint("BOTTOMRIGHT", prev, "BOTTOMLEFT", -6, 0)
        else b:SetPoint("BOTTOMRIGHT", btn, "BOTTOMLEFT", -10, 0) end
        b:RegisterForClicks("AnyUp", "AnyDown")
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.25)
        -- Hover: the icon's own tooltip, and that a click casts it.
        b:SetScript("OnEnter", function()
            local d = icon.deck and icon.deck[i]
            local fn = d and d:GetScript("OnEnter")
            if fn then pcall(fn, d) end
            if GameTooltip:IsShown() then
                GameTooltip:AddLine("Click: cast it.", 1, 0.65, 0)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b.text = ""
        b:Hide()
        S.buttons[slot] = b
        prev = b
    end
    -- Over the auto-attack badge, right of the icon.
    local w = CreateFrame("Button", "FlowSwingButton", btn, "SecureActionButtonTemplate")
    w:SetSize(24, 24)
    w:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    w:RegisterForClicks("AnyUp")   -- (once a click: Attack toggles)
    w.hl = w:CreateTexture(nil, "HIGHLIGHT")
    w.hl:SetAllPoints()
    w.hl:SetColorTexture(1, 1, 1, 0.25)
    w:SetScript("OnEnter", function()
        local fn = icon.swing and icon.swing:GetScript("OnEnter")
        if fn then pcall(fn, icon.swing) end
    end)
    w:SetScript("OnLeave", function() GameTooltip:Hide() end)
    w:Hide()
    S.swing = w
    S.built = true
end

-- Brings the buttons up to date. Out of a fight only; `fight`: the last
-- moment before one (every slot that casts something shows: its icon will).
function S.Sync(fight)
    if InCombatLockdown() then return false end
    local btn, icon = _G.FlowCastButton, _G.FlowRotationIcon
    if not (btn and icon and icon.deck) then return false end
    if not S.built then build(btn, icon) end
    local on = S.On()
    local slots = C:Slots() or {}
    local level = icon:GetFrameLevel() + 30
    for i, slot in ipairs(order()) do
        local b = S.buttons[slot]
        if b then
            local kind, what, unit = C.SlotAttributes(slots[slot])
            local text = S.Text(kind, what, unit)
            if text ~= b.text then
                b.text = text
                for _, a in ipairs({ "type", "spell", "item", "unit" }) do b:SetAttribute(a, nil) end
                if kind then
                    b:SetAttribute("type", kind)
                    b:SetAttribute(kind, what)
                    b:SetAttribute("unit", unit)
                end
            end
            if b:GetFrameLevel() ~= level then b:SetFrameLevel(level) end
            local d = icon.deck[i]
            local want = S.Wanted(on, kind ~= nil, fight or (d ~= nil and d:IsShown()))
            if want ~= b:IsShown() then b:SetShown(want) end
        end
    end
    -- The form handler swaps these with the key's own (once it exists).
    local h = C._FormHeader and C._FormHeader()
    if h and h ~= S.header then
        for slot, b in pairs(S.buttons) do h:SetFrameRef("deck-" .. slot, b) end
        S.header = h
    end
    -- Auto attack.
    local w = S.swing
    local spell = S.AttackSpell()
    if w then
        if spell ~= w.spell then
            w.spell = spell
            w:SetAttribute("type", spell and "spell" or nil)
            w:SetAttribute("spell", spell)
        end
        if w:GetFrameLevel() ~= level then w:SetFrameLevel(level) end
        local want = S.Wanted(on, spell ~= nil, fight or (icon.swing ~= nil and icon.swing:IsShown()))
        if want ~= w:IsShown() then w:SetShown(want) end
    end
    return true
end

local acc = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    acc = 0
    if InCombatLockdown() then return end
    local ok, err = pcall(S.Sync, false)
    if not ok and err ~= S.lastError then S.lastError = err; ns:Log("cast", "click slots: " .. tostring(err)) end
end)
-- (After Cast.lua has set the fight's slots: it registered first.)
ns:On("PLAYER_REGEN_DISABLED", function() pcall(S.Sync, true) end)

function S.Lines()
    local out = { "  click to cast: " .. (S.On() and "on" or "off") .. (S.lastError and ("; last error: " .. tostring(S.lastError)) or "") }
    for _, slot in ipairs(order()) do
        local b = S.buttons[slot]
        if b then out[#out + 1] = string.format("    %s icon: %s%s", slot, b.text ~= "" and b.text or "nothing", b:IsShown() and "" or " (hidden)") end
    end
    if S.swing then out[#out + 1] = "    auto-attack badge: " .. tostring(S.swing.spell) .. (S.swing:IsShown() and "" or " (hidden)") end
    return out
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "key",
        label = "Click the icons beside the Flow icon to cast",
        note = "(and the auto-attack badge)",
        tip = "A click on one of the small icons beside Flow's icon casts what its Shift, Ctrl, Alt or Ctrl + Shift press casts. A click on the crossed swords turns auto attack on or off.",
        get = function() return S.On() end,
        set = function(on)
            ns.db.cast.clickSlots = on and true or false
            if not InCombatLockdown() then pcall(S.Sync, false) end
        end,
    })
end
