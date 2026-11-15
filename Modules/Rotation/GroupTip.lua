-- Your buffs for others, on a player's tooltip.
--
-- "When I hover over a party member it shows my buffs if they have them, but
-- not if they have a more powerful one (perhaps from someone else). Can we
-- show the buff whoever cast it, so I know if I need to buff them?"
-- (0.35.272)
--
-- The game's own party tooltip lists only the buffs YOU could have cast, by
-- its own filter, and leaves out a stronger or group version. Flow adds its
-- own lines to the tooltip of any friendly player, one per buff you give
-- others (the class's groupBuffs: Mark of the Wild, Thorns; a paladin's
-- blessings), read from everything that's on them, whoever cast it:
--   Mark of the Wild: has it (24 min)
--   Mark of the Wild: has Gift of the Wild (51 min)
--   Mark of the Wild: has a more powerful one       (the game refused yours)
--   Thorns: MISSING
--   Mark of the Wild: can't tell (the game hides their buffs)
-- Only buffs you know, and only the ones that fit the person (Thorns for a
-- tank). Setting: "Your buffs on a player's tooltip" (Flow Settings, In a
-- group).

local _, ns = ...
local A = ns.api
local T = {}
ns.groupTip = T

function T.On() return not (ns.db and ns.db.settings and ns.db.settings.groupTip == false) end

-- Pure: minutes or seconds left, in words ("24 min", "40 s"); "" when it
-- doesn't run out or isn't known.
function T.Left(seconds)
    if type(seconds) ~= "number" or seconds == math.huge or seconds <= 0 then return "" end
    if seconds >= 90 then return string.format(" (%d min)", math.floor(seconds / 60 + 0.5)) end
    return string.format(" (%d s)", math.floor(seconds + 0.5))
end

-- Pure: one buff's line and its kind ("has", "other", "stronger", "missing",
-- "hidden").
--   up: true / false / nil (the game won't say); left: seconds; found: the
--   buff's name on them (another name: a group or stronger version);
--   bounced: the game refused yours as weaker.
function T.Line(spell, up, left, found, bounced)
    if up == true then
        if found and found ~= spell then return string.format("%s: has %s%s", spell, found, T.Left(left)), "other" end
        return string.format("%s: has it%s", spell, T.Left(left)), "has"
    end
    if bounced then return spell .. ": has a more powerful one", "stronger" end
    if up == nil then return spell .. ": can't tell (the game hides their buffs)", "hidden" end
    return spell .. ": MISSING", "missing"
end

T.COLORS = {
    has = { 0.45, 1, 0.45 }, other = { 0.45, 1, 0.45 }, stronger = { 0.45, 1, 0.45 },
    missing = { 1, 0.35, 0.35 }, hidden = { 0.7, 0.7, 0.7 },
}

-- The lines for a unit: { { text, kind } }; none for yourself, an enemy, an
-- NPC, or when your class has no buffs for others.
function T.Lines(unit)
    local E = ns.rotation
    local def = E and E.Definition and E:Definition()
    local list = def and def.groupBuffs
    if not (list and unit and E.AuraOn) then return {} end
    local Yes = E.Yes
    if not (Yes(UnitExists(unit), false) and Yes(UnitIsPlayer(unit), false)) then return {} end
    if Yes(UnitIsUnit(unit, "player"), false) or not Yes(UnitIsFriend("player", unit), false) then return {} end
    local _, class = UnitClass(unit)
    class = A.Safe(class)
    local assigned = A.Safe(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) or "NONE"
    local u = { unit = unit, class = class, guid = A.Safe(UnitGUID(unit)), name = A.Safe(UnitName(unit)),
                kind = E.UnitKind(class, assigned, A.Safe(UnitPowerType(unit))) }
    local out, now = {}, GetTime()
    for _, rule in ipairs(list) do
        local okW, fits = pcall(rule.who, u)
        if E:Knows(rule.spell) and okW and fits then
            local names = {}
            for _, n in ipairs(rule.aura or { rule.spell }) do names[n] = true end
            local okA, up, left, found = pcall(E.AuraOn, unit, names)
            if not okA then up, left, found = nil, nil, nil end
            local text, kind = T.Line(rule.spell, up, left, found, E.Bounced and E.Bounced(u, rule.spell, now))
            out[#out + 1] = { text = text, kind = kind }
        end
    end
    return out
end

local function addLines(tt, unit)
    if not T.On() then return end
    local ok, lines = pcall(T.Lines, unit)
    if not ok or #lines == 0 then return end
    tt:AddLine("Your buffs for them:", 1, 0.82, 0.25)
    for _, l in ipairs(lines) do
        local c = T.COLORS[l.kind] or T.COLORS.hidden
        tt:AddLine("  " .. l.text, c[1], c[2], c[3])
    end
end
T._addLines = addLines   -- (tests)

local function unitOf(tt)
    if not tt.GetUnit then return nil end
    local ok, _, unit = pcall(tt.GetUnit, tt)
    unit = ok and A.Safe(unit) or nil
    return type(unit) == "string" and unit or nil
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt ~= GameTooltip then return end
        local unit = unitOf(tt)
        if unit then pcall(addLines, tt, unit) end
    end)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt)
        local unit = unitOf(tt)
        if unit then pcall(addLines, tt, unit) end
    end)
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "group",
        label = "Your buffs on a player's tooltip",
        note = "(has it, has a stronger one, missing)",
        tip = "Hover a friendly player: for each buff you give others, whether they have it (from anyone, a group or "
            .. "stronger version too), how long it lasts, or that it's missing.",
        get = function() return T.On() end,
        set = function(on)
            ns.db.settings = ns.db.settings or {}
            ns.db.settings.groupTip = on and true or false
        end,
    })
end
