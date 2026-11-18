-- Flight masters on the world map (0.35.314).
--
-- "Don't we have like a Flow Map button on the map or something that can
-- show flight paths?" There wasn't one. Now a Flow button sits by the map's
-- other two (above the route on/off button) and shows or hides them:
--   a green ring: a flight path you have, so you can fly there (Flow reads
--     them from every flight map you open, per character);
--   a light blue ring: a flight master whose path you don't have yet (free:
--     talk to them once). The same colour as the route's "Learn the flight
--     path" steps. From the NPCs Flow learned, other Flow players' shared
--     places and the quest data, on the continent you're on;
--   the route's colour, joined by a line: the flight that gets you to your
--     next step quicker than walking (the one the arrow's card suggests).
-- Hover one for its name and what it's for; click it to point Flow's arrow
-- there. Hidden until you click the button (the map is busy enough); the
-- button remembers. Setting: "Flight masters on the world map".
--
-- Flow's own frames on the map's canvas, like the route's pins. It never
-- changes the game's map or calls its functions, so the map's own buttons
-- can't be blocked by it.

local _, ns = ...
local MF = {}
ns.mapFlights = MF

MF.MAX = 80        -- flight masters looked at (the nearest)
MF.KEEP = 10       -- seconds the list of them is kept
MF.SIZE = 16       -- a pin, in screen pixels at any zoom
MF.ROLE_SIZE = 20  -- the two of your next step's flight
MF.SAME = 250      -- yards: a flight master this close to a flight path you have is its master
MF.ICON = "Interface\\GossipFrame\\TaxiGossipIcon"   -- (the route's flight step icon, theme.kinds.flight)
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

function MF.On() return ns.db and ns.db.nav and ns.db.nav.mapFlights == true end

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- Pure: the pins, drawn in this order (the ones of your next step's flight
-- last, on top).
--   known: your flight paths ({ [name] = { cont, wx, wy } }, ns.db.flights);
--   masters: flight masters Flow knows of ({ name, map, x, y, cont, wx, wy },
--     S:All); learned(fm) -> true when you have that one's path although no
--     flight path of yours stands by them (you talked to them: FP.Learned);
--   onRoute: [name] = true for those whose step is on your route;
--   air: your next step's flight ({ from, to }, N.AirRoute) or nil.
-- -> { { name, kind = "have" | "new", cont, wx, wy, map, x, y, npc, role =
--   "from" | "to" | nil, onRoute } }
function MF.Pins(known, masters, learned, onRoute, air, same)
    same = same or MF.SAME
    local out, used = {}, {}
    for name, f in pairs(known or {}) do
        if type(f) == "table" and f.wx and f.wy then
            local pin = { name = name, kind = "have", cont = f.cont, wx = f.wx, wy = f.wy }
            -- Its flight master, when Flow knows them: their name, and their
            -- zone's map for the arrow.
            local best, bd
            for i, fm in ipairs(masters or {}) do
                if fm.cont == f.cont and fm.wx then
                    local d = dist(fm.wx, fm.wy, f.wx, f.wy)
                    if d <= same and (not bd or d < bd) then best, bd = i, d end
                end
            end
            if best then
                local fm = masters[best]
                pin.npc, pin.map, pin.x, pin.y = fm.name, fm.map, fm.x, fm.y
            end
            if air and air.from == name then pin.role = "from" elseif air and air.to == name then pin.role = "to" end
            out[#out + 1] = pin
        end
    end
    -- A flight master who stands by a flight path you have is its master:
    -- not one to learn.
    for _, fm in ipairs(masters or {}) do
        if fm.name and fm.wx then
            for _, f in pairs(known or {}) do
                if type(f) == "table" and f.cont == fm.cont and f.wx and dist(fm.wx, fm.wy, f.wx, f.wy) <= same then
                    used[fm.name] = true
                end
            end
        end
    end
    local seen = {}
    for _, fm in ipairs(masters or {}) do
        local name = fm.name
        if name and fm.wx and not used[name] and not seen[name] and not (learned and learned(fm)) then
            seen[name] = true
            out[#out + 1] = { name = name, kind = "new", cont = fm.cont, wx = fm.wx, wy = fm.wy, map = fm.map, x = fm.x, y = fm.y,
                              npc = name, onRoute = (onRoute and onRoute[name]) and true or nil }
        end
    end
    local function rank(p) return (p.role and 3) or (p.kind == "have" and 2) or 1 end
    table.sort(out, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return a.name < b.name
    end)
    return out
end

-- Pure: a pin's tooltip. stepText: your next step; airText: how long it
-- takes by air, door to door ("4 min"; nil: not known). -> title, { lines }
function MF.TipLines(pin, stepText, airText)
    local lines = {}
    if pin.kind == "have" then
        if pin.npc then lines[#lines + 1] = "Flight master: " .. pin.npc end
        lines[#lines + 1] = "You have this flight path: you can fly here."
        if pin.role == "from" then
            lines[#lines + 1] = "Fly from here: your next step is quicker by air" .. (airText and (", " .. airText .. " in all") or "") .. "."
        elseif pin.role == "to" then
            lines[#lines + 1] = "Land here for your next step" .. (stepText and (": " .. stepText) or "") .. "."
        end
        return pin.name, lines
    end
    lines[#lines + 1] = "Flight master. You don't have this flight path yet: talk to them once (it's free), and later trips through here are shorter."
    if pin.onRoute then lines[#lines + 1] = "It's a step on your route (Flight paths to learn)." end
    return pin.name, lines
end

-- Pure: the label beside one of your next step's two pins (nil: none).
function MF.RoleLabel(role)
    if role == "from" then return "Fly from here" end
    if role == "to" then return "Land here: next step" end
    return nil
end

-------------------------------------------------------------------------------
-- What's drawn.
-------------------------------------------------------------------------------

local host          -- Flow's frame on the canvas, holding the flight's line
local pins, nPins = {}, 0
local flyLine
local last          -- what the last draw was of
MF.shown = { have = 0, new = 0 }
MF.draws = 0        -- (tests, /flow perf)

local cache = { at = -100, list = nil }
local function masters()
    local now = GetTime()
    if cache.list and now - cache.at < MF.KEEP then return cache.list end
    local S = ns.services
    if not (S and S.All) then return {} end
    pcall(S.Scan, S)   -- (started 20 s after login; at once when you open the map before that)
    local ok, list = pcall(S.All, S, "flight", MF.MAX)
    list = ok and list or {}
    -- Not the druids' own flyers in Moonglade: no path to learn (FlightPaths.lua).
    if ns.flightPaths and ns.flightPaths.NotRides then
        list = ns.flightPaths.NotRides(list, function(name) return ns:Get("ride", name) ~= nil end)
    end
    cache.at, cache.list = now, list
    return list
end
function MF._Forget() cache.list = nil; last = nil end   -- (tests)

-- Your next step's flight, as the arrow's card says it ("Quicker by air").
local function airNow()
    local N = ns.nav
    local cur = N and N.current
    if not (cur and cur.point and N.AirRoute) then return nil end
    local ok, air = pcall(N.AirRoute, N:PlayerPos(), cur.point, cur.d)
    return ok and air or nil
end

local function onRouteNow()
    local set, n = {}, 0
    for _, s in ipairs(ns.nav and ns.nav.plan or {}) do
        local key = s.goal and s.goal.key
        local name = type(key) == "string" and key:match("^flightpath:(.+)$")
        if name then set[name] = true; n = n + 1 end
    end
    return set, n
end

local function learnedFn()
    local FP = ns.flightPaths
    if not (FP and FP.Learned) then return nil end
    return function(fm) return FP.Learned(fm, ns.db.flightTalked, ns.db.flights) end
end

local function hideAll()
    for i = 1, nPins do pins[i]:Hide() end
    nPins = 0
    if flyLine then flyLine:Hide() end
end

-- Points Flow's arrow at a pin.
function MF.PointAt(pin, mapID, mx, my)
    if not (pin and ns.waypoint) then return false end
    local note = (pin.npc or pin.name) .. " (flight master)"
    if pin.map and pin.x then ns.waypoint:Set(pin.map, pin.x, pin.y, note) return true end
    if mapID and mx then ns.waypoint:Set(mapID, mx, my, note) return true end
    return false
end

local function makePin(c)
    local p = CreateFrame("Button", nil, c)
    p.edge = p:CreateTexture(nil, "BACKGROUND")
    p.edge:SetTexture(CIRCLE)
    p.edge:SetVertexColor(0, 0, 0, 0.9)
    p.ring = p:CreateTexture(nil, "BORDER", nil, 1)
    p.ring:SetTexture(CIRCLE)
    p.hole = p:CreateTexture(nil, "BORDER", nil, 2)
    p.hole:SetTexture(CIRCLE)
    p.hole:SetVertexColor(0.05, 0.05, 0.08, 1)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetTexture(MF.ICON)
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.text:SetPoint("LEFT", p, "RIGHT", 4, 0)
    p:SetScript("OnEnter", function(self)
        MF.hovering = true
        ns.Tip(self, "ANCHOR_RIGHT")
        local cur = ns.nav and ns.nav.current
        local step = cur and cur.goal and (cur.goal.text or cur.goal.title)
        local air = self.air
        local airText = air and air.sec and ns.nav.FormatSeconds and ns.nav.FormatSeconds(air.sec) or nil
        local title, lines = MF.TipLines(self.pin, step, airText)
        local col = self.col
        GameTooltip:AddLine(title, col[1], col[2], col[3])
        for _, l in ipairs(lines) do GameTooltip:AddLine(l, 1, 1, 1, true) end
        GameTooltip:AddLine("Click: point Flow's arrow here.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
        self.edge:SetVertexColor(1, 1, 1, 1)
    end)
    p:SetScript("OnLeave", function(self)
        MF.hovering = false
        GameTooltip:Hide()
        self.edge:SetVertexColor(0, 0, 0, 0.9)
    end)
    p:SetScript("OnClick", function(self) MF.PointAt(self.pin, self.mapID, self.mx, self.my) end)
    return p
end

local function placePin(c, pin, x, y, mapID, base, air)
    nPins = nPins + 1
    local p = pins[nPins]
    if not p then p = makePin(c); pins[nPins] = p end
    local T = ns.theme
    local col = (pin.role and T.route) or (pin.kind == "have" and T.flightHave) or (T.kinds.flight and T.kinds.flight.color) or T.muted
    p.pin, p.col, p.mapID, p.mx, p.my, p.air = pin, col, mapID, x, y, air
    p:SetParent(c)
    p:SetFrameStrata(ns.mapOverlay.AboveMap())
    p:SetFrameLevel(base + (pin.role and 60 or 50))
    local size = pin.role and MF.ROLE_SIZE or MF.SIZE
    p:SetSize(size, size)
    p:SetScale(1 / ns.mapOverlay.CanvasScale())
    local s = p:GetScale()
    p:ClearAllPoints()
    p:SetPoint("CENTER", c, "TOPLEFT", x * c:GetWidth() / s, -y * c:GetHeight() / s)
    p.edge:ClearAllPoints(); p.edge:SetPoint("TOPLEFT", -2, 2); p.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    p.ring:SetAllPoints()
    p.ring:SetVertexColor(col[1], col[2], col[3], 1)
    p.hole:ClearAllPoints(); p.hole:SetPoint("TOPLEFT", 2, -2); p.hole:SetPoint("BOTTOMRIGHT", -2, 2)
    p.icon:ClearAllPoints(); p.icon:SetPoint("TOPLEFT", 3, -3); p.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    -- One you don't have yet: its picture a little faded, so the ones you
    -- can fly to stand out.
    p.icon:SetAlpha(pin.kind == "have" and 1 or 0.7)
    local label = MF.RoleLabel(pin.role)
    p.text:SetText(label or "")
    p.text:SetShown(label ~= nil)
    p:Show()
    return p
end

-- Draws them all on the map shown. Returns how many of each it drew.
function MF.Draw()
    local M = ns.mapOverlay
    local c = M and M.Canvas and M.Canvas()
    if not (c and WorldMapFrame and WorldMapFrame:IsShown() and MF.On()) then hideAll() return nil end
    local mapID = WorldMapFrame:GetMapID()
    local base = math.min(c:GetFrameLevel() + 1000, 9000)
    if not host then
        host = CreateFrame("Frame", nil, c)
        host:SetAllPoints(c)
        host:EnableMouse(false)
        flyLine = host:CreateLine(nil, "OVERLAY")
    end
    host:SetFrameStrata(M.AboveMap())
    host:SetFrameLevel(base + 40)
    local old = nPins
    nPins = 0
    local air = airNow()
    local onRoute = onRouteNow()
    local list = MF.Pins(ns.db.flights, masters(), learnedFn(), onRoute, air)
    local shown, at = { have = 0, new = 0 }, {}
    for _, pin in ipairs(list) do
        local x, y = M.ToMap(pin, mapID)
        if x then
            placePin(c, pin, x, y, mapID, base, air)
            shown[pin.kind] = shown[pin.kind] + 1
            if pin.role then at[pin.role] = { x, y } end
        end
    end
    for i = nPins + 1, old do pins[i]:Hide() end
    -- Your next step's flight: a line from where you'd take off to where you'd land.
    if at.from and at.to then
        local col, w, h = ns.theme.route, c:GetWidth(), c:GetHeight()
        flyLine:SetThickness(2 / M.CanvasScale())
        flyLine:SetColorTexture(col[1], col[2], col[3], 0.75)
        flyLine:SetStartPoint("TOPLEFT", c, at.from[1] * w, -at.from[2] * h)
        flyLine:SetEndPoint("TOPLEFT", c, at.to[1] * w, -at.to[2] * h)
        flyLine:Show()
    else
        flyLine:Hide()
    end
    MF.shown, MF.draws = shown, MF.draws + 1
    local note = string.format("world map %s: %d flight paths you have, %d to learn%s", tostring(mapID), shown.have, shown.new,
        air and string.format("; your next step by air, %s to %s", air.from, air.to) or "")
    if note ~= MF.lastNote then
        MF.lastNote = note
        ns:Log("flight", note)
    end
    return shown
end

-- What the last draw was of: drawn again only when it changed (a new map,
-- a zoom, a flight path learned, your next step's flight, the list of
-- flight masters every MF.KEEP seconds) and not while you point at a pin
-- (it would move under the mouse).
local function stateNow()
    local M = ns.mapOverlay
    local c = M.Canvas()
    local air = airNow()
    local _, nRoute = onRouteNow()
    return table.concat({ tostring(WorldMapFrame:GetMapID()), string.format("%.3f", M.CanvasScale()),
        math.floor(c:GetWidth()), math.floor(c:GetHeight()), tostring(ns.nav and ns.nav.flightGen or 0),
        tostring(masters()), air and air.from or "-", air and air.to or "-", nRoute }, "|")
end

-------------------------------------------------------------------------------
-- The button, above the route on/off button (MapOverlay.lua).
-------------------------------------------------------------------------------

local button
local function anchor(b)
    local M = ns.mapOverlay
    local d = M and M.DrawerButton and M.DrawerButton()
    local r = d and d.routeToggle
    b:ClearAllPoints()
    if r then
        b:SetSize(r:GetWidth(), r:GetHeight())
        b:SetPoint("BOTTOM", r, "TOP", 0, 4)
        b:SetFrameLevel(r:GetFrameLevel())
        return true
    end
    -- (Flow's route is off on the map, so its two buttons aren't made: where they'd be.)
    local blizz = WorldMapFrame.SidePanelToggle
    local h = b:GetHeight()
    if blizz then b:SetPoint("BOTTOM", blizz, "TOP", 0, 4 + 2 * (h + 4))
    else b:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -6, 46 + 2 * (h + 4)) end
    return false
end

function MF.Button()
    if button then return button end
    if not WorldMapFrame then return nil end
    local b = CreateFrame("Button", "FlowMapFlightsToggle", WorldMapFrame)
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
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture(MF.ICON)
    function b:Draw()
        local on, c, hot = MF.On(), ns.theme.route, self:IsMouseOver()
        self.bg:SetColorTexture(on and c[1] * 0.25 or 0.05, on and c[2] * 0.25 or 0.05, on and c[3] * 0.25 or 0.08, 0.92)
        for _, t in ipairs(self.edge) do t:SetColorTexture(c[1], c[2], c[3], hot and 1 or 0.75) end
        local s = math.min(self:GetWidth(), self:GetHeight()) * 0.62
        self.icon:SetSize(s, s)
        if self.icon.SetDesaturated then self.icon:SetDesaturated(not on) end
        self.icon:SetAlpha(on and 1 or (hot and 0.8 or 0.55))
    end
    b:SetScript("OnClick", function(self)
        MF.Set(not MF.On())
        self:Draw()
        if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end)
    b:SetScript("OnEnter", function(self)
        self:Draw()
        ns.Tip(self, "ANCHOR_LEFT")
        local on = MF.On()
        GameTooltip:AddLine("Flow flight masters on the map: " .. (on and "shown" or "hidden"))
        GameTooltip:AddLine("Green: flight paths you have. Light blue: ones you don't have yet (free: talk to them once). "
            .. "Joined by a line in the route's colour: the flight your next step is quicker by.", 1, 1, 1, true)
        if on then
            GameTooltip:AddLine(string.format("On this map: %d you have, %d to learn.", MF.shown.have, MF.shown.new), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("Click to " .. (on and "hide" or "show") .. " them.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self:Draw(); GameTooltip:Hide() end)
    b.anchored = anchor(b)
    b:Draw()
    button = b
    return b
end

-- The map's tick: the button by the others, and the pins kept up.
function MF.Tick()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local b = MF.Button()
    if b and not b.anchored then b.anchored = anchor(b); b:Draw() end
    if not MF.On() then
        if nPins > 0 or (flyLine and flyLine:IsShown()) then hideAll(); last = nil end
        return
    end
    if MF.hovering then return end
    local okS, now = pcall(stateNow)
    if okS and now == last then return end
    last = okS and now or nil
    MF.Draw()
end
MF.Tick = ns.perf.Wrap("world map (flight masters)", MF.Tick)

function MF.Set(on)
    ns.db.nav.mapFlights = on and true or false
    last = nil
    if button then button:Draw() end
    pcall(MF.Tick)
    if not on then hideAll() end
end

ns:OnLoad(function()
    local acc = 0
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < ((ns.Lite and ns.Lite()) and 2 or 0.5) then return end   -- lite: every 2 s
        acc = 0
        if WorldMapFrame and WorldMapFrame:IsShown() then pcall(MF.Tick) end
    end)
end)

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck{ group = "route", label = "Flight masters on the world map",
        tip = "The same as the Flow button on the world map, above the route button: green rings for the flight paths you have, "
            .. "light blue for the ones you don't have yet, and the flight your next step is quicker by, joined by a line.",
        get = MF.On, set = MF.Set }
end
