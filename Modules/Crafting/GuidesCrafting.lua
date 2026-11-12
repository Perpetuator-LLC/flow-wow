-- Levelling data for Tailoring, Leatherworking, Alchemy, Enchanting and
-- Engineering, 1-300 (Classic Era). Same shape as Guides.lua, which documents
-- the fields; materials already registered there (ores, bars, stones, Linen
-- Cloth, Simple Wood, the Blacksmith Hammer) are not repeated here.
--
-- Routes follow the Wowhead Classic levelling guides: the cheapest trainer
-- recipes, plus the fewest bought patterns. Materials with no itemSource (cloth
-- other than Linen, leather and hides, enchanting dust and essences, gems,
-- Bronze and Steel Bars) show as Auction House buys.

local _, ns = ...

-------------------------------------------------------------------------------
-- Items
-------------------------------------------------------------------------------

-- Herbs (Herbalism node object IDs as in Nearby.lua).
ns:Register("itemSource", 2447,  { name = "Peacebloom", gather = "Herbalism", objects = { 1618, 3724 }, node = "Peacebloom", skill = 1, yield = 1.5 })
ns:Register("itemSource", 765,   { name = "Silverleaf", gather = "Herbalism", objects = { 1617, 3725 }, node = "Silverleaf", skill = 1, yield = 1.5 })
ns:Register("itemSource", 785,   { name = "Mageroyal", gather = "Herbalism", objects = { 1620, 3727 }, node = "Mageroyal", skill = 50, yield = 1.5 })
ns:Register("itemSource", 2450,  { name = "Briarthorn", gather = "Herbalism", objects = { 1621, 3729 }, node = "Briarthorn", skill = 70, yield = 1.5 })
ns:Register("itemSource", 3820,  { name = "Stranglekelp", gather = "Herbalism", objects = { 2045 }, node = "Stranglekelp", skill = 85, yield = 1.5 })
ns:Register("itemSource", 2453,  { name = "Bruiseweed", gather = "Herbalism", objects = { 1622, 3730 }, node = "Bruiseweed", skill = 100, yield = 1.5 })
ns:Register("itemSource", 3355,  { name = "Wild Steelbloom", gather = "Herbalism", objects = { 1623 }, node = "Wild Steelbloom", skill = 115, yield = 1.5 })
ns:Register("itemSource", 3356,  { name = "Kingsblood", gather = "Herbalism", objects = { 1624 }, node = "Kingsblood", skill = 125, yield = 1.5 })
ns:Register("itemSource", 3357,  { name = "Liferoot", gather = "Herbalism", objects = { 2041 }, node = "Liferoot", skill = 150, yield = 1.5 })
ns:Register("itemSource", 3821,  { name = "Goldthorn", gather = "Herbalism", objects = { 2046 }, node = "Goldthorn", skill = 170, yield = 1.5 })
ns:Register("itemSource", 3358,  { name = "Khadgar's Whisker", gather = "Herbalism", objects = { 2043 }, node = "Khadgar's Whisker", skill = 185, yield = 1.5 })
ns:Register("itemSource", 8831,  { name = "Purple Lotus", gather = "Herbalism", objects = { 142140 }, node = "Purple Lotus", skill = 210, yield = 1.5 })
ns:Register("itemSource", 8836,  { name = "Arthas' Tears", gather = "Herbalism", objects = { 142141 }, node = "Arthas' Tears", skill = 220, yield = 1.5 })
ns:Register("itemSource", 8838,  { name = "Sungrass", gather = "Herbalism", objects = { 142142 }, node = "Sungrass", skill = 230, yield = 1.5 })
ns:Register("itemSource", 8839,  { name = "Blindweed", gather = "Herbalism", objects = { 142143 }, node = "Blindweed", skill = 235, yield = 1.5 })
ns:Register("itemSource", 13464, { name = "Golden Sansam", gather = "Herbalism", objects = { 176583 }, node = "Golden Sansam", skill = 260, yield = 1.5 })
ns:Register("itemSource", 13465, { name = "Mountain Silversage", gather = "Herbalism", objects = { 176586 }, node = "Mountain Silversage", skill = 280, yield = 1.5 })

