-- Fight types: what kind of fight is this right now? Rotations can use a
-- different priority list per type, and the profiler learns separately for
-- each type, because a boss fight isn't a pack of trash.
--
-- Add a type:
--   ns:Register("fightType", "key", { order = n, label = "...", match = function(info) ... end })
-- Lower order is checked first; the first match wins. "normal" is the fallback.

local _, ns = ...
local F = {}
ns.fight = F

-- Enemies near you that are in combat, counted from nameplates.
local function enemyPlatesInCombat()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return 0 end
    local n = 0
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        -- Count only enemies fighting YOU, not ones fighting other players.
        if unit and UnitCanAttack("player", unit) and UnitAffectingCombat(unit) then
            local mine
            if UnitThreatSituation then
                mine = ns.api.Safe(UnitThreatSituation("player", unit)) ~= nil
            else
                mine = UnitIsUnit(unit .. "target", "player")
            end
            if mine then n = n + 1 end
        end
    end
    return n
end

function F:Info()
    local hasTarget = UnitExists("target") and UnitCanAttack("player", "target")
    return {
        classification = hasTarget and UnitClassification("target") or nil,
        targetLevel = hasTarget and UnitLevel("target") or nil,
        bossFrame = UnitExists("boss1"),
        attackers = math.max(ns.tracker and ns.tracker:AttackerCount() or 0, enemyPlatesInCombat()),
        inGroup = IsInGroup and IsInGroup() or (GetNumPartyMembers and GetNumPartyMembers() > 0),
        inInstance = select(2, IsInInstance()) ~= "none",
    }
end

local sorted
local function types()
    if not sorted then
        sorted = {}
        for key, def in ns:Each("fightType") do sorted[#sorted + 1] = { key = key, def = def } end
        table.sort(sorted, function(a, b) return (a.def.order or 100) < (b.def.order or 100) end)
    end
    return sorted
end

function F:Classify(info)
    if not info then
        local ok, i = pcall(self.Info, self)
        info = ok and i or { attackers = 0 }
    end
    for _, t in ipairs(types()) do
        local ok, hit = pcall(t.def.match, info)
        if ok and hit then return t.key end
    end
    return "normal"
end

function F:Label(key)
    local def = ns:Get("fightType", key)
    return def and def.label or key
end

-- Built-in types -------------------------------------------------------------

ns:Register("fightType", "boss", {
    order = 10, label = "Boss",
    match = function(i)
        -- A skull-level elite inside a dungeon is almost always a boss; a
        -- skull-level mob out in the world is just much higher level.
        local eliteSkull = i.targetLevel == -1 and i.inInstance
            and (i.classification == "elite" or i.classification == "rareelite")
        return i.bossFrame or i.classification == "worldboss" or eliteSkull
    end,
})

ns:Register("fightType", "aoe", {
    order = 20, label = "Several enemies",
    match = function(i) return i.attackers >= 3 end,
})

ns:Register("fightType", "elite", {
    order = 30, label = "Elite",
    match = function(i) return i.classification == "elite" or i.classification == "rareelite" end,
})

ns:Register("fightType", "normal", {
    order = 1000, label = "Normal mob",
    match = function() return true end,
})
