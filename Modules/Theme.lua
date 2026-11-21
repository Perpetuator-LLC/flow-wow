-- Colours used across Flow. Swap the values here to re-theme everything.

local _, ns = ...

local function rgb(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
             tonumber(hex:sub(5, 6), 16) / 255, hex = hex }
end

-- Route colours (map lines, pins, the nav arrow, the minimap dot). The route
-- and the arrow share one colour, and it tells you the route's state:
--   Most XP first       epic purple   optimised
--   Shortest path       rare blue     optimised
--   Custom route        legendary orange: you picked the next step (a ^);
--                       stays until you choose Most XP or Shortest again
-- Your own waypoint is green (uncommon green), its own colour so it never
-- reads as a Custom route: the arrow and a line on the map to it. Hovering a
-- ^ previews that route in orange. The step under your mouse is red.
-- Colour-blind palette (/flow settings): Okabe-Ito equivalents that stay
-- apart for the common kinds of colour blindness.
local PALETTES = {
    standard = {
        modes    = { xp = rgb("A335EE"), distance = rgb("0070DD"), custom = rgb("FF8000"), selected = rgb("FF8000") },
        proposed = rgb("FF8000"),  -- legendary orange: the route you'd follow if you pick the hovered step
        waypoint = rgb("1EFF00"),  -- uncommon green: your own waypoint (arrow, map line, Router line)
        changed  = rgb("9A9A9A"),  -- grey: your route while previewing another
        hover    = rgb("FF4A4A"),  -- red: the step under your mouse
        -- The modern arrow's colour by how close you are (Nav.lua, N.ArrowColor):
        -- grey while the step is in another zone, then red (far) through
        -- yellow to green (close), and blue once you're in its area.
        arrowAway = rgb("9EA0A8"),
        arrowFar  = rgb("FF8C1A"),  -- orange, not red: red reads as "can't", and the arrow says "go"
        arrowMid  = rgb("FFD91A"),
        arrowNear = rgb("33F24D"),
        arrowHere = rgb("4DA6FF"),
    },
    colorblind = {
        modes    = { xp = rgb("CC79A7"), distance = rgb("0072B2"), custom = rgb("E69F00"), selected = rgb("E69F00") },
        proposed = rgb("E69F00"),
        waypoint = rgb("009E73"),  -- bluish green
        changed  = rgb("9A9A9A"),
        hover    = rgb("D55E00"),
        arrowAway = rgb("9EA0A8"),
        arrowFar  = rgb("E69F00"),  -- orange (not vermillion: red reads as "can't")
        arrowMid  = rgb("F0E442"),  -- yellow
        arrowNear = rgb("009E73"),  -- bluish green
        arrowHere = rgb("56B4E9"),  -- sky blue
    },
}

ns.theme = {
    arrow    = rgb("E69F00"),  -- orange: Flow's accent colour on panels and buttons
    user     = rgb("56B4E9"),  -- sky blue: your own waypoint
    muted    = rgb("BBBBBB"),
    good     = rgb("66FF66"),  -- green: worth doing (a dungeon run with your group)
    flightHave = rgb("66FF66"),  -- green: a flight path you have, on the world map (MapFlights.lua;
                                 -- one you don't have yet wears kinds.flight's colour, as its route step does)
    flightCant = rgb("E8443A"),  -- red: a flight you can't take yet (one end not learned), on the world map
    profPointer = rgb("1E2026"),  -- near-black smoked glass: the profession arrow under the main arrow
}

-- Flow's panel title bar, the brand on every Flow panel (Flow Tracker, Flow
-- Router, Flow Seller): a dark bar with the orange accent down its left edge,
-- an icon and the title in gold. One recipe, so the panels can't drift apart.
-- frameType "Button" when the bar is clickable. Returns the bar with
-- .bg, .accent, .icon and .text (the title).
ns.theme.TITLE_H = 24
ns.theme.BAR = { 0.11, 0.09, 0.06, 0.92 }   -- the dark bar itself (also Flow's buttons on WoW's windows)
function ns.theme:TitleBar(parent, title, icon, frameType)
    local h = CreateFrame(frameType or "Frame", nil, parent)
    h.flowTitleBar = true
    h:SetHeight(self.TITLE_H)
    h:SetPoint("TOPLEFT"); h:SetPoint("TOPRIGHT")
    h.bg = h:CreateTexture(nil, "BACKGROUND"); h.bg:SetAllPoints()
    h.bg:SetColorTexture(self.BAR[1], self.BAR[2], self.BAR[3], self.BAR[4])
    local o = self.arrow
    h.accent = h:CreateTexture(nil, "BORDER")
    h.accent:SetPoint("TOPLEFT"); h.accent:SetPoint("BOTTOMLEFT"); h.accent:SetWidth(4)
    h.accent:SetColorTexture(o[1], o[2], o[3], 1)
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(16, 16); h.icon:SetPoint("LEFT", 9, 0)
    if icon then h.icon:SetTexture(icon) end
    h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.text:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
    h.text:SetText(title or "")
    return h
