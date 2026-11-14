-- Flow's buttons on the game's own windows: a "Flow Talents" tab standing
-- on the top edge of WoW's talent window opens the Flow Talents view, and so
-- on for the other windows that have a Flow view to go with them. The Flow
-- view stays closed until you click: nothing opens by itself.
--
-- Registry "gameButton" (add one from any file):
--   ns:Register("gameButton", "talents", {
--       order = 10,
--       frames = { "PlayerSpellsFrame.TalentsFrame", "PlayerTalentFrame" },
--                      -- the game's window: the first of these that exists.
--                      -- Dots walk into a window's parts, so a button can sit
--                      -- on one tab of a window only.
--       label = "Flow Talents",              -- the Flow view it opens
--       tip = "...",
--       click = function() ... end,          -- opens the view (or closes it)
--       isOpen = function() return ... end,  -- optional: lit while it's open
--       x = -52, y = -1,                     -- optional: from the window's top right corner
--   })
--
-- The button is a child of the frame it names, so the game shows and hides
-- it with that frame, and it stands on the top edge of the window the frame
-- belongs to, near its right end (a tab: nothing of the window covers it). Flow only adds a
-- child: it never moves, shows, hides or calls anything on the game's
-- window, so nothing of the game's is tainted. Windows the game loads only
-- when you first open them get their button then (ADDON_LOADED).
--
-- "Flow buttons on WoW's windows" in Flow Settings (On your screen) turns
-- them all off. /flow buttons lists them and the windows they found (also in
-- the diagnostics: the frame names differ between clients).

local _, ns = ...
local GB = {}
ns.gameButtons = GB

-- A tab standing on the window's top edge, near its right end (0.35.190).
-- It used to be a small dark button inside the title bar: the game reported
-- it attached to the talent window, and the player asked for a button there.
-- On top of the window nothing of the window's own can cover it.
GB.X, GB.Y, GB.HEIGHT = -40, -3, 22

function GB.On() return ns.db.settings.gameButtons ~= false end

-------------------------------------------------------------------------------
-- Pure parts (the tests pass their own tables in)
-------------------------------------------------------------------------------

