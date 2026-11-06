-- World map overlay: your route as numbered checkpoints and lines.
--   checkpoint label: "3 [9]" = 3rd stop, quest level 9; "!2 [8]" = 2nd quest pickup
--   colours (Theme.lua, colour-blind safe):
--     current route  bluish green      quest pickups (!N)  blue
--     preview route  yellow            hovered checkpoint  reddish purple
--     while previewing, your current route turns blue and the yellow lines
--     show the alternative, so you can compare.
--   Hover a checkpoint (or a place in the advice list) to preview the route
--   that starts there; click it to make that your route (the arrow follows).

local _, ns = ...
local M = {}
ns.mapOverlay = M

local host           -- frame on the map canvas holding lines
local lines, pins = {}, {}
local nLines, nPins = 0, 0
local previewKey, hoverKey

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
    l:SetThickness(4 / canvasScale())
    l:SetColorTexture(color[1], color[2], color[3], alpha or 0.9)
    l:SetStartPoint("TOPLEFT", c, x1 * w, -y1 * h)
    l:SetEndPoint("TOPLEFT", c, x2 * w, -y2 * h)
    l:Show()
end

local function pin(c, x, y, label, color, stop)
    nPins = nPins + 1
    local p = pins[nPins]
    if not p then
        p = CreateFrame("Button", nil, c)
        p:SetSize(16, 16)
        p.bg = p:CreateTexture(nil, "BACKGROUND")
        p.bg:SetAllPoints()
        p.edge = p:CreateTexture(nil, "BORDER")
        p.edge:SetPoint("TOPLEFT", -1, 1)
        p.edge:SetPoint("BOTTOMRIGHT", 1, -1)
        p.edge:SetColorTexture(0, 0, 0, 0.9)
        p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        p.text:SetPoint("LEFT", p, "RIGHT", 3, 0)
        p:SetScript("OnEnter", function(self)
            hoverKey = self.stop.goal.key
            M:Preview(hoverKey)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local g = self.stop.goal
            GameTooltip:AddLine(g.text or g.title or "?", 1, 1, 1, true)
            for _, d in ipairs(g.details or {}) do GameTooltip:AddLine(d, 0.8, 0.8, 0.8, true) end
            local c2 = theme().proposed
            GameTooltip:AddLine("Yellow: your route if you go here first. Click to choose it.", c2[1], c2[2], c2[3], true)
            GameTooltip:Show()
        end)
        p:SetScript("OnLeave", function()
            hoverKey = nil
            M:Preview(nil)
            GameTooltip:Hide()
        end)
        p:SetScript("OnClick", function(self)
            ns.nav:Select(self.stop.goal.key)
            M:Preview(nil)
            ns:Print("route updated: " .. (self.stop.goal.text or "?") .. " first")
        end)
        pins[nPins] = p
    end
    p.stop = stop
    p:SetParent(c)
    p:SetFrameLevel(2000)
    p:SetScale(1 / canvasScale())
    p:ClearAllPoints()
    local s = p:GetScale()
    p:SetPoint("CENTER", c, "TOPLEFT", x * c:GetWidth() / s, -y * c:GetHeight() / s)
    p.bg:SetColorTexture(color[1], color[2], color[3], 1)
    p.text:SetText(label)
    p.text:SetTextColor(color[1], color[2], color[3])
    p:Show()
end

-- Draws one route. Returns nothing; numbering: pickups "!k", others by order.
local function drawRoute(c, mapID, plan, color, withPins)
    if not plan then return end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    local px, py
    if pos then px, py = pos:GetXY() end
    local labels = ns.nav:PlanLabels(plan)
    for i, s in ipairs(plan) do
        local x, y = toMap(s.point, mapID)
        if x then
            if px then line(c, px, py, x, y, color, 0.9) end
            px, py = x, y
            if withPins then
                local pc = ns.nav:StopColor(i, s.goal)
                if s.goal.key == hoverKey then pc = theme().hover end
                pin(c, x, y, labels[i], pc, s)
            end
        else
            px, py = nil, nil  -- off this map: break the line
        end
    end
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