end

local function set(self, k, c)
    if self[k] then
        self[k][1], self[k][2], self[k][3], self[k].hex = c[1], c[2], c[3], c.hex
    else
        self[k] = { c[1], c[2], c[3], hex = c.hex }
    end
end

-- Colour of a route state ("xp", "distance", "custom") in the current palette:
-- menus and the map list colour their labels with it.
function ns.theme:ModeColor(mode)
    local p = PALETTES[self.palette or "standard"]
    return p.modes[mode] or p.modes.xp
end
function ns.theme:ModeText(mode, text) return "|cff" .. self:ModeColor(mode).hex .. text .. "|r" end

-- Route colour from the order mode (call after the mode changes).
function ns.theme:UpdateRoute()
    local p = PALETTES[self.palette or "standard"]
    local mode = ns.db and ns.db.nav and ns.db.nav.sorter or (ns.xpValue and ns.xpValue.DEFAULT) or "distance"
    if mode == "selected" then mode = "custom" end   -- (its older name)
    local obj = ns.Get and ns:Get("routeObjective", mode)
    set(self, "route", p.modes[mode] or (obj and obj.color) or p.modes.xp)
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

-- Step types on the route: a colour AND an icon each, so colour is never
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
    flight       = { color = rgb("7FD1FF"), icon = "Interface\\GossipFrame\\TaxiGossipIcon", label = "Flight path to learn" },
    skill        = { color = rgb("57C785"), icon = "Interface\\Icons\\Trade_Fishing", label = "Skill-up" },
    gather       = { color = rgb("B5651D"), icon = "Interface\\Icons\\Trade_Mining", label = "Gather (mine, herbs)" },
    craft        = { color = rgb("CFCFCF"), icon = "Interface\\Icons\\Trade_BlackSmithing", label = "Craft / smelt" },
    waypoint     = { color = rgb("56B4E9"), icon = "Interface\\Minimap\\MinimapArrow", label = "Your waypoint" },
    party        = { color = rgb("56B4E9"), icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", label = "Party route" },
}

-- Progress reads as a path, where you are -> where you're going: "9 -> 66",
-- never "9/66". ProgressText rewrites the game's "0/7 Murloc slain".
function ns.Progress(have, need) return tostring(have) .. " -> " .. tostring(need) end
function ns.ProgressText(text)
    if type(text) ~= "string" then return text end
    return (text:gsub("(%d+)%s*/%s*(%d+)", "%1 -> %2"))
end

-------------------------------------------------------------------------------
-- A blue glow while the mouse is over one of Flow's square buttons (0.35.381:
-- "as the user hovers over Flow flight masters or Flow route it doesn't
-- really highlight that well ... it should give it a nice glow, like the game
-- does, in blue"). Drawn on the button's highlight layer, so the game shows
-- and hides it with the mouse and nothing needs redrawing: a soft halo round
-- the button, a faint wash inside it, and a bright edge.
--   ns.theme:HoverGlow(button) -> the glow's parts (button.hoverGlow)
-------------------------------------------------------------------------------
ns.theme.GLOW = { 0.35, 0.65, 1 }
ns.theme.GLOW_HALO = 1.9   -- the halo's size, in button widths
function ns.theme:HoverGlow(b)
    if not (b and b.CreateTexture) then return nil end
    if b.hoverGlow then return b.hoverGlow end
    local c = self.GLOW
    local g = {}
    g.halo = b:CreateTexture(nil, "HIGHLIGHT")
    g.halo:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    g.halo:SetBlendMode("ADD")
    g.halo:SetVertexColor(c[1], c[2], c[3], 0.9)
    g.halo:SetPoint("CENTER")
    g.wash = b:CreateTexture(nil, "HIGHLIGHT")
    g.wash:SetAllPoints()
    g.wash:SetBlendMode("ADD")
    g.wash:SetColorTexture(c[1], c[2], c[3], 0.16)
    g.edge = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                           { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = b:CreateTexture(nil, "HIGHLIGHT")
        t:SetPoint(pts[1]); t:SetPoint(pts[2])
        if i <= 2 then t:SetHeight(1.5) else t:SetWidth(1.5) end
        t:SetColorTexture(c[1], c[2], c[3], 1)
        g.edge[i] = t
    end
    function g.Size()
        local w, h = b:GetWidth(), b:GetHeight()
        g.halo:SetSize(w * ns.theme.GLOW_HALO, h * ns.theme.GLOW_HALO)
    end
    g.Size()
    b:HookScript("OnSizeChanged", g.Size)
    b.hoverGlow = g
    return g
end
