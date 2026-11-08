-- Druid rotation. Spells you don't know yet are skipped automatically, so
-- the list grows with you: a caster at first (Moonfire, Wrath), Bear Form
-- from 10, Cat Form from 20. What's suggested follows the form you're in.
--
-- Rule fields: spell, kind (damage/buff/heal), reason, target (needs a
-- hostile target in range), when = function(ctx) -> bool,
-- adaptive = true (part of a group the profiler may reorder; see Engine).

local _, ns = ...
local A = ns.api

local BEAR = { ["Bear Form"] = true, ["Dire Bear Form"] = true }
local function inCat() return A.Form() == "Cat Form" end
local function inBear() return BEAR[A.Form() or ""] == true end
-- Caster form: no form, or Moonkin. (Travel and Aquatic Form: nothing to cast.)
local function caster()
    local f = A.Form()
    return f == nil or f == "Moonkin Form"
end
local function inAnimal() return inCat() or inBear() end

-- Missing, or under `secs` left.
local function needBuff(name, secs)
    local up, left = A.Buff("player", name)
    return not up or left < secs
end
local function missingOnTarget(spell)
    local up = A.Debuff("target", spell)
    return not up
end

local buffs = {
    { spell = "Mark of the Wild", kind = "buff", reason = "Mark of the Wild missing or running out",
      when = function(c) return not c.inCombat and caster() and needBuff("Mark of the Wild", 60) end },
    { spell = "Thorns", kind = "buff", reason = "Thorns missing or running out",
      when = function(c) return not c.inCombat and caster() and needBuff("Thorns", 30) end },
}

-- Auto attack in Cat or Bear Form ("Attack" on older clients).
local melee = {
    { spell = "Attack", target = true, reason = "Start attacking",
      when = function(c) return c.hostile and inAnimal() and not A.IsCurrent("Attack") end },
    { spell = "Auto Attack", target = true, reason = "Start attacking",
      when = function(c) return c.hostile and inAnimal() and not A.IsCurrent("Auto Attack") end },
}

local cat = {
    { spell = "Ferocious Bite", target = true, reason = "Spend 4+ combo points",
      when = function(c) return c.hostile and inCat() and A.ComboPoints() >= 4 end },
    { spell = "Rip", target = true, reason = "Spend combo points (bleed)",
      when = function(c)
          return c.hostile and inCat() and A.ComboPoints() >= 4 and not c.engine:Knows("Ferocious Bite")
              and missingOnTarget("Rip")
      end },
    { spell = "Rake", target = true, reason = "Rake bleed missing",
      when = function(c) return c.hostile and inCat() and missingOnTarget("Rake") end },
    { spell = "Claw", target = true, reason = "Build combo points",
      when = function(c) return c.hostile and inCat() end },
}

local bear = {
    { spell = "Demoralizing Roar", reason = "Weaken what's hitting you",
      when = function(c) return c.inCombat and c.hostile and inBear() and missingOnTarget("Demoralizing Roar") end },
    { spell = "Maul", target = true, reason = "Maul on your next swing",
      when = function(c) return c.hostile and inBear() and not A.IsCurrent("Maul") end },
}

local bearAoe = {
    { spell = "Swipe", target = true, reason = "Several enemies",
      when = function(c) return c.hostile and inBear() end },
}

local casterDamage = {
    { spell = "Moonfire", target = true, reason = "Moonfire missing on the target",
      when = function(c) return c.hostile and caster() and missingOnTarget("Moonfire") end },
    { spell = "Wrath", target = true, reason = "Wrath",
      when = function(c) return c.hostile and caster() end },
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
    if k("Mark of the Wild") then add("  - Mark of the Wild on yourself (30 minutes).") end
    if k("Thorns") then add("  - Thorns on yourself (10 minutes): melee mobs hurt themselves.") end
    add("As a caster:")
    if k("Moonfire") then add("  1. Moonfire to open (instant, damage over time).") end
    if k("Wrath") then add("  2. Wrath until it dies; the cast key stays on Wrath for the fight.") end
    if k("Entangling Roots") then add("  - Entangling Roots a melee mob, step back, keep casting.") end
    if k("Bear Form") then
        add("Bear Form (tough pulls, several mobs):")
        if k("Demoralizing Roar") then add("  1. Demoralizing Roar.") end
        if k("Maul") then add("  2. Maul on every swing (the cast key stays on Maul).") end
        if k("Swipe") then add("  - Several enemies: Swipe.") end
    end
    if k("Cat Form") then
        add("Cat Form (fastest kills, no mana):")
        if k("Rake") then add("  1. Rake.") end
        if k("Claw") then add("  2. Claw to build combo points (the cast key stays on Claw).") end
        if k("Ferocious Bite") then add("  3. Ferocious Bite at 4-5 combo points.")
        elseif k("Rip") then add("  3. Rip at 4-5 combo points.") end
    end
    add("Healing (caster form):")
    if k("Rejuvenation") then add("  - Rejuvenation after a fight (instant, heals over time).") end
    if k("Healing Touch") then add("  - Healing Touch when hurt; mid-fight only when Flow flashes gold.") end
    if k("Regrowth") then add("  - Regrowth: quick heal plus a heal over time.") end
    return out
end

ns:Register("rotation", "DRUID", {
    guide = guide,

    -- Self-heals, considered before anything else (see Engine HealDecision).
    -- In Cat or Bear Form they're not usable, so they're skipped there.
    heals = { "Regrowth", "Healing Touch", "Rejuvenation" },
    afterFightHeals = { "Rejuvenation", "Healing Touch", "Regrowth" },

    -- What the cast key stays on for a fight (it can't change in combat):
    -- the form's main attack, so pressing it all fight keeps hitting.
    -- Moonfire, Rake and Roar show on the Flow icon to press yourself.
    pullLock = function(s, engine)
        if s and (s.kind == "heal" or s.kind == "emergency") then s = nil end
        if inCat() then
            if engine:Knows("Claw") then return "Claw" end
        elseif inBear() then
            if engine:Knows("Maul") then return "Maul" end
        elseif engine:Knows("Wrath") then
            return "Wrath"
        end
        return s and s.spell
    end,

    -- Default priority (first match wins).
    priority = join(buffs, melee, cat, bear, casterDamage),

    -- Per fight type (see Modules/Fight/FightTypes.lua). Missing types use `priority`.
    priorities = {
        aoe = join(buffs, melee, cat, bearAoe, bear, casterDamage),
    },
})
