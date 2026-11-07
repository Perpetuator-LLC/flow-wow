-- Setup table (/flow setup; opens once on first run). Each row is a setting
-- with a tick box showing its CURRENT state (ticked = on). Change any of them
-- and click Apply: it turns things on or off to match. Quick picks:
--   All / None / Flow suggests / WoW default / Reset (back to current)
-- Rows are registered, so features can add their own:
--   ns:Register("setupItem", key, { order, label, why, available = fn,
--       isOn = fn() -> bool, set = fn(on), suggested = bool, default = bool })
--   or an action row: { order, label, why, now = fn() -> text, action = "Set...", run = fn }
--   or an info row:   { order, label, why, now = fn() -> text, info = true }
-- Rows whose setting this client doesn't have are left out.

local _, ns = ...
local S = {}
ns.setup = S

local function cvar(name)
    local ok, v = pcall(GetCVar, name)
    if ok then return v end
end

local function cvarDefault(name)
    local ok, v = pcall(GetCVarDefault, name)
    if ok then return v end
end

-- An on/off CVar row.
local function cvarRow(key, order, label, why, name, onValue, offValue, suggested)
    ns:Register("setupItem", key, {
        order = order, label = label, why = why,
        available = function() return cvar(name) ~= nil end,
        isOn = function() return cvar(name) == onValue end,
        set = function(on) SetCVar(name, on and onValue or offValue) end,
        suggested = suggested,
        default = function() return cvarDefault(name) == onValue end,
    })
end

cvarRow("autoLoot", 10, "Auto loot", "Loot everything with one click instead of picking each item.",
    "autoLootDefault", "1", "0", true)
cvarRow("enemyPlates", 20, "Enemy nameplates", "Flow's quest marks (skull, diamond) sit on nameplates.",
    "nameplateShowEnemies", "1", "0", true)
cvarRow("friendPlates", 30, "Friendly nameplates", "Shows Flow's star on NPCs your quests mention.",
    "nameplateShowFriends", "1", "0", true)
cvarRow("instantQuest", 40, "Instant quest text", "Quest text appears at once instead of scrolling.",
    "instantQuestText", "1", "0", true)
cvarRow("autoPush", 50, "Auto-place new spells on bars",
    "The game drops newly learned spells into empty bar slots. Leave off if you place spells yourself.",
    "AutoPushSpellToActionBar", "1", "0", false)

-- Target of target: classic-style clients have a CVar; newer ones put it in Edit Mode
-- (Target Frame > "Target of Target"), so that case is an info row telling you where.
ns:Register("setupItem", "targetOfTarget", {
    order = 55, label = "Target of target",
    why = "Shows who your target is attacking, so you see when a mob turns on you or a party member.",
    available = function() return cvar("showTargetOfTarget") ~= nil end,
    isOn = function() return cvar("showTargetOfTarget") == "1" end,
    set = function(on)
        SetCVar("showTargetOfTarget", on and "1" or "0")
        if TargetofTarget_Update and TargetFrameToT then pcall(TargetofTarget_Update, TargetFrameToT) end
    end,
    suggested = true,
    default = function() return cvarDefault("showTargetOfTarget") == "1" end,
    isNew = true,  -- added after the first-run table: shown once to existing installs too
})
ns:Register("setupItem", "targetOfTargetEdit", {
    order = 55, label = "Target of target",
    why = "Shows who your target is attacking. Turn it on in Edit Mode: Target Frame > Target of Target.",
    available = function() return cvar("showTargetOfTarget") == nil end,
    now = function() return "in Edit Mode" end,
    info = true,
})

ns:Register("setupItem", "zoom", {
    order = 60, label = "Max camera zoom", why = "See more around you while questing.",
    isOn = function() return ns.camera:IsOn() end,
    set = function(on) ns.camera:Set(on) end,
    suggested = true, default = false,
})

ns:Register("setupItem", "stamps", {
    order = 70, label = "Chat timestamps", why = "See when each chat line arrived.",
    isOn = function() local v = cvar("showTimestamps"); return v ~= nil and v ~= "none" end,
    set = function(on) SetCVar("showTimestamps", on and "%H:%M:%S " or "none") end,
    suggested = true,
    default = function() local d = cvarDefault("showTimestamps"); return d ~= nil and d ~= "none" end,
})

