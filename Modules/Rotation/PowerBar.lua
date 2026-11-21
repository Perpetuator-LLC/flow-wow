-------------------------------------------------------------------------------
-- Flow - Rotation/PowerBar.lua
-- What a spell is waiting for, on its icon (0.35.393).
--
-- "At the top of the easy buttons' icons, can we show what the energy bar
-- needs to do in order to cast it? A fill at the top of the icon, telling us
-- when we're going to be able to cast it: if we're waiting on mana, or energy
-- or rage, whatever our current form and whatever's preventing that from
-- being cast, we know the requirement, and we see ourselves trending
-- towards it."
--
-- A thin bar across the top of an icon: empty at none, full at what the
-- spell costs, in the colour of what it costs (mana blue, rage red, energy
-- yellow). It's on the target button's icon and the small icons beside it.
--   * While you have enough, there's no bar: only a spell that's waiting
--     shows one, filling as your mana, rage or energy comes in.
--   * In a fight this game hides those numbers from add-ons. The bar is the
--     game's own kind (a StatusBar), which may be handed a hidden number and
--     draws it without Flow reading it. Flow then can't tell "enough" from
--     "not yet", so the bar stays up and a full bar means ready.
-- "Show what a spell is waiting for on its icon" in Flow Settings (Easy
-- keys) turns it off.
-------------------------------------------------------------------------------

local _, ns = ...
local A = ns.api
local P = {}
ns.powerBar = P

P.COLORS = { [0] = { 0.3, 0.55, 1 }, [1] = { 1, 0.25, 0.2 }, [2] = { 1, 0.6, 0.2 }, [3] = { 1, 0.9, 0.25 } }
P.OTHER = { 0.8, 0.8, 0.8 }
P.KEEP = 1        -- seconds a spell's cost is remembered
P.SHARE = 0.1     -- the bar's height, as a share of the icon's
P.MIN = 3

function P.On() return not (ns.db and ns.db.actions and ns.db.actions.powerBar == false) end

-- Pure: what a spell costs, from the game's list of costs: { type, cost }.
--   costs: { { type, cost } }; safe(v) -> v, or nil when the game hides it
-- The first cost that isn't plainly nothing (a hidden cost counts: nil).
function P.Pick(costs, safe)
    for _, c in ipairs(type(costs) == "table" and costs or {}) do
        if type(c) == "table" and type(c.type) == "number" then
            local known = safe(c.cost)
            if known == nil or (type(known) == "number" and known > 0) then return { type = c.type, cost = c.cost, known = known } end
        end
    end
    return nil
end

-- Pure: does the bar show? cost, power: the numbers, nil where hidden.
-- Enough: no. Short, or can't tell: yes.
function P.Shows(cost, power)
    if type(cost) == "number" and type(power) == "number" then return power < cost end
    return true
end
-- Pure: how full, 0 to 1 (for the tests and the diagnostics; the bar itself is given the raw numbers).
function P.Fill(cost, power)
    if type(cost) ~= "number" or type(power) ~= "number" or cost <= 0 then return nil end
    return math.max(0, math.min(1, power / cost))
end
-- Pure: the bar's height on an icon this tall.
function P.Height(iconHeight) return math.max(P.MIN, math.floor((iconHeight or 0) * P.SHARE + 0.5)) end

local cache = {}
function P.CostOf(spell)
    local now = GetTime()
    local c = cache[spell]
    if c and now - c.at < P.KEEP then return c.cost end
    local get = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    local cost
    if get then
        local ok, costs = pcall(get, spell)
        if ok then cost = P.Pick(costs, A.Safe) end
    end
    cache[spell] = { at = now, cost = cost }
    return cost
end

local function build(host)
    local bar = CreateFrame("StatusBar", nil, host)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetFrameLevel((host:GetFrameLevel() or 1) + 4)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar.back = bar:CreateTexture(nil, "BACKGROUND")
    bar.back:SetAllPoints()
    bar.back:SetColorTexture(0, 0, 0, 0.7)
    bar:Hide()
    host.flowPower = bar
    return bar
end

-- Brings an icon's bar up to date for the step it shows. -> is the bar up?
function ns.PaintPower(host, s)
    if not host then return false end
    local bar = host.flowPower
    local c = s and s.spell and P.On() and P.CostOf(s.spell) or nil
    if not c then
        if bar then bar:Hide() end
        return false
    end
    local power = UnitPower("player", c.type)
    if not P.Shows(c.known, A.Safe(power)) then
        if bar then bar:Hide() end
        return false
    end
    bar = bar or build(host)
    -- (The raw numbers go to the game's own bar: either may be one Flow can't read.)
    local ok = pcall(function()
        bar:SetMinMaxValues(0, c.cost)
        bar:SetValue(power)
    end)
    if not ok then bar:Hide() return false end
    bar:SetHeight(P.Height(host:GetHeight()))
    local col = P.COLORS[c.type] or P.OTHER
    bar:SetStatusBarColor(col[1], col[2], col[3])
    bar:Show()
    return true
end

-- The small icons (the queue's, the modifiers'): after their status is painted.
do
    local paint = ns.PaintStatus
    if paint then
        function ns.PaintStatus(tex, timer, s, now, cd)
            local txt, tv = paint(tex, timer, s, now, cd)
            local host = tex and tex.GetParent and tex:GetParent()
            if host then pcall(ns.PaintPower, host, s) end
            return txt, tv
        end
    end
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck{ group = "key", label = "Show what a spell is waiting for on its icon",
        note = "(a bar filling with your mana, rage or energy)",
        tip = "A thin bar across the top of the target button's icon and the small icons beside it, while the spell there costs more mana, rage or energy than you have: it fills as that comes in. "
            .. "In a fight the game hides those numbers from add-ons, so the bar stays up and a full bar means ready.",
        get = function() return P.On() end,
        set = function(on)
            ns.db.actions = ns.db.actions or {}
            ns.db.actions.powerBar = on and true or false
        end }
end

function P.Lines()
    local out = { "power bars on the icons: " .. (P.On() and "on" or "off") }
    local f = _G.FlowRotationIcon
    local bar = f and f.flowPower
    out[#out + 1] = "  the target button's icon: " .. (f and (bar and (bar:IsShown() and "its bar is up" or "has a bar, not showing (enough for the spell, or no cost)") or "no bar made yet") or "not made yet")
    for _, t in ipairs({ { 0, "mana" }, { 1, "rage" }, { 3, "energy" } }) do
        local v = A.Safe(UnitPower("player", t[1]))
        out[#out + 1] = string.format("  your %s: %s", t[2], v == nil and "hidden from add-ons right now" or tostring(v))
    end
    return out
end
ns.commands.powerbar = function()
    for i, l in ipairs(P.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end
