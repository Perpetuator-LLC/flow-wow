-- Nearest repair / vendor / flight master / innkeeper / banker / auctioneer /
-- mailbox: sets Flow's own waypoint on the closest one. Right-click the
-- arrow ("Nearest repair", "Nearest vendor (sell)"), or /flow way repair |
-- vendor | flight | inn | bank | auction | mail.
--
-- Where they are: the ones you've used before (Places.lua learns each NPC
-- you talk to and what they do, for all your characters), plus Questie's NPC
-- data scanned once in the background for every NPC flagged for it. Only
-- NPCs friendly to your faction (a tauren could be sent to an Alliance vendor).

local _, ns = ...
local S = {}
ns.services = S

-- npcFlags bits (classic data)
local FLAG = { vendor = 0x80, repair = 0x1000, flight = 0x2000, inn = 0x10000, bank = 0x20000, auction = 0x200000 }
local band = bit and bit.band
local found = { vendor = {}, repair = {}, flight = {}, inn = {}, bank = {}, auction = {} }   -- { { name, spawns, faction } }
local scan                                         -- nil, "running", "done"
S.KINDS = { "repair", "vendor", "flight", "inn", "bank", "auction", "mail" }

-- One background pass over Questie's NPCs (a few hundred per frame, paused
-- in combat), keeping the ones that offer a service.
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
                    if band(flags, bitv) ~= 0 then
                        found[kind][#found[kind] + 1] = { name = npc.name, spawns = npc.spawns, faction = npc.friendlyToFaction }
                    end
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

-- Nearest one of `kind` (S.KINDS) on your continent:
-- { name, map, x, y, yards, learned = true if you've used it } or nil.
function S:Nearest(kind)
    local nav = ns.nav
    local p = nav and nav:PlayerPos()
    if not p then return nil end
    local best
    local function consider(name, map, x, y, learned)
        local cont, wx, wy = nav:ToWorld(map, x, y)
        if cont == p.cont and wx then
            local d = math.sqrt((wx - p.wx) ^ 2 + (wy - p.wy) ^ 2)
            if not best or d < best.yards then best = { name = name, map = map, x = x, y = y, yards = d, learned = learned } end
        end
    end
    -- What you've learned yourself.
    for name, spot in pairs(ns.db.places or {}) do
        if spot.map and ns.places.HasRole(spot, kind) then pcall(consider, name, spot.map, spot.x, spot.y, true) end
    end
    if kind == "mail" then
        for _, m in ipairs(ns.db.mailboxes or {}) do pcall(consider, "Mailbox", m.map, m.x, m.y, true) end
    end
    -- Questie's data: only your own faction's NPCs.
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    for _, npc in ipairs(found[kind] or {}) do
        if ns.places.FriendlyTo(npc.faction, faction) then
            for areaId, list in pairs(npc.spawns) do
                local map = ns.quests:UiMapForArea(areaId)
                if map then
                    for _, c in ipairs(list) do
                        if c[1] and c[1] >= 0 then pcall(consider, npc.name, map, c[1] / 100, c[2] / 100) end
                    end
                end
            end
        end
    end
    return best
end

local LABEL = { repair = "repair", vendor = "vendor", flight = "flight master", inn = "innkeeper",
                bank = "banker", auction = "auctioneer", mail = "mailbox" }
S.LABEL = LABEL
function S:GoTo(kind)
    if not LABEL[kind] then return end
    local state = self:Scan()
    local n = self:Nearest(kind)
    if not n then
        ns:Print(state == "running" and ("looking up " .. LABEL[kind] .. "s... try again in a few seconds.")
            or ("Flow doesn't know a " .. LABEL[kind] .. " on this continent yet (it learns each one you use)."))
        return
    end
    ns.waypoint:Set(n.map, n.x, n.y, n.name .. " (" .. LABEL[kind] .. ")")
    local bind = GetBindLocation and GetBindLocation()
    ns:Print(string.format("nearest %s: %s, %d yd%s.%s", LABEL[kind], n.name, n.yards,
        n.learned and " (you've been there)" or "",
        (n.yards > 600 and bind) and (" Far: your hearthstone goes to " .. bind .. ".") or ""))
end

ns:On("PLAYER_LOGIN", function() C_Timer.After(20, function() pcall(S.Scan, S) end) end)