-- Silver, for the Engineering Silver Contact.
ns:Register("itemSource", 2775, { name = "Silver Ore", gather = "Mining", objects = { 1733, 105569 }, node = "Silver Vein", skill = 75, yield = 2 })
ns:Register("itemSource", 2842, { name = "Silver Bar", smelt = { from = 2775, n = 1, skill = 75, spell = "Smelt Silver" } })

-- Trade-goods vendor items (prices in copper, before reputation discounts).
ns:Register("itemSource", 2320,  { name = "Coarse Thread", vendor = true, price = 10 })
ns:Register("itemSource", 2321,  { name = "Fine Thread", vendor = true, price = 100 })
ns:Register("itemSource", 2324,  { name = "Bleach", vendor = true, price = 25 })
ns:Register("itemSource", 2604,  { name = "Red Dye", vendor = true, price = 50 })
ns:Register("itemSource", 4291,  { name = "Silken Thread", vendor = true, price = 500 })
ns:Register("itemSource", 6260,  { name = "Blue Dye", vendor = true, price = 50 })
ns:Register("itemSource", 6261,  { name = "Orange Dye", vendor = true, price = 1000 })
ns:Register("itemSource", 8343,  { name = "Heavy Silken Thread", vendor = true, price = 2000 })
ns:Register("itemSource", 14341, { name = "Rune Thread", vendor = true, price = 5000 })
ns:Register("itemSource", 4289,  { name = "Salt", vendor = true, price = 50 })
ns:Register("itemSource", 4340,  { name = "Gray Dye", vendor = true, price = 350 })
ns:Register("itemSource", 2325,  { name = "Black Dye", vendor = true, price = 1000 })
ns:Register("itemSource", 3371,  { name = "Empty Vial", vendor = true, price = 20 })
ns:Register("itemSource", 3372,  { name = "Leaded Vial", vendor = true, price = 200 })
ns:Register("itemSource", 8925,  { name = "Crystal Vial", vendor = true, price = 2500 })
ns:Register("itemSource", 6217,  { name = "Copper Rod", vendor = true, price = 124 })
ns:Register("itemSource", 2880,  { name = "Weak Flux", vendor = true, price = 100 })

-- Bought patterns, recipes, formulas and schematics.
ns:Register("itemSource", 14481, { name = "Pattern: Runecloth Gloves", vendor = true, price = 16000 }) -- Qia, Everlook (limited)
ns:Register("itemSource", 15725, { name = "Pattern: Wicked Leather Gauntlets", vendor = true, price = 12000 }) -- limited
ns:Register("itemSource", 15756, { name = "Pattern: Runic Leather Headband", vendor = true, price = 22000 }) -- Jase Farlane, Eastern Plaguelands (limited)
ns:Register("itemSource", 13477, { name = "Recipe: Superior Mana Potion", vendor = true, price = 12000 }) -- limited
ns:Register("itemSource", 13480, { name = "Recipe: Major Healing Potion", vendor = true, price = 15000 }) -- Everlook (limited)
ns:Register("itemSource", 11039, { name = "Formula: Enchant Cloak - Minor Agility", vendor = true, price = 800 }) -- limited
ns:Register("itemSource", 11101, { name = "Formula: Enchant Bracer - Lesser Strength", vendor = true, price = 2500 }) -- limited
ns:Register("itemSource", 20754, { name = "Formula: Lesser Mana Oil", vendor = true, price = 10000 })
ns:Register("itemSource", 16217, { name = "Formula: Enchant Shield - Greater Stamina", vendor = true, price = 12000 }) -- limited
ns:Register("itemSource", 16224, { name = "Formula: Enchant Cloak - Superior Defense", vendor = true, price = 20000 }) -- limited
ns:Register("itemSource", 16042, { name = "Schematic: Thorium Widget", vendor = true, price = 12000 }) -- limited
ns:Register("itemSource", 16047, { name = "Schematic: Thorium Tube", vendor = true, price = 16000 }) -- Xizzer Fizzbolt, Everlook (limited)

