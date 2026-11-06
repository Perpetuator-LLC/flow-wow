-- Colours used across Flow. Swap the values here to re-theme everything.

local _, ns = ...

local function rgb(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
             tonumber(hex:sub(5, 6), 16) / 255, hex = hex }
end

-- Route colours (map lines, pins, the nav arrow, the minimap dot). The route
-- and the arrow share one colour, and it tells you the order mode:
--   Most XP first       epic purple
--   Shortest path       rare blue
--   From selected stop  legendary orange
-- Hovering a stop previews the route you'd follow, all in legendary orange
-- (the same as "From selected", which is what clicking it gives you). The stop
-- under your mouse is red.
-- Colour-blind palette (/flow settings): Okabe-Ito equivalents that stay
-- apart for the common kinds of colour blindness.
local PALETTES = {
    standard = {
        modes    = { xp = rgb("A335EE"), distance = rgb("0070DD"), selected = rgb("FF8000") },
        proposed = rgb("FF8000"),  -- legendary orange: the route you'd follow if you pick the hovered stop
        changed  = rgb("9A9A9A"),  -- grey: your route while previewing another
        hover    = rgb("FF4A4A"),  -- red: the stop under your mouse
    },
    colorblind = {
        modes    = { xp = rgb("CC79A7"), distance = rgb("0072B2"), selected = rgb("E69F00") },
        proposed = rgb("E69F00"),
        changed  = rgb("9A9A9A"),
        hover    = rgb("D55E00"),
    },
}

ns.theme = {
    arrow    = rgb("E69F00"),  -- orange: Flow's accent colour on panels and buttons
    user     = rgb("56B4E9"),  -- sky blue: your own waypoint
    muted    = rgb("BBBBBB"),
}

local function set(self, k, c)
    if self[k] then
        self[k][1], self[k][2], self[k][3], self[k].hex = c[1], c[2], c[3], c.hex
    else
        self[k] = { c[1], c[2], c[3], hex = c.hex }
    end
end

-- Route colour from the order mode (call after the mode changes).
function ns.theme:UpdateRoute()
    local p = PALETTES[self.palette or "standard"]
    local mode = ns.db and ns.db.nav and ns.db.nav.sorter or "xp"
    set(self, "route", p.modes[mode] or p.modes.xp)
    self.current = self.route  -- older name
end

-- Copies a palette's colours into ns.theme (the tables are shared, so code
-- that kept a reference sees the change too).
function ns.theme:UsePalette(name)
    local p = PALETTES[name] or PALETTES.standard
    self.palette = PALETTES[name] and name or "standard"
    for k, c in pairs(p) do if k ~= "modes" then set(self, k, c) end end
    self:UpdateRoute()
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
