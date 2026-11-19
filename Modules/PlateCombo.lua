-- Your combo points on your target's nameplate.
--
-- "Show combo points on the nameplates, or if there's already a native
-- option built into WoW that exposes that, make it one of the default Flow
-- options and turn it on for me." (0.35.333)
--
-- Newer versions of the game have their own setting for it (the class
-- resource shown on the target's nameplate, "nameplateResourceOnTarget").
-- Whether WoW: Forever has it, and whether it draws combo points there, isn't
-- known: /flow combo (and the diagnostics) say what the game answers. So Flow
-- draws its own, which needs nothing from the game but the nameplate and the
-- count, both of which Flow already reads:
--   * a row of small pips under your target's nameplate, one for each combo
--     point you can hold; the ones you have are lit (gold, red when full);
--   * only for a class that uses them now (a rogue; a druid in Cat Form),
--     with an enemy targeted whose nameplate is on screen;
--   * with no points yet the empty pips still show, so you see where they'll be.
-- It's on from the start. Off: Flow Settings (On your screen), /flow combo off.

local _, ns = ...
local A = ns.api
local PC = {}
ns.plateCombo = PC

PC.PIP, PC.GAP, PC.DROP = 9, 3, 3     -- a pip's size, the space between two, how far under the plate
PC.TICK = 0.2                         -- seconds between looks while it shows (the game's events come first)

ns:OnLoad(function(saved) saved.plateCombo = saved.plateCombo or {} end)
local function cfg() return ns.db.plateCombo or {} end
function PC.On() return cfg().off ~= true end

-- Pure: does this class use combo points right now?
function PC.Uses(class, form)
    if class == "ROGUE" then return true end
    return class == "DRUID" and form == "Cat Form"
end

-- Pure: show the pips? on: the setting; hostile: an enemy is targeted.
function PC.Wanted(on, class, form, hostile)
    return (on and hostile and PC.Uses(class, form)) and true or false
end

-- Pure: which pips are lit, and their colour. -> { bool, ... }, r, g, b
function PC.Pips(points, max)
    max = math.max(1, math.min(tonumber(max) or 5, 10))
    points = math.max(0, math.min(tonumber(points) or 0, max))
    local lit = {}
    for i = 1, max do lit[i] = i <= points end
    if points >= max then return lit, 1, 0.25, 0.2 end       -- full: spend them
    return lit, 1, 0.82, 0.1
end

-- Pure: how wide the row is.
function PC.Width(max, pip, gap)
    return max * (pip or PC.PIP) + (max - 1) * (gap or PC.GAP)
end

local function maxPoints()
    local n
    if UnitPowerMax and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
        local ok, v = pcall(UnitPowerMax, "player", Enum.PowerType.ComboPoints)
        n = ok and A.Safe(v) or nil
    end
    n = tonumber(n)
    return (n and n > 0) and n or 5
end

local function hostileTarget()
    local Yes = ns.rotation and ns.rotation.Yes
    if not Yes then return false end
    return Yes(UnitExists("target"), false) and Yes(UnitCanAttack("player", "target"), false) and not Yes(UnitIsDead("target"), false)
end

local bar
local function build()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(PC.Width(5), PC.PIP)
    f.pips = {}
    f:Hide()
    return f
end
local function pip(f, i)
    local p = f.pips[i]
    if p then return p end
    p = { back = f:CreateTexture(nil, "BACKGROUND"), fill = f:CreateTexture(nil, "ARTWORK") }
    p.back:SetSize(PC.PIP, PC.PIP)
    p.back:SetPoint("LEFT", f, "LEFT", (i - 1) * (PC.PIP + PC.GAP), 0)
    p.back:SetColorTexture(0, 0, 0, 0.8)
    p.fill:SetPoint("TOPLEFT", p.back, "TOPLEFT", 1, -1)
    p.fill:SetPoint("BOTTOMRIGHT", p.back, "BOTTOMRIGHT", -1, 1)
    f.pips[i] = p
    return p
end

local ticker
local function stop()
    if ticker then ticker:Cancel(); ticker = nil end
    if bar then bar:Hide() end
    PC.shown = false
end

-- Draws (or puts away) the pips for now.
function PC.Update()
    local _, class = UnitClass("player")
    local wanted = PC.Wanted(PC.On(), class, A.Form and A.Form() or nil, hostileTarget())
    local plate = wanted and C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target") or nil
    if not plate then
        if bar then bar:Hide() end
        PC.shown = false
        -- (No nameplate for it yet: keep looking while the target is there.)
        if not wanted then stop() end
        return false
    end
    bar = bar or build()
    local max = maxPoints()
    local lit, r, g, b = PC.Pips(A.ComboPoints(), max)
    for i = 1, math.max(#bar.pips, max) do
        local p = pip(bar, i)
        local there = i <= max
        p.back:SetShown(there)
        p.fill:SetShown(there)
        if there then
            if lit[i] then p.fill:SetColorTexture(r, g, b, 1) else p.fill:SetColorTexture(0.25, 0.25, 0.25, 0.9) end
        end
    end
    if bar.plate ~= plate or bar.max ~= max then
        bar.plate, bar.max = plate, max
        bar:SetParent(plate)
        bar:SetSize(PC.Width(max), PC.PIP)
        bar:ClearAllPoints()
        bar:SetPoint("TOP", plate, "BOTTOM", 0, -PC.DROP)
        bar:SetFrameLevel((plate:GetFrameLevel() or 0) + 10)
    end
    bar:Show()
    PC.shown, PC.last = true, A.ComboPoints()
    return true
end

local function refresh()
    local ok, err = pcall(PC.Update)
    if not ok then PC.lastError = tostring(err) end
    -- While there's an enemy targeted and this class uses them: keep looking
    -- (points can change with no event an add-on is sent).
    local _, class = UnitClass("player")
    local want = PC.Wanted(PC.On(), class, A.Form and A.Form() or nil, hostileTarget())
    if want and not ticker and C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(PC.TICK, function() pcall(PC.Update) end)
    elseif not want then
        stop()
    end
end
for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    ns:On(ev, refresh)
end
ns:On("NAME_PLATE_UNIT_ADDED", function(unit)
    if ns.rotation and ns.rotation.Yes and ns.rotation.Yes(UnitIsUnit(unit, "target"), false) then refresh() end
end)
ns:On("NAME_PLATE_UNIT_REMOVED", function()
    if bar and bar:IsShown() then refresh() end
end)
ns:On("UNIT_POWER_UPDATE", function(unit) if unit == "player" and PC.shown then pcall(PC.Update) end end)

function PC.Set(on)
    ns.db.plateCombo = ns.db.plateCombo or {}
    ns.db.plateCombo.off = (not on) or nil
    refresh()
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "screen",
        label = "Combo points on your target's nameplate",
        note = "(rogue; druid in Cat Form)",
        tip = "A row of small pips under your target's nameplate, one for each combo point you can hold; the ones you have are lit, and they turn red when full.",
        get = function() return PC.On() end,
        set = function(on) PC.Set(on) end,
    })
end

-- What the game's own setting for this answers (names only read).
function PC.Native()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local out = {}
    for _, name in ipairs({ "nameplateResourceOnTarget", "nameplateShowSelf", "nameplateShowEnemies" }) do
        local ok, v = pcall(get, name)
        out[#out + 1] = name .. " = " .. ((ok and v ~= nil) and tostring(v) or "not on this game")
    end
    return out
end

function PC.Lines()
    local _, class = UnitClass("player")
    local out = { string.format("combo points on the nameplate: %s; this class uses them now: %s; shown: %s; points: %d of %d", PC.On() and "on" or "off",
        tostring(PC.Uses(class, A.Form and A.Form() or nil)), tostring(PC.shown and true or false), A.ComboPoints(), maxPoints()) }
    out[#out + 1] = "  the game's own settings: " .. table.concat(PC.Native(), "; ")
    if PC.lastError then out[#out + 1] = "  last error: " .. PC.lastError end
    return out
end
ns.commands.combo = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        PC.Set(arg == "on")
        ns:Print("combo points on your target's nameplate: " .. arg)
        return
    end
    for i, l in ipairs(PC.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end
