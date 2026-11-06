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

-- Stop types on the route: a colour AND an icon each, so colour is never
-- the only cue. (Quests yellow, dailies blue, kills red were chosen by the
-- player; the rest are picked to stay apart from those.)
local R = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
ns.theme.kinds = {
    accept       = { color = rgb("F0E442"), icon = "Interface\\GossipFrame\\AvailableQuestIcon", label = "Accept quest" },
    turnin       = { color = rgb("FFD100"), icon = "Interface\\GossipFrame\\ActiveQuestIcon", label = "Turn in" },
    daily        = { color = rgb("4DA6FF"), icon = "Interface\\GossipFrame\\AvailableQuestIcon", label = "Daily quest" },
    kill         = { color = rgb("E8443A"), icon = R .. "8", label = "Kill" },
    collect      = { color = rgb("E69F00"), icon = R .. "3", label = "Collect (drops)" },
    use          = { color = rgb("C8A165"), icon = "Interface\\Icons\\INV_Misc_Gear_01", label = "Use / click" },
    talk         = { color = rgb("8FD694"), icon = "Interface\\GossipFrame\\GossipGossipIcon", label = "Talk to" },
    proftrainer  = { color = rgb("B07CFF"), icon = "Interface\\GossipFrame\\TrainerGossipIcon", label = "Profession trainer" },
    classtrainer = { color = rgb("2EC4B6"), icon = "Interface\\GossipFrame\\TrainerGossipIcon", label = "Class trainer" },
    merchant     = { color = rgb("D4AF37"), icon = "Interface\\GossipFrame\\VendorGossipIcon", label = "Merchant" },
    hearth       = { color = rgb("E0E0E0"), icon = "Interface\\Icons\\INV_Misc_Rune_01", label = "Hearthstone" },
    skill        = { color = rgb("57C785"), icon = "Interface\\Icons\\Trade_Fishing", label = "Skill-up" },
    waypoint     = { color = rgb("56B4E9"), icon = "Interface\\Minimap\\MinimapArrow", label = "Your waypoint" },
    party        = { color = rgb("56B4E9"), icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", label = "Party route" },
}
