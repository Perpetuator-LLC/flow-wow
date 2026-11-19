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
-- count, both of which Flow already reads.
--
-- 0.35.334, how it looks: "I like the squares under the nameplate. They
-- should be right under the health bar, or under the energy or mana bar if
-- there is one, and look just like the experience bar where there's the
-- chunks: the full width of the default nameplate, five sections, each a
-- combo point, filling up as the points accrue, in the default colours the
-- game uses for combo points."
--   * one bar, as wide as the nameplate's health bar and right under it
--     (under its power bar when it shows one), with the game's bar texture,
--     a dark back and a thin dark edge, like the bars above it;
--   * cut into as many sections as you can hold points (five);
--   * filled a section a point, in the game's own combo point colour
--     (PowerBarColor.COMBO_POINTS).
-- Only for a class that uses them now (a rogue; a druid in Cat Form), with
-- an enemy targeted whose nameplate is on screen. Empty, the bar still shows.
-- (The sections are placed without measuring the nameplate: the game doesn't
-- let add-ons measure those. Each divider rides on an unseen bar filled to
-- that many points, so it sits where that many points end.)
-- It's on from the start. Off: Flow Settings (On your screen), /flow combo off.

local _, ns = ...
local A = ns.api
local PC = {}
ns.plateCombo = PC

