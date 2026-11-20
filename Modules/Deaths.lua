-------------------------------------------------------------------------------
-- Flow - Deaths.lua
-- Flow Deaths: who died, and the play-by-play of each death (0.35.356).
--
-- "Show deaths; the user can click on that and look at the combat log of a
-- death for that specific character ... a play-by-play. And if you want to
-- get fancy, a health graph: hover it and it highlights the action in the
-- table; hover the table and it shows the point in the graph."
--
-- Where it comes from. This client gives add-ons no combat log, so Flow
-- can't write its own play-by-play. The game keeps one itself for each death
-- (its death recap): the last things that happened to that character, each
-- with what it was, who did it, how much, and the health left after it. Flow
-- shows that: a table, oldest first, the killing blow last, and a graph of
-- the health over those moments.
--   * It holds what the game recorded, no more. Whether heals are in it, and
--     how far back it goes, is the game's choice; the window says how many
--     moments it got, and /flow deaths (and the diagnostics) say what shape
--     the game's answer had, so Flow can show more if there's more to show.
--   * The list of who died is the game's own count (Flow Meters' "Deaths").
--
-- Open it: left-click Flow Meters while it counts Deaths, "Deaths: the
-- play-by-play" in its right-click menu, or /flow deaths.
-------------------------------------------------------------------------------

local _, ns = ...
local A = ns.api
local D = {}
ns.deaths = D

D.ROWS = 12          -- lines of the play-by-play shown
D.NAMES = 8          -- deaths listed at the left
D.PLOT_W, D.PLOT_H = 370, 84

-------------------------------------------------------------------------------
-- Pure parts
-------------------------------------------------------------------------------

