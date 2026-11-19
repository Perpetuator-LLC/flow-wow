-- Moving and resizing Flow's secure buttons (the Flow key): a handle that
-- appears over the button while you hold Ctrl (ns.MoveKeyDown, Core.lua), out
-- of combat. Drag it to move the button, turn the mouse wheel to resize it.
-- (Kept out of Core.lua: the core holds registries and the event bus; this
-- is UI, and the Flow key is its only user so far. Loaded after Theme.lua.)

local _, ns = ...

-- Sizes a button can take with Ctrl + mouse wheel: half to double size, in
-- steps of a tenth. ClampScale rounds to the nearest 5 % and keeps it in range.
ns.SCALE_MIN, ns.SCALE_MAX, ns.SCALE_STEP = 0.5, 2, 0.1
-- The "drag to move" note: this far under the button (clear of the line of
-- text the button has under it), and this faint.
ns.MOVE_NOTE_DROP, ns.MOVE_NOTE_ALPHA = 20, 0.6
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
-- opts.off: function, true while something else moves this button (the buff
--   button docked under Flow's icon): then it has no handle of its own.
-- opts.fixed: function, true while the button can't be dragged (docked: it
--   goes where Flow's icon goes) but can still be resized with the wheel.
-- opts.wheel: function(delta) that does the resize itself and returns true
--   (docked: the size is kept apart and the button is put back in its dock).
-- opts.quiet: function, true to leave this handle's own note out (docked:
--   the one note under both buttons is Flow's).
-- opts.noteUnder: function returning the frame the note goes under (the
--   docked self button: one note, under both), or nil for the button itself.
-- opts.dragVia: function returning another handle that a drag on this one
--   moves instead (the docked self button: dragging it moves Flow's button,
--   and so the pair, 0.35.315), or nil.
-- Pure: does a handle show?
function ns.HandleWanted(keyDown, inCombat, shown, off)
    return (keyDown and not inCombat and shown and not off) and true or false
end
local handles = {}
-- What happened this session, for the diagnostics (0.35.315: "I'm no longer
-- able to use Ctrl to move the easy button or the buff button"): Ctrl
-- changes the game told Flow about, the ones only Flow's own look caught,
-- handles shown, drags begun and finished, and what lay under the mouse
-- when Ctrl went down over a button.
local stats = { events = 0, polled = 0, shown = 0, drags = 0, saved = 0, errors = 0 }
ns.moveStats = stats
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
    -- The note sits BELOW the button and its own line of text, small and
    -- faint (0.35.194). It used to sit above, bright, on a dark tab: Ctrl is
    -- also a cast modifier, so every Ctrl + key flashed it over the key's
    -- bind and the modifier names.
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h.text:SetPoint("TOP", h, "BOTTOM", 0, -(ns.MOVE_NOTE_DROP))
    h.text:SetAlpha(ns.MOVE_NOTE_ALPHA)
    h.tab = h:CreateTexture(nil, "BACKGROUND")
    h.tab:SetPoint("TOPLEFT", h.text, "TOPLEFT", -4, 2)
    h.tab:SetPoint("BOTTOMRIGHT", h.text, "BOTTOMRIGHT", 4, -2)
    h.tab:SetColorTexture(0, 0, 0, 0.3)

    -- Hover: it lights up, so it's clear you can grab it.
    function h:Paint(hot)
        self.bg:SetColorTexture(o[1], o[2], o[3], hot and 0.35 or 0.12)
        for _, t in ipairs(self.edge) do t:SetColorTexture(o[1], o[2], o[3], hot and 1 or 0.7) end
        -- (Faint until the mouse is over the handle: then it's what you're doing.)
        self.text:SetTextColor(hot and 1 or 0.7, hot and 1 or 0.7, hot and 1 or 0.7)
        self.text:SetAlpha(hot and 1 or ns.MOVE_NOTE_ALPHA)
    end
    function h:Label()
        self.text:SetText(string.format("drag to move · wheel to resize (%d%%)", math.floor(target:GetScale() * 100 + 0.5)))
    end
    -- Show while Ctrl is held (out of combat, button on screen).
    function h:Refresh()
        local want = ns.HandleWanted(ns.MoveKeyDown(), InCombatLockdown(), target:IsShown(), opts.off and opts.off())
        if want then
            self:ClearAllPoints()
            self:SetAllPoints(target)
            local under = opts.noteUnder and opts.noteUnder() or self
            self.noteUnder = under
            self.text:ClearAllPoints()
            self.text:SetPoint("TOP", under, "BOTTOM", 0, -(ns.MOVE_NOTE_DROP))
            local quiet = (opts.quiet and opts.quiet()) and true or false
            self.text:SetShown(not quiet)
            self.tab:SetShown(not quiet)
            self:Label()
            if not self:IsShown() then stats.shown = stats.shown + 1; stats.lastShown = (opts.name or "?") .. " at " .. date("%H:%M:%S") end
            self:Show()
        elseif not (self.moving or self.via) then   -- (mid-drag it stays, so the release lands on it)
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
        save.scale = ns.ClampScale(target:GetScale())   -- the game keeps 1.1 as 1.1000000238
        if opts.onDone then opts.onDone() end
    end
    -- A drag still going when a fight starts is finished at the start of the
    -- fight (still allowed then); a release during the fight does nothing.
    function h:Finish()
        if not self.moving or InCombatLockdown() then return end
        self.moving = false
        target:StopMovingOrSizing()
        -- (Alignment lines, MoveGuides.lua: it settles on the line that shows.)
        if ns.guides then pcall(ns.guides.Drop, target) end
        self:Save()
        stats.saved = stats.saved + 1
        stats.lastSaved = (opts.name or "?") .. " at " .. date("%H:%M:%S")
    end
    -- A drag begins (Ctrl held, out of combat). true when it did.
    function h:BeginDrag()
        if InCombatLockdown() or not ns.MoveKeyDown() then return false end
        target:StartMoving()
        self.moving = true
        if ns.guides then pcall(ns.guides.Start, target) end
        stats.drags = stats.drags + 1
        stats.lastDrag = (opts.name or "?") .. " at " .. date("%H:%M:%S")
        return true
    end
    -- One wheel notch with Ctrl held: a tenth bigger or smaller.
    function h:Resize(delta)
        if ns.MoveKeyDown() then self:ScaleBy(delta) end
    end
    -- Resize keeping the centre still on the screen.
    function h:ScaleBy(delta)
        if InCombatLockdown() then return end
        if opts.wheel and opts.wheel(delta) then self:Label() return end
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
        -- Docked: a drag on the self button moves Flow's button, which it hangs from.
        local via = opts.dragVia and opts.dragVia()
        if via and via ~= self then
            if via:BeginDrag() then self.via = via end
            return
        end
        if opts.fixed and opts.fixed() then return end
        self:BeginDrag()
    end)
    h:SetScript("OnMouseUp", function(self)
        local via = self.via
        if via then self.via = nil; via:Finish() return end
        self:Finish()
    end)
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

-- Each handle on its own: one that fails can't keep the others from showing.
local function refreshAll()
    for _, h in ipairs(handles) do
        local ok, err = pcall(h.Refresh, h)
        if not ok then
            stats.errors = stats.errors + 1
            stats.lastError = (h.opts and h.opts.name or "?") .. ": " .. tostring(err)
        end
    end
end

-- Pure: the name of what takes the mouse (the first of the game's list, or
-- the one), for the diagnostics.
function ns.MouseFocusName(foci, focus)
    local f = (type(foci) == "table" and foci[1]) or focus
    if not f then return "nothing" end
    local ok, name = pcall(function() return f.GetName and f:GetName() end)
    local Safe = ns.api and ns.api.Safe or function() return nil end
    name = ok and Safe(name) or nil
    if type(name) == "string" then return name end
    local okP, pn = pcall(function() local p = f:GetParent(); return p and p:GetName() end)
    pn = okP and Safe(pn) or nil
    return type(pn) == "string" and ("a child of " .. pn) or "an unnamed frame"
end
-- Ctrl just went down: over one of the buttons, what's under the mouse?
-- (The handle, when all is well.)
local function noteFocus()
    for _, h in ipairs(handles) do
        local t = h.target
        local okO, over = pcall(t.IsMouseOver, t)
        if okO and over and t:IsVisible() and h.opts and h.opts.name ~= "test" then
            local foci = GetMouseFoci and GetMouseFoci() or nil
            local focus = (not foci) and GetMouseFocus and GetMouseFocus() or nil
            stats.focus = string.format("Ctrl down over %s at %s: under the mouse %s (its handle %s)", h.opts.name, date("%H:%M:%S"),
                ns.MouseFocusName(foci, focus), h:IsShown() and "showing" or "not showing")
            return
        end
    end
end

local ctrlWas = false
local function ctrlChanged()
    local down = ns.MoveKeyDown()
    if down == ctrlWas then return false end
    ctrlWas = down
    refreshAll()
    if down then pcall(noteFocus) end
    return true
end
ns:On("MODIFIER_STATE_CHANGED", function()
    stats.events = stats.events + 1
    ctrlChanged()
end)
-- Flow looks for itself too, ten times a second: the handles show even when
-- the game doesn't say a key changed (0.35.315).
do
    local poll, acc = CreateFrame("Frame"), 0
    poll:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        if ctrlChanged() then stats.polled = stats.polled + 1 end
    end)
