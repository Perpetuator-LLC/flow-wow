-- Navigation arrow: points at your next goal (a quest mob, an item source, a
-- turn-in NPC...), with a short sentence and the distance. Left-click for
-- details, right-click to switch to the next goal, shift-drag to move.
--
-- Paths: WoW gives addons no map of walkable ground, so Flow learns it.
-- As you travel, your route is recorded as a network of trail points per
-- continent. When both you and your goal are near known trails, the arrow
-- follows the shortest known trail (A* search) instead of a straight line,
-- so it leads you around hills, rivers and walls the way you've actually
-- walked before. In new places it points straight until it has learned more.
--
-- Goals come from registered providers:
--   ns:Register("navGoal", key, { collect = function() return { goal, ... } end })
--   goal = { key, title, text, details = { lines }, weight = 1,
--            points = { { map = uiMapID, x = 0-1, y = 0-1 }, ... } }

local _, ns = ...
local A = ns.api
local N = {}
ns.nav = N

local SPACING = 15     -- yards between recorded trail points
local SNAP = 8         -- reuse an existing trail point this close
local MAX_EDGE = 45    -- longer jumps are teleports/hearths, not walking
local MAX_NODES = 6000 -- per continent
local CELL = 50        -- spatial grid size (yards)
local ARRIVED = 12     -- yards

local floor, sqrt, atan2 = math.floor, math.sqrt, math.atan2

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end

-------------------------------------------------------------------------------
-- Positions
-------------------------------------------------------------------------------

function N:PlayerPos()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    x, y = A.Safe(x), A.Safe(y)
    if not x or not y then return nil end
    local cont, world = C_Map.GetWorldPosFromMapPos(map, pos)
    if not world then return nil end
    local wx, wy = world:GetXY()
    return { map = map, x = x, y = y, cont = cont, wx = wx, wy = wy }
end

-- World position (yards) of a point on a map.
function N:ToWorld(map, x, y)
    local cont, world = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))
    if not world then return nil end
    local wx, wy = world:GetXY()
    return cont, wx, wy
end

-- East/south unit vectors of a map in world space, so world offsets can be
-- turned into a compass bearing without caring how world axes are oriented.
local axes = {}
local function mapAxes(map)
    local a = axes[map]
    if a ~= nil then return a or nil end
    local _, ox, oy = N:ToWorld(map, 0, 0)
    local _, ex, ey = N:ToWorld(map, 1, 0)
    local _, sx, sy = N:ToWorld(map, 0, 1)
    if not (ox and ex and sx) then axes[map] = false return nil end
    local el, sl = dist(ex, ey, ox, oy), dist(sx, sy, ox, oy)
    if el == 0 or sl == 0 then axes[map] = false return nil end
    a = { ex = (ex - ox) / el, ey = (ey - oy) / el, sx = (sx - ox) / sl, sy = (sy - oy) / sl }
    axes[map] = a
    return a
end

-- Bearing (radians clockwise from north) from the player to a world point.
local function bearing(p, wx, wy)
    local a = mapAxes(p.map)
    if not a then return nil end
    local dx, dy = wx - p.wx, wy - p.wy
    local east = dx * a.ex + dy * a.ey
    local south = dx * a.sx + dy * a.sy
    return atan2(east, -south)
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function compass(b)
    local i = floor(((b % (2 * math.pi)) / (2 * math.pi)) * 8 + 0.5) % 8
    return COMPASS[i + 1]
end

-------------------------------------------------------------------------------
-- Learned trails
-------------------------------------------------------------------------------

local grids = {}  -- runtime spatial index per continent (not saved)

local function graph(cont)
    local all = ns.db.nav.graphs
    local g = all[cont]
    if not g then
        g = { x = {}, y = {}, adj = {} }
        all[cont] = g
    end
    if not grids[cont] then
        local grid = {}
        for i = 1, #g.x do
            local k = floor(g.x[i] / CELL) .. ":" .. floor(g.y[i] / CELL)
            grid[k] = grid[k] or {}
            table.insert(grid[k], i)
        end
        grids[cont] = grid
    end
    return g, grids[cont]
end

