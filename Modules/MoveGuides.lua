-- Alignment lines while you move Flow's buttons.
--
-- "When the user is moving the easy buttons around, can we show alignment
-- highlights like the WoW UI does? Centre to vertical, centre to horizontal,
-- and if we set it on top it kind of magnets to the bottom of it, or centre
-- to centre, the same with left to right. Just something so it's easy to
-- align and check if they're close to aligned." (0.35.327)
--
-- While you drag the target button or the self button (Ctrl + drag), Flow
-- compares its left edge, middle and right edge, and its top, middle and
-- bottom, with:
--   * the middle of the screen, both ways (a line right across the screen);
--   * Flow's other button, when it's on screen and isn't docked to the one
--     you're dragging: its edges and its middle;
--   * the middle of Flow's arrow, when it's on screen.
-- When one is within a few pixels, a line is drawn there. Let go while a
-- line shows and the button settles exactly on it.
--
-- 0.35.330, "they're all out of whack; I don't see what it's aligning to;
-- maybe it should align to things that are visual, only currently
-- displayed": with the two buttons docked, the one you drag was compared
-- with its own docked partner, which moves with it and so always "lined up"
-- (a line through the pair wherever it was, and a snap toward nothing); and
-- with the edges of the arrow's frame, a box you can't see. Now only what's
-- on screen and stays put is used, a line to another thing runs just from
-- the button to that thing (so you see what it lines up with), and that
-- thing is outlined while the line shows.
-- (A frame the game is dragging can't be nudged while it moves, so the snap
-- happens at the release; the line is the promise.)
-- Off: Flow Settings, On your screen.

local _, ns = ...
local G = {}
ns.guides = G

