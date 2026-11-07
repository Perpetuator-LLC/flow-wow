-- Your current route stop on the minimap: a dot in the route colour (with
-- the stop type's icon on hover). At the edge of the minimap when it's
-- further away than the minimap shows.

local _, ns = ...
local P = {}
ns.minimapPin = P

-- Minimap diameter in yards per zoom level (as used by the common map libraries).
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR  = { [0] = 300, 240, 180, 120, 80, 50 }

local pin
local function build()
    pin = CreateFrame("Button", "FlowMinimapPin", Minimap)
    pin:SetSize(14, 14)
    pin:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    pin.edge = pin:CreateTexture(nil, "BACKGROUND")
    pin.edge:SetPoint("TOPLEFT", -2, 2); pin.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    pin.edge:SetTexture(CIRCLE)
    pin.edge:SetVertexColor(0, 0, 0, 0.9)
    -- Flow's target marker (o): ring in the route colour, a dark gap, the dot.
    pin.ring = pin:CreateTexture(nil, "BORDER")
    pin.ring:SetAllPoints()
    pin.ring:SetTexture(CIRCLE)
    pin.hole = pin:CreateTexture(nil, "ARTWORK", nil, 1)
    pin.hole:SetPoint("TOPLEFT", 2, -2); pin.hole:SetPoint("BOTTOMRIGHT", -2, 2)
    pin.hole:SetTexture(CIRCLE)
    pin.hole:SetVertexColor(0.05, 0.05, 0.08, 1)
    pin.dot = pin:CreateTexture(nil, "ARTWORK", nil, 2)
    pin.dot:SetPoint("TOPLEFT", 4, -4); pin.dot:SetPoint("BOTTOMRIGHT", -4, 4)
    pin.dot:SetTexture(CIRCLE)
    pin:SetScript("OnEnter", function(self)
        if not self.goal then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Flow: " .. (self.goal.text or self.goal.title or "next stop"), 1, 1, 1, true)
        if self.yards then GameTooltip:AddLine(string.format("%d yd", self.yards), 0.8, 0.8, 0.8) end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:Hide()
end

local function indoors()
    return IsIndoors and IsIndoors() or false
end

-- World point -> minimap pixels from the centre (rotation included), and
-- pixels per yard.
local function toMini(p, wx, wy)
    local east, south = ns.nav:Offset(p, wx, wy)
    if not east then return nil end
    local zoom = Minimap:GetZoom() or 0
    local yards = (indoors() and INDOOR or OUTDOOR)[zoom] or 466
    local radius = Minimap:GetWidth() / 2
    local scale = radius / (yards / 2)            -- pixels per yard
    local x, y = east * scale, -south * scale
    -- Rotating minimap: turn the offset with the player's facing.
    if GetCVar and GetCVar("rotateMinimap") == "1" then
        local f = ns.api.Safe(GetPlayerFacing and GetPlayerFacing())
        if f then
            local c, s = math.cos(f), -math.sin(f)   -- turn by -facing: what you face is up
            x, y = x * c - y * s, x * s + y * c
        end
    end
    return x, y, scale, east, south
end

-------------------------------------------------------------------------------
-- Areas on the minimap: the same patches as the world map (spawn discs and a
-- border), for the stop the arrow points at, and, while you hover a row in
-- the Flow Tracker, for that stop in the hover colour. So you can tell at a
-- glance whether you're standing in this stop's area, the next one's, or both.
-------------------------------------------------------------------------------

local AREA_YARDS = 45
local discs, nDiscs, edges, nEdges = {}, 0, {}, 0
local hoverGoal
local areaHost

local function disc(x, y, r, color, alpha)
    nDiscs = nDiscs + 1
    local t = discs[nDiscs]
    if not t then
        t = areaHost:CreateTexture(nil, "BACKGROUND")
        t:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        discs[nDiscs] = t
    end
    t:SetSize(r * 2, r * 2)
    t:ClearAllPoints()
    t:SetPoint("CENTER", Minimap, "CENTER", x, y)
    t:SetVertexColor(color[1], color[2], color[3], alpha)
    t:Show()
end

local function edge(x1, y1, x2, y2, color, alpha)
    nEdges = nEdges + 1
    local l = edges[nEdges]
    if not l then
        l = areaHost:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        edges[nEdges] = l
    end
    l:SetStartPoint("CENTER", Minimap, x1, y1)
    l:SetEndPoint("CENTER", Minimap, x2, y2)
    l:SetColorTexture(color[1], color[2], color[3], alpha)
    l:Show()
end

local function drawAreaMini(p, goal, color, strong)
    if not (goal and goal.area and goal.points) then return end
    local radius = Minimap:GetWidth() / 2
    local pts, r = {}, nil
    for _, pt in ipairs(goal.points) do
        if pt.wx and pt.cont == p.cont then
            local x, y, scale = toMini(p, pt.wx, pt.wy)
            if x then
                r = r or math.max(3, AREA_YARDS * scale)
                if math.sqrt(x * x + y * y) < radius - r * 0.5 then pts[#pts + 1] = { x, y } end
            end
        end
    end
    if #pts == 0 then return end
    local M = ns.mapOverlay
    for _, q in ipairs(pts) do disc(q[1], q[2], r, color, strong and 0.3 or 0.18) end
    if not (M and M._hull and M._clusters) then return end
    for _, group in ipairs(M._clusters(pts, r * 3)) do
        local ring = {}
        for _, q in ipairs(group) do
            for k = 0, 11 do
                local a = k * math.pi / 6
                ring[#ring + 1] = { q[1] + r * math.cos(a), q[2] + r * math.sin(a) }
            end
        end
        local hull = M._hull(ring)
        for i = 1, #hull do
            local a, b = hull[i], hull[i % #hull + 1]
            -- Only inside the round minimap.
            if a[1] * a[1] + a[2] * a[2] < radius * radius and b[1] * b[1] + b[2] * b[2] < radius * radius then
                edge(a[1], a[2], b[1], b[2], color, strong and 0.95 or 0.7)
            end
        end
    end
end

local lastAreas = 0
function P:UpdateAreas(p, goal, force)
    if not Minimap then return end
    if not force and GetTime() - lastAreas < 0.2 then return end
    lastAreas = GetTime()
    if not areaHost then
        areaHost = CreateFrame("Frame", nil, Minimap)
        areaHost:SetAllPoints(Minimap)
        areaHost:SetFrameLevel(Minimap:GetFrameLevel() + 2)   -- under the pin
    end
    local oldD, oldE = nDiscs, nEdges
    nDiscs, nEdges = 0, 0
    if ns.db.nav.minimapPin ~= false and ns.db.nav.minimapAreas ~= false and p then
        if hoverGoal and hoverGoal ~= goal then drawAreaMini(p, hoverGoal, ns.theme.hover, true) end
        drawAreaMini(p, goal, ns.theme.route, hoverGoal == nil or hoverGoal == goal)
    end
    for i = nDiscs + 1, oldD do discs[i]:Hide() end
    for i = nEdges + 1, oldE do edges[i]:Hide() end
end

-- The Flow Tracker calls this while you hover one of its rows (nil = none).
function P:SetHover(goal)
    hoverGoal = goal
    P.lastP = P.lastP or (ns.nav and ns.nav:PlayerPos())
    P:UpdateAreas(P.lastP, P.lastGoal, true)
end

-- p: player position (Nav:PlayerPos), pt: the stop's point, goal: the stop.
function P:Update(p, pt, goal)
    if not Minimap then return end
    if not pin then build() end
    P.lastP, P.lastGoal = p, goal
    pcall(P.UpdateAreas, P, p, goal)
    if ns.db.nav.minimapPin == false or not (p and pt and pt.wx and pt.cont == p.cont) then pin:Hide() return end
    local x, y, _, east, south = toMini(p, pt.wx, pt.wy)
    if not x then pin:Hide() return end
    local radius = Minimap:GetWidth() / 2
    local d = math.sqrt(x * x + y * y)
    local edge = d > radius - 6
    if edge then x, y = x / d * (radius - 6), y / d * (radius - 6) end
    local col = ns.theme.route
    pin.dot:SetVertexColor(col[1], col[2], col[3], 1)
    pin.ring:SetVertexColor(col[1], col[2], col[3], 1)
    pin:SetSize(edge and 12 or 16, edge and 12 or 16)
    pin:SetAlpha(edge and 0.8 or 1)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
    pin.goal, pin.yards = goal, math.floor(math.sqrt(east * east + south * south))
    pin:Show()
end

function P:Hide()
    if pin then pin:Hide() end
    for i = 1, nDiscs do discs[i]:Hide() end
    for i = 1, nEdges do edges[i]:Hide() end
    nDiscs, nEdges = 0, 0
end
