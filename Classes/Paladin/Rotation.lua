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

-- The seal you have up now (its name), or nil.
local function currentSeal()
    local name
    A.Buff("player", function(n)
        if n and n:find("^Seal of") then name = n return true end
    end)
    return name
end

-- Every Classic Era / Forever seal, for /flow seal.
local SEALS = { "Seal of Righteousness", "Seal of the Crusader", "Seal of Command",
                "Seal of Justice", "Seal of Light", "Seal of Wisdom", "Seal of Fury" }

-- Which seal Flow puts up: the one you chose (/flow seal), if you know it;
-- else the one you already have up (you cast it, so keep it); else Fury when
-- tanking; else Righteousness. engine:Knows, role and the seal up can be
-- passed in (tests); otherwise they're read from the game.
local function pickSeal(engine, role, up)
    local chosen = ns.db and ns.db.paladinSeal
    if chosen and engine:Knows(chosen) then return chosen end
    if up == nil then up = currentSeal() end
    if up and up ~= false then return up end
    if role == "tank" and engine:Knows("Seal of Fury") then return "Seal of Fury" end
    return "Seal of Righteousness"
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
-- One rule per seal; only the one pickSeal chooses can fire. (Tanks get
-- Seal of Fury, Forever level 10; everyone else Righteousness; /flow seal
-- or the seal you cast yourself overrides both.)
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
        ns.db.paladinSeal = nil
        ns:Print("seal: back to automatic (the seal you have up; else Fury when tanking, Righteousness otherwise)")
        return
    end
    if arg ~= "" then
        local s = findSeal(arg)
        if not s then
            ns:Print("no seal called '" .. arg .. "'. Try: righteousness, crusader, command, justice, light, wisdom, fury, or auto")
            return
        end
        ns.db.paladinSeal = s
        local known = ns.api.KnownSpells()[s]
        ns:Print("seal: Flow now suggests " .. s
            .. (known and "" or " (you don't know it yet: Flow keeps its usual seal until you do)"))
        return
    end
    ns:Print("seal: " .. (ns.db.paladinSeal or "automatic")
        .. ". /flow seal <righteousness|crusader|command|justice|light|wisdom|fury|auto>")
end

ns:Register("help", "seal", { order = 32, title = "Paladin seal", lines = {
    "/flow seal command (or righteousness, crusader, justice, light, wisdom, fury): the seal Flow suggests, for this character.",
    "/flow seal auto: back to automatic (keeps the seal you cast yourself; else Fury when tanking, Righteousness otherwise).",
} })

ns:Register("rotation", "PALADIN", {
    guide = guide,
    wantSeal = wantSeal,   -- (tests)
    pickSeal = pickSeal,   -- (tests)
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
