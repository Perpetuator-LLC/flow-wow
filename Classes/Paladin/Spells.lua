-- Paladin trainer spells: the level each first becomes trainable, and what it
-- improves. Used by the advisor to say "go train X, it improves A, B".
--
-- Levels are from Classic Era (1.12-style) plus Forever changes reported by
-- guides; not checked against the live game. The advisor also learns the real
-- list every time you open the trainer, and that learned list wins over this one.
-- Forever notes: Judgement no longer consumes your seal; Consecration hits only
-- 4 targets at full damage; dual spec at 40.

local _, ns = ...

ns:Register("classSpells", "PALADIN", {
    { level = 1,  spell = "Holy Light",              improves = { "Healing", "Survival" } },
    { level = 1,  spell = "Seal of Righteousness",   improves = { "DPS" } },
    { level = 1,  spell = "Devotion Aura",           improves = { "Survival" } },
    { level = 4,  spell = "Blessing of Might",       improves = { "DPS" } },
    { level = 4,  spell = "Judgement",               improves = { "DPS" } },
    { level = 6,  spell = "Divine Protection",       improves = { "Survival" } },
    { level = 6,  spell = "Seal of the Crusader",    improves = { "DPS" } },
    -- Forever additions/changes (from Forever guides; [F] in the levelling notes):
    { level = 6,  spell = "Holy Strike",             improves = { "DPS" }, note = "new in Forever" },
    { level = 10, spell = "Seal of Fury",            improves = { "Threat" }, note = "new in Forever, tanking seal" },
    { level = 20, spell = "Consecration",            improves = { "DPS", "Threat" }, note = "baseline in Forever" },
    { level = 20, spell = "Blessing of Kings",       improves = { "Stats" }, note = "baseline in Forever" },
    { level = 8,  spell = "Hammer of Justice",       improves = { "Survival", "Control" } },
    { level = 8,  spell = "Purify",                  improves = { "Survival" } },
    { level = 10, spell = "Lay on Hands",            improves = { "Survival" } },
    { level = 10, spell = "Blessing of Protection",  improves = { "Survival", "Group" } },
    { level = 12, spell = "Redemption",              improves = { "Group" }, note = "class quest" },
    { level = 14, spell = "Blessing of Wisdom",      improves = { "Mana" } },
    { level = 16, spell = "Retribution Aura",        improves = { "DPS" } },
    { level = 16, spell = "Righteous Fury",          improves = { "Threat" } },
    { level = 18, spell = "Blessing of Freedom",     improves = { "Control" } },
    { level = 20, spell = "Exorcism",                improves = { "DPS" } },
    { level = 20, spell = "Flash of Light",          improves = { "Healing", "Mana" } },
    { level = 22, spell = "Seal of Justice",         improves = { "Control" } },
    { level = 22, spell = "Concentration Aura",      improves = { "Healing" } },
    { level = 24, spell = "Turn Undead",             improves = { "Control" } },
    { level = 26, spell = "Blessing of Salvation",   improves = { "Threat", "Group" } },
    { level = 30, spell = "Seal of Light",           improves = { "Survival" } },
    { level = 30, spell = "Divine Intervention",     improves = { "Group" } },
    { level = 34, spell = "Divine Shield",           improves = { "Survival" } },
    { level = 38, spell = "Seal of Wisdom",          improves = { "Mana" } },
    { level = 40, spell = "Summon Warhorse",         improves = { "Travel" }, note = "class quest / trainer" },
    { level = 42, spell = "Cleanse",                 improves = { "Survival", "Group" } },
    { level = 44, spell = "Hammer of Wrath",         improves = { "DPS" } },
    { level = 50, spell = "Holy Wrath",              improves = { "DPS" } },
})
