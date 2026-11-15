-- Your cast, as a thin bar along the bottom edge of Flow's icon and of the
-- buff button.
--
-- "Can both easy and buff show the cast timer on an edge of it too?"
-- (0.35.233) While you cast or channel, a bar fills (a channel empties)
-- along the bottom edge of each button, so you needn't look away to the
-- cast bar to know when the next press will go.

local _, ns = ...
local A = ns.api
local CE = {}
ns.castEdge = CE

CE.HEIGHT = 3

-- Pure: how full the bar is, 0..1, or nil when nothing is being cast.
--   startMs, endMs: the cast's times (milliseconds); nowMs: now;
--   channel: it empties as it goes.
function CE.Progress(startMs, endMs, nowMs, channel)
    if not (startMs and endMs and nowMs) or endMs <= startMs then return nil end
    local p = (nowMs - startMs) / (endMs - startMs)
    if p < 0 or p > 1.05 then return nil end
    p = math.max(0, math.min(1, p))
    return channel and (1 - p) or p
end

-- What you're casting now: start, end (ms), channel?; nil for nothing (or
-- when the game hides the times).
function CE.Now()
    if UnitCastingInfo then
        local _, _, _, s, e = UnitCastingInfo("player")
        s, e = A.Safe(s), A.Safe(e)
        if type(s) == "number" and type(e) == "number" then return s, e, false end
    end
    if UnitChannelInfo then
        local _, _, _, s, e = UnitChannelInfo("player")
        s, e = A.Safe(s), A.Safe(e)
        if type(s) == "number" and type(e) == "number" then return s, e, true end
    end
    return nil
end

local bars = {}
local function barFor(parent)
    local b = bars[parent]
    if b then return b end
    b = CreateFrame("StatusBar", nil, parent)
    b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    b:SetHeight(CE.HEIGHT)
    b:SetFrameLevel(parent:GetFrameLevel() + 6)
    b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    b:SetStatusBarColor(1, 0.82, 0.1, 1)
    b:SetMinMaxValues(0, 1)
    b.back = b:CreateTexture(nil, "BACKGROUND")
    b.back:SetAllPoints()
    b.back:SetColorTexture(0, 0, 0, 0.7)
    b:Hide()
    bars[parent] = b
    return b
end
CE._bars = bars   -- (tests)

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
    local s, e, channel = CE.Now()
    local p = CE.Progress(s, e, GetTime() * 1000, channel)
    for _, name in ipairs({ "FlowRotationIcon", "FlowBuffButton" }) do
        local parent = _G[name]
        if parent then
            if p and parent:IsVisible() then
                local b = barFor(parent)
                b:SetValue(p)
                if not b:IsShown() then b:Show() end
            elseif bars[parent] and bars[parent]:IsShown() then
                bars[parent]:Hide()
            end
        end
    end
end)
