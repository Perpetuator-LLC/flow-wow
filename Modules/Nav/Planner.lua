-- Trip planner: orders ALL your nearby goals into one trip instead of just
-- chasing the nearest one. It answers questions like "turn in the bandanas
-- first, or go to the trainers first?" and "grab that quest before heading
-- out so I don't have to come back".
--
-- Stops: every goal with a location on your continent (quest objectives,
-- turn-ins, quests to pick up, trainers, gathering/fishing). Rules:
--   * a quest's turn-in comes after that quest's objectives (goal.deps)
--   * optional stops (goal.optional) stay only if they cost less than
--     OPTIONAL_DETOUR extra yards, i.e. they're roughly on the way
--   * a stop with many possible spots (mob spawns) uses whichever spot is
--     closest to where you'll be at that point in the trip
-- Method: greedy nearest-first, then improved by moving single stops and
-- reversing segments while the trip gets shorter (and still obeys the rules).
-- Distances are straight lines; the arrow then follows learned trails.

local _, ns = ...
local P = {}
ns.planner = P

local MAX_STOPS = 30          -- nearest goals considered per plan
-- Only the first stops get the slow polish (improve() costs ~n^3); the rest
-- of the trip is nearest-next from there. It's planned again as you go, so
-- the far end gets polished by the time you reach it. 14 = what the whole
-- plan used to be, so a plan costs no more than before (/flow perf).
local IMPROVE_HEAD = 14
local MAX_POINTS = 25         -- spots per stop considered (nearest to you)
local OPTIONAL_DETOUR = 250   -- yards an optional stop may add
local MAX_PASSES = 6

local sqrt = math.sqrt
local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end

-- Options for the plan being built (set by P:Plan):
--   first = goal key that must be the first stop (your choice)
--   tour  = { [key] = true } stops that must all come before anything else
--           (e.g. "pick up all these quests first")
local OPT = {}

local function forced(key) return OPT.first == key or (OPT.tour and OPT.tour[key]) end

