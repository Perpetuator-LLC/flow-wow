-- Money as short text, the same everywhere Flow shows a price (0.35.307).
--
-- "needs 13552c" said nothing at a glance: Flow's money went through the
-- game's GetCoinTextureString, which WoW: Forever doesn't have, so it fell
-- back to plain copper. Now every price is about three figures in its
-- biggest coin ("generally 3 chars so 124g"):
--
--   52c, 5.52s, 45.5s, 1.36g, 13.6g, 124g, 1240g
--
-- Rounded to the nearest, so "needs 1.36g" with 1g 35s 50c in your bags is
-- still more than you have. Under a silver it's exact copper; past 999 gold
-- it's whole gold. AH.ParseMoney reads these back ("1.36g").

local _, ns = ...

-- Pure: copper -> "1.36g". nil or not a number -> "?".
function ns.Money(c)
    c = tonumber(c)
    if not c then return "?" end
    if c < 0 then return "-" .. ns.Money(-c) end
    c = math.floor(c + 0.5)
    if c < 100 then return c .. "c" end
    local unit, size = "s", 100
    if c >= 10000 then unit, size = "g", 10000 end
    local v = c / size
    local places = (v < 10 and 2) or (v < 100 and 1) or 0
    local scale = 10 ^ places
    v = math.floor(v * scale + 0.5) / scale
    -- 99.96s rounds up to a whole gold.
    if unit == "s" and v >= 100 then return ns.Money(10000) end
    local text = string.format("%." .. places .. "f", v)
    if places > 0 then text = text:gsub("0+$", ""):gsub("%.$", "") end
    return text .. unit
end
