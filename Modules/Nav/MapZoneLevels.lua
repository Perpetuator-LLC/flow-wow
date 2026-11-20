-- Zone level ranges on the continent world map.
--
-- "I had previous mods that showed me the level of each zone on the map."
-- On Kalimdor or the Eastern Kingdoms map, each levelling zone shows its
-- range ("10-20") at its centre, coloured against your level:
--   red: well above you; orange: a little above you; yellow: your level;
--   green: just below you (easy); grey: outgrown.
-- A Flow button above the flight-masters button shows or hides them; it
-- remembers. Setting: "Zone levels on the world map". On by default.
--
-- Ranges: warcraft.wiki.gg "Zones by level (Classic)". Zones are matched by
-- their English name (the map's own list of zones on that continent), so a
-- zone Flow has no range for just shows nothing.
--
-- Flow's own frames on the map's canvas, like the route's pins. It never
-- changes the game's map or calls its functions; the labels don't take the
-- mouse, so the map's own zone hover still works.

local _, ns = ...
local ZL = {}
ns.mapZoneLevels = ZL

ZL.FONT_SIZE = 14   -- screen pixels at any zoom

-- { min, max } by zone name.
ZL.RANGES = {
    -- Eastern Kingdoms
    ["Dun Morogh"] = { 1, 10 }, ["Elwynn Forest"] = { 1, 10 }, ["Tirisfal Glades"] = { 1, 10 },
    ["Westfall"] = { 10, 20 }, ["Loch Modan"] = { 10, 20 }, ["Silverpine Forest"] = { 10, 20 },
    ["Redridge Mountains"] = { 15, 25 }, ["Duskwood"] = { 18, 30 }, ["Wetlands"] = { 20, 30 },
    ["Hillsbrad Foothills"] = { 20, 35 }, ["Alterac Mountains"] = { 30, 40 }, ["Arathi Highlands"] = { 30, 40 },
    ["Stranglethorn Vale"] = { 30, 45 }, ["Badlands"] = { 35, 45 }, ["Swamp of Sorrows"] = { 35, 45 },
    ["The Hinterlands"] = { 40, 50 }, ["Searing Gorge"] = { 45, 50 }, ["Blasted Lands"] = { 45, 55 },
    ["Burning Steppes"] = { 50, 58 }, ["Western Plaguelands"] = { 51, 58 }, ["Eastern Plaguelands"] = { 53, 60 },
    ["Deadwind Pass"] = { 55, 60 },
    -- Kalimdor
    ["Teldrassil"] = { 1, 10 }, ["Durotar"] = { 1, 10 }, ["Mulgore"] = { 1, 10 },
    ["Darkshore"] = { 10, 20 }, ["The Barrens"] = { 10, 25 }, ["Stonetalon Mountains"] = { 15, 27 },
    ["Ashenvale"] = { 18, 30 }, ["Thousand Needles"] = { 25, 35 }, ["Desolace"] = { 30, 40 },
    ["Dustwallow Marsh"] = { 35, 45 }, ["Feralas"] = { 40, 50 }, ["Tanaris"] = { 40, 50 },
    ["Azshara"] = { 45, 55 }, ["Un'Goro Crater"] = { 48, 55 }, ["Felwood"] = { 48, 55 },
    ["Winterspring"] = { 53, 60 }, ["Moonglade"] = { 55, 60 }, ["Silithus"] = { 55, 60 },
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

function ZL.Text(range) return range[1] .. "-" .. range[2] end

-- The labels for the map `mapID`: { { name, text, x, y, r, g, b } } at each
-- zone's centre (0-1 on that map), or nil when it isn't a continent.
-- children / rectOf can be passed in (tests); otherwise read from C_Map.
function ZL.Labels(mapID, level, children, rectOf)
    if not children then
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        local cont = Enum and Enum.UIMapType and Enum.UIMapType.Continent
        if not (info and cont and info.mapType == cont and C_Map.GetMapChildrenInfo) then return nil end
        children = C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone) or {}
    end
    rectOf = rectOf or function(child)
        if not C_Map.GetMapRectOnMap then return nil end
        return C_Map.GetMapRectOnMap(child, mapID)
    end
    local out = {}
    for _, child in ipairs(children) do
        local range = child.name and ZL.RANGES[child.name]
        if range then
            local minX, maxX, minY, maxY = rectOf(child.mapID)
            if minX and maxX > minX and maxY > minY then
                local r, g, b = ZL.Color(range[1], range[2], level)
                out[#out + 1] = { name = child.name, text = ZL.Text(range),
                                  x = (minX + maxX) / 2, y = (minY + maxY) / 2, r = r, g = g, b = b }
            end
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- Drawing.
-------------------------------------------------------------------------------

local host
local labels, nLabels = {}, 0
ZL.shown = 0

local function hideAll()
    for i = 1, nLabels do labels[i]:Hide() end
    nLabels = 0
    ZL.shown = 0
end

local function label(i)
    local fs = labels[i]
    if not fs then
        fs = host:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, ZL.FONT_SIZE, "OUTLINE")
        fs:SetShadowOffset(1, -1)
        labels[i] = fs
    end
    return fs
end

