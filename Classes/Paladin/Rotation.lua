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

local function hasBlessing()
    return A.Buff("player", function(n) return n and n:find("^Blessing of") end)
end

local buffs = {
    { spell = "Devotion Aura", kind = "buff", reason = "No aura",
      when = function() return not hasAura() end },
    { spell = "Blessing of Might", kind = "buff", reason = "No blessing",
      when = function(c) return not c.inCombat and not hasBlessing() end },
    -- Kings (Forever: baseline at 20) only if you don't have Might.
    { spell = "Blessing of Kings", kind = "buff", reason = "No blessing",
      when = function(c)
          return not c.inCombat and not hasBlessing() and not c.engine:Knows("Blessing of Might")
      end },
    -- Tanks use Seal of Fury (Forever, level 10); everyone else Righteousness.
    { spell = "Seal of Fury", kind = "buff", reason = "No seal (tanking)",
      when = function(c) return c.role == "tank" and (c.hostile or c.inCombat) and not hasSeal() end },
    { spell = "Seal of Righteousness", kind = "buff", reason = "No seal",
      when = function(c)
          local tankSeal = c.role == "tank" and c.engine:Knows("Seal of Fury")
          return not tankSeal and (c.hostile or c.inCombat) and not hasSeal()
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

ns:Register("rotation", "PALADIN", {
    -- Self-heals, considered before anything else (see Engine HealDecision).
    heals = { "Flash of Light", "Holy Light", "Word of Glory" },

    -- Default priority (first match wins).
    priority = join(buffs, melee, execute, singleTarget),

    -- Per fight type (see Modules/Fight/FightTypes.lua). Missing types use `priority`.
    priorities = {
        aoe = join(buffs, melee, aoe, execute, singleTarget),
        -- boss / elite: same as default for now. As fights get recorded, the
        -- profiler learns a separate order for each type anyway.
    },
})
