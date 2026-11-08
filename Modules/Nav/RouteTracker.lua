-- Flow Tracker: your route's next stops on screen (objectives with counts,
-- turn-ins, quests to accept, trainers...). Click a stop to open it (the
-- quest, or the map at that stop); right-click for a menu (hide, route, order).
-- Changing the route itself is done on the world map (click a stop there).
--
-- Accordion with Questie's tracker: only one is open at a time, and both can
-- be collapsed. On first run Flow opens its tracker and collapses Questie's.
-- Opening Questie's tracker (its own header) collapses Flow's; opening Flow's
-- collapses Questie's. Uses Questie's own Collapse/Expand, nothing is hidden by force.

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
    -- Always hang from the top-left corner, so collapsing shrinks it up into
    -- the header instead of towards its middle. (Older saves used other anchors.)
    local function pinTop()
        if f.docked then return end
        local l, tp = f:GetLeft(), f:GetTop()
        if not (l and tp) then return end
        local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * s, tp * s)
        db().point = { "TOPLEFT", "BOTTOMLEFT", l * s, tp * s }
    end
    f.pinTop = pinTop
    if not p or p[1] ~= "TOPLEFT" then C_Timer.After(0, pinTop) end
    local o = ns.theme.arrow

    -- Header: Flow's title bar (Theme.lua), the same on every Flow panel.
    local h = ns.theme:TitleBar(f, nil, "Interface\\Icons\\INV_Misc_Map_01", "Button")
    -- Shown in place of the map icon while the route is being redone: the
    -- game's own loading spinner if this client has it, else a turning arrow.
    local okS, spinner = pcall(CreateFrame, "Frame", nil, h, "LoadingSpinnerTemplate")
    if okS and spinner then
        spinner:SetSize(20, 20); spinner:SetPoint("CENTER", h.icon)
        local anim = spinner.Anim or spinner.AnimFrame
        h.spin = { Show = function() spinner:Show(); if anim and anim.Play then anim:Play() end end,
                   Hide = function() spinner:Hide(); if anim and anim.Stop then anim:Stop() end end }
        spinner:Hide()
    else
        local t = h:CreateTexture(nil, "OVERLAY")
        t:SetSize(16, 16); t:SetPoint("CENTER", h.icon)
        t:SetTexture("Interface\\Minimap\\MinimapArrow")
        t:SetVertexColor(o[1], o[2], o[3], 1)
        local ag = t:CreateAnimationGroup(); ag:SetLooping("REPEAT")
        local r = ag:CreateAnimation("Rotation"); r:SetDegrees(-360); r:SetDuration(1)
        h.spin = { Show = function() t:Show(); ag:Play() end, Hide = function() ag:Stop(); t:Hide() end }
        t:Hide()
    end
    h.pm = h:CreateTexture(nil, "ARTWORK")
    h.pm:SetSize(16, 16); h.pm:SetPoint("RIGHT", -6, 0)
    h:SetScript("OnClick", function()
        RT:Open(db().open == "flow" and "none" or "flow")
    end)
    h:RegisterForDrag("LeftButton")  -- Shift-drag the header to move the tracker
    -- Shift-drag the header to move it. Docked under Questie's tracker, the
    -- drag undocks it; drop it just under Questie's tracker to dock again.
    h:SetScript("OnDragStart", function()
        if not IsShiftKeyDown() then return end
        if f.docked then
            local l, tp = f:GetLeft(), f:GetTop()
            db().dock = false
            f.docked = false
            if l and tp then
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, tp)
            end
        end
        f:StartMoving()
    end)
    h:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        f.pinTop()
        local q = _G.Questie_BaseFrame
        if q and q:IsShown() and q:GetLeft() and f:GetLeft()
            and math.abs(f:GetLeft() - q:GetLeft()) < 40 and math.abs(f:GetTop() - q:GetBottom()) < 40 then
            db().dock = true
            ns:Print("Flow Tracker docked under Questie's tracker again.")
            RT:Refresh()
        end
    end)
    f:SetMovable(true); f:SetClampedToScreen(true)
    f.header = h

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, 0)
    f.body:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", 0, 0)
    f.body.bg = f.body:CreateTexture(nil, "BACKGROUND"); f.body.bg:SetAllPoints()
    f.body.bg:SetColorTexture(0, 0, 0, 0.45)
    -- A faint rail down the left edge with a small down chevron at the end:
    -- the stops run top to bottom, 1 then 2 then 3.
    f.body.rail = f.body:CreateTexture(nil, "BORDER")
    f.body.rail:SetWidth(1)
    f.body.rail:SetPoint("TOPLEFT", 3, -6)
    f.body.rail:SetColorTexture(1, 1, 1, 0.14)
    f.body.chev = { f.body:CreateLine(nil, "BORDER"), f.body:CreateLine(nil, "BORDER") }
    for _, l in ipairs(f.body.chev) do l:SetThickness(1); l:SetColorTexture(1, 1, 1, 0.22) end
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, f.body)
        r:SetHeight(16)
        r:SetPoint("TOPLEFT", 8, -4 - (i - 1) * 17)
        r:SetPoint("TOPRIGHT", -6, -4 - (i - 1) * 17)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.open = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.open:SetPoint("RIGHT", 0, 0)
        r.open:SetText("open")
        r.open:Hide()
        r.text:SetPoint("LEFT"); r.text:SetPoint("RIGHT", r.open, "LEFT", -4, 0)
        r.text:SetHeight(16); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.08)
        r:SetScript("OnClick", function(self, button)
            if not self.goal then return end
            -- Its area lights up on the minimap (hover colour), next to the current stop's.
            if ns.minimapPin and ns.minimapPin.SetHover then pcall(ns.minimapPin.SetHover, ns.minimapPin, self.goal) end
            local g = self.goal
            if button == "RightButton" then
                local items = {
                    { title = true, text = g.text or g.title or "This stop" },
                    { text = "Open it", func = function() ns.nav:OpenStop(g, self) end },
                    { text = "Point the arrow here (your waypoint)", func = function() if ns.mapOverlay then ns.mapOverlay.PointHere(g) end end },
                    { text = "Hide this stop", func = function() ns.nav:Hide(g.key) end },
                    { sep = true },
                }
                for _, it in ipairs(ns.menu:RouteItems()) do items[#items + 1] = it end
                ns.menu:Open(items)
            elseif self.blocked then
                ns:Print((g.text or "that stop") .. ": " .. (self.blocked.blockedBy or "blocked"))
            else
                ns.nav:OpenStop(g, self)
            end
        end)
        r:SetScript("OnEnter", function(self)
            if not self.goal then return end
            -- Its area lights up on the minimap (hover colour), next to the current stop's.
            if ns.minimapPin and ns.minimapPin.SetHover then pcall(ns.minimapPin.SetHover, ns.minimapPin, self.goal) end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            -- Clickable rows say so: hand cursor and an "open" hint.
            if not self.blocked then self.open:Show(); ns.nav:ClickCursor(true) end
            ns.nav:FillTooltip(GameTooltip, self.goal, self.blocked
                and "Joins the route by itself once that's sorted. Right-click: menu."
                or "Click: open it. Right-click: menu. (Change the route on the world map.)")
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function(self)
            GameTooltip:Hide(); self.open:Hide(); ns.nav:ClickCursor(false)
            if ns.minimapPin and ns.minimapPin.SetHover then pcall(ns.minimapPin.SetHover, ns.minimapPin, nil) end
        end)
        f.rows[i] = r
    end
    return f
end

-- Docked under Questie's tracker (default when Questie is there): one
-- column. Flow's header hangs from the bottom of Questie's tracker and its
-- list opens downward; only one of the two is open at a time (or neither).
-- Move Questie's tracker and Flow's follows; when Questie's opens, Flow's
-- header moves down with it.
-- /flow tracker undock puts it back where you dragged it.
local function questieFrame()
    if db().dock == false then return nil end
    local q = _G.Questie_BaseFrame
    if q and q:IsShown() and q:GetWidth() > 50 then return q end
end

local function layout(q)
    local docked = q ~= nil
    if frame.docked ~= docked then
        frame.docked = docked
        frame:ClearAllPoints()
        if not docked then
            local p = db().point
            if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
            else frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -230) end
        end
    end
    if docked then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", q, "BOTTOMLEFT", 0, -2)
        frame:SetWidth(math.max(220, math.min(360, q:GetWidth())))
    else
        frame:SetWidth(260)
    end
