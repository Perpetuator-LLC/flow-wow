-- Gates: the ways between places you can't walk between in a straight line.
--
-- WoW gives add-ons no map of walkable ground and, on Forever, no heights.
-- Seen from above, a spot on top of Thunder Bluff and a spot at its foot are
-- a few yards apart; on foot they're a lift ride apart. Zones are the same
-- on a bigger scale: Mulgore and the Barrens touch along a mountain range
-- with one pass through it. A straight arrow walks you into the cliff.
--
-- What Flow does know is which MAP a spot is on (Thunder Bluff has its own),
-- and where you yourself crossed from one map to the next on foot. Those
-- crossings are gates:
--   * learned: each time you walk (or ride a lift) from one map into another
--     the spot is kept, per continent, for all your characters;
--   * registered, for ones worth shipping with Flow:
--       ns:Register("navGate", key, { cont, wx, wy, a = uiMapID, b = uiMapID })
--
-- A REGION is a zone, or a walled map:
--   ns:Register("walledMap", uiMapID, { why })
-- a city on a mesa or behind walls. Into a walled map there is never a
-- straight line: Flow goes by a gate when it knows one, and says so when it
-- doesn't yet. A gate into a walled map is only learned on the way IN (you
-- can leave a mesa by falling off it).
--
-- Who uses it:
--   the arrow (Nav.lua steer)   a stop in another region: the trail you've
--                               walked there, else the nearest gate, then on
--   the planner (opts.walk)     the walk between two spots goes by the gate,
--                               so stops on the bluff are done together
--   the world map (N.LegVia)    the dotted path bends through the gate
--
-- /flow gates lists what's known (also in the diagnostics).

local _, ns = ...
local G = {}
ns.gates = G

G.SAME = 60       -- a crossing this close to a known gate of the same two regions is that gate
G.MAX_STEP = 60   -- yards between two looks at where you are: more is a teleport, not a walk
G.MAX = 300       -- gates kept

local floor, sqrt = math.floor, math.sqrt
local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end
local function between2(a, b) return dist(a.wx, a.wy, b.wx, b.wy) end

-- The capital cities, by the game's map numbers (Thunder Bluff's seen in
-- play: "your map: 1456"). Each is walled off from the zone around it.
ns:Register("walledMap", 1456, { why = "Thunder Bluff: on a mesa, lifts only", lift = true })
ns:Register("walledMap", 1454, { why = "Orgrimmar: behind walls, gates only" })
ns:Register("walledMap", 1458, { why = "Undercity: underground, lifts and the sewers" })
ns:Register("walledMap", 1453, { why = "Stormwind: behind walls, gates only" })
ns:Register("walledMap", 1455, { why = "Ironforge: inside a mountain, gates only" })
ns:Register("walledMap", 1457, { why = "Darnassus: on Teldrassil, a portal" })

-------------------------------------------------------------------------------
-- Regions
-------------------------------------------------------------------------------

local regionOf = {}   -- [uiMapID] = region (a map number), or false (none: a continent, the world)

function G.Walled(region) return region ~= nil and ns:Get("walledMap", region) ~= nil end
-- Reached only by lift (`lift = true`): a way in is learned only from a ride.
function G.LiftOnly(region)
    local w = region ~= nil and ns:Get("walledMap", region)
    return (w and w.lift == true) or false
end

-- The region a map belongs to: itself when it's walled, else its zone. nil
-- for a continent or world map (nothing to say about those).
function G.Region(map)
    if not map then return nil end
    local r = regionOf[map]
    if r == nil then
        -- A walled map, or a map inside one (a cave under the city): that city.
        local m = map
        for _ = 1, 6 do
            if ns:Get("walledMap", m) then r = m break end
            local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
            if not (info and info.parentMapID and info.parentMapID ~= 0) then break end
            m = info.parentMapID
        end
        if not r then
            r = (ns.nav and ns.nav.ZoneOf and ns.nav.ZoneOf(map)) or map
            local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(r)
            local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
            if info and (info.mapType or zoneType) < zoneType then r = false end
        end
        regionOf[map] = r or false
    end
    return r or nil
end

function G.Name(region)
    local info = region and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(region)
    return info and info.name or ("map " .. tostring(region))
end

-------------------------------------------------------------------------------
-- Pure parts (the tests pass their own lists in)
-------------------------------------------------------------------------------

