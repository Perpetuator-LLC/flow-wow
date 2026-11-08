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
    -- Tanks use Seal of Fury (Forever, level 10); everyone else Righteousness.
    { spell = "Seal of Fury", kind = "buff", reason = "No seal, or running out (tanking)",
      when = function(c) return c.role == "tank" and wantSeal(c) end },
    { spell = "Seal of Righteousness", kind = "buff", reason = "No seal, or running out",
      when = function(c)
          local tankSeal = c.role == "tank" and c.engine:Knows("Seal of Fury")
          return not tankSeal and wantSeal(c)
      end },
}

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
    if k("Seal of Righteousness") then add("  - Seal of Righteousness, cast just before you pull.") end
    add("Fight:")
    if k("Judgement") then
        add("  1. Judgement to open (in Forever it doesn't use up your seal), then again on every cooldown.")
    end
    add("  2. Auto attack: keep swinging (Flow suggests Attack if you aren't).")
    if k("Holy Strike") then add("  3. Holy Strike on every cooldown.") end
    if k("Seal of Righteousness") then add("  4. Refresh Seal of Righteousness when it has ~3s left.") end
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

ns:Register("rotation", "PALADIN", {
    guide = guide,
    wantSeal = wantSeal,   -- (tests)

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

    -- Default priority (first match wins).
    priority = join(buffs, melee, execute, singleTarget),

    -- Per fight type (see Modules/Fight/FightTypes.lua). Missing types use `priority`.
    priorities = {
        aoe = join(buffs, melee, aoe, execute, singleTarget),
        -- boss / elite: same as default for now. As fights get recorded, the
        -- profiler learns a separate order for each type anyway.
    },
})
