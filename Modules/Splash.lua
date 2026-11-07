-- Login intro, played on Flow's arrow (it replaced a separate title card):
-- the arrow spins up and settles into its ring with FLOW in the middle,
-- while the text under it says "Flow (unfettered)", the version and what
-- Flow has to work with. Then the arrow goes back to pointing the way.
-- /flow splash replays it; Options > AddOns > Flow turns it off.

local _, ns = ...
local I = {}
ns.intro = I

local SPIN, HOLD = 2.0, 2.6   -- seconds: spinning, then the ring with FLOW
local TURNS = 2

local function version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ns.name, "Version") or "?"
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- One short status line about what Flow has to work with.
function I.Status()
    local bits = {}
    local spells = ns.rotation and count(ns.rotation:KnownSpells()) or 0
    bits[#bits + 1] = spells .. " spells"
    local src = ns.quests and ns.quests:Source()
    bits[#bits + 1] = src and src.label == "Questie" and "Questie linked" or "no quest database"
    local plan = ns.nav and ns.nav.plan
    if plan and #plan > 0 then bits[#bits + 1] = #plan .. " stops planned" end
    return table.concat(bits, "  ·  ")
end

-- The arrow's rotation t seconds into the intro: fast at first, easing out,
-- TURNS full turns, ending pointing up.
function I.SpinAngle(t)
    local u = math.min(math.max(t / SPIN, 0), 1)
    return (1 - (1 - u) ^ 3) * TURNS * 2 * math.pi
end

local driver = CreateFrame("Frame")

function I:Play()
    local f = ns.nav and ns.nav.arrowFrame
    if not (f and f.arrow) or ns.db.nav.enabled == false then ns.nav.intro = nil return end
    local a = f.arrow
    if not f.introText then
        f.introText = f:CreateFontString(nil, "OVERLAY")
        f.introText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
        f.introText:SetPoint("CENTER", 0, 1)
        f.introText:SetTextColor(1, 0.82, 0.25)
        f.introText:SetText("FLOW")
    end
    ns.nav.intro = true   -- the arrow's own update leaves it alone meanwhile
    f:Show()
    local col = ns.theme.route
    a:SetVertexColor(col[1], col[2], col[3])
    a:SetArrived(false)
    f.text:SetText("|cffffd200Flow|r |cffbbbbbb(unfettered)|r")
    local ok, s = pcall(I.Status)
    f.sub:SetText("v" .. version() .. (ok and ("  ·  " .. s) or ""))
    f.introText:SetAlpha(0)
    f.introText:Show()
    local t0 = GetTime()
    f.introStatusAt = nil
    driver:SetScript("OnUpdate", function()
        local t = GetTime() - t0
        -- Quest data and the route arrive during the intro: keep the status current.
        if t - (f.introStatusAt or 0) > 0.5 then
            f.introStatusAt = t
            local okS, st = pcall(I.Status)
            f.sub:SetText("v" .. version() .. (okS and ("  ·  " .. st) or ""))
        end
        if t < SPIN then
            a:SetRotation(I.SpinAngle(t))
            f.introText:SetAlpha(t / SPIN)
        elseif t < SPIN + HOLD then
            if not a.arrived then a:SetArrived(true) end   -- the ring, FLOW in the middle
            f.introText:SetAlpha(1)
        else
            driver:SetScript("OnUpdate", nil)
            f.introText:Hide()
            a:SetArrived(false)
            ns.nav.intro = nil   -- back to pointing the way
        end
    end)
end

ns:OnLoad(function(saved)
    saved.splash = saved.splash or {}
    if saved.splash.enabled == nil then saved.splash.enabled = true end
    -- Hold the arrow from the very start, so it never shows a quest first
    -- and then gets taken over (that flashed).
    if saved.splash.enabled and ns.nav then ns.nav.intro = true end
end)

local shown = false
ns:On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
    -- Only on login or /reload, not on every loading screen.
    if not shown or isInitialLogin or isReloadingUi then
        shown = true
        if ns.db.splash.enabled then
            -- At once: the status line fills in as quest data and the route arrive.
            local ok = pcall(I.Play, I)
            if not ok and ns.nav then ns.nav.intro = nil end
            -- Never leave the arrow held if the intro didn't run to the end.
            C_Timer.After(SPIN + HOLD + 2, function() if ns.nav and not driver:GetScript("OnUpdate") then ns.nav.intro = nil end end)
        end
    end
end)

ns.commands.splash = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.splash.enabled = (arg == "on")
        ns:Print("login intro on the arrow " .. arg)
    else
        I:Play()
    end
end
ns.commands.hello = ns.commands.splash
ns.commands.intro = ns.commands.splash
