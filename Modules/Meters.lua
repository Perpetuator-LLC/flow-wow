-- Flow Meters: two small lists, threat on top of damage per second, each
-- three rows tall.
--
-- "I need to be able to see threat, so in a raid or party a small threat +
-- DPS meter would be awesome, shown at training dummies too. By default the
-- top, the second, and me; if I'm either of those, add the third. Allow
-- picking all 5 or 10, default 3; small enough to stack one on the other,
-- each 3 rows with the member and their amount; for DPS maybe a total of the
-- group." (0.35.211)
--
-- Where the numbers come from (both the game's own, nothing is counted from
-- a combat log, which this client doesn't give add-ons):
--   damage  C_DamageMeter.GetCombatSessionFromType(Current, DamageDone): one
--           entry per player, with its amount per second; whether an entry
--           is you is always readable (isLocalPlayer).
--   threat  UnitDetailedThreatSituation(unit, "target") for you and each
--           group member: the share of the tank's threat, in percent.
-- In a fight the game may hide the amounts (and the names) from add-ons:
-- "secret" values, which can be shown but not compared. Flow copes both ways:
--   readable  the rows are sorted here, biggest first;
--   hidden    the rows keep the order the game gives them (damage) or the
--             group's order (threat), and the hidden number is handed
--             straight to the text. /flow meters says which it is.
--
-- Shown in a group, and solo while your target is a training dummy. After a
-- fight the last numbers stay until the next one. Ctrl + drag moves them.
-- Flow menu, Flow windows: on or off, and 3, 5 or 10 rows.

local _, ns = ...
local A = ns.api
local M = {}
ns.meters = M
-- (A value the game may hide, as a yes or no: Engine.lua.)
local function Yes(v, unknown)
    v = A.Safe(v)
    if v == nil then return unknown end
    return v and true or false
end

M.ROW_H = 13
M.WIDTH = 150
M.HEAD_H, M.HEAD_ACCENT = 12, 3   -- each list's heading bar, and its orange accent
M.BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"   -- a plain colour: flat bars (0.35.257: "more flat")
M.ROWS = { 3, 5, 10 }

ns:OnLoad(function(saved) saved.meters = saved.meters or {} end)
local function cfg() return ns.db.meters end
function M.On() return cfg().off ~= true end
function M.RowCount()
    local n = tonumber(cfg().rows) or 3
    return (n == 5 or n == 10) and n or 3
end

-- How many players each list shows (0.35.258). "When we set it to 5 I'd
-- expect the group and then each individual: the total shouldn't count as
-- one of them. Compact really only needs the total and the other 2; 2 for
-- threat is enough." So the choice is players: compact (saved as 3, its old
-- name) shows 2, the others 5 or 10; the damage list has the group's row on
-- top of those, not among them.
-- Pure: players per list for a saved choice.
function M.PlayerRows(n)
    n = n or M.RowCount()
    return n == 3 and 2 or n
end
-- Pure: the choice's name in the menus.
function M.RowsLabel(n)
    return tostring(M.PlayerRows(n))
end

-- What stretch the second list counts over (0.35.258): this fight (it
-- starts again at every pull), or every fight since you last reset it (all
-- the damage over all the time in combat). Both are the game's own counts.
function M.SpanKey(saved) return saved == "all" and "all" or "fight" end
function M.SetSpan(key)
    cfg().span = (key == "all") and "all" or nil
    pcall(M.Update)
end
-- The game's name for it, or nil when this client keeps no such count.
function M.SessionType(span)
    local T = Enum and Enum.DamageMeterSessionType
    if not T then return nil end
    if span == "all" then return T.Overall end
    return T.Current
end
function M.Reset()
    local DM = C_DamageMeter
    if not (DM and DM.ResetAllCombatSessions) then return false end
    local ok = pcall(DM.ResetAllCombatSessions)
    pcall(M.Update)
    return ok
end

-- Pure: which entries of a list (best first, `count` long) to show in `rows`
-- rows. me: your place in it (nil: not in it). Three rows: the top two and
-- you; when you are one of those, the third. More rows: the top ones, with
-- you in the last row if you'd fall off the end.
function M.Pick(count, rows, me)
    local out = {}
    rows = math.min(rows or 3, count or 0)
    for i = 1, rows do out[i] = i end
    if me and me > rows and rows >= 1 then out[rows] = me end
    return out
end

