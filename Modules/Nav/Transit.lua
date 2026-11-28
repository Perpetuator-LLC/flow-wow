-------------------------------------------------------------------------------
-- Flow - Nav/Transit.lua
-- The quickest way from you to your next step, over a small travel graph
-- (0.35.422).
--
-- "It is just telling me to walk up to Crossroads instead of to fly ... these
-- mistakes should not happen." At Camp Taurajo, with both flight paths known
-- and a hand-in at the Crossroads next, Flow knew the flight was quicker: the
-- small text by the arrow said "by air" and the hover card said "Quicker by
-- air". The arrow itself still pointed straight at the Crossroads. Only a
-- step behind a wall with no way known on foot ever sent it to a flight
-- master.
--
-- And the flight it knew of was always "the flight master nearest you to the
-- one nearest the step", which isn't always the quickest pair.
--
-- So one leg (you -> your next step) is now a graph of its own:
--   places: you, the step, every flight master you know on this continent;
--   ways:   you -> the step on foot; you -> a flight master on foot; a
--           flight master -> another by flight; a flight master -> the step
--           on foot. Each costs its seconds.
-- The quickest way through it is found by Dijkstra's algorithm. When that
-- way has a flight in it and saves enough over walking, the arrow leads to
-- the flight master and says where to fly; after you land it's worked out
-- again from where you stand.
--
-- T.Edges takes `extra` ways, so a hearthstone, a teleport, a boat or a
-- zeppelin can be added as more ways between places without changing the
-- search. Today those are still worked out apart (Hearth.lua, TravelSpells,
-- Crossings.lua, Rides.lua).
-------------------------------------------------------------------------------

local _, ns = ...
local T = {}
ns.transit = T

T.SAVES = 0.8      -- a flight is only the way when it takes less than this share of the walk
T.AT = 15          -- yards: this near a flight master you're at them
T.YOU, T.STEP = "@you", "@step"

local sqrt = math.sqrt
local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end

