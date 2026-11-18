-- Your next step's flight master, marked on the flight map (0.35.312).
--
-- "When I go to fly somewhere, it would be really nice if the target
-- destination flight path that is recommended for my next flow item was
-- somehow illuminated, circled, something like that."
--
-- When a flight map opens, Flow picks the flight master you can fly to that
-- lands you nearest your next step (the one the arrow points at) and rings it
-- with dots in the route's colour, turning slowly, with the step's name under
-- it. Not when the step is about as quick to walk to from the flight master
-- you're standing at. The ring is Flow's own frame laid over the map: Flow
-- only reads the game's flight map, never changes it or its buttons, and the
-- ring takes no clicks (the flight master under it is clicked as always).
--
-- Setting: "Ring your next step's flight master on the flight map" (Finding
-- your way).

local _, ns = ...
local TM = {}
ns.taxiMark = TM

TM.DOTS, TM.DOT = 12, 4
TM.SPIN = 0.5          -- radians a second: a slow turn
TM.LABEL_MAX = 34      -- characters of the step's name under the ring

function TM.On() return not (ns.db and ns.db.nav and ns.db.nav.taxiMark == false) end

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- Pure: the flight master to ring. nodes: the ones on the open map you can
-- fly to, in world yards ({ name, cont, wx, wy }); here: the one you're at;
-- pt: your next step's spot ({ cont, wx, wy }); flightSec(from, to) ->
-- seconds or nil; speed: yards a second on foot; saves: the share of the
-- walk a flight must beat (N.AIR_SAVES).
-- -> its name and how far it lands from the step, or nil.
function TM.Pick(nodes, here, pt, flightSec, speed, saves)
    if not (pt and pt.wx and pt.cont ~= nil) then return nil end
    local best, bd, hereD
    for _, n in ipairs(nodes or {}) do
        if n.cont == pt.cont and n.wx then
            local d = dist(n.wx, n.wy, pt.wx, pt.wy)
            if n.name == here then hereD = d
            elseif not bd or d < bd then best, bd = n.name, d end
        end
    end
    if not best then return nil end
    if hereD then
        if hereD <= bd then return nil end   -- the step is nearer where you stand
        local fly = flightSec and flightSec(here, best)
        speed = speed or 7
        if fly and fly + bd / speed >= (hereD / speed) * (saves or 0.8) then return nil end   -- walking is about as quick
    end
    return best, bd
end

-- Pure: the words under the ring.
function TM.Label(text)
    text = tostring(text or "your next step")
    if #text > TM.LABEL_MAX then
        local cut = text:sub(1, TM.LABEL_MAX - 3)
        text = (cut:match("^(.*%S)%s+%S*$") or cut) .. "..."
    end
    return "Flow: " .. text
end

-- The game's own button for a flight master on the open map, and which one
-- it was (for the log), or nil. Only reads.
function TM.Button(name)
    -- The classic flight map: TaxiButton1, 2, ... in the order of TaxiNodeName.
    if NumTaxiNodes and TaxiNodeName then
        for i = 1, NumTaxiNodes() do
            if TaxiNodeName(i) == name then
                local b = _G["TaxiButton" .. i]
                if b and b:IsVisible() then return b, "TaxiButton" .. i end
            end
        end
    end
    -- The newer one: a pin a flight master on FlightMapFrame.
    local fm = _G.FlightMapFrame
    if fm and fm:IsVisible() and fm.EnumeratePinsByTemplate then
        for pin in fm:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
            local d = pin.taxiNodeData
            if d and d.name == name and pin:IsVisible() then return pin, "a pin on FlightMapFrame" end
        end
    end
    return nil
end

