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

-- East / south offset in yards from the player to a world point (minimap pin).
function N:Offset(p, wx, wy)
    local a = mapAxes(p.map)
    if not a then return nil end
    local dx, dy = wx - p.wx, wy - p.wy
    return dx * a.ex + dy * a.ey, dx * a.sx + dy * a.sy
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

function N:Coin(c)
    return GetCoinTextureString and GetCoinTextureString(c or 0) or ((c or 0) .. "c")
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
    -- Blocked stops stay off the route but are listed (with a lock and the
    -- reason) on the map list and the tracker:
    --   goal.blockedBy = "needs Mining"     set by the goal's provider
    --   goal.cost = copper                  blocked while you have less money
    -- Money-blocked stops are remembered in ns.db.nav.deferred. When your
    -- money reaches the cost (PLAYER_MONEY below) they come back and are
    -- planned like any other stop: by distance and weight, so a trainer you're
    -- standing near (say, after a hearth) goes to the top by itself.
    local money = GetMoney and GetMoney() or 0
    local deferred = ns.db.nav.deferred or {}
    ns.db.nav.deferred = deferred
    local present, kept, blockedGoals = {}, {}, {}
    for _, g in ipairs(list) do
        present[g.key] = true
        if g.cost and g.cost > money then
            if not deferred[g.key] then
                ns:Print(string.format("skipping %s for now: it costs %s and you have %s. It comes back on the route once you can pay.",
                    g.title or g.text or g.key, N:Coin(g.cost), N:Coin(money)))
            end
            deferred[g.key] = { text = g.title or g.text, cost = g.cost, since = deferred[g.key] and deferred[g.key].since or time() }
            g.blockedBy = string.format("needs %s (you have %s)", N:Coin(g.cost), N:Coin(money))
            g.blockIcon = "Interface\MoneyFrame\UI-GoldIcon"
        elseif deferred[g.key] then
            ns:Print((g.title or g.text or g.key) .. ": you have the money now, back on the route.")
            deferred[g.key] = nil
            g.details = g.details or {}
            table.insert(g.details, 1, "Skipped earlier for lack of money; you can afford it now.")
        end
        if g.blockedBy then blockedGoals[#blockedGoals + 1] = g else kept[#kept + 1] = g end
    end
    -- Gone altogether (trained elsewhere, no longer needed): forget it.
    for key in pairs(deferred) do if not present[key] then deferred[key] = nil end end
    N.blockedGoals = blockedGoals
    N.deferredGoals = blockedGoals  -- older name
    list = kept
    -- Route mode: "quests" = only quests already in your log (their objectives
    -- and turn-ins), plus your waypoint and the party route; "optimal" (default)
    -- = everything worth doing: pickups, trainers, fishing/gathering too.
    if N:Mode() == "quests" then
        local kept = {}
        for _, g in ipairs(list) do
            if g.key:find("^%d+:") or g.key == "user:wp" or g.key:find("^party:") then
                kept[#kept + 1] = g
            end
        end
        list = kept
    end
    -- Stops you hid (right-click on the map) stay out of the route; they're
    -- kept in N.hiddenGoals so the map panel can list and unhide them.
    local hidden = ns.db.nav.hidden or {}
    local shown, hiddenGoals = {}, {}
    for _, g in ipairs(list) do
        if hidden[g.key] then hiddenGoals[#hiddenGoals + 1] = g else shown[#shown + 1] = g end
    end
    N.hiddenGoals = hiddenGoals
    -- XP-first sorting (XpValue.lua): weights by XP and quest level; also adds XP to tooltips.
    if ns.xpValue then pcall(ns.xpValue.Apply, ns.xpValue, shown) end
    goals = shown
    N.planDirty = true
end

function N:Hide(key)
    if not key then return end
    ns.db.nav.hidden = ns.db.nav.hidden or {}
    ns.db.nav.hidden[key] = true
    self:Collect()
end

function N:Unhide(key)
    if ns.db.nav.hidden then ns.db.nav.hidden[key] = nil end
    self:Collect()
end

function N:Mode() return (ns.db.nav and ns.db.nav.mode) or "optimal" end

function N:SetMode(mode)
    ns.db.nav.mode = (mode == "quests") and "quests" or "optimal"
    self:Collect()
end

function N:Goals() return goals end

-------------------------------------------------------------------------------
-- HUD arrow: a chevron drawn from thin lines with a soft glow, a centre
-- spine, and a faint ring of dots with one bright dot in the direction of
-- travel. Lines can point anywhere, so the arrow is redrawn rotated instead
-- of rotating a picture. Same calls as a texture: SetRotation (radians,
-- counter-clockwise), SetVertexColor, Show, Hide.
-------------------------------------------------------------------------------

local CHEVRON = { { 0, 22 }, { -15, -14 }, { 0, -5 }, { 15, -14 } }
local RING_R, RING_DOTS = 27, 16

function N:MakeHudArrow(parent)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(64, 64)
    a:SetPoint("CENTER")
    a.glow, a.core = {}, {}
    for i = 1, #CHEVRON do
        a.glow[i] = a:CreateLine(nil, "BACKGROUND")
        a.glow[i]:SetThickness(7)
        a.core[i] = a:CreateLine(nil, "ARTWORK")
        a.core[i]:SetThickness(2.5)
    end
    a.spine = a:CreateLine(nil, "OVERLAY")
    a.spine:SetThickness(1)
    a.ring = {}
    for i = 1, RING_DOTS do
        local d = a:CreateTexture(nil, "BACKGROUND")
        d:SetSize(2, 2)
        d:SetColorTexture(1, 1, 1, 0.22)
        local t = (i - 1) / RING_DOTS * 2 * math.pi
        d:SetPoint("CENTER", a, "CENTER", RING_R * math.sin(t), RING_R * math.cos(t))
        a.ring[i] = d
    end
    a.lead = a:CreateTexture(nil, "OVERLAY")
    a.lead:SetSize(5, 5)
    a.lead:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    a.angle, a.r, a.g, a.b = 0, 1, 0.62, 0
    local function draw()
        local c, s = math.cos(a.angle), math.sin(a.angle)
        local pts = {}
        for i, p in ipairs(CHEVRON) do
            pts[i] = { p[1] * c - p[2] * s, p[1] * s + p[2] * c }
        end
        for i = 1, #pts do
            local p1, p2 = pts[i], pts[i % #pts + 1]
            for _, l in ipairs({ a.glow[i], a.core[i] }) do
                l:SetStartPoint("CENTER", a, p1[1], p1[2])
                l:SetEndPoint("CENTER", a, p2[1], p2[2])
            end
            a.glow[i]:SetColorTexture(a.r, a.g, a.b, 0.25)
            a.core[i]:SetColorTexture(a.r, a.g, a.b, 1)
        end
        a.spine:SetStartPoint("CENTER", a, pts[1][1], pts[1][2])
        a.spine:SetEndPoint("CENTER", a, pts[3][1], pts[3][2])
        a.spine:SetColorTexture(1, 1, 1, 0.85)
        -- Bright dot on the ring where the arrow points.
        a.lead:ClearAllPoints()
        a.lead:SetPoint("CENTER", a, "CENTER", -RING_R * s, RING_R * c)
        a.lead:SetVertexColor(a.r, a.g, a.b, 1)
    end
    function a:SetRotation(r) self.angle = r or 0; draw() end
    function a:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b; draw() end
    draw()
    return a
end

-- Shared look for route stops (trip plan, world map pins, map list):
--   label "3 [9]" = 3rd stop, quest level 9; "!2 [8]" = 2nd quest pickup
--   colour: route colour (green) = where the arrow points now, blue = quest pickup,
--           sky blue = your waypoint, bluish green = the rest of the route
-- A blocked stop for lists: lock (or coin) icon, greyed text, and the reason.
local LOCK = "Interface\Buttons\LockButton-Locked-Up"
function N:FormatBlocked(goal)
    return string.format("|T%s:12:12|t |cff9a9a9a%s|r", goal.blockIcon or LOCK, goal.text or goal.title or "?"),
           "|cffff7070" .. (goal.blockedBy or "blocked") .. "|r"
end

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

-- The kind of a stop (accept, turnin, kill, collect, ...): set by the goal's
-- provider, or worked out from its key for older goals.
function N:StopKind(goal)
    if goal.kind then return goal.kind end
    local k = goal.key
    if k == "user:wp" then return "waypoint" end
    if k:find("^party:") then return "party" end
    if k:find("^pickup:") then return "accept" end
    if k:find(":done$") then return "turnin" end
    if k == "train:class" then return "classtrainer" end
    if k:find("^train:") then return "proftrainer" end
    if k:find("^skill:") then return "skill" end
    if k:find("^hearth:") then return "hearth" end
    if k == "merchant" then return "merchant" end
    return "kill"
end

-- Colour for a stop: by its kind (see Theme.lua kinds).
function N:StopColor(i, goal)
    local kinds = ns.theme.kinds
    local k = kinds[self:StopKind(goal)]
    return k and k.color or ns.theme.current
end

-- "icon number text" for lists: the number is in the route colour for the stop the arrow
-- points at now, grey for the rest; the text takes the kind's colour.
function N:FormatStop(i, goal, label)
    local kindName = self:StopKind(goal)
    local kind = ns.theme.kinds[kindName]
    local path = kind and kind.icon
    -- Profession stops show that profession's own icon (pickaxe, anvil...).
    local prof = goal.key:match("^train:(.+)$") or goal.key:match("^skill:(.+)$")
    if prof and ns.disposition and ns.disposition.PROF_ICON[prof] then path = ns.disposition.PROF_ICON[prof] end
    local icon = path and string.format("|T%s:13:13|t ", path) or ""
    local numColor = (i == 1) and ns.theme.route.hex or "999999"
    local textColor = kind and kind.color.hex or "ffffff"
    return string.format("%s|cff%s%s|r |cff%s%s|r", icon, numColor, label or tostring(i),
        textColor, goal.text or goal.title or "?")
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

-- Quest pickups near you ("this hub"), nearest first, capped at the free
-- quest log slots. Walkthroughs grab every quest in a hub before heading out.
local HUB_RADIUS = 250  -- yards
function N:PickupKeys(radius)
    local p = self:PlayerPos()
    if not p then return nil end
    local near = {}
    for _, g in ipairs(goals) do
        if g.provider == "pickups" then
            local _, d = nearestPoint(g, p)
            if d and d <= (radius or HUB_RADIUS) then near[#near + 1] = { key = g.key, d = d } end
        end
    end
    table.sort(near, function(a, b) return a.d < b.d end)
    local free = ns.quests.FreeSlots and ns.quests:FreeSlots() or 20
    local t, any = {}, false
    for i = 1, math.min(#near, free) do t[near[i].key] = true; any = true end
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
    -- Choosing a stop switches to "From selected stop"; clearing goes back.
    if key then ns.db.nav.sorter = "selected"
    elseif ns.db.nav.sorter == "selected" then ns.db.nav.sorter = ns.db.nav.baseSorter or "xp" end
    self.planDirty = true
    pinnedKey = nil
end

function N:ClearSelection() self:Select(nil) end

-- Open what a stop is about, without changing the route (tracker clicks,
-- arrow menu): a quest in your log opens in the quest log; anything else
-- opens the world map on that stop, highlighted.
local function questLogIndex(id)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(id) end
    if GetQuestLogIndexByID then
        local i = GetQuestLogIndexByID(id)
        if i and i > 0 then return i end
    end
end

function N:OpenStop(goal)
    if not goal then return end
    local id = tonumber(goal.key:match("^(%d+):"))
    local idx = id and questLogIndex(id)
    if idx then
        if QuestMapFrame_OpenToQuestDetails then
            if pcall(QuestMapFrame_OpenToQuestDetails, id) then return end
        end
        if QuestLogFrame and SelectQuestLogEntry then
            SelectQuestLogEntry(idx)
            if not QuestLogFrame:IsShown() then ShowUIPanel(QuestLogFrame) end
            if QuestLog_Update then pcall(QuestLog_Update) end
            if QuestLog_UpdateQuestDetails then pcall(QuestLog_UpdateQuestDetails) end
            return
        end
    end
    -- Not a quest in your log: show it on the world map.
    if InCombatLockdown() then ns:Print("can't open the map in combat.") return end
    local pt = goal.points and goal.points[1]
    for _, s in ipairs(N.plan or {}) do if s.goal.key == goal.key then pt = s.point break end end
    if not WorldMapFrame:IsShown() then
        if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
    end
    if pt and pt.map and WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, pt.map) end
    if ns.mapOverlay and ns.mapOverlay.Focus then ns.mapOverlay:Focus(goal.key) end
end

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
    if not first and not tour and self.selection then
        self.selection = nil  -- the chosen stop is done: back to the usual sorting
        if ns.db.nav.sorter == "selected" then ns.db.nav.sorter = ns.db.nav.baseSorter or "xp" end
    end
    -- Default (nothing chosen): pick up the quests in this hub before heading
    -- out, like a walkthrough does, as long as your quest log has room.
    if not tour and not sel.first and self:Mode() == "optimal" then
        tour = self:PickupKeys()
    end
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
-- Previews are cached until the main route is re-planned (goals changed or
-- every few seconds), so hovering checkpoints doesn't re-plan every frame.
local previewCache, previewVersion = {}, -1
function N:PlanFor(key)
    if previewVersion ~= self.planVersion then
        wipe(previewCache)
        previewVersion = self.planVersion
    end
    local cacheKey = key or "-"
    local hit = previewCache[cacheKey]
    if hit ~= nil then return hit or nil end
    local p = self:PlayerPos()
    if not (p and ns.planner) then return nil end
    local tour = key and key:find("^pickup:") and self:PickupKeys() or nil
    local ok, result = pcall(ns.planner.Plan, ns.planner, p, goals, self:Options({ first = key, tour = tour }))
    previewCache[cacheKey] = (ok and result) or false
    return ok and result or nil
end

-- The plan: the whole trip in order (see Planner.lua). Re-planned when goals
-- change, and every few seconds as you move.
local plan, planAt = nil, 0
local function choose(p)
    -- "Do it where you stand" stops (e.g. crafting with no station) follow you.
    for _, goal in ipairs(goals) do
        if goal.anywhere then goal.points = { { cont = p.cont, wx = p.wx, wy = p.wy, map = p.map, x = p.x, y = p.y } } end
    end
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
            lines[#lines + 1] = "  " .. N:FormatStop(i, s.goal, labels[i])
                .. string.format(" |cff888888(+%d yd)|r", s.leg or 0)
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
    f.arrow = N:MakeHudArrow(f)
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
            -- Menu: this stop, then route and order choices, unhide all.
            local items = {}
            if current then
                local g = current.goal
                items[#items + 1] = { title = true, text = g.text or g.title or "This stop" }
                items[#items + 1] = { text = "Open it (quest / map)", func = function() N:OpenStop(g) end }
                items[#items + 1] = { text = "Hide this stop", func = function() N:Hide(g.key) end }
                items[#items + 1] = { sep = true }
            end
            for _, it in ipairs(ns.menu:RouteItems()) do items[#items + 1] = it end
            ns.menu:Open(items)
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
    -- Route colour follows the order mode (purple / blue / gold): recolour on change.
    if cfg.sorter ~= N.lastSorter then
        N.lastSorter = cfg.sorter
        ns.theme:UpdateRoute()
        if ns.mapOverlay and WorldMapFrame:IsShown() then pcall(ns.mapOverlay.Redraw, ns.mapOverlay) end
    end
    if not cfg.enabled then frame:Hide(); if ns.minimapPin then ns.minimapPin:Hide() end return end
    local p = N:PlayerPos()
    if not p then frame:Hide() return end
    if cfg.learn then record(p) end

    local choice = choose(p)
    current = choice
    if ns.minimapPin then pcall(ns.minimapPin.Update, ns.minimapPin, p, choice and choice.point, choice and choice.goal) end
    local tk = choice and choice.goal.key
    if tk ~= N.lastTargetKey then
        N.lastTargetKey = tk  -- mark the NPC of the new stop above its nameplate
        if ns.questMarks and ns.questMarks.SetRouteTarget then pcall(ns.questMarks.SetRouteTarget, choice and choice.goal.npcs) end
    end
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
        local c = ns.theme.route
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
N.RequestCollect = scheduleCollect  -- other modules: re-plan soon (throttled)

-- Money changed: re-plan only when it crosses a skipped stop's cost (so it
-- comes back) or drops below a planned stop's cost (so it's skipped).
ns:On("PLAYER_MONEY", function()
    local money = GetMoney()
    for _, d in pairs(ns.db.nav.deferred or {}) do
        if d.cost and d.cost <= money then scheduleCollect() return end
    end
    for _, g in ipairs(goals or {}) do
        if g.cost and g.cost > money then scheduleCollect() return end
    end
end)

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
            if err ~= N.lastError then ns:Log("nav", err) end
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
    elseif arg:find("^professions") then
        local v = arg:match("^professions%s+(%a+)")
        cfg.professions = (v ~= "off")
        N:Collect()
        ns:Print("professions on the route: " .. (cfg.professions and "on" or "off"))
    elseif arg == "xp" or arg == "xp on" or arg == "xp off" or arg == "distance" then
        ns.xpValue:Set(arg ~= "xp off" and arg ~= "distance")
        ns:Print("route sorting: " .. (ns.xpValue:On() and "most XP first" or "shortest path"))
    elseif arg == "unhide" or arg == "hidden" then
        -- Bring back every stop you hid (right-click), or list them.
        local n = 0
        for _ in pairs(cfg.hidden or {}) do n = n + 1 end
        if arg == "hidden" then
            ns:Print(n .. " hidden stop(s):")
            for _, g in ipairs(N.hiddenGoals or {}) do ns:Print("  " .. (g.text or g.title or g.key)) end
            ns:Print("/flow nav unhide brings them all back")
        else
            cfg.hidden = {}
            N:Collect()
            ns:Print(n .. " hidden stop(s) back on the route.")
        end
    elseif arg == "why" then
        -- What the route is made of, and what Flow wanted but couldn't place.
        ns:Print(string.format("route: mode %s, professions %s, Questie %s",
            N:Mode(), cfg.professions ~= false and "on" or "off",
            ns.quests:Source() and ns.quests:Source().label or "not found"))
        local byProvider = {}
        for _, g in ipairs(goals) do
            local placed = g.points and #g.points > 0
            local b = byProvider[g.provider] or { n = 0, placed = 0 }
            b.n = b.n + 1
            if placed then b.placed = b.placed + 1 end
            byProvider[g.provider] = b
        end
        for prov, b in pairs(byProvider) do
            print(string.format("  %s: %d goal(s), %d with a location", prov, b.n, b.placed))
        end
        local missing = {}
        for name in pairs(ns.places.missing or {}) do missing[#missing + 1] = name end
        if #missing > 0 then
            print("  couldn't find on the map: " .. table.concat(missing, ", "))
            print("  (talk to them once and Flow remembers where they stand)")
        end
        local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        print("  your map: " .. tostring(here) .. ", Elwynn zone lookup: " .. tostring(ns.quests:UiMapForArea(12)))
        print("  plan: " .. (N.plan and #N.plan or 0) .. " stop(s)")
        -- The route itself (also saved in the diagnostics for Claude to check).
        local free, max = ns.quests:FreeSlots()
        print(string.format("  quest log: %d free of %d; bound to %s", free, max, tostring(GetBindLocation and GetBindLocation())))
        for _, g in ipairs(N.blockedGoals or {}) do
            print(string.format("  blocked: %s - %s [%s]", tostring(g.text or g.title), tostring(g.blockedBy), g.key))
        end
        local nHidden = 0
        for _ in pairs(cfg.hidden or {}) do nHidden = nHidden + 1 end
        if nHidden > 0 then print(string.format("  hidden by you: %d stop(s) (/flow nav unhide)", nHidden)) end
        local labels = N:PlanLabels(N.plan or {})
        for i, s in ipairs(N.plan or {}) do
            if i > 25 then print("  ...") break end
            print(string.format("  %s %s  +%d yd  [%s]", labels[i], s.goal.text or s.goal.title or "?", s.leg or 0, s.goal.key))
        end
        local p = N:PlayerPos()
        if p then print(string.format("  you: map %d at %.1f, %.1f", p.map, p.x * 100, p.y * 100)) end
    elseif arg == "quests" or arg == "optimal" then
        N:SetMode(arg)
        ns:Print(arg == "quests" and "following your current quests only" or "following the optimal path (quests, pickups, trainers, skill-ups)")
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
