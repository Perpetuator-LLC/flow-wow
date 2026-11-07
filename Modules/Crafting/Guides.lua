-- Profession levelling data: what to make at each skill, what it takes, and
-- where those materials come from. The planner (SkillPlan.lua) works from
-- this plus what you have right now (skill, bags, quests, position) to put
-- gather / smelt / craft stops on the route. Nothing here is a fixed path.
--
-- Skill colours (learn / yellow / green / grey) are approximate, from public
-- levelling guides. What the profession window shows in game (Recipes.lua)
-- wins whenever Flow has seen it.
--
-- Extend by registering more:
--   ns:Register("profGuide", "<Profession>", {
--       kind = "craft" | "gather",
--       tool = itemID,                       -- needed in your bags (craft)
--       steps = { { recipe, item, learn, yellow, green, grey, mats = { [itemID] = n },
--                   station = "anvil" | "forge" | "fire" | nil } } })
--   ns:Register("itemSource", itemID, {
--       name, gather = "<Profession>", objects = { objectIDs }, skill = n, yield = per node,
--       smelt = { from = itemID, n = count, skill = n, spell = "Smelt X" },
--       drops = { "NPC name", ... },        -- mobs that drop it
--       fished = true, share = 0.7,         -- caught while levelling Fishing
--       rate = 0.35,                        -- rough chance per kill (Flow learns yours as you loot)
--       vendor = true })                     -- bought (Questie lists the vendors)

local _, ns = ...

-------------------------------------------------------------------------------
-- Items
-------------------------------------------------------------------------------

local COPPER_VEIN = { 1731, 2055, 3763, 103713 }
local TIN_VEIN    = { 1732, 2054, 3764, 103711 }
local IRON_VEIN   = { 1735 }

ns:Register("itemSource", 2770, { name = "Copper Ore", gather = "Mining", objects = COPPER_VEIN, node = "Copper Vein", skill = 1, yield = 2 })
ns:Register("itemSource", 2835, { name = "Rough Stone", gather = "Mining", objects = COPPER_VEIN, node = "Copper Vein", skill = 1, yield = 0.8 })
ns:Register("itemSource", 2840, { name = "Copper Bar", smelt = { from = 2770, n = 1, skill = 1, spell = "Smelt Copper" } })
ns:Register("itemSource", 2771, { name = "Tin Ore", gather = "Mining", objects = TIN_VEIN, node = "Tin Vein", skill = 65, yield = 2 })
ns:Register("itemSource", 2836, { name = "Coarse Stone", gather = "Mining", objects = TIN_VEIN, node = "Tin Vein", skill = 65, yield = 0.8 })
ns:Register("itemSource", 3576, { name = "Tin Bar", smelt = { from = 2771, n = 1, skill = 65, spell = "Smelt Tin" } })
ns:Register("itemSource", 2772, { name = "Iron Ore", gather = "Mining", objects = IRON_VEIN, node = "Iron Deposit", skill = 125, yield = 2 })
ns:Register("itemSource", 2838, { name = "Heavy Stone", gather = "Mining", objects = IRON_VEIN, node = "Iron Deposit", skill = 125, yield = 0.8 })
ns:Register("itemSource", 3575, { name = "Iron Bar", smelt = { from = 2772, n = 1, skill = 125, spell = "Smelt Iron" } })

-- Mob drops (names are looked up in Questie; only spawns on your map are used).
ns:Register("itemSource", 2589, { name = "Linen Cloth", drops = {
    "Defias Thug", "Defias Cutpurse", "Defias Bandit", "Defias Rogue Wizard", "Defias Smuggler",
    "Kobold Vermin", "Kobold Worker", "Kobold Laborer", "Kobold Tunneler", "Riverpaw Gnoll", "Riverpaw Runt",
    "Murloc Streamrunner", "Murloc Forager" } })
ns:Register("itemSource", 2672, { name = "Stringy Wolf Meat", rate = 0.35, drops = { "Young Wolf", "Timber Wolf", "Prowler", "Gray Forest Wolf" } })
ns:Register("itemSource", 769,  { name = "Chunk of Boar Meat", rate = 0.45, drops = { "Stonetusk Boar", "Rockhide Boar", "Small Crag Boar" } })
-- Caught while levelling Fishing (share: roughly how many catches are this fish
-- in starting-zone water). Counts against the meat Cooking would otherwise farm.
ns:Register("itemSource", 6291, { name = "Raw Brilliant Smallfish", fished = true, share = 0.7 })
ns:Register("itemSource", 6325, { name = "Recipe: Brilliant Smallfish", vendor = true, price = 40 })

