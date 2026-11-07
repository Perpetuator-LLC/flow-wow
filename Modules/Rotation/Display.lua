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
}

local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton",
    "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local icon, glows, current
local buttonsBySpell = {}

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
    f:SetFrameStrata("HIGH")
    local p = cfg.point
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, -160) end

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.border = makeBorder(f, 3)
    f.border.fill:Hide()  -- keep the spell icon clear

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -4)

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
    wipe(buttonsBySpell)
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

local function showGlows(spell, color, kind)
    clearGlows()
    for _, btn in ipairs(buttonsBySpell[spell] or {}) do
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

local function render(s, cfg)
    if not s then
        current = nil
        clearGlows()
        if cfg.locked then icon:Hide() else
            icon.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            icon.text:SetText("Shift-drag me")
            icon:Show()
        end
        return
    end

    local color = COLORS[s.kind] or ns.theme.route or COLORS.damage
    local tex = s.icon
    if not tex and s.spell then tex = select(2, A.SpellInfo(s.spell)) end
    icon.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon.border:SetColor(color[1], color[2], color[3])
    -- Flow Actions always say what the press does ("Equip your Fishing Pole").
    icon.text:SetText(s.label or (cfg.debug and s.reason) or "")
    if s.spell then
        local start, dur = A.CooldownRaw(s.spell)
        icon.cd:SetCooldown(start, dur)
    else
        icon.cd:SetCooldown(0, 0)
    end
    icon:Show()

    local key = tostring(s.spell or s.item or s.type) .. s.kind
    if key ~= current then
        current = key
        if s.spell then showGlows(s.spell, color, s.kind) else clearGlows() end
    end
end

local elapsed = 0
local function onUpdate(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0

    local cfg = ns.db.rotation
    if not cfg.enabled then
        E.shown = nil
        if icon:IsShown() then icon:Hide(); clearGlows(); current = nil end
        return
    end

    local ok, s = pcall(E.Evaluate, E)
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
        local okA, a = pcall(ns.actions.Current, ns.actions)
        if okA and a and (a.urgent or not s) then s = a end
    end
    E.shown = s   -- what the icon shows = what the key does (Cast.lua)
    local okR, err = pcall(render, s, cfg)
    if not okR then E.lastError, E.lastErrorAt = "display: " .. tostring(err), GetTime() end
end

ns:OnLoad(function(saved)
    icon = buildIcon(saved.rotation)
    E.icon = icon  -- for the cast button (Cast.lua)
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", ns.perf.Wrap("rotation + actions (10/s)", onUpdate))
end)

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
