-- From group to group in a quest's area.
--
-- "When I'm doing a farming quest, it would be super valuable if it just
-- guided me from one fuzzy area to the next. It has me go to one and then it
-- just stops and I don't know what to do next. There are three quests on the
-- map, spread all over it: if you have me hop from group to group, whatever's
-- closest, I hit all these things on the way." (0.35.325)
--
-- A kill or collect step has many spots where its things can be. The arrow
-- took you to the nearest and became a ring ("You're in the area"), and that
-- was all. Now the spots of every such step near the front of your route are
-- gathered into groups (spots within a stone's throw of each other), and:
--   * in a group: the ring, as before, and the line says how far the next
--     group is;
--   * when a group is worked (you walked out of it, or stood in it a while
--     with no fight and nothing looted): the arrow points to the nearest
--     group you haven't just worked, whichever of those steps it belongs to,
--     and the line names it: "Next group: 140 yd (Deviate Hides)";
--   * a worked group rests for a few minutes (things come back), then counts
--     again.
-- It starts when you first reach a group; until then the arrow leads you
-- there the usual way (trails, gates, flights). It ends when no group is
-- near. Herb and ore steps have their own spot-to-spot rule (Nav.lua).
-- Flow can't see what's alive: groups are where things can be, so a group may
-- be empty when you get there. Standing in it a moment sends you on.
-- Off: Flow Settings, Finding your way.

local _, ns = ...
local N = ns.nav
if not N then return end
local H = {}
ns.areaHop = H

H.GROUP = 60        -- yards: spots this close to a group's middle are one group
H.INSIDE = 45       -- yards from any of its spots: you're in the group (Nav.lua's AREA)
H.RANGE = 700       -- yards: groups further than this aren't offered
H.AHEAD = 12        -- steps of the route looked at
H.STAY = 20         -- seconds in a group with no fight and no loot: worked
H.REST = 300        -- seconds a worked group is left alone
H.MAX_SPOTS = 600   -- spots looked at (a step can have hundreds)

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function H.On() return not (ns.db and ns.db.nav and ns.db.nav.areaHop == false) end