ns:Register("setupItem", "colorblind", {
    order = 75, label = "Colour-blind route colours",
    why = "Route colours that stay apart for the common kinds of colour blindness (same meaning: route colour = order mode, orange = preview of the hovered stop).",
    isOn = function() return ns.theme:ColorBlind() end,
    set = function(on) ns.theme:SetColorBlind(on) end,
    suggested = false, default = false,
})

ns:Register("setupItem", "combatLog", {
    order = 80, label = "Combat log file every session",
    why = "Lets Claude analyse your fights and tune Flow's rotation (tools\\analyze-combatlog.ps1).",
    isOn = function() return ns.db.log and ns.db.log.auto == true end,
    set = function(on)
        ns.db.log.auto = on
        if LoggingCombat then pcall(LoggingCombat, on) end
    end,
    suggested = true, default = false,
})

ns:Register("setupItem", "castKey", {
    order = 90, label = "Flow cast key", why = "One key that casts Flow's suggestion.",
    now = function() return ns.db.cast.key and ns.cast:KeyLabel() or "not set" end,
    action = "Set...",
    run = function() if ns.settings then ns.settings:Open() end end,
})

ns:Register("setupItem", "questie", {
    order = 100, label = "Questie + QuestieDB",
    why = "Quest and NPC locations for the arrow, map route and missed quests. Install it yourself (CurseForge app).",
    now = function() return ns.quests:Source() and ns.quests:Source().label == "Questie" and "installed" or "not found" end,
    info = true,
})

-------------------------------------------------------------------------------
-- Panel
-------------------------------------------------------------------------------

local frame

