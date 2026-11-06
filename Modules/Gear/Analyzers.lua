-- Special considerations: item value beyond plain stats. Each analyzer looks
-- at one item and returns a bonus per role, plus optional notes for the tooltip.
--
-- Most of these are PLACEHOLDERS: they show a note in the tooltip (so you can
-- see what isn't counted yet) but add 0 to the score. See docs/GEAR_PLAN.md
-- for how each one will be built. To add a consideration, register another
-- analyzer here.
--
-- Analyzer signature:
--   fn(item) -> { dps = n, heal = n, tank = n } or nil, { "note", ... } or nil
-- where item = { link, stats, equipLoc, classID, subclassID, minLevel, setID,
--                sellPrice, slots }  and G:TooltipLines(link) gives the tooltip text.

local _, ns = ...
local G = ns.gear or {}
ns.gear = G
-- Shorthand for ns:Register("gearAnalyzer", name, fn). Other files (e.g. a
-- class folder) can register their own considerations the same way.
function G:RegisterAnalyzer(name, fn)
    ns:Register("gearAnalyzer", name, fn)
end

-------------------------------------------------------------------------------
-- Tooltip text reader, for things the item API doesn't expose (weapon speed,
-- "Equip:" effects, "Unique", set names). English client text.
-------------------------------------------------------------------------------

local scanner
local lineCache = {}

-- Returns { {left = "...", right = "..."}, ... }
function G:TooltipLines(link)
    if lineCache[link] then return lineCache[link] end
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local data = C_TooltipInfo.GetHyperlink(link)
        for _, l in ipairs(data and data.lines or {}) do
            lines[#lines + 1] = { left = l.leftText or "", right = l.rightText or "" }
        end
    else
        if not scanner then
            scanner = CreateFrame("GameTooltip", "FlowScanTooltip", nil, "GameTooltipTemplate")
        end
        scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
        scanner:ClearLines()
        scanner:SetHyperlink(link)
        for i = 1, scanner:NumLines() do
            local l = _G["FlowScanTooltipTextLeft" .. i]
            local r = _G["FlowScanTooltipTextRight" .. i]
            lines[#lines + 1] = { left = l and l:GetText() or "", right = r and r:GetText() or "" }
        end
    end
    if #lines > 0 then lineCache[link] = lines end
    return lines
end

local function findLine(item, pattern)
    for _, l in ipairs(G:TooltipLines(item.link)) do
        local a = l.left:match(pattern) or l.right:match(pattern)
        if a then return a end
    end
end

-------------------------------------------------------------------------------
-- Weapon speed. Slow weapons hit harder per swing, which matters for
-- abilities that deal "weapon damage" (Paladin Seals/Judgement, Warrior
-- strikes) and for burst. Class data says which speed each role prefers:
--   classData.weaponSpeed = { dps = { prefer = "slow", why = "..." } }
-- Counted in the score (G.SpeedBonus), a little: speed tips the balance.
-------------------------------------------------------------------------------

-- Score bonus per role for a weapon speed: up to +/-1 (about one point of the
-- main stat), so speed tips the balance between similar weapons without
-- outweighing real stats. slow = 3.3 s or more, fast = 2.0 s or less.
function G.SpeedBonus(speed, prefer)
    if not (speed and prefer) then return 0 end
    local b
    if prefer == "slow" then b = (speed - 2.6) / 1.0
    elseif prefer == "fast" then b = (2.6 - speed) / 1.0
    else b = -math.abs(speed - 2.6) / 1.2 end
    return math.max(-1, math.min(1, b))
end

G:RegisterAnalyzer("weaponSpeed", function(item)
    if item.classID ~= 2 then return end
    local speed = tonumber(findLine(item, "Speed (%d+%.%d+)"))
    if not speed then return end
    local d = ns:ClassData()
    local prefs = d and d.weaponSpeed or {}
    local bonus = {}
    for _, role in ipairs(G.ROLES) do
        bonus[role] = G.SpeedBonus(speed, prefs[role] and prefs[role].prefer)
    end
    local role = ns:LevelingRole()
    local pref = prefs[role]
    local feel = speed >= 3.3 and "slow" or (speed <= 2.0 and "fast" or "medium")
    local note = string.format("Speed %.2f (%s)", speed, feel)
    if pref then
        note = note .. (pref.prefer == feel and (": good for " .. ns:RoleName(role))
            or (": " .. ns:RoleName(role) .. " prefers " .. pref.prefer))
            .. string.format(" (%+.1f score)", bonus[role])
    end
    return bonus, { note }
end)

-- Gem sockets. PLACEHOLDER: counted and noted, not valued yet.
G:RegisterAnalyzer("sockets", function(item)
    local n = 0
    for key, v in pairs(item.stats) do
        if key:find("^EMPTY_SOCKET_") then n = n + v end
    end
    if n > 0 then
        return nil, { string.format("%d gem socket(s): not scored yet", n) }
    end
end)

-- Set bonuses. PLACEHOLDER: will look at how many pieces you own and what
-- the next bonus is worth for each role.
G:RegisterAnalyzer("setBonus", function(item)
    if item.setID and item.setID > 0 then
        return nil, { "Part of a set: set bonus not scored yet" }
    end
end)

-- "Equip:", "Use:" and "Chance on hit:" effects that aren't plain stats.
-- PLACEHOLDER: noted; will convert to stat equivalents.
G:RegisterAnalyzer("equipEffects", function(item)
    local notes = {}
    for _, l in ipairs(G:TooltipLines(item.link)) do
        if l.left:find("^Equip:") or l.left:find("^Use:") or l.left:find("^Chance on hit:") then
            notes[#notes + 1] = "Has an effect: not scored yet"
            break
        end
    end
    return nil, notes
end)

-- Enchant on the item. PLACEHOLDER.
G:RegisterAnalyzer("enchant", function(item) end)

-- Armor type: e.g. mail before plate, or the armor-type bonus at higher
-- levels for wearing only your best type. PLACEHOLDER.
G:RegisterAnalyzer("armorType", function(item) end)

-- Resistances (fire/nature/...): only worth something for specific fights.
-- PLACEHOLDER.
G:RegisterAnalyzer("resistances", function(item) end)

-- "Unique" / "Unique-Equipped": can't wear two. PLACEHOLDER.
G:RegisterAnalyzer("unique", function(item) end)

-- Combos: two-hander vs one-hander + shield per role, stat caps (hit,
-- defense), talents that change stat value, synergy with gear you wear.
-- PLACEHOLDER.
G:RegisterAnalyzer("combos", function(item) end)
