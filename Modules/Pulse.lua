-- One colour and one beat for "Flow suggests this".
--
-- "Is there a way we can indicate what is suggested? We have the action
-- bar's border flashing, the modifier key flashing, the icon at the bottom
-- right... Can we make these all legendary orange, flashing in sync, so it
-- becomes clear that we are suggesting to cast that?" (0.35.233)
--
-- Each of those had its own gold and its own animation, so they blinked out
-- of step. Now anything that means "press this" takes its colour from here
-- (the orange of a legendary item) and is pulsed by one clock: every pulsing
-- thing has the same brightness at the same moment.
--
--   ns.pulse.COLOR             { r, g, b }
--   ns.pulse.Add(region)       it pulses with the rest (a frame or a texture)
--   ns.pulse.Remove(region)    it stops, back to full brightness

local _, ns = ...
local P = {}
ns.pulse = P

P.COLOR = { 1, 0.5, 0 }    -- legendary orange
P.PERIOD = 0.9             -- seconds from bright to dim and back
P.LOW = 0.3                -- the dimmest it gets

-- Pure: the brightness at a moment (the same for everything that pulses).
function P.Alpha(now, period, low)
    period, low = period or P.PERIOD, low or P.LOW
    local phase = (now % period) / period            -- 0..1
    local wave = 0.5 + 0.5 * math.cos(phase * 2 * math.pi)   -- 1 at the start, 0 halfway
    return low + (1 - low) * wave
end

local items = {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function()
    local a = P.Alpha(GetTime())
    local any = false
    for region in pairs(items) do
        any = true
        region:SetAlpha(a)
    end
    if not any then driver:Hide() end
end)

function P.Add(region)
    if not (region and region.SetAlpha) then return end
    items[region] = true
    driver:Show()
end
function P.Remove(region, alpha)
    if not region then return end
    if items[region] then
        items[region] = nil
        if region.SetAlpha then region:SetAlpha(alpha or 1) end
    end
end
function P.Has(region) return items[region] == true end
function P.Count()
    local n = 0
    for _ in pairs(items) do n = n + 1 end
    return n
end
