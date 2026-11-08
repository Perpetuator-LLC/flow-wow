-- Druid trainer spells: the level each first becomes trainable, and what it
-- improves. Used by the advisor to say "go train X, it improves A, B".
--
-- Levels are from Classic Era (1.12-style); not checked against Forever. The
-- advisor also learns the real list every time you open the trainer, and
-- that learned list wins over this one.

local _, ns = ...

ns:Register("classSpells", "DRUID", {
    { level = 1,  spell = "Wrath",                 improves = { "DPS" } },
    { level = 1,  spell = "Healing Touch",         improves = { "Healing", "Survival" } },
    { level = 1,  spell = "Mark of the Wild",      improves = { "Stats" } },
    { level = 4,  spell = "Moonfire",              improves = { "DPS" } },
    { level = 4,  spell = "Rejuvenation",          improves = { "Healing", "Survival" } },
    { level = 6,  spell = "Thorns",                improves = { "DPS", "Survival" } },
    { level = 8,  spell = "Entangling Roots",      improves = { "Control" } },
    { level = 10, spell = "Bear Form",             improves = { "Survival", "Threat" }, note = "class quest" },
    { level = 10, spell = "Demoralizing Roar",     improves = { "Survival" } },
    { level = 10, spell = "Growl",                 improves = { "Threat" } },
    { level = 10, spell = "Maul",                  improves = { "DPS", "Threat" } },
    { level = 10, spell = "Nature's Grasp",        improves = { "Control" } },
    { level = 12, spell = "Regrowth",              improves = { "Healing" } },
    { level = 12, spell = "Enrage",                improves = { "Threat" } },
    { level = 14, spell = "Bash",                  improves = { "Control" } },
    { level = 14, spell = "Cure Poison",           improves = { "Survival" } },
    { level = 16, spell = "Swipe",                 improves = { "DPS", "Threat" } },
    { level = 16, spell = "Aquatic Form",          improves = { "Travel" }, note = "class quest" },
    { level = 18, spell = "Faerie Fire",           improves = { "DPS" } },
    { level = 18, spell = "Hibernate",             improves = { "Control" } },
    { level = 20, spell = "Cat Form",              improves = { "DPS" } },
    { level = 20, spell = "Claw",                  improves = { "DPS" } },
    { level = 20, spell = "Rake",                  improves = { "DPS" } },
    { level = 20, spell = "Prowl",                 improves = { "Control" } },
    { level = 20, spell = "Starfire",              improves = { "DPS" } },
    { level = 20, spell = "Rebirth",               improves = { "Group" } },
    { level = 22, spell = "Shred",                 improves = { "DPS" } },
    { level = 24, spell = "Rip",                   improves = { "DPS" } },
    { level = 24, spell = "Tiger's Fury",          improves = { "DPS" } },
    { level = 24, spell = "Remove Curse",          improves = { "Survival" } },
    { level = 26, spell = "Dash",                  improves = { "Travel" } },
    { level = 30, spell = "Travel Form",           improves = { "Travel" } },
    { level = 30, spell = "Tranquility",           improves = { "Healing", "Group" } },
    { level = 32, spell = "Ferocious Bite",        improves = { "DPS" } },
    { level = 36, spell = "Pounce",                improves = { "DPS", "Control" } },
    { level = 36, spell = "Frenzied Regeneration", improves = { "Survival" } },
    { level = 40, spell = "Dire Bear Form",        improves = { "Survival", "Threat" } },
    { level = 40, spell = "Innervate",             improves = { "Mana" } },
    { level = 40, spell = "Hurricane",             improves = { "DPS" } },
})