PC.HEIGHT = 5                         -- the bar's height (a nameplate's health bar is about this)
PC.DROP = 1                           -- the gap under the bar above it
PC.WIDTH = 110                        -- its width when the nameplate's health bar can't be found
PC.TICK = 0.2                         -- seconds between looks while it shows (the game's events come first)
PC.TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
PC.COLOR = { 1.00, 0.96, 0.41 }       -- the game's combo point colour, where its own table doesn't say

ns:OnLoad(function(saved) saved.plateCombo = saved.plateCombo or {} end)
local function cfg() return ns.db.plateCombo or {} end
function PC.On() return cfg().off ~= true end

-- Pure: does this class use combo points right now?
function PC.Uses(class, form)
    if class == "ROGUE" then return true end
    return class == "DRUID" and form == "Cat Form"
end

-- Pure: show the bar? on: the setting; hostile: an enemy is targeted.
function PC.Wanted(on, class, form, hostile)
    return (on and hostile and PC.Uses(class, form)) and true or false
end

-- Pure: how full the bar is. -> points (0..max), max
function PC.Fill(points, max)
    max = math.max(1, math.min(tonumber(max) or 5, 10))
    return math.max(0, math.min(tonumber(points) or 0, max)), max
end

-- Pure: the bar's colour: the game's own for combo points, else Flow's copy of it.
--   colors: the game's PowerBarColor table (or nil)
function PC.BarColor(colors)
    local c = type(colors) == "table" and (colors.COMBO_POINTS or colors[4]) or nil
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return PC.COLOR[1], PC.COLOR[2], PC.COLOR[3]
end

-- Pure: what the bar hangs under: the nameplate's power bar when it shows
-- one, else its health bar, else the nameplate itself.
--   uf: the nameplate's unit frame (or nil); shown(frame) -> is it showing
--   -> frame, "power" | "health" | "plate"
function PC.Under(plate, uf, shown)
    if type(uf) == "table" then
        for _, key in ipairs({ "powerBar", "PowerBar", "manabar", "ManaBar" }) do
            local p = uf[key]
            if p and shown(p) then return p, "power" end
        end
        local h = uf.healthBar or uf.HealthBar
            or (type(uf.HealthBarsContainer) == "table" and (uf.HealthBarsContainer.healthBar or uf.HealthBarsContainer))
        if h and shown(h) then return h, "health" end
    end
    return plate, "plate"
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
    f:SetSize(PC.WIDTH, PC.HEIGHT)
    -- A thin dark edge and a dark back, like the bars above it.
    f.edge = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    f.edge:SetPoint("TOPLEFT", -1, 1); f.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    f.edge:SetColorTexture(0, 0, 0, 0.9)
    f.back = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.back:SetAllPoints()
    f.back:SetTexture(PC.TEXTURE)
    f.back:SetVertexColor(0.18, 0.17, 0.1, 0.9)
    f.fill = CreateFrame("StatusBar", nil, f)
    f.fill:SetAllPoints()
    f.fill:SetStatusBarTexture(PC.TEXTURE)
    f.marks = {}   -- unseen bars, one for each divider
    f.lines = CreateFrame("Frame", nil, f)
    f.lines:SetAllPoints()
    f.lines:SetFrameLevel(f.fill:GetFrameLevel() + 2)
    f.dividers = {}
    f:Hide()
    return f
end

-- The dividers for `max` sections: each at the end of an unseen bar filled to
-- that many points (no measuring).
local function sections(f, max)
    if f.max == max then return end
    f.max = max
    f.fill:SetMinMaxValues(0, max)
    for k = 1, math.max(#f.marks, max - 1) do
        local m = f.marks[k]
        if k <= max - 1 then
            if not m then
                m = CreateFrame("StatusBar", nil, f)
                m:SetAllPoints()
                m:SetStatusBarTexture(PC.TEXTURE)
                m:SetStatusBarColor(0, 0, 0, 0)
                f.marks[k] = m
                local d = f.lines:CreateTexture(nil, "OVERLAY")
                d:SetColorTexture(0, 0, 0, 1)
                d:SetWidth(1)
                local tex = m:GetStatusBarTexture()
                d:SetPoint("TOP", tex, "TOPRIGHT", 0, 0)
                d:SetPoint("BOTTOM", tex, "BOTTOMRIGHT", 0, 0)
                f.dividers[k] = d
            end
            m:SetMinMaxValues(0, max)
            m:SetValue(k)
            m:Show()
            f.dividers[k]:Show()
        elseif m then
            m:Hide()
            f.dividers[k]:Hide()
        end
    end
end

local ticker
local function stop()
    if ticker then ticker:Cancel(); ticker = nil end
    if bar then bar:Hide() end
    PC.shown = false
end

local function isShown(frame)
    local ok, v = pcall(function() return frame:IsShown() end)
    return ok and v and true or false
end

-- Draws (or puts away) the bar for now.
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
    local points, max = PC.Fill(A.ComboPoints(), maxPoints())
    sections(bar, max)
    bar.fill:SetValue(points)
    bar.fill:SetStatusBarColor(PC.BarColor(_G.PowerBarColor))
    local okU, under, what = pcall(PC.Under, plate, plate.UnitFrame, isShown)
    if not okU then under, what = plate, "plate" end
    if bar.under ~= under then
        bar.under, PC.under = under, what
        bar:SetParent(plate)
        bar:ClearAllPoints()
        if what == "plate" then
            -- (Its bars weren't found: a bar of Flow's own width under the nameplate.)
            bar:SetSize(PC.WIDTH, PC.HEIGHT)
            bar:SetPoint("TOP", plate, "BOTTOM", 0, -PC.DROP - 2)
        else
            -- As wide as the bar above it, right under it.
            bar:SetHeight(PC.HEIGHT)
            bar:SetPoint("TOPLEFT", under, "BOTTOMLEFT", 0, -PC.DROP - 1)
            bar:SetPoint("TOPRIGHT", under, "BOTTOMRIGHT", 0, -PC.DROP - 1)
        end
        bar:SetFrameLevel((plate:GetFrameLevel() or 0) + 10)
    end
    bar:Show()
    PC.shown, PC.last = true, points
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
        ticker = C_Timer.NewTicker(PC.TICK, function()
            local okT, errT = pcall(PC.Update)
            if not okT then PC.lastError = tostring(errT) end
        end)
    elseif not want then
        stop()
    end
end
for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    ns:On(ev, refresh)
end
ns:On("NAME_PLATE_UNIT_ADDED", function(unit)
    if ns.rotation and ns.rotation.Yes and ns.rotation.Yes(UnitIsUnit(unit, "target"), false) then
        if bar then bar.under = nil end   -- (a nameplate is handed out anew: hang the bar again)
        refresh()
    end
end)
ns:On("NAME_PLATE_UNIT_REMOVED", function()
    if bar and bar:IsShown() then bar.under = nil; refresh() end
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
        tip = "A bar under your target's health bar, as wide as it, cut into a section for each combo point you can hold and filled a section a point, in the game's combo point colour.",
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

-- What your target's nameplate is made of, by name (for hanging the bar).
function PC.PlateParts()
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
    if not plate then return "no nameplate for your target on screen" end
    local uf = plate.UnitFrame
    if type(uf) ~= "table" then return "the nameplate has no UnitFrame" end
    local names = {}
    for k, v in pairs(uf) do
        if type(k) == "string" and type(v) == "table" and (k:lower():find("bar") or k:lower():find("health") or k:lower():find("power")) then
            names[#names + 1] = k .. (isShown(v) and "" or " (hidden)")
        end
    end
    table.sort(names)
    return "its parts: " .. (#names > 0 and table.concat(names, ", "):sub(1, 300) or "none with bar, health or power in the name")
end

function PC.Lines()
    local _, class = UnitClass("player")
    local out = { string.format("combo points on the nameplate: %s; this class uses them now: %s; shown: %s; points: %d of %d; hung under: %s", PC.On() and "on" or "off",
        tostring(PC.Uses(class, A.Form and A.Form() or nil)), tostring(PC.shown and true or false), A.ComboPoints(), maxPoints(), tostring(PC.under or "nothing yet")) }
    out[#out + 1] = "  the game's own settings: " .. table.concat(PC.Native(), "; ")
    local okP, parts = pcall(PC.PlateParts)
    out[#out + 1] = "  your target's nameplate: " .. (okP and parts or ("unreadable: " .. tostring(parts)))
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
