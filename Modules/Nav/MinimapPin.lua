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
-- Areas on the minimap: the same areas as the world map, as soft clouds
-- for the stop the arrow points at, and, while you hover a row in
-- the Flow Tracker, for that stop in the hover colour. So you can tell at a
-- glance whether you're standing in this stop's area, the next one's, or both.
-------------------------------------------------------------------------------

-- Drawn as one cloud like the game's own quest areas, not a pile of circles:
-- the outline of all the spawn circles together, filled row by row with thin
-- strips that never overlap (overlapping see-through circles pile up colour,
-- which is what made each circle show). A smaller core on top gives the
-- soft edge. Clipped to the round minimap.
local AREA_YARDS = 45
local ROW = 2                -- pixels per strip
local CORE = 0.62            -- core radius, as a share of the area's
local discs, nDiscs = {}, 0  -- (the strips)
local hoverGoal
local areaHost

local function strip(x1, x2, y, color, alpha)
    nDiscs = nDiscs + 1
    local t = discs[nDiscs]
    if not t then
        t = areaHost:CreateTexture(nil, "BACKGROUND")
        discs[nDiscs] = t
    end
    t:SetColorTexture(color[1], color[2], color[3], alpha)
    t:ClearAllPoints()
    t:SetSize(math.max(1, x2 - x1), ROW)
    t:SetPoint("CENTER", Minimap, "CENTER", (x1 + x2) / 2, y)
    t:Show()
end

-- Where row `y` crosses the union of circles (centres pts, radius r), as
-- merged { x1, x2 } spans clipped to the round minimap of `radius`.
function P.Spans(pts, r, y, radius)
    local iv = {}
    for _, q in ipairs(pts) do
        local dy = y - q[2]
        if dy > -r and dy < r then
            local dx = math.sqrt(r * r - dy * dy)
            iv[#iv + 1] = { q[1] - dx, q[1] + dx }
        end
    end
    if #iv == 0 then return iv end
    table.sort(iv, function(a, b) return a[1] < b[1] end)
    local merged = { { iv[1][1], iv[1][2] } }
    for i = 2, #iv do
        local last = merged[#merged]
        if iv[i][1] <= last[2] then last[2] = math.max(last[2], iv[i][2])
        else merged[#merged + 1] = { iv[i][1], iv[i][2] } end
    end
    local m = radius * radius - y * y
    if m <= 0 then return {} end
    m = math.sqrt(m)
    local out = {}
    for _, s in ipairs(merged) do
        local a, b = math.max(s[1], -m), math.min(s[2], m)
        if b > a then out[#out + 1] = { a, b } end
    end
    return out
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
                if math.sqrt(x * x + y * y) < radius + r then pts[#pts + 1] = { x, y } end
            end
        end
    end
    if #pts == 0 then return end
    local top, bottom = -radius, radius
    local lo, hi = math.huge, -math.huge
    for _, q in ipairs(pts) do lo = math.min(lo, q[2] - r); hi = math.max(hi, q[2] + r) end
    lo, hi = math.max(lo, top), math.min(hi, bottom)
    local edgeA, coreA = strong and 0.17 or 0.1, strong and 0.17 or 0.1
    local y = lo + ROW / 2
    while y < hi and nDiscs < 900 do
        for _, s in ipairs(P.Spans(pts, r, y, radius)) do strip(s[1], s[2], y, color, edgeA) end
        for _, s in ipairs(P.Spans(pts, r * CORE, y, radius)) do strip(s[1], s[2], y, color, coreA) end
        y = y + ROW
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
    local oldD = nDiscs
    nDiscs = 0
    if ns.db.nav.minimapPin ~= false and ns.db.nav.minimapAreas ~= false and p then
        if hoverGoal and hoverGoal ~= goal then drawAreaMini(p, hoverGoal, ns.theme.hover, true) end
        drawAreaMini(p, goal, ns.theme.route, hoverGoal == nil or hoverGoal == goal)
    end
    for i = nDiscs + 1, oldD do discs[i]:Hide() end

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
    nDiscs = 0
end