local function nearestNode(cont, x, y, radius)
    local g, grid = graph(cont)
    local cx, cy, r = floor(x / CELL), floor(y / CELL), math.ceil(radius / CELL)
    local best, bestD
    for i = cx - r, cx + r do
        for j = cy - r, cy + r do
            for _, n in ipairs(grid[i .. ":" .. j] or {}) do
                local d = dist(x, y, g.x[n], g.y[n])
                if d <= radius and (not bestD or d < bestD) then best, bestD = n, d end
            end
        end
    end
    return best, bestD
end

local function addNode(cont, x, y)
    local g, grid = graph(cont)
    if #g.x >= MAX_NODES then return nil end
    local n = #g.x + 1
    g.x[n], g.y[n] = floor(x * 10) / 10, floor(y * 10) / 10
    local k = floor(x / CELL) .. ":" .. floor(y / CELL)
    grid[k] = grid[k] or {}
    table.insert(grid[k], n)
    return n
end

local function link(g, a, b)
    g.adj[a] = g.adj[a] or {}
    g.adj[b] = g.adj[b] or {}
    for _, v in ipairs(g.adj[a]) do if v == b then return end end
    table.insert(g.adj[a], b)
    table.insert(g.adj[b], a)
end

local lastNode, lastCont
local function record(p)
    if (UnitOnTaxi and UnitOnTaxi("player")) or (IsFlying and IsFlying()) then lastNode = nil return end
    local speed = A.Safe(GetUnitSpeed("player")) or 0
    if speed == 0 then return end
    if lastCont ~= p.cont then lastNode, lastCont = nil, p.cont end
    local g = graph(p.cont)
    if lastNode then
        local d = dist(p.wx, p.wy, g.x[lastNode], g.y[lastNode])
        if d < SPACING then return end
        if d > MAX_EDGE then lastNode = nil end
    end
    local n = nearestNode(p.cont, p.wx, p.wy, SNAP) or addNode(p.cont, p.wx, p.wy)
    if n and lastNode and n ~= lastNode then link(g, lastNode, n) end
    lastNode = n or lastNode
end

-------------------------------------------------------------------------------
-- Shortest known trail (A*)
-------------------------------------------------------------------------------

local function heapPush(h, node, f)
    local i = #h + 1
    h[i] = { node, f }
    while i > 1 do
        local parent = floor(i / 2)
        if h[parent][2] <= h[i][2] then break end
        h[parent], h[i] = h[i], h[parent]
        i = parent
    end
end

local function heapPop(h)
    local top = h[1]
    local last = table.remove(h)
    if #h > 0 then
        h[1] = last
        local i = 1
        while true do
            local l, r, s = i * 2, i * 2 + 1, i
            if h[l] and h[l][2] < h[s][2] then s = l end
            if h[r] and h[r][2] < h[s][2] then s = r end
            if s == i then break end
            h[i], h[s] = h[s], h[i]
            i = s
        end
    end
    return top[1]
end

local function astar(cont, s, t)
    local g = graph(cont)
    local tx, ty = g.x[t], g.y[t]
    local open, gScore, came, closed = {}, { [s] = 0 }, {}, {}
    heapPush(open, s, dist(g.x[s], g.y[s], tx, ty))
    local steps = 0
    while #open > 0 do
        steps = steps + 1
        if steps > 20000 then return nil end
        local cur = heapPop(open)
        if cur == t then
            local path, n, length = { t }, t, 0
            while came[n] do
                length = length + dist(g.x[n], g.y[n], g.x[came[n]], g.y[came[n]])
                n = came[n]
                table.insert(path, 1, n)
            end
            return path, length
        end
        if not closed[cur] then
            closed[cur] = true
            for _, nb in ipairs(g.adj[cur] or {}) do
                local ng = gScore[cur] + dist(g.x[cur], g.y[cur], g.x[nb], g.y[nb])
                if not gScore[nb] or ng < gScore[nb] then
                    gScore[nb] = ng
                    came[nb] = cur
                    heapPush(open, nb, ng + dist(g.x[nb], g.y[nb], tx, ty))
                end
            end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Goals
-------------------------------------------------------------------------------