-- Made by an earlier step of the same profession.
ns:Register("itemSource", 2996,  { name = "Bolt of Linen Cloth", made = "Tailoring" })
ns:Register("itemSource", 2997,  { name = "Bolt of Woolen Cloth", made = "Tailoring" })
ns:Register("itemSource", 4305,  { name = "Bolt of Silk Cloth", made = "Tailoring" })
ns:Register("itemSource", 4339,  { name = "Bolt of Mageweave", made = "Tailoring" })
ns:Register("itemSource", 14048, { name = "Bolt of Runecloth", made = "Tailoring" })
ns:Register("itemSource", 4233,  { name = "Cured Medium Hide", made = "Leatherworking" })
ns:Register("itemSource", 4236,  { name = "Cured Heavy Hide", made = "Leatherworking" })
ns:Register("itemSource", 4246,  { name = "Fine Leather Belt", made = "Leatherworking" })
ns:Register("itemSource", 118,   { name = "Minor Healing Potion", made = "Alchemy" })
ns:Register("itemSource", 4357,  { name = "Rough Blasting Powder", made = "Engineering" })
ns:Register("itemSource", 4359,  { name = "Handful of Copper Bolts", made = "Engineering" })
ns:Register("itemSource", 4364,  { name = "Coarse Blasting Powder", made = "Engineering" })
ns:Register("itemSource", 4371,  { name = "Bronze Tube", made = "Engineering" })
ns:Register("itemSource", 4375,  { name = "Whirring Bronze Gizmo", made = "Engineering" })
ns:Register("itemSource", 4377,  { name = "Heavy Blasting Powder", made = "Engineering" })
ns:Register("itemSource", 4382,  { name = "Bronze Framework", made = "Engineering" })
ns:Register("itemSource", 10505, { name = "Solid Blasting Powder", made = "Engineering" })
ns:Register("itemSource", 10560, { name = "Unstable Trigger", made = "Engineering" })
ns:Register("itemSource", 10561, { name = "Mithril Casing", made = "Engineering" })
-- The Enchanting rods start from a Blacksmith's rod (or the Auction House).
ns:Register("itemSource", 6338,  { name = "Silver Rod" })
ns:Register("itemSource", 11128, { name = "Golden Rod" })
ns:Register("itemSource", 11144, { name = "Truesilver Rod" })
-- The tools single steps need, by name: a stop then reads "needs a Runed
-- Copper Rod" (not "item 6218"), and one with another item ID on this
-- client still counts as carried (SkillPlan matches by ID, else by name).
ns:Register("itemSource", 6218,  { name = "Runed Copper Rod" })
ns:Register("itemSource", 6339,  { name = "Runed Silver Rod" })
ns:Register("itemSource", 11130, { name = "Runed Golden Rod" })
ns:Register("itemSource", 11145, { name = "Runed Truesilver Rod" })
ns:Register("itemSource", 16207, { name = "Runed Arcanite Rod" })
ns:Register("itemSource", 10498, { name = "Gyromatic Micro-Adjustor" })

-- Annora teaches Artisan Enchanting, inside Uldaman.
ns:Register("npcIds", "artisan-trainers", { ["Annora"] = 11073 })

-------------------------------------------------------------------------------
-- Tailoring
-------------------------------------------------------------------------------

