-------------------------------------------------------------------------------
-- Flow - Rotation/Sheen.lua
-- A small glint that runs round the easy buttons' coloured edges (0.35.429).
--
-- "On the flow easy buttons, the color and border is great. It's just kind
-- of boring ... It would be cool if I had a little animation, like a little
-- glistening, or maybe a tracker that went around it. But we don't want to
-- miscommunicate that there's some action or something's active."
--
-- So it's deliberately quiet: a short lighter streak travels once round the
-- edge of the target button's icon and of the self button, taking S.RUN
-- seconds, and then nothing happens for S.REST seconds. It's a lighter shade
-- of whatever colour the edge is (white, added on), it never pulses, never
-- changes speed and never depends on what the button would cast, so it can't
-- be read as "press now". The glows that do mean something (Pulse.lua, the
-- swing glow) look nothing like it.
--
-- Its frames are Flow's own, parented to the screen and pinned to the
-- buttons, so nothing is added to the secure buttons themselves.
-- Flow Settings, On your screen; /flow sheen on|off.
-------------------------------------------------------------------------------

local _, ns = ...
local S = {}
ns.sheen = S

S.RUN = 2.6       -- seconds for one trip round the edge
S.REST = 6        -- seconds of nothing between trips
S.LENGTH = 16     -- pixels: the streak
S.ALPHA = 0.55
S.HOSTS = { "FlowRotationIcon", "FlowBuffButton" }

function S.On() return not (ns.db and ns.db.rotation and ns.db.rotation.sheen == false) end

-- Pure: where the streak is at time t (seconds since the cycle began).
--   w, h: the edge's rectangle; len: the streak's length
-- -> side ("top" | "right" | "bottom" | "left"), offset along that side (the
--    streak's leading end, from the side's start going clockwise), and its
--    strength 0..1 (it fades in and out at the ends of the trip); nil while resting.
function S.At(t, w, h, run, rest)
    run, rest = run or S.RUN, rest or S.REST
    local cycle = run + rest
    t = t % cycle
    if t >= run or w <= 0 or h <= 0 then return nil end
    local u = t / run
    local d = u * 2 * (w + h)
    local fade = math.min(1, u / 0.12, (1 - u) / 0.12)
    if d < w then return "top", d, fade end
    d = d - w
    if d < h then return "right", d, fade end
    d = d - h
    if d < w then return "bottom", d, fade end
    return "left", d - w, fade
end

local SOLID = "Interface\\Buttons\\WHITE8X8"
local frames = {}
local function frameFor(host)
    local f = frames[host]
    if f then return f end
    if InCombatLockdown() then return nil end
    local e = ns.ICON_EDGE or 3
    f = CreateFrame("Frame", nil, UIParent)
    f:SetPoint("TOPLEFT", host, "TOPLEFT", -e, e)
    f:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", e, -e)
    f:EnableMouse(false)
    f.thick = e
    f.streak = f:CreateTexture(nil, "OVERLAY", nil, 7)
    f.streak:SetTexture(SOLID)
    f.streak:SetBlendMode("ADD")
    f.streak:Hide()
    f.started = GetTime() + (#S.HOSTS > 1 and (host:GetName() == S.HOSTS[2] and 1.3 or 0) or 0)   -- (the two don't run in step)
    frames[host] = f
    return f
end

local function place(f, side, off, strength)
    local st, e, len = f.streak, f.thick, S.LENGTH
    local w, h = f:GetWidth(), f:GetHeight()
    st:ClearAllPoints()
    if side == "top" then
        st:SetSize(math.min(len, w - off), e)
        st:SetPoint("TOPLEFT", f, "TOPLEFT", off, 0)
    elseif side == "right" then
        st:SetSize(e, math.min(len, h - off))
        st:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -off)
    elseif side == "bottom" then
        st:SetSize(math.min(len, w - off), e)
        st:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -off, 0)
    else
        st:SetSize(e, math.min(len, h - off))
        st:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, off)
    end
    st:SetVertexColor(1, 1, 1, S.ALPHA * strength)
    st:Show()
end

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.03 then return end
    acc = 0
    local on = S.On()
    local now = GetTime()
    for _, name in ipairs(S.HOSTS) do
        local host = _G[name]
        if host then
            local f = (on and host:IsVisible()) and frameFor(host) or frames[host]
            if f then
                if not (on and host:IsVisible()) then
                    f.streak:Hide()
                else
                    f:SetFrameStrata(host:GetFrameStrata())
                    f:SetFrameLevel(host:GetFrameLevel() + 8)
                    local side, off, strength = S.At(now - f.started, f:GetWidth(), f:GetHeight())
                    if side then place(f, side, off, strength) else f.streak:Hide() end
                end
            end
        end
    end
end)
S._frames = frames   -- (tests)

ns.commands.sheen = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.rotation = ns.db.rotation or {}
        ns.db.rotation.sheen = (arg == "on")
    end
    ns:Print("the glint round the target and self buttons' edges: " .. (S.On() and "on" or "off") .. " (/flow sheen on|off)")
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "screen",
        label = "A glint round the target and self buttons' edges",
        note = "(only for looks)",
        tip = "A short lighter streak runs once round the coloured edge of the target button and the self button, then rests a few seconds. It's only for looks: it never means a spell is ready.",
        get = function() return S.On() end,
        set = function(on)
            ns.db.rotation = ns.db.rotation or {}
            ns.db.rotation.sheen = on and true or false
        end,
    })
end