-- Pure: the quickest way from one place to another (Dijkstra).
--   ways: { { a = place, b = place, sec = seconds, kind = "walk" | "fly" | ... } }, one direction each
--   -> seconds, { the ways taken, in order }; nil when there's no way.
function T.Shortest(ways, from, to)
    local out = {}
    for _, w in ipairs(ways or {}) do
        if type(w.sec) == "number" and w.sec >= 0 and w.a ~= nil and w.b ~= nil then
            local list = out[w.a]
            if not list then list = {}; out[w.a] = list end
            list[#list + 1] = w
        end
    end
    local best, by, done = { [from] = 0 }, {}, {}
    while true do
        local at, sec
        for place, s in pairs(best) do
            if not done[place] and (not sec or s < sec) then at, sec = place, s end
        end
        if at == nil then return nil end
        if at == to then break end
        done[at] = true
        for _, w in ipairs(out[at] or {}) do
            local s = sec + w.sec
            if not done[w.b] and (best[w.b] == nil or s < best[w.b]) then best[w.b], by[w.b] = s, w end
        end
    end
    local path, at = {}, to
    while at ~= from do
        local w = by[at]
        table.insert(path, 1, w)
        at = w.a
    end
    return best[to], path
end

-- Pure: the ways of one leg.
--   p, pt: you and the step ({ cont, wx, wy }); masters: { { name, cont, wx, wy } };
--   speed: yards a second on the ground; flightSec(from, to) -> seconds or nil;
--   walkYd: the walk from you to the step (a trail's length, else the straight line);
--   extra: more ways ({ a, b, sec, kind }), or nil
function T.Edges(p, pt, masters, speed, flightSec, walkYd, extra)
    local ways = {}
    speed = (type(speed) == "number" and speed > 0) and speed or 7
    if p.cont == pt.cont then
        ways[#ways + 1] = { a = T.YOU, b = T.STEP, kind = "walk", sec = (walkYd or dist(p.wx, p.wy, pt.wx, pt.wy)) / speed }
    end
    for _, m in ipairs(masters or {}) do
        -- (A flight master inside a walled place, Thunder Bluff on its bluff, is only
        -- a walk away from spots inside it: p.region / pt.region say where each is.)
        if m.cont == p.cont and (not m.walled or m.walled == p.region) then
            ways[#ways + 1] = { a = T.YOU, b = m.name, kind = "walk", sec = dist(p.wx, p.wy, m.wx, m.wy) / speed }
        end
        if m.cont == pt.cont and (not m.walled or m.walled == pt.region) then
            ways[#ways + 1] = { a = m.name, b = T.STEP, kind = "walk", sec = dist(m.wx, m.wy, pt.wx, pt.wy) / speed }
        end
        for _, n in ipairs(masters) do
            if n ~= m and n.cont == m.cont then
                local sec = flightSec(m.name, n.name)
                if type(sec) == "number" then ways[#ways + 1] = { a = m.name, b = n.name, kind = "fly", sec = sec } end
            end
        end
    end
    for _, w in ipairs(extra or {}) do ways[#ways + 1] = w end
    return ways
end

-- Pure: the flight to take for this leg, or nil when walking is the way (or
-- is about as quick: a flight has to take less than `saves` of the walk).
--   -> { sec, walkSec, from, to, hops = { the ways, in order } }
function T.Plan(p, pt, masters, speed, flightSec, walkYd, saves, extra)
    if not (p and pt and p.wx and pt.wx and p.cont ~= nil and p.cont == pt.cont) then return nil end
    speed = (type(speed) == "number" and speed > 0) and speed or 7
    walkYd = walkYd or dist(p.wx, p.wy, pt.wx, pt.wy)
    local total, path = T.Shortest(T.Edges(p, pt, masters, speed, flightSec, walkYd, extra), T.YOU, T.STEP)
    if not total then return nil end
    local first, last
    for _, w in ipairs(path) do
        if w.kind == "fly" then first = first or w; last = w end
    end
    if not first then return nil end
    local walkSec = walkYd / speed
    if total >= walkSec * (saves or T.SAVES) then return nil end
    return { sec = total, walkSec = walkSec, from = first.a, to = last.b, hops = path }
end

-- Pure: the arrow's line while it leads you to a flight master.
function T.Text(way, yards)
    if not way then return "" end
    yards = math.floor((yards or 0) + 0.5)
    if yards <= T.AT then return string.format("Talk to the flight master: fly to %s", tostring(way.to)) end
    return string.format("%d yd to the flight master: fly %s to %s", yards, tostring(way.from), tostring(way.to))
end

-- Pure: the card's line about it.
function T.Hint(way, fmtSeconds)
    if not way then return nil end
    fmtSeconds = fmtSeconds or tostring
    return string.format("Quicker by air (%s, not %s on foot): the arrow takes you to the flight master at %s. Fly to %s.",
        fmtSeconds(way.sec), fmtSeconds(way.walkSec), tostring(way.from), tostring(way.to))
end

-- Pure: the walled place a flight master is in, by their name ("Thunder Bluff,
-- Mulgore"), or nil. walled: { { region = map, name = "Thunder Bluff" } }
function T.WalledOf(name, walled)
    name = tostring(name)
    for _, w in ipairs(walled or {}) do
        if type(w.name) == "string" and w.name ~= "" and name:sub(1, #w.name) == w.name then return w.region end
    end
    return nil
end

-- The flight masters you know, as a list (each with the walled place it's in).
function T.Masters()
    local walled, G = {}, ns.gates
    if G and G.Name then
        for region in ns:Each("walledMap") do walled[#walled + 1] = { region = region, name = G.Name(region) } end
    end
    local list = {}
    for name, n in pairs(ns.db and ns.db.flights or {}) do
        if type(n) == "table" and n.wx then
            list[#list + 1] = { name = name, cont = n.cont, wx = n.wx, wy = n.wy, walled = T.WalledOf(name, walled) }
        end
    end
    return list
end

-- The flight for the leg from p to pt now, or nil: T.Plan over what you know.
-- (Not while you're on a flight: then you're already on your way.)
function T.Now(p, pt, walkYd, speed)
    local N = ns.nav
    if not (N and p and pt and pt.wx) then return nil end
    if UnitOnTaxi and UnitOnTaxi("player") then return nil end
    local masters = T.Masters()
    if #masters < 2 then return nil end
    -- Which walled place each end is in (nil: out in the open).
    local G = ns.gates
    if G and G.Region then
        local ra, rb = G.Region(p.map), G.Region(pt.map)
        p.region, pt.region = (G.Walled(ra) and ra) or nil, (G.Walled(rb) and rb) or nil
    end
    local way = T.Plan(p, pt, masters, speed or N.TravelSpeed(), N.FlightSeconds, walkYd)
    if way then
        local node = ns.db.flights[way.from]
        way.point = { cont = node.cont, wx = node.wx, wy = node.wy }
    end
    return way
end

-- The same, kept a second for each step's spot (the arrow asks ten times a second).
local kept = setmetatable({}, { __mode = "k" })
function T.Way(p, pt, walkYd)
    if not (p and pt) then return nil end
    local now = GetTime()
    local c = kept[pt]
    if c and now - c.at < 1 and math.abs((c.yd or 0) - (walkYd or 0)) < 30 then return c.way or nil end
    local ok, way = pcall(T.Now, p, pt, walkYd)
    way = ok and way or nil
    kept[pt] = { at = now, yd = walkYd, way = way or false }
    return way
end

-- /flow transit: the way to your next step, place by place.
function T.Lines()
    local N = ns.nav
    local cur = N and N.current
    local p = N and N:PlayerPos()
    if not (cur and cur.point and p) then return { "Flow: no next step to travel to." } end
    local masters = T.Masters()
    local speed = N.TravelSpeed()
    local out = { string.format("Flow: the way to your next step (%d yd in a straight line, %.1f yd a second, %d flight master(s) known):",
        cur.d or 0, speed, #masters) }
    local total, path = T.Shortest(T.Edges(p, cur.point, masters, speed, N.FlightSeconds, cur.d), T.YOU, T.STEP)
    if not total then out[#out + 1] = "  no way found (another continent?)"; return out end
    for _, w in ipairs(path) do
        out[#out + 1] = string.format("  %s: %s -> %s, %s", w.kind, w.a == T.YOU and "you" or tostring(w.a),
            w.b == T.STEP and "the step" or tostring(w.b), N.FormatSeconds(w.sec))
    end
    out[#out + 1] = string.format("  in all %s; on foot %s", N.FormatSeconds(total), N.FormatSeconds((cur.d or 0) / speed))
    local way = T.Now(p, cur.point, cur.d)
    out[#out + 1] = way and ("  the arrow: to the flight master at " .. tostring(way.from) .. ", then fly to " .. tostring(way.to))
        or "  the arrow: straight to the step (no flight saves enough)"
    return out
end
ns.commands.transit = function() for _, l in ipairs(T.Lines()) do print(l) end end
