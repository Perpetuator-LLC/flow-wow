-- A small context menu in Flow's own style (dark panel, accent edge).
--   ns.menu:Open(items)   at the cursor
-- items: { text, func, checked = bool|nil, radio = bool, disabled = bool,
--          title = bool, sep = true, stay = bool, tip = "...", refresh = fn }
-- The first section (the thing you clicked) is shown open; every later
-- section is one row, and its entries pop out beside the menu when you
-- point at the row or click it (Menu.Fold).
-- Closes on a click outside it, on Escape, or after choosing an entry.

local _, ns = ...
local Menu = {}
ns.menu = Menu

local ROW_H, PAD, W = 18, 6, 230
local frame, catcher, fly
local rows, flyRows = {}, {}
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

-- One panel in Flow's menu look: the menu itself, or the pop-out beside it.
local function panel(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetWidth(W)
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.97)
    local o = ns.theme.arrow
    f.accent = f:CreateTexture(nil, "BORDER")
    f.accent:SetPoint("TOPLEFT"); f.accent:SetPoint("BOTTOMLEFT")
    f.accent:SetWidth(3)
    f.accent:SetColorTexture(o[1], o[2], o[3], 1)
    f:SetClampedToScreen(true)
    f:Hide()
    return f
end

local function build()
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() Menu:Close() end)
    -- The catcher covers the whole screen to close the menu on a click
    -- outside it: never leave it up without the menu, or no click would get
    -- through to the game.
    catcher:SetScript("OnUpdate", function(self)
        if not (frame and frame:IsShown()) then self:Hide(); ns:Log("menu", "click catcher was up without a menu: hidden") end
    end)
    catcher:Hide()

    frame = panel("FlowMenu")
    frame:SetFrameLevel(catcher:GetFrameLevel() + 10)
    -- The pop-out for a folded section, beside the menu.
    fly = panel("FlowMenuSection")
    fly:SetFrameLevel(catcher:GetFrameLevel() + 30)
    frame:SetScript("OnHide", function() catcher:Hide(); fly:Hide(); Menu.openSection = nil end)
    tinsert(UISpecialFrames, "FlowMenu")  -- Escape closes it
end

