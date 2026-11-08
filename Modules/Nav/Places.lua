-- Places: where NPCs are, so the arrow can take you to trainers, vendors
-- and quest givers. Two sources:
--   learned : every time you talk to an NPC (gossip, trainer, vendor, quest
--             window), Flow remembers where you were standing. Works for any
--             NPC, including Forever-only ones no database knows yet.
--   Questie : spawn locations by NPC name, when Questie is installed.
--
-- Trainer names per profession are data (registry kind "trainerNames"), so
-- other zones/factions/classes can add theirs without touching this file.

local _, ns = ...
local P = {}
ns.places = P

-- Alliance starting-area trainers (from the levelling guide; not verified
-- in game). Nearest known one wins.
ns:Register("trainerNames", "alliance-elwynn", {
    ["Mining"]        = { "Kelsey Fargo", "Gelman Stonehand" },
    ["Blacksmithing"] = { "Smith Argus", "Therum Deepforge" },
    ["First Aid"]     = { "Michelle Belle" },
    ["Cooking"]       = { "Tomas" },
    ["Fishing"]       = { "Lee Brown" },
    ["Skinning"]      = { "Helene Peltskinner" },
    ["Herbalism"]     = { "Herbalist Pomeroy", "Nancy Songflower" },
    -- Class trainers (Northshire, Goldshire, Stormwind Cathedral).
    ["class:PALADIN"] = { "Brother Sammuel", "Brother Wilhelm", "Arthur the Faithful",
                          "Lord Grayson Shadowbreaker" },
})

-- Druid trainers: night elves (Shadowglen, Dolanaar, Darnassus' Cenarion
-- Enclave) and tauren (Camp Narache, Bloodhoof Village, Thunder Bluff).
ns:Register("trainerNames", "druid", {
    ["class:DRUID"] = { "Mardant Strongoak", "Kal", "Denatharion", "Fylerian Nightwing",
                        "Mathrengyl Bearwalker", "Gart Mistrunner", "Gennia Runetotem",
                        "Turak Runetotem", "Sheal Runetotem" },
})
ns:Register("npcIds", "druid", {
    ["Mardant Strongoak"] = 3597, ["Kal"] = 3602, ["Denatharion"] = 4218,
    ["Fylerian Nightwing"] = 4219, ["Mathrengyl Bearwalker"] = 4217,
    ["Gart Mistrunner"] = 3060, ["Gennia Runetotem"] = 3064,
    ["Turak Runetotem"] = 3033, ["Sheal Runetotem"] = 3034,
})

