-- Zone info when you hover a zone on the continent world map.
--
-- "I would just like to highlight the zone and see the name of the zone,
-- the level range, and the fishing level range."
-- On Kalimdor or the Eastern Kingdoms map, the zone under the cursor gets a
-- small card beside the cursor:
--   Westfall
--   Level 10-20        (coloured against your level)
--   Fishing 1
-- Nothing is drawn until you hover; the game's own zone highlight shows
-- which zone it is. Setting: "Zone info when hovering the world map". On by
-- default.
--
-- Level ranges: warcraft.wiki.gg "Zones by level (Classic)". Fishing: the
-- skill to fish the zone's waters without the catch getting away, as the
-- Classic fishing tables give it; "130 (205)" means most waters need 130 and
-- some need 205. Keyed by the map's own zone ID (locale-proof).
--
-- Flow's own frames only. It reads the cursor and C_Map; it never changes
-- the game's map, its labels or its highlight, and its card takes no mouse.

local _, ns = ...
local ZL = {}
ns.mapZoneLevels = ZL

ZL.FONT_SIZE = 14

-- [uiMapID] = { name, min, max, fish, fishTop }. A city has no range; a zone
-- with no water no fishing.
ZL.ZONES = {
    -- Eastern Kingdoms
    [1426] = { "Dun Morogh", 1, 10, 1 },           [1429] = { "Elwynn Forest", 1, 10, 1 },
    [1420] = { "Tirisfal Glades", 1, 10, 1 },       [1436] = { "Westfall", 10, 20, 1 },
    [1432] = { "Loch Modan", 10, 20, 1 },           [1421] = { "Silverpine Forest", 10, 20, 1 },
    [1433] = { "Redridge Mountains", 15, 25, 55 },  [1431] = { "Duskwood", 18, 30, 55 },
    [1437] = { "Wetlands", 20, 30, 55 },            [1424] = { "Hillsbrad Foothills", 20, 35, 55 },
    [1416] = { "Alterac Mountains", 30, 40, 130 },  [1417] = { "Arathi Highlands", 30, 40, 130 },
    [1434] = { "Stranglethorn Vale", 30, 45, 130, 205 },
    [1418] = { "Badlands", 35, 45 },                [1435] = { "Swamp of Sorrows", 35, 45, 130 },
    [1425] = { "The Hinterlands", 40, 50, 205 },    [1427] = { "Searing Gorge", 45, 50 },
    [1419] = { "Blasted Lands", 45, 55 },           [1428] = { "Burning Steppes", 50, 58, 330 },
    [1422] = { "Western Plaguelands", 51, 58, 205 },
    [1423] = { "Eastern Plaguelands", 53, 60, 330 },
    [1430] = { "Deadwind Pass", 55, 60, 330 },
    [1453] = { "Stormwind City", nil, nil, 1 },     [1455] = { "Ironforge", nil, nil, 1 },
    [1458] = { "Undercity", nil, nil, 1 },
    -- Kalimdor
    [1438] = { "Teldrassil", 1, 10, 1 },            [1411] = { "Durotar", 1, 10, 1 },
    [1412] = { "Mulgore", 1, 10, 1 },               [1439] = { "Darkshore", 10, 20, 1 },
    [1413] = { "The Barrens", 10, 25, 1 },          [1442] = { "Stonetalon Mountains", 15, 27, 55 },
    [1440] = { "Ashenvale", 18, 30, 55 },           [1441] = { "Thousand Needles", 25, 35, 130 },
    [1443] = { "Desolace", 30, 40, 130 },           [1445] = { "Dustwallow Marsh", 35, 45, 130 },
    [1444] = { "Feralas", 40, 50, 205, 330 },       [1446] = { "Tanaris", 40, 50, 205 },
    [1447] = { "Azshara", 45, 55, 205, 330 },       [1449] = { "Un'Goro Crater", 48, 55, 205 },
    [1448] = { "Felwood", 48, 55, 205 },            [1452] = { "Winterspring", 53, 60, 330 },
    [1450] = { "Moonglade", 55, 60, 205 },          [1451] = { "Silithus", 55, 60, 330 },
    [1454] = { "Orgrimmar", nil, nil, 1 },          [1456] = { "Thunder Bluff", nil, nil, 1 },
    [1457] = { "Darnassus", nil, nil, 1 },
}

function ZL.On() return not (ns.db and ns.db.nav and ns.db.nav.mapZoneLevels == false) end

-- The colour of a zone's range for someone of `level`.
function ZL.Color(min, max, level)
    if level < min - 3 then return 1, 0.1, 0.1, "red" end
    if level < min then return 1, 0.5, 0.25, "orange" end
    if level <= max then return 1, 0.82, 0, "yellow" end
    if level <= max + 5 then return 0.25, 0.75, 0.25, "green" end
    return 0.62, 0.62, 0.62, "grey"