-- "A.B.C" walked from env (the game's globals), to a frame; nil when any
-- part is missing or what's there isn't a frame.
function GB.Resolve(path, env)
    local at = env or _G
    for part in tostring(path):gmatch("[^%.]+") do
        if type(at) ~= "table" then return nil end
        at = at[part]
    end
    if type(at) == "table" and type(at.IsShown) == "function" then return at end
    return nil
end

-- The first of a button's frames that exists: the frame and its path.
function GB.Find(def, env)
    for _, path in ipairs(def.frames or {}) do
        local f = GB.Resolve(path, env)
        if f then return f, path end
    end
end

-- The window a frame belongs to: its outermost parent under the screen.
function GB.Window(frame, screen)
    screen = screen or UIParent
    local at = frame
    for _ = 1, 12 do
        local p = at.GetParent and at:GetParent()
        if not p or p == screen then return at end
        at = p
    end
    return at
end

-- In order, for the settings, the report and the tests: { key, def }.
function GB.List()
    local out = {}
    for key, def in ns:Each("gameButton") do out[#out + 1] = { key = key, def = def } end
    table.sort(out, function(a, b)
        local ao, bo = a.def.order or 50, b.def.order or 50
        if ao ~= bo then return ao < bo end
        return a.key < b.key
    end)
    return out
end

-- Pure: where a button showed up, for the log.
function GB.Where(label, left, bottom, strata, level, window)
    return string.format("%s button shown at %d, %d (%s, level %d) on %s", tostring(label), math.floor((left or -1) + 0.5),
        math.floor((bottom or -1) + 0.5), tostring(strata), level or 0, tostring(window or "a window with no name"))
end

-- One line of /flow buttons.
function GB.Line(def, path, shown)
    if not path then
        return string.format("%s: its window isn't loaded yet (looked for %s)", def.label, table.concat(def.frames or {}, ", "))
    end
    return string.format("%s: on %s%s", def.label, path, shown and ", showing now" or "")
end

-------------------------------------------------------------------------------
-- The buttons
-------------------------------------------------------------------------------

local buttons = {}   -- [key] = the button
local paths = {}     -- [key] = the frame path it was put on
local waiting        -- a window appeared during a fight: its button comes after

local function paint(b, def)
    local open = false
    if def.isOpen then
        local ok, v = pcall(def.isOpen)
        open = ok and v and true or false
    end
    local bar, o = ns.theme.BAR, ns.theme.arrow
    if open then b.bg:SetColorTexture(o[1] * 0.45, o[2] * 0.45, o[3] * 0.45, 0.95)
    else b.bg:SetColorTexture(bar[1], bar[2], bar[3], bar[4]) end
    b.open = open
end

function GB.Click(key)
    local def = ns:Get("gameButton", key)
    if not def then return false end
    local ok, err = pcall(def.click)
    if not ok then ns:Log("buttons", (def.label or key) .. ": " .. tostring(err)) end
    if buttons[key] then paint(buttons[key], def) end
    return ok
end

local function make(key, def, frame)
    local win = GB.Window(frame)
    local b = CreateFrame("Button", "FlowGameButton_" .. key, frame)
    b:SetHeight(GB.HEIGHT)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    local o = ns.theme.arrow
    b.accent = b:CreateTexture(nil, "BORDER")
    b.accent:SetPoint("TOPLEFT"); b.accent:SetPoint("BOTTOMLEFT"); b.accent:SetWidth(3)
    b.accent:SetColorTexture(o[1], o[2], o[3], 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("CENTER", 2, 0)
    b.text:SetText(def.label)
    b:SetWidth(math.max(70, (b.text:GetStringWidth() or 70) + 22))
    b.hover = b:CreateTexture(nil, "HIGHLIGHT")
    b.hover:SetAllPoints()
    b.hover:SetColorTexture(1, 1, 1, 0.12)
    -- Its bottom edge a few pixels into the window's top edge: a tab on top of it.
    b:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", def.x or GB.X, def.y or GB.Y)
    -- Over the window's own art (the game puts its title and close button at 510).
    b:SetFrameLevel(math.min((win:GetFrameLevel() or 1) + 520, 9990))
    -- A gold line round it, so it reads as a button.
    b.edge = {}
    for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local e = b:CreateTexture(nil, "OVERLAY")
        e:SetColorTexture(1, 0.82, 0, 0.9)
        e:SetPoint(side[1]); e:SetPoint(side[2])
        if i == 1 then e:SetHeight(1) else e:SetWidth(1) end
        b.edge[i] = e
    end
    b:SetScript("OnClick", function() GB.Click(key) end)
    b:SetScript("OnShow", function(self)
        paint(self, def)
        if not self.logged then
            self.logged = true
            ns:Log("buttons", GB.Where(def.label, self:GetLeft(), self:GetBottom(), self:GetFrameStrata(), self:GetFrameLevel(), win:GetName()))
        end
    end)
    b:SetScript("OnEnter", function(self)
        paint(self, def)
        ns.Tip(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine(def.label)
        if def.tip then GameTooltip:AddLine(def.tip, 1, 1, 1, true) end
        GameTooltip:AddLine(self.open and "Click to close it." or "Click to open it.", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Flow Settings, On your screen: these buttons on or off.", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    paint(b, def)
    return b
end

-- Puts each button on its window, for the windows that exist by now; shows
-- or hides them all with the setting. Cheap: a few table lookups a button.
function GB:Attach()
    if not (ns.db and ns.db.settings) then return end   -- (a game add-on loaded before Flow's saved data)
    if InCombatLockdown() then waiting = true return end
    waiting = nil
    local on = GB.On()
    for _, e in ipairs(GB.List()) do
        local key, def = e.key, e.def
        if not buttons[key] and on then
            local frame, path = GB.Find(def)
            if frame then
                local ok, b = pcall(make, key, def, frame)
                if ok then buttons[key], paths[key] = b, path
                else ns:Log("buttons", (def.label or key) .. ": " .. tostring(b)) end
            end
        end
        if buttons[key] then buttons[key]:SetShown(on) end
    end
end

function GB:Set(on)
    ns.db.settings.gameButtons = on and true or false
    GB:Attach()
end

GB._Buttons = function() return buttons end   -- (tests)

ns:On("ADDON_LOADED", function() GB:Attach() end)
ns:On("PLAYER_ENTERING_WORLD", function() GB:Attach() end)
ns:On("PLAYER_REGEN_ENABLED", function() if waiting then GB:Attach() end end)

-------------------------------------------------------------------------------
-- The built-in ones
-------------------------------------------------------------------------------

-- The talent view is one of several frames, depending on the client (and a
-- client can have more than one of them, only one in use): a Flow Talents
-- button on each that exists, so it's on the one you open.
for i, frames in ipairs({
    { "PlayerSpellsFrame.TalentsFrame" },
    { "ClassTalentFrame.TalentsTab", "ClassTalentFrame" },
    { "PlayerTalentFrame", "TalentFrame" },
}) do
    ns:Register("gameButton", i == 1 and "talents" or ("talents" .. i), {
    order = 10 + (i - 1) * 0.1,
    alt = i > 1 or nil,
    frames = frames,
    label = "Flow Talents",
    tip = "Your talent trees with Flow's levelling build over them: what to take now, what comes at each level, and where it ends up.",
    isOpen = function() local f = ns.talents and ns.talents._Frame(); return f and f:IsShown() end,
    click = function()
        local T = ns.talents
        local f = T._Frame()
        if f and f:IsShown() then f:Hide() else T:Show() end
    end,
    })
end

ns:Register("gameButton", "spellbook", {
    order = 20,
    frames = { "PlayerSpellsFrame.SpellBookFrame", "SpellBookFrame" },
    label = "Flow Key Bindings",
    tip = "Hover any action button and press a key to bind it. Nothing changes until you click Save.",
    isOpen = function() return ns.bind and ns.bind.Active and ns.bind:Active() end,
    click = function()
        local B = ns.bind
        if B:Active() then B:Stop() else B:Start() end
    end,
})

ns:Register("gameButton", "professions", {
    order = 30,
    frames = { "ProfessionsFrame", "TradeSkillFrame" },
    label = "Flow Professions",
    tip = "Which professions Flow plans for you: tick the ones you want, and the route takes you to their trainers and skill-ups.",
    isOpen = function() local f = ns.professions and ns.professions._Frame and ns.professions._Frame(); return f and f:IsShown() end,
    click = function()
        local P = ns.professions
        local f = P._Frame and P._Frame()
        if f and f:IsShown() then f:Hide() else P:Open() end
    end,
})

ns:Register("gameButton", "character", {
    order = 40,
    frames = { "CharacterFrame" },
    label = "Flow Improvements",
    tip = "What would make your character stronger right now: spells to train, gear to put on, things to set up.",
    click = function() ns.advisor:TogglePanel() end,
})

-------------------------------------------------------------------------------
-- Settings, /flow buttons, help
-------------------------------------------------------------------------------

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "screen",
        label = "Flow buttons on WoW's windows",
        note = "(Flow Talents on the talent window...)",
        tip = "A Flow tab on top of the game's talent window, spellbook, profession window and "
            .. "character window opens the Flow view that goes with it (Flow Talents, Flow Key Bindings, Flow "
            .. "Professions, Flow Improvements). The Flow view stays closed until you click. /flow buttons lists them.",
        get = function() return GB.On() end,
        set = function(on) GB:Set(on) end,
    })
end

-- The game's windows that are open right now, by name: how to find what a
-- client calls a window Flow has no button on yet (open it, type /flow
-- buttons; the names go into the log too, so the diagnostics have them).
function GB.OpenWindows()
    local out = {}
    for _, f in ipairs({ UIParent:GetChildren() }) do
        local ok, name = pcall(function()
            local n = f:IsShown() and f:GetName()
            if n and not n:find("^Flow") and (f:GetWidth() or 0) >= 250 and (f:GetHeight() or 0) >= 250 then return n end
        end)
        if ok and name then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

ns.commands.buttons = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then GB:Set(arg == "on") end
    GB:Attach()
    ns:Print("Flow buttons on WoW's windows: " .. (GB.On() and "on" or "off") .. "  (/flow buttons on|off)")
    for _, e in ipairs(GB.List()) do
        local b = buttons[e.key]
        -- (A second home for a view, on a window this client doesn't have: not worth a line.)
        if b or not e.def.alt then print("  " .. GB.Line(e.def, paths[e.key], b and b:IsVisible())) end
    end
    if ns.mapOpen then
        for _, l in ipairs(ns.mapOpen.Lines()) do print("  " .. l) end
    end
    local open = GB.OpenWindows()
    if #open > 0 then
        local line = "WoW windows open now: " .. table.concat(open, ", ")
        print("  " .. line)
        ns:Log("buttons", line)
    end
end

ns:Register("help", "buttons", { order = 47, title = "Flow buttons on WoW's windows", lines = {
    "A Flow tab on top of the talent window, spellbook, profession window and character window opens the Flow view that goes with it.",
    "/flow buttons on|off: all of them. /flow buttons: which windows they found.",
} })