ns:Register("profGuide", "Tailoring", {
    kind = "craft",
    artisan = { Horde = "Daryl Stack", Alliance = "Timothy Worthington" },
    steps = {
        { recipe = "Bolt of Linen Cloth", item = 2996, learn = 1, yellow = 25, green = 37, grey = 50, mats = { [2589] = 2 }, use = { 1, 45 } },
        { recipe = "Linen Belt", item = 7026, learn = 15, yellow = 50, green = 67, grey = 85, mats = { [2996] = 1, [2320] = 1 }, use = { 45, 70 } },
        { recipe = "Reinforced Linen Cape", item = 2580, learn = 60, yellow = 85, green = 102, grey = 120, mats = { [2996] = 2, [2320] = 3 }, use = { 70, 75 } },
        { recipe = "Bolt of Woolen Cloth", item = 2997, learn = 75, yellow = 90, green = 97, grey = 105, mats = { [2592] = 3 }, use = { 75, 100 } },
        { recipe = "Simple Kilt", item = 10047, learn = 75, yellow = 100, green = 117, grey = 135, mats = { [2996] = 4, [2321] = 1 }, use = { 100, 110 } },
        { recipe = "Double-stitched Woolen Shoulders", item = 4314, learn = 110, yellow = 135, green = 152, grey = 170,
          mats = { [2997] = 3, [2321] = 2 }, use = { 110, 125 } },
        { recipe = "Bolt of Silk Cloth", item = 4305, learn = 125, yellow = 135, green = 140, grey = 145, mats = { [4306] = 4 }, use = { 125, 145 } },
        { recipe = "Azure Silk Hood", item = 7048, learn = 145, yellow = 155, green = 160, grey = 165, mats = { [4305] = 2, [6260] = 2, [2321] = 1 }, use = { 145, 160 } },
        { recipe = "Silk Headband", item = 7050, learn = 160, yellow = 170, green = 175, grey = 180, mats = { [4305] = 3, [2321] = 2 }, use = { 160, 170 } },
        { recipe = "Formal White Shirt", item = 4334, learn = 170, yellow = 180, green = 185, grey = 190,
          mats = { [4305] = 3, [2324] = 2, [2321] = 1 }, use = { 170, 175 } },
        { recipe = "Bolt of Mageweave", item = 4339, learn = 175, yellow = 180, green = 182, grey = 185, mats = { [4338] = 5 }, use = { 175, 185 } },
        { recipe = "Crimson Silk Vest", item = 7058, learn = 185, yellow = 205, green = 215, grey = 225,
          mats = { [4305] = 4, [2604] = 2, [2321] = 2 }, use = { 185, 205 } },
        { recipe = "Crimson Silk Pantaloons", item = 7062, learn = 195, yellow = 215, green = 225, grey = 235,
          mats = { [4305] = 4, [2604] = 2, [4291] = 2 }, use = { 205, 215 } },
        { recipe = "Orange Mageweave Shirt", item = 10056, learn = 215, yellow = 220, green = 225, grey = 230,
          mats = { [4339] = 1, [6261] = 1, [8343] = 1 }, use = { 215, 220 } },
        { recipe = "Black Mageweave Gloves", item = 10003, learn = 215, yellow = 230, green = 245, grey = 260, mats = { [4339] = 2, [8343] = 2 }, use = { 220, 230 } },
        { recipe = "Black Mageweave Headband", item = 10024, learn = 230, yellow = 245, green = 260, grey = 275, mats = { [4339] = 3, [8343] = 2 }, use = { 230, 250 } },
        { recipe = "Bolt of Runecloth", item = 14048, learn = 250, yellow = 255, green = 257, grey = 260, mats = { [14047] = 5 }, use = { 250, 260 } },
        { recipe = "Runecloth Belt", item = 13856, learn = 255, yellow = 270, green = 285, grey = 300, mats = { [14048] = 3, [14341] = 1 }, use = { 260, 280 } },
        -- Qia (Everlook) stocks one pattern at a time; Runecloth Belt to 300 is the fallback.
        { recipe = "Runecloth Gloves", item = 13863, learn = 275, yellow = 290, green = 305, grey = 320,
          mats = { [14048] = 4, [8170] = 4, [14341] = 1 }, use = { 280, 300 }, recipeItem = 14481 },
    },
})

-------------------------------------------------------------------------------
-- Leatherworking
-------------------------------------------------------------------------------

