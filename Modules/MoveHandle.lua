-- Moving and resizing Flow's secure buttons (the Flow key): a handle that
-- appears over the button while you hold Ctrl (ns.MoveKeyDown, Core.lua), out
-- of combat. Drag it to move the button, turn the mouse wheel to resize it.
-- (Kept out of Core.lua: the core holds registries and the event bus; this
-- is UI, and the Flow key is its only user so far. Loaded after Theme.lua.)

local _, ns = ...

-- Sizes a button can take with Ctrl + mouse wheel: half to double size, in
-- steps of a tenth. ClampScale rounds to the nearest 5 % and keeps it in range.
ns.SCALE_MIN, ns.SCALE_MAX, ns.SCALE_STEP = 0.5, 2, 0.1
function ns.ClampScale(s)
    s = tonumber(s) or 1
    s = math.floor(s * 20 + 0.5) / 20
    return math.max(ns.SCALE_MIN, math.min(ns.SCALE_MAX, s))
end

-- ns:MoveHandle(target, opts): moving and resizing a secure button (the
-- Flow button). Out of combat, hold Ctrl and a handle appears over it: drag
-- it to move the button, turn the mouse wheel over it to resize it. (Ctrl,
-- as in Questie, since 0.35.138: Shift now shows what Shift + your key casts.
-- The handle shows while Ctrl is down, so a Ctrl key binding flashes it.)
-- Dragging the secure button itself didn't work
-- (it takes the press as a click), and a secure button can't move or change
-- size in a fight, so the handle does both, and only out of combat.
-- opts.name: what it's called in the tooltip ("the Flow button").
-- opts.save: table (or function returning it) where .point and .scale go.
-- opts.also: function returning frames that resize along with it.
-- opts.onDone: called after each move or resize.
local handles = {}
function ns:MoveHandle(target, opts)
    local h = CreateFrame("Frame", nil, UIParent)
    h.target, h.opts = target, opts
    h:SetFrameStrata("DIALOG")
    h:EnableMouse(true)
    h:EnableMouseWheel(true)
    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    h.edge = {}
    local o = ns.theme.arrow
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                           { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = h:CreateTexture(nil, "BORDER")
        t:SetPoint(pts[1]); t:SetPoint(pts[2])
        if i <= 2 then t:SetHeight(2) else t:SetWidth(2) end
        h.edge[i] = t
    end
    -- The label sits ABOVE the button (under it is the button's own text,
    -- which it would cover), on a small dark tab so it reads.
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.text:SetPoint("BOTTOM", h, "TOP", 0, 4)
    h.tab = h:CreateTexture(nil, "BACKGROUND")
    h.tab:SetPoint("TOPLEFT", h.text, "TOPLEFT", -4, 2)
    h.tab:SetPoint("BOTTOMRIGHT", h.text, "BOTTOMRIGHT", 4, -2)
    h.tab:SetColorTexture(0, 0, 0, 0.6)

    -- Hover: it lights up, so it's clear you can grab it.
    function h:Paint(hot)
        self.bg:SetColorTexture(o[1], o[2], o[3], hot and 0.35 or 0.12)
        for _, t in ipairs(self.edge) do t:SetColorTexture(o[1], o[2], o[3], hot and 1 or 0.7) end
        self.text:SetTextColor(hot and 1 or o[1], hot and 1 or o[2], hot and 1 or o[3])
    end
    function h:Label()
        self.text:SetText(string.format("drag to move · wheel to resize (%d%%)", math.floor(target:GetScale() * 100 + 0.5)))
    end
    -- Show while Ctrl is held (out of combat, button on screen).
    function h:Refresh()
        local want = ns.MoveKeyDown() and not InCombatLockdown() and target:IsShown()
        if want then
            self:ClearAllPoints()
            self:SetAllPoints(target)
            self:Label()
            self:Show()
        elseif not self.moving then
            self:Hide()
        end
    end
    -- Remember the spot by the button's centre on the screen, so it no
    -- longer depends on whatever it was first attached to.
    function h:Save()
        local x, y = target:GetCenter()
        if not x then return end
        target:ClearAllPoints()
        target:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        local save = type(opts.save) == "function" and opts.save() or opts.save
        save.point = { "CENTER", "BOTTOMLEFT", x, y }
        save.scale = target:GetScale()
        if opts.onDone then opts.onDone() end
    end
    -- A drag still going when a fight starts is finished at the start of the
    -- fight (still allowed then); a release during the fight does nothing.
    function h:Finish()
        if not self.moving or InCombatLockdown() then return end
        self.moving = false
        target:StopMovingOrSizing()
        self:Save()
    end
    -- One wheel notch with Ctrl held: a tenth bigger or smaller.
    function h:Resize(delta)
        if ns.MoveKeyDown() then self:ScaleBy(delta) end
    end
    -- Resize keeping the centre still on the screen.
    function h:ScaleBy(delta)
        if InCombatLockdown() then return end
        local old = target:GetScale()
        local new = ns.ClampScale(old + (delta > 0 and ns.SCALE_STEP or -ns.SCALE_STEP))
        if new == old then return end
        local x, y = target:GetCenter()
        target:SetScale(new)
        for _, f in ipairs(opts.also and opts.also() or {}) do f:SetScale(new) end
        if x then
            target:ClearAllPoints()
            target:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * old / new, y * old / new)
        end
        self:Save()
        self:Label()
    end

    h:Paint(false)
    h:SetScript("OnEnter", function(self)
        self:Paint(true)
        pcall(SetCursor, "UI_MOVE_CURSOR")
        ns.Tip(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Move or resize " .. (opts.name or "this button"), 1, 1, 1)
        GameTooltip:AddLine("Ctrl: drag to move, mouse wheel to resize.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Let go of the key to use it again.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function(self)
        self:Paint(false)
        pcall(ResetCursor)
        GameTooltip:Hide()
    end)
    h:SetScript("OnMouseDown", function(self)
        if InCombatLockdown() or not ns.MoveKeyDown() then return end
        target:StartMoving()
        self.moving = true
    end)
    h:SetScript("OnMouseUp", function(self) self:Finish() end)
    h:SetScript("OnMouseWheel", function(self, delta) self:Resize(delta) end)
    h:Hide()
    target:SetMovable(true)
    target:SetClampedToScreen(true)
    handles[#handles + 1] = h
    return h
end

-- Put a button back where and at the size you left it (x0, y0: the default
-- spot from the screen centre).
function ns.RestorePlace(frame, save, x0, y0)
    frame:SetScale(ns.ClampScale(save.scale or 1))
    local p = save.point
    frame:ClearAllPoints()
    if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else frame:SetPoint("CENTER", UIParent, "CENTER", x0 or 0, y0 or 0) end
end

ns:On("MODIFIER_STATE_CHANGED", function()
    for _, h in ipairs(handles) do h:Refresh() end
end)
ns:On("PLAYER_REGEN_DISABLED", function()
    for _, h in ipairs(handles) do h:Finish(); h.moving = false; h:Hide() end
end)