G.SNAP = 8          -- pixels (at the screen's own scale): closer than this lines up
G.THICK = 2
G.REACH = 14        -- how far a line to another thing runs past the two

function G.On() return not (ns.db and ns.db.settings and ns.db.settings.moveGuides == false) end

-- Pure: a rectangle's three places along each way.
--   r: { l, r, b, t } -> xs { l, c, r }, ys { b, c, t }
function G.Marks(r)
    return { r.l, (r.l + r.r) / 2, r.r }, { r.b, (r.b + r.t) / 2, r.t }
end

-- Pure: the nearest line-up one way. mine: the moving thing's three places;
-- theirs: every place it could line up with (a number, or { v = number, src
-- = what it belongs to }). -> how far to move (nil: none within `snap`), the
-- place it lines up on, and what that place belongs to (nil: the screen).
function G.Nearest(mine, theirs, snap)
    local best, bestAt, bestSrc
    for _, m in ipairs(mine or {}) do
        for _, at in ipairs(theirs or {}) do
            local v = type(at) == "table" and at.v or at
            local d = v - m
            if math.abs(d) <= (snap or G.SNAP) and (not best or math.abs(d) < math.abs(best)) then
                best, bestAt, bestSrc = d, v, type(at) == "table" and at.src or nil
            end
        end
    end
    return best, bestAt, bestSrc
end

-- Pure: where a rectangle would settle. rect: the moving thing; screen:
-- { w, h }; others: rectangles to line up with ({ l, r, b, t }; one with
-- `middle = true` offers only its middle: the arrow).
--   -> { dx, dy (how far it moves; 0 when nothing's near), x, y (the upright
--        and the level line's place, or nil), xSrc, ySrc (the rectangle each
--        lines up with; nil: the middle of the screen), rect }
function G.Snap(rect, screen, others, snap)
    local xs, ys = { screen.w / 2 }, { screen.h / 2 }
    for _, o in ipairs(others or {}) do
        local ox, oy = G.Marks(o)
        for i = 1, 3 do
            if not o.middle or i == 2 then
                xs[#xs + 1] = { v = ox[i], src = o }
                ys[#ys + 1] = { v = oy[i], src = o }
            end
        end
    end
    local mx, my = G.Marks(rect)
    local dx, x, xSrc = G.Nearest(mx, xs, snap)
    local dy, y, ySrc = G.Nearest(my, ys, snap)
    return { dx = dx or 0, dy = dy or 0, x = x, y = y, xSrc = xSrc, ySrc = ySrc, rect = rect }
end

-- Pure: how far a line to another thing runs: from the nearer end of the two
-- to the further, and a little past. lo1, hi1: the moving thing; lo2, hi2: the other.
function G.Span(lo1, hi1, lo2, hi2, reach)
    return math.min(lo1, lo2) - (reach or G.REACH), math.max(hi1, hi2) + (reach or G.REACH)
end

-- Pure: which of Flow's two buttons the one you drag may line up with: the
-- other one, unless they're docked (then it moves with the one you drag).
--   dragging: "FlowCastButton" | "FlowBuffButton" | other; docked: bool
function G.Partner(dragging, docked)
    if docked then return nil end
    if dragging == "FlowCastButton" then return "FlowBuffButton" end
    if dragging == "FlowBuffButton" then return "FlowCastButton" end
    return nil
end

-------------------------------------------------------------------------------
-- On screen
-------------------------------------------------------------------------------
-- A frame's rectangle in the screen's own units (UIParent's), whatever its
-- scale. nil unless it's really on screen (shown, and its parents too).
function G.RectOf(frame)
    if not (frame and frame.GetLeft and frame:IsVisible()) then return nil end
    local l, r, b, t = frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop()
    if not (l and r and b and t) then return nil end
    local s = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return { l = l * s, r = r * s, b = b * s, t = t * s }
end

-- What the frame you drag may line up with, besides the middle of the screen.
function G.Others(target)
    local out = {}
    local BB = ns.buffButton
    local docked = BB and BB.Docked and BB.Docked() and true or false
    local partner = G.Partner(target and target.GetName and target:GetName() or nil, docked)
    local r = partner and G.RectOf(_G[partner]) or nil
    if r then r.name = partner; out[#out + 1] = r end
    -- The arrow: its middle only (its frame is a box you can't see).
    local arrow = _G.FlowNavArrow
    local a = arrow and arrow ~= target and G.RectOf(arrow) or nil
    if a then a.middle, a.name = true, "FlowNavArrow"; out[#out + 1] = a end
    return out
end

function G.Now(target)
    local rect = G.RectOf(target)
    if not rect then return nil end
    return G.Snap(rect, { w = UIParent:GetWidth() or 0, h = UIParent:GetHeight() or 0 }, G.Others(target))
end

local host
local function build()
    host = CreateFrame("Frame", "FlowMoveGuides", UIParent)
    host:SetAllPoints(UIParent)
    host:SetFrameStrata("TOOLTIP")
    local c = ns.theme and ns.theme.arrow or { 1, 0.6, 0.1 }
    local function line()
        local t = host:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(c[1], c[2], c[3], 0.9)
        t:Hide()
        return t
    end
    host.v, host.h = line(), line()
    host.v:SetWidth(G.THICK)
    host.h:SetHeight(G.THICK)
    -- The outline round what a line lines up with: four thin edges, twice.
    host.box = { {}, {} }
    for _, edges in ipairs(host.box) do
        for i = 1, 4 do edges[i] = line(); edges[i]:SetColorTexture(1, 1, 1, 0.8) end
    end
    host:Hide()
    host:SetScript("OnUpdate", function(self)
        -- (A fight began mid-drag: the release won't move anything, so no promise.)
        if not self.target or InCombatLockdown() then self.target = nil; self:Hide() return end
        local ok, s = pcall(G.Now, self.target)
        G.Draw(ok and s or nil)
    end)
    return host
end

local function outline(edges, r)
    for _, e in ipairs(edges) do e:ClearAllPoints(); e:SetShown(r ~= nil) end
    if not r then return end
    local function at(e, x0, y0, x1, y1)
        e:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x0, y0)
        e:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x1, y1)
    end
    at(edges[1], r.l - 1, r.t, r.r + 1, r.t + 1)
    at(edges[2], r.l - 1, r.b - 1, r.r + 1, r.b)
    at(edges[3], r.l - 1, r.b, r.l, r.t)
    at(edges[4], r.r, r.b, r.r + 1, r.t)
end

-- Draws (or hides) the two lines for a line-up, and what each lines up with.
function G.Draw(s)
    if not host then return end
    host.v:ClearAllPoints()
    host.h:ClearAllPoints()
    local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    if s and s.x then
        -- The middle of the screen: right across. Another thing: from the
        -- button to it.
        local y0, y1 = 0, sh
        if s.xSrc and s.rect then y0, y1 = G.Span(s.rect.b, s.rect.t, s.xSrc.b, s.xSrc.t) end
        host.v:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", s.x, y0)
        host.v:SetPoint("TOP", UIParent, "BOTTOMLEFT", s.x, y1)
    end
    if s and s.y then
        local x0, x1 = 0, sw
        if s.ySrc and s.rect then x0, x1 = G.Span(s.rect.l, s.rect.r, s.ySrc.l, s.ySrc.r) end
        host.h:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x0, s.y)
        host.h:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", x1, s.y)
    end
    host.v:SetShown(s ~= nil and s.x ~= nil)
    host.h:SetShown(s ~= nil and s.y ~= nil)
    local a = s and s.x and s.xSrc and not s.xSrc.middle and s.xSrc or nil
    local b = s and s.y and s.ySrc and not s.ySrc.middle and s.ySrc or nil
    if b == a then b = nil end
    outline(host.box[1], a)
    outline(host.box[2], b)
end

-- A drag begins: the lines watch this frame.
function G.Start(target)
    if not G.On() then return false end
    host = host or build()
    host.target = target
    host:Show()
    return true
end

-- The drag ends: the frame settles on the lines that show. Out of a fight
-- only (the caller checks). -> dx, dy it moved (screen units)
function G.Drop(target)
    local was = host and host.target
    if host then host.target = nil; host:Hide() end
    if not (was and was == target and G.On()) then return 0, 0 end
    local ok, s = pcall(G.Now, target)
    if not ok or not s or (s.dx == 0 and s.dy == 0) then return 0, 0 end
    local x, y = target:GetCenter()
    if not x then return 0, 0 end
    -- (The frame's own units: its scale may differ from the screen's.)
    local k = (UIParent:GetEffectiveScale() or 1) / (target:GetEffectiveScale() or 1)
    target:ClearAllPoints()
    target:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + s.dx * k, y + s.dy * k)
    G.last = string.format("%s settled by %.1f, %.1f (%s; %s)", tostring(target.GetName and target:GetName() or "?"), s.dx, s.dy,
        s.x and (s.xSrc and tostring(s.xSrc.name) or "the screen's middle") or "no upright line",
        s.y and (s.ySrc and tostring(s.ySrc.name) or "the screen's middle") or "no level line")
    if ns.Log then ns:Log("move", G.last) end
    return s.dx, s.dy
end
G._Host = function() return host end   -- (tests)

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "screen",
        label = "Alignment lines while you move Flow's buttons",
        note = "(Ctrl + drag)",
        tip = "While you drag the target button or the self button, a line shows when its edge or middle is level with the middle of the screen, "
            .. "with Flow's other button (when they aren't docked) or with the middle of the arrow. Let go while a line shows and it settles exactly on it.",
        get = function() return G.On() end,
        set = function(on)
            ns.db.settings = ns.db.settings or {}
            ns.db.settings.moveGuides = on and true or false
        end,
    })
end