-- Pure: "1.2k", "34.5k", "1.2m"; a number under a thousand to `decimals`
-- places (0: whole).
function M.Short(n, decimals)
    n = tonumber(n)
    if not n then return "" end
    if n >= 1e6 then return string.format("%.1fm", n / 1e6) end
    if n >= 1e4 then return string.format("%.0fk", n / 1e3) end
    if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
    return string.format("%." .. math.max(0, math.min(3, math.floor(tonumber(decimals) or 0))) .. "f", n)
end

-- Pure: sorts entries by .value (a number), biggest first; entries whose
-- value isn't readable keep their order, after the readable ones.
function M.Sort(list)
    local out = {}
    for i, e in ipairs(list or {}) do out[i] = e; e.order = i end
    table.sort(out, function(a, b)
        local av, bv = tonumber(a.value), tonumber(b.value)
        if av and bv and av ~= bv then return av > bv end
        if (av ~= nil) ~= (bv ~= nil) then return av ~= nil end
        return a.order < b.order
    end)
    return out
end

-- Pure: is this a training dummy's name?
function M.IsDummy(name)
    return type(name) == "string" and name:lower():find("dummy", 1, true) ~= nil
end

-------------------------------------------------------------------------------
-- Reading the game
-------------------------------------------------------------------------------
local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.6
end