end

-- The card for the zone `zoneID` (named `name` by the map) for someone of
-- `level`: { name, level = "Level 10-20" or nil, r, g, b, fish = "Fishing
-- 130 (205)" or nil }, or nil when Flow knows nothing about it.
function ZL.Card(zoneID, name, level)
    local z = ZL.ZONES[zoneID]
    if not z then return nil end
    local card = { name = name or z[1] }
    if z[2] then
        card.level = z[2] == z[3] and ("Level " .. z[2]) or string.format("Level %d-%d", z[2], z[3])
        card.r, card.g, card.b = ZL.Color(z[2], z[3], level)
    end
    if z[4] then
        card.fish = "Fishing " .. z[4] .. (z[5] and string.format(" (%d)", z[5]) or "")
    end
    return card
end

-------------------------------------------------------------------------------
-- The card.
-------------------------------------------------------------------------------

local card
local function makeCard()
    local f = CreateFrame("Frame", nil, WorldMapFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetFrameStrata("TOOLTIP")
    f:EnableMouse(false)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 14,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
        f:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)
    end
    f.name = f:CreateFontString(nil, "ARTWORK")
    f.name:SetPoint("TOPLEFT", 10, -9)
    f.level = f:CreateFontString(nil, "ARTWORK")
    f.level:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
    f.fish = f:CreateFontString(nil, "ARTWORK")
    f.fish:SetTextColor(0.35, 0.8, 1)   -- water blue
    for _, fs in ipairs({ f.name, f.level, f.fish }) do
        fs:SetFont(STANDARD_TEXT_FONT, ZL.FONT_SIZE, "OUTLINE")
        fs:SetShadowOffset(1, -1)
        fs:SetJustifyH("LEFT")
    end
    f.name:SetTextColor(1, 1, 1)
    f:Hide()
    return f
end

local shownFor
local function hideCard()
    if card then card:Hide() end
    shownFor = nil
end

local function showCard(c, zoneID)
    card = card or makeCard()
    if shownFor ~= zoneID then
        card.name:SetText(c.name)
        local below = card.name
        card.level:SetShown(c.level ~= nil)
        if c.level then
            card.level:SetText(c.level)
            card.level:SetTextColor(c.r, c.g, c.b)
            below = card.level
        end
        card.fish:ClearAllPoints()
        card.fish:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -3)
        card.fish:SetShown(c.fish ~= nil)
        if c.fish then card.fish:SetText(c.fish) end
        local w = math.max(card.name:GetStringWidth(), c.level and card.level:GetStringWidth() or 0,
                           c.fish and card.fish:GetStringWidth() or 0)
        local h = 9 + card.name:GetStringHeight()
            + (c.level and 4 + card.level:GetStringHeight() or 0)
            + (c.fish and 3 + card.fish:GetStringHeight() or 0) + 9
        card:SetSize(math.ceil(w) + 20, math.ceil(h))
        shownFor = zoneID
    end
    -- Down and to the right of the cursor, like the waypoint tip.
    local cx, cy = GetCursorPosition()
    local s = card:GetEffectiveScale()
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / s + 18, cy / s - 22)
    card:Show()
end

-- The continent zone under the cursor, or nil.
local function zoneUnderCursor()
    local sc = WorldMapFrame.ScrollContainer
    if not (sc and sc.GetNormalizedCursorPosition and sc:IsMouseOver()) then return nil end
    local mapID = WorldMapFrame:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    if not (info and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent) then return nil end
    local x, y = sc:GetNormalizedCursorPosition()
    if not (x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return nil end
    local at = C_Map.GetMapInfoAtPosition(mapID, x, y)
    if not at or at.mapID == mapID then return nil end
    return at.mapID, at.name
end

function ZL.Tick()
    if not (ZL.On() and WorldMapFrame and WorldMapFrame:IsShown()) then hideCard() return end
    -- A pin's own tooltip wins: no card on top of it.
    if GameTooltip:IsShown() then hideCard() return end
    local zoneID, name = zoneUnderCursor()
    local c = zoneID and ZL.Card(zoneID, name, UnitLevel("player") or 1)
    if c then showCard(c, zoneID) else hideCard() end
end
ZL.Tick = ns.perf.Wrap("world map (zone info)", ZL.Tick)

function ZL.Set(on)
    ns.db.nav.mapZoneLevels = on and true or false
    if not on then hideCard() end
end

ns:OnLoad(function()
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function()
        if WorldMapFrame and WorldMapFrame:IsShown() then pcall(ZL.Tick)
        elseif shownFor then hideCard() end
    end)
end)

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck{ group = "route", label = "Zone info when hovering the world map",
        tip = "On the continent map, the zone under the cursor shows its name, level range (coloured against "
            .. "your level) and the fishing skill its waters need.",
        get = ZL.On, set = ZL.Set }
end
