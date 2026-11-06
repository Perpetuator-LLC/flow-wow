-- World map overlay: your route as numbered checkpoints and lines.
--   checkpoint label: "3 [9]" = 3rd stop, quest level 9; "!2 [8]" = 2nd quest pickup
--   colours (Theme.lua): the route and arrow colour shows the order mode
--     (purple = Most XP first, blue = Shortest path, gold = From selected stop);
--     a previewed route is yellow and yours turns grey meanwhile; the stop
--     under your mouse is red. /flow settings has a colour-blind palette.
--   Hover a checkpoint (or a place in the advice list) to preview the route
--   that starts there; click it to make that your route (the arrow follows).

local _, ns = ...
local M = {}
ns.mapOverlay = M

local host           -- frame on the map canvas holding lines
local lines, pins = {}, {}
local nLines, nPins = 0, 0
local previewKey, hoverKey
local focusKey, focusUntil = nil, 0   -- a stop opened from the tracker / arrow menu

local function theme() return ns.theme end

local function canvas()
    if not WorldMapFrame then return nil end
    if WorldMapFrame.GetCanvas then return WorldMapFrame:GetCanvas() end
    return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function canvasScale()
    local sc = WorldMapFrame.ScrollContainer
    return (sc and sc.GetCanvasScale and sc:GetCanvasScale()) or 1
end

-- Position (0-1) of a route point on the map being shown.
local function toMap(pt, mapID)
    if not pt then return nil end
    if pt.map == mapID and pt.x then return pt.x, pt.y end
    if pt.wx and pt.cont and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, pt.cont, CreateVector2D(pt.wx, pt.wy), mapID)
        if ok and pos then
            local x, y = pos:GetXY()
            if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
        end
    end
end

local function line(c, x1, y1, x2, y2, color, alpha)
    nLines = nLines + 1
    local l = lines[nLines]
    if not l then
        l = host:CreateLine(nil, "OVERLAY")
        lines[nLines] = l
    end
    local w, h = c:GetWidth(), c:GetHeight()
    l:SetThickness(2 / canvasScale())  -- thin, solid line
    l:SetColorTexture(color[1], color[2], color[3], alpha or 0.9)
    l:SetStartPoint("TOPLEFT", c, x1 * w, -y1 * h)
    l:SetEndPoint("TOPLEFT", c, x2 * w, -y2 * h)
    l:Show()
end

local function pin(c, x, y, label, color, stop, top)
    nPins = nPins + 1
    local p = pins[nPins]
    if not p then
        p = CreateFrame("Button", nil, c)
        -- A small round point: dark ring + coloured dot (the portrait mask
        -- is a white circle, tinted).
        p:SetSize(11, 11)
        local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
        p.edge = p:CreateTexture(nil, "BACKGROUND")
        p.edge:SetPoint("TOPLEFT", -2, 2)
        p.edge:SetPoint("BOTTOMRIGHT", 2, -2)
        p.edge:SetTexture(CIRCLE)
        p.edge:SetVertexColor(0, 0, 0, 0.9)
        p.bg = p:CreateTexture(nil, "BORDER")
        p.bg:SetAllPoints()
        p.bg:SetTexture(CIRCLE)
        p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        p.text:SetPoint("LEFT", p, "RIGHT", 3, 0)
        p:SetScript("OnEnter", function(self)
            hoverKey = self.stop.goal.key
            M:Preview(hoverKey)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local g = self.stop.goal
            ns.nav:FillTooltip(GameTooltip, g, "Yellow line: your route if you go here first. Click: go here first. Right-click: hide.")
            GameTooltip:Show()
        end)
        p:SetScript("OnLeave", function()
            hoverKey = nil
            M:Preview(nil)
            GameTooltip:Hide()
        end)
        p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        p:SetScript("OnClick", function(self, button)
            M:Preview(nil)
            if button == "RightButton" then
                ns.nav:Hide(self.stop.goal.key)
                ns:Print("hid " .. (self.stop.goal.text or "that stop") .. " (map panel: Show hidden stops to undo)")
                return
            end
            ns.nav:Select(self.stop.goal.key)
            ns:Print("route updated: " .. (self.stop.goal.text or "?") .. " first")
        end)
        pins[nPins] = p
    end
    p.stop = stop
    p:SetParent(c)
    -- The hovered stop: bigger, white ring, above every other pin and line.
    -- Relative to the map canvas: fixed numbers could end up under the map's own
    -- art (lakes, towns) when the canvas itself sits at a high level.
    local base = math.min(c:GetFrameLevel() + 1000, 9000)
    p:SetFrameLevel(top and base + 200 or base + 100)
    p:SetSize(top and 18 or 11, top and 18 or 11)
    p.edge:SetVertexColor(top and 1 or 0, top and 1 or 0, top and 1 or 0, top and 1 or 0.9)
    p.text:SetFontObject(top and "GameFontNormal" or "GameFontHighlightSmall")
    p:SetScale(1 / canvasScale())
    p:ClearAllPoints()
    local s = p:GetScale()
    p:SetPoint("CENTER", c, "TOPLEFT", x * c:GetWidth() / s, -y * c:GetHeight() / s)
    p.bg:SetVertexColor(color[1], color[2], color[3], 1)
    p.text:SetText(label)
    p:Show()
