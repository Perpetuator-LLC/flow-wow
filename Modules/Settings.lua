-- Flow's settings: a page in the game's Options > AddOns > Flow (the
-- Settings API; older clients: Interface Options). /flow settings opens it.
--
--   Cast key       Click "Set key", press the key (modifiers and mouse
--                  buttons 3-5 work). If the key already does something,
--                  Flow says what and you choose: use it anyway (your own
--                  binding is untouched and comes back if you clear Flow's
--                  key) or pick another. Movement keys get an extra warning.
--   Flow           Flow's own options (route colours, 3D arrow, minimap).
--   Suggested WoW settings
--                  The game settings Flow recommends (Setup.lua rows: auto
--                  loot, nameplates, target of target, ...), each with what
--                  Flow suggests and why; "Use Flow's suggestions" sets all.
--
-- Nothing here calls Blizzard's panel functions (ShowUIPanel/HideUIPanel on
-- their frames): doing that from add-on code taints the game menu.

local _, ns = ...
local S = {}
ns.settings = S

local frame

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true,
}
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function withModifiers(key)
    local s = ""
    if IsAltKeyDown() then s = s .. "ALT-" end
    if IsControlKeyDown() then s = s .. "CTRL-" end
    if IsShiftKeyDown() then s = s .. "SHIFT-" end
    return s .. key
end

local function label(key)
    if not key then return "not set" end
    return (GetBindingText and GetBindingText(key, "KEY_", true)) or key
end

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 110, 24)
    b:SetText(text)
    return b
end

-- Every tick box and value on the page shows the current state.
local function refresh()
    if not frame then return end
    frame.keyValue:SetText(label(ns.db.cast.key))
    frame.clear:SetEnabled(ns.db.cast.key ~= nil)
    for _, c in ipairs(frame.checks or {}) do
        local ok, on = pcall(c.get)
        c:SetChecked(ok and on and true or false)
        if c.now then local ok2, t = pcall(c.nowText); c.now:SetText(ok2 and t or "") end
    end
end

local function stopCapture(msg)
    frame.capturing = false
    frame.capture:Hide()
    frame.status:SetText(msg or "")
end

-- A key was pressed while capturing: check it, then set it or ask.
local function choose(key)
    stopCapture()
    local what, action = ns.cast:Conflict(key)
    if not what then
        ns.cast:SetKey(key)
        frame.status:SetText("|cff66ff66" .. label(key) .. " now casts Flow's suggestion.|r")
        refresh()
        return
    end
    frame.pendingKey = key
    local warn = ns.cast:IsMovement(action) and "|cffff9933That's a movement key, so this isn't recommended.|r\n" or ""
    frame.status:SetText(string.format(
        "%s%s already does: |cffffd200%s|r.\nUse it for Flow anyway? Your own binding isn't changed; it comes back if you clear Flow's key.",
        warn, label(key), what))
    frame.confirm:Show()
    frame.another:Show()
end


local WIDTH = 580

local function heading(f, y, text)
    local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", 16, y)
    h:SetText(text)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -4)
    line:SetSize(WIDTH - 40, 1)
    line:SetColorTexture(1, 0.82, 0.25, 0.5)
    return y - 34
end