end
ns:On("PLAYER_REGEN_DISABLED", function()
    for _, h in ipairs(handles) do h:Finish(); h.moving = false; h.via = nil; h:Hide() end
end)

-- The diagnostics' "moving buttons" lines.
function ns.MoveLines()
    local out = { string.format("moving buttons (Ctrl): Ctrl now %s; changes the game told Flow about %d, only Flow's own look caught %d; "
        .. "handles shown %d, drags %d, saved %d; errors %d", ns.MoveKeyDown() and "down" or "up", stats.events, stats.polled,
        stats.shown, stats.drags, stats.saved, stats.errors) }
    for _, h in ipairs(handles) do
        local name = h.opts and h.opts.name or "?"
        if name ~= "test" then
            local t = h.target
            out[#out + 1] = string.format("  %s: on screen %s, handle %s, can't be dragged itself %s, drags move %s",
                name, tostring(t:IsVisible()), h:IsShown() and "showing" or "hidden",
                tostring((h.opts.fixed and h.opts.fixed()) and true or false),
                (h.opts.dragVia and h.opts.dragVia()) and "Flow's button (docked)" or "itself")
        end
    end
    for _, k in ipairs({ "lastShown", "lastDrag", "lastSaved", "focus", "lastError" }) do
        if stats[k] then out[#out + 1] = "  " .. k .. ": " .. tostring(stats[k]) end
    end
    return out
end

