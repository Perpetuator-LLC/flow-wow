-- A note when you're in a zone you haven't picked (0.35.316).
--
-- "We need to also do some kind of flashy notification that they're in a
-- zone that they don't currently have selected for questing, and or provide
-- a way to one-click update it for the current zone."
--
-- Your zones are the ones you tick in the Flow Router (Route, Zones; Nav.lua,
-- N.ZoneOn). When you come into a zone that has quests for you (steps of
-- yours there, or quests to pick up around your level) and it isn't one of
-- yours, a bar comes up at the top of the screen: "You're in Stonetalon
-- Mountains: not one of your questing zones", what it holds, and two
-- buttons: Quest here (it becomes one of your zones, its quests come onto
-- your route) and No thanks. Its edge pulses orange for a few seconds. Not
-- on a flight, in a dungeon or in a fight. Ctrl-drag moves it.
--
-- 0.35.374: "The zeppelin zones out as you're leaving Durotar and fades back
-- in after a bit of a loading screen ... I had to say no twice. We should
-- wait for a little while after being in that zone. And if the user's already
-- said no, we should never ask them again for that zone."
--   * No is kept, for this character: that zone is never asked about again.
--     (Tick it in the Flow Router, Route, Zones, whenever you want it.)
--   * The note waits until you've been in the zone Z.SETTLE seconds without a
--     break, so passing through, a zeppelin leaving and the game's flickers
--     between zones don't bring it up.
-- 0.35.386: "This thing popping up all the time asking me if I want a quest
-- here is super annoying ... I have a custom route set ... maybe just wait
-- until I accept the first quest in that area."
--   * The note only comes up once you've accepted a quest in that zone (this
--     session): that's you questing there, not travelling through.
--   * Never while you're on a custom route: you're on a mission.
-- Setting: "Say when you're in a zone you haven't picked" (Finding your way).

local _, ns = ...
local Z = {}
ns.zoneNotice = Z

Z.PULSE = 6       -- seconds the edge pulses
Z.CHECK = 2       -- seconds between looks
Z.TOP = -170      -- where it sits, under the top of the screen (until you move it)
Z.SETTLE = 30     -- seconds in a zone, without a break, before the note may come up

-- Pure: have you been here long enough to be asked?
function Z.Settled(seconds, wait) return (seconds or 0) >= (wait or Z.SETTLE) end

-- The zones you said No to (this character), never asked about again.
function Z.Declined(zone)
    local no = ns.db and ns.db.nav and ns.db.nav.zoneNo
    return zone ~= nil and no ~= nil and no[zone] == true
end
function Z.Decline(zone, on)
    if not zone then return end
    ns.db.nav.zoneNo = ns.db.nav.zoneNo or {}
    ns.db.nav.zoneNo[zone] = on and true or nil
end

function Z.On() return not (ns.db and ns.db.nav and ns.db.nav.zoneNotice == false) end

-- Pure: does the note show?
--   here: the zone you're in; on: is it one of yours; choice: its row in the
--   Zones list (nil: nothing there for you); dismissed: the zone you said
--   No thanks to; busy: on a flight, in a dungeon or in a fight.
--   accepted: you took a quest in this zone (false: not yet; nil: not told);
--   custom: you're on a custom route.
function Z.Wanted(here, on, choice, dismissed, busy, accepted, custom)
    if not here or on or busy or not choice or dismissed == here then return false end
    if accepted == false or custom then return false end
    local r, w = choice.route, choice.where
    return ((r and r.steps or 0) > 0) or ((w and w.quests or 0) > 0)
end