ns:Register("profGuide", "Leatherworking", {
    kind = "craft",
    artisan = { Horde = "Hahrana Ironhide", Alliance = "Drakk Stonehand" },
    steps = {
        { recipe = "Light Leather", item = 2318, learn = 1, yellow = 20, green = 30, grey = 40, mats = { [2934] = 3 }, use = { 1, 30 } },
        { recipe = "Light Armor Kit", item = 2304, learn = 1, yellow = 30, green = 45, grey = 60, mats = { [2318] = 1 }, use = { 30, 45 } },
        { recipe = "Cured Light Hide", item = 4231, learn = 35, yellow = 55, green = 65, grey = 75, mats = { [783] = 1, [4289] = 1 }, use = { 45, 55 } },
        { recipe = "Embossed Leather Gloves", item = 4239, learn = 55, yellow = 85, green = 100, grey = 115, mats = { [2318] = 3, [2320] = 2 }, use = { 55, 85 } },
        -- Keep the belts and Medium hides: Dark Leather Belt takes one of each at 135-150.
        { recipe = "Fine Leather Belt", item = 4246, learn = 80, yellow = 110, green = 125, grey = 140, mats = { [2318] = 6, [2320] = 2 }, use = { 85, 100 } },
        { recipe = "Cured Medium Hide", item = 4233, learn = 100, yellow = 115, green = 122, grey = 130, mats = { [4232] = 1, [4289] = 1 }, use = { 100, 115 } },
        { recipe = "Dark Leather Boots", item = 2315, learn = 100, yellow = 125, green = 137, grey = 150,
          mats = { [2319] = 4, [2321] = 2, [4340] = 1 }, use = { 115, 135 } },
        { recipe = "Dark Leather Belt", item = 4249, learn = 125, yellow = 150, green = 162, grey = 175,
          mats = { [4246] = 1, [4233] = 1, [2321] = 2, [4340] = 1 }, use = { 135, 150 } },
        { recipe = "Heavy Leather", item = 4234, learn = 150, yellow = 150, green = 155, grey = 160, mats = { [2319] = 5 }, use = { 150, 155 } },
        { recipe = "Cured Heavy Hide", item = 4236, learn = 150, yellow = 160, green = 165, grey = 170, mats = { [4235] = 1, [4289] = 3 }, use = { 155, 160 } },
        { recipe = "Heavy Armor Kit", item = 4265, learn = 150, yellow = 170, green = 180, grey = 190, mats = { [4234] = 5, [2321] = 1 }, use = { 160, 180 } },
        { recipe = "Barbaric Shoulders", item = 5964, learn = 175, yellow = 195, green = 205, grey = 215,
          mats = { [4234] = 8, [4236] = 1, [2321] = 2 }, use = { 180, 190 } },
        { recipe = "Guardian Gloves", item = 5966, learn = 190, yellow = 210, green = 220, grey = 230,
          mats = { [4234] = 4, [4236] = 1, [4291] = 1 }, use = { 190, 200 } },
        { recipe = "Thick Armor Kit", item = 8173, learn = 200, yellow = 220, green = 230, grey = 240, mats = { [4304] = 5, [4291] = 1 }, use = { 200, 220 } },
        { recipe = "Nightscape Headband", item = 8176, learn = 205, yellow = 225, green = 235, grey = 245, mats = { [4304] = 5, [4291] = 2 }, use = { 220, 230 } },
        { recipe = "Nightscape Pants", item = 8193, learn = 230, yellow = 250, green = 260, grey = 270, mats = { [4304] = 14, [4291] = 4 }, use = { 230, 250 } },
        { recipe = "Rugged Armor Kit", item = 15564, learn = 250, yellow = 250, green = 260, grey = 270, mats = { [8170] = 5 }, use = { 250, 260 } },
        { recipe = "Wicked Leather Gauntlets", item = 15083, learn = 260, yellow = 280, green = 290, grey = 300,
          mats = { [8170] = 8, [2325] = 1, [14341] = 1 }, use = { 260, 290 }, recipeItem = 15725 },
        -- The guide's Wicked Leather Headband is a world drop; this one is sold in Eastern Plaguelands.
        { recipe = "Runic Leather Headband", item = 15094, learn = 290, yellow = 310, green = 320, grey = 330,
          mats = { [8170] = 14, [14047] = 10, [14341] = 1 }, use = { 290, 300 }, recipeItem = 15756 },
    },
})

-------------------------------------------------------------------------------
-- Alchemy
-------------------------------------------------------------------------------

