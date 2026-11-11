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

-------------------------------------------------------------------------------
-- Hiding advice: click a row in the list and it goes under "Hidden" at the
-- bottom (collapsed); click it there to bring it back. Kept per character.
-- The key ignores numbers and colours, so "Train 2 spells" stays hidden as
-- "Train 3 spells".
-------------------------------------------------------------------------------

function Adv.KeyOf(item)
    local text = tostring(item.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("%d+", "#")
    return tostring(item.source or "?") .. "|" .. text
end
function Adv:IsHidden(item) return ns.db.advisor.hidden[Adv.KeyOf(item)] ~= nil end
function Adv:Hide(item)
    ns.db.advisor.hidden[Adv.KeyOf(item)] = { text = item.text, at = time and time() or 0 }
    self:Refresh()
end
function Adv:Unhide(item)
    ns.db.advisor.hidden[Adv.KeyOf(item)] = nil
    self:Refresh()
end

-- The advice you haven't hidden, and the hidden advice that still applies.
function Adv.Split(list, isHidden)
    local shown, hidden = {}, {}
    for _, item in ipairs(list) do
        if isHidden(item) then hidden[#hidden + 1] = item else shown[#shown + 1] = item end
    end
    return shown, hidden
end
function Adv:Shown()
    local shown, hidden = Adv.Split(items, function(item) return self:IsHidden(item) end)
    return shown, hidden
end

function Adv:Print(limit)
    local shown, hidden = self:Shown()
    local more = #hidden > 0 and string.format(" |cff888888(%d hidden)|r", #hidden) or ""
    if #shown == 0 then ns:Print("nothing to improve right now |cff888888(Flow v" .. (ns.Version and ns.Version() or "?") .. ")|r." .. more) return end
    ns:Print("ways to improve |cff888888(Flow v" .. (ns.Version and ns.Version() or "?") .. ")|r:" .. more)
    for i = 1, math.min(limit or #shown, #shown) do print("  " .. i .. ". " .. line(shown[i])) end
end

local function buildButton()
    local b = CreateFrame("Button", "FlowAdviceButton", UIParent)
    -- A round, minimap-style button: an icon in a gold ring, with a small
    -- orange count bubble. Pulses gently when new important advice appears.
    b:SetSize(34, 34)
    b:SetFrameStrata("MEDIUM")   -- (under the game's own windows: the game menu, Settings; 0.35.163)
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
    b:SetScript("OnDragStart", function(self) if ns.MoveKeyDown() then self:StartMoving() end end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, r, x, y = self:GetPoint()
        ns.db.advisor.point = { a, r, x, y }
    end)
    b:SetScript("OnClick", function() Adv:TogglePanel() end)
    b:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Flow Improvements")
        local shown, hidden = Adv:Shown()
        for i = 1, math.min(10, #shown) do
            GameTooltip:AddLine(i .. ". " .. line(shown[i]), 1, 1, 1, true)
        end
        if #hidden > 0 then GameTooltip:AddLine(string.format("(%d hidden)", #hidden), 0.6, 0.6, 0.6) end
        GameTooltip:AddLine("Click to open the list. Ctrl-drag to move.", 0.6, 0.6, 0.6)
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
    local shown = self:Shown()
    if ns.db.advisor.enabled and #shown > 0 then
        button.text:SetText(#shown > 99 and "99+" or tostring(#shown))
        -- Pulse a few times when something important (an upgrade, training,
        -- a capped profession) shows up that wasn't there before.
        local top = shown[1] and shown[1].importance or 0
        if top >= 60 and top > (self.lastTop or 0) then
            button.pulse:Play()
            C_Timer.After(4, function() button.pulse:Stop(); button:SetAlpha(1) end)
        end
        self.lastTop = top
        -- (New to Flow: it comes in after your first level or 10 minutes, Reveal.lua.)
        button:SetShown(not (ns.reveal and not ns.reveal:Shown("advice")))
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
    saved.advisor.hidden = saved.advisor.hidden or {}
    if saved.advisor.enabled == nil then saved.advisor.enabled = true end
    button = buildButton()
end)
ns:PerCharacter("advisor.hidden")   -- what you hid is about your character

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
-- Advice panel (click the ! button):
--   * click a row: it's hidden (under "Hidden" at the bottom, collapsed);
--     click "Hidden (N)" to open that list, click a row there to bring it back
--   * the link button on the right of a row opens what it's about: the stop on
--     your route (its card: go here next...), the spell (place it or bind a
--     key), the item, the profession picker, the talent plan
-------------------------------------------------------------------------------

local panel
local ROWS = 16

local function goalFor(key)
    if not (key and ns.nav) then return nil end
    for _, g in ipairs(ns.nav:Goals()) do
        if g.key == key and g.points and #g.points > 0 then return g end
    end
end

-- What a row's link opens: kind ("open", "goal", "spell", "item") and a label,
-- or nil when there's nothing to open. goalOf(key) -> the route stop or nil.
function Adv.LinkOf(item, goalOf)
    if item.onClick or item.open then return "open", item.openLabel or "it" end
    local g = item.goalKey and goalOf(item.goalKey)
    if g then return "goal", "the stop on your route: " .. tostring(g.text or g.title or item.goalKey) end
    if item.spell then return "spell", item.spell .. " (put it on a bar or bind a key)" end
    local link = tostring(item.text or ""):match("(|c%x+|Hitem:.-|h.-|h|r)")
    if link then return "item", link end
end

function Adv.Open(item, anchor)
    local kind = Adv.LinkOf(item, goalFor)
    if kind == "open" then
        local fn = item.onClick or item.open
        local ok, err = pcall(fn)
        if not ok then ns:Print("couldn't open it: " .. tostring(err)) end
    elseif kind == "goal" then
        ns.nav:OpenStop(goalFor(item.goalKey), anchor)
    elseif kind == "spell" then
        if ns.newSpell and ns.newSpell.Offer then ns.newSpell:Offer(item.spell) end
    elseif kind == "item" then
        local link = tostring(item.text):match("(|c%x+|Hitem:.-|h.-|h|r)")
        if ItemRefTooltip and link then
            ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")
            ItemRefTooltip:SetHyperlink(link:match("|H(.-)|h"))
            ItemRefTooltip:Show()
        end
    end
end

-- The rows on screen: your advice, then "Hidden (N)" and (opened) the hidden ones.
--   -> { { kind = "item" | "header" | "hidden", item } }, at most `max`
function Adv.Rows(shown, hidden, open, max)
    local rows = {}
    local room = #hidden > 0 and max - 1 or max
    for i = 1, math.min(#shown, room) do rows[#rows + 1] = { kind = "item", item = shown[i] } end
    if #hidden > 0 then
        rows[#rows + 1] = { kind = "header", count = #hidden, open = open }
        if open then
            for _, item in ipairs(hidden) do
                if #rows >= max then break end
                rows[#rows + 1] = { kind = "hidden", item = item }
            end
        end
    end
    return rows
end

-- The link button's picture: a chain link where the game has one, else a spyglass.
local LINK_ICON, LINK_FALLBACK = "Interface\\Buttons\\UI-LinkProfession-Up", "Interface\\Icons\\INV_Misc_Spyglass_02"
local function linkButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    b:SetPoint("RIGHT", -2, 0)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    local ok = b.tex:SetTexture(LINK_ICON)
    if ok == false or (b.tex.GetTextureFileID and not b.tex:GetTextureFileID()) then
        b.tex:SetTexture(LINK_FALLBACK); b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.25)
    return b
end

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
    f.title:SetText("Flow Improvements")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)   -- (our own: the game's handler can't close an add-on window in a fight)
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(416, 18)
        r:SetPoint("TOPLEFT", 12, -30 - (i - 1) * 20)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.08)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 2, 0)
        r.text:SetPoint("RIGHT", -22, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r.link = linkButton(r)
        r.link:SetScript("OnClick", function(self) Adv.Open(r.row.item, self) end)
        r.link:SetScript("OnEnter", function(self)
            local _, label = Adv.LinkOf(r.row.item, goalFor)
            ns.Tip(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Open " .. tostring(label), 1, 1, 1, true)
            if r.row.item.goalKey and ns.mapOverlay then ns.mapOverlay:Preview(r.row.item.goalKey) end
            GameTooltip:Show()
        end)
        r.link:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if ns.mapOverlay then ns.mapOverlay:Preview(nil) end
        end)
        r:SetScript("OnEnter", function(self)
            local row = self.row
            ns.Tip(self, "ANCHOR_RIGHT")
            if row.kind == "header" then
                GameTooltip:AddLine(row.open and "Click to fold the hidden ones away." or "Click to see what you hid.", 1, 1, 1, true)
            else
                GameTooltip:AddLine(row.item.text, 1, 1, 1, true)
                if row.item.improves then GameTooltip:AddLine("Improves: " .. table.concat(row.item.improves, ", "), 0.7, 0.7, 0.7) end
                GameTooltip:AddLine(row.kind == "hidden" and "Click to bring it back." or "Click to hide it (it goes under Hidden at the bottom).", 1, 0.65, 0)
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self)
            local row = self.row
            if row.kind == "header" then
                f.hiddenOpen = not f.hiddenOpen
                Adv:FillPanel()
            elseif row.kind == "hidden" then
                Adv:Unhide(row.item)
            else
                Adv:Hide(row.item)
            end
        end)
        f.rows[i] = r
    end
    f:Hide()
    return f
end

function Adv:FillPanel()
    if not (panel and panel:IsShown()) then return end
    local shown, hidden = self:Shown()
    local rows = Adv.Rows(shown, hidden, panel.hiddenOpen, ROWS)
    local pickup = 0
    for i = 1, ROWS do
        local r, row = panel.rows[i], rows[i]
        if row then
            r.row = row
            local label
            if row.kind == "header" then
                label = string.format("|cffffd200%s Hidden (%d)|r", row.open and "-" or "+", row.count)
            else
                label = row.item.text
                if row.item.goalKey and row.item.goalKey:find("^pickup:") then
                    pickup = pickup + 1
                    local c = ns.theme and ns.theme.changed
                    label = string.format("|cff%s!%d|r %s", c and c.hex or "0072B2", pickup, label)
                end
                if row.kind == "hidden" then label = "|cff888888" .. label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r" end
            end
            r.text:SetText(label)
            r.link:SetShown(row.kind ~= "header" and Adv.LinkOf(row.item, goalFor) ~= nil)
            r:Show()
        else
            r:Hide()
        end
    end
    panel:SetHeight(46 + math.max(1, #rows) * 20)
    if #rows == 0 then
        panel.rows[1].row = { kind = "header", count = 0 }
        panel.rows[1].text:SetText("|cff888888Nothing to improve right now.|r")
        panel.rows[1].link:Hide()
        panel.rows[1]:Show()
    end
end

function Adv:TogglePanel()
    GameTooltip:Hide()
    panel = panel or buildPanel()
    if panel:IsShown() then panel:Hide() return end
    self:Refresh()
    panel:Show()
    self:FillPanel()
end
