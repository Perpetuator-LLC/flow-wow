-- Colours used across Flow. Okabe-Ito palette: safe for the common kinds of
-- colour blindness. Swap the values here to re-theme everything.

local _, ns = ...

local function rgb(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
             tonumber(hex:sub(5, 6), 16) / 255, hex = hex }
end

ns.theme = {
    current  = rgb("009E73"),  -- bluish green: your current route
    proposed = rgb("F0E442"),  -- yellow: a route you're previewing
    changed  = rgb("0072B2"),  -- blue: current route while previewing another; quest pickups (!N)
    arrow    = rgb("E69F00"),  -- orange: the nav arrow
    hover    = rgb("CC79A7"),  -- reddish purple: the checkpoint under your mouse
    user     = rgb("56B4E9"),  -- sky blue: your own waypoint
    muted    = rgb("BBBBBB"),
}