ns:Register("profGuide", "Alchemy", {
    kind = "craft",
    artisan = { Horde = "Rogvar", Alliance = "Kylanna Windwhisper" },
    steps = {
        -- Keep the Minor Healing Potions: Lesser Healing Potion takes one each.
        { recipe = "Minor Healing Potion", item = 118, learn = 1, yellow = 55, green = 75, grey = 95, mats = { [2447] = 1, [765] = 1, [3371] = 1 }, use = { 1, 60 } },
        { recipe = "Lesser Healing Potion", item = 858, learn = 55, yellow = 85, green = 105, grey = 125, mats = { [118] = 1, [2450] = 1 }, use = { 60, 110 } },
        { recipe = "Healing Potion", item = 929, learn = 110, yellow = 135, green = 155, grey = 175, mats = { [2453] = 1, [2450] = 1, [3372] = 1 }, use = { 110, 140 } },
        { recipe = "Lesser Mana Potion", item = 3385, learn = 120, yellow = 145, green = 165, grey = 185, mats = { [785] = 1, [3820] = 1, [3371] = 1 }, use = { 140, 155 } },
        { recipe = "Greater Healing Potion", item = 1710, learn = 155, yellow = 175, green = 195, grey = 215, mats = { [3357] = 1, [3356] = 1, [3372] = 1 }, use = { 155, 185 } },
        { recipe = "Elixir of Agility", item = 8949, learn = 185, yellow = 205, green = 225, grey = 245, mats = { [3820] = 1, [3821] = 1, [3372] = 1 }, use = { 185, 210 } },
        { recipe = "Elixir of Greater Defense", item = 8951, learn = 195, yellow = 215, green = 235, grey = 255, mats = { [3355] = 1, [3821] = 1, [3372] = 1 }, use = { 210, 215 } },
        { recipe = "Superior Healing Potion", item = 3928, learn = 215, yellow = 230, green = 250, grey = 270, mats = { [8838] = 1, [3358] = 1, [8925] = 1 }, use = { 215, 230 } },
        { recipe = "Elixir of Detect Undead", item = 9154, learn = 230, yellow = 245, green = 265, grey = 285, mats = { [8836] = 1, [8925] = 1 }, use = { 230, 250 } },
        { recipe = "Elixir of Greater Agility", item = 9187, learn = 240, yellow = 255, green = 275, grey = 295, mats = { [8838] = 1, [3821] = 1, [8925] = 1 }, use = { 250, 265 } },
        { recipe = "Superior Mana Potion", item = 13443, learn = 260, yellow = 275, green = 295, grey = 315,
          mats = { [8838] = 2, [8839] = 2, [8925] = 1 }, use = { 265, 285 }, recipeItem = 13477 },
        { recipe = "Major Healing Potion", item = 13446, learn = 275, yellow = 290, green = 310, grey = 330,
          mats = { [13464] = 2, [13465] = 1, [8925] = 1 }, use = { 285, 300 }, recipeItem = 13480 },
    },
})

-------------------------------------------------------------------------------
-- Enchanting
-------------------------------------------------------------------------------