-- A tick box: label, grey note, tooltip; get() -> on, set(on).
local function check(f, y, text, note, tip, get, set)
    local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c:SetPoint("TOPLEFT", 14, y)
    c.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 4, 0)
    c.label:SetText(text .. (note and ("  |cff888888" .. note .. "|r") or ""))
    c.get = get
    c:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            refresh()
            frame.status:SetText("Settings can't change in combat.")
            return
        end
        local ok, err = pcall(set, self:GetChecked() and true or false)
        if not ok then ns:Log("settings", text .. ": " .. tostring(err)) end
        refresh()
    end)
    if tip then
        c:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(text)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    frame.checks[#frame.checks + 1] = c
    return c, y - 28
end

local function build(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local f = CreateFrame("Frame", "FlowSettings", scroll)
    f:SetSize(WIDTH, 900)
    scroll:SetScrollChild(f)
    f.scroll = scroll
    frame = f
    f.checks = {}

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.title:SetPoint("TOPLEFT", 16, -12)
    f.title:SetText("Flow  |cff888888v" .. (ns.Version and ns.Version() or "?") .. "|r")

    -- Cast key
    local y = heading(f, -52, "Cast key")
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT", 16, y - 4)
    name:SetText("Your key:")
    f.keyValue = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.keyValue:SetPoint("LEFT", name, "RIGHT", 12, 0)
    local set = button(f, "Set key", 90)
    set:SetPoint("TOPLEFT", 250, y)
    f.clear = button(f, "Clear", 80)
    f.clear:SetPoint("LEFT", set, "RIGHT", 8, 0)
    local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 16, y - 32)
    help:SetWidth(WIDTH - 40)
    help:SetJustifyH("LEFT")
    help:SetText("Press this key (or click the suggestion icon) to cast what Flow suggests. "
        .. "In combat WoW doesn't let add-ons change what a key casts, so it keeps the spell it "
        .. "had when the fight started; a small \"key:\" icon shows it.")
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 16, y - 66)
    f.status:SetWidth(WIDTH - 40)
    f.status:SetJustifyH("LEFT")
    f.confirm = button(f, "Use it anyway", 120)
    f.confirm:SetPoint("TOPLEFT", 16, y - 96)
    f.another = button(f, "Pick another", 110)
    f.another:SetPoint("LEFT", f.confirm, "RIGHT", 8, 0)
    f.confirm:Hide(); f.another:Hide()
    y = y - 126

    -- Flow's own options
    y = heading(f, y, "Flow")
    local _
    _, y = check(f, y, "Colour-blind route colours", "(safer colours)",
        "The route and arrow colour shows the route's state: purple = Most XP first, blue = Shortest path, orange = Custom route (you picked the next stop), green = your own waypoint. On: the same roles in colours that stay apart for the common kinds of colour blindness.",
        function() return ns.theme:ColorBlind() end, function(on) ns.theme:SetColorBlind(on) end)
    _, y = check(f, y, "3D arrow", "(off = flat line arrow)",
        "A shaded chevron lying on the ground ahead of you. It turns left and right; WoW: Forever gives no heights, so it can't point up or down.",
        function() return ns.db.nav.arrowStyle ~= "flat" end,
        function(on) ns.nav:SetArrowStyle(on and "3d" or "flat") end)
    _, y = check(f, y, "Stop areas on the minimap", nil,
        "The area of the stop the arrow points at, on the minimap (and the stop you hover in the Flow Tracker).",
        function() return ns.db.nav.minimapAreas ~= false end,
        function(on) ns.db.nav.minimapAreas = on; if ns.minimapPin then ns.minimapPin:Hide() end end)
    _, y = check(f, y, "Show the route on the world map", nil, nil,
        function() return ns.db.nav.mapLines ~= false end,
        function(on) ns.db.nav.mapLines = on end)
    _, y = check(f, y, "Intro on the arrow when you log in", "(/flow splash replays it)",
        "After logging in or /reload the arrow spins, shows FLOW in its ring, and the version and status underneath.",
        function() return ns.db.splash.enabled ~= false end,
        function(on) ns.db.splash.enabled = on end)
    _, y = check(f, y, "Flow key does fishing and gathering steps", "(/flow action)",
        "Out of combat at a fishing or gathering stop, the key equips your pole, puts on a lure, casts and reels in; at veins and herbs it gathers.",
        function() return ns.db.actions.enabled ~= false end,
        function(on) ns.db.actions.enabled = on end)
    _, y = check(f, y, "Flow Seller: auto-sell at vendors", "(also on the Flow Seller drawer)",
        "When you open a vendor, sell everything Flow marks to sell: up to 12 a visit, so you can buy any back (Flow then never sells it again).",
        function() return ns.db.sell.autoAll == true end,
        function(on) ns.db.sell.autoAll = on end)
    _, y = check(f, y, "Flow Seller: auto-sell grey junk", nil,
        "Sells every grey item as soon as you open a vendor.",
        function() return ns.db.sell.autoJunk == true end,
        function(on) ns.db.sell.autoJunk = on end)
    _, y = check(f, y, "Accept group invites from friends", "(/flow invites)",
        "Invites from your friends list and Battle.net friends are accepted for you. Anyone else gets the usual popup.",
        function() return ns.db.invites.friends ~= false end,
        function(on) ns.db.invites.friends = on end)
    y = y - 10

    -- Suggested WoW settings (Setup.lua rows)
    f.suggestTop = y
    y = heading(f, y, "Suggested WoW settings")
    local intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 16, y + 4)
    intro:SetWidth(WIDTH - 40)
    intro:SetJustifyH("LEFT")
    intro:SetText("Game settings that help while levelling. Each row says what Flow suggests; hover it for why.")
    y = y - 20
    local suggestions = {}
    for _, r in ipairs(ns.setup and ns.setup:Rows() or {}) do
        local item = r.item
        if item.isOn then
            _, y = check(f, y, item.label,
                item.suggested and "|cff66ff66Flow suggests on|r" or "Flow suggests off",
                item.why, item.isOn, item.set)
            suggestions[#suggestions + 1] = item
        elseif item.now and not item.action then
            local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            t:SetPoint("TOPLEFT", 42, y - 4)
            t:SetWidth(WIDTH - 70)
            t:SetJustifyH("LEFT")
            local ok, now = pcall(item.now)
            t:SetText(item.label .. ":  |cffffd200" .. tostring(ok and now or "?") .. "|r  |cff888888" .. (item.why or "") .. "|r")
            y = y - math.max(24, t:GetStringHeight() + 8)
        end
    end
    local all = button(f, "Use Flow's suggestions", 190)
    all:SetPoint("TOPLEFT", 16, y - 6)
    all:SetScript("OnClick", function()
        if InCombatLockdown() then f.status:SetText("Settings can't change in combat.") return end
        local n = 0
        for _, item in ipairs(suggestions) do
            local want = item.suggested and true or false
            if want ~= (item.isOn() and true or false) then pcall(item.set, want); n = n + 1 end
        end
        ns.db.setup.done = true
        ns:Print(n .. " setting(s) changed to Flow's suggestions.")
        refresh()
    end)
    y = y - 44
    f:SetHeight(-y + 20)

    -- Key capture overlay (over the visible page).
    local cap = CreateFrame("Button", nil, parent)
    cap:SetAllPoints(parent)
    cap:SetFrameLevel(parent:GetFrameLevel() + 50)
    cap.bg = cap:CreateTexture(nil, "BACKGROUND")
    cap.bg:SetAllPoints()
    cap.bg:SetColorTexture(0, 0, 0, 0.85)
    cap.text = cap:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cap.text:SetPoint("CENTER")
    cap.text:SetText("Press a key for Flow (Escape cancels)")
    cap:EnableKeyboard(true)
    if cap.SetPropagateKeyboardInput then cap:SetPropagateKeyboardInput(false) end
    cap:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then stopCapture("Cancelled.") return end
        if MODIFIER_KEYS[key] then return end
        choose(withModifiers(key))
    end)
    cap:RegisterForClicks("AnyUp")
    cap:SetScript("OnMouseDown", function(_, mb)
        if MOUSE[mb] then choose(withModifiers(MOUSE[mb])) end
    end)
    cap:Hide()
    f.capture = cap

    set:SetScript("OnClick", function()
        if InCombatLockdown() then f.status:SetText("Key bindings can't change in combat.") return end
        f.confirm:Hide(); f.another:Hide()
        f.capturing = true
        cap:Show()
    end)
    f.clear:SetScript("OnClick", function()
        ns.cast:SetKey(nil)
        f.status:SetText("Flow's key cleared; that key does what it did before.")
        refresh()
    end)
    f.confirm:SetScript("OnClick", function()
        ns.cast:SetKey(f.pendingKey)
        f.status:SetText("|cff66ff66" .. label(f.pendingKey) .. " now casts Flow's suggestion.|r")
        f.confirm:Hide(); f.another:Hide()
        refresh()
    end)
    f.another:SetScript("OnClick", function()
        f.confirm:Hide(); f.another:Hide()
        f.capturing = true
        cap:Show()
    end)
    return f