function ZL.Draw()
    local M = ns.mapOverlay
    local c = M and M.Canvas and M.Canvas()
    if not (c and WorldMapFrame and WorldMapFrame:IsShown() and ZL.On()) then hideAll() return nil end
    local list = ZL.Labels(WorldMapFrame:GetMapID(), UnitLevel("player") or 1)
    if not list then hideAll() return 0 end
    if not host then
        host = CreateFrame("Frame", nil, c)
        host:SetAllPoints(c)
        host:EnableMouse(false)
    end
    host:SetFrameStrata(M.AboveMap())
    host:SetFrameLevel(math.min(c:GetFrameLevel() + 1000, 9000) + 20)   -- under the route's pins and flight masters
    host:Show()
    -- One size on screen at any zoom: the host is scaled against the canvas.
    local s = 1 / M.CanvasScale()
    host:SetScale(s)
    local w, h = c:GetWidth() / s, c:GetHeight() / s
    for i, l in ipairs(list) do
        local fs = label(i)
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", host, "TOPLEFT", l.x * w, -l.y * h)
        fs:SetText(l.text)
        fs:SetTextColor(l.r, l.g, l.b)
        fs:Show()
    end
    for i = #list + 1, nLabels do labels[i]:Hide() end
    nLabels = #list
    ZL.shown = #list
    return #list
end

local last
local function stateNow()
    local M = ns.mapOverlay
    local c = M.Canvas()
    return table.concat({ tostring(WorldMapFrame:GetMapID()), string.format("%.3f", M.CanvasScale()),
        math.floor(c:GetWidth()), math.floor(c:GetHeight()), tostring(UnitLevel("player")) }, "|")
end

-------------------------------------------------------------------------------
-- The button, above the flight-masters button (MapFlights.lua).
-------------------------------------------------------------------------------

local button
local function anchor(b)
    local above = ns.mapFlights and ns.mapFlights.Button and ns.mapFlights.Button()
    b:ClearAllPoints()
    if not above then return false end
    b:SetSize(above:GetWidth(), above:GetHeight())
    b:SetPoint("BOTTOM", above, "TOP", 0, 4)
    b:SetFrameLevel(above:GetFrameLevel())
    return above.anchored and true or false
end

function ZL.Button()
    if button then return button end
    if not WorldMapFrame then return nil end
    local b = CreateFrame("Button", "FlowMapZoneLevelsToggle", WorldMapFrame)
    b:SetSize(32, 32)
    b:SetFrameStrata("HIGH")
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
    b.edge = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                           { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = b:CreateTexture(nil, "BORDER")
        t:SetPoint(pts[1]); t:SetPoint(pts[2])
        if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
        b.edge[i] = t
    end
    b.text = b:CreateFontString(nil, "ARTWORK")
    b.text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    b.text:SetPoint("CENTER")
    b.text:SetText("Lv")
    function b:Draw()
        local on, col, hot = ZL.On(), ns.theme.route, self:IsMouseOver()
        self.bg:SetColorTexture(on and col[1] * 0.25 or 0.05, on and col[2] * 0.25 or 0.05, on and col[3] * 0.25 or 0.08, 0.92)
        for _, t in ipairs(self.edge) do t:SetColorTexture(col[1], col[2], col[3], hot and 1 or 0.75) end
        if on then self.text:SetTextColor(1, 0.82, 0) else self.text:SetTextColor(0.6, 0.6, 0.6) end
        self.text:SetAlpha(on and 1 or (hot and 0.8 or 0.55))
    end
    b:SetScript("OnClick", function(self)
        ZL.Set(not ZL.On())
        self:Draw()
        if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end)
    b:SetScript("OnEnter", function(self)
        self:Draw()
        ns.Tip(self, "ANCHOR_LEFT")
        local on = ZL.On()
        GameTooltip:AddLine("Flow zone levels on the map: " .. (on and "shown" or "hidden"))
        GameTooltip:AddLine("On the continent map, each zone's level range, coloured against your level: "
            .. "red well above you, orange a little above, yellow your level, green easy, grey outgrown.", 1, 1, 1, true)
        if on then GameTooltip:AddLine(string.format("On this map: %d zones.", ZL.shown), 0.8, 0.8, 0.8) end
        GameTooltip:AddLine("Click to " .. (on and "hide" or "show") .. " them.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self:Draw(); GameTooltip:Hide() end)
    b.anchored = anchor(b)
    b:Draw()
    button = b
    return b
end

function ZL.Tick()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local b = ZL.Button()
    if b and not b.anchored then b.anchored = anchor(b); b:Draw() end
    if not ZL.On() then
        if nLabels > 0 then hideAll(); last = nil end
        return
    end
    local okS, now = pcall(stateNow)
    if okS and now == last then return end
    last = okS and now or nil
    ZL.Draw()
end
ZL.Tick = ns.perf.Wrap("world map (zone levels)", ZL.Tick)

function ZL.Set(on)
    ns.db.nav.mapZoneLevels = on and true or false
    last = nil
    if button then button:Draw() end
    if not on then hideAll() end
    pcall(ZL.Tick)
end

ns:OnLoad(function()
    local acc = 0
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < ((ns.Lite and ns.Lite()) and 2 or 0.5) then return end
        acc = 0
        if WorldMapFrame and WorldMapFrame:IsShown() then pcall(ZL.Tick) end
    end)
end)

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck{ group = "route", label = "Zone levels on the world map",
        tip = "The same as the Lv button on the world map, above the flight-masters button: each zone's level range "
            .. "on the continent map, coloured against your level.",
        get = ZL.On, set = ZL.Set }
end
