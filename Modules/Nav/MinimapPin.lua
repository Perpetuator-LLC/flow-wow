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
    pin.dot = pin:CreateTexture(nil, "ARTWORK")
    pin.dot:SetAllPoints()
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

-- p: player position (Nav:PlayerPos), pt: the stop's point, goal: the stop.
function P:Update(p, pt, goal)
    if not Minimap then return end
    if not pin then build() end
    if ns.db.nav.minimapPin == false or not (p and pt and pt.wx and pt.cont == p.cont) then pin:Hide() return end
    local east, south = ns.nav:Offset(p, pt.wx, pt.wy)
    if not east then pin:Hide() return end
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
    local d = math.sqrt(x * x + y * y)
    local edge = d > radius - 6
    if edge then x, y = x / d * (radius - 6), y / d * (radius - 6) end
    local col = ns.theme.route
    pin.dot:SetVertexColor(col[1], col[2], col[3], 1)
    pin:SetSize(edge and 10 or 14, edge and 10 or 14)
    pin:SetAlpha(edge and 0.8 or 1)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
    pin.goal, pin.yards = goal, math.floor(math.sqrt(east * east + south * south))
    pin:Show()
end

function P:Hide() if pin then pin:Hide() end end
