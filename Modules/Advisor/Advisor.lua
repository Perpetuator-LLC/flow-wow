-- Advisor: "what should I change to get better?" Collects advice from every
-- registered advisor (train this spell, equip that item, raise a profession,
-- spend talent points, rotation habits from your best fights) and shows it
-- as a small "!" button with a count. Hover for the list; /flow advice prints it.
--
-- Add an advisor:
--   ns:Register("advisor", "key", { check = function() return { advice, ... } end })
-- advice = { importance = 0-100, text = "...", improves = { "DPS", ... } }

local _, ns = ...
local Adv = {}
ns.advisor = Adv

local items = {}
local button

function Adv:Collect()
    local out = {}
    for key, a in ns:Each("advisor") do
        local ok, list = pcall(a.check)
        if ok then
            for _, item in ipairs(list or {}) do
                item.source = key
                out[#out + 1] = item
            end
        elseif ns.db.rotation.debug then
            ns:Print("advisor " .. key .. ": " .. tostring(list))
        end
    end
    table.sort(out, function(a, b) return (a.importance or 0) > (b.importance or 0) end)
    return out
end

local function line(item)
    local tags = item.improves and #item.improves > 0
        and (" |cff888888(improves " .. table.concat(item.improves, ", ") .. ")|r") or ""
    return item.text .. tags
end

function Adv:Print(limit)
    if #items == 0 then ns:Print("nothing to improve right now |cff888888(Flow v" .. (ns.Version and ns.Version() or "?") .. ")|r.") return end
    ns:Print("ways to improve |cff888888(Flow v" .. (ns.Version and ns.Version() or "?") .. ")|r:")
    for i = 1, math.min(limit or #items, #items) do print("  " .. i .. ". " .. line(items[i])) end
end

local function buildButton()
    local b = CreateFrame("Button", "FlowAdviceButton", UIParent)
    -- A round, minimap-style button: an icon in a gold ring, with a small
    -- orange count bubble. Pulses gently when new important advice appears.
    b:SetSize(34, 34)
    b:SetFrameStrata("HIGH")
    local p = ns.db.advisor.point
    if p then b:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else b:SetPoint("CENTER", UIParent, "CENTER", 52, -160) end

    b.back = b:CreateTexture(nil, "BACKGROUND")
    b.back:SetSize(26, 26)
    b.back:SetPoint("CENTER")
    b.back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.back:SetVertexColor(0, 0, 0, 0.85)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(21, 21)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
    if b.icon.SetMask then
        pcall(b.icon.SetMask, b.icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    else
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- The standard minimap-button ring (sits offset to the top left by design).
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetSize(56, 56)
    b.ring:SetPoint("TOPLEFT", -1, 1)
    b.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetSize(30, 30)
    b.hl:SetPoint("CENTER")
    b.hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b.hl:SetBlendMode("ADD")

    -- Count bubble (bottom right).
    b.badge = CreateFrame("Frame", nil, b)
    b.badge:SetSize(18, 18)
    b.badge:SetPoint("CENTER", b, "BOTTOMRIGHT", -3, 4)
    b.badge:SetFrameLevel(b:GetFrameLevel() + 3)
    b.badge.bg = b.badge:CreateTexture(nil, "BACKGROUND")
    b.badge.bg:SetAllPoints()
    b.badge.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local o = ns.theme and ns.theme.arrow or { 0.9, 0.62, 0 }
    b.badge.bg:SetVertexColor(o[1], o[2], o[3], 1)
    b.text = b.badge:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetTextColor(1, 1, 1)

    local pulse = b:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.45)
    a:SetDuration(0.6)
    pulse.anim = a
    b.pulse = pulse
    b:SetScript("OnMouseDown", function(self) self.pulse:Stop(); self:SetAlpha(1) end)
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, r, x, y = self:GetPoint()
        ns.db.advisor.point = { a, r, x, y }
    end)
    b:SetScript("OnClick", function() Adv:TogglePanel() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Flow: ways to improve")
        for i = 1, math.min(10, #items) do
            GameTooltip:AddLine(i .. ". " .. line(items[i]), 1, 1, 1, true)
        end
        GameTooltip:AddLine("Click to open the list (pick a place to route there). Shift-drag to move.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

function Adv:Refresh()
    if InCombatLockdown and InCombatLockdown() then return end
    items = self:Collect()
    if not button then return end
    if ns.db.advisor.enabled and #items > 0 then
        button.text:SetText(#items > 99 and "99+" or tostring(#items))
        -- Pulse a few times when something important (an upgrade, training,
        -- a capped profession) shows up that wasn't there before.
        local top = items[1] and items[1].importance or 0
        if top >= 60 and top > (self.lastTop or 0) then
            button.pulse:Play()
            C_Timer.After(4, function() button.pulse:Stop(); button:SetAlpha(1) end)
        end
        self.lastTop = top
        button:Show()
    else
        button:Hide()
    end
    self:FillPanel()
end

-- Many events fire in bursts; refresh once things settle.
local pending = false
local function schedule()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        pcall(Adv.Refresh, Adv)
    end)
end

ns:OnLoad(function(saved)
    saved.advisor = saved.advisor or {}
    if saved.advisor.enabled == nil then saved.advisor.enabled = true end
    button = buildButton()
end)

for _, ev in ipairs({ "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
                      "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "TRAINER_CLOSED",
                      "PLAYER_REGEN_ENABLED", "ACTIONBAR_SLOT_CHANGED",
                      "CHARACTER_POINTS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    ns:On(ev, schedule)
end

ns:On("PLAYER_LOGIN", function()
    C_Timer.After(6, function()
        pcall(Adv.Refresh, Adv)
        if #items > 0 then Adv:Print(3) end
    end)
end)

ns:On("PLAYER_LEVEL_UP", function()
    C_Timer.After(2, function() pcall(Adv.Refresh, Adv); Adv:Print(5) end)
end)

ns.commands.advice = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.advisor.enabled = (arg == "on")
        Adv:Refresh()
        ns:Print("advice button " .. arg)
    else
        Adv:Refresh()
        Adv:Print()
    end
end

-------------------------------------------------------------------------------
-- Advice panel (click the ! button). Rows that are places (quests to pick up,
-- trainers, skill spots) have an arrow: hover to preview that route on the
-- world map, click to make it your route. Picking a "!" quest pickup routes
-- you through all the pickups first, then the rest of your plan.
-------------------------------------------------------------------------------

local panel
local ROWS = 16

local function buildPanel()
    local f = CreateFrame("Frame", "FlowAdvicePanel", UIParent)
    f:SetSize(440, 46 + ROWS * 20)
    f:SetFrameStrata("DIALOG")
    local p = ns.db.advisor.panelPoint
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER", 0, 80) end
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
    local top = f:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
    top:SetColorTexture(1, 0.65, 0, 0.9)
    ns:MakeMovable(f, setmetatable({}, { __newindex = function(_, k, v)
        if k == "point" then ns.db.advisor.panelPoint = v end end }), true)
    f:EnableMouse(true)
    tinsert(UISpecialFrames, "FlowAdvicePanel")
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText("Flow: ways to improve")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(416, 18)
        r:SetPoint("TOPLEFT", 12, -30 - (i - 1) * 20)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.08)
        r.go = r:CreateTexture(nil, "OVERLAY")
        r.go:SetSize(14, 14)
        r.go:SetPoint("LEFT")
        r.go:SetTexture("Interface\\Minimap\\MinimapArrow")
        r.go:SetRotation(-math.pi / 2)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 18, 0)
        r.text:SetWidth(396)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.item.text, 1, 1, 1, true)
            if self.item.improves then GameTooltip:AddLine("Improves: " .. table.concat(self.item.improves, ", "), 0.7, 0.7, 0.7) end
            if self.goal then
                GameTooltip:AddLine("Click to go here first. Open your map to see the route.", 1, 0.65, 0)
                if ns.mapOverlay then ns.mapOverlay:Preview(self.item.goalKey) end
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if ns.mapOverlay then ns.mapOverlay:Preview(nil) end
        end)
        r:SetScript("OnClick", function(self)
            if self.item.onClick then self.item.onClick() return end
            if not self.goal then return end
            ns.nav:Select(self.item.goalKey)
            ns:Print("route updated: " .. (self.goal.text or self.item.text) .. " first")
        end)
        f.rows[i] = r
    end
    f:Hide()
    return f
end

local function goalFor(key)
    if not (key and ns.nav) then return nil end
    for _, g in ipairs(ns.nav:Goals()) do
        if g.key == key and g.points and #g.points > 0 then return g end
    end
end

function Adv:FillPanel()
    if not (panel and panel:IsShown()) then return end
    local pickup = 0
    for i = 1, ROWS do
        local r, item = panel.rows[i], items[i]
        if item then
            r.item = item
            r.goal = goalFor(item.goalKey)
            local label = item.text
            if item.goalKey and item.goalKey:find("^pickup:") then
                pickup = pickup + 1
                local c = ns.theme and ns.theme.changed
                label = string.format("|cff%s!%d|r %s", c and c.hex or "0072B2", pickup, label)
            end
            r.text:SetText(label)
            r.go:SetShown(r.goal ~= nil or item.onClick ~= nil)
            if r.goal then local c = ns.theme.arrow; r.go:SetVertexColor(c[1], c[2], c[3]) end
            r:Show()
        else
            r:Hide()
        end
    end
end

function Adv:TogglePanel()
    panel = panel or buildPanel()
    if panel:IsShown() then panel:Hide() return end
    self:Refresh()
    panel:Show()
    self:FillPanel()
end