-- The game's recap events as rows, oldest first.
--   events: the game's list ({ timestamp, event, spellName, sourceName,
--   amount, overkill, currentHP, environmentalType, ... }, in any order);
--   maxHp: the character's full health (nil: unknown); safe(v): unwraps a
--   value the game may hide (nil when hidden).
--   -> { { t = seconds before the last moment (0 or less), kind = "damage" |
--        "heal", what, who, amount (damage is negative), hp, pct, over } }
function D.Shape(events, maxHp, safe)
    safe = safe or function(v) return v end
    local rows = {}
    for i, e in ipairs(events or {}) do
        if type(e) == "table" then
            local ev = tostring(safe(e.event) or "")
            local heal = ev:find("HEAL", 1, true) ~= nil
            local amount = tonumber(safe(e.amount))
            local what = safe(e.spellName)
            if type(what) ~= "string" or what == "" then
                local env = safe(e.environmentalType)
                what = (type(env) == "string" and env ~= "" and (env:sub(1, 1):upper() .. env:sub(2):lower()))
                    or (ev:find("SWING", 1, true) and "Melee") or "?"
            end
            local who = safe(e.sourceName)
            rows[#rows + 1] = {
                at = tonumber(safe(e.timestamp)), order = i, kind = heal and "heal" or "damage", what = what,
                who = (type(who) == "string" and who ~= "") and who or nil,
                amount = amount and (heal and amount or -amount) or nil,
                hp = tonumber(safe(e.currentHP)), over = tonumber(safe(e.overkill)),
            }
        end
    end
    -- Oldest first: by time where the game gives one, else the reverse of the
    -- game's order (it lists the newest first).
    table.sort(rows, function(a, b)
        if a.at and b.at and a.at ~= b.at then return a.at < b.at end
        return a.order > b.order
    end)
    local last = rows[#rows] and rows[#rows].at
    for _, r in ipairs(rows) do
        r.t = (r.at and last) and (r.at - last) or nil
        r.pct = (r.hp and maxHp and maxHp > 0) and math.max(0, math.min(100, r.hp / maxHp * 100)) or nil
    end
    return rows
end

-- A row's line of the table.
function D.Line(r)
    local t = r.t and string.format("%5.1fs", r.t) or "      "
    local amount = r.amount and string.format("%+d", r.amount) or "?"
    local colour = r.kind == "heal" and "40ff40" or "ff5050"
    local hp = r.pct and string.format("%d%%", math.floor(r.pct + 0.5)) or (r.hp and tostring(r.hp) or "")
    return string.format("%s  %s%s  |cff%s%s|r%s%s", t, r.who and (r.who .. ": ") or "", tostring(r.what), colour, amount,
        (r.over and r.over > 0) and string.format(" (%d over)", r.over) or "", hp ~= "" and ("  |cff999999" .. hp .. "|r") or "")
end

-- What killed them, and what healing they had, in a line or two.
function D.Summary(rows)
    local out = {}
    local blow
    for i = #rows, 1, -1 do if rows[i].kind == "damage" then blow = rows[i] break end end
    if blow then
        out[#out + 1] = string.format("Killing blow: %s%s%s", blow.who and (blow.who .. "'s ") or "", tostring(blow.what),
            blow.amount and string.format(" for %d", -blow.amount) or "")
    end
    local taken, healed, healers, seen = 0, 0, {}, {}
    for _, r in ipairs(rows) do
        if r.kind == "damage" then taken = taken - (r.amount or 0)
        else
            healed = healed + (r.amount or 0)
            if r.who and not seen[r.who] then seen[r.who] = true; healers[#healers + 1] = r.who end
        end
    end
    local span = (rows[1] and rows[1].t) and string.format(" in the last %.1f s", -rows[1].t) or ""
    out[#out + 1] = string.format("%d damage taken%s; %s", taken, span,
        healed > 0 and string.format("%d healed by %s", healed, table.concat(healers, ", ")) or "no healing in what the game recorded")
    return out
end

-- The graph's points: x by time (evenly spaced when the game gives none), y
-- by health. -> { { x, y, i } } for the rows that have a health.
function D.Points(rows, w, h, maxHp)
    local out = {}
    local n = #rows
    if n == 0 then return out end
    local top = maxHp
    if not top or top <= 0 then
        top = 0
        for _, r in ipairs(rows) do if r.hp and r.hp > top then top = r.hp end end
    end
    local t0 = rows[1].t
    for i, r in ipairs(rows) do
        if r.hp and top > 0 then
            local x = (t0 and r.t and t0 < 0) and ((r.t - t0) / -t0 * w) or (n > 1 and (i - 1) / (n - 1) * w or w / 2)
            out[#out + 1] = { x = x, y = math.max(0, math.min(1, r.hp / top)) * h, i = i }
        end
    end
    return out
end

-- The point nearest to x (the mouse over the graph): its row's index.
function D.Nearest(points, x)
    local best, bestD
    for _, p in ipairs(points or {}) do
        local d = math.abs(p.x - x)
        if not bestD or d < bestD then best, bestD = p.i, d end
    end
    return best
end

-- Which rows of a long play-by-play show: the last `max` (the death is at the end).
function D.Window(n, max)
    return math.max(1, n - max + 1), n
end

-------------------------------------------------------------------------------
-- The game's answers
-------------------------------------------------------------------------------

-- Who died: the game's own count (Flow Meters' Deaths), each with the recap
-- the game keeps for it. -> { { name, class, count, recap, me } }, why not
function D.List()
    local M = ns.meters
    if not (M and M.ReadDamage and M.MODES.deaths) then return {}, "Flow Meters isn't loaded" end
    local ok, list, _, _, why = pcall(M.ReadDamage, M.MODES.deaths)
    if not ok then return {}, tostring(list) end
    local out = {}
    for _, e in ipairs(list or {}) do
        out[#out + 1] = { name = A.Safe(e.name) or "(name hidden)", class = e.class, count = e.value, recap = e.recap, me = e.me }
    end
    return out, why
end

-- A death's play-by-play from the game. -> rows, full health, why not
function D.Read(recap)
    if recap == nil then return {}, nil, "the game gave no recap for this death" end
    local DR = _G.C_DeathRecap
    local events
    if DR and DR.GetRecapEvents then
        local ok, ev = pcall(DR.GetRecapEvents, recap)
        events = ok and type(ev) == "table" and ev or nil
    elseif _G.DeathRecap_GetEvents then
        local ok, ev = pcall(_G.DeathRecap_GetEvents, recap)
        events = ok and type(ev) == "table" and ev or nil
    else
        return {}, nil, "this game has no death recap an add-on can read"
    end
    if not events or #events == 0 then return {}, nil, "the game's recap for this death is empty" end
    local maxHp
    if DR and DR.GetRecapMaxHealth then
        local ok, m = pcall(DR.GetRecapMaxHealth, recap)
        maxHp = ok and tonumber(A.Safe(m)) or nil
    end
    return D.Shape(events, maxHp, A.Safe), maxHp, nil
end

-- What shape the game's answers have (names only), for /flow deaths.
function D.Probe()
    local out = {}
    local DR = _G.C_DeathRecap
    local names = {}
    for k in pairs(type(DR) == "table" and DR or {}) do names[#names + 1] = tostring(k) end
    table.sort(names)
    out[#out + 1] = "  the game's death recap (C_DeathRecap): " .. (#names > 0 and table.concat(names, ", ") or (_G.DeathRecap_GetEvents and "the older DeathRecap_GetEvents" or "none"))
    local DM = _G.C_DamageMeter
    local ok, session = pcall(function()
        return DM.GetCombatSessionFromType(ns.meters.SessionType(ns.meters.SpanKey(ns.db.meters.span)), Enum.DamageMeterType.Deaths)
    end)
    local src = ok and type(session) == "table" and type(session.combatSources) == "table" and session.combatSources[1] or nil
    if type(src) == "table" then
        local keys = {}
        for k in pairs(src) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        out[#out + 1] = "  a death in the game's count has: " .. table.concat(keys, ", ")
        local okE, ev = pcall(function() return DR.GetRecapEvents(A.Safe(src.deathRecapID)) end)
        local first = okE and type(ev) == "table" and ev[1] or nil
        if type(first) == "table" then
            local ek = {}
            for k in pairs(first) do ek[#ek + 1] = tostring(k) end
            table.sort(ek)
            out[#out + 1] = string.format("  its recap: %d moment(s), each with: %s", #ev, table.concat(ek, ", "))
        else
            out[#out + 1] = "  its recap: " .. (okE and "nothing" or ("failed: " .. tostring(ev)))
        end
    else
        out[#out + 1] = "  no death in the game's count right now" .. (ok and "" or (" (" .. tostring(session) .. ")"))
    end
    return out
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
D.sel, D.hover = 1, nil
D.rows, D.points = {}, {}

local function build()
    local f = CreateFrame("Frame", "FlowDeaths", UIParent)
    f:SetSize(560, 150 + D.PLOT_H + D.ROWS * 14)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
    f.head = ns.theme:TitleBar(f, "Flow Deaths", "Interface\\Icons\\Ability_Rogue_FeignDeath")
    f:EnableMouse(true)
    local p = ns.db.deaths.point
    if p then f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    ns:MakeMovable(f, setmetatable({}, { __newindex = function(_, key, v)
        if key == "point" then ns.db.deaths.point = v end end }), true)
    tinsert(UISpecialFrames, "FlowDeaths")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)   -- (our own: the game's handler can't close an add-on window in a fight)
    -- Who died: a column of names at the left.
    f.names = {}
    for i = 1, D.NAMES do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(150, 16)
        b:SetPoint("TOPLEFT", 8, -30 - (i - 1) * 17)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.1)
        b.sel = b:CreateTexture(nil, "BACKGROUND"); b.sel:SetAllPoints(); b.sel:SetColorTexture(1, 0.82, 0, 0.18)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 3, 0); b.text:SetPoint("RIGHT", -3, 0); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
        b:SetScript("OnClick", function() D:Pick(i) end)
        b:Hide()
        f.names[i] = b
    end
    -- The death picked: what killed them, the graph, the table.
    f.sum = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sum:SetPoint("TOPLEFT", 170, -30); f.sum:SetPoint("TOPRIGHT", -10, -30)
    f.sum:SetJustifyH("LEFT")
    f.plot = CreateFrame("Frame", nil, f)
    f.plot:SetSize(D.PLOT_W, D.PLOT_H)
    f.plot:SetPoint("TOPLEFT", 172, -72)
    f.plot.bg = f.plot:CreateTexture(nil, "BACKGROUND")
    f.plot.bg:SetAllPoints(); f.plot.bg:SetColorTexture(0, 0, 0, 0.45)
    f.plot.cap = f.plot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.plot.cap:SetPoint("TOPRIGHT", -2, -2)
    f.plot.cap:SetText("health")
    f.plot.lines, f.plot.dots = {}, {}
    f.plot.mark = f.plot:CreateTexture(nil, "OVERLAY")
    f.plot.mark:SetSize(11, 11)
    f.plot.mark:SetColorTexture(1, 0.82, 0, 0.95)
    f.plot.mark:Hide()
    f.plot:EnableMouse(true)
    f.plot:SetScript("OnEnter", function(self) self.over = true end)
    f.plot:SetScript("OnLeave", function(self) self.over = false; D:Hover(nil) end)
    f.plot:SetScript("OnUpdate", function(self)
        if not self.over then return end
        local x = GetCursorPosition() / (self:GetEffectiveScale() or 1) - (self:GetLeft() or 0)
        D:Hover(D.Nearest(D.points, x))
    end)
    f.lines = {}
    for i = 1, D.ROWS do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(14)
        b:SetPoint("TOPLEFT", f.plot, "BOTTOMLEFT", -2, -8 - (i - 1) * 14)
        b:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        b.sel = b:CreateTexture(nil, "BACKGROUND"); b.sel:SetAllPoints(); b.sel:SetColorTexture(1, 0.82, 0, 0.22)
        b.sel:Hide()
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 2, 0); b.text:SetPoint("RIGHT", -2, 0); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
        b:SetScript("OnEnter", function(self) D:Hover(self.index) end)
        b:SetScript("OnLeave", function() D:Hover(nil) end)
        b:SetScript("OnClick", function(self) D:Hover(self.index) end)
        b:Hide()
        f.lines[i] = b
    end
    f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.foot:SetPoint("BOTTOMLEFT", 10, 8); f.foot:SetPoint("BOTTOMRIGHT", -10, 8)
    f.foot:SetJustifyH("LEFT")
    f:Hide()
    return f
end

-- The moment under the mouse (the graph's point, or the table's line): both light up.
function D:Hover(index)
    if D.hover == index then return end
    D.hover = index
    local f = D.frame
    if not f then return end
    for _, b in ipairs(f.lines) do b.sel:SetShown(b.index ~= nil and b.index == index) end
    local mark = f.plot.mark
    mark:Hide()
    for _, p in ipairs(D.points) do
        if p.i == index then
            mark:ClearAllPoints()
            mark:SetPoint("CENTER", f.plot, "BOTTOMLEFT", p.x, p.y)
            mark:Show()
        end
    end
end

local function drawPlot(f)
    local plot = f.plot
    for _, l in ipairs(plot.lines) do l:Hide() end
    for _, d in ipairs(plot.dots) do d:Hide() end
    for i, p in ipairs(D.points) do
        local d = plot.dots[i]
        if not d then
            d = plot:CreateTexture(nil, "ARTWORK", nil, 2)
            d:SetSize(5, 5)
            plot.dots[i] = d
        end
        local r = D.rows[p.i]
        if r and r.kind == "heal" then d:SetColorTexture(0.25, 1, 0.25, 1) else d:SetColorTexture(1, 0.35, 0.35, 1) end
        d:ClearAllPoints()
        d:SetPoint("CENTER", plot, "BOTTOMLEFT", p.x, p.y)
        d:Show()
        local q = D.points[i + 1]
        if q and plot.CreateLine then
            local l = plot.lines[i]
            if not l then
                l = plot:CreateLine(nil, "ARTWORK", nil, 1)
                l:SetThickness(1.5)
                l:SetColorTexture(0.85, 0.85, 0.85, 0.9)
                plot.lines[i] = l
            end
            l:SetStartPoint("BOTTOMLEFT", plot, p.x, p.y)
            l:SetEndPoint("BOTTOMLEFT", plot, q.x, q.y)
            l:Show()
        end
    end
end

function D:Fill()
    local f = D.frame
    if not f then return end
    local list, why = D.List()
    D.list = list
    if D.sel > #list then D.sel = math.max(1, #list) end
    for i, b in ipairs(f.names) do
        local e = list[i]
        if e then
            b.text:SetText(string.format("%s%s", tostring(e.name), (e.count and e.count > 1) and string.format("  x%d", e.count) or ""))
            b.sel:SetShown(i == D.sel)
            b:Show()
        else
            b:Hide()
        end
    end
    local e = list[D.sel]
    local rows, maxHp, whyNot = {}, nil, nil
    if e then rows, maxHp, whyNot = D.Read(e.recap) end
    D.rows = rows
    D.points = D.Points(rows, D.PLOT_W - 8, D.PLOT_H - 8, maxHp)
    for _, p in ipairs(D.points) do p.x, p.y = p.x + 4, p.y + 4 end
    D.hover = nil
    f.plot.mark:Hide()
    if not e then
        f.sum:SetText(why or "Nobody has died in what the game has counted (Flow Meters' span: this fight, or all fights).")
    elseif #rows == 0 then
        f.sum:SetText(string.format("%s: %s.", tostring(e.name), tostring(whyNot or "nothing recorded")))
    else
        f.sum:SetText(tostring(e.name) .. "\n" .. table.concat(D.Summary(rows), "\n"))
    end
    drawPlot(f)
    f.plot:SetShown(#D.points > 0)
    local first, last = D.Window(#rows, D.ROWS)
    for i, b in ipairs(f.lines) do
        local at = first + i - 1
        local r = at <= last and rows[at] or nil
        b.index = r and at or nil
        b.sel:Hide()
        if r then b.text:SetText(D.Line(r)); b:Show() else b:Hide() end
    end
    f.foot:SetText(#rows > 0 and string.format("%d moment(s), as the game recorded them%s. Hover the graph or a line.", #rows,
            #rows > D.ROWS and string.format(" (the last %d shown)", D.ROWS) or "")
        or "The play-by-play is the game's own death recap: Flow has no combat log on this client.")
end

function D:Pick(i)
    D.sel = i
    D:Fill()
end
function D:Show()
    if not ns.db.deaths then return end
    D.frame = D.frame or build()
    D:Fill()
    D.frame:Show()
end
function D:Toggle()
    if D.frame and D.frame:IsShown() then D.frame:Hide() return end
    D:Show()
end
function D._Frame() return D.frame end

ns:OnLoad(function(saved) saved.deaths = saved.deaths or {} end)

function D.Lines()
    local list, why = D.List()
    local out = { string.format("Flow Deaths: %d in the game's count%s", #list, why and (" (" .. tostring(why) .. ")") or "") }
    for i, e in ipairs(list) do
        if i <= 6 then
            local rows, _, whyNot = D.Read(e.recap)
            out[#out + 1] = string.format("  %s%s: %s", tostring(e.name), e.count and string.format(" x%s", tostring(e.count)) or "",
                #rows > 0 and (D.Summary(rows)[1] or (#rows .. " moment(s)")) or tostring(whyNot))
        end
    end
    local okP, probe = pcall(D.Probe)
    for _, l in ipairs(okP and probe or { "  probe failed: " .. tostring(probe) }) do out[#out + 1] = l end
    return out
end
ns.commands.deaths = function(arg)
    if (arg or ""):lower() == "show" or (arg or "") == "" then D:Show() end
    for i, l in ipairs(D.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end
ns:Register("help", "deaths", { order = 64, title = "Flow Deaths", lines = {
    "Who died in the fight (or in all fights: Flow Meters' span), and for each the game's own record of the death: what hit them, who did it, how much, and the health left, oldest first, the killing blow last.",
    "A graph shows the health over those moments. Hover a point and its line lights up; hover a line and its point does.",
    "Open it with a left-click on Flow Meters while it counts Deaths, from its right-click menu, or /flow deaths.",
} })