end

-------------------------------------------------------------------------------
-- The page in Options > AddOns.
-------------------------------------------------------------------------------

local canvas, category

local function register()
    canvas = CreateFrame("Frame")
    canvas.name = "Flow"
    canvas:SetSize(WIDTH + 40, 600)
    canvas:SetScript("OnShow", function(self)
        if not frame then build(self) end
        refresh()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(canvas, "Flow")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(canvas)
    end
end

-- Opens Flow's page in the game's Options. `section` "suggest" scrolls to
-- the suggested WoW settings. Returns false if this client has no page.
function S:Open(section)
    if InCombatLockdown() then ns:Print("Options can't open in combat.") return true end
    local opened = false
    if category and Settings and Settings.OpenToCategory then
        opened = pcall(Settings.OpenToCategory, (category.GetID and category:GetID()) or category)
    elseif canvas and InterfaceOptionsFrame_OpenToCategory then
        opened = pcall(InterfaceOptionsFrame_OpenToCategory, canvas)
        pcall(InterfaceOptionsFrame_OpenToCategory, canvas)  -- (older clients need it twice)
    end
    if not opened then return false end
    if not frame and canvas then build(canvas) end
    refresh()
    if section == "suggest" and frame and frame.scroll and frame.suggestTop then
        C_Timer.After(0, function() frame.scroll:SetVerticalScroll(math.max(0, -frame.suggestTop - 10)) end)
    end
    return true
end

-- (Tests) the page's rows: Flow options and suggested WoW settings.
function S:Checks()
    return frame and frame.checks or {}
end

ns:OnLoad(function(saved)
    saved.settings = saved.settings or {}
    pcall(register)
end)

-- First run: open the page once so the key can be set.
ns:On("PLAYER_ENTERING_WORLD", function()
    if ns.db.cast.key or ns.db.settings.prompted then return end
    ns.db.settings.prompted = true
    C_Timer.After(7, function()
        if not InCombatLockdown() and S:Open() and frame then
            frame.status:SetText("First setting: pick the key that casts Flow's suggestion.")
        end
    end)
end)

ns.commands.settings = function() if not S:Open() then ns:Print("this client has no add-on options page") end end
ns.commands.key = function(arg)
    if (arg or ""):lower():match("^%s*test") then ns.cast:Test() else ns.commands.settings() end
end
ns:Register("help", "settings", { order = 5, title = "Settings", lines = {
    "/flow settings (or Game Menu > Options > AddOns > Flow) - cast key, Flow options, suggested WoW settings",
    "/flow key test - check the cast key",
    "/flow zoom on|off - max camera zoom",
} })
