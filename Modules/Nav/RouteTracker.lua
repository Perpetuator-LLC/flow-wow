-- Flow Tracker: your route's next stops on screen (objectives with counts,
-- turn-ins, quests to accept, trainers...). Click a stop to go there first,
-- right-click to hide it.
--
-- Accordion with Questie's tracker: only one is open at a time, and both can
-- be collapsed. On first run Flow opens its tracker and collapses Questie's.
-- The bright "Questie" button on Flow's header (always there) switches to
-- Questie's tracker; opening Questie's (from its own header too) collapses
-- Flow's. Uses Questie's own Collapse/Expand, nothing is hidden by force.

local _, ns = ...
local RT = {}
ns.routeTracker = RT

local ROWS = 10
local frame

local function questieTracker()
    if not QuestieLoader then return nil end
    local ok, t = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieTracker")
    if ok and t and type(t.Collapse) == "function" then return t end
end

local function questieOpen()
    return Questie and Questie.db and Questie.db.char and Questie.db.char.isTrackerExpanded == true
end

local function db() return ns.db.tracker end

local function setQuestie(open)
    local t = questieTracker()
    if not t then return end
    if open then pcall(t.Expand, t) else pcall(t.Collapse, t) end
end

function RT:Open(which)
    db().open = which  -- "flow" | "questie" | "none"
    if which == "flow" then setQuestie(false)
    elseif which == "questie" then setQuestie(true) end
    self:Refresh()
end