-- Horde profession trainers (Thunder Bluff, Orgrimmar, Undercity), so a
-- tauren, orc, troll or undead isn't sent to Elwynn Forest. Names are looked
-- up in Questie (a name it doesn't know is just skipped), and a trainer of
-- the other faction is never used (P:Points checks who they're friendly to).
ns:Register("trainerNames", "horde", {
    ["Alchemy"]        = { "Bena Winterhoof", "Yelmak", "Doctor Herbert Halsey" },
    ["Herbalism"]      = { "Komin Winterhoof", "Jandi", "Martha Alliestar" },
    ["Mining"]         = { "Brek Stonehoof", "Makaru", "Brom Killian" },
    ["Blacksmithing"]  = { "Karn Stonehoof", "Saru Steelfury", "James Van Brunt" },
    ["Skinning"]       = { "Mooranta", "Thuwd" },
    ["Leatherworking"] = { "Una", "Karolek" },
    ["First Aid"]      = { "Pand Stonebinder", "Arnok", "Mary Edras" },
    ["Cooking"]        = { "Aska Mistrunner", "Zamja", "Eunice Burch" },
    ["Fishing"]        = { "Kah Mistrunner", "Lumak", "Armand Cromwell" },
})

-- NPC IDs (stable since vanilla) so Questie can be asked directly. The
-- lookup checks the name matches, so a wrong ID is ignored, not followed.
ns:Register("npcIds", "alliance-elwynn", {
    ["Smith Argus"] = 514, ["Michelle Belle"] = 2329, ["Tomas"] = 1430, ["Lee Brown"] = 1651,
    ["Herbalist Pomeroy"] = 1218, ["Gelman Stonehand"] = 5513, ["Therum Deepforge"] = 5511,
    ["Brother Sammuel"] = 925, ["Brother Wilhelm"] = 927, ["Lord Grayson Shadowbreaker"] = 928,
    ["Arthur the Faithful"] = 5491,
})

-- Horde city trainers (Thunder Bluff, Orgrimmar, Undercity): found by name
-- they never got a place (0.35.83 diagnostics), so ask Questie by ID too.
ns:Register("npcIds", "horde-cities", {
    ["Bena Winterhoof"] = 3009, ["Aska Mistrunner"] = 3026, ["Kah Mistrunner"] = 3028,
    ["Pand Stonebinder"] = 3373, ["Yelmak"] = 3347, ["Zamja"] = 3399, ["Lumak"] = 3332,
    ["Arnok"] = 5943, ["Doctor Herbert Halsey"] = 4611, ["Eunice Burch"] = 4552,
    ["Armand Cromwell"] = 4573, ["Mary Edras"] = 4591,
})

local function npcId(name)
    for _, t in ns:Each("npcIds") do
        if t[name] then return t[name] end
    end
end

-- Where to raise a gathering/secondary skill. objects = Questie object IDs
-- (with the skill needed), npcs = stand near this NPC (e.g. the fishing
-- trainer at Crystal Lake). Unverified IDs; extend per zone as needed.
ns:Register("skillSpots", "alliance-elwynn", {
    ["Fishing"] = { npcs = { "Lee Brown" }, text = "Fish at the lake" },
    ["Mining"]  = { objects = { { id = 1731, skill = 1, name = "Copper Vein" },
                                { id = 1732, skill = 65, name = "Tin Vein" } }, text = "Mine" },
    ["Herbalism"] = { objects = { { id = 1617, skill = 1, name = "Silverleaf" },
                                  { id = 1618, skill = 1, name = "Peacebloom" } }, text = "Pick herbs" },
})

function P:SpotsFor(profession)
    local out = {}
    for _, t in ns:Each("skillSpots") do
        if t[profession] then out[#out + 1] = t[profession] end
    end
    return out
end

function P:TrainersFor(profession)
    local out = {}
    for _, t in ns:Each("trainerNames") do
        for _, name in ipairs(t[profession] or {}) do out[#out + 1] = name end
    end
    return out
end

-------------------------------------------------------------------------------
-- What Flow learns as you play: every NPC you talk to, where you stood, and
-- what they do for you. Saved for your account, so your other characters know
-- it too. Used by the route (where a trainer or quest giver stands) and by
-- "Nearest repair / vendor / flight master..." (Services.lua).
--   ns.db.places[name] = { map, x, y, kind, roles = { vendor = true, repair = true, ... },
--                          id (NPC ID), seen (time), n (times seen) }
--   roles: npc, quest, vendor, repair, trainer, flight, inn, bank, auction
--   kind: the main role (older saves have only this; "vendor" whenever it sells)
-- Mailboxes (objects, no name) go in ns.db.mailboxes: { { map, x, y }, ... }.
-- Talking to someone again only adds to what Flow knows: before 0.35.89 a
-- chat with a merchant overwrote them as a plain NPC, so Flow forgot they
-- sell and repair.
-------------------------------------------------------------------------------

local KIND_ORDER = { "vendor", "trainer", "flight", "inn", "bank", "auction", "quest", "npc" }

-- Add what you just saw to a remembered NPC (pure: tests call it).
--   pos { map, x, y }, role, extra { id, repair = true/false }
function P.Learn(places, name, pos, role, extra, now)
    local spot = places[name] or {}
    spot.map, spot.x, spot.y = pos.map, pos.x, pos.y
    spot.roles = spot.roles or {}
    if spot.kind and spot.kind ~= "npc" then spot.roles[spot.kind] = true end   -- (older saves)
    spot.roles[role] = true
    extra = extra or {}
    if extra.repair ~= nil then spot.roles.repair = extra.repair or nil; spot.repair = extra.repair end
    if extra.id then spot.id = extra.id end
    for _, k in ipairs(KIND_ORDER) do
        if spot.roles[k] then spot.kind = k break end
    end
    spot.seen, spot.n = now or (time and time()) or 0, (spot.n or 0) + 1
    places[name] = spot
    return spot
end

-- Does a remembered NPC do this? ("repair" also from the older .repair flag.)
function P.HasRole(spot, role)
    if not spot then return false end
    if spot.roles and spot.roles[role] then return true end
    if role == "repair" then return spot.repair == true end
    return spot.kind == role
end

-- The NPC ID from a unit's GUID ("Creature-0-...-<id>-..."), or nil.
function P.NpcIdOf(guid)
    guid = ns.api.Safe(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" then return nil end
    return tonumber(id)
end

local function remember(role, extra)
    local name = ns.api.Safe(UnitName("npc"))
    if not name or UnitIsPlayer("npc") then return end
    local p = ns.nav and ns.nav:PlayerPos()
    if not p then return end
    extra = extra or {}
    extra.id = extra.id or P.NpcIdOf(UnitGUID("npc"))
    P.Learn(ns.db.places, name, p, role, extra)
end
P._remember = remember

-- A mailbox where you stand, unless one is already known right there.
function P.LearnMailbox(list, pos)
    for _, m in ipairs(list) do
        if m.map == pos.map and math.abs(m.x - pos.x) < 0.01 and math.abs(m.y - pos.y) < 0.01 then return false end
    end
    list[#list + 1] = { map = pos.map, x = pos.x, y = pos.y }
    return true
end

-- Names Flow wanted to route to but couldn't place (for /flow nav why).
P.missing = {}

-- Map points for an NPC name: where you've talked to them before, then
-- Questie by NPC ID (name checked), then Questie by name.
-- Is an NPC friendly to your faction? flag: Questie's "A", "H", "AH" (or
-- nil: unknown, counts as friendly). faction: "Alliance" / "Horde".
function P.FriendlyTo(flag, faction)
    if type(flag) ~= "string" or flag == "" or not faction then return true end
    return flag:find(faction == "Horde" and "H" or "A", 1, true) ~= nil
end

function P:Points(name)
    local points = {}
    local spot = ns.db.places[name]
    if spot then points[#points + 1] = { map = spot.map, x = spot.x, y = spot.y } end
    local npc
    local id = npcId(name)
    if id and ns.quests.QuestieGet then
        local n = ns.quests:QuestieGet("GetNPC", id)
        if n and n.name == name then npc = n end
    end
    if not npc then
        local found = ns.quests.NPCsByName and ns.quests:NPCsByName({ name })
        npc = found and found[name] or nil
    end
    -- Only your own faction's NPCs (Questie: friendly to "A", "H" or "AH").
    if npc and not P.FriendlyTo(npc.friendlyToFaction, UnitFactionGroup and UnitFactionGroup("player")) then
        self.missing[name] = nil
        return {}
    end
    if npc and npc.spawns then
        for areaId, list in pairs(npc.spawns) do
            local map = ns.quests:UiMapForArea(areaId)
            if map then
                for _, c in ipairs(list) do
                    if c[1] and c[1] >= 0 then points[#points + 1] = { map = map, x = c[1] / 100, y = c[2] / 100 } end
                end
            end
        end
    end
    self.missing[name] = (#points == 0) or nil
    return points
end

-- Why an NPC has no place (for /flow nav why): which lookup gave up.
function P:Explain(name)
    local id = npcId(name)
    local byId = id and ns.quests:QuestieGet("GetNPC", id)
    local byName = ns.quests.NPCsByName and ns.quests:NPCsByName({ name })
    local npc = (byId and byId.name == name and byId) or (byName and byName[name]) or nil
    local parts = { name .. ":" }
    if id then parts[#parts + 1] = string.format("id %d %s", id, byId and ("is " .. tostring(byId.name)) or "unknown to Questie") end
    if byName == nil then parts[#parts + 1] = "name search running"
    elseif not (byName and byName[name]) then parts[#parts + 1] = "not found by name" end
    if npc then
        local areas = {}
        for areaId, list in pairs(npc.spawns or {}) do
            areas[#areas + 1] = string.format("area %s (%d spots) -> map %s", tostring(areaId), #list, tostring(ns.quests:UiMapForArea(areaId)))
        end
        parts[#parts + 1] = #areas > 0 and table.concat(areas, ", ") or "no spawns"
        parts[#parts + 1] = "faction " .. tostring(npc.friendlyToFaction)
    end
    return table.concat(parts, " ")
end

ns:OnLoad(function(saved)
    saved.places = saved.places or {}
    saved.mailboxes = saved.mailboxes or {}
end)

-- /flow places: what Flow has learned so far, by role.
function P:Summary()
    local counts, total = {}, 0
    for _, spot in pairs(ns.db.places or {}) do
        total = total + 1
        for _, role in ipairs({ "vendor", "repair", "trainer", "flight", "inn", "bank", "auction", "quest" }) do
            if P.HasRole(spot, role) then counts[role] = (counts[role] or 0) + 1 end
        end
    end
    return total, counts, #(ns.db.mailboxes or {})
end
ns.commands.places = function()
    local total, c, mail = P:Summary()
    ns:Print(string.format("learned while you play (all your characters): %d NPCs - %d vendors (%d repair), %d trainers, %d flight masters, %d innkeepers, %d bankers, %d auctioneers, %d quest givers; %d mailboxes",
        total, c.vendor or 0, c.repair or 0, c.trainer or 0, c.flight or 0, c.inn or 0, c.bank or 0, c.auction or 0, c.quest or 0, mail))
end

-- An innkeeper's chat offers to make the inn your home.
local function isInnkeeper()
    if not (C_GossipInfo and C_GossipInfo.GetOptions) then return false end
    local ok, options = pcall(C_GossipInfo.GetOptions)
    if not ok or type(options) ~= "table" then return false end
    for _, o in ipairs(options) do
        local text = ns.api.Safe(o.name)
        if type(text) == "string" and text:lower():find("inn your home", 1, true) then return true end
    end
    return false
end

ns:On("GOSSIP_SHOW", function() remember(isInnkeeper() and "inn" or "npc") end)
ns:On("MERCHANT_SHOW", function()
    -- (whether they repair: asked a moment later, once the window is up)
    remember("vendor")
    C_Timer.After(0.2, function()
        if CanMerchantRepair then remember("vendor", { repair = CanMerchantRepair() and true or false }) end
    end)
end)
ns:On("TAXIMAP_OPENED", function() remember("flight") end)
ns:On("BANKFRAME_OPENED", function() remember("bank") end)
ns:On("AUCTION_HOUSE_SHOW", function() remember("auction") end)
ns:On("CONFIRM_BINDER", function() remember("inn") end)
ns:On("MAIL_SHOW", function()
    local p = ns.nav and ns.nav:PlayerPos()
    if p then P.LearnMailbox(ns.db.mailboxes, p) end
end)
ns:On("QUEST_DETAIL", function() remember("quest") end)
ns:On("QUEST_GREETING", function() remember("quest") end)
ns:On("QUEST_COMPLETE", function() remember("quest") end)
ns:On("TRAINER_SHOW", function()
    remember("trainer")
    -- Remember which NPC is your class trainer, for "go train" errands.
    local isTrade = IsTradeskillTrainer and IsTradeskillTrainer()
    if not isTrade then ns.db.trainer.npc = ns.api.Safe(UnitName("npc")) end
end)
