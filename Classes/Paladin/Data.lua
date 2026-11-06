-- Paladin class data shared by the spec, gear and (later) talent modules.
-- Roles map to the three colours used everywhere in Flow:
--   dps = red, heal = green, tank = blue

local _, ns = ...

ns:Register("class", "PALADIN", {
    specs = {
        dps  = { name = "Retribution" },
        heal = { name = "Holy" },
        tank = { name = "Protection" },
    },

    -- Recommended spec while levelling, and why.
    leveling = {
        role = "dps",
        -- Professions to pick up early (see the guide's Professions page).
        -- optional ones get a lower priority on the arrow.
        professions = {
            { name = "Mining" }, { name = "Blacksmithing" },
            { name = "First Aid" }, { name = "Cooking" },
            { name = "Fishing", optional = true },
        },
        why = {
            "Kills fastest solo: big two-handed weapon hits plus Seal and Judgement damage.",
            "Paladin self-heals and armor already make you hard to kill, so you don't need Protection to survive.",
            "Holy levels very slowly solo. Switch at max level, or if you mostly run dungeons as healer.",
        },
        -- Talent points in order, filled in once we confirm this client's talent tree.
        -- PLACEHOLDER: { {tab = 3, index = 2}, ... }
        talentPlan = {},
    },

    -- Stat weights per role: score = sum(stat * weight). The numbers are relative,
    -- tuned for levelling. Keys are the stat names the game's item API returns.
    weights = {
        dps = {
            ITEM_MOD_STRENGTH_SHORT = 1.0,
            ITEM_MOD_AGILITY_SHORT = 0.6,
            ITEM_MOD_STAMINA_SHORT = 0.35,
            ITEM_MOD_INTELLECT_SHORT = 0.2,
            ITEM_MOD_SPIRIT_SHORT = 0.1,
            ITEM_MOD_ATTACK_POWER_SHORT = 0.5,
            ITEM_MOD_CRIT_RATING_SHORT = 0.8,
            ITEM_MOD_HIT_RATING_SHORT = 0.9,
            ITEM_MOD_HASTE_RATING_SHORT = 0.6,
            ITEM_MOD_MASTERY_RATING_SHORT = 0.6,
            ITEM_MOD_VERSATILITY = 0.6,
            ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3.0,
            RESISTANCE0_NAME = 0.02,
        },
        heal = {
            ITEM_MOD_INTELLECT_SHORT = 1.0,
            ITEM_MOD_SPELL_HEALING_DONE_SHORT = 0.9,
            ITEM_MOD_SPELL_POWER_SHORT = 0.85,
            ITEM_MOD_MANA_REGENERATION_SHORT = 1.5,
            ITEM_MOD_SPIRIT_SHORT = 0.35,
            ITEM_MOD_STAMINA_SHORT = 0.3,
            ITEM_MOD_CRIT_RATING_SHORT = 0.6,
            ITEM_MOD_HASTE_RATING_SHORT = 0.7,
            ITEM_MOD_MASTERY_RATING_SHORT = 0.5,
            ITEM_MOD_VERSATILITY = 0.5,
            ITEM_MOD_STRENGTH_SHORT = 0.05,
            RESISTANCE0_NAME = 0.01,
        },
        tank = {
            ITEM_MOD_STAMINA_SHORT = 1.0,
            RESISTANCE0_NAME = 0.08,
            ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 1.2,
            ITEM_MOD_DODGE_RATING_SHORT = 1.0,
            ITEM_MOD_PARRY_RATING_SHORT = 0.9,
            ITEM_MOD_BLOCK_RATING_SHORT = 0.6,
            ITEM_MOD_BLOCK_VALUE_SHORT = 0.3,
            ITEM_MOD_STRENGTH_SHORT = 0.5,
            ITEM_MOD_AGILITY_SHORT = 0.4,
            ITEM_MOD_INTELLECT_SHORT = 0.25,
            ITEM_MOD_SPELL_POWER_SHORT = 0.3,
            ITEM_MOD_HIT_RATING_SHORT = 0.5,
            ITEM_MOD_VERSATILITY = 0.7,
            ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 0.6,
        },
    },

    -- Preferred weapon speed per role (see the weaponSpeed analyzer).
    weaponSpeed = {
        dps  = { prefer = "slow", why = "Seal and Judgement damage scales with damage per swing" },
        tank = { prefer = "medium", why = "steady swings for steady threat" },
        heal = { prefer = "medium", why = "speed barely matters; stats do" },
    },

    -- What the class can equip, by item class and subclass IDs.
    -- Armor (classID 4): 0 misc, 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram.
    -- Weapons (classID 2): 0/1 axes, 4/5 maces, 6 polearm, 7/8 swords.
    proficiency = {
        [4] = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true, [7] = true },
        -- 20 = fishing pole (anyone can use one).
        [2] = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [20] = true },
    },
})