local function build()
    local f = CreateFrame("Frame", "FlowTracker", UIParent)
    f:SetWidth(260)
    f:SetFrameStrata("MEDIUM")
    local p = db().point
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -230) end
    local o = ns.theme.arrow

    -- Header (same style as the map's Flow route bar).
    local h = CreateFrame("Button", nil, f)
    h:SetHeight(24)
    h:SetPoint("TOPLEFT"); h:SetPoint("TOPRIGHT")
    h.bg = h:CreateTexture(nil, "BACKGROUND"); h.bg:SetAllPoints()
    h.bg:SetColorTexture(0.11, 0.09, 0.06, 0.92)
    local accent = h:CreateTexture(nil, "BORDER")
    accent:SetPoint("TOPLEFT"); accent:SetPoint("BOTTOMLEFT"); accent:SetWidth(4)
    accent:SetColorTexture(o[1], o[2], o[3], 1)
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(16, 16); h.icon:SetPoint("LEFT", 9, 0)
    h.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01"); h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.text:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
    h.pm = h:CreateTexture(nil, "ARTWORK")
    h.pm:SetSize(16, 16); h.pm:SetPoint("RIGHT", -6, 0)
    h:SetScript("OnClick", function()
        RT:Open(db().open == "flow" and "none" or "flow")
    end)
    h:RegisterForDrag("LeftButton")  -- Shift-drag the header to move the tracker
    h:SetScript("OnDragStart", function() if IsShiftKeyDown() then f:StartMoving() end end)
    h:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local a, _, b, x, y = f:GetPoint()
        db().point = { a, b, x, y }
    end)
    f:SetMovable(true); f:SetClampedToScreen(true)
    f.header = h

    -- Bright switch to Questie's tracker (always there when Questie is).
    local q = CreateFrame("Button", nil, h)
    q:SetSize(92, 18); q:SetPoint("RIGHT", h.pm, "LEFT", -6, 0)
    q.bg = q:CreateTexture(nil, "BACKGROUND"); q.bg:SetAllPoints()
    local u = ns.theme.user
    q.bg:SetColorTexture(u[1], u[2], u[3], 0.95)
    q.text = q:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); q.text:SetPoint("CENTER")
    q.text:SetText("Questie")
    q:SetScript("OnClick", function()
        RT:Open(db().open == "questie" and "none" or "questie")
    end)
    q:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Switch to Questie's tracker (Flow's collapses). Click again to collapse it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    q:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.questie = q

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, 0)
    f.body:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", 0, 0)
    f.body.bg = f.body:CreateTexture(nil, "BACKGROUND"); f.body.bg:SetAllPoints()
    f.body.bg:SetColorTexture(0, 0, 0, 0.45)
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, f.body)
        r:SetHeight(16)
        r:SetPoint("TOPLEFT", 8, -4 - (i - 1) * 17)
        r:SetPoint("TOPRIGHT", -6, -4 - (i - 1) * 17)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetAllPoints(); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.08)
        r:SetScript("OnClick", function(self, button)
            if not self.key then return end
            if button == "RightButton" then ns.nav:Hide(self.key) else ns.nav:Select(self.key) end
        end)
        r:SetScript("OnEnter", function(self)
            if not self.goal then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(self.goal.text or self.goal.title or "?", 1, 1, 1, true)
            for _, d in ipairs(self.goal.details or {}) do GameTooltip:AddLine(d, 0.8, 0.8, 0.8, true) end
            GameTooltip:AddLine("Click: go here first. Right-click: hide.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.rows[i] = r
    end
    return f
end

function RT:Refresh()
    if not frame then return end
    local enabled = ns.db.tracker.enabled ~= false
    frame:SetShown(enabled)
    if not enabled then return end
    local open = db().open == "flow"
    local plan = ns.nav and ns.nav.plan or {}
    local h = frame.header
    h.text:SetText(string.format("Flow Tracker  |cff888888%d stops|r", #plan))
    h.pm:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
    frame.questie:SetShown(questieTracker() ~= nil)
    frame.questie.text:SetText(db().open == "questie" and "Questie (open)" or "Questie")
    frame.body:SetShown(open)
    local shown = 0
    if open then
        local labels = ns.nav:PlanLabels(plan)
        for i = 1, ROWS do
            local r, s = frame.rows[i], plan[i]
            if s then
                local col = ns.nav:StopColor(i, s.goal)
                r.key, r.goal = s.goal.key, s.goal
                r.text:SetText(string.format("|cff%s%s|r %s", col.hex, labels[i], s.goal.text or s.goal.title or "?"))
                r:Show()
                shown = i
            else
                r:Hide()
            end
        end
        if shown == 0 then
            frame.rows[1].key, frame.rows[1].goal = nil, nil
            frame.rows[1].text:SetText("|cff888888Nothing on your route right now.|r")
            frame.rows[1]:Show()
            shown = 1
        end
    end
    frame.body:SetHeight(8 + shown * 17)
    frame:SetHeight(24 + (open and (8 + shown * 17) or 0))
end

ns:OnLoad(function(saved)
    saved.tracker = saved.tracker or {}
end)

ns:On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(4, function()
        frame = frame or build()
        -- First run (or Questie added later): Flow open, Questie collapsed.
        if not db().init then
            db().init = true
            RT:Open("flow")
        elseif questieTracker() and not db().questieSeen then
            RT:Open("flow")
        end
        if questieTracker() then db().questieSeen = true end
        RT:Refresh()
        -- Keep the accordion in step if Questie's own header is clicked, and
        -- follow the route as it changes.
        local acc, lastVersion = 0, -1
        frame:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc < 0.5 then return end
            acc = 0
            if questieOpen() and db().open == "flow" then db().open = "questie" end
            if not questieOpen() and db().open == "questie" and questieTracker() then db().open = "none" end
            if ns.nav and ns.nav.planVersion ~= lastVersion then lastVersion = ns.nav.planVersion end
            RT:Refresh()
        end)
    end)
end)

ns.commands.tracker = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.tracker.enabled = (arg == "on")
        RT:Refresh()
        ns:Print("Flow Tracker " .. arg)
    elseif arg == "questie" or arg == "flow" then
        RT:Open(arg)
    else
        ns:Print("/flow tracker on|off|flow|questie")
    end
end

ns:Register("help", "tracker", { order = 42, title = "Flow Tracker", lines = {
    "Your next stops on screen. Header: click to open/collapse; the blue Questie button switches trackers.",
    "Click a stop to go there first, right-click to hide it. /flow tracker on|off|flow|questie",
} })
