-- Druid class data shared by the spec, gear and (later) talent modules.
-- Roles map to the three colours used everywhere in Flow:
--   dps = red, heal = green, tank = blue
-- Levelling: a caster (Wrath, Moonfire) until Bear Form at 10, then Cat Form
-- at 20 does the killing. Feral covers both cat (dps) and bear (tank).

local _, ns = ...

ns:Register("class", "DRUID", {
    specs = {
        dps  = { name = "Feral (Cat)", icon = "Interface\\Icons\\Ability_Druid_CatForm" },
        heal = { name = "Restoration", icon = "Interface\\Icons\\Spell_Nature_HealingTouch" },
        tank = { name = "Feral (Bear)", icon = "Interface\\Icons\\Ability_Racial_BearForm" },
    },

    -- Recommended spec while levelling, and why.
    leveling = {
        role = "dps",
        -- Herbalism picks flowers on the way (and in Travel Form later);
        -- Alchemy turns them into potions. Optional ones rank lower.
        professions = {
            { name = "Herbalism" }, { name = "Alchemy" },
            { name = "First Aid" }, { name = "Cooking" },
            { name = "Fishing", optional = true },
        },
        why = {
            "Levels 1-9: you're a caster. Moonfire, then Wrath, and heal yourself between pulls.",
            "From 10, Bear Form takes hits for tough pulls; from 20, Cat Form kills fastest and needs no mana.",
            "Feral talents help both Cat and Bear. Balance and Restoration level slower solo (mana breaks).",
        },
        -- Talent points in order, filled in once we confirm this client's talent tree.
        -- PLACEHOLDER: { {tab = 2, index = 1}, ... }
        talentPlan = {},
    },

    -- Stat weights per role: score = sum(stat * weight). Relative numbers,
    -- tuned for levelling. Keys are the stat names the game's item API returns.
    weights = {
        dps = {
            ITEM_MOD_AGILITY_SHORT = 1.0,      -- cat: attack power and crit
            ITEM_MOD_STRENGTH_SHORT = 0.9,     -- cat: 2 attack power per point
            ITEM_MOD_STAMINA_SHORT = 0.35,
            ITEM_MOD_INTELLECT_SHORT = 0.3,    -- casting until 20, shifting costs mana
            ITEM_MOD_SPIRIT_SHORT = 0.15,
            ITEM_MOD_ATTACK_POWER_SHORT = 0.45,
            ITEM_MOD_CRIT_RATING_SHORT = 0.8,
            ITEM_MOD_HIT_RATING_SHORT = 0.8,
            ITEM_MOD_HASTE_RATING_SHORT = 0.5,
            ITEM_MOD_MASTERY_RATING_SHORT = 0.5,
            ITEM_MOD_VERSATILITY = 0.5,
            ITEM_MOD_SPELL_POWER_SHORT = 0.25,
            RESISTANCE0_NAME = 0.05,
        },
        heal = {
            ITEM_MOD_INTELLECT_SHORT = 1.0,
            ITEM_MOD_SPELL_HEALING_DONE_SHORT = 0.9,
            ITEM_MOD_SPELL_POWER_SHORT = 0.85,
            ITEM_MOD_MANA_REGENERATION_SHORT = 1.5,
            ITEM_MOD_SPIRIT_SHORT = 0.45,
            ITEM_MOD_STAMINA_SHORT = 0.3,
            ITEM_MOD_CRIT_RATING_SHORT = 0.5,
            ITEM_MOD_HASTE_RATING_SHORT = 0.7,
            ITEM_MOD_MASTERY_RATING_SHORT = 0.5,
            ITEM_MOD_VERSATILITY = 0.5,
            RESISTANCE0_NAME = 0.05,
        },
        tank = {
            ITEM_MOD_STAMINA_SHORT = 1.0,
            RESISTANCE0_NAME = 0.12,           -- Bear Form multiplies armor
            ITEM_MOD_AGILITY_SHORT = 0.7,      -- dodge and armor
            ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 1.0,
            ITEM_MOD_DODGE_RATING_SHORT = 1.0,
            ITEM_MOD_STRENGTH_SHORT = 0.5,
            ITEM_MOD_HIT_RATING_SHORT = 0.5,
            ITEM_MOD_ATTACK_POWER_SHORT = 0.25,
            ITEM_MOD_INTELLECT_SHORT = 0.15,
            ITEM_MOD_VERSATILITY = 0.7,
        },
    },

    keepItems = {},

    -- No weaponSpeed: in Cat or Bear Form your paws hit, not the weapon, so
    -- only its stats count (the speed analyzer then adds nothing).

    -- What the class can equip, by item class and subclass IDs.
    -- Armor (classID 4): 0 misc, 1 cloth, 2 leather, 8 idol.
    -- Weapons (classID 2): 4/5 maces, 6 polearm, 10 staff, 13 fist, 15 dagger, 20 fishing pole.
    proficiency = {
        [4] = { [0] = true, [1] = true, [2] = true, [8] = true },
        [2] = { [4] = true, [5] = true, [6] = true, [10] = true, [13] = true, [15] = true, [20] = true },
    },
})
