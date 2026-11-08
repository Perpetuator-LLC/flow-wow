-- Hover-to-bind mode (/flow bind): hover an action button (or stance button,
-- or Flow's cast button) and press a key or mouse button 3-5. Nothing changes
-- until you click Save:
--   * every change is listed first ("Shift-2 -> Action Bar 1 slot 2, was: ...")
--   * Ctrl+Z undoes the last change
--   * Save keeps them; Cancel drops them
--   * Esc cancels everything; with more than 3 changes it asks first, and Esc
--     again (or "Keep editing") takes you back to binding
--   * right-click a button to clear its keys (also listed until you save)
-- Bindings can't change in combat, so the mode closes if a fight starts.

local _, ns = ...
local B = {}
ns.bind = B

local BARS = {
    { "ActionButton", "ACTIONBUTTON", "Action Bar 1" },
    { "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON", "Bottom Left Bar" },
    { "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON", "Bottom Right Bar" },
    { "MultiBarRightButton", "MULTIACTIONBAR3BUTTON", "Right Bar" },
    { "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON", "Right Bar 2" },
    { "MultiBar5Button", "MULTIACTIONBAR5BUTTON", "Bar 6" },
    { "MultiBar6Button", "MULTIACTIONBAR6BUTTON", "Bar 7" },
    { "MultiBar7Button", "MULTIACTIONBAR7BUTTON", "Bar 8" },
    { "StanceButton", "SHAPESHIFTBUTTON", "Stance Bar" },
}
local FLOW_CAST = "FLOW_CAST"  -- special: Flow's own cast key (override binding)
local MODIFIERS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, LMETA = 1, RMETA = 1 }
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local MOVEMENT = { MOVEFORWARD = 1, MOVEBACKWARD = 1, TURNLEFT = 1, TURNRIGHT = 1, STRAFELEFT = 1, STRAFERIGHT = 1, JUMP = 1 }

local active = false
local overlays = {}   -- list of { frame, cmd, label }
local hovered         -- overlay entry under the mouse
local staged = {}     -- { { key, cmd, label, was } } in order; cmd nil = clear key
local capture, panel, confirm

local function keyText(key) return (GetBindingText and GetBindingText(key, "KEY_", true)) or key end
local function cmdName(cmd)
    if cmd == FLOW_CAST then return "Flow cast key" end
    return (cmd and _G["BINDING_NAME_" .. cmd]) or cmd or "nothing"
end

local function withModifiers(key)
    local s = ""
    if IsAltKeyDown() then s = s .. "ALT-" end
    if IsControlKeyDown() then s = s .. "CTRL-" end
    if IsShiftKeyDown() then s = s .. "SHIFT-" end
    return s .. key
end