end

-- Draws one route as a thin, unbroken line through round points. Stops on
-- another map are skipped, and the line joins the ones on this map.
-- Each point's label carries the stop's type icon and number ("[icon] 3 [9]").
-- Direction: small chevrons travel along each leg ("marching ants"), so you
-- can see which way the route runs, and when a leg goes out and back.
-- Legs are kept from the last draw; only the chevrons move (cheap).
local legs, ants, nAnts = {}, {}, 0
local antPhase = 0
local ANT_GAP = 46    -- screen pixels between chevrons
local ANT_SIZE = 4

local function antLine()
    nAnts = nAnts + 1
    local l = ants[nAnts]
    if not l then l = host:CreateLine(nil, "OVERLAY", nil, 7); ants[nAnts] = l end
    return l
end

local function drawAnts()
    local c = canvas()
    if not (c and host) then return end
    local old = nAnts
    nAnts = 0
    local w, h, sc = c:GetWidth(), c:GetHeight(), canvasScale()
    local gap, size = ANT_GAP / sc, ANT_SIZE / sc
    for _, leg in ipairs(legs) do
        local x1, y1, x2, y2 = leg[1] * w, -leg[2] * h, leg[3] * w, -leg[4] * h
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        if len > gap * 0.6 then
            local ux, uy = dx / len, dy / len
            local d = (antPhase * gap) % gap
            local col = leg.color
            while d < len and nAnts < 400 do
                local cx, cy = x1 + ux * d, y1 + uy * d
                -- ">" pointing along the leg: two arms back from the tip.
                for side = -1, 1, 2 do
                    local l = antLine()
                    l:SetThickness(1.6 / sc)
                    l:SetColorTexture(col[1], col[2], col[3], leg.alpha or 0.95)
                    l:SetStartPoint("TOPLEFT", c, cx - ux * size + side * uy * size * 0.8, cy - uy * size - side * ux * size * 0.8)
                    l:SetEndPoint("TOPLEFT", c, cx + ux * size * 0.4, cy + uy * size * 0.4)
                    l:Show()
                end
                d = d + gap
            end
        end
    end
    for i = nAnts + 1, old do ants[i]:Hide() end
end