-- Pure: gathers spots into groups. steps: { { key, title, points = { { wx, wy, cont } } } }
--   -> { { id, key, title, x, y, cont, spots = { { wx, wy } } } }
function H.Groups(steps, cont, maxSpots, groupYards)
    local out, seen = {}, 0
    for _, s in ipairs(steps or {}) do
        local mine = {}
        for _, pt in ipairs(s.points or {}) do
            if pt.wx and pt.wy and (cont == nil or pt.cont == cont) then
                seen = seen + 1
                if seen > (maxSpots or H.MAX_SPOTS) then break end
                local home
                for _, g in ipairs(mine) do
                    if dist(pt.wx, pt.wy, g.x, g.y) <= (groupYards or H.GROUP) then home = g break end
                end
                if not home then
                    home = { key = s.key, title = s.title, x = pt.wx, y = pt.wy, cont = pt.cont, spots = {} }
                    mine[#mine + 1] = home
                end
                local n = #home.spots
                home.x, home.y = (home.x * n + pt.wx) / (n + 1), (home.y * n + pt.wy) / (n + 1)
                home.spots[n + 1] = { wx = pt.wx, wy = pt.wy }
            end
        end
        for _, g in ipairs(mine) do
            g.id = string.format("%s@%d:%d", tostring(s.key), math.floor(g.x / 20), math.floor(g.y / 20))
            out[#out + 1] = g
        end
    end
    return out
end

-- Pure: yards from a place to a group: to its nearest spot.
function H.YardsTo(group, x, y)
    local best
    for _, sp in ipairs(group.spots or {}) do
        local d = dist(x, y, sp.wx, sp.wy)
        if not best or d < best then best = d end
    end
    return best or dist(x, y, group.x, group.y)
end

-- Pure: the group you're standing in (the nearest within `inside` yards), or nil.
function H.Inside(groups, x, y, inside)
    local best, bestD
    for _, g in ipairs(groups or {}) do
        local d = H.YardsTo(g, x, y)
        if d <= (inside or H.INSIDE) and (not bestD or d < bestD) then best, bestD = g, d end
    end
    return best
end

-- Pure: is the group resting? worked: { [id] = time }.
function H.Resting(worked, id, now, rest)
    local at = worked and worked[id]
    return at ~= nil and (now - at) < (rest or H.REST)
end

-- Pure: the nearest group to go to: not the one you're in, not resting,
-- within range. -> group, yards
function H.Next(groups, x, y, worked, now, skip, range, rest)
    local best, bestD
    for _, g in ipairs(groups or {}) do
        if g ~= skip and not H.Resting(worked, g.id, now, rest) then
            local d = dist(x, y, g.x, g.y)
            if d <= (range or H.RANGE) and (not bestD or d < bestD) then best, bestD = g, d end
        end
    end
    return best, bestD
end

-- Pure: the next group by the route's own plan (0.35.329): the planner now
-- orders a step's groups among the other steps (plan.hops), so the arrow
-- follows that order, not just "whatever is nearest".
--   hops: { { key, wx, wy } } in planned order -> group, yards (nil: none fits)
function H.Planned(groups, hops, x, y, worked, now, skip, rest)
    for _, hop in ipairs(hops or {}) do
        local best, bestD
        for _, g in ipairs(groups or {}) do
            if g.key == hop.key then
                local d = dist(g.x, g.y, hop.wx, hop.wy)
                if d <= H.GROUP * 1.5 and (not bestD or d < bestD) then best, bestD = g, d end
            end
        end
        if best and best ~= skip and not H.Resting(worked, best.id, now, rest) then
            return best, dist(x, y, best.x, best.y)
        end
    end
    return nil
end

-- Pure: the arrow's second line.
--   state "in": inTitle (nil: the step you're on), nextYards (nil: none near)
--   state "go": yards, title (nil: the step you're on)
function H.Text(state, title, yards, nextYards)
    if state == "go" then
        return string.format("Next group: %d yd%s", math.floor((yards or 0) + 0.5), title and (" (" .. title .. ")") or "")
    end
    local head = title and ("In the area: " .. title) or "You're in the area"
    if nextYards then return string.format("%s. Next group: %d yd", head, math.floor(nextYards + 0.5)) end
    return head
end

-------------------------------------------------------------------------------
-- Now
-------------------------------------------------------------------------------
H.worked = {}
local groups, groupsAt, groupsSig = {}, 0, nil
local inId, inSince, started = nil, nil, false

-- The kill and collect steps near the front of your route.
local function areaSteps()
    local steps, parts = {}, {}
    for i, e in ipairs(N.plan or {}) do
        if i > H.AHEAD then break end
        local g = e.goal
        if g and g.area and g.points and not (N.GatherSpots and N.GatherSpots(g)) then
            steps[#steps + 1] = { key = g.key, title = g.title or g.text, points = g.points }
            parts[#parts + 1] = tostring(g.key) .. ":" .. #g.points
        end
    end
    return steps, table.concat(parts, "|")
end

local function refreshGroups(p, now)
    local steps, sig = areaSteps()
    if sig == groupsSig and now - groupsAt < 30 then return groups end
    groupsSig, groupsAt = sig, now
    groups = H.Groups(steps, p.cont)
    return groups
end

local function titleFor(group, currentKey)
    if not group or group.key == currentKey then return nil end
    if not group.title then return nil end
    return (tostring(group.title):gsub("^%s+", ""))
end

-- Once a second: where you are among the groups, and what the arrow should say.
function H.Tick()
    H.cur = nil
    if not H.On() then started = false return end
    local cur = N.current
    local goal = cur and cur.goal
    if not (goal and goal.area) or cur.waypoint or cur.follow or (N.GatherSpots and N.GatherSpots(goal))
        or (UnitOnTaxi and UnitOnTaxi("player")) or UnitIsDeadOrGhost("player") then
        inId, inSince = nil, nil
        return
    end
    local p = N:PlayerPos()
    if not (p and p.wx) then return end
    local now = GetTime()
    local list = refreshGroups(p, now)
    if #list == 0 then started = false return end
    local here = H.Inside(list, p.wx, p.wy)
    -- Leaving a group, or standing in it with nothing to do: it's worked.
    if here and here.id == inId then
        if InCombatLockdown() then inSince = now end
        if now - (inSince or now) >= H.STAY then H.worked[here.id] = now end
    elseif inId and not (here and here.id == inId) then
        H.worked[inId] = H.worked[inId] or now
    end
    if here then
        if here.id ~= inId then inId, inSince = here.id, now end
        started = true
    else
        inId, inSince = nil, nil
    end
    if not started then return end
    local resting = here and H.Resting(H.worked, here.id, now)
    -- The route's own order of groups first; the nearest when it has none.
    local nextG, nextD = H.Planned(list, N.plan and N.plan.hops, p.wx, p.wy, H.worked, now, here)
    if not nextG then nextG, nextD = H.Next(list, p.wx, p.wy, H.worked, now, here) end
    if here and not resting then
        H.cur = { state = "in", key = goal.key, group = here,
                  text = H.Text("in", titleFor(here, goal.key), nil, nextD) }
    elseif nextG then
        H.cur = { state = "go", key = goal.key, group = nextG, wx = nextG.x, wy = nextG.y, d = math.floor(nextD + 0.5),
                  text = H.Text("go", titleFor(nextG, goal.key), nextD) }
    elseif not here then
        started = false   -- nothing near to hop to: the arrow leads the usual way again
    end
end

-- For the arrow (Nav.lua, every update): what to do now, or nil for the usual.
function N.Hop(_, choice)
    local cur = H.cur
    if not cur or not choice or not choice.goal or choice.goal.key ~= cur.key then return nil end
    return cur
end

-- Something looted or a fight: you're busy here, the group isn't done.
ns:On("LOOT_OPENED", function() if inId then inSince = GetTime() end end)
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1, function() pcall(H.Tick) end)
end

function H.Lines()
    local out = { string.format("area hop: %s; started: %s; groups known: %d; in: %s", H.On() and "on" or "off", tostring(started), #groups, tostring(inId)) }
    local now = GetTime()
    local p = N:PlayerPos()
    for i, g in ipairs(groups) do
        if i > 12 then out[#out + 1] = string.format("  ... and %d more", #groups - 12) break end
        out[#out + 1] = string.format("  %s: %d spot(s), %s yd%s", tostring(g.title or g.key), #g.spots,
            p and p.wx and tostring(math.floor(dist(p.wx, p.wy, g.x, g.y))) or "?", H.Resting(H.worked, g.id, now) and ", resting" or "")
    end
    if H.cur then out[#out + 1] = "  the arrow: " .. tostring(H.cur.text) end
    return out
end
ns.commands.hop = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.nav.areaHop = (arg == "on")
        ns:Print("leading you from group to group in a quest's area: " .. arg)
        return
    end
    for i, l in ipairs(H.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "route",
        label = "Lead me from group to group in a quest's area",
        note = "(kill and collect steps)",
        tip = "In a kill or collect step's area the arrow is a ring. When you walk out of a group of its spots, or stand in one a while with no fight "
            .. "and nothing looted, the arrow points to the nearest group you haven't just worked, of any such step near the front of your route. "
            .. "Off: the ring, and nothing more.",
        get = function() return H.On() end,
        set = function(on) ns.db.nav.areaHop = on and true or false end,
    })
end