-- Each enchant needs its rod in your bags (the lower rods don't stand in for
-- the higher ones), and most need an item to put the enchant on: any cheap
-- bracer, cloak, gloves, boots, chest or shield of the right slot.
ns:Register("profGuide", "Enchanting", {
    kind = "craft",
    artisan = { Horde = "Annora", Alliance = "Annora" },
    steps = {
        { recipe = "Runed Copper Rod", item = 6218, learn = 1, yellow = 5, green = 7, grey = 10, mats = { [6217] = 1, [10940] = 1, [10938] = 1 }, use = { 1, 2 } },
        { recipe = "Enchant Bracer - Minor Health", learn = 1, yellow = 70, green = 90, grey = 110, mats = { [10940] = 1 }, use = { 2, 90 }, tool = 6218 },
        { recipe = "Enchant Bracer - Minor Stamina", learn = 50, yellow = 100, green = 120, grey = 140, mats = { [10940] = 3 }, use = { 90, 100 }, tool = 6218 },
        { recipe = "Runed Silver Rod", item = 6339, learn = 100, yellow = 130, green = 150, grey = 170,
          mats = { [6338] = 1, [10940] = 6, [10939] = 3, [1210] = 1 }, use = { 100, 101 } },
        { recipe = "Greater Magic Wand", item = 11288, learn = 70, yellow = 110, green = 130, grey = 150, mats = { [4470] = 1, [10939] = 1 }, use = { 101, 110 }, tool = 6218 },
        { recipe = "Enchant Cloak - Minor Agility", learn = 110, yellow = 135, green = 155, grey = 175, mats = { [10998] = 1 },
          use = { 110, 135 }, recipeItem = 11039, tool = 6339 },
        { recipe = "Enchant Bracer - Lesser Stamina", learn = 130, yellow = 155, green = 175, grey = 195, mats = { [11083] = 2 }, use = { 135, 155 }, tool = 6339 },
        { recipe = "Runed Golden Rod", item = 11130, learn = 150, yellow = 175, green = 195, grey = 215,
          mats = { [11128] = 1, [5500] = 1, [11082] = 2, [11083] = 2 }, use = { 155, 156 } },
        { recipe = "Enchant Bracer - Lesser Strength", learn = 140, yellow = 165, green = 185, grey = 205, mats = { [11083] = 2 },
          use = { 156, 185 }, recipeItem = 11101, tool = 6339 },
        -- The Truesilver Rod goes in at 200, between the two Strength runs.
        { recipe = "Enchant Bracer - Strength", learn = 180, yellow = 200, green = 220, grey = 240, mats = { [11137] = 1 },
          use = { { 185, 200 }, { 201, 220 } }, tool = 11130 },
        { recipe = "Runed Truesilver Rod", item = 11145, learn = 200, yellow = 220, green = 240, grey = 260,
          mats = { [11144] = 1, [7971] = 1, [11135] = 2, [11137] = 2 }, use = { 200, 201 } },
        { recipe = "Enchant Cloak - Greater Defense", learn = 205, yellow = 225, green = 245, grey = 265, mats = { [11137] = 3 }, use = { 220, 225 }, tool = 11145 },
        { recipe = "Enchant Gloves - Agility", learn = 210, yellow = 230, green = 250, grey = 270, mats = { [11174] = 1, [11137] = 1 }, use = { 225, 230 }, tool = 11145 },
        { recipe = "Enchant Boots - Stamina", learn = 215, yellow = 235, green = 255, grey = 275, mats = { [11137] = 5 }, use = { 230, 235 }, tool = 11145 },
        { recipe = "Enchant Chest - Superior Health", learn = 220, yellow = 240, green = 260, grey = 280, mats = { [11137] = 6 }, use = { 235, 250 }, tool = 11145 },
        { recipe = "Lesser Mana Oil", item = 20747, learn = 250, yellow = 260, green = 270, grey = 280,
          mats = { [11176] = 3, [8831] = 2, [8925] = 1 }, use = { 250, 265 }, recipeItem = 20754, tool = 11145 },
        -- The guide's one Runed Arcanite Rod at 294 is left out: it costs an Arcanite
        -- Rod and a Golden Pearl for one point, and nothing on this route needs it.
        { recipe = "Enchant Shield - Greater Stamina", learn = 265, yellow = 285, green = 305, grey = 325, mats = { [11176] = 10 },
          use = { 265, 290 }, recipeItem = 16217, tool = 11145 },
        { recipe = "Enchant Cloak - Superior Defense", learn = 285, yellow = 305, green = 325, grey = 345, mats = { [16204] = 8 },
          use = { 290, 300 }, recipeItem = 16224, tool = 11145 },
    },
})

-------------------------------------------------------------------------------
-- Engineering
-------------------------------------------------------------------------------