-- Draws one route as a thin, unbroken line through round points, starting
-- at you. Stops on another map are skipped, and the line joins the ones on
-- this map. Each point's label carries the stop's type icon and number.
local function drawRoute(c, mapID, plan, color, withPins, alpha)
    if not plan then return end
    local px, py = toMap(ns.nav:PlayerPos(), mapID)
    local labels = ns.nav:PlanLabels(plan)
    local hovered
    for i, s in ipairs(plan) do
        local x, y = toMap(s.point, mapID)
        if x then
            if px then
                -- From you to the first stop: brighter, so it's clear where to go now.
                local first = (i == 1)
                line(c, px, py, x, y, first and theme().route or color, first and 1 or (alpha or 0.95))
                legs[#legs + 1] = { px, py, x, y, color = first and { 1, 1, 1 } or color, alpha = first and 1 or (alpha or 0.95) }
            end
            px, py = x, y
            if withPins then
                local kind = ns.theme.kinds[ns.nav:StopKind(s.goal)]
                local icon = kind and string.format("|T%s:12:12|t", kind.icon) or ""
                if s.goal.key == hoverKey or (focusKey and s.goal.key == focusKey and GetTime() < focusUntil) then
                    hovered = { x, y, icon .. labels[i], s }
                else
                    pin(c, x, y, icon .. labels[i], color, s)
                end
            end
        end
    end
    -- The stop you're pointing at (here or in the list) goes on top of everything.
    if hovered then pin(c, hovered[1], hovered[2], hovered[3], theme().hover, hovered[4], true) end
end

-------------------------------------------------------------------------------
-- Route panel: the trip plan as a routed quest log. It takes over the game's
-- quest log area on the right of the map when that's open, otherwise it sits
-- just outside the map on the right, so it never covers the map itself.
-- The orange "Flow route" bar at its top rolls it up (showing the default
-- quest log / map again) and brings it back. Same numbers and colours as the
-- map pins; hover a row to preview, click to choose.
-------------------------------------------------------------------------------

local list
local MAX_ROWS = 26
local ROW_H = 18

local function collapsed() return ns.db.nav.mapListCollapsed == true end

-- The game's quest log side panel and Flow's route drawer share one slot:
-- only one is open at a time, and both can be closed (like the trackers).
-- Flow's square button sits just above the game's own side-panel button.
local function sidePanelOpen()
    local q = QuestMapFrame
    return q and q:IsShown() and q:GetWidth() > 100 or false
end

local selfToggling = false
local function setSidePanel(open)
    if sidePanelOpen() == open then return end
    selfToggling = true
    if WorldMapFrame.HandleUserActionToggleSidePanel then
        pcall(WorldMapFrame.HandleUserActionToggleSidePanel, WorldMapFrame)
    elseif WorldMapFrame.SidePanelToggle and WorldMapFrame.SidePanelToggle.Click then
        pcall(WorldMapFrame.SidePanelToggle.Click, WorldMapFrame.SidePanelToggle)
    end
    selfToggling = false
end

function M:SetDrawer(open)
    ns.db.nav.mapListCollapsed = not open
    setSidePanel(open)  -- open: make room (the drawer covers the panel); closed: both closed
    M:Redraw()
end

local button
local function buildButton()
    local blizz = WorldMapFrame.SidePanelToggle
    local b = CreateFrame("Button", "FlowMapDrawerButton", WorldMapFrame)
    local w, h = 32, 32
    if blizz and blizz.GetSize then
        local bw, bh = blizz:GetSize()
        if bw and bw > 10 then w, h = bw, bh end
    end
    b:SetSize(w, h)
    if blizz then
        b:SetPoint("BOTTOM", blizz, "TOP", 0, 4)
    else
        b:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -6, 46)
    end
    b:SetFrameStrata("HIGH")
    b:SetFrameLevel((blizz and blizz:GetFrameLevel() or 10) + 5)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.edge = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                           { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = b:CreateTexture(nil, "BORDER")
        t:SetPoint(pts[1]); t:SetPoint(pts[2])
        if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
        b.edge[i] = t
    end
    -- A chevron drawn with two lines: "<" opens the drawer, ">" closes it.
    b.arms = { b:CreateLine(nil, "ARTWORK"), b:CreateLine(nil, "ARTWORK") }
    for _, l in ipairs(b.arms) do l:SetThickness(2) end
    function b:Draw()
        local open = not collapsed()
        local c = theme().route
        local hot = self:IsMouseOver()
        self.bg:SetColorTexture(open and c[1] * 0.25 or 0.05, open and c[2] * 0.25 or 0.05, open and c[3] * 0.25 or 0.08, 0.92)
        for _, t in ipairs(self.edge) do t:SetColorTexture(c[1], c[2], c[3], hot and 1 or 0.75) end
        local dir = open and 1 or -1   -- points right when open (push it away), left when closed
        local s = math.min(self:GetWidth(), self:GetHeight()) * 0.18
        for i, l in ipairs(self.arms) do
            l:SetStartPoint("CENTER", self, -dir * s * 0.6, (i == 1 and 1 or -1) * s)
            l:SetEndPoint("CENTER", self, dir * s * 0.6, 0)
            l:SetColorTexture(1, 1, 1, hot and 1 or 0.85)
        end
    end
    b:SetScript("OnClick", function() M:SetDrawer(collapsed()) end)
    b:SetScript("OnEnter", function(self)
        self:Draw()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Flow route")
        GameTooltip:AddLine(collapsed() and "Open Flow's route list (closes the quest log)."
            or "Close Flow's route list.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self:Draw(); GameTooltip:Hide() end)
    -- The game's own button: opening the quest log closes Flow's drawer.
    if blizz and blizz.HookScript then
        blizz:HookScript("OnClick", function()
            if selfToggling then return end
            ns.db.nav.mapListCollapsed = true
            M:Redraw()
        end)
    end
    return b
end

local function place()
    list:ClearAllPoints()
    local q = QuestMapFrame
    if q and q:IsShown() and q:GetWidth() > 100 then
        -- Cover the quest log slot exactly (the quest log is "closed" while
        -- the drawer is open).
        list:SetPoint("TOPLEFT", q, "TOPLEFT", 0, 0)
        list:SetPoint("BOTTOMRIGHT", q, "BOTTOMRIGHT", 0, 0)
    else
        -- No side panel on this client: dock outside, to the right of the map.
        list:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 2, 0)
        list:SetSize(300, math.max(200, WorldMapFrame:GetHeight()))
    end
end

local function buildList()
    local f = CreateFrame("Frame", "FlowMapRoute", WorldMapFrame)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.04, 0.04, 0.07, 0.95)

    -- The roll-up bar: always visible. A dark header with an orange accent,
    -- a map icon, the title, and a +/- button on the right.
    local t = CreateFrame("Button", "FlowMapRouteToggle", f)
    t:SetHeight(26)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetPoint("TOPRIGHT", 0, 0)
    local o = theme().arrow
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.bg:SetColorTexture(0.11, 0.09, 0.06, 0.97)
    t.accent = t:CreateTexture(nil, "BORDER")
    t.accent:SetPoint("TOPLEFT"); t.accent:SetPoint("BOTTOMLEFT")
    t.accent:SetWidth(4)
    t.accent:SetColorTexture(o[1], o[2], o[3], 1)
    t.line = t:CreateTexture(nil, "BORDER")
    t.line:SetPoint("BOTTOMLEFT"); t.line:SetPoint("BOTTOMRIGHT")
    t.line:SetHeight(1)
    t.line:SetColorTexture(o[1], o[2], o[3], 0.8)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(18, 18)
    t.icon:SetPoint("LEFT", 10, 0)
    t.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.text:SetPoint("LEFT", t.icon, "RIGHT", 8, 0)
    t.state = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    t.state:SetPoint("RIGHT", -32, 0)
    t.pm = t:CreateTexture(nil, "ARTWORK")
    t.pm:SetSize(18, 18)
    t.pm:SetPoint("RIGHT", -8, 0)
    t.hl = t:CreateTexture(nil, "HIGHLIGHT")
    t.hl:SetAllPoints()
    t.hl:SetColorTexture(o[1], o[2], o[3], 0.12)
    t:SetScript("OnClick", function()
        M:SetDrawer(collapsed())
    end)
    t:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(collapsed() and "Show Flow's routed quest list" or "Hide it and use the game's own map and quest log")
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.toggle = t
    t:Hide()  -- the square map button opens and closes the drawer now

    -- How to use it, and which route to follow.
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("TOPLEFT", 8, -6)
    f.hint:SetPoint("TOPRIGHT", -8, -6)
    f.hint:SetJustifyH("LEFT")
    f.hint:SetText("Click a stop to follow that route. Hover to preview it on the map.")

    local function choice(y, mode, text, tip)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", 6, y)
        cb.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.label:SetText(text)
        cb.mode = mode
        cb:SetScript("OnClick", function()
            ns.nav:SetMode(mode)
            M:Redraw()
        end)
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return cb
    end
    f.modeQuests = choice(-20, "quests", "Follow current quests",
        "Only the quests already in your log: their objectives, then turn-ins.")
    f.modeOptimal = choice(-38, "optimal", "Follow optimal path",
        "Everything worth doing nearby: your quests plus quests to pick up, trainers, and fishing or gathering when it's on the way.")

    -- Include professions (trainers to learn/raise them, and skill-up stops).
    local pc = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    pc:SetSize(20, 20)
    pc:SetPoint("TOPLEFT", 26, -58)
    pc.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pc.label:SetPoint("LEFT", pc, "RIGHT", 2, 0)
    pc.label:SetText("Include professions")
    pc:SetScript("OnClick", function(self)
        ns.db.nav.professions = self:GetChecked() and true or false
        ns.nav:Collect()
        M:Redraw()
    end)
    pc:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Trainers for professions you plan or have capped, and fishing / mining stops when a skill is behind your level.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pc:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.profs = pc

    -- Show hidden stops (greyed out at the end of the list; click to unhide).
    local hc = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    hc:SetSize(20, 20)
    hc:SetPoint("TOPLEFT", 170, -82)
    hc.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hc.label:SetPoint("LEFT", hc, "RIGHT", 2, 0)
    hc.label:SetText("Show hidden stops")
    hc:SetScript("OnClick", function(self)
        ns.db.nav.showHidden = self:GetChecked() and true or false
        M:Redraw()
    end)
    hc:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Right-click any stop (here or on the map) to hide it. Tick this to see hidden ones and click one to bring it back.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hc:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.showHidden = hc
    hc:Hide(); hc.label:Hide()  -- hidden stops are always listed now

    -- Route sorting (XpValue.lua): three modes, one row of radios.
    f.sorts = {}
    local SORTS = {
        { "xp", "Most XP", 6, "Most XP first (default): the shortest path, but quests are weighed by XP and level. More XP is worth a longer walk; quests 3+ levels above you wait." },
        { "distance", "Shortest", 92, "Shortest path: nearest stops first, XP ignored." },
        { "selected", "From selected", 172, "From the stop you clicked on the map: it goes first, the rest is planned after it. Picking another mode clears it." },
    }
    for _, sdef in ipairs(SORTS) do
        local rb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        rb:SetSize(20, 20)
        rb:SetPoint("TOPLEFT", sdef[3], -78)
        rb.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rb.label:SetPoint("LEFT", rb, "RIGHT", 1, 0)
        rb.label:SetText(sdef[2])
        rb.mode = sdef[1]
        rb:SetScript("OnClick", function() ns.xpValue:SetMode(sdef[1]); M:Redraw() end)
        rb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(sdef[4], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        rb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.sorts[#f.sorts + 1] = rb
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOPLEFT", 8, -102)
    f.title:SetPoint("TOPRIGHT", -8, -102)
    f.title:SetJustifyH("LEFT")

    -- Each row: [^] handle, then the stop.
    --   ^ handle    route from this stop (like clicking it on the map);
    --               hovering it previews that route
    --   row hover   the stop's details (quest objectives and text)
    --   row click   open it (quest details, closing this drawer)
    --   right-click menu
    f.rows = {}
    for i = 1, MAX_ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetHeight(ROW_H - 2)
        r:SetPoint("TOPLEFT", 8, -120 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -8, -120 - (i - 1) * ROW_H)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.1)
        r.go = CreateFrame("Button", nil, r)
        r.go:SetSize(ROW_H - 2, ROW_H - 2)
        r.go:SetPoint("LEFT", 0, 0)
        r.go.bg = r.go:CreateTexture(nil, "BACKGROUND")
        r.go.bg:SetAllPoints()
        r.go.arms = { r.go:CreateLine(nil, "ARTWORK"), r.go:CreateLine(nil, "ARTWORK") }
        for k, l in ipairs(r.go.arms) do
            l:SetThickness(2)
            l:SetStartPoint("CENTER", r.go, (k == 1 and -1 or 1) * 4, -2)
            l:SetEndPoint("CENTER", r.go, 0, 3)
        end
        function r.go:Paint(hot)
            local c = theme().route
            self.bg:SetColorTexture(c[1], c[2], c[3], hot and 0.55 or 0.18)
            for _, l in ipairs(self.arms) do l:SetColorTexture(1, 1, 1, hot and 1 or 0.8) end
        end
        r.go:Paint(false)
        r.go:SetScript("OnEnter", function(self)
            self:Paint(true)
            local row = self:GetParent()
            hoverKey = row.key
            M:Preview(row.key)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Go here first")
            GameTooltip:AddLine("Routes from this stop (order: From selected stop). Shown in the preview colour on the map.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        r.go:SetScript("OnLeave", function(self)
            self:Paint(false)
            hoverKey = nil
            M:Preview(nil)
            GameTooltip:Hide()
        end)
        r.go:SetScript("OnClick", function(self)
            local row = self:GetParent()
            M:Preview(nil)
            if row.key then ns.nav:Select(row.key) end
            M:Redraw()
        end)
        r.leg = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.leg:SetPoint("RIGHT", 0, 0)
        r.leg:SetJustifyH("RIGHT")
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r.go, "RIGHT", 5, 0)
        r.text:SetPoint("RIGHT", r.leg, "LEFT", -6, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:SetScript("OnEnter", function(self)
            local g = self.blocked or self.goal
            if not g then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local footer
            if self.isHidden then footer = "Hidden. Click to bring it back."
            elseif self.blocked then footer = "Joins the route by itself once that's sorted. Right-click: menu."
            else footer = "Click: open it. ^: go here first. Right-click: menu." end
            ns.nav:FillTooltip(GameTooltip, g, footer)
            GameTooltip:Show()
            if not (self.isHidden or self.blocked) then hoverKey = self.key; M:Redraw() end
        end)
        r:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if hoverKey then hoverKey = nil; M:Redraw() end
        end)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, button)
            M:Preview(nil)
            local g = self.blocked or self.goal
            if self.isHidden then
                ns.nav:Unhide(self.key)        -- either click brings it back
            elseif button == "RightButton" and g then
                local items = {
                    { title = true, text = g.text or g.title or "This stop" },
                    { text = "Open it", func = function() ns.nav:OpenStop(g) end },
                    { text = "Go here first", disabled = self.blocked ~= nil, func = function() ns.nav:Select(g.key) end },
                    { text = "Hide this stop", func = function() ns.nav:Hide(g.key) end },
                    { sep = true },
                }
                for _, it in ipairs(ns.menu:RouteItems()) do items[#items + 1] = it end
                ns.menu:Open(items)
            elseif self.blocked then
                ns:Print((g.text or "that stop") .. ": " .. (g.blockedBy or "blocked"))
            elseif g then
                ns.nav:OpenStop(g)
            end
            M:Redraw()
        end)
        f.rows[i] = r
    end
    return f
end

local function updateList()
    list = list or buildList()
    button = button or buildButton()
    button:Draw()
    local plan = ns.nav.plan
    -- Keep the panel up even with an empty route, so the mode can be switched back.
    plan = plan or {}
    if not ns.nav:PlayerPos() then list:Hide() return end
    -- Drawer open but the slot closed (e.g. map reopened): make room again.
    if not collapsed() and QuestMapFrame and not sidePanelOpen() and not InCombatLockdown() then setSidePanel(true) end
    if collapsed() then list:Hide() return end
    place()
    list:Show()
    local hidden = collapsed()
    list.toggle.text:SetText("Flow route")
    list.toggle.state:SetText(hidden and "show" or "hide")
    list.toggle.pm:SetTexture(hidden and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    list.bg:SetShown(not hidden)
    list.title:SetShown(not hidden)
    list.hint:SetShown(not hidden)
    list.modeQuests:SetShown(not hidden); list.modeQuests.label:SetShown(not hidden)
    list.modeOptimal:SetShown(not hidden); list.modeOptimal.label:SetShown(not hidden)
    local mode = ns.nav:Mode()
    list.modeQuests:SetChecked(mode == "quests")
    list.modeOptimal:SetChecked(mode == "optimal")
    -- Professions only matter on the optimal path.
    local showProfs = not hidden and mode == "optimal"
    list.profs:SetShown(showProfs); list.profs.label:SetShown(showProfs)
    list.profs:SetChecked(ns.db.nav.professions ~= false)
    for _, rb in ipairs(list.sorts) do rb:SetChecked(ns.xpValue:Mode() == rb.mode) end
    if hidden then
        -- Rolled up: only the bar remains, at the top of the area.
        for i = 1, MAX_ROWS do list.rows[i]:Hide() end
        return
    end
    local following = ns.party and ns.party:Following()
    local nBlocked = ns.nav.blockedGoals and #ns.nav.blockedGoals or 0
    list.title:SetText(string.format("%s: %d stops, about %d yd%s",
        following and "Party route" or "Your route", #plan, plan[#plan] and plan[#plan].cum or 0,
        nBlocked > 0 and string.format("  |cffff7070(%d blocked, listed below)|r", nBlocked) or ""))
    if #plan == 0 then list.title:SetText("Nothing on this route right now. Try \"Follow optimal path\".") end
    local labels = ns.nav:PlanLabels(plan)
    local fit = math.min(MAX_ROWS, math.floor((list:GetHeight() - 126) / ROW_H))
    -- Route stops first, then blocked stops (lock + reason), then (if
    -- ticked) hidden stops, greyed out.
    local blocked = ns.nav.blockedGoals or {}
    local hiddenGoals = ns.nav.hiddenGoals or {}  -- always listed, greyed out
    -- One list of rows: route stops, then blocked, then hidden. Blocked and
    -- hidden rows always get room (up to half the list), so a full route
    -- can't push them out of sight.
    local entries = {}
    local extras = #blocked + #hiddenGoals
    local reserve = math.min(extras, math.floor(fit / 2))
    for i, s in ipairs(plan) do
        if i > fit - reserve then break end
        entries[#entries + 1] = { stop = s, i = i }
    end
    for _, b in ipairs(blocked) do entries[#entries + 1] = { blocked = b } end
    for _, h in ipairs(hiddenGoals) do entries[#entries + 1] = { hidden = h } end
    for i = 1, MAX_ROWS do
        local r, e = list.rows[i], entries[i]
        if e and i <= fit and e.stop then
            local s = e.stop
            r.key, r.isHidden, r.blocked = s.goal.key, false, nil
            r.goal = s.goal
            r.go:Show()
            r.text:SetText(ns.nav:FormatStop(e.i, s.goal, labels[e.i]))
            r.leg:SetText(string.format("+%d yd", s.leg or 0))
            r:Show()
        elseif e and i <= fit and e.blocked then
            local b = e.blocked
            r.key, r.isHidden, r.blocked, r.goal = b.key, false, b, b
            r.go:Hide()
            local text, why = ns.nav:FormatBlocked(b)
            r.text:SetText(text)
            r.leg:SetText(why)
            r:Show()
        elseif e and i <= fit and e.hidden then
            local h = e.hidden
            r.key, r.isHidden, r.blocked, r.goal = h.key, true, nil, h
            r.go:Hide()
            r.text:SetText("|cff777777(hidden) " .. (h.text or h.title or "?") .. "|r")
            r.leg:SetText("|cff777777click to show|r")
            r:Show()
        else
            r:Hide()
        end
    end
end

function M:Redraw()
    local c = canvas()
    if not (c and WorldMapFrame:IsShown() and ns.nav and ns.db.nav.mapRoute ~= false) then return end
    if not host then
        host = CreateFrame("Frame", nil, c)
        host:SetAllPoints(c)
        host:EnableMouse(false)
    end
    host:SetFrameLevel(math.min(c:GetFrameLevel() + 1000, 9000))
    -- Reuse frames in place and only hide leftovers afterwards: hiding the
    -- pin under the mouse would fire OnLeave and make previews flicker.
    local oldLines, oldPins = nLines, nPins
    legs = {}
    nLines, nPins = 0, 0
    local mapID = WorldMapFrame:GetMapID()
    if mapID then
        local T = theme()
        if previewKey then
            -- Your current route turns blue (sky blue when colour-blind) and
            -- the yellow (purple) line shows the route if you picked the hovered place.
            drawRoute(c, mapID, ns.nav.plan, T.changed, true, 0.6)
            drawRoute(c, mapID, ns.nav:PlanFor(previewKey), T.proposed, false, 0.95)
        else
            drawRoute(c, mapID, ns.nav.plan, T.route, true)
        end
    end
    for i = nLines + 1, oldLines do lines[i]:Hide() end
    for i = nPins + 1, oldPins do pins[i]:Hide() end
    drawAnts()
    if not host.antsOn then
        host.antsOn = true
        host:SetScript("OnUpdate", function(_, dt)
            antPhase = antPhase + dt * 0.6   -- chevrons crawl along the route
            host.antT = (host.antT or 0) + dt
            if host.antT > 0.05 then host.antT = 0; drawAnts() end
        end)
    end
    updateList()
end

-- Highlight one stop for a few seconds (opened from the tracker or arrow menu).
function M:Focus(key)
    focusKey, focusUntil = key, GetTime() + 6
    M:Redraw()
    C_Timer.After(6.1, function() if WorldMapFrame:IsShown() then M:Redraw() end end)
end

function M:Preview(key)
    if previewKey == key then return end
    previewKey = key
    pcall(M.Redraw, M)
end

ns:OnLoad(function()
    local acc = 0
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.5 then return end
        acc = 0
        if WorldMapFrame and WorldMapFrame:IsShown() then pcall(M.Redraw, M) end
    end)
end)

ns.commands.map = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.nav.mapRoute = (arg == "on")
        if arg == "off" then
            for i = 1, nLines do lines[i]:Hide() end
            for i = 1, nPins do pins[i]:Hide() end
            if list then list:Hide() end
        end
        ns:Print("route on the world map " .. arg)
    else
        ns:Print("/flow map on|off. Hover a checkpoint to preview, click to choose. Alt-click the map to set a waypoint.")
    end
end
