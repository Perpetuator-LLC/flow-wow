-- Where the Flow Router sits by the world map: just outside the map on the
-- right, so to the right of the quest log (the map's right-hand panel). The
-- quest log and the Flow Router are separate (0.35.155): each opens and
-- closes with its own button, and either, both or neither can be open. They
-- used to share one slot, the Router covering the quest log, and L closed it.
-- A maximised map leaves no room on the right: then the Router sits inside
-- the map's right edge, left of the quest log when that's open.
--
-- (A new file on purpose: WoW: Forever reloads every file on /reload,
-- including ones added while the game runs. Its self-test, "core: a file
-- added while the game runs loads on /reload", fails if that ever stops.)

local _, ns = ...
local D = {}
ns.routerDock = D

D.WIDTH, D.GAP = 300, 2

-- Pure (the tests pass numbers in): where it goes. Right edges and the room
-- it needs in screen pixels; questLogOpen: the map's quest panel is showing.
-- "outside" (right of the map), "besideLog" (inside, left of the quest
-- log) or "inside" (inside the map's right edge).
function D.Spot(mapRight, screenRight, need, questLogOpen)
    if mapRight and screenRight and need and mapRight + need <= screenRight then return "outside" end
    return questLogOpen and "besideLog" or "inside"
end

local function questLog()
    local q = QuestMapFrame
    if q and q:IsShown() and (q:GetWidth() or 0) > 100 then return q end
end

-- Puts the Flow Router (a child of the world map) where D.Spot says.
function D.Place(list)
    local map = WorldMapFrame
    if not (list and map) then return end
    local q = questLog()
    local right = map:GetRight()
    local spot = D.Spot(right and right * map:GetEffectiveScale(),
        UIParent:GetRight() * UIParent:GetEffectiveScale(),
        (D.WIDTH + D.GAP) * list:GetEffectiveScale(), q ~= nil)
    list:ClearAllPoints()
    if spot == "outside" then
        list:SetPoint("TOPLEFT", map, "TOPRIGHT", D.GAP, 0)
        list:SetSize(D.WIDTH, math.max(200, map:GetHeight()))
    elseif spot == "besideLog" then
        list:SetPoint("TOPRIGHT", q, "TOPLEFT", -D.GAP, 0)
        list:SetSize(D.WIDTH, math.max(200, q:GetHeight()))
    else
        local area = map.ScrollContainer or map
        list:SetPoint("TOPRIGHT", area, "TOPRIGHT", -D.GAP, 0)
        list:SetSize(D.WIDTH, math.max(200, area:GetHeight()))
    end
    D.lastSpot = spot
    return spot
end

ns:On("PLAYER_LOGIN", function()
    ns:Log("session", "RouterDock.lua loaded (new in 0.35.155): /reload loads files added while the game runs")
end)
