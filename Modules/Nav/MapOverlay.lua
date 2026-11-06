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
-- Trip plan list beside the map: same numbers and colours as the pins.
-- Hover a row to preview, click to choose.
-------------------------------------------------------------------------------

local list
local LIST_ROWS = 12

local function buildList()
    local f = CreateFrame("Frame", "FlowMapTripList", WorldMapFrame)
    f:SetSize(250, 28 + LIST_ROWS * 16)
    f:SetPoint("BOTTOMLEFT", WorldMapFrame.ScrollContainer or WorldMapFrame, "BOTTOMLEFT", 8, 8)
    f:SetFrameStrata("HIGH")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.7)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOPLEFT", 8, -6)
    f.rows = {}
    for i = 1, LIST_ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(236, 15)
        r:SetPoint("TOPLEFT", 8, -22 - (i - 1) * 16)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.1)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetAllPoints()
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
    list.title:SetText(string.format("Flow trip plan: %d stops, about %d yd", #plan, plan[#plan].cum or 0))
    local labels = ns.nav:PlanLabels(plan)
    for i = 1, LIST_ROWS do
        local r, s = list.rows[i], plan[i]
        if s then
            local col = ns.nav:StopColor(i, s.goal)
            if s.goal.key == hoverKey then col = theme().hover end
            r.key = s.goal.key
            r.text:SetText(string.format("|cff%s%s|r %s", col.hex, labels[i], s.goal.text or s.goal.title or "?"))
            r:Show()
        else
            r:Hide()
        end
    end
    list:Show()
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