-- Is a crossing from one region into another one to learn? Into a walled
-- place: yes. Out of one into the open: no. Into a place only lifts reach
-- (liftOnly): only when you rode one (rode), not when the map flipped as you
-- walked along its edge.
function G.Learnable(from, to, walledFrom, walledTo, liftOnly, rode)
    if not (from and to) or from == to then return false end
    if walledFrom and not walledTo then return false end
    if liftOnly and not rode then return false end
    return true
end

-- Is this crossing a new gate, or one already known (the same two regions,
-- within G.SAME yards)?
function G.IsNew(list, cont, wx, wy, a, b)
    for _, g in ipairs(list) do
        if g.cont == cont and ((g.a == a and g.b == b) or (g.a == b and g.b == a))
            and dist(g.wx, g.wy, wx, wy) < G.SAME then return false end
    end
    return true
end

-- The gates to pass from spot a (in region ra) to spot b (in rb), as
-- { points = { gate, ... }, yards }: through one gate, else through two (one
-- region in between). nil: none known.
--   between(r1, r2) -> gates between two regions; touching(r) -> gates of one
function G.Route(a, b, ra, rb, between, touching)
    local best, bestD
    for _, g in ipairs(between(ra, rb) or {}) do
        if g.cont == a.cont then
            local d = between2(a, g) + between2(g, b)
            if not bestD or d < bestD then best, bestD = { g }, d end
        end
    end
    if best then return { points = best, yards = bestD } end
    for _, g1 in ipairs(touching(ra) or {}) do
        if g1.cont == a.cont then
            local mid = (g1.a == ra) and g1.b or g1.a
            if mid ~= rb and mid ~= ra then
                for _, g2 in ipairs(between(mid, rb) or {}) do
                    if g2.cont == a.cont then
                        local d = between2(a, g1) + between2(g1, g2) + between2(g2, b)
                        if not bestD or d < bestD then best, bestD = { g1, g2 }, d end
                    end
                end
            end
        end
    end
    if best then return { points = best, yards = bestD } end
    return nil
end

-- A walled place with no whole way known: at least its own nearest gate
-- (out of it, or into it), then straight on. nil: it has no gate yet.
function G.Partial(a, b, walled, touching)
    local best, bestD
    for _, g in ipairs(touching(walled) or {}) do
        if g.cont == a.cont then
            local d = between2(a, g) + between2(g, b)
            if not bestD or d < bestD then best, bestD = g, d end
        end
    end
    return best and { points = { best }, yards = bestD, partial = true } or nil
end

-------------------------------------------------------------------------------
-- The gates Flow knows
-------------------------------------------------------------------------------

local function store()
    ns.db.nav.gates = ns.db.nav.gates or {}
    return ns.db.nav.gates
end

local index   -- { by = { [pair key] = { gates } }, touching = { [region] = { gates } }, n }
local function pairKey(a, b)
    if a > b then a, b = b, a end
    return a * 100000 + b
end
local function build()
    index = { by = {}, touching = {}, n = 0 }
    local function add(g)
        local a, b = G.Region(g.a), G.Region(g.b)
        if not (g.cont and g.wx and g.wy and a and b) or a == b then return end
        local e = { cont = g.cont, wx = g.wx, wy = g.wy, a = a, b = b }
        local k = pairKey(a, b)
        index.by[k] = index.by[k] or {}
        table.insert(index.by[k], e)
        for _, r in ipairs({ a, b }) do
            index.touching[r] = index.touching[r] or {}
            table.insert(index.touching[r], e)
        end
        index.n = index.n + 1
    end
    for _, g in ipairs(store()) do add(g) end
    for _, g in ns:Each("navGate") do add(g) end
end
function G.Between(a, b)
    if not index then build() end
    return index.by[pairKey(a, b)]
end
function G.Touching(r)
    if not index then build() end
    return index.touching[r]
end
function G.Count()
    if not index then build() end
    return index.n
end
function G.Forget() index = nil end   -- (after a change to the list)

-- From spot a to spot b ({ cont, wx, wy, map }): the gates on the way.
--   nil                        a straight line: the same region, or two open
--                              zones with no gate known between them
--   { points, yards }          through these gates, in order
--   { points, yards, partial } a walled place: its nearest gate, then straight
--   { points = {}, unknown }   a walled place Flow knows no way into (or out of) yet
function G.Via(a, b)
    if not (a and b and a.wx and b.wx and a.cont == b.cont and a.map and b.map) then return nil end
    local ra, rb = G.Region(a.map), G.Region(b.map)
    if not ra or not rb or ra == rb then return nil end
    local r = G.Route(a, b, ra, rb, G.Between, G.Touching)
    local wa, wb = G.Walled(ra), G.Walled(rb)
    if not r and (wa or wb) then
        r = (wa and G.Partial(a, b, ra, G.Touching)) or (wb and G.Partial(a, b, rb, G.Touching))
            or { points = {}, unknown = true }
    end
    if r then r.from, r.to = ra, rb end
    return r
