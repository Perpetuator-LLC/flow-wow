-- Load splash: a short animated title card when you log in or /reload,
-- showing that Flow is running and what it's working with.
-- Replaces the old "hello sooth" popup (popups from addons can taint
-- Blizzard's own dialogs). /flow splash replays it; /flow splash off.

local _, ns = ...

local GOLD = { 1.0, 0.82, 0.25 }
local BAR_W = 460      -- width of the two gold bars
local INTRO = 0.15     -- seconds for the bars to sweep in
local SHOW_TIME = 1.75  -- seconds the bars count down (whole splash: 0.15 + 1.75 + 0.1 = 2 s)
local frame

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
local function status()
    local bits = {}
    local spells = ns.rotation and count(ns.rotation:KnownSpells()) or 0
    bits[#bits + 1] = "rotation " .. spells .. " spells"
    local src = ns.quests and ns.quests:Source()
    bits[#bits + 1] = src and src.label == "Questie" and "Questie linked" or "no quest database"
    local learned = ns:Get("learned", "combatlog")
    local fights = #(ns.db.profiler and ns.db.profiler.fights or {}) + (learned and learned.fights or 0)
    bits[#bits + 1] = fights .. " fights learned"
    local trail = 0
    for _, g in pairs(ns.db.nav and ns.db.nav.graphs or {}) do trail = trail + #g.x end
    bits[#bits + 1] = trail .. " trail points"
    return table.concat(bits, "   |cff666666•|r   ")
end

local function scaleAnim(group, fromX, toX, duration)
    local a = group:CreateAnimation("Scale")
    if a.SetScaleFrom then
        a:SetScaleFrom(fromX, 1)
        a:SetScaleTo(toX, 1)
    else
        a:SetFromScale(fromX, 1)
        a:SetToScale(toX, 1)
    end
    a:SetDuration(duration)
    a:SetOrigin("CENTER", 0, 0)
    a:SetSmoothing("OUT")
    return a
end

local function build()
    local f = CreateFrame("Frame", "FlowSplash", UIParent)
    f:SetSize(520, 130)
    -- Below the game's own zone name text, which appears near the top on login.
    f:SetPoint("TOP", UIParent, "TOP", 0, -260)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)

    -- Soft dark band behind the text.
    f.band = f:CreateTexture(nil, "BACKGROUND")
    f.band:SetPoint("TOPLEFT", 0, -18)
    f.band:SetPoint("BOTTOMRIGHT", 0, 8)
    f.band:SetColorTexture(0, 0, 0, 0.45)

    -- Thin golden lines: they sweep out from the middle, then count down the
    -- time the splash stays up. The top one empties left to right (pinned to
    -- its right end), the bottom one right to left (pinned to its left end).
    -- When both are empty, the splash is gone.
    local function line(y, pin)
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
        t:SetSize(BAR_W, 2)
        t:SetPoint(pin, f, "TOP", pin == "RIGHT" and BAR_W / 2 or -BAR_W / 2, y)
        local g = t:CreateAnimationGroup()
        scaleAnim(g, 0.01, 1, INTRO)
        t.sweep = g
        return t
    end
    f.top = line(-18, "RIGHT")
    f.bottom = line(-122, "LEFT")

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(STANDARD_TEXT_FONT, 46, "OUTLINE")
    f.title:SetPoint("TOP", 0, -26)
    f.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    f.title:SetText("F  L  O  W")

    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4)

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.status:SetPoint("TOP", f.sub, "BOTTOM", 0, -8)
    f.status:SetTextColor(0.8, 0.8, 0.8)

    local fadeIn = f:CreateAnimationGroup()
    local a = fadeIn:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.15)
    a:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    f.fadeIn = fadeIn

    local fadeOut = f:CreateAnimationGroup()
    local b = fadeOut:CreateAnimation("Alpha")
    b:SetFromAlpha(1)
    b:SetToAlpha(0)
    b:SetDuration(0.1)  -- gone 100 ms after the bars empty
    b:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function() f:Hide() end)
    f.fadeOut = fadeOut

    f:Hide()
    return f
end

local token = 0
local function show()
    frame = frame or build()
    token = token + 1
    local mine = token
    local name = UnitName("player") or "friend"
    frame.sub:SetText(string.format("|cffbbbbbb(unfettered)|r   ready, %s   |cff888888v%s  ·  /flow help  ·  /flow settings|r", name, version()))
    local ok, s = pcall(status)
    frame.status:SetText(ok and s or "")
    frame.fadeOut:Stop()
    frame:SetAlpha(0)
    frame.top:SetWidth(BAR_W)
    frame.bottom:SetWidth(BAR_W)
    frame:Show()
    frame.fadeIn:Play()
    frame.top.sweep:Play()
    frame.bottom.sweep:Play()
    if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end

    -- Count down: after the sweep-in, both bars shrink to nothing over
    -- SHOW_TIME; then the splash fades out.
    local t = 0
    frame:SetScript("OnUpdate", function(self, dt)
        if mine ~= token then self:SetScript("OnUpdate", nil) return end
        t = t + dt
        if t < INTRO then return end
        local left = 1 - (t - INTRO) / SHOW_TIME
        if left <= 0 then
            self.top:SetWidth(0.1); self.bottom:SetWidth(0.1)
            self:SetScript("OnUpdate", nil)
            self.fadeOut:Play()
            return
        end
        self.top:SetWidth(BAR_W * left)
        self.bottom:SetWidth(BAR_W * left)
    end)
end

ns:OnLoad(function(saved)
    saved.splash = saved.splash or {}
    if saved.splash.enabled == nil then saved.splash.enabled = true end
end)

local shown = false
ns:On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
    -- Only on login or /reload, not on every loading screen.
    if isInitialLogin or isReloadingUi or (isInitialLogin == nil and not shown) then
        shown = true
        if ns.db.splash.enabled then
            -- Give spells and quest data a moment to load so the status is right.
            C_Timer.After(1.5, function() pcall(show) end)
        end
    end
end)

ns.commands.splash = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.splash.enabled = (arg == "on")
        ns:Print("load splash " .. arg)
    else
        show()
    end
end
ns.commands.hello = ns.commands.splash
