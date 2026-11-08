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

local function remember(kind)
    local name = ns.api.Safe(UnitName("npc"))
    if not name or UnitIsPlayer("npc") then return end
    local p = ns.nav and ns.nav:PlayerPos()
    if not p then return end
    ns.db.places[name] = { map = p.map, x = p.x, y = p.y, kind = kind }
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

ns:OnLoad(function(saved) saved.places = saved.places or {} end)

ns:On("GOSSIP_SHOW", function() remember("npc") end)
ns:On("MERCHANT_SHOW", function() remember("vendor") end)
ns:On("QUEST_DETAIL", function() remember("quest") end)
ns:On("QUEST_GREETING", function() remember("quest") end)
ns:On("QUEST_COMPLETE", function() remember("quest") end)
ns:On("TRAINER_SHOW", function()
    remember("trainer")
    -- Remember which NPC is your class trainer, for "go train" errands.
    local isTrade = IsTradeskillTrainer and IsTradeskillTrainer()
    if not isTrade then ns.db.trainer.npc = ns.api.Safe(UnitName("npc")) end
end)
