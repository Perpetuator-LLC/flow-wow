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

-- Map points for an NPC name: learned spot first, then Questie spawns.
function P:Points(name)
    local points = {}
    local spot = ns.db.places[name]
    if spot then points[#points + 1] = { map = spot.map, x = spot.x, y = spot.y } end
    local found = ns.quests.NPCsByName and ns.quests:NPCsByName({ name })
    local npc = found and found[name]
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
