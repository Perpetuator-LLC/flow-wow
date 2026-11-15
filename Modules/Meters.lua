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
M.ROWS = { 3, 5, 10 }

ns:OnLoad(function(saved) saved.meters = saved.meters or {} end)
local function cfg() return ns.db.meters end
function M.On() return cfg().off ~= true end
function M.RowCount()
    local n = tonumber(cfg().rows) or 3
    return (n == 5 or n == 10) and n or 3
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

-- Damage per second: { { name, raw (may be hidden), value (number or nil),
-- class, me } }, in the game's order; total (may be hidden); readable?
function M.ReadDamage()
    local DM = C_DamageMeter
    if not (DM and DM.GetCombatSessionFromType and Enum and Enum.DamageMeterSessionType and Enum.DamageMeterType) then
        return nil, nil, false, "this client has no damage meter"
    end
    if DM.IsDamageMeterAvailable then
        local okA, avail = pcall(DM.IsDamageMeterAvailable)
        if okA and A.Safe(avail) == false then return nil, nil, false, "the game's damage meter is switched off" end
    end
    local ok, session = pcall(DM.GetCombatSessionFromType, Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)
    if not ok or type(session) ~= "table" then return nil, nil, false, "no fight recorded yet" end
    local list, readable = {}, true
    local okL, sources = pcall(function() return session.combatSources end)
    for _, src in ipairs(okL and type(sources) == "table" and sources or {}) do
        local value = A.Safe(src.amountPerSecond)
        if type(value) ~= "number" then readable = false; value = nil end
        list[#list + 1] = { name = src.name, raw = src.amountPerSecond, value = value, bar = src.amountPerSecond,
                            class = A.Safe(src.classFilename), me = A.Safe(src.isLocalPlayer) == true }
    end
    return list, session.totalAmount, readable
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
    if UnitExists("pet") then units[#units + 1] = "pet" end
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
function M.Wanted()
    if not M.On() then return false end
    if cfg().always then return true end   -- (/flow meter: shown whenever, alone too)
    if (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) then return true end
    return M.IsDummy(A.Safe(UnitName("target")))
end

-------------------------------------------------------------------------------
-- The two lists
-------------------------------------------------------------------------------
local frame

local function makeList(parent, title)
    local l = CreateFrame("Frame", nil, parent)
    l:SetWidth(M.WIDTH)
    l.head = l:CreateFontString(nil, "OVERLAY")
    l.head:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    l.head:SetPoint("TOPLEFT", 2, -1)
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
    r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
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
        GameTooltip:AddLine("Threat on your target (percent of the tank's) and damage per second in this fight, from the game's own counts.", 1, 1, 1, true)
        GameTooltip:AddLine(M.note or "DPS: the group, then the top player (a full bar) and the rest against them. Threat: who it's on first; past 100% means close to pulling it.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Ctrl + drag: move. Right-click: rows, decimals, when it shows.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    -- Right-click: its own menu (rows, decimals, when it shows).
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and ns.menu and ns.menu.Open then ns.menu:Open(M.ContextItems()) end
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end
function M._Frame() return frame end

M.state = {}   -- what the last update saw, for /flow meters
function M.Update()
    if not M.Wanted() then
        if frame and frame:IsShown() then frame:Hide() end
        return
    end
    frame = frame or build()
    local rows = M.RowCount()
    local threat, tReadable, tWhy = M.ReadThreat()
    if threat and tReadable then threat = M.SortThreat(threat) end
    fill(frame.threat, M.ThreatRows(threat, rows, tReadable), rows, tWhy or "nobody on its list")
    local damage, total, dReadable, dWhy = M.ReadDamage()
    if damage and dReadable then damage = M.Sort(damage) end
    -- The group's total: every entry's amount per second, where readable.
    local sum
    if damage and dReadable then
        sum = 0
        for _, e in ipairs(damage) do sum = sum + (e.value or 0) end
    end
    -- Row 1 the group, then the players against the top one.
    fill(frame.damage, M.DamageRows(damage, rows, sum, nil), rows, dWhy or "no damage yet")
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
        local ok, list, _, readable = pcall(M.ReadDamage)
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
    local okD, list, total, readable, why = pcall(M.ReadDamage)
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
    for _, n in ipairs(M.ROWS) do
        items[#items + 1] = { text = string.format("%d rows%s", n, n == 3 and " (the group, the top one and you)" or ""), radio = true, stay = true,
            checked = M.RowCount() == n, refresh = function(it) it.checked = M.RowCount() == n end,
            func = function() cfg().rows = n; pcall(M.Update) end }
    end
    items[#items + 1] = { rule = true }
    for d = 0, 3 do
        items[#items + 1] = { text = d == 0 and "Whole numbers" or string.format("%d decimal%s", d, d == 1 and "" or "s"), radio = true, stay = true,
            checked = M.Decimals() == d, refresh = function(it) it.checked = M.Decimals() == d end,
            func = function() cfg().decimals = d; pcall(M.Update) end }
    end
    items[#items + 1] = { rule = true }
    items[#items + 1] = { text = "Always shown (alone too)", stay = true, checked = cfg().always == true,
        refresh = function(it) it.checked = cfg().always == true end,
        func = function() M.SetAlways(not cfg().always) end }
    items[#items + 1] = { text = "Turn Flow Meters off", func = function() cfg().off = true; pcall(M.Update) end }
    return items
end

-- The Flow menu's entries (Menu.lua puts them under Flow windows).
function M.MenuItems()
    local items = { { text = "Flow Meters: threat and DPS in a group", stay = true, checked = M.On(),
        tip = "Two small lists, shown in a party or raid and at training dummies: threat on your target, and damage per second. The top two and you.",
        refresh = function(it) it.checked = M.On() end,
        func = function() cfg().off = M.On() or nil; pcall(M.Update) end } }
    items[#items + 1] = { text = "   Flow Meters: always shown (alone too)", stay = true, checked = cfg().always == true,
        tip = "Off: the meters show in a party or raid and while a training dummy is your target. On: always. /flow meter does the same.",
        refresh = function(it) it.checked = cfg().always == true end,
        func = function() M.SetAlways(not cfg().always) end }
    for _, n in ipairs(M.ROWS) do
        items[#items + 1] = { text = string.format("   Flow Meters rows: %d%s", n, n == 3 and " (the top two and you)" or ""), stay = true,
            radio = true, checked = M.RowCount() == n,
            refresh = function(it) it.checked = M.RowCount() == n end,
            func = function() cfg().rows = n; pcall(M.Update) end }
    end
    return items
end
