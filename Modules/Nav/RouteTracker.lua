-- Flow Tracker: everything to do around you and your waypoint (objectives
-- with counts, turn-ins, quests to accept, trainers...; they drop off as you
-- finish them), or your next stops as on the map (right-click its title).
-- Click a stop to open it (the quest, or the map at that stop); right-click a
-- stop for its menu (hide, route, order).
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

-- "Everything here" (on by default): the tracker lists every stop around
-- you and your waypoint, not just your next N (those stay on the map).
function RT.Here() return db().here ~= false end
function RT:SetHere(on)
    db().here = on and true or false
    self:Refresh()
end

-- Right-click on the title: the tracker's own options, then the route's.
function RT.MenuItems()
    local items = {
        { title = true, text = "Flow Tracker" },
        { text = "Everything here (around you and your waypoint)", radio = true, checked = RT.Here(),
          func = function() RT:SetHere(true) end },
        { text = "Next stops, as on the map (" .. ns.nav:StopsShownLabel() .. ")", radio = true, checked = not RT.Here(),
          func = function() RT:SetHere(false) end },
        { text = "Open (fold Questie's tracker)", checked = db().open == "flow",
          func = function() RT:Open(db().open == "flow" and "none" or "flow") end },
    }
    if questieTracker() then
        items[#items + 1] = { text = "Docked under Questie's tracker", checked = db().dock ~= false,
            func = function() ns.commands.tracker(db().dock ~= false and "undock" or "dock") end }
    end
    items[#items + 1] = { text = "Hide the Flow Tracker (/flow tracker on)", func = function() ns.commands.tracker("off") end }
    items[#items + 1] = { sep = true }
    for _, it in ipairs(ns.menu:RouteItems()) do items[#items + 1] = it end
    return items
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
    -- Left-click: open or fold it. Right-click: its menu.
    h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    h:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ns.menu:Open(RT.MenuItems()) return end
        RT:Open(db().open == "flow" and "none" or "flow")
    end)
    h:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Flow Tracker", 1, 1, 1)
        GameTooltip:AddLine("Click: open or fold it. Right-click: its menu. Shift-drag: move it.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
            ns.Tip(self, "ANCHOR_LEFT")
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
    -- Under the stops: ore and herbs you can gather around you and your next
    -- stop (Crafting/Nearby.lua). Not a stop, just "while you're here".
    local nb = CreateFrame("Button", nil, f.body)
    nb:SetHeight(16)
    nb.text = nb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nb.text:SetAllPoints(); nb.text:SetJustifyH("LEFT"); nb.text:SetWordWrap(false)
    nb:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_LEFT")
        local d = self.drop
        if d then
            GameTooltip:AddLine("Quest drop around here")
            GameTooltip:AddLine(string.format("%s, from %s, starts the quest %s. Kill them and loot it; their nameplates show a yellow !.",
                d.item, d.mob or "mobs here", d.quest or "?"), 1, 1, 1, true)
            GameTooltip:AddLine(" ")
        end
        GameTooltip:AddLine("Your professions, while you're here")
        for _, e in ipairs(self.counts or {}) do
            GameTooltip:AddDoubleLine(string.format("|T%s:14:14|t %s", ns.nearby.ICON[e.prof] or "", e.name),
                string.format("%d spot(s)%s", e.n, e.skillUp and ", raises your skill" or ""), 1, 1, 1, 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("Where they spawn within " .. ns.nearby.RADIUS .. " yd of you and your next stop: the tan (ore) and green (herb) clouds on the minimap. Not a stop of its own.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    nb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    nb:Hide()
    f.nearby = nb
    -- "Finishing Elwynn Forest first": the route stays in this zone until its
    -- quests are done (Nav.lua N.AreaSplit).
    f.zone = f.body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.zone:SetJustifyH("LEFT")
    f.zone:Hide()
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
    -- (New to Flow: it comes in a little after the arrow, Reveal.lua.)
    local enabled = ns.db.tracker.enabled ~= false and not (ns.reveal and not ns.reveal:Shown("tracker"))
    frame:SetShown(enabled)
    if not enabled then return end
    layout(questieFrame())
    local open = db().open == "flow"
    local plan = ns.nav and ns.nav.plan or {}
    local h = frame.header
    local nBlocked = ns.nav and ns.nav.blockedGoals and #ns.nav.blockedGoals or 0
    local busy = ns.nav and ns.nav.Busy and ns.nav.Busy()
    local count = (RT.Here() and #plan > 0)
        and string.format("%d here, %d stops", #ns.nav.HereStops(plan, ns.nav:PlayerPos()), #plan) or (#plan .. " stops")
    h.text:SetText(string.format("Flow Tracker  |cff888888%s|r%s", busy and "updating route..." or count,
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
        -- Which stops: everything to do here (the next stop and the stops
        -- around you or it; they drop off as you finish them), or your next
        -- N as on the map, blocked ones after the route.
        local here = RT.Here()
        local idx = here and ns.nav.HereStops(plan, ns.nav:PlayerPos()) or {}
        if not here then
            for i = 1, math.min(#plan, ns.nav:StopsShown() or ROWS) do idx[i] = i end
        end
        local nRows = here and ROWS or math.min(ROWS, ns.nav:StopsShown() or ROWS)
        local nPlan = math.min(#idx, nRows)
        for i = 1, ROWS do
            local r = frame.rows[i]
            local pi = (i <= nPlan) and idx[i] or nil
            local s = pi and plan[pi] or nil
            local bl = (not s and not here and i <= nRows) and blocked[i - nPlan] or nil
            if s then
                -- (row colour comes from FormatStop)
                r.key, r.goal, r.blocked = s.goal.key, s.goal, nil
                r.text:SetText(ns.nav:FormatStop(pi, s.goal, labels[pi]))
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
    -- "Nearby: Iron Deposit x3 +skill" under the stops (not part of the rail).
    local line, counts, drop
    if open and ns.nearby then line, counts, drop = ns.nearby.Now() end
    local nb = frame.nearby
    if line then
        nb.text:SetText(line)
        nb.counts, nb.drop = counts, drop
        nb:ClearAllPoints()
        nb:SetPoint("TOPLEFT", 8, -4 - shown * 17)
        nb:SetPoint("TOPRIGHT", -6, -4 - shown * 17)
        nb:Show()
    else
        nb:Hide()
    end
    local extra = line and 17 or 0
    local note = open and ns.nav and ns.nav.zoneNote
    if note then
        frame.zone:SetText(note .. ", then the next zone")
        frame.zone:ClearAllPoints()
        frame.zone:SetPoint("TOPLEFT", 8, -4 - shown * 17 - extra)
        frame.zone:SetPoint("TOPRIGHT", -6, -4 - shown * 17 - extra)
        frame.zone:Show()
        extra = extra + 15
    else
        frame.zone:Hide()
    end
    frame.body:SetHeight(8 + shown * 17 + extra)
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
    frame:SetHeight(24 + (open and (8 + shown * 17 + extra) or 0))
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
        -- 0.35.108: the tracker became "everything here", open by default:
        -- once, open it with that on (the menu changes either back).
        if not db().hereInit then
            db().hereInit = true
            db().here = true
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
    elseif arg == "here" or arg == "next" then
        RT:SetHere(arg == "here")
        ns:Print(arg == "here" and "Flow Tracker: everything around you and your waypoint."
            or "Flow Tracker: your next stops, as on the map.")
    else
        ns:Print("/flow tracker on|off|flow|questie|dock|undock|here|next")
    end
end

ns:Register("help", "tracker", { order = 42, title = "Flow Tracker", lines = {
    "Everything to do around you and your waypoint (or your next stops: right-click its title), docked under Questie's tracker, one open at a time.",
    "Click a stop to open it (quest log or map); right-click a stop or the title for a menu. Change the route on the world map.",
    "Shift-drag its header to move it (undocks); drop it under Questie's tracker to dock again. /flow tracker on|off|flow|questie|dock|undock|here|next",
} })

-- Timed for /flow perf.
RT.Refresh = ns.perf.Wrap("Flow Tracker", RT.Refresh)

-- A Flow window you can switch off (its menu, /flow tracker off): the menus offer it back (Menu.lua).
ns:Register("window", "tracker", { name = "Flow Tracker", order = 20,
    hidden = function() return ns.db.tracker.enabled == false end,
    show = function() ns.commands.tracker("on") end,
    hide = function() ns.commands.tracker("off") end })
