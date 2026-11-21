-- Paladin rotation. Spells you don't know yet are skipped automatically,
-- so this list can grow ahead of your level. Covers both classic-style
-- names (Judgement, seals) and modern ones (Judgment, Crusader Strike).
--
-- Rule fields: spell, kind (damage/buff/heal), reason, target (needs a
-- hostile target in range), when = function(ctx) -> bool,
-- adaptive = true (part of a group the profiler may reorder; see Engine).

local _, ns = ...
local A = ns.api

local function hasSeal()
    return A.Buff("player", function(n) return n and n:find("^Seal of") end)
end

-- Every Classic Era / Forever seal, for /flow seal.
local SEALS = { "Seal of Righteousness", "Seal of the Crusader", "Seal of Command",
                "Seal of Justice", "Seal of Light", "Seal of Wisdom", "Seal of Fury" }

-- The last seal you cast (yourself, or with Flow's key) since your last fight
-- ended. Flow keeps suggesting it until you leave combat, so switching seals
-- for one fight is just casting the other one.
local ownSeal
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not spellID then return end
    local name = A.SpellInfo(spellID)   -- (Flow's own: the bare GetSpellInfo isn't on every client)
    if name and name:find("^Seal of") then ownSeal = name end
end)
ns:On("PLAYER_REGEN_ENABLED", function() ownSeal = nil end)

