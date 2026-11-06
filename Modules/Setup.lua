-- First-run setup: a table of recommended settings. Each row shows what the
-- setting is now and what Flow suggests; tick the ones you want and click
-- "Apply selected". Shown once the first time Flow loads; /flow setup
-- reopens it. Rows are registered, so features can add their own:
--   ns:Register("setupItem", key, { order, label, why, now = fn() -> text,
--       suggested = "text", isSet = fn() -> bool, apply = fn(), action = "Set..." })
-- Rows whose setting this client doesn't have are left out.

local _, ns = ...
local S = {}
ns.setup = S

local function cvar(name)
    local ok, v = pcall(GetCVar, name)
    if ok then return v end
end

local function cvarRow(key, order, label, why, name, want, wantText, nowText)
    ns:Register("setupItem", key, {
        order = order, label = label, why = why,
        available = function() return cvar(name) ~= nil end,
        now = function() return nowText(cvar(name)) end,
        suggested = wantText,
        isSet = function() return cvar(name) == want end,
        apply = function() SetCVar(name, want) end,
    })
end

local onOff = function(v) return v == "1" and "on" or "off" end

cvarRow("autoLoot", 10, "Auto loot", "Loot everything with one click instead of picking each item.",
    "autoLootDefault", "1", "on", onOff)
cvarRow("enemyPlates", 20, "Enemy nameplates", "Flow's quest marks (skull, diamond) sit on nameplates.",
    "nameplateShowEnemies", "1", "on", onOff)
cvarRow("friendPlates", 30, "Friendly nameplates", "Shows Flow's star on NPCs your quests mention.",
    "nameplateShowFriends", "1", "on", onOff)
cvarRow("instantQuest", 40, "Instant quest text", "Quest text appears at once instead of scrolling.",
    "instantQuestText", "1", "on", onOff)
cvarRow("autoPush", 50, "Auto-place new spells on bars",
    "The game drops newly learned spells into empty bar slots. Off if you place spells yourself.",
    "AutoPushSpellToActionBar", "0", "off", onOff)

ns:Register("setupItem", "zoom", {
    order = 60, label = "Max camera zoom", why = "See more around you while questing.",
    now = function() return ns.camera:IsOn() and "max" or "game default" end,
    suggested = "max",
    isSet = function() return ns.camera:IsOn() end,
    apply = function() ns.camera:Set(true) end,
})

ns:Register("setupItem", "stamps", {
    order = 70, label = "Chat timestamps", why = "See when each chat line arrived.",
    now = function() local v = cvar("showTimestamps"); return (v and v ~= "none") and "on" or "off" end,
    suggested = "on",
    isSet = function() local v = cvar("showTimestamps"); return v ~= nil and v ~= "none" end,
    apply = function() SetCVar("showTimestamps", "%H:%M:%S ") end,
})

ns:Register("setupItem", "combatLog", {
    order = 80, label = "Combat log file every session",
    why = "Lets Claude analyse your fights and tune Flow's rotation (tools\\analyze-combatlog.ps1).",
    now = function() return ns.db.log and ns.db.log.auto and "on" or "off" end,
    suggested = "on",
    isSet = function() return ns.db.log and ns.db.log.auto end,
    apply = function() ns.db.log.auto = true; if LoggingCombat then pcall(LoggingCombat, true) end end,
})

ns:Register("setupItem", "castKey", {
    order = 90, label = "Flow cast key", why = "One key that casts Flow's suggestion.",
    now = function() return ns.db.cast.key and ns.cast:KeyLabel() or "not set" end,
    suggested = "a key you like",
    isSet = function() return ns.db.cast.key ~= nil end,
    action = "Set...",
    apply = function() if ns.settings then ns.settings:Open() end end,
})

ns:Register("setupItem", "questie", {
    order = 100, label = "Questie + QuestieDB", why = "Quest and NPC locations for the arrow, map route and missed quests.",
    now = function() return ns.quests:Source() and ns.quests:Source().label == "Questie" and "installed" or "not found" end,
    suggested = "installed",
    isSet = function() return ns.quests:Source() and ns.quests:Source().label == "Questie" end,
    info = true,  -- can't be applied from here
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

local function build()
    local list = rows()
    local f = CreateFrame("Frame", "FlowSetup", UIParent)
    f:SetSize(560, 110 + #list * 26)
    f:SetPoint("CENTER", 0, 60)
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
    title:SetText("Welcome to Flow: recommended settings")
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 16, -36)
    sub:SetText("Tick what you want and click Apply. Hover a row for why. Reopen any time with /flow setup.")

    local function header(text, x)
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", x, -58)
        h:SetText(text)
    end
    header("Setting", 44); header("Now", 300); header("Flow suggests", 400)

    f.rows = {}
    for i, r in ipairs(list) do
        local y = -74 - (i - 1) * 26
        local row = CreateFrame("Frame", nil, f)
        row:SetPoint("TOPLEFT", 12, y)
        row:SetSize(536, 24)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.item.label)
            GameTooltip:AddLine(r.item.why or "", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if r.item.action then
            local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            b:SetSize(56, 20)
            b:SetPoint("LEFT", 0, 0)
            b:SetText(r.item.action)
            b:SetScript("OnClick", function() r.item.apply() end)
        elseif not r.item.info then
            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetSize(22, 22)
            row.check:SetPoint("LEFT", 2, 0)
        end
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", 32, 0)
        row.label:SetText(r.item.label)
        row.now = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.now:SetPoint("LEFT", 288, 0)
        row.want = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.want:SetPoint("LEFT", 388, 0)
        row.want:SetText(r.item.suggested or "")
        row.item = r.item
        f.rows[#f.rows + 1] = row
    end

    local apply = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    apply:SetSize(140, 24)
    apply:SetPoint("BOTTOMRIGHT", -110, 12)
    apply:SetText("Apply selected")
    apply:SetScript("OnClick", function()
        if InCombatLockdown() then ns:Print("can't change settings in combat") return end
        local n = 0
        for _, row in ipairs(f.rows) do
            if row.check and row.check:GetChecked() and not row.item.isSet() then
                pcall(row.item.apply); n = n + 1
            end
        end
        ns.db.setup.done = true
        ns:Print(n .. " setting(s) applied. /flow setup to change them later.")
        S:Refresh()
    end)
    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(90, 24)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetText("Not now")
    close:SetScript("OnClick", function() ns.db.setup.done = true; f:Hide() end)
    f:Hide()
    return f
end

function S:Refresh()
    if not frame then return end
    for _, row in ipairs(frame.rows) do
        local ok, now = pcall(row.item.now)
        local set = row.item.isSet() and true or false
        row.now:SetText((ok and now or "?") .. (set and "  |cff66ff66(done)|r" or ""))
        -- Pre-tick what isn't set yet.
        if row.check then row.check:SetChecked(not set) end
    end
end

function S:Open()
    frame = frame or build()
    frame:Show()
    self:Refresh()
end

ns:OnLoad(function(saved)
    saved.setup = saved.setup or {}
    -- The old first-run prompt (settings window) is replaced by this table.
    if saved.settings then saved.settings.prompted = true end
end)

ns:On("PLAYER_ENTERING_WORLD", function()
    if ns.db.setup.done then return end
    C_Timer.After(7, function()
        if not InCombatLockdown() and not ns.db.setup.done then S:Open() end
    end)
end)

ns.commands.setup = function() S:Open() end
ns:Register("help", "setup", { order = 4, title = "Setup", lines = {
    "/flow setup - recommended settings table (auto loot, nameplates, zoom, cast key...)",
} })
