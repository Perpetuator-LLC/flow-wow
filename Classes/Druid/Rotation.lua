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
-- Not enough mana for Wrath (the game says so: "usable, but no mana").
local function outOfMana()
    local _, noMana = A.Usable("Wrath")
    return noMana == true
end

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

-- Entangling Roots holds a melee mob back while you cast (outdoors only: the
-- game says when it can't). Before the pull it's the opener the key casts
-- (the fight starts when it lands, then the key stays on Wrath); in a fight
-- it shows on the icon when the mob is on you again: press it on your bar.
-- Not on a caster mob (it has a mana pool: it casts from where it stands
-- anyway). Beasts and fighters report mana as their power with none of it.
function ns.MeleeMob(manaMax) return not (manaMax and manaMax > 0) end
local function meleeMob() return ns.MeleeMob(A.Safe(UnitPowerMax and UnitPowerMax("target", 0))) end
local function targetOnYou()
    return A.Safe(UnitIsUnit("targettarget", "player")) == true
end
local roots = {
    { spell = "Entangling Roots", target = true, reason = "Root it before it reaches you, then cast",
      when = function(c)
          return c.hostile and caster() and meleeMob() and missingOnTarget("Entangling Roots")
              and (not c.inCombat or targetOnYou())
      end },
}

local casterDamage = {
    { spell = "Moonfire", target = true, reason = "Moonfire missing on the target",
      when = function(c) return c.hostile and caster() and missingOnTarget("Moonfire") end },
    { spell = "Wrath", target = true, reason = "Wrath",
      when = function(c) return c.hostile and caster() end },
    -- Out of mana in caster form: hit it with your staff (in one 66 s fight
    -- Flow had nothing to suggest for 52 of 131 checks once the mana ran out).
    { spell = "Attack", target = true, reason = "Out of mana: hit it with your weapon",
      when = function(c) return c.hostile and caster() and outOfMana() and not A.IsCurrent("Attack") end },
    { spell = "Auto Attack", target = true, reason = "Out of mana: hit it with your weapon",
      when = function(c) return c.hostile and caster() and outOfMana() and not A.IsCurrent("Auto Attack") end },
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
    if k("Entangling Roots") then add("  1. Entangling Roots on a melee mob to open (the key casts it): it can't reach you.") end
    if k("Moonfire") then add("  2. Moonfire (instant, damage over time).") end
    if k("Wrath") then add("  3. Wrath until it dies; the cast key stays on Wrath for the fight.") end
    if k("Entangling Roots") then add("  - It comes for you again: Entangling Roots on your bar, step back, keep casting.") end
    if k("War Stomp") then add("  - It starts casting close to you: War Stomp on your bar stops it.") end
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

-- Your party or raid (Engine GroupBuff): Mark of the Wild for everyone,
-- Thorns for whoever takes the hits (a tank, or a warrior). Caster form only.
local groupBuffs = {
    canCast = caster,
    { spell = "Mark of the Wild", aura = { "Mark of the Wild", "Gift of the Wild" }, minutes = 30, rebuff = 60,
      who = function() return true end },
    { spell = "Thorns", minutes = 10, rebuff = 30,
      who = function(u) return u.kind == "tank" or u.class == "WARRIOR" end },
}

-- Curses and poisons on you or your group (Engine Dispel). Caster form only.
local dispels = {
    canCast = caster,
    { spell = "Remove Curse", types = { Curse = true } },
    { spell = "Abolish Poison", types = { Poison = true } },
    { spell = "Cure Poison", types = { Poison = true } },
}

ns:Register("rotation", "DRUID", {
    guide = guide,
    groupBuffs = groupBuffs,
    dispels = dispels,

    -- Self-heals, considered before anything else (see Engine HealDecision).
    -- In Cat or Bear Form they're not usable, so they're skipped there.
    heals = { "Regrowth", "Healing Touch", "Rejuvenation" },
    -- Heals over time: put on early (Engine EarlyHeal), counted as on you for
    -- their duration after you cast them.
    hots = { "Rejuvenation" },
    hotDuration = { Rejuvenation = 12 },

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

    -- The easy button's queue (Queue.lua): what Ctrl + key and Alt + key cast
    -- in a fight, for the form you're in at the pull (the first you know).
    -- Caster: Moonfire beside Wrath, Entangling Roots to hold a mob off you
    -- (War Stomp if you can't root yet). Cat: your finisher beside Claw (Rake
    -- until you have one). Bear: Swipe beside Maul, Bash to stop a cast.
    -- Shift + key is your heal; Alt is your healthstone or potion if you carry one.
    fightKeys = function()
        if inCat() then return { ctrl = { "Ferocious Bite", "Rip", "Rake" }, alt = {} } end
        if inBear() then return { ctrl = { "Swipe", "Demoralizing Roar" }, alt = { "Bash" } } end
        return { ctrl = { "Moonfire" }, alt = { "Entangling Roots", "War Stomp" } }
    end,

    -- Default priority (first match wins).
    priority = join(buffs, melee, cat, bear, roots, casterDamage),

    -- Per fight type (see Modules/Fight/FightTypes.lua). Missing types use `priority`.
    priorities = {
        aoe = join(buffs, melee, cat, bearAoe, bear, casterDamage),   -- (several mobs: no roots, they keep coming)
    },
})
