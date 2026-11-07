-- Nearest repair / vendor: sets Flow's own waypoint on the closest NPC who
-- repairs (or buys your stuff). Right-click the arrow: "Nearest repair",
-- "Nearest vendor (sell)", or /flow way repair | vendor.
--
-- Where they are: merchants you've opened before (Flow remembers each one,
-- and whether they repair), plus Questie's NPC data scanned once in the
-- background for every NPC flagged as vendor or repairer.

local _, ns = ...
local S = {}
ns.services = S

local FLAG = { vendor = 0x80, repair = 0x1000 }   -- npcFlags bits (classic data)
local band = bit and bit.band
local found = { vendor = {}, repair = {} }        -- { { name, spawns } }
local scan                                         -- nil, "running", "done"

-- One background pass over Questie's NPCs (a few hundred per frame, paused
-- in combat), keeping the ones that sell or repair.
function S:Scan()
    if scan then return scan end
    local db = ns.quests.QuestieDB and ns.quests.QuestieDB()
    if not (db and db.NPCPointers and band) then scan = "done" return scan end
    scan = "running"
    local co = coroutine.create(function()
        local n = 0
        for id in pairs(db.NPCPointers) do
            local npc = ns.quests:QuestieGet("GetNPC", id)
            local flags = npc and tonumber(npc.npcFlags)
            if flags and npc.spawns and npc.name then
                for kind, bitv in pairs(FLAG) do
                    if band(flags, bitv) ~= 0 then found[kind][#found[kind] + 1] = { name = npc.name, spawns = npc.spawns } end
                end
            end
            n = n + 1
            if n % 300 == 0 then coroutine.yield() end
        end
    end)
    local function step()
        if InCombatLockdown() then C_Timer.After(1, step) return end
        local ok = coroutine.resume(co)
        if ok and coroutine.status(co) ~= "dead" then C_Timer.After(0, step) else scan = "done" end
    end
    step()
    return scan
end

-- Merchants you open: remember whether they repair (next to where Places
-- already remembers them).
ns:On("MERCHANT_SHOW", function()
    C_Timer.After(0.2, function()
        local name = ns.api.Safe(UnitName("npc"))
        local spot = name and ns.db.places and ns.db.places[name]
        if spot and CanMerchantRepair then spot.repair = CanMerchantRepair() and true or false end
    end)
end)

-- Nearest one of `kind` ("vendor" or "repair") on your continent:
-- { name, map, x, y, yards } or nil.
function S:Nearest(kind)
    local nav = ns.nav
    local p = nav and nav:PlayerPos()
    if not p then return nil end
    local best
    local function consider(name, map, x, y)
        local cont, wx, wy = nav:ToWorld(map, x, y)
        if cont == p.cont and wx then
            local d = math.sqrt((wx - p.wx) ^ 2 + (wy - p.wy) ^ 2)
            if not best or d < best.yards then best = { name = name, map = map, x = x, y = y, yards = d } end
        end
    end
    for name, spot in pairs(ns.db.places or {}) do
        if spot.kind == "vendor" and (kind == "vendor" or spot.repair) and spot.map then
            consider(name, spot.map, spot.x, spot.y)
        end
    end
    for _, npc in ipairs(found[kind] or {}) do
        for areaId, list in pairs(npc.spawns) do
            local map = ns.quests:UiMapForArea(areaId)
            if map then
                for _, c in ipairs(list) do
                    if c[1] and c[1] >= 0 then pcall(consider, npc.name, map, c[1] / 100, c[2] / 100) end
                end
            end
        end
    end
    return best
end

local LABEL = { repair = "repair", vendor = "vendor" }
function S:GoTo(kind)
    local state = self:Scan()
    local n = self:Nearest(kind)
    if not n then
        ns:Print(state == "running" and ("looking up " .. LABEL[kind] .. "s... try again in a few seconds.")
            or ("Flow doesn't know a " .. LABEL[kind] .. " on this continent yet."))
        return
    end
    ns.waypoint:Set(n.map, n.x, n.y, n.name .. " (" .. LABEL[kind] .. ")")
    local bind = GetBindLocation and GetBindLocation()
    ns:Print(string.format("nearest %s: %s, %d yd.%s", LABEL[kind], n.name, n.yards,
        (n.yards > 600 and bind) and (" Far: your hearthstone goes to " .. bind .. ".") or ""))
end

ns:On("PLAYER_LOGIN", function() C_Timer.After(20, function() pcall(S.Scan, S) end) end)