-- Your spec: the talent tree with the most points (tabs 1 Holy,
-- 2 Protection, 3 Retribution), or nil before you've spent any. Read again
-- only when your talents change.
local TREES = { "holy", "prot", "ret" }
local tree, treeRead
local function talentTree()
    if treeRead then return tree end
    treeRead, tree = true, nil
    if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return nil end
    local most = 0
    for tab = 1, math.min(GetNumTalentTabs() or 0, #TREES) do
        local points = 0
        for i = 1, GetNumTalents(tab) or 0 do
            points = points + (tonumber((select(5, GetTalentInfo(tab, i)))) or 0)
        end
        if points > most then tree, most = TREES[tab], points end
    end
    return tree
end
for _, event in ipairs({ "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_ENTERING_WORLD" }) do
    ns:On(event, function() treeRead = false end)
end

local function inGroup()
    if IsInGroup then return IsInGroup() and true or false end
    return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
end

-- The seal for your spec: Protection (or tanking) Fury, Retribution Command,
-- Holy in a group Wisdom; Righteousness otherwise, and until you know those.
local function specSeal(engine, role, spec, grouped)
    if (role == "tank" or spec == "prot") and engine:Knows("Seal of Fury") then return "Seal of Fury" end
    if spec == "ret" and engine:Knows("Seal of Command") then return "Seal of Command" end
    if (spec == "holy" or role == "heal") and grouped and engine:Knows("Seal of Wisdom") then return "Seal of Wisdom" end
    return "Seal of Righteousness"
end

-- Which seal Flow puts up: the one you cast this fight; else the one you
-- chose (settings, /flow seal), if you know it; else your spec's. `s` can
-- hold own / tree / grouped (tests; false = none); missing ones are read
-- from the game.
local function pickSeal(engine, role, s)
    s = s or {}
    local own = s.own
    if own == nil then own = ownSeal end
    if own and engine:Knows(own) then return own end
    local chosen = ns.db and ns.db.paladinSeal
    if chosen and engine:Knows(chosen) then return chosen end
    local spec = s.tree
    if spec == nil then spec = talentTree() end
    local grouped = s.grouped
    if grouped == nil then grouped = inGroup() end
    return specSeal(engine, role or (ns.LevelingRole and ns:LevelingRole()) or "dps", spec, grouped)
end

-- Your choice (a seal's name, or nil for automatic). A new choice applies
-- at once, even mid-fight.
local function setSeal(name)
    ns.db.paladinSeal = name
    ownSeal = nil
end

-- Seal missing or about to drop. In Forever, Judgement no longer uses up
-- the seal, so it only ends by running out: refresh it just before that
-- (a few seconds in combat; a little earlier right before a pull).
local function needSeal(c)
    local up, left = hasSeal()
    if not up then return true end
    return left < (c.inCombat and 3 or 8)
end

-- When to put a seal on: missing or running out at a pull or in a fight,
-- and also out of combat whenever you have none at all, so it's already up
-- when a fight starts. (A fight that started without one locked the key to
-- Judgement, which fails with no seal: "cast failed: Judgement" in the log.)
-- Not in inns and cities: the engine skips buffs while you're resting.
local function wantSeal(c)
    if c.hostile or c.inCombat then return needSeal(c) end
    return not hasSeal()
end

-- Blessing missing, or under 30 seconds left while you're out of combat.
local function needBlessing()
    local up, left = A.Buff("player", function(n) return n and n:find("^Blessing of") end)
    return not up or left < 30
end

-- Only your own paladin auras count (not e.g. a hunter's Trueshot Aura).
local PALADIN_AURAS = {
    ["Devotion Aura"] = true, ["Retribution Aura"] = true, ["Concentration Aura"] = true,
    ["Shadow Resistance Aura"] = true, ["Frost Resistance Aura"] = true,
    ["Fire Resistance Aura"] = true, ["Sanctity Aura"] = true, ["Crusader Aura"] = true,
}
local function hasAura()
    -- An active aura on the stance bar counts even if it isn't shown as a buff.
    for _, s in ipairs(A.StanceSpells()) do
        if s.active and PALADIN_AURAS[s.name] then return true end
    end
    return A.Buff("player", function(n) return PALADIN_AURAS[n] end)
end

local buffs = {
    { spell = "Devotion Aura", kind = "buff", reason = "No aura",
      when = function() return not hasAura() end },
    { spell = "Blessing of Might", kind = "buff", reason = "Blessing missing or running out",
      when = function(c) return not c.inCombat and needBlessing() end },
    -- Kings (Forever: baseline at 20) only if you don't have Might.
    { spell = "Blessing of Kings", kind = "buff", reason = "Blessing missing or running out",
      when = function(c)
          return not c.inCombat and needBlessing() and not c.engine:Knows("Blessing of Might")
      end },
}
-- One rule per seal; only the one pickSeal chooses can fire.
for _, seal in ipairs(SEALS) do
    buffs[#buffs + 1] = { spell = seal, kind = "buff", reason = "No seal, or running out",
        when = function(c) return wantSeal(c) and pickSeal(c.engine, c.role) == seal end }
end

-- Auto attack: suggested when you have a hostile target and aren't swinging.
-- Older clients call it "Attack", newer ones "Auto Attack"; only the one you
-- know is used.
local melee = {
    { spell = "Attack", target = true, reason = "Start attacking",
      when = function(c) return c.hostile and not A.IsCurrent("Attack") end },
    { spell = "Auto Attack", target = true, reason = "Start attacking",
      when = function(c) return c.hostile and not A.IsCurrent("Auto Attack") end },
}

local execute = {
    { spell = "Hammer of Wrath", target = true, reason = "Execute",
      when = function(c) return c.hostile end },
}

-- Roughly equal single-target hits: the profiler may reorder these.
local singleTarget = {
    { spell = "Judgement", target = true, reason = "Judge the seal", adaptive = true,
      -- Needs a seal up. (In Forever judging no longer uses the seal up.)
      when = function(c) return c.hostile and hasSeal() end },
    { spell = "Holy Strike", target = true, reason = "Holy Strike", adaptive = true,
      when = function(c) return c.hostile end },
    { spell = "Judgment", target = true, reason = "Judgment", adaptive = true,
      when = function(c) return c.hostile end },
    { spell = "Crusader Strike", target = true, reason = "Crusader Strike", adaptive = true,
      when = function(c) return c.hostile end },
    { spell = "Shield of the Righteous", target = true, reason = "Spend Holy Power", adaptive = true,
      when = function(c) return c.hostile end },
}

local aoe = {
    { spell = "Consecration", reason = "Several enemies",
      when = function(c) return c.inCombat end },
    { spell = "Holy Wrath", reason = "Several enemies",
      when = function(c) return c.inCombat end },
}

local function join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, rule in ipairs(list) do out[#out + 1] = rule end
    end
    return out
end

-- Plain-language rotation for /flow rot guide, using only spells you know.
local function guide(e)
    local k = function(s) return e:Knows(s) end
    local out = {}
    local function add(s) out[#out + 1] = s end
    add("Before a pull:")
    if k("Devotion Aura") then add("  - Devotion Aura on (stays on; it's on your stance bar).") end
    if k("Blessing of Might") then add("  - Blessing of Might (re-cast when under 30s left).") end
    local seal = pickSeal(e)
    if k(seal) then add("  - " .. seal .. ", cast just before you pull (change it: /flow seal).") end
    add("Fight:")
    if k("Judgement") then
        add("  1. Judgement to open (in Forever it doesn't use up your seal), then again on every cooldown.")
    end
    add("  2. Auto attack: keep swinging (Flow suggests Attack if you aren't).")
    if k("Holy Strike") then add("  3. Holy Strike on every cooldown.") end
    if k(seal) then add("  4. Refresh " .. seal .. " when it has ~3s left.") end
    if k("Hammer of Justice") then add("  - Hammer of Justice: stun a runner or buy time to heal.") end
    if k("Consecration") then add("  - Several enemies: Consecration (full damage on up to 4).") end
    add("Healing:")
    if k("Holy Light") then
        add("  - Holy Light between pulls, or mid-fight only when Flow flashes gold (heal now).")
    end
    if k("Divine Protection") then add("  - Divine Protection if a fight goes badly, then heal.") end
    if k("Lay on Hands") then add("  - Lay on Hands: last resort.") end
    return out
end

-- Your party or raid (Engine GroupBuff): one blessing each, the one that
-- helps them most. Kings for a tank; Might for melee (warriors, rogues,
-- paladins, a druid in Cat Form); Wisdom for casters, healers and hunters
-- (Might doesn't help ranged attacks); Kings for anyone else once you have it.
local function physical(u) return u.kind == "melee" or u.kind == "tank" end
local function usesMana(u) return u.kind == "caster" or u.kind == "healer" or u.kind == "ranged" end
local groupBuffs = {
    { spell = "Blessing of Kings", group = "blessing", minutes = 5, rebuff = 30,
      who = function(u) return u.kind == "tank" end },
    { spell = "Blessing of Might", group = "blessing", minutes = 5, rebuff = 30, who = physical },
    { spell = "Blessing of Wisdom", group = "blessing", minutes = 5, rebuff = 30, who = usesMana },
    { spell = "Blessing of Kings", group = "blessing", minutes = 5, rebuff = 30, who = function() return true end },
}

-- /flow seal [name|auto]: choose the seal Flow suggests (this character only).
ns:PerCharacter("paladinSeal")

local function findSeal(text)
    text = (text or ""):lower():gsub("^seal of%s*", ""):gsub("^the%s+", "")
    if text == "" then return nil end
    for _, s in ipairs(SEALS) do
        if s:lower():gsub("^seal of%s*", ""):gsub("^the%s+", ""):find(text, 1, true) == 1 then return s end
    end
end

ns.commands.seal = function(arg)
    arg = (arg or ""):match("^%s*(.-)%s*$")
    if arg:lower() == "auto" then
        setSeal(nil)
        ns:Print("seal: back to automatic (by your talents)")
        return
    end
    if arg ~= "" then
        local s = findSeal(arg)
        if not s then
            ns:Print("no seal called '" .. arg .. "'. Try: righteousness, crusader, command, justice, light, wisdom, fury, or auto")
            return
        end
        setSeal(s)
        local known = ns.api.KnownSpells()[s]
        ns:Print("seal: Flow now suggests " .. s
            .. (known and "" or " (you don't know it yet: Flow keeps its usual seal until you do)"))
        return
    end
    ns:Print("seal: " .. (ns.db.paladinSeal or "automatic")
        .. ". /flow seal <righteousness|crusader|command|justice|light|wisdom|fury|auto>")
end

ns:Register("help", "seal", { order = 32, title = "Paladin seal", lines = {
    "Automatic: by your talents. Retribution: Command; Protection (or tanking): Fury; Holy in a group: Wisdom; otherwise Righteousness.",
    "Cast a different seal and Flow keeps that one until the fight ends.",
    "Settings, Easy keys: \"Paladin seal\" picks one for good; or /flow seal command (righteousness, crusader, justice, light, wisdom, fury), /flow seal auto.",
} })

ns:Register("rotation", "PALADIN", {
    guide = guide,
    wantSeal = wantSeal,   -- (tests)
    pickSeal = pickSeal,   -- (tests)
    SetSeal = setSeal,     -- (settings)
    SEALS = SEALS,         -- (tests)
    groupBuffs = groupBuffs,
    -- Poisons, diseases (and magic, with Cleanse) on you or your group (Engine Dispel).
    dispels = {
        { spell = "Cleanse", types = { Poison = true, Disease = true, Magic = true } },
        { spell = "Purify", types = { Poison = true, Disease = true } },
    },

    -- Self-heals, considered before anything else (see Engine HealDecision).
    heals = { "Flash of Light", "Holy Light", "Word of Glory" },

    -- What the cast key stays on for a fight (it can't change in combat).
    -- The pull suggestion if it's a real attack; a seal only if you have none
    -- (Judgement needs one); otherwise Judgement, your main hit.
    pullLock = function(s, engine)
        -- A heal suggested at the pull is the after-fight prompt from the last
        -- fight: never lock the key to it for this one.
        if s and (s.kind == "heal" or s.kind == "emergency") then s = nil end
        if s and s.kind ~= "buff" and s.spell ~= "Attack" and s.spell ~= "Auto Attack" then return s.spell end
        if s and s.spell:find("^Seal of") and not hasSeal() then return s.spell end
        for _, spell in ipairs({ "Judgement", "Judgment", "Crusader Strike", "Holy Strike" }) do
            if engine:Knows(spell) then return spell end
        end
        return s and s.spell
    end,

    -- The target button's queue (Queue.lua): Ctrl + key is your next strike
    -- beside the key's own (the first you know that the key doesn't hold),
    -- Alt + key the stun that stops a cast. Shift + key is your heal; Alt is
    -- your healthstone or potion if you carry one.
    fightKeys = function()
        return { ctrl = { "Crusader Strike", "Holy Strike", "Judgement", "Judgment", "Shield of the Righteous", "Consecration", "Exorcism" },
                 alt = { "Hammer of Justice" } }
    end,

    -- Default priority (first match wins).
    priority = join(buffs, melee, execute, singleTarget),

    -- Per fight type (see Modules/Fight/FightTypes.lua). Missing types use `priority`.
    priorities = {
        aoe = join(buffs, melee, aoe, execute, singleTarget),
        -- boss / elite: same as default for now. As fights get recorded, the
        -- profiler learns a separate order for each type anyway.
    },
})