local goals = {}       -- collected goals
local current          -- chosen goal
local pinnedKey        -- goal chosen with right-click
local route            -- { goalKey, cont, nodes = {...}, idx, length } or nil

local function resolvePoints(goal)
    for _, pt in ipairs(goal.points or {}) do
        if pt.wx == nil and pt.map then
            local cont, wx, wy = N:ToWorld(pt.map, pt.x, pt.y)
            pt.cont, pt.wx, pt.wy = cont, wx, wy
            if not wx then pt.wx = false end
        end
    end
end

-- Nearest point of a goal to the player (same continent only).
local function nearestPoint(goal, p)
    local best, bestD
    for _, pt in ipairs(goal.points or {}) do
        if pt.wx and pt.cont == p.cont then
            local d = dist(p.wx, p.wy, pt.wx, pt.wy)
            if not bestD or d < bestD then best, bestD = pt, d end
        end
    end
    return best, bestD
end

function N:Collect()
    local list = {}
    for key, provider in ns:Each("navGoal") do
        local ok, found = pcall(provider.collect)
        if ok then
            for _, goal in ipairs(found or {}) do
                goal.provider = key
                resolvePoints(goal)
                list[#list + 1] = goal
            end
        elseif ns.db.rotation.debug then
            ns:Print("nav goal " .. key .. ": " .. tostring(found))
        end
    end
    goals = list
    N.planDirty = true
end

function N:Goals() return goals end

-- Shared look for route stops (trip plan, world map pins, map list):
--   label "3 [9]" = 3rd stop, quest level 9; "!2 [8]" = 2nd quest pickup
--   colour: orange = where the arrow points now, blue = quest pickup,
--           sky blue = your waypoint, bluish green = the rest of the route
function N:PlanLabels(plan)
    local out, pickups = {}, 0
    for i, s in ipairs(plan or {}) do
        local isPickup = s.goal.key:find("^pickup:") ~= nil
        if isPickup then pickups = pickups + 1 end
        out[i] = (isPickup and ("!" .. pickups) or tostring(i))
            .. (s.goal.level and string.format(" [%d]", s.goal.level) or "")
    end
    return out
end

function N:StopColor(i, goal)
    local T = ns.theme
    if goal.key == "user:wp" or goal.key:find("^party:") then return T.user end
    if goal.key:find("^pickup:") then return T.changed end
    if i == 1 then return T.arrow end
    return T.current
end

-------------------------------------------------------------------------------
-- Choosing the route. N.selection = { first = goal key, tour = { [key] = true } }
--   first : the stop you picked (from the map, the advice list, or right-click)
--   tour  : stops that must all come before anything else (picking one of the
--           "!" quest pickups puts all pickups first: !3 -> the other pickups
--           -> then the normal plan)
-- Your own waypoint (Waypoint.lua) is always first when set.
-------------------------------------------------------------------------------

N.planVersion = 0

function N:PickupKeys()
    local t, any = {}, false
    for _, g in ipairs(goals) do
        if g.provider == "pickups" then t[g.key] = true; any = true end
    end
    return any and t or nil
end

function N:Select(key)
    -- On a shared party route, choosing edits the shared route instead:
    -- a shared stop moves to the front; anything else is added at the front.
    if key and ns.party and ns.party:Following() then
        local id = key:match("^party:(.+)$")
        if id then
            ns.party:MoveFirst(id)
        else
            for _, g in ipairs(goals) do
                if g.key == key then ns.party:AddGoal(g) break end
            end
        end
        return
    end
    local tour
    if key and key:find("^pickup:") then tour = self:PickupKeys() end
    self.selection = key and { first = key, tour = tour } or nil
    self.planDirty = true
    pinnedKey = nil
end

function N:ClearSelection() self:Select(nil) end

-- The constraints for planning, dropping any that refer to finished goals.
function N:Options(sel)
    sel = sel or self.selection or {}
    local present = {}
    for _, g in ipairs(goals) do present[g.key] = true end
    local first = sel.first and present[sel.first] and sel.first or nil
    local tour
    if sel.tour then
        tour = {}
        for k in pairs(sel.tour) do if present[k] then tour[k] = true end end
        if not next(tour) then tour = nil end
    end
    if present["user:wp"] then first = "user:wp" end
    if not first and not tour and self.selection then self.selection = nil end
    -- Shared party route: its stops come first, in the shared order (their
    -- deps chain), before your own goals.
    if ns.party and ns.party:Following() then
        local partyFirst
        for _, s in ipairs(ns.party:Stops()) do
            local k = "party:" .. s.id
            if present[k] then
                tour = tour or {}
                tour[k] = true
                partyFirst = partyFirst or k
            end
        end
        if partyFirst and first ~= "user:wp" then first = partyFirst end
    end
    return { first = first, tour = tour }
end

-- A plan as if you had picked this stop (for previews on the map / advice list).
function N:PlanFor(key)
    local p = self:PlayerPos()
    if not (p and ns.planner) then return nil end
    local tour = key and key:find("^pickup:") and self:PickupKeys() or nil
    local ok, result = pcall(ns.planner.Plan, ns.planner, p, goals, self:Options({ first = key, tour = tour }))
    return ok and result or nil
end

-- The plan: the whole trip in order (see Planner.lua). Re-planned when goals
-- change, and every few seconds as you move.
local plan, planAt = nil, 0
local function choose(p)
    local ranked = {}
    for _, goal in ipairs(goals) do
        local pt, d = nearestPoint(goal, p)
        if pt then ranked[#ranked + 1] = { goal = goal, point = pt, d = d, score = d * (goal.weight or 1) } end
    end
    table.sort(ranked, function(a, b) return a.score < b.score end)
    N.ranked = ranked
    if #ranked == 0 then N.plan = nil return nil end
    if pinnedKey then
        for _, r in ipairs(ranked) do if r.goal.key == pinnedKey then return r end end
        pinnedKey = nil
    end

    local now = GetTime()
    if ns.planner and (N.planDirty or not plan or now - planAt > 8) then
        local ok, result = pcall(ns.planner.Plan, ns.planner, p, goals, N:Options())
        plan = ok and result or nil
        if not ok then N.lastError = "planner: " .. tostring(result) end
        planAt, N.planDirty = now, false
        N.planVersion = N.planVersion + 1
    end
    N.plan = plan
    if plan and plan[1] then
        local s = plan[1]
        return { goal = s.goal, point = s.point, d = dist(p.wx, p.wy, s.point.wx, s.point.wy) }
    end
    -- Sticky: don't flip between goals unless the new one is clearly closer.
    if current then
        for _, r in ipairs(ranked) do
            if r.goal.key == current.goal.key then
                if ranked[1].score < r.score * 0.7 then return ranked[1] end
                return r
            end
        end
    end
    return ranked[1]
end

-- Decide where the arrow points: a trail point along a known path, or the
-- goal itself. Returns wx, wy, how ("path"/"direct"), routeLength.
local lastRouteAt = 0
local function steer(p, choice)
    local pt = choice.point
    local direct = choice.d
    if direct < 80 then route = nil return pt.wx, pt.wy, "direct", direct end

    local now = GetTime()
    local stale = not route or route.goalKey ~= choice.goal.key or route.cont ~= p.cont
    if route and not stale then
        local g = graph(p.cont)
        local w = route.nodes[route.idx]
        -- Off the path? Re-plan (at most every 3s).
        if w and dist(p.wx, p.wy, g.x[w], g.y[w]) > 60 and now - lastRouteAt > 3 then stale = true end
    end
    if stale and now - lastRouteAt > 1 then
        lastRouteAt = now
        route = nil
        local s = nearestNode(p.cont, p.wx, p.wy, 40)
        local t, td = nearestNode(p.cont, pt.wx, pt.wy, 80)
        if s and t and s ~= t then
            local nodes, length = astar(p.cont, s, t)
            if nodes and length + (td or 0) < direct * 4 then
                route = { goalKey = choice.goal.key, cont = p.cont, nodes = nodes, idx = 1,
                          length = length + (td or 0) }
            end
        end
    end
    if not route then return pt.wx, pt.wy, "direct", direct end

    local g = graph(p.cont)
    -- Advance along the path; also jump ahead if a later point is already closer.
    local bestIdx, bestD = route.idx, nil
    for i = route.idx, math.min(#route.nodes, route.idx + 6) do
        local n = route.nodes[i]
        local d = dist(p.wx, p.wy, g.x[n], g.y[n])
        if not bestD or d < bestD then bestIdx, bestD = i, d end
    end
    route.idx = bestIdx
    local n = route.nodes[route.idx]
    while n and dist(p.wx, p.wy, g.x[n], g.y[n]) < ARRIVED and route.idx < #route.nodes do
        route.idx = route.idx + 1
        n = route.nodes[route.idx]
    end
    if route.idx >= #route.nodes and dist(p.wx, p.wy, g.x[n], g.y[n]) < ARRIVED then
        return pt.wx, pt.wy, "direct", direct   -- end of known trail: head straight in
    end
    return g.x[n], g.y[n], "path", route.length
end

-------------------------------------------------------------------------------
-- Arrow UI
-------------------------------------------------------------------------------

local frame, panel

local function buildPanel()
    local f = CreateFrame("Frame", "FlowNavPanel", UIParent)
    f:SetSize(300, 140)
    f:SetFrameStrata("DIALOG")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.8)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", 10, -10)
    f.text:SetPoint("BOTTOMRIGHT", -10, 10)
    f.text:SetJustifyH("LEFT")
    f.text:SetJustifyV("TOP")
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", function(self) self:Hide() end)
    f:Hide()
    return f
end

local function showPanel()
    if not current then return end
    panel = panel or buildPanel()
    local g = current.goal
    local lines = { "|cffffd200" .. (g.title or g.text or "Next goal") .. "|r" }
    for _, l in ipairs(g.details or {}) do lines[#lines + 1] = l end
    lines[#lines + 1] = " "
    lines[#lines + 1] = string.format("%d yd away (%s)", current.d, N.how == "path"
        and "following a trail you've walked before" or "straight line: no known trail yet")
    -- The whole trip, in the order Flow plans to do it.
    if N.plan and #N.plan > 1 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = string.format("|cffffd200Trip plan|r (%d stops, about %d yd):",
            #N.plan, N.plan[#N.plan].cum or 0)
        local labels = N:PlanLabels(N.plan)
        for i, s in ipairs(N.plan) do
            if i > 10 then lines[#lines + 1] = "  ..."; break end
            local hex = N:StopColor(i, s.goal).hex
            lines[#lines + 1] = string.format("  |cff%s%s|r %s |cff888888(+%d yd)|r",
                hex, labels[i], s.goal.text or s.goal.title or "?", s.leg or 0)
        end
        if N.plan.dropped and #N.plan.dropped > 0 then
            lines[#lines + 1] = "|cff888888Skipped as too far out of the way: " .. table.concat(N.plan.dropped, ", ") .. "|r"
        end
        lines[#lines + 1] = "Right-click the arrow to skip ahead to the next stop."
    end
    lines[#lines + 1] = "|cff888888Click this panel to close.|r"
    panel.text:SetText(table.concat(lines, "\n"))
    panel:SetHeight(math.max(80, panel.text:GetStringHeight() + 24))
    panel:ClearAllPoints()
    panel:SetPoint("TOP", frame, "BOTTOM", 0, -24)
    panel:Show()
end

local function buildArrow()
    local f = CreateFrame("Button", "FlowNavArrow", UIParent)
    f:SetSize(56, 56)
    f:SetFrameStrata("HIGH")
    local p = ns.db.nav.point
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end
    f.arrow = f:CreateTexture(nil, "ARTWORK")
    f.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.arrow:SetSize(48, 48)
    f.arrow:SetPoint("CENTER")
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOP", f.text, "BOTTOM", 0, -2)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, r, x, y = self:GetPoint()
        ns.db.nav.point = { a, r, x, y }
    end)
    f:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            -- Skip ahead to the next stop of the plan (or the next-nearest goal).
            local ranked = N.plan or N.ranked or {}
            if #ranked > 1 and current then
                for i, r in ipairs(ranked) do
                    if r.goal.key == current.goal.key then
                        N:Select(ranked[(i % #ranked) + 1].goal.key)
                        break
                    end
                end
            end
        elseif panel and panel:IsShown() then
            panel:Hide()
        else
            showPanel()
        end
    end)
    f:Hide()
    return f
end

local function update()
    local cfg = ns.db.nav
    if not cfg.enabled then frame:Hide() return end
    local p = N:PlayerPos()
    if not p then frame:Hide() return end
    if cfg.learn then record(p) end

    local choice = choose(p)
    current = choice
    if not choice then
        if #goals == 0 and not ns.quests:Source() then
            frame.text:SetText("No directions yet")
            frame.sub:SetText("Install Questie + QuestieDB for quest locations")
            frame.arrow:Hide()
            frame:Show()
        else
            frame:Hide()
        end
        return
    end

    local wx, wy, how, length = steer(p, choice)
    N.how = how
    local b = bearing(p, wx, wy)
    local facing = A.Safe(GetPlayerFacing and GetPlayerFacing())
    if b and facing then
        frame.arrow:SetRotation(-(b + facing))
        frame.arrow:Show()
    else
        frame.arrow:Hide()
    end

    local g = choice.goal
    -- Your own waypoint clears itself when you get there.
    if g.key == "user:wp" and choice.d < 10 and ns.waypoint then
        ns.waypoint:Clear()
        ns:Print("arrived at your waypoint")
    end
    -- Reaching a shared stop clears it for the whole party.
    local partyId = g.key:match("^party:(.+)$")
    if partyId and choice.d < 15 and ns.party then
        ns.party:Done(partyId)
        ns:Print("reached a shared stop: " .. (g.title or "?"))
    end
    frame.text:SetText(g.text or g.title or "Next goal")
    if choice.d < ARRIVED * 2 then
        frame.sub:SetText("You're here")
        frame.arrow:SetVertexColor(0.3, 1, 0.3)
    else
        frame.sub:SetText(string.format("%d yd%s%s", choice.d,
            (not facing and b) and (" " .. compass(b)) or "",
            how == "path" and string.format(" (trail, %d yd walk)", length) or ""))
        local c = ns.theme.arrow
        frame.arrow:SetVertexColor(c[1], c[2], c[3])
    end
    frame:Show()
    if panel and panel:IsShown() then showPanel() end
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------

local pendingCollect = false
local function scheduleCollect()
    if pendingCollect then return end
    pendingCollect = true
    C_Timer.After(1, function()
        pendingCollect = false
        pcall(N.Collect, N)
    end)
end

ns:OnLoad(function(saved)
    saved.nav = saved.nav or {}
    saved.nav.graphs = saved.nav.graphs or {}
    if saved.nav.enabled == nil then saved.nav.enabled = true end
    if saved.nav.learn == nil then saved.nav.learn = true end
    frame = buildArrow()
    local acc, collectAcc = 0, 0
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc, collectAcc = acc + dt, collectAcc + dt
        if collectAcc > 10 then collectAcc = 0; scheduleCollect() end
        if acc < 0.1 then return end
        acc = 0
        local ok, err = pcall(update)
        if not ok then
            N.lastError = err
            if ns.db.rotation.debug then ns:Print("nav: " .. tostring(err)) end
        end
    end)
end)

for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED",
                      "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP",
                      "SKILL_LINES_CHANGED", "TRAINER_CLOSED", "LEARNED_SPELL_IN_TAB" }) do
    ns:On(ev, scheduleCollect)
end

ns.commands.nav = function(arg)
    arg = (arg or ""):lower()
    local cfg = ns.db.nav
    if arg == "on" or arg == "off" then
        cfg.enabled = (arg == "on")
        ns:Print("navigation arrow " .. arg)
    elseif arg == "learn" then
        cfg.learn = not cfg.learn
        ns:Print("trail learning " .. (cfg.learn and "on" or "off"))
    elseif arg == "forget" then
        wipe(cfg.graphs); wipe(grids); route = nil; lastNode = nil
        ns:Print("forgot all learned trails")
    else
        local nodes = 0
        for _, g in pairs(cfg.graphs) do nodes = nodes + #g.x end
        ns:Print(string.format("%d goals, %d learned trail points. Last error: %s",
            #goals, nodes, tostring(N.lastError or "none")))
        print("  /flow nav on|off|learn|forget. Shift-drag the arrow to move it.")
    end
end
