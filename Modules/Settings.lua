-- Flow settings window. /flow settings (also in the game's Options >
-- AddOns list where the client supports it).
--
-- First setting: the cast key. Click "Set key", press the key (modifiers and
-- mouse buttons 3-5 work). If the key already does something else, Flow says
-- what, and you choose: use it anyway (Flow overrides it only while Flow is
-- loaded; your own binding is untouched and comes back if you clear Flow's
-- key) or pick another. Movement keys get an extra warning.
--
-- More settings are added as rows in build(); keep each one self-explaining.

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

local function refresh()
    if not frame then return end
    frame.keyValue:SetText(label(ns.db.cast.key))
    frame.clear:SetEnabled(ns.db.cast.key ~= nil)
    if frame.zoom and ns.camera then frame.zoom:SetChecked(ns.camera:IsOn()) end
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

local function build()
    local f = CreateFrame("Frame", "FlowSettings", UIParent)
    f:SetSize(420, 300)
    local p = ns.db.settings.point
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER", 0, 120) end
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
    f.edge = f:CreateTexture(nil, "BORDER")
    f.edge:SetPoint("TOPLEFT", 0, 0)
    f.edge:SetPoint("TOPRIGHT", 0, 0)
    f.edge:SetHeight(2)
    f.edge:SetColorTexture(1, 0.82, 0.25, 0.9)
    ns:MakeMovable(f, ns.db.settings, true)
    tinsert(UISpecialFrames, "FlowSettings")  -- Escape closes it

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.title:SetText("Flow settings  |cff888888v" .. (ns.Version and ns.Version() or "?") .. "|r")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- Row: cast key
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT", 16, -52)
    name:SetText("Cast key")
    f.keyValue = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.keyValue:SetPoint("LEFT", name, "RIGHT", 16, 0)

    local set = button(f, "Set key", 90)
    set:SetPoint("TOPRIGHT", -110, -46)
    f.clear = button(f, "Clear", 80)
    f.clear:SetPoint("LEFT", set, "RIGHT", 8, 0)

    local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 16, -80)
    help:SetWidth(388)
    help:SetJustifyH("LEFT")
    help:SetText("Press this key (or click the suggestion icon) to cast what Flow suggests. "
        .. "In combat WoW doesn't let addons change what a key casts, so it keeps the spell it "
        .. "had when the fight started; a small \"key:\" icon shows it.")

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 16, -132)
    f.status:SetWidth(388)
    f.status:SetJustifyH("LEFT")

    -- Row: max camera zoom (Camera.lua). Unticking restores the game default.
    local zoom = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    zoom:SetSize(24, 24)
    zoom:SetPoint("TOPLEFT", 12, -206)
    local zoomLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    zoomLabel:SetPoint("LEFT", zoom, "RIGHT", 4, 0)
    zoomLabel:SetText("Max camera zoom  |cff888888(off = game default)|r")
    zoom:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            self:SetChecked(ns.camera:IsOn())
            f.status:SetText("Camera settings can't change in combat.")
            return
        end
        ns.camera:Set(self:GetChecked() and true or false)
    end)
    f.zoom = zoom

    f.confirm = button(f, "Use it anyway", 120)
    f.confirm:SetPoint("BOTTOMLEFT", 16, 14)
    f.another = button(f, "Pick another", 110)
    f.another:SetPoint("LEFT", f.confirm, "RIGHT", 8, 0)
    f.confirm:Hide()
    f.another:Hide()

    -- Key capture overlay.
    local cap = CreateFrame("Button", nil, f)
    cap:SetAllPoints()
    cap:SetFrameLevel(f:GetFrameLevel() + 20)
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

    f:SetScript("OnShow", refresh)
    f:Hide()
    return f
end

function S:Open()
    frame = frame or build()
    frame:Show()
    refresh()
end

-- Entry in the game's Options > AddOns list (clients with the Settings API),
-- or the older Interface Options list.
local function registerInOptions()
    local canvas = CreateFrame("Frame")
    canvas.name = "Flow"
    local t = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("Flow")
    local b = button(canvas, "Open Flow settings", 160)
    b:SetPoint("TOPLEFT", 16, -48)
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
        S:Open()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(canvas, "Flow")
        Settings.RegisterAddOnCategory(cat)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(canvas)
    end
end

ns:OnLoad(function(saved)
    saved.settings = saved.settings or {}
    pcall(registerInOptions)
end)

-- First run: open settings once so the key can be set.
ns:On("PLAYER_ENTERING_WORLD", function()
    if ns.db.cast.key or ns.db.settings.prompted then return end
    ns.db.settings.prompted = true
    C_Timer.After(7, function()
        if not InCombatLockdown() then
            S:Open()
            frame.status:SetText("First setting: pick the key that casts Flow's suggestion.")
        end
    end)
end)

ns.commands.settings = function() S:Open() end
ns.commands.key = function(arg)
    if (arg or ""):lower():match("^%s*test") then ns.cast:Test() else S:Open() end
end
ns:Register("help", "settings", { order = 5, title = "Settings", lines = {
    "/flow settings (or /flow key) - set the key that casts Flow's suggestion; /flow key test - check it",
    "/flow zoom on|off - max camera zoom (also in /flow settings)",
} })