local function rows()
    local list = {}
    for key, item in ns:Each("setupItem") do
        if not item.available or item.available() then list[#list + 1] = { key = key, item = item } end
    end
    table.sort(list, function(a, b) return (a.item.order or 100) < (b.item.order or 100) end)
    return list
end

local function val(v) if type(v) == "function" then return v() end return v end

local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    return b
end

local function each(fn)
    for _, row in ipairs(frame.rows) do if row.check then fn(row) end end
end

local function build()
    local list = rows()
    local f = CreateFrame("Frame", "FlowSetup", UIParent)
    f:SetSize(580, 128 + #list * 26)
    local p = ns.db.setup.point
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER", 0, 60) end
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    tinsert(UISpecialFrames, "FlowSetup")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    local top = f:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
    top:SetColorTexture(1, 0.82, 0.25, 0.9)
    ns:MakeMovable(f, ns.db.setup, true)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Flow settings")
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 16, -36)
    sub:SetText("Ticked = on. Change what you like and click Apply. Hover a row for why. /flow setup reopens this.")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local function header(text, x)
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", x, -58)
        h:SetText(text)
    end
    header("Setting", 48); header("Now", 320); header("Flow suggests", 400)

    f.rows = {}
    for i, r in ipairs(list) do
        local item = r.item
        local row = CreateFrame("Frame", nil, f)
        row:SetPoint("TOPLEFT", 12, -74 - (i - 1) * 26)
        row:SetSize(556, 24)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(item.label)
            GameTooltip:AddLine(item.why or "", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if item.isOn then
            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetSize(22, 22)
            row.check:SetPoint("LEFT", 6, 0)
            row.check:SetScript("OnClick", function() S:RefreshText() end)
        end
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", 36, 0)
        row.label:SetText(item.label)
        row.now = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.now:SetPoint("LEFT", 308, 0)
        row.want = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.want:SetPoint("LEFT", 388, 0)
        if item.isOn then row.want:SetText(item.suggested and "on" or "off") end
        if item.action then
            -- Own column on the right, clear of the text.
            local b = button(row, item.action, 70)
            b:SetPoint("RIGHT", -4, 0)
            b:SetScript("OnClick", function() item.run() end)
        end
        row.item = item
        f.rows[#f.rows + 1] = row
    end

    -- Quick picks + apply.
    local x = 12
    local function pick(text, w, fn)
        local b = button(f, text, w)
        b:SetPoint("BOTTOMLEFT", x, 12)
        x = x + w + 4
        b:SetScript("OnClick", function() fn(); S:RefreshText() end)
    end
    pick("All", 50, function() each(function(r) r.check:SetChecked(true) end) end)
    pick("None", 56, function() each(function(r) r.check:SetChecked(false) end) end)
    pick("Flow suggests", 104, function() each(function(r) r.check:SetChecked(r.item.suggested and true or false) end) end)
    pick("WoW default", 96, function() each(function(r) r.check:SetChecked(val(r.item.default) and true or false) end) end)
    pick("Reset", 60, function() each(function(r) r.check:SetChecked(r.item.isOn() and true or false) end) end)

    local apply = button(f, "Apply", 90)
    apply:SetPoint("BOTTOMRIGHT", -12, 12)
    apply:SetScript("OnClick", function()
        if InCombatLockdown() then ns:Print("can't change settings in combat") return end
        local n = 0
        each(function(r)
            local want = r.check:GetChecked() and true or false
            if want ~= (r.item.isOn() and true or false) then pcall(r.item.set, want); n = n + 1 end
        end)
        ns.db.setup.done = true
        ns:Print(n .. " setting(s) changed.")
        S:Refresh()
    end)
    f:Hide()
    return f
end

-- Updates the "Now" column (and marks rows you've changed but not applied).
function S:RefreshText()
    if not frame then return end
    for _, row in ipairs(frame.rows) do
        local item = row.item
        if item.isOn then
            local on = item.isOn() and true or false
            local pending = row.check:GetChecked() ~= on
            row.now:SetText((on and "on" or "off") .. (pending and "  |cffffd200(will change)|r" or ""))
        elseif item.now then
            local ok, t = pcall(item.now)
            row.now:SetText(ok and t or "?")
        end
    end
end

-- Tick boxes back to the current state of each setting.
function S:Refresh()
    if not frame then return end
    for _, row in ipairs(frame.rows) do
        if row.check then row.check:SetChecked(row.item.isOn() and true or false) end
    end
    self:RefreshText()
end

function S:Open()
    frame = frame or build()
    self:MarkSeen()
    frame:Show()
    self:Refresh()
end

ns:OnLoad(function(saved)
    saved.setup = saved.setup or {}
    if saved.settings then saved.settings.prompted = true end
end)

-- Suggested rows you've never been shown that are still off (e.g. a row added in an update).
-- Installs from before this list existed count every row as seen except ones marked isNew.
function S:Unseen()
    local db = ns.db.setup
    if not db.seen then
        db.seen = {}
        if db.done then
            for key, item in ns:Each("setupItem") do if not item.isNew then db.seen[key] = true end end
        end
    end
    local out = {}
    for _, r in ipairs(rows()) do
        local it = r.item
        if not db.seen[r.key] and it.isOn and it.suggested and not it.isOn() then out[#out + 1] = it.label end
    end
    return out
end

function S:MarkSeen()
    if not ns.db.setup.seen then self:Unseen() end
    for _, r in ipairs(rows()) do ns.db.setup.seen[r.key] = true end
end

-- First run, or once when an update adds a suggestion you haven't seen.
ns:On("PLAYER_ENTERING_WORLD", function()
    if ns.db.setup.done and #S:Unseen() == 0 then return end
    C_Timer.After(30, function()  -- well after the splash, so new players aren't swamped
        if InCombatLockdown() then return end
        local new = ns.db.setup.done and S:Unseen() or nil
        if new and #new == 0 then return end
        ns.db.setup.done = true
        S:MarkSeen()
        if new then ns:Print("new in the setup table: " .. table.concat(new, ", ")) end
        S:Open()
    end)
end)

ns.commands.setup = function() S:Open() end
ns:Register("help", "setup", { order = 4, title = "Setup", lines = {
    "/flow setup - settings table: auto loot, nameplates, zoom, timestamps, combat log, cast key...",
} })
