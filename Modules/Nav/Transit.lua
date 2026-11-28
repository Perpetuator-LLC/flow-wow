-------------------------------------------------------------------------------
-- Flow - Nav/Transit.lua
-- The quickest way from you to your next step, over a small travel graph
-- (0.35.422; the hearthstone, teleports and the planner: 0.35.424).
--
-- "It is just telling me to walk up to Crossroads instead of to fly ... these
-- mistakes should not happen." At Camp Taurajo, with both flight paths known
-- and a hand-in at the Crossroads next, Flow knew the flight was quicker: the
-- small text by the arrow said "by air" and the hover card said "Quicker by
-- air". The arrow itself still pointed straight at the Crossroads. Only a
-- step behind a wall with no way known on foot ever sent it to a flight
-- master. And the flight it knew of was always "the flight master nearest you
-- to the one nearest the step", which isn't always the quickest pair.
--
-- "That should also include Hearthstone, if it's available, Moonglade
-- teleport. If they're a mage, should have their teleports set up in there
-- ... is it faster to get there with the Hearthstone? Is it faster to get
-- there with flight? ... using the Hearthstone, then the flight."
--
-- So one leg (from a spot to a spot) is a graph of its own:
--   places: you, the step, every flight master you know, the inn your
--           hearthstone is set to, where each travel spell you know lands;
--   ways:   on foot (you -> the step, you -> a flight master, a place -> the
--           step, a landing -> a flight master), by flight (a flight master
--           -> another), by a cast (your hearthstone: you -> your inn, when
--           it's ready; a travel spell: from anywhere -> where it lands).
-- Each way costs its seconds, and the quickest way through is found by
-- Dijkstra's algorithm (T.Shortest). So "hearthstone, then fly" is found
-- when that's the quickest, not only "walk" or "fly".
--
-- The arrow (T.Way): when the quickest way starts with a flight, it leads to
-- the flight master and says where to fly. When it starts with a cast, the
-- arrow's line says so ("Quicker: hearthstone to Camp Taurajo, then fly Camp
-- Taurajo to Crossroads"); Flow never casts for you. After each hop it's
-- worked out again from where you stand.
--
-- The order of your steps (T.PlanCost, the planner's `air`): the same places
-- and ways, solved once a plan between every pair of places, so the trip
-- between two steps is priced by the quickest flights and travel spells, not
-- by the nearest flight masters. Your hearthstone isn't in that: it's one use
-- an hour, and the planner prices each trip on its own.
--
-- Not here: boats and zeppelins (they're steps of their own, Crossings.lua),
-- and the rides out of Moonglade (Rides.lua).
-------------------------------------------------------------------------------

local _, ns = ...
local T = {}
ns.transit = T

T.SAVES = 0.8        -- a flight (or travel spell) is only the way when it takes less than this share of the walk
T.AT = 15            -- yards: this near a flight master you're at them
T.LEAVE = 1.3        -- the walk out of a walled place is this much longer than the straight line
T.CAST, T.LOAD = 10, 10               -- seconds: a cast, and a guess at the loading screen
T.HEARTH_SAVE, T.HEARTH_SHARE = 120, 0.25   -- your hearthstone: only when it saves 2 minutes and a quarter of the trip
T.NEAR = 3           -- the planner tries this many places nearest each end of a trip
T.YOU, T.STEP = "@you", "@step"

local sqrt, huge = math.sqrt, math.huge
local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end

-- Pure: the quickest way from one place to another (Dijkstra).
--   ways: { { a = place, b = place, sec = seconds, kind = "walk" | "fly" | "hearth" | "cast" } }, one direction each
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

-- Pure: the walk from a spot to a place, in yards, or nil when there's none.
-- A flight master inside a walled place (Thunder Bluff on its bluff) is only
-- a walk away from spots inside it, unless the place says how far the way in
-- is (m.fromYou: yards by the gate, or false for no way known).
local function walkIn(spot, m, own)
    if m.cont ~= spot.cont then return nil end
    if own ~= nil then return own or nil end
    if m.walled and m.walled ~= spot.region then return nil end
    return dist(spot.wx, spot.wy, m.wx, m.wy)
end
-- Pure: the walk on from a place to a spot. Out of a walled place: longer
-- than the straight line (the gate, the lift).
local function walkOut(m, spot)
    if m.cont ~= spot.cont then return nil end
    local d = dist(m.wx, m.wy, spot.wx, spot.wy)
    if m.walled and m.walled ~= spot.region then return d * T.LEAVE end
    return d
end

-- Pure: the ways of one leg.
--   p, pt: you and the step ({ cont, wx, wy, region = the walled place it's in });
--   places: { { name, cont, wx, wy, walled, landing = true for where a cast lands (else a flight master),
--               onward = false when no flight leaves from there } };
--   speed: yards a second on the ground; flightSec(from, to) -> seconds or nil;
--   walkYd: the walk from you to the step (a trail's length, else the straight line);
--   extra: more ways ({ a, b, sec, kind }), or nil (T.JumpWays makes the casts)
function T.Edges(p, pt, places, speed, flightSec, walkYd, extra)
    local ways = {}
    speed = (type(speed) == "number" and speed > 0) and speed or 7
    if p.cont == pt.cont then
        ways[#ways + 1] = { a = T.YOU, b = T.STEP, kind = "walk", sec = (walkYd or dist(p.wx, p.wy, pt.wx, pt.wy)) / speed }
    end
    for _, m in ipairs(places or {}) do
        if not m.landing then
            local d = walkIn(p, m, m.fromYou)
            if d then ways[#ways + 1] = { a = T.YOU, b = m.name, kind = "walk", sec = d / speed } end
        end
        local on = walkOut(m, pt)
        if on then ways[#ways + 1] = { a = m.name, b = T.STEP, kind = "walk", sec = on / speed } end
        for _, n in ipairs(places) do
            if n ~= m and not n.landing then
                if not m.landing then
                    local sec = n.cont == m.cont and flightSec(m.name, n.name)
                    if type(sec) == "number" then ways[#ways + 1] = { a = m.name, b = n.name, kind = "fly", sec = sec } end
                elseif m.onward ~= false then
                    -- From where a cast lands, on foot to a flight master there.
                    local d = walkIn({ cont = m.cont, wx = m.wx, wy = m.wy, region = m.walled }, n)
                    if d then ways[#ways + 1] = { a = m.name, b = n.name, kind = "walk", sec = d / speed } end
                end
            end
        end
    end
    for _, w in ipairs(extra or {}) do ways[#ways + 1] = w end
    return ways
end

-- Pure: the casts as ways.
--   jumps: { { to = place name, sec, kind = "hearth" | "cast", name = what to cast or where to,
--              from = "you" (your hearthstone: once) | "any" (a travel spell: from anywhere) } }
function T.JumpWays(places, jumps)
    local ways = {}
    for _, j in ipairs(jumps or {}) do
        ways[#ways + 1] = { a = T.YOU, b = j.to, kind = j.kind, sec = j.sec, name = j.name }
        if j.from == "any" then
            for _, m in ipairs(places or {}) do
                if m.name ~= j.to then ways[#ways + 1] = { a = m.name, b = j.to, kind = j.kind, sec = j.sec, name = j.name } end
            end
        end
    end
    return ways
end

-- Pure: the quickest way for this leg when it isn't simply walking, or nil
-- when walking is the way (or about as quick: it has to take less than
-- `saves` of the walk; a way with your hearthstone in it has to save
-- T.HEARTH_SAVE seconds and T.HEARTH_SHARE of the walk, or it's left out).
--   -> { sec, walkSec, kind = the first hop that isn't a walk ("fly" | "hearth" | "cast"),
--        from, to = the first and last flight master flown between (nil: no flight),
--        hops = { the ways, in order } }
function T.Plan(p, pt, places, speed, flightSec, walkYd, saves, extra)
    if not (p and pt and p.wx and pt.wx and p.cont ~= nil and pt.cont ~= nil) then return nil end
    speed = (type(speed) == "number" and speed > 0) and speed or 7
    if p.cont == pt.cont then walkYd = walkYd or dist(p.wx, p.wy, pt.wx, pt.wy) end
    local walkSec = walkYd and (walkYd / speed) or huge
    local ways = T.Edges(p, pt, places, speed, flightSec, walkYd, extra)
    for _ = 1, 2 do
        local total, path = T.Shortest(ways, T.YOU, T.STEP)
        if not total then return nil end
        local first, from, to, hearth
        for _, w in ipairs(path) do
            if w.kind ~= "walk" then first = first or w end
            if w.kind == "fly" then from = from or w.a; to = w.b end
            if w.kind == "hearth" then hearth = true end
        end
        if not first then return nil end
        local saving = walkSec - total
        if hearth and not (saving >= T.HEARTH_SAVE and saving >= walkSec * T.HEARTH_SHARE) then
            -- Not worth the hour's wait: the quickest way without it.
            local kept = {}
            for _, w in ipairs(ways) do if w.kind ~= "hearth" then kept[#kept + 1] = w end end
            ways = kept
        else
            if total >= walkSec * (saves or T.SAVES) then return nil end
            return { sec = total, walkSec = walkSec, kind = first.kind, from = from, to = to, hops = path }
        end
    end
    return nil
end

-- Pure: a way in words: "hearthstone to Camp Taurajo, then fly Camp Taurajo to Crossroads".
function T.Say(way)
    local parts, flyFrom, flyTo = {}, nil, nil
    local function flush()
        if flyFrom then parts[#parts + 1] = string.format("fly %s to %s", tostring(flyFrom), tostring(flyTo)) end
        flyFrom, flyTo = nil, nil
    end
    for _, w in ipairs(way and way.hops or {}) do
        if w.kind == "fly" then
            flyFrom, flyTo = flyFrom or w.a, w.b
        else
            flush()
            if w.kind == "hearth" then parts[#parts + 1] = "hearthstone to " .. tostring(w.name or "your inn")
            elseif w.kind == "cast" then parts[#parts + 1] = "cast " .. tostring(w.name or "your travel spell") end
        end
    end
    flush()
    return table.concat(parts, ", then ")
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
    local walk = way.walkSec and way.walkSec < huge and (", not " .. fmtSeconds(way.walkSec) .. " on foot") or ""
    if way.kind == "fly" then
        return string.format("Quicker by air (%s%s): the arrow takes you to the flight master at %s. Fly to %s.",
            fmtSeconds(way.sec), walk, tostring(way.from), tostring(way.to))
    end
    return string.format("Quicker (%s%s): %s. Your call: Flow never casts it for you.", fmtSeconds(way.sec), walk, T.Say(way))
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

-- The walled place a map is in, or nil for the open.
local function regionOf(map)
    local G = ns.gates
    if not (G and G.Region and map) then return nil end
    local r = G.Region(map)
    return (r and G.Walled(r) and r) or nil
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

-- Where the travel spells you know land, and the casts that take you there.
--   -> places (to add to the flight masters), jumps
function T.Spells()
    local places, jumps = {}, {}
    local TS, N = ns.travelSpells, ns.nav
    if not (TS and TS.Mine and N) then return places, jumps end
    local ok, mine = pcall(TS.Mine)
    for _, s in ipairs(ok and mine or {}) do
        local cont, wx, wy = N:ToWorld(s.map, 0.5, 0.5)
        if cont and wx then
            local name = "@spell:" .. s.name
            places[#places + 1] = { name = name, cont = cont, wx = wx, wy = wy, landing = true, walled = regionOf(s.map),
                                    onward = s.fly ~= false }
            jumps[#jumps + 1] = { to = name, sec = T.CAST + T.LOAD, kind = "cast", name = s.name, from = "any" }
        end
    end
    return places, jumps
end

-- Your hearthstone: the inn it's set to and the cast, when Flow knows the inn
-- and the game says how long is left on it. -> place, jump; or nil and why.
function T.Hearth()
    local H, N = ns.hearth, ns.nav
    if not (H and H.BindPoint and H.CooldownLeft and N) then return nil, "no hearthstone module" end
    local okB, p, bind = pcall(H.BindPoint, H)
    if not (okB and p) then return nil, "Flow doesn't know the inn it's set to" end
    local okC, left = pcall(H.CooldownLeft, H)
    if not okC or type(left) ~= "number" then return nil, "you carry none, or the game won't say its cooldown" end
    local cont, wx, wy = N:ToWorld(p.map, p.x, p.y)
    if not (cont and wx) then return nil, "its inn has no place on the map" end
    return { name = "@inn", cont = cont, wx = wx, wy = wy, landing = true, walled = regionOf(p.map) },
           { to = "@inn", sec = left + T.CAST + T.LOAD, kind = "hearth", name = bind, from = "you" }, left
end

-- The quickest way for the leg from p to pt now, or nil: T.Plan over what
-- you know. (Not while you're on a flight: then you're already on your way.)
function T.Now(p, pt, walkYd, speed)
    local N = ns.nav
    if not (N and p and pt and pt.wx) then return nil end
    if UnitOnTaxi and UnitOnTaxi("player") then return nil end
    local places = T.Masters()
    local landings, jumps = T.Spells()
    for _, l in ipairs(landings) do places[#places + 1] = l end
    local inn, cast = T.Hearth()
    if inn then places[#places + 1] = inn; jumps[#jumps + 1] = cast end
    if #places < 2 and #jumps == 0 then return nil end
    p.region, pt.region = regionOf(p.map), regionOf(pt.map)
    -- A flight master inside a walled place you're outside of: by its gate, when Flow knows one.
    local G = ns.gates
    for _, m in ipairs(places) do
        if not m.landing and m.walled and m.walled ~= p.region and G and G.Via and p.map then
            local via = G.Via(p, { cont = m.cont, wx = m.wx, wy = m.wy, map = m.walled })
            m.fromYou = (via and via.points and via.points[1] and via.yards) or false
        end
    end
    local way = T.Plan(p, pt, places, speed or N.TravelSpeed(), N.FlightSeconds, walkYd, nil, T.JumpWays(places, jumps))
    if way and way.kind == "fly" then
        for _, m in ipairs(places) do
            if m.name == way.from then way.point = { cont = m.cont, wx = m.wx, wy = m.wy, map = m.walled } end
        end
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

-------------------------------------------------------------------------------
-- The planner: what a trip between two steps costs, by the same ways.
-------------------------------------------------------------------------------

-- Pure: the quickest seconds between every pair of places (flights, the walk
-- from where a cast lands to a flight master, and casts from anywhere).
--   -> D, where D[i][j] is seconds from places[i] to places[j] (math.huge: no way)
function T.Hubs(places, speed, flightSec, jumps)
    local n, D = #places, {}
    local index = {}
    for i, m in ipairs(places) do index[m.name] = i end
    for i = 1, n do
        local row, m = {}, places[i]
        for j = 1, n do
            local o, sec = places[j], huge
            if i == j then sec = 0
            elseif not o.landing then
                if not m.landing then
                    local f = o.cont == m.cont and flightSec(m.name, o.name)
                    if type(f) == "number" then sec = f end
                elseif m.onward ~= false then
                    local d = walkIn({ cont = m.cont, wx = m.wx, wy = m.wy, region = m.walled }, o)
                    if d then sec = d / speed end
                end
            end
            row[j] = sec
        end
        D[i] = row
    end
    for _, jmp in ipairs(jumps or {}) do
        local j = jmp.from == "any" and index[jmp.to]
        if j then
            for i = 1, n do if i ~= j and jmp.sec < D[i][j] then D[i][j] = jmp.sec end end
        end
    end
    for k = 1, n do
        local Dk = D[k]
        for i = 1, n do
            local Di = D[i]
            local ik = Di[k]
            if ik < huge then
                for j = 1, n do
                    local s = ik + Dk[j]
                    if s < Di[j] then Di[j] = s end
                end
            end
        end
    end
    return D
end

-- Pure: the few places nearest a spot, by what the walk costs.
--   walk(m) -> yards or nil; -> { { i = index, sec } }, at most `keep`
function T.Nearest(places, walk, speed, keep)
    local out = {}
    for i, m in ipairs(places) do
        local d = walk(m)
        if d then
            local sec, at = d / speed, #out + 1
            while at > 1 and out[at - 1].sec > sec do at = at - 1 end
            if at <= keep then
                table.insert(out, at, { i = i, sec = sec })
                out[keep + 1] = nil
            end
        end
    end
    return out
end

-- Pure: the seconds from spot a to spot b by the places, or nil when there's no such way.
--   fromA: T.Nearest of the flight masters by the walk from a, plus the casts ({ i, sec });
--   toB: T.Nearest of all places by the walk on to b
function T.Through(fromA, toB, D)
    local best
    for _, x in ipairs(fromA) do
        local row = D[x.i]
        for _, y in ipairs(toB) do
            if x.i ~= y.i or x.cast then
                local s = x.sec + row[y.i] + y.sec
                if s < huge and (not best or s < best) then best = s end
            end
        end
    end
    return best
end

-- The planner's answer for one plan (Planner: air): the trip from spot a to
-- spot b by flights and travel spells, as the yards you'd run in that time;
-- nil when you know nothing to travel by. The places are solved once; each
-- spot's nearest places are worked out once.
function T.PlanCost()
    local N = ns.nav
    local places = T.Masters()
    local masters = #places
    local landings, jumps = T.Spells()
    for _, l in ipairs(landings) do places[#places + 1] = l end
    if masters < 2 and #jumps == 0 then return nil end
    local speed = N.TravelSpeed()
    local D = T.Hubs(places, speed, N.FlightSeconds, jumps)
    local index = {}
    for i, m in ipairs(places) do index[m.name] = i end
    local casts = {}
    for _, j in ipairs(jumps) do
        if j.from == "any" and index[j.to] then casts[#casts + 1] = { i = index[j.to], sec = j.sec, cast = true } end
    end
    local from, to = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
    local function spot(pt) return { cont = pt.cont, wx = pt.wx, wy = pt.wy, region = regionOf(pt.map) } end
    return function(a, b)
        if not (a and b and a.wx and b.wx) then return nil end
        local fa = from[a]
        if not fa then
            local s = spot(a)
            fa = T.Nearest(places, function(m) return (not m.landing) and walkIn(s, m) or nil end, speed, T.NEAR)
            for _, c in ipairs(casts) do fa[#fa + 1] = c end
            from[a] = fa
        end
        local tb = to[b]
        if not tb then
            local s = spot(b)
            tb = T.Nearest(places, function(m) return walkOut(m, s) end, speed, T.NEAR)
            to[b] = tb
        end
        local sec = T.Through(fa, tb, D)
        return sec and sec * speed or nil
    end
end

-- /flow transit: the way to your next step, place by place.
function T.Lines()
    local N = ns.nav
    local cur = N and N.current
    local p = N and N:PlayerPos()
    local places = T.Masters()
    local masters = #places
    local landings, jumps = T.Spells()
    local inn, cast, left = T.Hearth()
    local out = { string.format("Flow: travel: %d flight master(s), %d travel spell(s); hearthstone: %s", masters, #landings,
        inn and (tostring(cast.name) .. (left > 0 and string.format(", %s left", N.FormatSeconds(left)) or ", ready")) or ("not counted (" .. tostring(cast) .. ")")) }
    if not (cur and cur.point and p) then out[#out + 1] = "  no next step to travel to"; return out end
    for _, l in ipairs(landings) do places[#places + 1] = l end
    if inn then places[#places + 1] = inn; jumps[#jumps + 1] = cast end
    local speed = N.TravelSpeed()
    out[#out + 1] = string.format("  to your next step: %d yd in a straight line, at %.1f yd a second", cur.d or 0, speed)
    p.region, cur.point.region = regionOf(p.map), regionOf(cur.point.map)
    local total, path = T.Shortest(T.Edges(p, cur.point, places, speed, N.FlightSeconds, cur.d, T.JumpWays(places, jumps)), T.YOU, T.STEP)
    if not total then out[#out + 1] = "  no way found (another continent?)"; return out end
    for _, w in ipairs(path) do
        out[#out + 1] = string.format("  %s: %s -> %s, %s", w.kind, w.a == T.YOU and "you" or tostring(w.a),
            w.b == T.STEP and "the step" or tostring(w.b), N.FormatSeconds(w.sec))
    end
    out[#out + 1] = string.format("  in all %s; on foot %s", N.FormatSeconds(total), N.FormatSeconds((cur.d or 0) / speed))
    local way = T.Now(p, cur.point, cur.d)
    out[#out + 1] = (way and way.kind == "fly" and ("  the arrow: to the flight master at " .. tostring(way.from) .. ", then fly to " .. tostring(way.to)))
        or (way and ("  the arrow's line: quicker: " .. T.Say(way)))
        or "  the arrow: straight to the step (nothing saves enough)"
    return out
end
ns.commands.transit = function() for _, l in ipairs(T.Lines()) do print(l) end end
