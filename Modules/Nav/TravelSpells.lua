-- Spells that take you somewhere far: a druid's Teleport: Moonglade.
--
-- The Bear Form class quest sends a level 10 druid to Moonglade, at the far
-- end of Kalimdor. On foot that's thousands of yards through zones twenty
-- levels above them, so the route left the quest for last and the arrow never
-- went there ("Flow Improvements shows I need Bear Form, but the Flow Tracker
-- isn't having me go there"). A druid goes by Teleport: Moonglade. So:
--
--   ns:Register("travelSpell", "<spell name>", { map = uiMapID, class = "DRUID" })
--
-- A step on that map, while you're somewhere else and know the spell, counts
-- as one cast away: the planner measures it so (opts.port), the arrow and its
-- panel say "cast Teleport: Moonglade". When you don't know the spell yet,
-- the panel says where it comes from. One way only: the way back is on foot,
-- by hearthstone, or however the quest sends you.

local _, ns = ...
local TS = {}
ns.travelSpells = TS

TS.YARDS = 120   -- what a ten-second cast is worth, in running yards

-- (The classic map numbers; Moonglade is 1450.)
-- fly = false: no flight path leaves from where it lands (Moonglade's flight
-- masters only carry druids home: Rides.lua), so the travel graph (Transit.lua)
-- doesn't fly on from there.
ns:Register("travelSpell", "Teleport: Moonglade", { map = 1450, class = "DRUID", from = "your class trainer, from level 10", fly = false })
-- A mage's teleports (0.35.424): each lands in a city, with its flight master
-- a walk away. (Classic's names and levels; they need a Rune of Teleportation,
-- which Flow doesn't check.)
for name, map in pairs({ ["Teleport: Orgrimmar"] = 1454, ["Teleport: Undercity"] = 1458, ["Teleport: Thunder Bluff"] = 1456,
                         ["Teleport: Stormwind"] = 1453, ["Teleport: Ironforge"] = 1455, ["Teleport: Darnassus"] = 1457 }) do
    ns:Register("travelSpell", name, { map = map, class = "MAGE", from = "a portal trainer" })
end

-- Pure: the travel spell that reaches spot b from spot a, or nil. A spell
-- fits when b is in its zone and a isn't (you don't teleport across the
-- zone you're in).
--   spells: { { name, map, class } }; zoneOf(map) -> the zone a map is in;
--   class: yours ("DRUID")
function TS.Fits(a, b, spells, zoneOf, class)
    if not (a and b and b.map) then return nil end
    local za, zb = a.map and zoneOf(a.map) or nil, zoneOf(b.map)
    if not zb or za == zb then return nil end
    for _, s in ipairs(spells) do
        if (not s.class or s.class == class) and zoneOf(s.map) == zb then return s end
    end
    return nil
end

local function zoneOf(map)
    local G = ns.gates
    return (G and G.Region and G.Region(map)) or map
end

-- (Registered when the files load: read once.)
local list
local function all()
    if not list then
        list = {}
        for name, s in ns:Each("travelSpell") do list[#list + 1] = { name = name, map = s.map, class = s.class, from = s.from, fly = s.fly } end
    end
    return list
end

local function knows(name)
    return ns.nav and ns.nav.NeedMet and ns.nav.NeedMet("spell:" .. name) or false
end

-- From spot a to spot b: the spell to cast (you know it), or nil; and, when
-- one would fit but you don't know it, that spell as a second value.
function TS.Spell(a, b)
    local _, class = UnitClass("player")
    local s = TS.Fits(a, b, all(), zoneOf, class)
    if not s then return nil end
    if knows(s.name) then return s end
    return nil, s
end

-- The travel spells you know: { { name, map } } (Crossings.lua: a cast can
-- stand in for a zeppelin).
function TS.Mine()
    local _, class = UnitClass("player")
    local mine = {}
    for _, s in ipairs(all()) do
        if (not s.class or s.class == class) and knows(s.name) then mine[#mine + 1] = s end
    end
    return mine
end

-- The planner's answer for one plan: a step a cast away counts as near.
-- nil when you know no travel spell (then the planner needn't ask).
function TS.PlanPort()
    local _, class = UnitClass("player")
    local mine = {}
    for _, s in ipairs(all()) do
        if (not s.class or s.class == class) and knows(s.name) then mine[#mine + 1] = s end
    end
    if #mine == 0 then return nil end
    return function(a, b)
        return TS.Fits(a, b, mine, zoneOf, class) and TS.YARDS or nil
    end
end

-- A line for the arrow's panel, or nil: how to get to a far step.
function TS.Hint(a, b)
    local s, unknown = TS.Spell(a, b)
    if s then return "It's a long way: cast " .. s.name .. " to get there." end
    if unknown then
        return string.format("It's a long way on foot: %s takes you there (%s).", unknown.name, unknown.from or "your class trainer")
    end
    return nil
end