-- The flight masters on the open map, in world yards.
local function nodesHere()
    local N = ns.nav
    local nodes, here, map = N.ReadTaxiNodes()
    local out = {}
    for _, n in ipairs(nodes or {}) do
        local cont, wx, wy = N:ToWorld(map, n.x, n.y)
        if cont and wx then out[#out + 1] = { name = n.name, cont = cont, wx = wx, wy = wy } end
    end
    return out, here
end

local ring
local function build()
    local f = CreateFrame("Frame", "FlowTaxiMark", UIParent)
    f:SetSize(1, 1)
    f:EnableMouse(false)
    f.dots = {}
    for i = 1, TM.DOTS do
        local back = f:CreateTexture(nil, "ARTWORK")
        back:SetSize(TM.DOT + 2, TM.DOT + 2)
        back:SetColorTexture(0, 0, 0, 0.9)
        local dot = f:CreateTexture(nil, "OVERLAY")
        dot:SetSize(TM.DOT, TM.DOT)
        dot:SetColorTexture(1, 1, 1, 1)
        f.dots[i] = { back = back, dot = dot }
    end
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetShadowOffset(1, -1)
    f.angle, f.radius = 0, 14
    f:SetScript("OnUpdate", function(self, elapsed)
        -- The flight master's button went (the map closed or was redrawn).
        if not (self.target and self.target:IsVisible()) then self:Hide() return end
        self.angle = (self.angle + elapsed * TM.SPIN) % (2 * math.pi)
        for i, d in ipairs(self.dots) do
            local a = self.angle + (i - 1) * 2 * math.pi / TM.DOTS
            local x, y = math.cos(a) * self.radius, math.sin(a) * self.radius
            d.back:SetPoint("CENTER", self, "CENTER", x, y)
            d.dot:SetPoint("CENTER", self, "CENTER", x, y)
        end
    end)
    f:Hide()
    return f
end
TM._Ring = function() return ring end   -- (tests)

-- Ring a button: around it, in the route's colour, the words under it.
function TM.ShowAt(button, text)
    ring = ring or build()
    local s = ring:GetEffectiveScale() > 0 and (button:GetEffectiveScale() / ring:GetEffectiveScale()) or 1
    ring.radius = math.max(button:GetWidth(), button:GetHeight()) * s / 2 + 6
    ring.target = button
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", button, "CENTER")
    ring:SetFrameStrata(button:GetFrameStrata())
    ring:SetFrameLevel(math.min(button:GetFrameLevel() + 5, 10000))
    local c = ns.theme and ns.theme.route or { 1, 0.82, 0 }
    for _, d in ipairs(ring.dots) do d.dot:SetVertexColor(c[1] or 1, c[2] or 0.82, c[3] or 0, 1) end
    ring.label:ClearAllPoints()
    ring.label:SetPoint("TOP", ring, "CENTER", 0, -(ring.radius + 5))
    ring.label:SetText(text or "")
    ring:Show()
end

function TM.Hide()
    if ring then ring:Hide(); ring.target = nil end
end

-- The flight map is open: ring the flight master for your next step.
-- tries: the game may lay out its buttons a moment after the map opens.
function TM.Mark(tries)
    TM.Hide()
    if not TM.On() then return end
    local N = ns.nav
    local cur = N and N.current
    local pt = cur and cur.point
    if not (pt and pt.wx) then return end
    local nodes, here = nodesHere()
    local name, yd = TM.Pick(nodes, here, pt, N.FlightSeconds, N.TravelSpeed and N.TravelSpeed(), N.AIR_SAVES)
    if not name then
        TM.last = "nothing to ring: the step is as quick on foot from here, or no flight master you can fly to is near it"
        return
    end
    local button, which = TM.Button(name)
    if not button then
        if (tries or 0) < 3 then C_Timer.After(0.2, function() TM.Mark((tries or 0) + 1) end) return end
        TM.last = string.format("no button found for %s (TaxiFrame %s, FlightMapFrame %s)", name,
            _G.TaxiFrame and "there" or "missing", _G.FlightMapFrame and "there" or "missing")
        ns:Log("flight", "flight map: " .. TM.last)
        return
    end
    TM.ShowAt(button, TM.Label(cur.goal and (cur.goal.text or cur.goal.title)))
    TM.last = string.format("ringed %s (%s), %d yd from your next step", name, which, math.floor((yd or 0) + 0.5))
    ns:Log("flight", "flight map: " .. TM.last)
end

ns:On("TAXIMAP_OPENED", function() C_Timer.After(0.05, function() pcall(TM.Mark, 0) end) end)
ns:On("TAXIMAP_CLOSED", function() TM.Hide() end)

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck{ group = "route", label = "Ring your next step's flight master on the flight map",
        tip = "When you open a flight map, the flight master that lands you nearest your next step gets a ring of dots "
            .. "and the step's name. Not when the step is about as quick to walk to from where you stand.",
        get = TM.On,
        set = function(on) ns.db.nav.taxiMark = on and true or false; if not on then TM.Hide() end end }
end