-- Tools.
-- price: copper, approximate; replaced by the real price once you've seen it at a vendor.
ns:Register("itemSource", 5956, { name = "Blacksmith Hammer", vendor = true, price = 18 })
ns:Register("itemSource", 2901, { name = "Mining Pick", vendor = true, price = 16 })
ns:Register("itemSource", 6256, { name = "Fishing Pole", vendor = true, price = 23 })
ns:Register("itemSource", 6529, { name = "Shiny Bauble", vendor = true, price = 100 })   -- lure: +25 Fishing

-------------------------------------------------------------------------------
-- Professions
-------------------------------------------------------------------------------

ns:Register("profGuide", "Blacksmithing", {
    kind = "craft", tool = 5956,
    steps = {
        { recipe = "Rough Sharpening Stone", item = 2862, learn = 1, yellow = 15, green = 35, grey = 55, mats = { [2835] = 1 } },
        { recipe = "Rough Grinding Stone", item = 3470, learn = 25, yellow = 45, green = 65, grey = 85, mats = { [2835] = 2 } },
        { recipe = "Coarse Sharpening Stone", item = 2863, learn = 65, yellow = 65, green = 72, grey = 80, mats = { [2836] = 1 } },
        { recipe = "Coarse Grinding Stone", item = 3478, learn = 75, yellow = 75, green = 87, grey = 100, mats = { [2836] = 2 } },
    },
})

ns:Register("profGuide", "Mining", {
    kind = "gather", tool = 2901,
    -- Nodes raise Mining; smelting does too (craft-like steps below).
    nodes = {
        { item = 2770, learn = 1, yellow = 25, green = 50, grey = 100 },
        { item = 2771, learn = 65, yellow = 90, green = 115, grey = 165 },
        { item = 2772, learn = 125, yellow = 150, green = 175, grey = 225 },
    },
    steps = {
        { recipe = "Smelt Copper", item = 2840, learn = 1, yellow = 25, green = 47, grey = 70, mats = { [2770] = 1 }, station = "forge" },
        { recipe = "Smelt Tin", item = 3576, learn = 65, yellow = 65, green = 70, grey = 75, mats = { [2771] = 1 }, station = "forge" },
    },
})

ns:Register("profGuide", "First Aid", {
    kind = "craft",
    steps = {
        { recipe = "Linen Bandage", item = 1251, learn = 1, yellow = 30, green = 45, grey = 60, mats = { [2589] = 1 } },
        { recipe = "Heavy Linen Bandage", item = 2581, learn = 40, yellow = 60, green = 80, grey = 100, mats = { [2589] = 2 } },
    },
})

ns:Register("profGuide", "Cooking", {
    kind = "craft",
    steps = {
        { recipe = "Charred Wolf Meat", item = 2679, learn = 1, yellow = 45, green = 65, grey = 85, mats = { [2672] = 1 }, station = "fire" },
        { recipe = "Roasted Boar Meat", item = 2681, learn = 1, yellow = 45, green = 65, grey = 85, mats = { [769] = 1 }, station = "fire" },
        -- Fish from your Fishing stops levels Cooking just as well (the recipe is bought).
        { recipe = "Brilliant Smallfish", item = 6290, learn = 1, yellow = 45, green = 65, grey = 85, mats = { [6291] = 1 },
          station = "fire", recipeItem = 6325 },
    },
})

ns:Register("profGuide", "Fishing", { kind = "gather", spots = true, tool = 6256, lure = 6529,
    -- Keep up with the water you'll fish in, not with crafting: starting-zone
    -- lakes need ~25 so fish don't get away, the next zones ~75, then ~150.
    pace = { { 1, 1 }, { 10, 25 }, { 20, 75 }, { 30, 150 }, { 40, 225 }, { 50, 300 } },
    tip = "Tip: a Shiny Bauble (+25 Fishing for 10 minutes) catches more while your skill is low. Flow's key puts it on your pole." })

ns:Register("profGuide", "Herbalism", { kind = "gather", spots = true })