-- What the second list counts (0.35.249: "RMB and select total damage, HPS
-- and total healing"): the game's own figures for this fight. kind: the
-- game's Enum.DamageMeterType name; field: per second, or the whole amount.
M.MODES = {
    dps     = { title = "DPS",     menu = "Damage per second (DPS)",  kind = "DamageDone",  field = "amountPerSecond", empty = "no damage yet" },
    damage  = { title = "Damage",  menu = "Total damage",             kind = "DamageDone",  field = "totalAmount",     empty = "no damage yet" },
    hps     = { title = "HPS",     menu = "Healing per second (HPS)", kind = "HealingDone", field = "amountPerSecond", empty = "no healing yet" },
    healing = { title = "Healing", menu = "Total healing",            kind = "HealingDone", field = "totalAmount",     empty = "no healing yet" },
    -- 0.35.356: "add to the meter the amount of damage taken, and then
    -- interrupts, and deaths". The game counts all three itself.
    taken      = { title = "Taken",      menu = "Damage taken",  kind = "DamageTaken", field = "totalAmount", empty = "no damage taken yet" },
    interrupts = { title = "Interrupts", menu = "Interrupts",    kind = "Interrupts",  field = "totalAmount", empty = "no interrupts yet" },
    deaths     = { title = "Deaths",     menu = "Deaths (left-click the meter: the play-by-play)", kind = "Deaths", field = "totalAmount", empty = "nobody has died" },
}
M.MODE_ORDER = { "dps", "damage", "hps", "healing", "taken", "interrupts", "deaths" }
-- Pure: the mode a saved choice stands for (anything else: DPS).
function M.ModeKey(saved) return M.MODES[saved] and saved or "dps" end
function M.Mode() return M.MODES[M.ModeKey(cfg().mode)] end
function M.SetMode(key)
    cfg().mode = (M.MODES[key] and key ~= "dps") and key or nil
    pcall(M.Update)
end

-- The second list's figures (mode: one of M.MODES, default DPS):
-- { { name, raw (may be hidden), value (number or nil), class, me } }, in
-- the game's order; total (may be hidden); readable?
function M.ReadDamage(mode, span)
    mode = mode or M.MODES.dps
    span = span or M.SpanKey(cfg().span)
    local DM = C_DamageMeter
    if not (DM and DM.GetCombatSessionFromType and Enum and Enum.DamageMeterSessionType and Enum.DamageMeterType) then
        return nil, nil, false, "this client has no damage meter"
    end
    if DM.IsDamageMeterAvailable then
        local okA, avail = pcall(DM.IsDamageMeterAvailable)
        if okA and A.Safe(avail) == false then return nil, nil, false, "the game's damage meter is switched off" end
    end
    local kind = Enum.DamageMeterType[mode.kind]
    if kind == nil then return nil, nil, false, "the game's meter doesn't count that here" end
    local sessionType = M.SessionType(span)
    if sessionType == nil then return nil, nil, false, "the game keeps no count over all fights here" end
    local ok, session = pcall(DM.GetCombatSessionFromType, sessionType, kind)
    if not ok or type(session) ~= "table" then return nil, nil, false, "no fight recorded yet" end
    local list, readable = {}, true
    local okL, sources = pcall(function() return session.combatSources end)
    for _, src in ipairs(okL and type(sources) == "table" and sources or {}) do
        local amount = src[mode.field]
        local value = A.Safe(amount)
        if type(value) ~= "number" then readable = false; value = nil end
        list[#list + 1] = { name = src.name, raw = amount, value = value, bar = amount,
                            class = A.Safe(src.classFilename), me = A.Safe(src.isLocalPlayer) == true,
                            -- (A death carries the game's recap of it: Flow Deaths reads it.)
                            recap = A.Safe(src.deathRecapID) }
    end
    return list, session.totalAmount, readable
end

-- Pure: the pet of each unit ("player" -> "pet", "party2" -> "partypet2",
-- "raid7" -> "raidpet7").
function M.PetUnits(units)
    local out = {}
    for _, u in ipairs(units or {}) do
        if u == "player" then out[#out + 1] = "pet"
        else
            local kind, n = u:match("^(%a+)(%d+)$")
            if kind == "party" or kind == "raid" then out[#out + 1] = kind .. "pet" .. n end
        end
    end
    return out
end
local function groupUnits()
    local units = { "player" }
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            if not Yes(UnitIsUnit("raid" .. i, "player"), false) then units[#units + 1] = "raid" .. i end
        end
    else
        for i = 1, 4 do
            if UnitExists("party" .. i) then units[#units + 1] = "party" .. i end
        end
    end
    -- Pets: yours, and the others' ("pets don't show on the threat meter",
    -- 0.35.249: only your own was asked about).
    for _, pet in ipairs(M.PetUnits(units)) do
        if UnitExists(pet) then units[#units + 1] = pet end
    end
    return units
end
M._GroupUnits = groupUnits

-- Threat on your target: the same shape as ReadDamage's list; readable?
function M.ReadThreat()
    if not UnitDetailedThreatSituation then return nil, false, "this client has no threat call" end
    if not (UnitExists("target") and Yes(UnitCanAttack("player", "target"), false)) then return nil, false, "no enemy targeted" end
    local list, readable = {}, true
    for _, unit in ipairs(groupUnits()) do
        -- (The share of the tank's threat, which runs past 100: a mob turns on
        -- you only some way over.)
        local ok, tanking, status, scaled, rawPct = pcall(UnitDetailedThreatSituation, unit, "target")
        local pct = rawPct
        if pct == nil then pct = scaled end
        -- (nil: not on its threat list. A hidden value can't be compared, not even with nil.)
        local onList = (issecretvalue and issecretvalue(status)) or status ~= nil
        if ok and onList then
            local value = A.Safe(pct)
            if type(value) ~= "number" then readable = false; value = nil end
            local _, class = UnitClass(unit)
            list[#list + 1] = { name = UnitName(unit), raw = pct, value = value, class = A.Safe(class),
                                me = unit == "player", pct = true, tank = A.Safe(tanking) == true }
        end
    end
    return list, readable
end

-- When the meters show: in a group, or with a training dummy targeted.
-- When they show (0.35.261: "show in combat, show in group, always show").
-- Pure: the saved choice ("combat", "group" or "always"; group is the usual).
function M.WhenKey(c)
    if c and c.always then return "always" end
    if c and c.when == "combat" then return "combat" end
    return "group"
end
-- Pure: shown now? In a group also counts a training dummy as your target.
function M.ShowNow(when, inGroup, inCombat, dummy)
    if when == "always" then return true end
    if when == "combat" then return inCombat and true or false end
    return (inGroup or dummy) and true or false
end
function M.SetWhen(key)
    cfg().always = (key == "always") and true or nil
    cfg().when = (key == "combat") and "combat" or nil
    cfg().off = nil
    pcall(M.Update)
end
function M.Wanted()
    if not M.On() then return false end
    local grouped = ((IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid())) and true or false
    local fighting = (InCombatLockdown() or Yes(UnitAffectingCombat("player"), false)) and true or false
    return M.ShowNow(M.WhenKey(cfg()), grouped, fighting, M.IsDummy(A.Safe(UnitName("target"))))
end

-------------------------------------------------------------------------------
-- The two lists
-------------------------------------------------------------------------------
local frame

local function makeList(parent, title)
    local l = CreateFrame("Frame", nil, parent)
    l:SetWidth(M.WIDTH)
    -- Its heading looks like every Flow view's title bar, small (0.35.250:
    -- "give the Threat and the DPS a Flow header looking background"): the
    -- same dark bar, orange accent at the left and gold title (ns.theme).
    local th = ns.theme
    l.bar = l:CreateTexture(nil, "BACKGROUND")
    l.bar:SetPoint("TOPLEFT"); l.bar:SetPoint("TOPRIGHT")
    l.bar:SetHeight(M.HEAD_H)
    l.bar:SetColorTexture(th.BAR[1], th.BAR[2], th.BAR[3], th.BAR[4])
    l.barColor = th.BAR   -- (a plain colour texture doesn't report its colour: kept for the tests)
    l.accent = l:CreateTexture(nil, "BORDER")
    l.accent:SetPoint("TOPLEFT"); l.accent:SetSize(M.HEAD_ACCENT, M.HEAD_H)
    l.accent:SetColorTexture(th.arrow[1], th.arrow[2], th.arrow[3], 1)
    l.accentColor = th.arrow
    l.head = l:CreateFontString(nil, "OVERLAY")
    l.head:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    l.head:SetPoint("TOPLEFT", M.HEAD_ACCENT + 3, -1)
    l.head:SetTextColor(1, 0.82, 0.25)
    l.head:SetText(title)
    l.total = l:CreateFontString(nil, "OVERLAY")
    l.total:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    l.total:SetPoint("TOPRIGHT", -2, -1)
    l.total:SetTextColor(0.8, 0.8, 0.8)
    l.rows = {}
    return l
end

-- Decimals shown after a number under a thousand (0 to 3; the meter's
-- right-click menu). "It will at times show many, many decimals: make it
-- show 0 for now" (0.35.232).
function M.Decimals()
    local d = tonumber(cfg().decimals) or 0
    return math.max(0, math.min(3, math.floor(d)))
end

-- A row's number as text. Readable: shortened here. Hidden (a "secret"
-- value in a fight): the game formats it for us where it will, to the same
-- decimals; else it's handed over as it is.
function M.Text(e, decimals)
    decimals = decimals or M.Decimals()
    if e.value then return M.Short(e.value, decimals) .. (e.pct and "%" or "") end
    if e.raw == nil then return "" end
    local ok, text = pcall(string.format, "%." .. decimals .. "f" .. (e.pct and "%%" or ""), e.raw)
    if ok then return text end
    return e.raw
end

-- Pure: the damage list's rows. list: players, best first ({ name, value,
-- raw, class, me, bar }); rows: how many rows there are; sum: the group's
-- damage per second (nil: hidden); total: the game's own group figure, for
-- when sum is hidden; maxBar: the top player's bar value (nil: the first
-- entry's). Row 1 is the group; then the top players, with you in the last
-- row if you'd fall off. Each player's bar is measured against the top
-- player's, so the top one is full.
function M.DamageRows(list, rows, sum, total, maxBar)
    local out = {}
    list = list or {}
    if #list == 0 then return out end
    out[1] = { name = "Group", value = sum, raw = total, group = true, full = true }
    local me
    for i, e in ipairs(list) do if e.me then me = i break end end
    local top = maxBar
    if top == nil then top = list[1].bar end
    for _, i in ipairs(M.Pick(#list, math.max(1, (rows or 3) - 1), me)) do
        local e = list[i]
        out[#out + 1] = { name = e.name, value = e.value, raw = e.raw, class = e.class, me = e.me, bar = e.bar, barMax = top }
    end
    return out
end

-- Pure: threat, in the order that matters: whoever it's attacking first,
-- then the most threat. (Readable numbers only; hidden ones keep the
-- group's order.)
function M.SortThreat(list)
    local out = {}
    for i, e in ipairs(list or {}) do out[i] = e; e.order = i end
    table.sort(out, function(a, b)
        if (a.tank and true or false) ~= (b.tank and true or false) then return a.tank and true or false end
        local av, bv = tonumber(a.value), tonumber(b.value)
        if av and bv and av ~= bv then return av > bv end
        if (av ~= nil) ~= (bv ~= nil) then return av ~= nil end
        return a.order < b.order
    end)
    return out
end

-- Pure: the threat list's rows. Bars run to 100% (the tank's threat), or to
-- the highest figure when someone is past it (110%, 120%: a boss turns on
-- them only some way over the tank).
function M.ThreatRows(list, rows, readable)
    local out = {}
    list = list or {}
    local me, top = nil, 100
    for i, e in ipairs(list) do
        if e.me and not me then me = i end
        if readable and tonumber(e.value) and e.value > top then top = e.value end
    end
    for _, i in ipairs(M.Pick(#list, rows or 3, me)) do
        local e = list[i]
        out[#out + 1] = { name = e.name, value = e.value, raw = e.raw, class = e.class, me = e.me, pct = true, tank = e.tank,
                          bar = e.value or e.raw, barMax = top }
    end
    return out
end

local function row(l, i)
    local r = l.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, l)
    r:SetSize(M.WIDTH, M.ROW_H)
    r:SetPoint("TOPLEFT", 0, -12 - (i - 1) * M.ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0.35)
    -- The bar: a status bar, which the game fills even from a hidden number.
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("TOPLEFT", 0, -1)
    r.bar:SetPoint("BOTTOMRIGHT", 0, 0)
    r.bar:SetStatusBarTexture(M.BAR_TEXTURE)
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetValue(1)
    r.text = CreateFrame("Frame", nil, r)
    r.text:SetAllPoints()
    r.text:SetFrameLevel(r.bar:GetFrameLevel() + 2)
    r.name = r.text:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    r.name:SetPoint("LEFT", 3, 0)
    r.name:SetWidth(M.WIDTH - 52)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.value = r.text:CreateFontString(nil, "OVERLAY")
    r.value:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    r.value:SetPoint("RIGHT", -3, 0)
    l.rows[i] = r
    return r
end

-- Fills one list from its rows (M.DamageRows / M.ThreatRows).
local function fill(l, entries, rows, empty)
    local decimals = M.Decimals()
    for i = 1, math.max(rows, #l.rows) do
        local r = (i <= rows) and row(l, i) or l.rows[i]
        local e = entries and entries[i]
        if r and e then
            local cr, cg, cb = classColor(e.class)
            if e.group then cr, cg, cb = 1, 0.82, 0.25 end
            r.bar:SetStatusBarColor(cr, cg, cb, (e.me or e.group) and 0.8 or 0.55)
            -- (A hidden number can't be compared here, but the bar takes it.)
            local okB = false
            if not e.full and e.bar ~= nil and e.barMax ~= nil then
                okB = pcall(r.bar.SetMinMaxValues, r.bar, 0, e.barMax) and pcall(r.bar.SetValue, r.bar, e.bar)
            end
            if not okB then r.bar:SetMinMaxValues(0, 1); r.bar:SetValue(1) end
            r.bar:Show()
            if not pcall(r.name.SetText, r.name, e.name) then r.name:SetText("?") end
            if not pcall(r.value.SetText, r.value, M.Text(e, decimals)) then r.value:SetText("") end
            r:Show()
        elseif r then
            if i == 1 and empty then
                r.bar:Hide()
                r.name:SetText("|cff888888" .. empty .. "|r")
                r.value:SetText("")
                r:Show()
            else
                r:Hide()
            end
        end
    end
    l:SetHeight(13 + rows * M.ROW_H)
end

local function build()
    local f = CreateFrame("Frame", "FlowMeters", UIParent)
    f:SetSize(M.WIDTH, 2 * (13 + 3 * M.ROW_H) + 2)
    f:SetFrameStrata("LOW")
    local p = cfg().point
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("RIGHT", UIParent, "RIGHT", -220, -120) end
    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.03, 0.03, 0.05, 0.55)
    f.threat = makeList(f, "Threat")
    f.threat:SetPoint("TOPLEFT")
    f.damage = makeList(f, "DPS")
    f.damage:SetPoint("TOPLEFT", f.threat, "BOTTOMLEFT", 0, -2)
    f:EnableMouse(true)
    ns:MakeMovable(f, setmetatable({}, { __newindex = function(_, key, v)
        if key == "point" then cfg().point = v end end }), true)
    f:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Flow Meters", 1, 0.82, 0)
        GameTooltip:AddLine("Threat on your target (percent of the tank's) and damage or healing in this fight (per second or in all: right-click), from the game's own counts.", 1, 1, 1, true)
        GameTooltip:AddLine(M.note or "DPS: the group, then the top player (a full bar) and the rest against them. Threat: who it's on first; past 100% means close to pulling it.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Ctrl + drag: move. Right-click: what it counts (damage, healing, damage taken, interrupts, deaths), rows, decimals, when it shows.", 0.6, 0.6, 0.6, true)
        if M.ModeKey(cfg().mode) == "deaths" then GameTooltip:AddLine("Click: Flow Deaths, the play-by-play of each death.", 1, 0.82, 0, true) end
        GameTooltip:Show()
    end)
    -- Right-click: its own menu (rows, decimals, when it shows).
    f:SetScript("OnMouseUp", function(_, button) M.Click(button) end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end
function M._Frame() return frame end

-- A click on the meters. Right: their menu. Left, while the second list
-- counts Deaths: Flow Deaths, the play-by-play of each (Deaths.lua).
function M.Click(button)
    if button == "RightButton" then
        if ns.menu and ns.menu.Open then ns.menu:Open(M.ContextItems()) end
        return "menu"
    end
    if M.ModeKey(cfg().mode) == "deaths" and ns.deaths and not IsControlKeyDown() then
        ns.deaths:Show()
        return "deaths"
    end
    return nil
end

M.state = {}   -- what the last update saw, for /flow meters
function M.Update()
    if not M.Wanted() then
        if frame and frame:IsShown() then frame:Hide() end
        return
    end
    frame = frame or build()
    -- Players per list; the damage list has the group's row on top of them.
    local rows = M.PlayerRows()
    local threat, tReadable, tWhy = M.ReadThreat()
    if threat and tReadable then threat = M.SortThreat(threat) end
    fill(frame.threat, M.ThreatRows(threat, rows, tReadable), rows, tWhy or "nobody on its list")
    local mode = M.Mode()
    local damage, total, dReadable, dWhy = M.ReadDamage(mode)
    frame.damage.head:SetText(mode.title .. (M.SpanKey(cfg().span) == "all" and " (all fights)" or ""))
    if damage and dReadable then damage = M.Sort(damage) end
    -- The group's total: every entry's amount per second, where readable.
    local sum
    if damage and dReadable then
        sum = 0
        for _, e in ipairs(damage) do sum = sum + (e.value or 0) end
    end
    -- Row 1 the group, then the players against the top one.
    fill(frame.damage, M.DamageRows(damage, rows + 1, sum, nil), rows + 1, dWhy or mode.empty)
    frame.damage.total:SetText("")
    frame.damage:ClearAllPoints()
    frame.damage:SetPoint("TOPLEFT", frame.threat, "BOTTOMLEFT", 0, -2)
    frame:SetHeight(frame.threat:GetHeight() + frame.damage:GetHeight() + 2)
    M.note = (not dReadable or (threat and not tReadable))
        and "The game hides some of these numbers from add-ons in a fight: those rows aren't sorted by Flow." or nil
    M.state = { threat = threat and #threat or 0, threatReadable = tReadable, threatWhy = tWhy,
                damage = damage and #damage or 0, damageReadable = dReadable, damageWhy = dWhy,
                totalReadable = A.Safe(total) ~= nil, sum = sum, list = damage }
    if not frame:IsShown() then frame:Show() end
end

local acc = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.5 then return end
    acc = 0
    local ok, err = pcall(M.Update)
    if not ok and err ~= M.lastError then M.lastError = err; ns:Log("meters", "update failed: " .. tostring(err)) end
end)

-- After a fight in a group or at a dummy: the numbers, for the log (so the
-- rotation can be judged by them). A second later: the game shows them then.
ns:On("PLAYER_REGEN_ENABLED", function()
    if not (C_Timer and M.On()) then return end
    C_Timer.After(1.5, function()
        local ok, list, _, readable = pcall(M.ReadDamage, M.MODES.dps, "fight")
        if not (ok and list and #list > 0) then return end
        local parts, sum = {}, 0
        for i, e in ipairs(readable and M.Sort(list) or list) do
            sum = sum + (e.value or 0)
            if i <= 5 or e.me then
                parts[#parts + 1] = string.format("%s%s %s", e.me and "*" or "", tostring(A.Safe(e.name) or "?"), e.value and M.Short(e.value) or "hidden")
            end
        end
        ns:Log("meters", string.format("fight over: dps %s; group %s (%d in it, numbers %s)", table.concat(parts, ", "),
            readable and M.Short(sum) or "hidden", #list, readable and "readable" or "hidden"))
    end)
end)

-------------------------------------------------------------------------------
-- /flow meters, the menu
-------------------------------------------------------------------------------
function M.Lines()
    local out = { string.format("Flow Meters: %s, %d rows; shown now: %s", M.On() and "on" or "off", M.RowCount(), tostring(frame ~= nil and frame:IsShown())) }
    local DM = C_DamageMeter
    out[#out + 1] = "  the game's damage meter: " .. ((DM and DM.GetCombatSessionFromType) and "there" or "missing")
        .. "; threat call: " .. (UnitDetailedThreatSituation and "there" or "missing")
        .. "; says threat is hidden: " .. tostring(C_Secrets and C_Secrets.ShouldUnitThreatValuesBeSecret
            and select(2, pcall(C_Secrets.ShouldUnitThreatValuesBeSecret, "player", "target")) or "can't ask")
    -- What the game's meter can count here (for the menu's choices).
    local kinds = {}
    for k in pairs((Enum and Enum.DamageMeterType) or {}) do kinds[#kinds + 1] = tostring(k) end
    table.sort(kinds)
    out[#out + 1] = "  second list counts: " .. M.Mode().title .. "; the game's meter kinds: " .. (#kinds > 0 and table.concat(kinds, ", ") or "none")
    local okD, list, total, readable, why = pcall(M.ReadDamage, M.Mode())
    if okD then
        out[#out + 1] = string.format("  damage now: %d entr%s, numbers %s, total %s%s", list and #list or 0, (list and #list == 1) and "y" or "ies",
            readable and "readable" or "hidden", A.Safe(total) ~= nil and "readable" or "hidden", why and (" (" .. why .. ")") or "")
        for i, e in ipairs(list or {}) do
            if i <= 5 then
                out[#out + 1] = string.format("    %d. %s %s%s", i, tostring(A.Safe(e.name) or "(name hidden)"), e.value and M.Short(e.value) or "(hidden)", e.me and " (you)" or "")
            end
        end
    else
        out[#out + 1] = "  damage: failed: " .. tostring(list)
    end
    local okT, tl, tr, tw = pcall(M.ReadThreat)
    if okT then
        out[#out + 1] = string.format("  threat now: %d on the list, numbers %s%s", tl and #tl or 0, tr and "readable" or "hidden", tw and (" (" .. tw .. ")") or "")
    else
        out[#out + 1] = "  threat: failed: " .. tostring(tl)
    end
    if M.lastError then out[#out + 1] = "  last error: " .. tostring(M.lastError) end
    return out
end
ns.commands.meters = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then cfg().off = (arg == "off") or nil
    elseif tonumber(arg) then cfg().rows = tonumber(arg) end
    for i, l in ipairs(M.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
    print("  /flow meters on|off   /flow meters 3|5|10")
end
-- /flow meter: show them now and keep them shown (alone too); again: back
-- to "in a group or at a dummy". ("How can I open the meter if I want to
-- see it at any time?", 0.35.213)
function M.SetAlways(on)
    cfg().always = on and true or nil
    if on then cfg().off = nil end
    pcall(M.Update)
end
ns.commands.meter = function(arg)
    arg = (arg or ""):lower()
    if arg ~= "" then return ns.commands.meters(arg) end
    M.SetAlways(not cfg().always)
    ns:Print(cfg().always and "Flow Meters: shown all the time now (/flow meter again: only in a group or at a training dummy)."
        or "Flow Meters: back to showing in a group or at a training dummy.")
end
ns:Register("help", "meters", { order = 33, title = "Flow Meters", lines = {
    "In a group (and at a training dummy): threat on your target and damage per second, the top two and you.",
    "/flow meter: show them all the time (again: back to groups and dummies). /flow meters on|off, /flow meters 3|5|10 (rows). Ctrl + drag moves them.",
} })

-- The meters' own menu (right-click them): rows, decimals, when they show.
function M.ContextItems()
    local items = { { title = true, text = "Flow Meters" } }
    -- Show: when.
    items[#items + 1] = { title = true, text = "Show" }
    for _, w in ipairs({ { "combat", "Show in combat" }, { "group", "Show in group" }, { "always", "Always show" } }) do
        items[#items + 1] = { text = w[2], radio = true, stay = true,
            checked = M.WhenKey(cfg()) == w[1], refresh = function(it) it.checked = M.WhenKey(cfg()) == w[1] end,
            func = function() M.SetWhen(w[1]) end }
    end
    -- Rows: players per list (the group's row is on top of them).
    items[#items + 1] = { title = true, text = "Rows" }
    for _, n in ipairs(M.ROWS) do
        items[#items + 1] = { text = M.RowsLabel(n), radio = true, stay = true,
            checked = M.RowCount() == n, refresh = function(it) it.checked = M.RowCount() == n end,
            func = function() cfg().rows = n; pcall(M.Update) end }
    end
    items[#items + 1] = { title = true, text = "Count" }
    for _, key in ipairs(M.MODE_ORDER) do
        items[#items + 1] = { text = M.MODES[key].menu, radio = true, stay = true,
            checked = M.ModeKey(cfg().mode) == key, refresh = function(it) it.checked = M.ModeKey(cfg().mode) == key end,
            func = function() M.SetMode(key) end }
    end
    items[#items + 1] = { rule = true }
    for _, sp in ipairs({ { "fight", "This fight (starts again at every pull)" }, { "all", "All fights (everything since the last reset)" } }) do
        items[#items + 1] = { text = sp[2], radio = true, stay = true,
            checked = M.SpanKey(cfg().span) == sp[1], refresh = function(it) it.checked = M.SpanKey(cfg().span) == sp[1] end,
            func = function() M.SetSpan(sp[1]) end }
    end
    items[#items + 1] = { text = "Reset the counts", func = function() M.Reset() end }
    items[#items + 1] = { text = "Deaths: the play-by-play (Flow Deaths)", func = function() if ns.deaths then ns.deaths:Show() end end }
    items[#items + 1] = { title = true, text = "Numbers" }
    for d = 0, 3 do
        items[#items + 1] = { text = d == 0 and "Whole numbers" or string.format("%d decimal%s", d, d == 1 and "" or "s"), radio = true, stay = true,
            checked = M.Decimals() == d, refresh = function(it) it.checked = M.Decimals() == d end,
            func = function() cfg().decimals = d; pcall(M.Update) end }
    end
    items[#items + 1] = { rule = true }
    items[#items + 1] = { text = "Turn Flow Meters off", func = function() cfg().off = true; pcall(M.Update) end }
    return items
end

-- The Flow menu's entries (Menu.lua puts them under Flow windows).
-- The Flow menu's tick (0.35.284): ticked means "always shown". A tick turns
-- the meters on, always; unticking goes back to when they showed before (in a
-- group, unless you'd picked in combat). In combat or in a group only is
-- chosen on the meters' own right-click menu, so with those the tick is off.
-- Pure: is the tick on?
function M.MenuTicked(on, when) return (on and when == "always") and true or false end
-- Pure: what a click on it does: the "when" to set.
function M.MenuClick(ticked, before)
    if not ticked then return "always" end
    return (before == "combat") and "combat" or "group"
end
function M.MenuItems()
    return { { text = "Flow Meters", stay = true, checked = M.MenuTicked(M.On(), M.WhenKey(cfg())),
        tip = "Ticked: the meters are always shown. Untick and they show as before (in a group, or in combat). Right-click the meters themselves for in combat, in a group, the rows and what they count.",
        refresh = function(it) it.checked = M.MenuTicked(M.On(), M.WhenKey(cfg())) end,
        func = function()
            local when = M.WhenKey(cfg())
            local ticked = M.MenuTicked(M.On(), when)
            if not ticked and when ~= "always" then cfg().whenBefore = when end
            M.SetWhen(M.MenuClick(ticked, cfg().whenBefore))
        end } }
end

-------------------------------------------------------------------------------
-- What the game reports around a taunt (0.35.274)
-------------------------------------------------------------------------------
-- "If Growl sets my threat to the same as whoever has aggro, it isn't
-- reflected in our threat meter, and it should be." The meter shows the
-- game's own figure for you on your target and adds nothing to it, so the
-- question is what the game says after a taunt: your share at the moment of
-- the cast and again a moment later go in the log (the diagnostics), with
-- whether the game let Flow read it. Then the cause can be seen, not guessed.
M.TAUNTS = { Growl = true, Taunt = true, ["Mocking Blow"] = true, ["Challenging Shout"] = true,
             ["Challenging Roar"] = true, ["Righteous Defense"] = true, ["Hand of Reckoning"] = true }
-- Pure: your threat on your target, in words. entry: your row of
-- M.ReadThreat's list (nil: you're not on its list); readable: the numbers
-- can be read; why: the reason there's no list.
function M.ThreatNote(entry, readable, why)
    if not entry then return why and ("no figure: " .. why) or "you're not on its threat list" end
    local on = entry.tank and "on you" or "not on you"
    if not readable or entry.value == nil then return "hidden by the game (" .. on .. ")" end
    return string.format("%d%% of whoever it's on (%s)", math.floor(entry.value + 0.5), on)
end
function M.MyThreat()
    local list, readable, why = M.ReadThreat()
    for _, e in ipairs(list or {}) do
        if e.me then return e, readable, why end
    end
    return nil, readable, why
end
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if not (name and M.TAUNTS[name]) then return end
    local okB, before = pcall(function() return M.ThreatNote(M.MyThreat()) end)
    ns:Log("meters", string.format("%s cast: your threat right then: %s", name, okB and before or "unreadable"))
    if C_Timer then
        C_Timer.After(1.5, function()
            local okA, after = pcall(function() return M.ThreatNote(M.MyThreat()) end)
            ns:Log("meters", string.format("%s, 1.5 s later: %s", name, okA and after or "unreadable"))
        end)
    end
end)