-- What a key will do after the staged changes (for the overlay labels).
local function stagedKeysFor(cmd)
    local keys = {}
    if cmd == FLOW_CAST then
        for _, k in ipairs(ns.cast:Keys()) do keys[k] = true end   -- (both of Flow's keys)
    else
        for _, k in ipairs({ GetBindingKey(cmd) }) do keys[k] = true end
    end
    for _, s in ipairs(staged) do
        if s.cmd == cmd then keys[s.key] = true
        elseif keys[s.key] then keys[s.key] = nil end         -- key moved elsewhere
        if s.clear == cmd then keys[s.key] = nil end
    end
    return keys
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------

local function refresh()
    if not panel then return end
    local lines = {}
    for i, s in ipairs(staged) do
        if s.clear then
            lines[#lines + 1] = string.format("%d. clear |cffffd200%s|r from %s", i, keyText(s.key), cmdName(s.clear))
        else
            local warn = (s.wasCmd and MOVEMENT[s.wasCmd]) and " |cffff9933(movement key!)|r" or ""
            lines[#lines + 1] = string.format("%d. |cffffd200%s|r -> %s%s%s", i, keyText(s.key), s.label,
                (s.was and s.was ~= "" and s.wasCmd ~= s.cmd) and (" |cff888888(was: " .. s.was .. ")|r") or "", warn)
        end
    end
    panel.list:SetText(#lines > 0 and table.concat(lines, "\n") or "|cff888888No changes yet. Hover a button and press a key.|r")
    panel:SetHeight(math.max(140, 100 + #lines * 14))
    panel.save:SetEnabled(#staged > 0)
    for _, o in ipairs(overlays) do
        local names = {}
        for k in pairs(stagedKeysFor(o.cmd)) do names[#names + 1] = keyText(k) end
        o.frame.text:SetText(table.concat(names, " "))
    end
end

local function buildPanel()
    local f = CreateFrame("Frame", "FlowBindPanel", UIParent)
    f:SetSize(420, 140)
    f:SetPoint("TOP", 0, -80)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    local top = f:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
    local o = ns.theme.arrow
    top:SetColorTexture(o[1], o[2], o[3], 1)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText("Key binding mode: hover a button, press a key")
    f.help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.help:SetPoint("TOPLEFT", 12, -28)
    f.help:SetText("Right-click a button to clear it.  Ctrl+Z: undo last.  Esc: cancel.")
    f.list = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.list:SetPoint("TOPLEFT", 12, -50)
    f.list:SetWidth(396)
    f.list:SetJustifyH("LEFT")
    f.save = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.save:SetSize(100, 22)
    f.save:SetPoint("BOTTOMRIGHT", -116, 10)
    f.save:SetText("Save")
    f.save:SetScript("OnClick", function() B:Save() end)
    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(100, 22)
    cancel:SetPoint("BOTTOMRIGHT", -10, 10)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() B:Stop("cancelled; nothing changed") end)
    f:Hide()
    return f
end

local function buildConfirm()
    local f = CreateFrame("Frame", "FlowBindConfirm", UIParent)
    f:SetSize(320, 90)
    f:SetPoint("CENTER", 0, 100)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(50)
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.1, 0.06, 0.02, 0.97)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOP", 0, -14)
    f.text:SetWidth(300)
    local discard = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    discard:SetSize(130, 22)
    discard:SetPoint("BOTTOMLEFT", 20, 12)
    discard:SetText("Discard all")
    discard:SetScript("OnClick", function() f:Hide(); B:Stop("cancelled; nothing changed") end)
    local keep = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    keep:SetSize(130, 22)
    keep:SetPoint("BOTTOMRIGHT", -20, 12)
    keep:SetText("Keep editing")
    keep:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    return f
end

-------------------------------------------------------------------------------
-- Staging
-------------------------------------------------------------------------------

local function stage(key, entry)
    local wasCmd = GetBindingAction(key)
    -- The same key staged earlier for something else: the newest wins.
    for i = #staged, 1, -1 do
        if staged[i].key == key and not staged[i].clear then table.remove(staged, i) end
    end
    staged[#staged + 1] = { key = key, cmd = entry.cmd, label = entry.label,
                            wasCmd = wasCmd, was = (wasCmd and wasCmd ~= "") and cmdName(wasCmd) or nil }
    refresh()
end

local function stageClear(entry)
    for k in pairs(stagedKeysFor(entry.cmd)) do
        staged[#staged + 1] = { key = k, clear = entry.cmd }
    end
    refresh()
end

local function onKey(_, key)
    if confirm and confirm:IsShown() then
        if key == "ESCAPE" then confirm:Hide() end   -- back to binding
        return
    end
    if key == "ESCAPE" then
        if #staged > 3 then
            confirm.text:SetText(string.format("Discard %d key binding changes?", #staged))
            confirm:Show()
        else
            B:Stop("cancelled; nothing changed")
        end
        return
    end
    if MODIFIERS[key] then return end
    if key == "Z" and IsControlKeyDown() and not IsShiftKeyDown() and not IsAltKeyDown() then
        table.remove(staged)
        refresh()
        return
    end
    if hovered then stage(withModifiers(key), hovered) end
end

-------------------------------------------------------------------------------
-- Overlays on the buttons
-------------------------------------------------------------------------------

local function overlayFor(btn, cmd, label)
    local f = btn.flowBindOverlay
    if not f then
        f = CreateFrame("Button", nil, btn)
        f:SetAllPoints()
        f.hl = f:CreateTexture(nil, "OVERLAY")
        f.hl:SetAllPoints()
        f.text = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        f.text:SetPoint("TOPRIGHT", -2, -2)
        f:RegisterForClicks("AnyUp")
        btn.flowBindOverlay = f
    end
    local o = ns.theme.arrow
    f.hl:SetColorTexture(o[1], o[2], o[3], 0.15)
    f:SetFrameLevel(btn:GetFrameLevel() + 30)
    local entry = { frame = f, cmd = cmd, label = label }
    f:SetScript("OnEnter", function(self)
        hovered = entry
        self.hl:SetColorTexture(o[1], o[2], o[3], 0.45)
        ns.Tip(self, "ANCHOR_TOP")
        GameTooltip:AddLine(label)
        GameTooltip:AddLine("Press a key to bind. Right-click to clear.", 1, 1, 1)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function(self)
        if hovered == entry then hovered = nil end
        self.hl:SetColorTexture(o[1], o[2], o[3], 0.15)
        GameTooltip:Hide()
    end)
    f:SetScript("OnMouseDown", function(_, mb)
        if MOUSE[mb] then stage(withModifiers(MOUSE[mb]), entry) end
    end)
    f:SetScript("OnClick", function(_, mb)
        if mb == "RightButton" then stageClear(entry) end
    end)
    f:Show()
    overlays[#overlays + 1] = entry
end

local function addOverlays()
    wipe(overlays)
    for _, bar in ipairs(BARS) do
        for i = 1, (bar[1] == "StanceButton" and 10 or 12) do
            local btn = _G[bar[1] .. i]
            if btn and btn:IsVisible() then
                overlayFor(btn, bar[2] .. i, bar[3] .. " slot " .. i)
            end
        end
    end
    if _G.FlowCastButton and _G.FlowCastButton:IsVisible() then
        overlayFor(_G.FlowCastButton, FLOW_CAST, "Flow cast button")
    end
end

-------------------------------------------------------------------------------
-- Start / save / stop
-------------------------------------------------------------------------------

function B:Start()
    if InCombatLockdown() then ns:Print("key bindings can't change in combat") return end
    if active then return end
    active = true
    wipe(staged)
    panel = panel or buildPanel()
    confirm = confirm or buildConfirm()
    if not capture then
        capture = CreateFrame("Frame", "FlowBindCapture", UIParent)
        capture:SetAllPoints()
        capture:SetFrameStrata("FULLSCREEN")
        capture:EnableMouse(false)
        capture:SetScript("OnKeyDown", onKey)
    end
    capture:EnableKeyboard(true)
    if capture.SetPropagateKeyboardInput then capture:SetPropagateKeyboardInput(false) end
    capture:Show()
    addOverlays()
    panel:Show()
    refresh()
end

function B:Stop(msg)
    active = false
    hovered = nil
    wipe(staged)
    if capture then capture:EnableKeyboard(false); capture:Hide() end
    for _, o in ipairs(overlays) do o.frame:Hide() end
    wipe(overlays)
    if panel then panel:Hide() end
    if confirm then confirm:Hide() end
    if msg then ns:Print("key binding mode " .. msg) end
end

function B:Save()
    if InCombatLockdown() then ns:Print("can't save bindings in combat") return end
    local n = 0
    for _, s in ipairs(staged) do
        if s.clear then
            if s.clear == FLOW_CAST then ns.cast:SetKey(nil) else SetBinding(s.key) end
        elseif s.cmd == FLOW_CAST then
            ns.cast:SetKey(s.key)
        else
            SetBinding(s.key, s.cmd)
        end
        n = n + 1
    end
    if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
    if ns.cast then ns.cast:ApplyKey() end
    B:Stop(string.format("saved %d change(s)", n))
end

ns:On("PLAYER_REGEN_DISABLED", function()
    if active then B:Stop("closed: a fight started (nothing changed)") end
end)

ns.commands.bind = function() B:Start() end
ns:Register("help", "bind", { order = 6, title = "Key binding mode", lines = {
    "/flow bind - hover a button, press a key; Save or Cancel. Ctrl+Z undo, Esc cancel, right-click clears.",
} })
