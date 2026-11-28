-------------------------------------------------------------------------------
-- Flow - ErrorBand.lua
-- A dark band behind the game's red messages at the top of the screen
-- (0.35.433).
--
-- "When errors happen, there's red text that appears at the top of the screen,
-- but it's really hard to read sometimes, especially on a reddish or brownish
-- background ... give it some kind of faded background behind it that's a
-- little darker black so that the text appears very prominently."
--
-- The game writes those lines ("Inventory is full", "Out of range") into its
-- own frame, UIErrorsFrame, with nothing behind them. Flow puts a frame of
-- its own behind that one: a soft black band as wide as the longest line
-- showing and as tall as the lines showing, which fades out with them.
-- Nothing of the game's frame is changed: Flow only listens for lines being
-- added to it (hooksecurefunc) and draws behind it.
-- Flow Settings, On your screen; /flow errorband on|off.
-------------------------------------------------------------------------------

local _, ns = ...
local EB = {}
ns.errorBand = EB

EB.ALPHA = 0.6      -- how dark the band is
EB.PAD_X, EB.PAD_Y = 14, 3
EB.MAX_LINES = 3    -- the game shows this many at once
EB.HOLD, EB.FADE = 5, 3   -- seconds a line stays, then fades (read from the game's frame when it says)
EB.FALLBACK_WIDTH = 320   -- a line whose words the game hides

function EB.On() return not (ns.db and ns.db.screen and ns.db.screen.errorBand == false) end

-- Pure: note a line. list: { { text, at, width } } oldest first. The game
-- shows a line already up again in place (it doesn't add a second): so does this.
function EB.Add(list, text, now, width, max)
    for i, m in ipairs(list) do
        if text ~= nil and m.text == text then
            table.remove(list, i)
            break
        end
    end
    list[#list + 1] = { text = text, at = now, width = width }
    while #list > (max or EB.MAX_LINES) do table.remove(list, 1) end
    return list
end

-- Pure: what's showing now: how many lines, the widest, and how strong the
-- band is (1, then down to 0 as the last line fades); 0 lines: nothing.
function EB.Showing(list, now, hold, fade)
    hold, fade = hold or EB.HOLD, fade or EB.FADE
    local n, width, strength = 0, 0, 0
    for _, m in ipairs(list or {}) do
        local age = now - m.at
        if age < hold + fade then
            n = n + 1
            if (m.width or 0) > width then width = m.width end
            local s = age <= hold and 1 or (1 - (age - hold) / fade)
            if s > strength then strength = s end
        end
    end
    return n, width, strength
end

local list, band, measure = {}, nil, nil

local function times()
    local f = UIErrorsFrame
    local hold = f and f.GetTimeVisible and tonumber(f:GetTimeVisible()) or EB.HOLD
    local fade = f and f.GetFadeDuration and tonumber(f:GetFadeDuration()) or EB.FADE
    return hold, fade
end

local function build()
    local f = UIErrorsFrame
    band = CreateFrame("Frame", "FlowErrorBand", UIParent)
    band:SetFrameStrata("LOW")
    band:EnableMouse(false)
    band.mid = band:CreateTexture(nil, "BACKGROUND")
    band.mid:SetColorTexture(0, 0, 0, 1)
    band.mid:SetPoint("TOPLEFT", 24, 0)
    band.mid:SetPoint("BOTTOMRIGHT", -24, 0)
    -- Soft ends: black fading out to nothing.
    local function fadeEnd(left)
        local t = band:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetWidth(24)
        if left then t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT") else t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT") end
        local ok = false
        if t.SetGradient and CreateColor then
            ok = pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(0, 0, 0, left and 0 or 1), CreateColor(0, 0, 0, left and 1 or 0))
        end
        if not ok then t:SetColorTexture(0, 0, 0, 0.5) end
        return t
    end
    band.left, band.right = fadeEnd(true), fadeEnd(false)
    measure = band:CreateFontString(nil, "ARTWORK")
    measure:Hide()
    band:Hide()
    band:SetScript("OnUpdate", function(self)
        local hold, fade = times()
        local n, width, strength = EB.Showing(list, GetTime(), hold, fade)
        if n == 0 or not EB.On() or not (f and f:IsShown()) then self:Hide() return end
        local _, size = f:GetFont()
        local line = (tonumber(size) or 16) + (f.GetSpacing and tonumber(f:GetSpacing()) or 0)
        self:SetSize(width + 2 * (EB.PAD_X + 24), n * line + 2 * EB.PAD_Y)
        self:ClearAllPoints()
        -- (The lines fill the game's frame from the top, or from the bottom: as it says.)
        local top = not (f.GetInsertMode and tostring(f:GetInsertMode()):upper() == "BOTTOM")
        if top then self:SetPoint("TOP", f, "TOP", 0, EB.PAD_Y) else self:SetPoint("BOTTOM", f, "BOTTOM", 0, -EB.PAD_Y) end
        self:SetAlpha(EB.ALPHA * strength)
    end)
    return band
end

-- A line was added to the game's frame.
function EB.Note(text)
    if not (EB.On() and UIErrorsFrame) then return false end
    band = band or build()
    text = ns.api and ns.api.Safe and ns.api.Safe(text) or text
    local width = EB.FALLBACK_WIDTH
    if type(text) == "string" then
        local font, size, flags = UIErrorsFrame:GetFont()
        if font then
            measure:SetFont(font, size, flags)
            measure:SetText(text)
            width = math.min(measure:GetStringWidth() or width, UIErrorsFrame:GetWidth() or 512)
        end
    else
        text = nil
    end
    EB.Add(list, text, GetTime(), width)
    band:Show()
    return true
end
EB._band = function() return band end   -- (tests)
EB._list = function() return list end

if UIErrorsFrame and hooksecurefunc then
    hooksecurefunc(UIErrorsFrame, "AddMessage", function(_, text) pcall(EB.Note, text) end)
end

ns.commands.errorband = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.screen = ns.db.screen or {}
        ns.db.screen.errorBand = (arg == "on")
    end
    ns:Print("the dark band behind the game's red messages: " .. (EB.On() and "on" or "off") .. " (/flow errorband on|off)")
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
