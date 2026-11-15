-- Before you leave a zone: what's still to train or level here.
--
-- "I'm about to leave Mulgore and Flow should know that, because the route
-- is showing us that: make sure all trainings and professions that need to
-- happen in this area are met before we go on. I'd hate to get to the
-- Crossroads and realise my Herbalism or Skinning wasn't high enough."
-- (0.35.199)
--
-- When your next step is in another zone than the one you stand in, Flow
-- says once, in chat, what Flow Improvements still lists about training and
-- professions: spells to train, professions behind your level, a profession
-- tier to buy. It says it again only after you've been somewhere else.
-- It tells you; it doesn't hold the route back (Flow can't know which of
-- them you mean to do).

local _, ns = ...
local L = {}
ns.leaving = L

L.MAX = 6   -- lines at most

-- Pure: is an improvement about training or a profession?
function L.Counts(item)
    if type(item) ~= "table" or type(item.text) ~= "string" then return false end
    for _, what in ipairs(item.improves or {}) do
        if what == "Professions" then return true end
    end
    if item.goalKey == "train:class" or (type(item.goalKey) == "string" and item.goalKey:find("^train:")) then return true end
    return item.text:find("^Train ") ~= nil
end

-- Pure: the lines to say. items: Flow Improvements, in its order.
function L.Checklist(items, max)
    local out = {}
    for _, it in ipairs(items or {}) do
        if L.Counts(it) and #out < (max or L.MAX) then out[#out + 1] = it.text end
    end
    return out
end

-- Pure: say it now? here / next: the zone you're in and your next step's
-- (nil: unknown); said: the zone it was last said for.
function L.Due(here, next, said)
    if not (here and next) or here == next then return false end
    return said ~= here
end

local said   -- the zone the list was last given for
function L.Check()
    local N = ns.nav
    if not (N and N.plan and N.plan[1] and N.ZoneOf) or InCombatLockdown() then return false end
    local p = N:PlayerPos()
    local pt = N.plan[1].point
    local here, next = p and N.ZoneOf(p.map), pt and N.ZoneOf(pt.map)
    -- (Back in a zone after being away: it may be said again.)
    if here and said and said ~= here and here == next then said = nil end
    if not L.Due(here, next, said) then return false end
    said = here
    local Adv = ns.advisor
    local ok, shown = pcall(function() return Adv and Adv.Shown and (Adv:Shown()) or {} end)
    local lines = L.Checklist(ok and shown or {})
    if #lines == 0 then return false end
    ns:Print(string.format("your next step is in %s. Still to do before you leave %s:", N.ZoneNameOf(next), N.ZoneNameOf(here)))
    for i, l in ipairs(lines) do print("  " .. i .. ". " .. l) end
    print("  (Flow Improvements has the link to each.)")
    return true
end
function L._Forget() said = nil end   -- (tests)

if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, function() pcall(L.Check) end) end