-- The Blacksmith Hammer goes in your bags from the start; the Arclight
-- Spanner is made at 50 and needed by the steps that list it.
ns:Register("profGuide", "Engineering", {
    kind = "craft", tool = 5956,
    artisan = { Horde = "Buzzek Bracketswing", Alliance = "Buzzek Bracketswing" },
    steps = {
        { recipe = "Rough Blasting Powder", item = 4357, learn = 1, yellow = 20, green = 30, grey = 40, mats = { [2835] = 1 }, use = { 1, 30 } },
        { recipe = "Handful of Copper Bolts", item = 4359, learn = 30, yellow = 45, green = 52, grey = 60, mats = { [2840] = 1 }, use = { 30, 50 }, station = "anvil" },
        { recipe = "Arclight Spanner", item = 6219, learn = 50, yellow = 70, green = 80, grey = 90, mats = { [2840] = 6 }, use = { 50, 51 }, station = "anvil" },
        { recipe = "Rough Copper Bomb", item = 4360, learn = 30, yellow = 60, green = 75, grey = 90,
          mats = { [2840] = 1, [4359] = 1, [4357] = 2, [2589] = 1 }, use = { 51, 75 }, station = "anvil" },
        { recipe = "Coarse Blasting Powder", item = 4364, learn = 75, yellow = 85, green = 90, grey = 95, mats = { [2836] = 1 }, use = { 75, 90 } },
        { recipe = "Coarse Dynamite", item = 4365, learn = 75, yellow = 90, green = 97, grey = 105, mats = { [4364] = 3, [2589] = 1 }, use = { 90, 100 } },
        { recipe = "Silver Contact", item = 4404, learn = 90, yellow = 110, green = 125, grey = 140, mats = { [2842] = 1 }, use = { 100, 105 } },
        { recipe = "Bronze Tube", item = 4371, learn = 105, yellow = 105, green = 130, grey = 155, mats = { [2841] = 2, [2880] = 1 }, use = { 105, 125 }, station = "anvil" },
        { recipe = "Standard Scope", item = 4406, learn = 110, yellow = 135, green = 147, grey = 160, mats = { [4371] = 1, [1206] = 1 }, use = { 125, 135 }, tool = 6219 },
        { recipe = "Heavy Blasting Powder", item = 4377, learn = 125, yellow = 125, green = 135, grey = 145, mats = { [2838] = 1 }, use = { 135, 145 } },
        { recipe = "Whirring Bronze Gizmo", item = 4375, learn = 125, yellow = 125, green = 150, grey = 175, mats = { [2841] = 2, [2592] = 1 },
          use = { 145, 150 }, station = "anvil", tool = 6219 },
        { recipe = "Bronze Framework", item = 4382, learn = 145, yellow = 145, green = 170, grey = 195, mats = { [2841] = 2, [2319] = 1, [2592] = 1 }, use = { 150, 160 } },
        { recipe = "Explosive Sheep", item = 4384, learn = 150, yellow = 175, green = 187, grey = 200,
          mats = { [4382] = 1, [4375] = 1, [4377] = 2, [2592] = 2 }, use = { 160, 175 }, station = "anvil", tool = 6219 },
        -- Made once and kept: later schematics need it.
        { recipe = "Gyromatic Micro-Adjustor", item = 10498, learn = 175, yellow = 175, green = 195, grey = 215, mats = { [3859] = 4 }, use = { 175, 176 }, station = "anvil" },
        { recipe = "Solid Blasting Powder", item = 10505, learn = 175, yellow = 175, green = 185, grey = 195, mats = { [7912] = 2 }, use = { 176, 195 } },
        { recipe = "Mithril Tube", item = 10559, learn = 195, yellow = 195, green = 215, grey = 235, mats = { [3860] = 3 }, use = { 195, 200 }, station = "anvil" },
        { recipe = "Unstable Trigger", item = 10560, learn = 200, yellow = 200, green = 220, grey = 240,
          mats = { [3860] = 1, [4338] = 1, [10505] = 1 }, use = { 200, 215 }, station = "anvil", tool = 6219 },
        { recipe = "Mithril Casing", item = 10561, learn = 215, yellow = 215, green = 235, grey = 255, mats = { [3860] = 3 }, use = { 215, 238 }, station = "anvil", tool = 6219 },
        { recipe = "Hi-Explosive Bomb", item = 10562, learn = 235, yellow = 235, green = 255, grey = 275,
          mats = { [10561] = 2, [10560] = 1, [10505] = 2 }, use = { 238, 250 }, station = "anvil", tool = 6219 },
        { recipe = "Dense Blasting Powder", item = 15992, learn = 250, yellow = 250, green = 255, grey = 260, mats = { [12365] = 2 }, use = { 250, 260 } },
        { recipe = "Thorium Widget", item = 15994, learn = 260, yellow = 280, green = 290, grey = 300, mats = { [12359] = 3, [14047] = 1 },
          use = { 260, 285 }, recipeItem = 16042, station = "anvil", tool = 6219 },
        -- The guide's Thorium Shells schematic is a world drop; the Tube is sold in Everlook.
        { recipe = "Thorium Tube", item = 16000, learn = 275, yellow = 295, green = 305, grey = 315, mats = { [12359] = 6 },
          use = { 285, 300 }, recipeItem = 16047, station = "anvil", tool = 6219 },
    },
})
