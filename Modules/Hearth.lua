-- Hearthstone reminder. When you start resting at an inn that isn't where your
-- hearthstone is set, Flow asks whether to set it here: talk to the
-- innkeeper and choose "Make this inn your home". It asks once per inn
-- ("Not here" remembers that), and says so more strongly when most of your
-- route is in this zone.
-- Knowing "is it already set here?": Flow remembers where you were standing
-- when you last set your hearthstone; before that, it compares names.

local _, ns = ...
local H = {}
ns.hearth = H

local prompt

local function texts()
    return { GetSubZoneText and GetSubZoneText() or "", GetMinimapZoneText and GetMinimapZoneText() or "",
             GetZoneText and GetZoneText() or "" }
end

local function placeKey() return (GetZoneText() or "?") .. "/" .. (GetSubZoneText() or "?") end

-- true = hearth is set here; false = elsewhere; nil = can't tell
local function boundHere()
    local p = ns.nav and ns.nav:PlayerPos()
    local saved = ns.db.hearth.pos
    if saved and p and saved.cont == p.cont and saved.wx then
        local dx, dy = p.wx - saved.wx, p.wy - saved.wy
        return (dx * dx + dy * dy) < 120 * 120
    end
    local bind = GetBindLocation and GetBindLocation()
    if not bind then return nil end
    for _, t in ipairs(texts()) do
        if t ~= "" and (t == bind or t:find(bind, 1, true) or bind:find(t, 1, true)) then return true end
    end
    return false
end

-- Share of the planned route that is in the zone you're in.
local function routeShareHere()
    local plan = ns.nav and ns.nav.plan
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not (plan and #plan > 0 and here) then return 0 end
    local n = 0
    for _, s in ipairs(plan) do if s.point and s.point.map == here then n = n + 1 end end
    return n / #plan
end

local function showPrompt(bind, strong)
    if not prompt then
        local f = CreateFrame("Frame", "FlowHearthPrompt", UIParent)
        f:SetSize(380, 96)
        f:SetPoint("TOP", 0, -170)
        f:SetFrameStrata("DIALOG")
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()
        f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
        local top = f:CreateTexture(nil, "BORDER")
        top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
        local c = ns.theme.arrow
        top:SetColorTexture(c[1], c[2], c[3], 0.95)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(32, 32)
        f.icon:SetPoint("TOPLEFT", 10, -10)
        f.icon:SetTexture("Interface\\Icons\\INV_Misc_Rune_01")
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 50, -10)
        f.text:SetWidth(320)
        f.text:SetJustifyH("LEFT")
        local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        ok:SetSize(110, 22); ok:SetPoint("BOTTOMLEFT", 50, 10); ok:SetText("Got it")
        ok:SetScript("OnClick", function() f:Hide() end)
        local no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        no:SetSize(100, 22); no:SetPoint("LEFT", ok, "RIGHT", 6, 0); no:SetText("Not here")
        no:SetScript("OnClick", function() ns.db.hearth.skip[placeKey()] = true; f:Hide() end)
        local never = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        never:SetSize(90, 22); never:SetPoint("LEFT", no, "RIGHT", 6, 0); never:SetText("Never ask")
        never:SetScript("OnClick", function() ns.db.hearth.off = true; f:Hide() end)
        prompt = f
    end
    prompt.text:SetText(string.format("You're at an inn. Your hearthstone is set to |cffffd200%s|r.\n%s"
        .. "To set it here: talk to the innkeeper, choose \"Make this inn your home\".",
        bind or "somewhere else",
        strong and "Most of your next stops are in this zone, so setting it here saves walking.\n" or "Set it here?\n"))
    prompt:Show()
end

local function check()
    if ns.db.hearth.off or not (IsResting and IsResting()) then return end
    if UnitLevel("player") < 2 then return end
    if ns.db.hearth.skip[placeKey()] then return end
    local here = boundHere()
    if here ~= false then return end
    ns:Log("hearth", "resting at " .. placeKey() .. ", bound to " .. tostring(GetBindLocation()))
    showPrompt(GetBindLocation(), routeShareHere() >= 0.5)
    ns.db.hearth.skip[placeKey()] = true  -- ask once per inn
end

ns:OnLoad(function(saved)
    saved.hearth = saved.hearth or {}
    saved.hearth.skip = saved.hearth.skip or {}
end)

ns:On("PLAYER_UPDATE_RESTING", function() C_Timer.After(1, function() pcall(check) end) end)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(12, function() pcall(check) end) end)

-- You set your hearthstone: remember where, so "set here?" is exact next time.
ns:On("HEARTHSTONE_BOUND", function()
    local p = ns.nav and ns.nav:PlayerPos()
    if p then ns.db.hearth.pos = { cont = p.cont, wx = p.wx, wy = p.wy } end
    ns.db.hearth.skip[placeKey()] = true
    if prompt then prompt:Hide() end
    ns:Print("hearthstone set to " .. tostring(GetBindLocation()))
end)

ns.commands.hearth = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.hearth.off = (arg == "off")
        ns:Print("hearthstone reminders " .. arg)
    else
        ns:Print("hearthstone: " .. tostring(GetBindLocation()) .. ". Reminders " .. (ns.db.hearth.off and "off" or "on")
            .. ". /flow hearth on|off")
    end
end