local function candidates(p, goals)
    local stops = {}
    for _, g in ipairs(goals) do
        local pts = {}
        for _, pt in ipairs(g.points or {}) do
            if pt.wx and pt.cont == p.cont then
                pts[#pts + 1] = { pt = pt, d = dist(p.wx, p.wy, pt.wx, pt.wy) }
            end
        end
        if #pts > 0 then
            table.sort(pts, function(a, b) return a.d < b.d end)
            local keep = {}
            for i = 1, math.min(MAX_POINTS, #pts) do keep[i] = pts[i].pt end
            stops[#stops + 1] = { goal = g, key = g.key, points = keep, near = pts[1].d }
        end
    end
    -- Chosen stops always make the cut, then milestones (class training: it
    -- changes every fight after it), then the rest by (weighted) nearness.
    -- A milestone is never dropped as "too far", but it doesn't jump the
    -- queue either: its weight puts it where it costs the least detour.
    table.sort(stops, function(a, b)
        local fa, fb = forced(a.key) and 2 or (a.goal.milestone and 1 or 0), forced(b.key) and 2 or (b.goal.milestone and 1 or 0)
        if fa ~= fb then return fa > fb end
        return a.near * (a.goal.weight or 1) < b.near * (b.goal.weight or 1)
    end)

    local kept, keptKeys, allKeys = {}, {}, {}
    for _, s in ipairs(stops) do allKeys[s.key] = true end
    for i = 1, #stops do
        if i <= MAX_STOPS or forced(stops[i].key) then
            kept[#kept + 1] = stops[i]; keptKeys[stops[i].key] = true
        end
    end
    -- Turn-ins follow their quest: when every objective of a quest made the
    -- cut, its turn-in comes too, even past MAX_STOPS (a few extra at most),
    -- so the route finishes what it starts instead of stopping at the last
    -- objective.
    local extra = 0
    for i = 1, #stops do
        local s = stops[i]
        local deps = s.goal.deps
        if not keptKeys[s.key] and deps and #deps > 0 and extra < 8 then
            local all = true
            for _, dep in ipairs(deps) do
                if allKeys[dep] and not keptKeys[dep] then all = false end
            end
            if all then kept[#kept + 1] = s; keptKeys[s.key] = true; extra = extra + 1 end
        end
    end
    -- A turn-in whose objectives didn't make the cut would be planned too
    -- early; leave it out until they're in range.
    local out = {}
    for _, s in ipairs(kept) do
        local ok = true
        for _, dep in ipairs(s.goal.deps or {}) do
            if allKeys[dep] and not keptKeys[dep] then ok = false end
        end
        if ok then out[#out + 1] = s end
    end
    return out
end

-- Walks an order from your position. Returns weighted cost, legs, points.
local function walk(p, order)
    local x, y, total = p.wx, p.wy, 0
    local legs, pts = {}, {}
    for i, s in ipairs(order) do
        local best, bd
        for _, pt in ipairs(s.points) do
            local d = dist(x, y, pt.wx, pt.wy)
            if not bd or d < bd then best, bd = pt, d end
        end
        legs[i], pts[i] = bd, best
        total = total + bd * (s.goal.weight or 1)
        x, y = best.wx, best.wy
    end
    return total, legs, pts
end

local function valid(order)
    local pos = {}
    for i, s in ipairs(order) do pos[s.key] = i end
    if OPT.first and pos[OPT.first] and pos[OPT.first] ~= 1 then return false end
    local lastTour, firstOther = 0, math.huge
    for i, s in ipairs(order) do
        for _, dep in ipairs(s.goal.deps or {}) do
            if pos[dep] and pos[dep] > i then return false end
        end
        if OPT.tour then
            if OPT.tour[s.key] or s.key == OPT.first then lastTour = i
            elseif i < firstOther then firstOther = i end
        end
    end
    return lastTour < firstOther
end

local function greedy(p, stops)
    local remaining, order = {}, {}
    for _, s in ipairs(stops) do remaining[#remaining + 1] = s end
    local x, y = p.wx, p.wy
    while #remaining > 0 do
        local left, tourLeft, firstLeft = {}, false, false
        for _, s in ipairs(remaining) do
            left[s.key] = true
            if OPT.tour and OPT.tour[s.key] then tourLeft = true end
            if s.key == OPT.first then firstLeft = true end
        end
        local bestI, bestScore
        for i, s in ipairs(remaining) do
            local ready = true
            for _, dep in ipairs(s.goal.deps or {}) do if left[dep] then ready = false end end
            -- Your chosen stop first, then the rest of the tour, then the others.
            if firstLeft and s.key ~= OPT.first then ready = false end
            if tourLeft and not (OPT.tour[s.key] or s.key == OPT.first) then ready = false end
            if ready then
                local bd
                for _, pt in ipairs(s.points) do
                    local d = dist(x, y, pt.wx, pt.wy)
                    if not bd or d < bd then bd = d end
                end
                local score = bd * (s.goal.weight or 1)
                if not bestScore or score < bestScore then bestI, bestScore = i, score end
            end
        end
        if not bestI then bestI = 1 end  -- broken deps: don't loop forever
        local s = table.remove(remaining, bestI)
        order[#order + 1] = s
        local _, _, pts = walk({ wx = x, wy = y }, { s })
        x, y = pts[1].wx, pts[1].wy
    end
    return order
end

local function copy(t) local c = {} for i, v in ipairs(t) do c[i] = v end return c end

local function improve(p, order)
    local best = walk(p, order)
    for _ = 1, MAX_PASSES do
        local improved = false
        local n = #order
        -- Move one stop elsewhere.
        for i = 1, n do
            for j = 1, n do
                if i ~= j then
                    local o = copy(order)
                    local s = table.remove(o, i)
                    table.insert(o, j, s)
                    if valid(o) then
                        local c = walk(p, o)
                        if c < best - 1 then order, best, improved = o, c, true end
                    end
                end
            end
        end
        -- Reverse a segment.
        for i = 1, n - 1 do
            for j = i + 1, n do
                local o = copy(order)
                for k = 0, math.floor((j - i) / 2) do o[i + k], o[j - k] = o[j - k], o[i + k] end
                if valid(o) then
                    local c = walk(p, o)
                    if c < best - 1 then order, best, improved = o, c, true end
                end
            end
        end
        if not improved then break end
    end
    return order
end

-- Drop optional stops that add more than OPTIONAL_DETOUR yards.
local function prune(p, order)
    local dropped = {}
    local i = 1
    while i <= #order do
        local s = order[i]
        if s.goal.optional and not forced(s.key) then
            local o = copy(order)
            table.remove(o, i)
            local _, withLegs = walk(p, order)
            local _, withoutLegs = walk(p, o)
            local with, without = 0, 0
            for _, l in ipairs(withLegs) do with = with + l end
            for _, l in ipairs(withoutLegs) do without = without + l end
            if with - without > OPTIONAL_DETOUR and valid(o) then
                dropped[#dropped + 1] = s.goal.text or s.goal.title or s.key
                order = o
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    return order, dropped
end

-- Returns the trip: { { goal, point, leg, cum }, ..., dropped = { text } }
function P:Plan(p, goals, opts)
    OPT = opts or {}
    local stops = candidates(p, goals)
    if #stops == 0 then return nil end
    local order = greedy(p, stops)
    if #order > IMPROVE_HEAD then
        -- Polish the near part, then carry on nearest-next from its last stop.
        local head, rest = {}, {}
        for i, s in ipairs(order) do
            if i <= IMPROVE_HEAD then head[#head + 1] = s else rest[#rest + 1] = s end
        end
        head = improve(p, head)
        local _, _, pts = walk(p, head)
        local last = pts[#pts]
        order = head
        for _, s in ipairs(greedy({ wx = last.wx, wy = last.wy }, rest)) do order[#order + 1] = s end
    else
        order = improve(p, order)
    end
    local dropped
    order, dropped = prune(p, order)
    local _, legs, pts = walk(p, order)
    local plan, cum = { dropped = dropped }, 0
    for i, s in ipairs(order) do
        cum = cum + legs[i]
        plan[i] = { goal = s.goal, point = pts[i], leg = legs[i], cum = cum }
    end
    return plan
end

-- Timed for /flow perf.
P.Plan = ns.perf.Wrap("route: order stops", P.Plan)
