-- Colours used across Flow. Swap the values here to re-theme everything.

local _, ns = ...

local function rgb(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
             tonumber(hex:sub(5, 6), 16) / 255, hex = hex }
end

-- Route colours on the map and the nav arrow come in two palettes:
--   standard     green = your route, yellow = a route you're previewing,
--                blue = your route while you preview another, red = hovered stop
--   colourblind  Okabe-Ito: orange route, purple preview, sky blue while
--                previewing, light purple hover. Stays distinct for the common
--                kinds of colour blindness. (/flow settings, or /flow colors)
local PALETTES = {
    standard = {
        route    = rgb("3CC83C"),  -- green: your current route
        proposed = rgb("FFD800"),  -- yellow: a route you're previewing
        changed  = rgb("3C8CFF"),  -- blue: your route while previewing; quest pickups (!N)
        hover    = rgb("FF4A4A"),  -- red: the stop under your mouse
    },
    colorblind = {
        route    = rgb("E69F00"),  -- orange
        proposed = rgb("A97BFF"),  -- purple
        changed  = rgb("56B4E9"),  -- sky blue
        hover    = rgb("D9C2FF"),  -- light purple
    },
}

ns.theme = {
    arrow    = rgb("E69F00"),  -- orange: Flow's accent colour on panels and buttons
    user     = rgb("56B4E9"),  -- sky blue: your own waypoint
    muted    = rgb("BBBBBB"),
}

-- Copies a palette's route colours into ns.theme (the tables are shared, so
-- code that kept a reference sees the change too).
function ns.theme:UsePalette(name)
    local p = PALETTES[name] or PALETTES.standard
    for k, c in pairs(p) do
        if self[k] then
            self[k][1], self[k][2], self[k][3], self[k].hex = c[1], c[2], c[3], c.hex
        else
            self[k] = { c[1], c[2], c[3], hex = c.hex }
        end
    end
    self.current = self.route  -- older name
    self.palette = PALETTES[name] and name or "standard"
end
ns.theme:UsePalette("standard")

function ns.theme:ColorBlind() return self.palette == "colorblind" end
function ns.theme:SetColorBlind(on)
    ns.db.colorblind = on and true or false
    self:UsePalette(on and "colorblind" or "standard")
    if ns.mapOverlay and ns.mapOverlay.Redraw then pcall(ns.mapOverlay.Redraw, ns.mapOverlay) end
end

ns:OnLoad(function(saved)
    ns.theme:UsePalette(saved.colorblind and "colorblind" or "standard")
end)

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
    gather       = { color = rgb("B5651D"), icon = "Interface\\Icons\\Trade_Mining", label = "Gather (mine, herbs)" },
    craft        = { color = rgb("CFCFCF"), icon = "Interface\\Icons\\Trade_BlackSmithing", label = "Craft / smelt" },
    waypoint     = { color = rgb("56B4E9"), icon = "Interface\\Minimap\\MinimapArrow", label = "Your waypoint" },
    party        = { color = rgb("56B4E9"), icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", label = "Party route" },
}
