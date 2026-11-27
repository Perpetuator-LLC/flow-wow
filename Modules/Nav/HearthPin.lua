-------------------------------------------------------------------------------
-- Flow - Nav/HearthPin.lua
-- Point at your hearthstone: the map shows where it takes you (0.35.410).
--
-- "When I hover my hearthstone it shows the target red dot on the map of
-- where that will take me, so if I have it open and am trying to navigate
-- with it, then it is clear where I'm going."
--
-- While the game's tooltip is on your Hearthstone (in your bags or on a bar)
-- and the world map is open, a red dot with a white ring sits on the inn it's
-- set to, with the inn's name beside it. It goes when the tooltip does. The
-- tooltip itself gets a line saying where that is, and, when the inn isn't on
-- the map you're looking at, that it's off this map.
--
-- Flow knows the spot for the inns in its list (Hearth.lua: H:BindPoint). It
-- only reads the map (which map is shown, its canvas): it never turns it.
-------------------------------------------------------------------------------

local _, ns = ...
local HP = {}
ns.hearthPin = HP

HP.ITEM = 6948
HP.SIZE = 16
HP.COLOR = { 1, 0.15, 0.15 }

-- Pure: is this link the Hearthstone? (By its number or its name: this
-- game's item numbers aren't always classic's.)
function HP.IsHearth(link)
    if type(link) ~= "string" then return false end
    local id = tonumber(link:match("item:(%d+)"))
    if id == HP.ITEM then return true end
    local name = link:match("%[(.-)%]")
    return name == "Hearthstone"
end

-- Pure: does the dot show? hovering: the tooltip is on your Hearthstone;
-- mapOpen: the world map is up; x, y: where the inn is on the map shown (nil: not on it).
function HP.Shows(hovering, mapOpen, x, y)
    return (hovering and mapOpen and x ~= nil and y ~= nil) and true or false
end

-- Pure: the tooltip's line. bind: where it's set; known: Flow knows the spot;
-- onMap: it's on the map shown (nil: the map isn't open).
function HP.TipLine(bind, known, onMap)
    local where = tostring(bind or "your inn")
    if not known then return "Flow: set to " .. where .. " (Flow doesn't know that inn's place on the map)" end
    if onMap == nil then return "Flow: takes you to " .. where .. ". Open the map to see where." end
    if onMap then return "Flow: takes you to " .. where .. ": the red dot on the map." end
    return "Flow: takes you to " .. where .. ", which isn't on the map you have open."
end

-- Where the inn is on the map being shown: x, y (0 to 1), or nil.
function HP.OnMap(point)
    if not (point and WorldMapFrame and WorldMapFrame.GetMapID and C_Map) then return nil end
    local okM, mapID = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
    if not (okM and mapID) then return nil end
    if point.map == mapID and point.x then return point.x, point.y end
    local N = ns.nav
    if not (N and N.ToWorld and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local okW, cont, wx, wy = pcall(N.ToWorld, N, point.map, point.x, point.y)
    if not (okW and cont and wx) then return nil end
    local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy), mapID)
    if not (ok and pos and pos.GetXY) then return nil end
    local x, y = pos:GetXY()
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
    return nil
end

local function canvas()
    if not WorldMapFrame then return nil end
    if WorldMapFrame.GetCanvas then return WorldMapFrame:GetCanvas() end
    return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end
local function canvasScale()
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    return (sc and sc.GetCanvasScale and sc:GetCanvasScale()) or 1
end

local pin
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function build(c)
    local p = CreateFrame("Frame", "FlowHearthPin", c)
    p:SetSize(HP.SIZE, HP.SIZE)
    p.ring = p:CreateTexture(nil, "BACKGROUND")
    p.ring:SetTexture(DISC)
    p.ring:SetPoint("TOPLEFT", -3, 3); p.ring:SetPoint("BOTTOMRIGHT", 3, -3)
    p.ring:SetVertexColor(1, 1, 1, 0.95)
    p.dot = p:CreateTexture(nil, "ARTWORK")
    p.dot:SetTexture(DISC)
    p.dot:SetAllPoints()
    p.dot:SetVertexColor(HP.COLOR[1], HP.COLOR[2], HP.COLOR[3], 1)
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.text:SetPoint("LEFT", p, "RIGHT", 5, 0)
    p.text:SetTextColor(1, 0.85, 0.85)
    p:EnableMouse(false)
    p:Hide()
    return p
end

-- Brings the dot in line with what the mouse is on. -> is it showing
function HP.Update()
    local open = WorldMapFrame and WorldMapFrame:IsShown() and true or false
    local point, bind, x, y
    if HP.hovering and open and ns.hearth and ns.hearth.BindPoint then
        local ok, p, b = pcall(ns.hearth.BindPoint, ns.hearth)
        if ok then point, bind = p, b end
        if point then x, y = HP.OnMap(point) end
    end
    if not HP.Shows(HP.hovering, open, x, y) then
        if pin then pin:Hide() end
        return false
    end
    local c = canvas()
    if not c then return false end
    pin = pin or build(c)
    pin:SetParent(c)
    pin:SetFrameStrata("HIGH")
    pin:SetFrameLevel(math.min(c:GetFrameLevel() + 1000, 9000) + 160)
    local sc = 1 / canvasScale()
    pin:SetScale(sc)
    pin.text:SetText("Hearthstone: " .. tostring(bind or "your inn"))
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", c, "TOPLEFT", x * c:GetWidth() / sc, -y * c:GetHeight() / sc)
    pin:Show()
    return true
end
HP._Pin = function() return pin end   -- (tests)

-- The tooltip is on an item: is it the Hearthstone?
ns:Register("itemTip", "hearthPin", function(tooltip, link)
    if tooltip ~= GameTooltip then return end
    local is = HP.IsHearth(link)
    HP.hovering = is
    if not is then
        if pin and pin:IsShown() then pin:Hide() end
        return
    end
    local H = ns.hearth
    local bind = GetBindLocation and GetBindLocation() or nil
    local okP, point = pcall(function() return H and H.BindPoint and H:BindPoint() end)
    point = okP and point or nil
    local open = WorldMapFrame and WorldMapFrame:IsShown() and true or false
    local onMap
    if open and point then onMap = HP.OnMap(point) ~= nil end
    tooltip:AddLine(HP.TipLine(bind, point ~= nil, onMap), 1, 0.6, 0.6, true)
    tooltip:Show()
    pcall(HP.Update)
end)

-- The tooltip goes: so does the dot.
if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnHide", function()
        if HP.hovering then HP.hovering = false; pcall(HP.Update) end
    end)
end
-- (The map opened or turned while you're still pointing at it.)
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(0.3, function() if HP.hovering or (pin and pin:IsShown()) then pcall(HP.Update) end end)
end
