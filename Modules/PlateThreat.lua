-- Your threat on each enemy's nameplate.
--
-- "Show my threat percentage on each enemy's nameplate so I know if I'm
-- losing threat on one." (0.35.248)
--
-- In a fight, in a group (or with a pet out), every enemy nameplate whose
-- threat list you're on gets a small number at its right: your threat as a
-- share of whoever it is attacking (the game's own figure, the same one the
-- Flow Meters show for your target). Its colour says where you stand, and
-- which way that reads depends on whether you're tanking:
--   tanking (a bear, a role of Tank)   green: it's on you
--                                      orange: on you, but someone has more threat: you're losing it
--                                      yellow: not on you, and you have more threat: nearly yours
--                                      red: not on you
--   anyone else                        grey: fine    yellow: you have more threat than the tank
--                                      red: it's on you
-- While it's on you, the number beside yours is whoever is closest behind
-- ("100% · Beryl 85%"), in a party (in a raid that's too many to ask about).
--
-- The game may hide threat numbers from add-ons in a fight ("secret" values:
-- they can be shown, not compared). Then the number is handed to the text as
-- it is, white, with nobody behind: Flow can't tell where you stand.
-- /flow threat says which it is; /flow threat on|off.

local _, ns = ...
local A = ns.api
local P = {}
ns.plateThreat = P

ns:OnLoad(function(saved) saved.plateThreat = saved.plateThreat or {} end)
local function cfg() return ns.db.plateThreat end
function P.On() return cfg().off ~= true end

P.TICK = 0.5         -- seconds between looks while you're in a fight
P.CHASERS_MAX = 5    -- ask who's behind you only in a group this small

-- Raised a little (0.35.273: "they overlap the level"), and for anyone not
-- tanking coloured by the share itself: "above 90% red, over 100% flashing
-- red, below that yellow, way below green."
P.RAISE = 12
P.OVER, P.HIGH, P.MID = 100, 90, 50
-- Pure: the band a share falls in.
function P.Band(pct)
    if type(pct) ~= "number" then return nil end
    if pct >= P.OVER then return "over" end
    if pct >= P.HIGH then return "high" end
    if pct >= P.MID then return "mid" end
    return "calm"
end
-- Pure: the look for a number. tank: Flow's tanking colours (there 100% is
-- where you want to be); else by the band; a hidden share: white.
--   -> colour key, flash?
function P.Look(state, pct, tank)
    if tank or type(pct) ~= "number" then return state, false end
    local band = P.Band(pct)
    return band, band == "over"
end

P.COLORS = {
    over    = { 1.00, 0.15, 0.15 },
    high    = { 1.00, 0.25, 0.25 },
    mid     = { 1.00, 0.90, 0.20 },
    calm    = { 0.35, 1.00, 0.35 },
    safe    = { 0.35, 1.00, 0.35 },
    losing  = { 1.00, 0.55, 0.10 },
    pulling = { 1.00, 0.90, 0.20 },
    lost    = { 1.00, 0.25, 0.25 },
    danger  = { 1.00, 0.25, 0.25 },
    low     = { 0.75, 0.75, 0.75 },
    hidden  = { 1.00, 1.00, 1.00 },
}

-- Pure: where you stand on one enemy.
--   status: the game's 0 to 3 (3: it's on you; 2: on you, someone has more
--   threat; 1: not on you, you have more than who it's on; 0: not on you),
--   nil when the game hides it. tank: you're the one meant to hold it.
function P.State(status, tank)
    if status == nil then return "hidden" end
    if tank then
        if status >= 3 then return "safe" end
        if status == 2 then return "losing" end
        if status == 1 then return "pulling" end
        return "lost"
    end
    if status >= 2 then return "danger" end
    if status == 1 then return "pulling" end
    return "low"
end

-- Pure: the words. mine: your share (a number, or nil); behind: { name, pct }
-- of whoever is closest behind you while it's on you (or nil).
function P.Text(mine, behind)
    if mine == nil then return "" end
    local text = string.format("%d%%", math.floor(mine + 0.5))
    if behind and behind.pct then
        text = text .. string.format(" · %s %d%%", tostring(behind.name or "?"), math.floor(behind.pct + 0.5))
    end
    return text
end

-- Pure: the one closest behind, from { { name, pct } } (readable numbers only).
function P.Closest(others)
    local best
    for _, o in ipairs(others or {}) do
        if type(o.pct) == "number" and (not best or o.pct > best.pct) then best = o end
    end
    return best
end

