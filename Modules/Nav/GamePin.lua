-------------------------------------------------------------------------------
-- Flow - Nav/GamePin.lua
-- A try-out: the game's own waypoint on Flow's next step, so the game draws
-- its marker for it (0.35.446). Off unless you turn it on.
--
-- "Is there a way for us to control elevation so that our dot on the minimap
-- is showing the up or down arrow, just using the same up down arrow that
-- they already allow on their markers?"
--
-- An add-on is given no height on this client, and the little up and down
-- arrows are drawn by the game for the things it tracks itself. What an
-- add-on can do is hand the game a spot to track: its map pin (the one
-- Ctrl-click on the world map sets). The game then draws its own marker for
-- it, in the world and on the minimap. Whether that marker shows above and
-- below for a spot that's only a place on the flat map is what this is for
-- finding out: nobody knows until it's looked at in the game.
--
-- With /flow gamepin on:
--   * the game's map pin follows Flow's next step (looked at once a second,
--     set only when the step's spot changes), and the game tracks it;
--   * a pin you set yourself is never replaced: while yours is up, Flow's
--     isn't; clear yours and Flow's comes back;
--   * Flow's pin isn't "your waypoint": the arrow, the map and the route go
--     on as without it (Waypoint.lua asks GP.IsOurs);
--   * turned off, or with no step, Flow takes its pin away again.
-- /flow gamepin says what it's doing and what the above/below probe
-- (HeightProbe.lua) has seen. Flow already sets this same pin for your own
-- waypoint, so nothing new is asked of the game's map.
-------------------------------------------------------------------------------

local _, ns = ...
local GP = {}
ns.gamePin = GP

GP.NEAR = 0.002   -- two map spots this close (a share of the map) are the same spot

function GP.On() return ns.db ~= nil and ns.db.nav ~= nil and ns.db.nav.gamePin == true end

-- Pure: are two spots the same? ({ map, x, y } each)
function GP.Same(a, b)
    if not (a and b and a.map and b.map and a.x and b.x) then return false end
    return a.map == b.map and math.abs(a.x - b.x) <= GP.NEAR and math.abs(a.y - b.y) <= GP.NEAR
end

-- Pure: what to do now.
--   on: the try-out is on; step: your next step's spot or nil; pin: the game's
--   pin as it is or nil; ours: the spot Flow last pinned or nil
-- -> "leave" (the pin is yours: Flow's is forgotten), "keep", "set", "clear"
function GP.Decide(on, step, pin, ours)
    local mine = pin ~= nil and ours ~= nil and GP.Same(pin, ours)
    if pin ~= nil and not mine then return "leave" end
    if on and step then
        if mine and GP.Same(ours, step) then return "keep" end
        return "set"
    end
    return mine and "clear" or "keep"
end

local function ours() return ns.db and ns.db.nav and ns.db.nav.gamePinAt or nil end
local function setOurs(spot) if ns.db and ns.db.nav then ns.db.nav.gamePinAt = spot end end

-- Is this spot Flow's own pin (not a waypoint of yours)?
function GP.IsOurs(map, x, y)
    return GP.Same(ours(), { map = map, x = x, y = y })
end

-- Is the game drawing its pin for Flow's step now? (MinimapPin.lua: Flow's mark goes round the game's arrow then.)
-- Looked up once a second (GP.Tick): the minimap asks many times a second.
function GP.Shown() return GP.shown == true end

-- The game's pin as it is: { map, x, y } or nil.
function GP.Pin()
    if not (C_Map and C_Map.HasUserWaypoint and C_Map.GetUserWaypoint and C_Map.HasUserWaypoint()) then return nil end
    local pt = C_Map.GetUserWaypoint()
    local pos = pt and pt.position
    if not pos then return nil end
    local x, y
    if type(pos.GetXY) == "function" then x, y = pos:GetXY() else x, y = pos.x, pos.y end
    if not (x and y) then return nil end
    return { map = pt.uiMapID, x = x, y = y }
end

-- Once a second.
function GP.Tick()
    if not (C_Map and C_Map.SetUserWaypoint and C_Map.ClearUserWaypoint and UiMapPoint) then return "none" end
    local N = ns.nav
    local cur = N and N.current
    local step
    if cur and cur.point and cur.point.map and cur.point.x and not cur.waypoint and not cur.follow then
        step = { map = cur.point.map, x = cur.point.x, y = cur.point.y }
    end
    local what = GP.Decide(GP.On(), step, GP.Pin(), ours())
    GP.shown = (what == "keep" or what == "set") and GP.On() and step ~= nil
    if what == "leave" then
        if ours() then setOurs(nil) end
    elseif what == "set" then
        if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(step.map) then
            if GP.refused ~= step.map then
                GP.refused = step.map
                ns:Log("nav", "game pin: the game takes no pin on map " .. tostring(step.map))
            end
            GP.shown = false
            return "refused"
        end
        setOurs(step)   -- (first: the pin is Flow's from the moment it's there)
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(step.map, step.x, step.y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
        GP.sets = (GP.sets or 0) + 1
        if GP.sets <= 12 then   -- (a roaming step's nearest spot moves as you do: not a line for each)
            ns:Log("nav", string.format("game pin: set on your step at map %s %.1f, %.1f", tostring(step.map), step.x * 100, step.y * 100))
        end
    elseif what == "clear" then
        C_Map.ClearUserWaypoint()
        setOurs(nil)
        ns:Log("nav", "game pin: taken away")
    end
    return what
end

if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1, function()
        local ok, err = pcall(GP.Tick)
        if not ok and not GP.failed then
            GP.failed = true
            ns:Log("nav", "game pin failed: " .. tostring(err))
        end
    end)
end
ns:OnLoad(function(saved) saved.nav = saved.nav or {} end)
ns:PerCharacter("nav.gamePin")
ns:PerCharacter("nav.gamePinAt")

function GP.Lines()
    local out = { string.format("Flow: the game's pin on your next step (a try-out for above and below): %s; set %d time(s) this session%s",
        GP.On() and "on" or "off", GP.sets or 0, GP.failed and "; it failed once, see the log" or "") }
    local pin, mine = GP.Pin(), ours()
    out[#out + 1] = "  the game's pin now: " .. (pin and string.format("map %s %.1f, %.1f (%s)", tostring(pin.map), pin.x * 100, pin.y * 100,
        GP.Same(pin, mine) and "Flow's" or "yours") or "none")
    local HP = ns.heightProbe
    if HP and HP.seen then
        out[#out + 1] = string.format("  above/below probe: %d look(s); the game's marker was a frame in %d, measurable in %d",
            HP.seen.looks or 0, HP.seen.frame or 0, HP.seen.measured or 0)
    end
    out[#out + 1] = "  /flow gamepin on | off. On: look at the minimap and the marker in the world near a step that's above or below you."
    return out
end
ns.commands.gamepin = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.nav.gamePin = (arg == "on") or nil
        pcall(GP.Tick)
    end
    for _, l in ipairs(GP.Lines()) do print(l) end
end
