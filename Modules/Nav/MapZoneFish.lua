-- Generated from Wowhead Classic zone fishing records (see MapZoneLevels.lua).
-- [uiMapID] = { records, { itemID, percent, "English name" }, ... }
local _, ns = ...
local ZL = ns.mapZoneLevels
if not ZL then return end

ZL.FISH = {
    [1426] = { 203, -- Dun Morogh
        { 6291, 50, "Raw Brilliant Smallfish" }, { 6289, 33, "Raw Longjaw Mud Snapper" } },
    [1429] = { 1169, -- Elwynn Forest
        { 6291, 54, "Raw Brilliant Smallfish" }, { 6289, 35, "Raw Longjaw Mud Snapper" }, { 19975, 3, "Zulian Mudskunk" } },
    [1420] = { 519, -- Tirisfal Glades
        { 6291, 32, "Raw Brilliant Smallfish" }, { 6303, 24, "Raw Slitherskin Mackerel" }, { 6289, 20, "Raw Longjaw Mud Snapper" }, { 6299, 10, "Sickly Looking Fish" }, { 6297, 4, "Old Skull" } },
    [1436] = { 444, -- Westfall
        { 6358, 60, "Oily Blackmouth" }, { 20708, 11, "Tightly Sealed Trunk" }, { 3820, 7, "Stranglekelp" }, { 20709, 6, "Rumsey Rum Light" }, { 6303, 4, "Raw Slitherskin Mackerel" }, { 6361, 3, "Raw Rainbow Fin Albacore" } },
    [1432] = { 428, -- Loch Modan
        { 21071, 48, "Raw Sagefish" }, { 6289, 13, "Raw Longjaw Mud Snapper" }, { 6317, 13, "Raw Loch Frenzy" }, { 20708, 8, "Tightly Sealed Trunk" }, { 6308, 4, "Raw Bristle Whisker Catfish" }, { 6291, 4, "Raw Brilliant Smallfish" } },
    [1421] = { 245, -- Silverpine Forest
        { 6358, 35, "Oily Blackmouth" }, { 6289, 20, "Raw Longjaw Mud Snapper" }, { 6291, 8, "Raw Brilliant Smallfish" }, { 6308, 8, "Raw Bristle Whisker Catfish" }, { 6299, 6, "Sickly Looking Fish" }, { 20708, 6, "Tightly Sealed Trunk" } },
    [1433] = { 624, -- Redridge Mountains
        { 6308, 51, "Raw Bristle Whisker Catfish" }, { 6289, 30, "Raw Longjaw Mud Snapper" }, { 1467, 8, "Spotted Sunfish" } },
    [1431] = { 259, -- Duskwood
        { 6308, 44, "Raw Bristle Whisker Catfish" }, { 6289, 36, "Raw Longjaw Mud Snapper" }, { 13889, 3, "Raw Whitescale Salmon" }, { 13890, 3, "Plated Armorfish" } },
    [1437] = { 626, -- Wetlands
        { 6359, 28, "Firefin Snapper" }, { 6358, 25, "Oily Blackmouth" }, { 6361, 23, "Raw Rainbow Fin Albacore" }, { 21113, 8, "Watertight Trunk" }, { 3820, 4, "Stranglekelp" }, { 21114, 3, "Rumsey Rum Dark" } },
    [1424] = { 1093, -- Hillsbrad Foothills
        { 21113, 25, "Watertight Trunk" }, { 21071, 22, "Raw Sagefish" }, { 6308, 12, "Raw Bristle Whisker Catfish" }, { 6358, 10, "Oily Blackmouth" }, { 6361, 9, "Raw Rainbow Fin Albacore" }, { 6289, 7, "Raw Longjaw Mud Snapper" } },
    [1416] = { 273, -- Alterac Mountains
        { 21153, 64, "Raw Greater Sagefish" }, { 21150, 11, "Iron Bound Trunk" }, { 8365, 4, "Raw Mithril Head Trout" }, { 3820, 3, "Stranglekelp" } },
    [1417] = { 224, -- Arathi Highlands
        { 6308, 56, "Raw Bristle Whisker Catfish" }, { 6362, 11, "Raw Rockscale Cod" }, { 8366, 4, "Bloated Trout" }, { 6359, 4, "Firefin Snapper" }, { 4603, 4, "Raw Spotted Yellowtail" } },
    [1434] = { 3355, -- Stranglethorn Vale
        { 6359, 28, "Firefin Snapper" }, { 6362, 22, "Raw Rockscale Cod" }, { 6358, 22, "Oily Blackmouth" }, { 3820, 9, "Stranglekelp" }, { 4603, 9, "Raw Spotted Yellowtail" }, { 8365, 8, "Raw Mithril Head Trout" } },
    [1435] = { 391, -- Swamp of Sorrows
        { 6362, 29, "Raw Rockscale Cod" }, { 8365, 22, "Raw Mithril Head Trout" }, { 4603, 9, "Raw Spotted Yellowtail" }, { 6308, 9, "Raw Bristle Whisker Catfish" }, { 13758, 9, "Raw Redgill" }, { 6358, 7, "Oily Blackmouth" } },
    [1425] = { 1032, -- The Hinterlands
        { 13758, 41, "Raw Redgill" }, { 13759, 21, "Raw Nightfin Snapper" }, { 8365, 9, "Raw Mithril Head Trout" }, { 6358, 8, "Oily Blackmouth" }, { 4603, 7, "Raw Spotted Yellowtail" } },
    [1422] = { 1829, -- Western Plaguelands
        { 13758, 44, "Raw Redgill" }, { 13759, 27, "Raw Nightfin Snapper" }, { 8365, 9, "Raw Mithril Head Trout" }, { 6358, 9, "Oily Blackmouth" } },
    [1423] = { 2893, -- Eastern Plaguelands
        { 13888, 32, "Darkclaw Lobster" }, { 13756, 14, "Raw Summer Bass" }, { 13422, 8, "Stonescale Eel" }, { 7973, 7, "Big-mouth Clam" }, { 13893, 6, "Large Raw Mightfish" }, { 13889, 6, "Raw Whitescale Salmon" } },
    [1430] = { 358, -- Deadwind Pass
        { 13759, 58, "Raw Nightfin Snapper" }, { 13758, 12, "Raw Redgill" }, { 13760, 12, "Raw Sunscale Salmon" }, { 13757, 8, "Lightning Eel" } },
    [1453] = { 1931, -- Stormwind City
        { 6289, 58, "Raw Longjaw Mud Snapper" }, { 6308, 23, "Raw Bristle Whisker Catfish" }, { 6291, 14, "Raw Brilliant Smallfish" } },
    [1458] = { 437, -- Undercity
        { 6289, 36, "Raw Longjaw Mud Snapper" }, { 6297, 14, "Old Skull" }, { 6299, 12, "Sickly Looking Fish" }, { 6291, 12, "Raw Brilliant Smallfish" }, { 6308, 11, "Raw Bristle Whisker Catfish" }, { 6522, 7, "Deviate Fish" } },
    [1438] = { 485, -- Teldrassil
        { 6303, 46, "Raw Slitherskin Mackerel" }, { 6291, 30, "Raw Brilliant Smallfish" }, { 6289, 17, "Raw Longjaw Mud Snapper" } },
    [1411] = { 399, -- Durotar
        { 6303, 66, "Raw Slitherskin Mackerel" }, { 6291, 13, "Raw Brilliant Smallfish" }, { 6289, 8, "Raw Longjaw Mud Snapper" }, { 6295, 3, "15 Pound Mud Snapper" }, { 6356, 3, "Battered Chest" } },
    [1412] = { 436, -- Mulgore
        { 6291, 53, "Raw Brilliant Smallfish" }, { 6289, 34, "Raw Longjaw Mud Snapper" } },
    [1439] = { 1535, -- Darkshore
        { 6361, 24, "Raw Rainbow Fin Albacore" }, { 6358, 18, "Oily Blackmouth" }, { 6303, 16, "Raw Slitherskin Mackerel" }, { 6717, 16, "Gaffer Jack" }, { 6289, 12, "Raw Longjaw Mud Snapper" }, { 6291, 4, "Raw Brilliant Smallfish" } },
    [1413] = { 1156, -- The Barrens
        { 6358, 41, "Oily Blackmouth" }, { 6289, 16, "Raw Longjaw Mud Snapper" }, { 6303, 13, "Raw Slitherskin Mackerel" }, { 6361, 10, "Raw Rainbow Fin Albacore" }, { 3820, 6, "Stranglekelp" }, { 6308, 6, "Raw Bristle Whisker Catfish" } },
    [1442] = { 755, -- Stonetalon Mountains
        { 6308, 41, "Raw Bristle Whisker Catfish" }, { 6289, 23, "Raw Longjaw Mud Snapper" }, { 6359, 15, "Firefin Snapper" }, { 21071, 6, "Raw Sagefish" }, { 3820, 4, "Stranglekelp" } },
    [1440] = { 662, -- Ashenvale
        { 6308, 40, "Raw Bristle Whisker Catfish" }, { 6289, 20, "Raw Longjaw Mud Snapper" }, { 6361, 11, "Raw Rainbow Fin Albacore" }, { 6358, 6, "Oily Blackmouth" } },
    [1441] = { 130, -- Thousand Needles
        { 8365, 38, "Raw Mithril Head Trout" }, { 6308, 18, "Raw Bristle Whisker Catfish" }, { 6289, 12, "Raw Longjaw Mud Snapper" }, { 6522, 11, "Deviate Fish" }, { 6291, 6, "Raw Brilliant Smallfish" }, { 6310, 6, "19 Pound Catfish" } },
    [1443] = { 387, -- Desolace
        { 6362, 20, "Raw Rockscale Cod" }, { 8365, 19, "Raw Mithril Head Trout" }, { 6308, 13, "Raw Bristle Whisker Catfish" }, { 6358, 12, "Oily Blackmouth" }, { 6359, 11, "Firefin Snapper" }, { 4603, 6, "Raw Spotted Yellowtail" } },
    [1445] = { 1529, -- Dustwallow Marsh
        { 6308, 33, "Raw Bristle Whisker Catfish" }, { 8365, 24, "Raw Mithril Head Trout" }, { 6362, 16, "Raw Rockscale Cod" }, { 6358, 7, "Oily Blackmouth" }, { 6359, 7, "Firefin Snapper" }, { 4603, 6, "Raw Spotted Yellowtail" } },
    [1444] = { 2344, -- Feralas
        { 6358, 22, "Oily Blackmouth" }, { 4603, 18, "Raw Spotted Yellowtail" }, { 6359, 16, "Firefin Snapper" }, { 8365, 14, "Raw Mithril Head Trout" }, { 13422, 12, "Stonescale Eel" }, { 6362, 5, "Raw Rockscale Cod" } },
    [1446] = { 3768, -- Tanaris
        { 4603, 28, "Raw Spotted Yellowtail" }, { 6359, 14, "Firefin Snapper" }, { 13422, 13, "Stonescale Eel" }, { 13754, 8, "Raw Glossy Mightfish" }, { 6362, 7, "Raw Rockscale Cod" }, { 13755, 7, "Winter Squid" } },
    [1447] = { 3647, -- Azshara
        { 13422, 38, "Stonescale Eel" }, { 7973, 15, "Big-mouth Clam" }, { 4603, 15, "Raw Spotted Yellowtail" }, { 6359, 7, "Firefin Snapper" }, { 6358, 3, "Oily Blackmouth" }, { 6522, 3, "Deviate Fish" } },
    [1448] = { 907, -- Felwood
        { 13758, 45, "Raw Redgill" }, { 13759, 29, "Raw Nightfin Snapper" }, { 6358, 11, "Oily Blackmouth" }, { 8365, 11, "Raw Mithril Head Trout" } },
    [1452] = { 160, -- Winterspring
        { 13902, 28, "18 Pound Salmon" }, { 13903, 9, "22 Pound Salmon" }, { 13760, 9, "Raw Sunscale Salmon" }, { 13889, 9, "Raw Whitescale Salmon" }, { 13890, 8, "Plated Armorfish" }, { 13891, 8, "Bloated Salmon" } },
    [1450] = { 3154, -- Moonglade
        { 13758, 46, "Raw Redgill" }, { 13759, 25, "Raw Nightfin Snapper" }, { 8365, 10, "Raw Mithril Head Trout" }, { 6358, 9, "Oily Blackmouth" }, { 6289, 3, "Raw Longjaw Mud Snapper" } },
    [1451] = { 210, -- Silithus
        { 13757, 62, "Lightning Eel" }, { 13758, 19, "Raw Redgill" }, { 6522, 3, "Deviate Fish" }, { 13443, 3, "Superior Mana Potion" } },
    [1454] = { 1167, -- Orgrimmar
        { 6289, 54, "Raw Longjaw Mud Snapper" }, { 6308, 19, "Raw Bristle Whisker Catfish" }, { 6291, 15, "Raw Brilliant Smallfish" }, { 6522, 3, "Deviate Fish" } },
    [1456] = { 584, -- Thunder Bluff
        { 6289, 51, "Raw Longjaw Mud Snapper" }, { 6308, 20, "Raw Bristle Whisker Catfish" }, { 6291, 13, "Raw Brilliant Smallfish" } },
    [1457] = { 182, -- Darnassus
        { 6289, 46, "Raw Longjaw Mud Snapper" }, { 6291, 14, "Raw Brilliant Smallfish" }, { 6308, 14, "Raw Bristle Whisker Catfish" } },
}