end

function RT:Refresh()
    if not frame then return end
    local enabled = ns.db.tracker.enabled ~= false
    frame:SetShown(enabled)
    if not enabled then return end
    layout(questieFrame())
    local open = db().open == "flow"
    local plan = ns.nav and ns.nav.plan or {}
    local h = frame.header
    local nBlocked = ns.nav and ns.nav.blockedGoals and #ns.nav.blockedGoals or 0
    local busy = ns.nav and ns.nav.Busy and ns.nav.Busy()
    h.text:SetText(string.format("Flow Tracker  |cff888888%s|r%s", busy and "updating route..." or (#plan .. " stops"),
        nBlocked > 0 and string.format("  |cffff7070%d blocked|r", nBlocked) or ""))
    if busy ~= h.spinning then
        h.spinning = busy
        h.icon:SetShown(not busy)
        if busy then h.spin.Show() else h.spin.Hide() end
    end
    h.pm:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
    frame.body:SetShown(open)
    local shown = 0
    if open then
        local labels = ns.nav:PlanLabels(plan)
        local blocked = ns.nav.blockedGoals or {}
        -- Stops on the map (also here): only your next N rows, blocked ones after the route.
        local nRows = math.min(ROWS, ns.nav:StopsShown() or ROWS)
        local nPlan = math.min(#plan, nRows)
        for i = 1, ROWS do
            local r = frame.rows[i]
            local s = (i <= nPlan) and plan[i] or nil
            local bl = (not s and i <= nRows) and blocked[i - nPlan] or nil
            if s then
                -- (row colour comes from FormatStop)
                r.key, r.goal, r.blocked = s.goal.key, s.goal, nil
                r.text:SetText(ns.nav:FormatStop(i, s.goal, labels[i]))
                r:Show()
                shown = i
            elseif bl then
                r.key, r.goal, r.blocked = bl.key, bl, bl
                local text, why = ns.nav:FormatBlocked(bl)
                r.text:SetText(text .. "  " .. why)
                r:Show()
                shown = i
            else
                r:Hide()
            end
        end
        if shown == 0 then
            frame.rows[1].key, frame.rows[1].goal, frame.rows[1].blocked = nil, nil, nil
            frame.rows[1].text:SetText("|cff888888Nothing on your route right now.|r")
            frame.rows[1]:Show()
            shown = 1
        end
    end
    frame.body:SetHeight(8 + shown * 17)
    -- The order rail: as long as the list, chevron at the bottom (only with 2+ stops).
    local railLen = math.max(0, shown * 17 - 6)
    local rail = frame.body.rail
    rail:SetHeight(math.max(1, railLen))
    rail:SetShown(shown > 1)
    for k, l in ipairs(frame.body.chev) do
        l:SetStartPoint("TOPLEFT", frame.body, 3 + (k == 1 and -2.5 or 2.5), -6 - railLen + 3)
        l:SetEndPoint("TOPLEFT", frame.body, 3.5, -6 - railLen)
        l:SetShown(shown > 1)
    end
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
            if acc < ((ns.Lite and ns.Lite()) and 2 or 0.5) then return end   -- lite: every 2 s
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
    elseif arg == "dock" or arg == "undock" then
        db().dock = (arg == "dock")
        RT:Refresh()
        ns:Print(arg == "dock" and "Flow Tracker docked under Questie's tracker." or "Flow Tracker undocked (Shift-drag its header to move it).")
    elseif arg == "questie" or arg == "flow" then
        RT:Open(arg)
    else
        ns:Print("/flow tracker on|off|flow|questie|dock|undock")
    end
end

ns:Register("help", "tracker", { order = 42, title = "Flow Tracker", lines = {
    "Your next stops on screen, docked under Questie's tracker: one column, one open at a time (or neither).",
    "Click a stop to open it (quest log or map); right-click for a menu. Change the route on the world map.",
    "Shift-drag its header to move it (undocks); drop it under Questie's tracker to dock again. /flow tracker on|off|flow|questie|dock|undock",
} })

-- Timed for /flow perf.
RT.Refresh = ns.perf.Wrap("Flow Tracker", RT.Refresh)
