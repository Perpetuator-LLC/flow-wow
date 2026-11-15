-- Someone who carries you far: the druids' flight masters in Moonglade.
--
-- A level 12 druid cast Teleport: Moonglade for the Bear Form quest, and the
-- next step was back in Thunder Bluff: "how do I get back now? where do I go
-- from Moonglade?" (0.35.178). Flow knew the way in (TravelSpells.lua) and no
-- way out, so the arrow pointed across the whole of Kalimdor. The way out is
-- a person: Bunthen Plainswind flies druids to Thunder Bluff, free. So:
--
--   ns:Register("ride", "<NPC name>", { from = uiMapID, to = uiMapID,
--       land = { x, y } on the `to` map, toName = "...", class = "DRUID",
--       faction = "Horde", how = "he flies druids to Thunder Bluff, free" })
--
-- While you're in the `from` zone and your next step is outside it, the way
-- is: to that NPC, the flight, and on from where you land. The planner
-- measures legs so (opts.ride), and the arrow leads to the NPC and says who
-- to talk to. Where the NPC stands is read like any NPC's (your own visits,
-- other players' shared spots, Questie): nothing about it is stored here.

local _, ns = ...
local R = {}
ns.rides = R

R.SPEEDUP = 4.5   -- a flight covers ground about this many times faster than running
R.TALK = 40       -- what the talk and the take-off are worth, in running yards

-- (The classic map numbers: Moonglade 1450, Thunder Bluff 1456, Teldrassil 1438.)
ns:Register("ride", "Bunthen Plainswind", { from = 1450, to = 1456, land = { 0.47, 0.50 }, toName = "Thunder Bluff",
    class = "DRUID", faction = "Horde", how = "he flies druids to Thunder Bluff, free" })
ns:Register("ride", "Silva Fil'naveth", { from = 1450, to = 1438, land = { 0.58, 0.94 }, toName = "Rut'theran Village, below Darnassus",
    class = "DRUID", faction = "Alliance", how = "she flies druids to Rut'theran Village, free" })

-- Pure: what a ride costs in running yards: to the one who takes you, the
-- flight, and on from where you land.
function R.Cost(toNpc, flight, onward, speedup, talk)
    return toNpc + (talk or R.TALK) + flight / (speedup or R.SPEEDUP) + onward
end

-- Pure: the ride out of the zone spot a is in, for you, or nil. b in the
-- same zone: no ride (you don't fly out of the zone your step is in).
--   rides: { { name, from, class, faction } }; zoneOf(map) -> its zone
function R.Fits(a, b, rides, zoneOf, class, faction)
    if not (a and b and a.map and b.map) then return nil end
    local za, zb = zoneOf(a.map), zoneOf(b.map)
    if not za or za == zb then return nil end
    for _, r in ipairs(rides) do
        if zoneOf(r.from) == za and (not r.class or r.class == class) and (not r.faction or r.faction == faction) then
            return r
        end
    end
    return nil
end

-- Pure: the ride that leaves from the zone `map` is in, for you, or nil
-- (wherever it's going: for "which flight am I on?").
function R.From(map, rides, zoneOf, class, faction)
    if not map then return nil end
    local z = zoneOf(map)
    for _, r in ipairs(rides) do
        if zoneOf(r.from) == z and (not r.class or r.class == class) and (not r.faction or r.faction == faction) then
            return r
        end
    end
    return nil
end

local function zoneOf(map)
    local N = ns.nav
    return (N and N.ZoneOf and N.ZoneOf(map)) or map
end

-- (Registered when the files load: read once.)
local list
local function all()
    if not list then
        list = {}
        for name, r in ns:Each("ride") do
            list[#list + 1] = { name = name, from = r.from, to = r.to, land = r.land, toName = r.toName,
                                class = r.class, faction = r.faction, how = r.how }
        end
        table.sort(list, function(x, y) return x.name < y.name end)
    end
    return list
end
function R.List() return all() end

local function me()
    local _, class = UnitClass("player")
    return class, UnitFactionGroup and UnitFactionGroup("player") or nil
end

-- The ride that leaves from where you are (spot a), or nil.
function R.Here(a)
    local class, faction = me()
    return R.From(a and a.map, all(), zoneOf, class, faction)
end

-- A map spot as the route's points are: { map, x, y, cont, wx, wy }, or nil.
local function world(map, x, y)
    local N = ns.nav
    if not (N and N.ToWorld and map and x and y) then return nil end
    local ok, cont, wx, wy = pcall(N.ToWorld, N, map, x, y)
    if not (ok and cont and wx and wy) then return nil end
    return { map = map, x = x, y = y, cont = cont, wx = wx, wy = wy }
end

-- Where the one who takes you stands, and where you land. The landing is
-- kept for the session; the NPC is looked up again until it's found (the
-- quest data may load after Flow).
local spots, lands, missAt = {}, {}, {}
R.RETRY = 10   -- seconds between looks for an NPC nobody has placed yet (the arrow asks many times a second)
function R.Spot(r)
    local s = spots[r.name]
    if s then return s end
    local now = GetTime and GetTime() or 0
    if missAt[r.name] and now - missAt[r.name] < R.RETRY then return nil end
    local pts = ns.places and ns.places.Points and ns.places:Points(r.name) or {}
    local p = pts[1]
    s = p and world(p.map, p.x, p.y) or nil
    spots[r.name] = s
    if not s then missAt[r.name] = now end
    return s
end
function R.Landing(r)
    local l = lands[r.name]
    if l == nil then
        l = (r.land and world(r.to, r.land[1], r.land[2])) or false
        lands[r.name] = l
    end
    return l or nil
end
function R._Forget() spots, lands, missAt, list = {}, {}, {}, nil end   -- (tests)

local function dist(a, b)
    return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2)