-- Are you the one meant to hold them? (A role of Tank, or a bear.)
function P.Tanking()
    local E = ns.rotation
    if not (E and E.UnitKind) then return false end
    local _, class = UnitClass("player")
    local assigned = A.Safe(UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")) or "NONE"
    return E.UnitKind(A.Safe(class), assigned, A.Safe(UnitPowerType("player"))) == "tank"
end

-- Shown at all? In a group, or with a pet (alone, everything is on you).
function P.Wanted()
    if not P.On() or not UnitDetailedThreatSituation then return false end
    if cfg().always then return true end
    return ((IsInGroup and IsInGroup()) or UnitExists("pet")) and true or false
end

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- The others in your party (and your pet), for "who's behind you".
local function others()
    local out = {}
    if IsInRaid and IsInRaid() then return out end
    for i = 1, 4 do
        if UnitExists("party" .. i) then out[#out + 1] = "party" .. i end
    end
    if UnitExists("pet") then out[#out + 1] = "pet" end
    return out
end

-- One enemy: { text, state } or nil (you're not on its threat list).
function P.Read(unit, tank)
    local ok, _, status, scaled, rawPct = pcall(UnitDetailedThreatSituation, "player", unit)
    if not ok then return nil end
    local pct = rawPct
    if pct == nil then pct = scaled end
    local hiddenStatus = isSecret(status)
    if not hiddenStatus and status == nil then return nil end
    local st = (not hiddenStatus) and status or nil
    local mine = A.Safe(pct)
    if type(mine) ~= "number" then
        -- Hidden: the game writes it where it will; Flow can't say more.
        if pct == nil then return nil end
        local okF, text = pcall(string.format, "%.0f%%", pct)
        return { text = okF and text or pct, state = P.State(st, tank), hidden = true }
    end
    local behind
    if st and st >= 2 then
        local list = {}
        local units = others()
        if #units <= P.CHASERS_MAX then
            for _, u in ipairs(units) do
                local okO, _, oStatus, oScaled, oRaw = pcall(UnitDetailedThreatSituation, u, unit)
                local oPct = oRaw
                if oPct == nil then oPct = oScaled end
                if okO and not isSecret(oStatus) and oStatus ~= nil then
                    list[#list + 1] = { name = A.Safe(UnitName(u)), pct = A.Safe(oPct) }
                end
            end
        end
        behind = P.Closest(list)
    end
    return { text = P.Text(mine, behind), state = P.State(st, tank), value = mine }
end

-------------------------------------------------------------------------------
-- On the nameplates
-------------------------------------------------------------------------------
local plates = {}   -- [unit] = true: the nameplates on screen

local function labelFor(plate)
    if plate.FlowThreat then return plate.FlowThreat end
    local f = CreateFrame("Frame", nil, plate)
    f:SetSize(1, 12)
    f:SetPoint("LEFT", plate, "RIGHT", 2, P.RAISE)   -- (clear of the level beside the name)
    f:SetFrameLevel(plate:GetFrameLevel() + 10)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    f.text:SetPoint("LEFT", f, "LEFT", 0, 0)
    plate.FlowThreat = f
    return f
end

local function hide(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if plate and plate.FlowThreat then plate.FlowThreat:Hide() end
end

P.shown = 0
local function update(unit, wanted, tank)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local r
    if wanted and ns.rotation.Yes(UnitCanAttack("player", unit), false) then r = P.Read(unit, tank) end
    if not r then
        if plate.FlowThreat then plate.FlowThreat:Hide() end
        return
    end
    local f = labelFor(plate)
    f.text:SetText(r.text)
    local key, flash = P.Look(r.state, r.value, tank)
    local c = P.COLORS[key] or P.COLORS.hidden
    f.text:SetTextColor(c[1], c[2], c[3])
    if flash ~= f.flashing and ns.pulse then
        f.flashing = flash
        if flash then ns.pulse.Add(f.text) else ns.pulse.Remove(f.text); f.text:SetAlpha(1) end
    end
    f:Show()
    P.shown = P.shown + 1
    P.lastState, P.lastHidden = r.state, r.hidden and true or false
end

function P.UpdateAll()
    local wanted = P.Wanted()
    local tank = wanted and P.Tanking()
    P.shown = 0
    for unit in pairs(plates) do
        local ok, err = pcall(update, unit, wanted, tank)
        if not ok then P.lastError = tostring(err) end
    end
end

local ticker
local function stop()
    if ticker then ticker:Cancel(); ticker = nil end
    for unit in pairs(plates) do pcall(hide, unit) end
    P.shown = 0
end
ns:On("PLAYER_REGEN_DISABLED", function()
    if ticker or not P.Wanted() then return end
    P.UpdateAll()
    ticker = C_Timer.NewTicker(P.TICK, P.UpdateAll)
end)
ns:On("PLAYER_REGEN_ENABLED", stop)
ns:On("NAME_PLATE_UNIT_ADDED", function(unit)
    plates[unit] = true
    if ticker then pcall(update, unit, P.Wanted(), P.Tanking()) else pcall(hide, unit) end
end)
ns:On("NAME_PLATE_UNIT_REMOVED", function(unit)
    plates[unit] = nil
    pcall(hide, unit)
end)
ns:On("UNIT_THREAT_LIST_UPDATE", function() if ticker then P.UpdateAll() end end)

-------------------------------------------------------------------------------
-- Settings, /flow threat, diagnostics
-------------------------------------------------------------------------------
function P.Set(on)
    cfg().off = (not on) or nil
    if not on then stop() end
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "screen",
        label = "Your threat on enemy nameplates",
        note = "(in a group, in a fight)",
        tip = "A small number at the right of each enemy's nameplate: your threat as a share of whoever it's attacking. "
            .. "Tanking, green means it's on you, orange that you're losing it, red that it's on someone else. "
            .. "Otherwise red means it's on you and yellow that you're about to take it. Enemy nameplates must be on (V).",
        get = function() return P.On() end,
        set = function(on) P.Set(on) end,
    })
end

function P.Lines()
    local n = 0
    for _ in pairs(plates) do n = n + 1 end
    local out = { string.format("threat on nameplates: %s; wanted now: %s; you're %s; %d nameplate(s) in view, %d with a number",
        P.On() and "on" or "off", tostring(P.Wanted()), P.Tanking() and "tanking" or "not tanking", n, P.shown) }
    out[#out + 1] = "  threat call: " .. (UnitDetailedThreatSituation and "there" or "missing")
        .. "; last number: " .. (P.lastState and (P.lastState .. (P.lastHidden and ", hidden by the game" or ", readable")) or "none yet")
    if P.lastError then out[#out + 1] = "  last error: " .. P.lastError end
    return out
end
ns.commands.threat = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then P.Set(arg == "on") end
    for i, l in ipairs(P.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
    print("  /flow threat on|off")
end