end

-- The planner's answer for one plan: the walk between two spots when it goes
-- by a gate (longer than the straight line), else nil. nil when no gate is
-- known at all (then the planner needn't ask).
-- The planner asks about the same pairs of spots over and over in one plan:
-- each pair is worked out once.
function G.PlanWalk()
    if G.Count() == 0 then return nil end
    local memo = {}
    return function(a, b)
        local row = memo[a]
        if not row then row = {}; memo[a] = row end
        local yards = row[b]
        if yards == nil then
            local via = G.Via(a, b)
            yards = (via and via.points[1]) and via.yards or false
            row[b] = yards
        end
        return yards or nil
    end
end

-------------------------------------------------------------------------------
-- Learning them as you walk
-------------------------------------------------------------------------------

-- You crossed from one map to another on foot: keep the spot. rode: you
-- stood still on the map while it happened (a lift carried you).
function G.Learn(fromMap, toMap, p, rode)
    local a, b = G.Region(fromMap), G.Region(toMap)
    if not G.Learnable(a, b, G.Walled(a), G.Walled(b), G.LiftOnly(b), rode) then return false end
    local list = store()
    if #list >= G.MAX or not G.IsNew(list, p.cont, p.wx, p.wy, a, b) then return false end
    list[#list + 1] = { cont = p.cont, wx = floor(p.wx), wy = floor(p.wy), a = a, b = b }
    G.Forget()
    ns:Log("nav", string.format("learned a way from %s into %s%s", G.Name(a), G.Name(b), rode and " (a lift)" or ""))
    if ns.nav then ns.nav.planDirty = true end
    return true
end

-- A lift, or a walk? On a lift you stand still on the map while it carries
-- you up, and the map changes under you. Walking along the rim of Thunder
-- Bluff the game's map flips between Mulgore and Thunder Bluff too: four
-- "ways in" were learned in twenty minutes on a mesa with two lifts, and a
-- spot under a bridge is no way up (0.35.175). So into a lift-only place a
-- way is learned only when you rode. Pure:
--   stillSince: when you last stopped moving (nil while moving)
--   lastSpan, endedAt: how long your last standstill was, and when it ended
G.RIDE_STILL = 1.5   -- standing this long as the map changes: riding
G.RIDE_SPAN = 3      -- or a standstill this long...
G.RIDE_AFTER = 2.5   -- ...that ended this short a while ago (you stepped off)
G.STILL_SPEED = 1    -- yards a second: slower than this is standing
function G.Rode(now, stillSince, lastSpan, endedAt)
    if stillSince and now - stillSince >= G.RIDE_STILL then return true end
    return (lastSpan or 0) >= G.RIDE_SPAN and now - (endedAt or -math.huge) <= G.RIDE_AFTER
end

-- Called with where you are, several times a second (Nav.lua). carried: on
-- a flight path or flying, which is no walk. now: the clock (tests pass it).
local last
local still = { since = nil, lastSpan = 0, endedAt = -math.huge }
function G.Track(p, carried, now)
    now = now or GetTime()
    if not p or carried then
        last, still.since, still.lastSpan, still.endedAt = nil, nil, 0, -math.huge
        return
    end
    if last and last.cont == p.cont then
        local moved = dist(p.wx, p.wy, last.wx, last.wy)
        local dt = math.max(now - (last.t or now), 0.01)
        if moved / dt < G.STILL_SPEED then
            still.since = still.since or now
        else
            if still.since then still.lastSpan, still.endedAt = now - still.since, now end
            still.since = nil
        end
        if last.map ~= p.map and moved <= G.MAX_STEP then
            G.Learn(last.map, p.map, p, G.Rode(now, still.since, still.lastSpan, still.endedAt))
        end
    end
    last = last or {}
    last.cont, last.wx, last.wy, last.map, last.t = p.cont, p.wx, p.wy, p.map, now
end
-------------------------------------------------------------------------------
-- /flow gates
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Ways by air (0.35.182: "flow gates should include flight paths"). A
-- flight path is a way between maps like a lift is: you came into Thunder
-- Bluff by air, and Flow said it knew no way in or out.
--   * /flow gates lists the flight masters Flow knows and the people who
--     carry you (Rides.lua), beside the ways on foot.
--   * A walled place with no way known on foot: when flying from a flight
--     master you know gets you nearer the stop, that flight master is the
--     gate. The arrow leads there and says where to fly.
-------------------------------------------------------------------------------

-- Pure: a way that was "unknown" (no gate on foot), by air.
--   via: { points = {}, unknown = true, from, to } from G.Via
--   air: { from = "Thunder Bluff", to = "Crossroads" } (Nav's AirRoute), or nil
--   node: where the `from` flight master stands { cont, wx, wy }; yards: from you to it
-- -> via, now { points = { node }, yards, air = air } (no longer unknown); or via as it was
function G.WithAir(via, air, node, yards)
    if not (via and via.unknown and air and air.from and air.to and node and node.wx) then return via end
    via.points = { { cont = node.cont, wx = node.wx, wy = node.wy } }
    via.yards = yards or 0
    via.air = { from = air.from, to = air.to }
    via.unknown = nil
    return via
end

-- Pure: the lines about ways by air for /flow gates.
--   flights: { [name] = spot } (ns.db.flights); rides: { { name, how, mine } }
function G.AirLines(flights, rides)
    local names = {}
    for name in pairs(flights or {}) do names[#names + 1] = name end
    table.sort(names)
    local out = {}
    if #names == 0 then
        out[1] = "flight paths: none known yet. Talk to a flight master: Flow learns every flight path on their map."
    else
        out[1] = string.format("flight paths: %d known (a way in and out of a walled place too): %s", #names, table.concat(names, "; "))
    end
    for _, r in ipairs(rides or {}) do
        if r.mine then out[#out + 1] = string.format("ride: %s (%s)", r.name, r.how or "a ride") end
    end
    return out
end

function G.Lines()
    local out = {}
    for _, g in ipairs(store()) do
        out[#out + 1] = string.format("%s <-> %s at %d, %d (continent %s)", G.Name(g.a), G.Name(g.b), g.wx, g.wy, tostring(g.cont))
    end
    return out
end

ns.commands.gates = function(arg)
    arg = (arg or ""):lower()
    if arg == "forget" then
        wipe(store())
        G.Forget()
        ns:Print("forgot the ways between maps you've walked")
        return
    end
    local lines = G.Lines()
    ns:Print(string.format("ways between maps Flow has learned from your walking: %d (it learns one each time you walk or ride from one map into another)", #lines))
    for _, l in ipairs(lines) do print("  " .. l) end
    -- Ways by air: the flight masters you know, and the people who carry you.
    local rides = {}
    if ns.rides then
        local _, class = UnitClass("player")
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        for _, r in ipairs(ns.rides.List()) do
            rides[#rides + 1] = { name = r.name, how = r.how,
                mine = (not r.class or r.class == class) and (not r.faction or r.faction == faction) }
        end
    end
    for _, l in ipairs(G.AirLines(ns.db.flights, rides)) do print("  " .. l) end
    local p = ns.nav and ns.nav:PlayerPos()
    if p then
        local r = G.Region(p.map)
        print(string.format("  you: %s%s", r and G.Name(r) or "no region", G.Walled(r) and " (walled: in and out only by a gate)" or ""))
    end
    print("  /flow gates forget")
end

ns:Register("help", "gates", { order = 36, title = "Ways between maps", lines = {
    "Flow learns where you cross from one map into another on foot (a lift up Thunder Bluff, a pass between zones) and sends the arrow, the route and the map's path through them.",
    "/flow gates: the ones it knows. /flow gates forget.",
} })

-- Ways into a lift-only place learned before 0.35.175 may be spots where the
-- map flipped as you walked its rim, not lifts: forgotten once, and learned
-- again the next time you ride up.
ns:OnLoad(function(saved)
    local nav = saved.nav
    if not nav or (nav.gatesRule or 1) >= 2 then return end
    nav.gatesRule = 2
    local kept, dropped = {}, 0
    for _, g in ipairs(nav.gates or {}) do
        if G.LiftOnly(g.a) or G.LiftOnly(g.b) then dropped = dropped + 1 else kept[#kept + 1] = g end
    end
    nav.gates = kept
    G.Forget()
    if dropped > 0 then
        ns:Log("nav", string.format("forgot %d way(s) into lift-only places learned before the lift rule: ride a lift up once more", dropped))
    end
end)