end

-- From spot a toward spot b: the ride, when one is yours here and it beats
-- going straight: { name, how, toName, point = where they stand, toNpc,
-- yards = the whole way's cost }. Second value: a ride that fits but can't
-- be measured (nobody knows where the NPC stands, or b is on another
-- continent): still worth naming.
--   spotOf, landOf: (tests) stand-ins for R.Spot and R.Landing
function R.Way(a, b, class, faction, spotOf, landOf)
    if class == nil then class, faction = me() end
    local r = R.Fits(a, b, all(), zoneOf, class, faction)
    if not r then return nil end
    local npc, land = (spotOf or R.Spot)(r), (landOf or R.Landing)(r)
    if not (npc and land and a.wx and b.wx) then return nil, r end
    if a.cont and npc.cont and a.cont ~= npc.cont then return nil, r end
    if b.cont and land.cont and b.cont ~= land.cont then return nil, r end
    local toNpc = dist(a, npc)
    local cost = R.Cost(toNpc, dist(npc, land), dist(land, b))
    if cost >= dist(a, b) then return nil end   -- (a step next door: walk)
    return { name = r.name, how = r.how, toName = r.toName, point = npc, toNpc = toNpc, yards = cost }
end

-- The planner's answer for one plan: a leg out of a ride's zone costs the
-- ride. nil when no ride is yours (then the planner needn't ask).
function R.PlanRide()
    local class, faction = me()
    local any = false
    for _, r in ipairs(all()) do
        if (not r.class or r.class == class) and (not r.faction or r.faction == faction) then any = true end
    end
    if not any then return nil end
    return function(a, b)
        local w = R.Way(a, b, class, faction)
        return w and w.yards or nil
    end
end

-- Beside the arrow: "140 yd to Bunthen Plainswind: he flies druids to Thunder Bluff, free".
function R.Text(way, yards)
    if not way then return "" end
    return string.format("%d yd to %s: %s", yards or way.toNpc or 0, way.name, way.how or ("a ride to " .. (way.toName or "there")))
end

-- A line for the arrow's panel, or nil: how to get out of here.
--   r: a way (R.Way), or the ride it named without measuring
function R.HintOf(r)
    if not r then return nil end
    return string.format("It's a long way on foot: talk to %s here (%s).", r.name, r.how or ("a ride to " .. (r.toName or "there")))
end
function R.Hint(a, b)
    local way, unplaced = R.Way(a, b)
    return R.HintOf(way or unplaced)
end

-- /flow rides: who carries you, and what Flow knows of them.
function R.Lines()
    local class, faction = me()
    local out = {}
    for _, r in ipairs(all()) do
        local mine = (not r.class or r.class == class) and (not r.faction or r.faction == faction)
        local s = R.Spot(r)
        out[#out + 1] = string.format("%s: %s (%s%s); stands %s%s", r.name, r.how or "?", r.faction or "anyone",
            r.class and (", " .. r.class:lower() .. "s") or "",
            s and string.format("at %.1f, %.1f on map %d", s.x * 100, s.y * 100, s.map) or "somewhere Flow doesn't know yet",
            mine and "" or "; not for you")
    end
    return out
end
ns.commands.rides = function()
    ns:Print("rides (people who carry you far):")
    for _, l in ipairs(R.Lines()) do print("  " .. l) end
end