local function place()
    list:ClearAllPoints()
    local q = QuestMapFrame
    if q and q:IsShown() and q:GetWidth() > 100 then
        -- Take over the quest log area.
        list:SetPoint("TOPLEFT", q, "TOPLEFT", 0, 0)
        list:SetPoint("BOTTOMRIGHT", q, "BOTTOMRIGHT", 0, 0)
    else
        -- Dock outside, to the right of the map.
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

    -- The roll-up bar: always visible, very obvious.
    local t = CreateFrame("Button", "FlowMapRouteToggle", f)
    t:SetHeight(24)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetPoint("TOPRIGHT", 0, 0)
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    local o = theme().arrow
    t.bg:SetColorTexture(o[1], o[2], o[3], 0.95)
    t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t.text:SetPoint("CENTER")
    t.hl = t:CreateTexture(nil, "HIGHLIGHT")
    t.hl:SetAllPoints()
    t.hl:SetColorTexture(1, 1, 1, 0.15)
    t:SetScript("OnClick", function()
        ns.db.nav.mapListCollapsed = not collapsed()
        M:Redraw()
    end)
    t:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(collapsed() and "Show Flow's routed quest list" or "Hide it and use the game's own map and quest log")
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.toggle = t

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOPLEFT", 8, -30)
    f.title:SetPoint("TOPRIGHT", -8, -30)
    f.title:SetJustifyH("LEFT")

    f.rows = {}
    for i = 1, MAX_ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetHeight(ROW_H - 2)
        r:SetPoint("TOPLEFT", 8, -48 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -8, -48 - (i - 1) * ROW_H)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.1)
        r.leg = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.leg:SetPoint("RIGHT", 0, 0)
        r.leg:SetJustifyH("RIGHT")
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 0, 0)
        r.text:SetPoint("RIGHT", r.leg, "LEFT", -6, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:SetScript("OnEnter", function(self)
            hoverKey = self.key
            M:Preview(self.key)
        end)
        r:SetScript("OnLeave", function()
            hoverKey = nil
            M:Preview(nil)
        end)
        r:SetScript("OnClick", function(self)
            ns.nav:Select(self.key)
            M:Preview(nil)
        end)
        f.rows[i] = r
    end
    return f
end

local function updateList()
    list = list or buildList()
    local plan = ns.nav.plan
    if not plan or #plan == 0 then list:Hide() return end
    place()
    list:Show()
    local hidden = collapsed()
    list.toggle.text:SetText(hidden and "Show Flow route  (+)" or "Hide Flow route  (-)")
    list.bg:SetShown(not hidden)
    list.title:SetShown(not hidden)
    if hidden then
        -- Rolled up: only the bar remains, at the top of the area.
        for i = 1, MAX_ROWS do list.rows[i]:Hide() end
        return
    end
    local following = ns.party and ns.party:Following()
    list.title:SetText(string.format("%s: %d stops, about %d yd",
        following and "Party route" or "Your route", #plan, plan[#plan].cum or 0))
    local labels = ns.nav:PlanLabels(plan)
    local fit = math.min(MAX_ROWS, math.floor((list:GetHeight() - 54) / ROW_H))
    for i = 1, MAX_ROWS do
        local r, s = list.rows[i], plan[i]
        if s and i <= fit then
            local col = ns.nav:StopColor(i, s.goal)
            if s.goal.key == hoverKey then col = theme().hover end
            r.key = s.goal.key
            r.text:SetText(string.format("|cff%s%s|r %s", col.hex, labels[i], s.goal.text or s.goal.title or "?"))
            r.leg:SetText(string.format("+%d yd", s.leg or 0))
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
    host:SetFrameLevel(1999)
    -- Reuse frames in place and only hide leftovers afterwards: hiding the
    -- pin under the mouse would fire OnLeave and make previews flicker.
    local oldLines, oldPins = nLines, nPins
    nLines, nPins = 0, 0
    local mapID = WorldMapFrame:GetMapID()
    if mapID then
        local T = theme()
        if previewKey then
            -- Checkpoints stay those of your current route (now blue); the
            -- yellow lines show the route if you picked the hovered place.
            drawRoute(c, mapID, ns.nav.plan, T.changed, true)
            drawRoute(c, mapID, ns.nav:PlanFor(previewKey), T.proposed, false)
        else
            drawRoute(c, mapID, ns.nav.plan, T.current, true)
        end
    end
    for i = nLines + 1, oldLines do lines[i]:Hide() end
    for i = nPins + 1, oldPins do pins[i]:Hide() end
    updateList()
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
