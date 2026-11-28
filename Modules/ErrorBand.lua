-------------------------------------------------------------------------------
-- Flow - ErrorBand.lua
-- A dark band behind the game's red messages at the top of the screen
-- (0.35.433; measured from the lines themselves since 0.35.436).
--
-- "When errors happen, there's red text that appears at the top of the screen,
-- but it's really hard to read sometimes, especially on a reddish or brownish
-- background ... give it some kind of faded background behind it that's a
-- little darker black so that the text appears very prominently."
--
-- The game writes those lines ("Inventory is full", "Out of range") into its
-- own frame, UIErrorsFrame, with nothing behind them. Flow puts a frame of
-- its own behind that one: a soft black band with faded ends.
--
-- "The black background timing is off" (0.35.436, with a picture: three lines
-- up, the band behind the top one only). The first version guessed: it
-- counted the lines it heard being added and how long each should stay. It
-- counted a line said twice as one (the game shows it twice) and its clock
-- wasn't the game's. Now nothing is guessed: several times a second Flow
-- looks at the lines the game's frame is drawing (its text pieces: which
-- are shown, where each is, how wide its words are, how faded it is) and
-- the band is exactly their box, as strong as the least faded of them.
-- Reading only: nothing of the game's frame is changed.
-- Flow Settings, On your screen; /flow errorband on|off.
-------------------------------------------------------------------------------

local _, ns = ...
local EB = {}
ns.errorBand = EB

EB.ALPHA = 0.6      -- how dark the band is
EB.PAD_X, EB.PAD_Y = 14, 3
EB.END = 24         -- the faded ends
EB.EVERY = 0.05     -- seconds between looks

function EB.On() return not (ns.db and ns.db.screen and ns.db.screen.errorBand == false) end

-- Pure: the box of the lines showing.
--   lines: { { top, bottom, width, alpha } } (screen units; alpha 0..1)
-- -> top, bottom, width, strength (the least faded line's), how many; nil with none
function EB.Box(lines, floor)
    local top, bottom, width, strength, n
    for _, l in ipairs(lines or {}) do
        if type(l.top) == "number" and type(l.bottom) == "number" and (l.width or 0) > 0 and (l.alpha or 0) > (floor or 0.03) then
            n = (n or 0) + 1
            if not top or l.top > top then top = l.top end
            if not bottom or l.bottom < bottom then bottom = l.bottom end
            if not width or l.width > width then width = l.width end
            if not strength or l.alpha > strength then strength = l.alpha end
        end
    end
    if not n then return nil end
    return top, bottom, width, strength, n
end

-- The lines the game's frame is drawing now, as EB.Box wants them.
function EB.Lines(frame)
    local out = {}
    if not (frame and frame.GetRegions and frame:IsShown()) then return out end
    local Safe = ns.api and ns.api.Safe or function(v) return v end
    local frameAlpha = Safe(frame:GetAlpha()) or 1
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" and r:IsShown() then
            local ok, text = pcall(r.GetText, r)
            text = ok and text or nil
            -- (A line whose words the game hides still has a width.)
            local okW, w = pcall(r.GetStringWidth, r)
            w = okW and Safe(w) or nil
            local shown = (type(text) ~= "string") or text ~= ""
            if shown and type(w) == "number" and w > 0 then
                out[#out + 1] = { top = Safe(r:GetTop()), bottom = Safe(r:GetBottom()), width = w,
                                  alpha = (Safe(r:GetAlpha()) or 1) * frameAlpha }
            end
        end
    end
    return out
end

local band
local function build()
    band = CreateFrame("Frame", "FlowErrorBand", UIParent)
    band:SetFrameStrata("LOW")
    band:EnableMouse(false)
    band.mid = band:CreateTexture(nil, "BACKGROUND")
    band.mid:SetColorTexture(0, 0, 0, 1)
    band.mid:SetPoint("TOPLEFT", EB.END, 0)
    band.mid:SetPoint("BOTTOMRIGHT", -EB.END, 0)
    -- Soft ends: black fading out to nothing.
    local function fadeEnd(left)
        local t = band:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetWidth(EB.END)
        if left then t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT") else t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT") end
        local ok = false
        if t.SetGradient and CreateColor then
            ok = pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(0, 0, 0, left and 0 or 1), CreateColor(0, 0, 0, left and 1 or 0))
        end
        if not ok then t:SetColorTexture(0, 0, 0, 0.5) end
        return t
    end
    band.left, band.right = fadeEnd(true), fadeEnd(false)
    band:Hide()
    return band
end

-- Looks at the game's lines and puts the band behind them (or away).
function EB.Update()
    local f = UIErrorsFrame
    if not (f and EB.On()) then
        if band then band:Hide() end
        return 0
    end
    local top, bottom, width, strength, n = EB.Box(EB.Lines(f))
    if not n then
        if band then band:Hide() end
        return 0
    end
    band = band or build()
    -- (The lines' places are in the game frame's own scale: brought to the band's.)
    local k = (f:GetEffectiveScale() or 1) / (band:GetEffectiveScale() or 1)
    local cx = f:GetCenter()
    band:ClearAllPoints()
    band:SetPoint("TOP", UIParent, "BOTTOMLEFT", (cx or 0) * k, top * k + EB.PAD_Y)
    band:SetSize(width * k + 2 * (EB.PAD_X + EB.END), (top - bottom) * k + 2 * EB.PAD_Y)
    band:SetAlpha(EB.ALPHA * math.min(1, strength))
    band:Show()
    EB.last = n
    return n
end
EB._band = function() return band end   -- (tests)

local driver, acc = CreateFrame("Frame"), 0
driver:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < EB.EVERY then return end
    acc = 0
    local ok, err = pcall(EB.Update)
    if not ok and not EB.failed then
        EB.failed = true
        ns:Log("screen", "error band failed: " .. tostring(err))
    end
end)

ns.commands.errorband = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.screen = ns.db.screen or {}
        ns.db.screen.errorBand = (arg == "on")
    end
    local lines = UIErrorsFrame and EB.Lines(UIErrorsFrame) or {}
    ns:Print(string.format("the dark band behind the game's red messages: %s (/flow errorband on|off); lines showing now: %d%s",
        EB.On() and "on" or "off", #lines, EB.failed and "; it failed once, see the log" or ""))
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "screen",
        label = "A dark band behind the game's red messages",
        note = "(\"Inventory is full\", \"Out of range\")",
        tip = "A soft black band behind the red and yellow lines the game writes at the top of the screen, so they can be read over any ground. It fades out with them.",
        get = function() return EB.On() end,
        set = function(on)
            ns.db.screen = ns.db.screen or {}
            ns.db.screen.errorBand = on and true or false
        end,
    })
end