-- Pure: the note's two lines.
function Z.Words(choice)
    local title = string.format("You're in %s: not one of your questing zones", tostring(choice and choice.name or "this zone"))
    local parts = {}
    local r, w = choice and choice.route, choice and choice.where
    if r and r.steps > 0 then parts[#parts + 1] = string.format("%d step%s of yours here", r.steps, r.steps == 1 and "" or "s") end
    if w and w.quests > 0 then
        parts[#parts + 1] = string.format("%d quest%s to pick up, %s", w.quests, w.quests == 1 and "" or "s",
            w.min == w.max and ("level " .. w.min) or string.format("levels %d-%d", w.min, w.max))
    end
    if w and w.suggested then parts[#parts + 1] = "suggested for your level" end
    return title, table.concat(parts, "; ")
end

local bar
local function build()
    local T = ns.theme
    local f = CreateFrame("Frame", "FlowZoneNotice", UIParent)
    f:SetSize(440, 62)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(T.BAR[1], T.BAR[2], T.BAR[3], 0.95)
    local o = T.arrow
    f.accent = f:CreateTexture(nil, "BORDER")
    f.accent:SetPoint("TOPLEFT"); f.accent:SetPoint("BOTTOMLEFT"); f.accent:SetWidth(4)
    f.accent:SetColorTexture(o[1], o[2], o[3], 1)
    -- The edge that pulses (ns.pulse: the orange of "Flow suggests this").
    f.edge = {}
    local pc = ns.pulse and ns.pulse.COLOR or o
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                           { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = f:CreateTexture(nil, "BORDER", nil, 1)
        t:SetPoint(pts[1]); t:SetPoint(pts[2])
        if i <= 2 then t:SetHeight(2) else t:SetWidth(2) end
        t:SetColorTexture(pc[1], pc[2], pc[3], 1)
        f.edge[i] = t
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 14, -9)
    f.title:SetPoint("RIGHT", -10, 0)
    f.title:SetJustifyH("LEFT")
    f.detail = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.detail:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.detail:SetPoint("RIGHT", -10, 0)
    f.detail:SetJustifyH("LEFT")
    f.later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.later:SetSize(80, 20)
    f.later:SetPoint("BOTTOMRIGHT", -8, 7)
    f.later:SetText("No thanks")
    f.go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.go:SetSize(96, 20)
    f.go:SetPoint("RIGHT", f.later, "LEFT", -6, 0)
    f.go:SetText("Quest here")
    f.go:SetScript("OnClick", function() Z.QuestHere() end)
    f.go:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Quest here", 1, 1, 1)
        GameTooltip:AddLine("Adds this zone to your zones (Flow Router, Route, Zones): its quests come onto your route.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.go:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.later:SetScript("OnClick", function() Z.NotNow() end)
    f.later:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("No thanks", 1, 1, 1)
        GameTooltip:AddLine("Flow won't ask about this zone again. To quest here later, tick it in the Flow Router (Route, Zones).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.later:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.db.nav.zoneNoteSpot = ns.db.nav.zoneNoteSpot or {}
    if ns.db.nav.zoneNoteSpot.point and ns.RestorePlace then
        ns.RestorePlace(f, ns.db.nav.zoneNoteSpot)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, Z.TOP)
    end
    if ns.MoveHandle then ns:MoveHandle(f, { name = "the zone note", save = function() return ns.db.nav.zoneNoteSpot end }) end
    f:Hide()
    return f
end

local function stopPulse()
    if not (bar and ns.pulse) then return end
    for _, t in ipairs(bar.edge) do ns.pulse.Remove(t) end
end

-- Shows the note for a zone (its row in the Zones list). quiet: not in the
-- log (the tests).
function Z.Show(here, choice, quiet)
    bar = bar or build()
    local title, detail = Z.Words(choice)
    bar.title:SetText(title)
    bar.detail:SetText(detail)
    if bar.zone ~= here or not bar:IsShown() then
        bar.zone = here
        bar:Show()
        if ns.pulse then
            for _, t in ipairs(bar.edge) do ns.pulse.Add(t) end
            local shownFor = here
            C_Timer.After(Z.PULSE, function() if bar.zone == shownFor then stopPulse() end end)
        end
        if not quiet then ns:Log("route", title .. (detail ~= "" and (" (" .. detail .. ")") or "")) end
    end
    return bar
end
function Z.Hide()
    if bar and bar:IsShown() then
        stopPulse()
        bar:Hide()
    end
end

-- Quest here: the zone you're in becomes one of yours.
function Z.QuestHere()
    local zone = bar and bar.zone
    Z.Hide()
    local N = ns.nav
    if not (zone and N and N.SetZoneOn) then return end
    N.SetZoneOn(zone, true)
    ns:Print(tostring(N.ZoneNameOf and N.ZoneNameOf(zone) or zone)
        .. " is one of your zones now: its quests are on your route (Flow Router, Route, Zones).")
end
function Z.NotNow()
    Z.Decline(bar and bar.zone, true)
    Z.Hide()
end

-- On a flight, in a dungeon or in a fight: nothing to pick now.
local function busy()
    local Safe = ns.api and ns.api.Safe or function(v) return v end
    if UnitOnTaxi and Safe(UnitOnTaxi("player")) then return true end
    if IsInInstance and Safe((IsInInstance())) then return true end
    return InCombatLockdown() and true or false
end

-- Looks again: shows, keeps or puts away the note.
function Z.Check()
    local N = ns.nav
    if not (Z.On() and N and N.ZoneOn and N.PlayerPos) then Z.Hide() return end
    local p = N:PlayerPos()
    local here = p and N.ZoneOf and N.ZoneOf(p.map)
    if here ~= Z.lastHere then
        Z.lastHere = here
        Z.enteredAt = GetTime()   -- (a new zone, or back after a flicker: the wait starts again)
    end
    local on = here and N.ZoneOn(here)
    local choice
    if here and not on then
        local choices = N.ZoneChoicesNow()
        for _, c in ipairs(choices) do
            if c.zone == here then choice = c break end
        end
    end
    local settled = Z.Settled(GetTime() - (Z.enteredAt or GetTime()))
    local accepted = here ~= nil and Z.accepted[here] == true
    local custom = ns.focus and ns.focus.Active and ns.focus.Active() or false
    if settled and Z.Wanted(here, on, choice, Z.Declined(here) and here or nil, busy(), accepted, custom) then Z.Show(here, choice) else Z.Hide() end
end

-- The zones you've accepted a quest in since you logged in.
Z.accepted = {}
function Z.Accepted(zone)
    if zone == nil then return false end
    Z.accepted[zone] = true
    return true
end
ns:On("QUEST_ACCEPTED", function()
    local N = ns.nav
    local p = N and N.PlayerPos and N:PlayerPos()
    local here = p and N.ZoneOf and N.ZoneOf(p.map)
    if Z.Accepted(here) and C_Timer then C_Timer.After(1, function() pcall(Z.Check) end) end
end)
ns:OnLoad(function(saved)
    saved.nav = saved.nav or {}
    saved.nav.zoneNo = saved.nav.zoneNo or {}
end)
ns:PerCharacter("nav.zoneNo")

ns:On("PLAYER_LOGIN", function()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(Z.CHECK, function() pcall(Z.Check) end) end
end)
ns:On("ZONE_CHANGED_NEW_AREA", function() if C_Timer then C_Timer.After(1, function() pcall(Z.Check) end) end end)

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck{ group = "route", label = "Say when you're in a zone you haven't picked",
        tip = "A bar at the top of the screen when you accept a quest in a zone that isn't one of your zones "
            .. "(Flow Router, Route, Zones), with a button to quest there. Not while you're on a custom route.",
        get = Z.On,
        set = function(on) ns.db.nav.zoneNotice = on and true or false; pcall(Z.Check) end }
end

function Z._Bar() return bar end   -- (tests)