local function row(parent, list, i)
    local r = list[i]
    if r then return r end
    r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.1)
    r.mark = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.mark:SetPoint("LEFT", 8, 0)
    r.mark:SetWidth(14)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 24, 0)
    r.text:SetPoint("RIGHT", -18, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    -- A folded section's row: an arrow at its right edge.
    r.arrow = r:CreateTexture(nil, "OVERLAY")
    r.arrow:SetSize(12, 12)
    r.arrow:SetPoint("RIGHT", -4, 0)
    r.arrow:SetTexture(ARROW)
    r.arrow:Hide()
    r.line = r:CreateTexture(nil, "ARTWORK")
    r.line:SetPoint("LEFT", 8, 0); r.line:SetPoint("RIGHT", -8, 0)
    r.line:SetHeight(1)
    r.line:SetColorTexture(1, 1, 1, 0.15)
    list[i] = r
    return r
end

function Menu:Close() if frame then frame:Hide() end end

-- Flow's windows you can switch off (registry "window": { name, order,
-- hidden(), show() }). While one is off, every Flow menu offers to show it
-- again at the bottom (Yang: hide a Flow window, and the other menus bring
-- it back). Flow Settings has a box for each too.
function Menu.HiddenWindowItems()
    local list = {}
    for _, w in ns:Each("window") do
        local ok, hidden = pcall(w.hidden)
        if ok and hidden then list[#list + 1] = w end
    end
    table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
    local out = {}
    if #list == 0 then return out end
    out[1] = { title = true, text = "Hidden Flow windows" }
    for _, w in ipairs(list) do
        out[#out + 1] = { text = "Show " .. w.name, func = function() pcall(w.show) end }
    end
    return out
end

-------------------------------------------------------------------------------
-- Folded sections (0.35.177): "collapse each of the sections of the Flow
-- context menu, so that their options pop out if hovered over or clicked".
-- A menu is a flat list: a title, its entries, a separator, the next title...
-- The first section is the thing you clicked (a stop, the arrow, the
-- tracker) and stays open: its entries are one click away, as before. Every
-- later section is one row, "Order   Shortest path  >", and its entries pop
-- out beside the menu when you point at the row or click it.
-------------------------------------------------------------------------------

-- What a folded section is set to, for its row: the ticked radio's text
-- ("Shortest path"), how many ticks are on ("4 of 6"), or "on" / "off" for
-- a single tick. nil: nothing to say.
function Menu.SectionState(sub)
    local ticks, on = 0, 0
    for _, it in ipairs(sub) do
        if it.radio and it.checked then return it.text end
        if it.checked ~= nil and not it.radio then
            ticks = ticks + 1
            if it.checked then on = on + 1 end
        end
    end
    if ticks > 1 then return string.format("%d of %d", on, ticks) end
    if ticks == 1 then return on == 1 and "on" or "off" end   -- (a section that is one switch)
    return nil
end

-- Pure: the rows the menu shows, from the flat list.
--   the first section (up to its separator, or the next title): as it is
--   each later title: one row { section = true, text, sub = { its entries } }
--   entries after a separator with no title of their own: under "More"
function Menu.Fold(items)
    local out, i, n = {}, 1, #items
    local titled = false
    while i <= n do
        local it = items[i]
        if it.sep or (it.title and titled) then break end
        if it.title then titled = true end
        out[#out + 1] = it
        i = i + 1
    end
    local rest, section = {}, nil
    while i <= n do
        local it = items[i]
        if it.title then
            section = { section = true, text = it.text, sub = {} }
            rest[#rest + 1] = section
        elseif it.sep then
            section = nil
        else
            if not section then
                section = { section = true, text = "More", sub = {} }
                rest[#rest + 1] = section
            end
            section.sub[#section.sub + 1] = it
        end
        i = i + 1
    end
    local shown = 0
    for _, s in ipairs(rest) do
        if #s.sub > 0 then
            if shown == 0 and #out > 0 then out[#out + 1] = { sep = true } end
            out[#out + 1] = s
            shown = shown + 1
        end
    end
    return out
end

local layout   -- (declared here: a section's row opens the pop-out, which is laid out the same way)

-- Opens a section's pop-out beside its row. (A click never closes it: you
-- point at the row, it opens, and the click that follows would shut it
-- again. Pointing at another row, or a click outside, puts it away.)
function Menu.ShowSection(section, anchor)
    if not (fly and section and section.sub) then return end
    Menu.openSection = section
    layout(fly, flyRows, section.sub)
    fly:ClearAllPoints()
    -- Beside the menu, level with the row: to the right, or to the left
    -- where the screen ends.
    local right = frame:GetRight() or 0
    local room = (UIParent:GetRight() or 0) - right
    if room >= W + 4 then fly:SetPoint("TOPLEFT", anchor or frame, "TOPRIGHT", 2, PAD)
    else fly:SetPoint("TOPRIGHT", anchor or frame, "TOPLEFT", -2, PAD) end
    fly:Show()
end
function Menu.HideSection()
    if fly then fly:Hide() end
    Menu.openSection = nil
end

-- Draws `items` into a panel's rows (no positioning: Open does that once).
layout = function(f, list, items)
    local y = -PAD
    local n = 0
    for i, it in ipairs(items) do
        n = i
        local r = row(f, list, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 3, y)
        r:SetPoint("TOPRIGHT", 0, y)
        local h = it.sep and 7 or ROW_H
        r:SetHeight(h)
        r.line:SetShown(it.sep == true)
        r.text:SetShown(not it.sep)
        r.mark:SetShown(not it.sep)
        r.arrow:SetShown(it.section == true)
        r.hl:SetShown(not (it.sep or it.title or it.disabled))
        if not it.sep then
            if it.section then
                local state = Menu.SectionState(it.sub)
                r.text:SetText("|cffffd200" .. (it.text or "") .. "|r" .. (state and ("  |cff999999" .. state .. "|r") or ""))
            elseif it.title then
                r.text:SetText("|cffffd200" .. (it.text or "") .. "|r")
            elseif it.disabled then
                r.text:SetText("|cff777777" .. (it.text or "") .. "|r")
            else
                r.text:SetText(it.text or "")
            end
            local mark = ""
            -- Game fonts lack most symbols, so the tick is a texture.
            if it.checked then mark = "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t" end
            r.mark:SetText(mark)
        end
        r.item = it
        r:SetScript("OnClick", function(self)
            if it.section then Menu.ShowSection(it, self) else Menu.Click(it) end
        end)
        -- Pointing at a section's row pops it out; pointing at any other row
        -- of the menu itself puts the pop-out away. `tip`: a line or two
        -- about the entry, beside the menu.
        r:SetScript("OnEnter", function(self)
            if f == frame then
                if it.section then Menu.ShowSection(it, self)
                elseif not it.sep then Menu.HideSection() end
            end
            if not it.tip then return end
            ns.Tip(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(it.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Show()
        y = y - h
    end
    for i = n + 1, #list do list[i]:Hide() end
    f:SetHeight(-y + PAD)
end

-- A click on an entry. `stay` entries (ticks you set several of, like what
-- the route includes) keep the menu open: every entry with a `refresh`
-- function brings its own tick, text and disabled up to date, and the menu
-- is drawn again where it is.
function Menu.Click(it)
    if it.sep or it.title or it.disabled or it.section then return end
    if not it.stay then Menu:Close() end
    if it.func then
        local ok, err = pcall(it.func)
        if not ok then ns:Print("menu: " .. tostring(err)) end
    end
    if it.stay and frame and frame:IsShown() then Menu:Redraw() end
end
function Menu:Redraw()
    for _, it in ipairs(self.items or {}) do
        if it.refresh then pcall(it.refresh, it) end
    end
    if not (frame and self.items) then return end
    -- The same rows again (the fold is kept: the open pop-out shows the same
    -- section's entries, brought up to date).
    layout(frame, rows, self.shown or self.items)
    local open = Menu.openSection
    if open and fly and fly:IsShown() then layout(fly, flyRows, open.sub) end
end

function Menu:Open(items)
    -- Hidden Flow windows: "Show ..." at the end of every menu.
    local hidden = Menu.HiddenWindowItems()
    if #hidden > 0 then
        local all = {}
        for _, it in ipairs(items) do all[#all + 1] = it end
        all[#all + 1] = { sep = true }
        for _, it in ipairs(hidden) do all[#all + 1] = it end
        items = all
    end
    self.items = items              -- every entry, flat (tests read them)
    self.shown = Menu.Fold(items)   -- the rows on screen: later sections folded
    GameTooltip:Hide()
    if not frame then build() end
    Menu.HideSection()
    layout(frame, rows, self.shown)
    local scale = UIParent:GetEffectiveScale()
    local x, cy = GetCursorPosition()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 4, cy / scale - 4)
    catcher:Show()
    frame:Show()
end
-- (Tests) the rows of the menu and of its pop-out.
function Menu._Rows() return rows, flyRows end

-- "Route includes": one tick per kind of stop (Nav.lua N.Kinds; Goals.lua
-- registers Flow's), all or none in one click, and under Professions whether
-- they ride on the route or on their own faint arrow. The ticks stay open so
-- you can set several.
function Menu.KindItems()
    local nav = ns.nav
    local items = { { title = true, text = "Route includes" } }
    for _, k in ipairs(nav.Kinds()) do
        local key, def = k.key, k.def
        items[#items + 1] = { text = def.label, tip = def.tip, kind = key, stay = true,
            checked = nav:Includes(key),
            refresh = function(it) it.checked = nav:Includes(key) end,
            func = function() nav:SetKind(key, not nav:Includes(key)) end }
        if key == "professions" then
            local function sub(it)
                it.checked = ns.db.nav.profArrow == true
                it.disabled = not nav:Includes("professions")
            end
            local own = { text = "      on their own faint arrow", stay = true, func = function() nav:SetProfArrow(ns.db.nav.profArrow ~= true) end,
                tip = "Ticked: profession stops get a route of their own and a faint arrow behind the main one, which then only takes you to the rest. "
                    .. "Not ticked: they're stops on the one route, where the Flow key does their steps.",
                refresh = sub }
            sub(own)
            items[#items + 1] = own
        end
    end
    items[#items + 1] = { text = "Select all", stay = true, func = function() nav:SetAllKinds(true) end }
    items[#items + 1] = { text = "Clear all", stay = true, func = function() nav:SetAllKinds(false) end }
    return items
end

-- The Flow menu: the entries every Flow menu shares (the arrow, the Flow
-- Tracker, a stop on the map, the Flow Router's Route button). One section
-- for each thing you'd come here to do, always in this order (0.35.182:
-- "it needs to be better organized, cleaner sections"):
--
--   Order                 how the route is sorted
--   Route includes        which kinds of stops are on it; unhide what you hid
--   Go to the nearest...  repair, vendor, flight master, inn, mailbox, bank
--   Your waypoint         set one, follow someone, clear it
--   Dungeons              (when a run fits your level)
--   Party                 (in a group)
--   Stops on the map      how many the map and the Flow Tracker show
--   Arrow                 its look
--   Keys                  binding them, listing them
--   Extras                NPCs read aloud (text-to-speech)
--   Flow windows          Settings, Improvements, Professions, Setup
--
-- Every entry is under a title (nothing loose at the bottom), and no entry
-- is in two places. A section with nothing in it is left out. The menu
-- folds each section into one row (Menu.Fold).
Menu.SECTIONS = { "Order", "Route includes", "Go to the nearest...", "Your waypoint", "Dungeons", "Party",
                  "Stops on the map", "Arrow", "Keys", "Extras", "Flow windows" }

function Menu:RouteItemsRaw()
    local nav = ns.nav
    local sort = ns.xpValue:Mode()
    local items = {}
    -- A section: a line above it (not above the first), its title, its
    -- entries. One with no entries is left out.
    local function section(title, entries)
        if not entries or #entries == 0 then return end
        if #items > 0 then items[#items + 1] = { sep = true } end
        items[#items + 1] = { title = true, text = title }
        for _, it in ipairs(entries) do items[#items + 1] = it end
    end
    -- (One failing builder must not stop the menu opening: it's logged.)
    local function safe(fn, ...)
        if not fn then return {} end
        local ok, res = pcall(fn, ...)
        if ok and type(res) == "table" then return res end
        if not ok then ns:Log("menu", "a section failed: " .. tostring(res)) end
        return {}
    end

    -- Order (the default first).
    section("Order", {
        { text = ns.theme:ModeText("distance", "Shortest path"), radio = true, checked = sort == "distance", func = function() ns.xpValue:SetMode("distance") end },
        { text = ns.theme:ModeText("xp", "Most XP first"), radio = true, checked = sort == "xp", func = function() ns.xpValue:SetMode("xp") end },
        -- On while you've picked the next stop yourself (a ^ / Go here next);
        -- the two above put you back on an optimised route.
        { text = sort == "custom" and ns.theme:ModeText("custom", "Custom route (your pick)")
                or "|cff777777Custom route (pick a stop: its ^ or Go here next)|r",
          radio = true, checked = sort == "custom", disabled = sort ~= "custom",
          func = function() ns.xpValue:SetMode("custom") end },
        { text = "Finish the area you're in first", checked = ns.db.nav.areaFirst == true,
          func = function() ns.db.nav.areaFirst = (ns.db.nav.areaFirst ~= true); nav.planDirty = true end },
    })

    -- Route includes: the kinds of stops, the dungeon run on its own
    -- (Dungeons.lua, pull request 20), and the stops you hid.
    local includes = {}
    for i, it in ipairs(Menu.KindItems()) do
        if i > 1 then includes[#includes + 1] = it end   -- (its own title: the section's)
    end
    local D = ns.dungeons
    if D and D.RouteItem then
        local ok, it = pcall(D.RouteItem, D)
        if ok and it then includes[#includes + 1] = it end
    end
    local nHidden = 0
    for _ in pairs(ns.db.nav.hidden or {}) do nHidden = nHidden + 1 end
    includes[#includes + 1] = { text = string.format("Unhide all stops (%d)", nHidden), disabled = nHidden == 0,
        func = function() ns.commands.nav("unhide") end }
    section("Route includes", includes)

    -- One click sends the arrow to the nearest of these (your waypoint; the
    -- route carries on after).
    local function nearest(label, kind)
        return { text = label, func = function() if ns.services then ns.services:GoTo(kind) end end }
    end
    section("Go to the nearest...", {
        nearest("Repair", "repair"), nearest("Vendor (sell)", "vendor"), nearest("Flight master", "flight"),
        nearest("Innkeeper", "inn"), nearest("Mailbox", "mail"), nearest("Banker", "bank"),
    })

    -- Your waypoint; in a group, follow a party member (the arrow keeps
    -- pointing at them) or drop your waypoint where they are.
    local following = ns.follow and ns.follow:Target()
    local way = { { text = "Set a waypoint (coordinates, or a party member's name)...", func = function() ns.waypoint:Prompt() end } }
    if ns.follow and ns.party and ns.party:InGroup() then
        for _, it in ipairs(safe(ns.follow.MenuItems, ns.follow)) do way[#way + 1] = it end
    end
    way[#way + 1] = { text = following and ("Clear your waypoint (stop following " .. following .. ")") or "Clear your waypoint",
        disabled = ns.waypoint:Get() == nil and not following,
        func = function()
            if following then ns.follow:Stop() end
            if ns.waypoint:Get() then ns.waypoint:Clear(); ns:Print("waypoint cleared") end
        end }
    section("Your waypoint", way)

    -- Dungeon runs worth doing at your level (Dungeons.lua; needs Questie).
    -- Its list brings its own line and title.
    if ns.dungeons then
        local list = safe(ns.dungeons.MenuItems, ns.dungeons)
        if #list > 0 and not list[1].sep and #items > 0 then items[#items + 1] = { sep = true } end
        for _, it in ipairs(list) do items[#items + 1] = it end
    end

    -- In a group: your own route, the party route (one route for everyone's
    -- quests), or just one member's quests. Never switched for you.
    local P = ns.party
    if P and P:InGroup() then
        local party = {}
        local H = ns.partyHelp
        if H then for _, it in ipairs(safe(H.MenuItems, H)) do party[#party + 1] = it end end
        -- (A hand-made route someone shared with /flow party share.)
        if P:Active() then
            party[#party + 1] = { text = "Shared stops from " .. (P:Editor() or "the party"), radio = true, checked = P:Following(),
                func = function() P:SetFollowing(true) end }
            party[#party + 1] = { text = "Drop the shared stops", func = function() P:Leave() end }
        end
        section("Party", party)
    end

    -- Which stops the map and the Flow Tracker show (the Flow Router always
    -- lists them all): everything in this area, or your next N.
    local shown, area = nav:StopsShown(), nav:AreaMode()
    local stops = { { text = nav.AREA_LABEL, radio = true, checked = area, func = function() nav:SetArea(true) end } }
    for _, n in ipairs(nav.STOP_CHOICES) do
        stops[#stops + 1] = { text = nav:StopsShownLabel(n), radio = true, checked = not area and shown == n,
            func = function() nav:SetStopsShown(n) end }
    end
    stops[#stops + 1] = { text = string.format("All stops (%d on the route now)", nav.plan and #nav.plan or 0),
        radio = true, checked = not area and shown == nil, func = function() nav:SetStopsShown(nil) end }
    section("Stops on the map", stops)

    -- The arrow's look (Nav.lua).
    section("Arrow", safe(nav.ArrowMenuItems, nav))

    section("Keys", {
        -- Both of Flow's buttons and their keys ("we should be able to toggle the
        -- buff button on in the menu and bind both", 0.35.207).
        { text = "Set Flow's keys: the easy key and the buff button's (Flow Settings)...", disabled = InCombatLockdown(),
          tip = "Flow's key, a second key for it, and the buff button's own key. A key something else uses is shown, and can be taken off that.",
          func = function() if ns.settings and ns.settings.Open then ns.settings:Open() end end },
        { text = "Buff button: a second key for buffs, heals and potions", stay = true, disabled = InCombatLockdown(),
          checked = ns.buffButton ~= nil and ns.buffButton.On(),
          tip = "A blue button left of Flow's icon with its own key. Out of a fight: your next buff, bandage or food. In a fight: your heal; with Shift, Ctrl, Alt or Ctrl + Shift: your other heals, your potion, your bandage. Flow's own key then has Shift and Alt free for two more attacks.",
          refresh = function(it) it.checked = ns.buffButton ~= nil and ns.buffButton.On() end,
          func = function()
              local BB = ns.buffButton
              if not BB or InCombatLockdown() then return end
              BB.Set(not BB.On())
              if BB.On() and not BB.Key() then ns:Print("buff button on. It has no key yet: Flow menu, Keys, \"Set Flow's keys\" (or /flow buffkey <key>).") end
          end },
        -- Hover-to-bind mode (also in Flow Settings and /flow bind).
        { text = "Key bindings: hover a button, press a key...", disabled = InCombatLockdown(),
          func = function() if ns.bind then ns.bind:Start() end end },
        -- The keys that cast a spell straight away (bound from the Flow Spells
        -- list): the game's own Key Bindings window never lists those.
        { text = "Show keys bound straight to spells (in chat)", func = function() ns.commands.keys() end },
    })

    -- Extras (Bonus.lua). Text-to-speech was only in Flow Settings, under
    -- "Bonus mode": "how do I turn off the TTS, it was like a hidden setting".
    local B = ns.bonus
    if B and B.SetSpoken then
        section("Extras", {
            { text = "NPCs read their words aloud (text-to-speech)", checked = B:Extra("spoken"), stay = true,
              tip = "When you talk to an NPC, the game's text-to-speech voice reads what they say. Untick to switch it off.",
              refresh = function(it) it.checked = B:Extra("spoken") end,
              func = function() B:SetSpoken(not B:Extra("spoken")) end },
        })
    end

    -- Flow's own windows. (The game's options page can't be opened in a fight.)
    local windows = {}
    local function window(label, open, noCombat)
        if open then windows[#windows + 1] = { text = label, disabled = noCombat and InCombatLockdown() or nil, func = open } end
    end
    window("Flow Settings", ns.commands.settings, true)
    window("Flow Improvements", ns.advisor and ns.advisor.TogglePanel and function() ns.advisor:TogglePanel() end)
    window("Flow Professions", ns.commands.professions and function() ns.commands.professions("") end)
    window("Flow Setup", ns.commands.setup, true)
    section("Flow windows", windows)
    return items
end

-- The route list, never failing: an error in one entry (like the waypoint
-- check in 0.35.53) used to stop the whole menu from opening, with nothing
-- on screen. Now it's logged (diagnostics: "[menu]") and said in chat, and
-- the menu still opens with what it can show.
function Menu:RouteItems()
    local ok, items = pcall(self.RouteItemsRaw, self)
    if ok and type(items) == "table" then return items end
    ns:Log("menu", "route items: " .. tostring(items))
    if not Menu.warned then
        Menu.warned = true
        ns:Print("|cffff6060a menu entry failed (logged for the diagnostics).|r")
    end
    return { { title = true, text = "Route" },
             { text = "(something went wrong here: it's logged)", disabled = true } }
end
