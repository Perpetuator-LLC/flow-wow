-- Your own waypoint. It becomes the first stop of the route (the arrow goes
-- there first), and clears itself when you arrive.
--   Set:   Ctrl-click the world map (the game's own map pin, on clients that
--          have it), Alt-click the world map, or /flow way <x> <y> [note]
--   Clear: /flow way clear (or arrive)
-- PLACEHOLDER: a custom multi-point path (ticketed).

local _, ns = ...
local W = {}
ns.waypoint = W

local function blizzard() return C_Map and C_Map.HasUserWaypoint and C_Map.GetUserWaypoint end

-- { map, x, y, note } or nil
function W:Get()
    if blizzard() and C_Map.HasUserWaypoint() then
        local pt = C_Map.GetUserWaypoint()
        if pt and pt.position then
            local x, y = pt.position:GetXY()
            return { map = pt.uiMapID, x = x, y = y, note = ns.db.nav.waypointNote }
        end
    end
    return ns.db.nav.waypoint
end

function W:Set(map, x, y, note)
    -- On a shared party route, a waypoint becomes a shared stop at the front.
    if ns.party and ns.party:Following() then
        ns.party:AddFront(map, x, y, note or "Waypoint", nil, "waypoint")
        ns:Print(string.format("added %.1f, %.1f to the front of the shared route", x * 100, y * 100))
        return
    end
    ns.db.nav.waypointNote = note
    if blizzard() and C_Map.SetUserWaypoint and UiMapPoint then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
        ns.db.nav.waypoint = nil
    else
        ns.db.nav.waypoint = { map = map, x = x, y = y, note = note }
    end
    if ns.nav then ns.nav:Collect(); ns.nav.planDirty = true end
    ns:Print(string.format("waypoint set at %.1f, %.1f%s", x * 100, y * 100, note and (" (" .. note .. ")") or ""))
end

function W:Clear()
    if blizzard() and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
    ns.db.nav.waypoint, ns.db.nav.waypointNote = nil, nil
    if ns.nav then ns.nav:Collect(); ns.nav.planDirty = true end
end

ns:Register("navGoal", "userWaypoint", {
    collect = function()
        local w = W:Get()
        if not w then return nil end
        return { {
            key = "user:wp", weight = 0.1,
            points = { { map = w.map, x = w.x, y = w.y } },
            title = "Your waypoint",
            text = "Waypoint" .. (w.note and (": " .. w.note) or ""),
            details = { string.format("You set this at %.1f, %.1f.", w.x * 100, w.y * 100),
                        "It clears when you get there, or with /flow way clear." },
        } }
    end,
})

-- Alt-click on the world map.
local function hookMap()
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not (sc and sc.GetNormalizedCursorPosition) then return end
    sc:HookScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not IsAltKeyDown() then return end
        local x, y = self:GetNormalizedCursorPosition()
        local map = WorldMapFrame:GetMapID()
        if map and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then W:Set(map, x, y) end
    end)
end

ns:On("PLAYER_LOGIN", function() pcall(hookMap) end)
ns:On("USER_WAYPOINT_UPDATED", function() if ns.nav then ns.nav:Collect() end end)

ns.commands.way = function(arg)
    arg = arg or ""
    if arg:lower():match("^%s*clear") then
        W:Clear()
        ns:Print("waypoint cleared")
        return
    end
    local x, y, note = arg:match("^%s*([%d%.]+)[,%s]+([%d%.]+)%s*(.-)%s*$")
    x, y = tonumber(x), tonumber(y)
    if not (x and y) then
        ns:Print("/flow way <x> <y> [note] (map coordinates in your current zone), /flow way clear. Or Alt-click the world map.")
        return
    end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not map then ns:Print("can't tell which zone you're in") return end
    W:Set(map, x / 100, y / 100, note ~= "" and note or nil)
end
