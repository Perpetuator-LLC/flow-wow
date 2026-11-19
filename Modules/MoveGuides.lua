-- Alignment lines while you move Flow's buttons.
--
-- "When the user is moving the easy buttons around, can we show alignment
-- highlights like the WoW UI does? Centre to vertical, centre to horizontal,
-- and if we set it on top it kind of magnets to the bottom of it, or centre
-- to centre, the same with left to right. Just something so it's easy to
-- align and check if they're close to aligned." (0.35.327)
--
-- While you drag the target button, the self button or the zone note (Ctrl +
-- drag), Flow compares its left edge, middle and right edge, and its top,
-- middle and bottom, with:
--   * the middle of the screen, both ways;
--   * the edges and middles of Flow's other movable things on screen (the
--     other button, the arrow).
-- When one of them is within a few pixels of one of those, a line is drawn
-- there. Let go while a line shows and the button settles exactly on it: its
-- middle on the screen's middle, its top on the other button's bottom, its
-- left edge level with the other's, and so on.
-- (A frame the game is dragging can't be nudged while it moves, so the snap
-- happens at the release; the line is the promise.)
-- Off: Flow Settings, On your screen.

local _, ns = ...
local G = {}
ns.guides = G

G.SNAP = 8          -- pixels (at the screen's own scale): closer than this lines up
G.THICK = 2

function G.On() return not (ns.db and ns.db.settings and ns.db.settings.moveGuides == false) end

-- Pure: a rectangle's three places along each way.
--   r: { l, r, b, t } -> xs { l, c, r }, ys { b, c, t }
function G.Marks(r)
    return { r.l, (r.l + r.r) / 2, r.r }, { r.b, (r.b + r.t) / 2, r.t }
end

-- Pure: the nearest line-up one way. mine: the moving thing's three places;
-- theirs: every place it could line up with. -> how far to move (nil: none
-- within `snap`), and the place it lines up on.
function G.Nearest(mine, theirs, snap)
    local best, bestAt
    for _, m in ipairs(mine or {}) do
        for _, at in ipairs(theirs or {}) do
            local d = at - m
            if math.abs(d) <= (snap or G.SNAP) and (not best or math.abs(d) < math.abs(best)) then best, bestAt = d, at end
        end
    end
    return best, bestAt
end

-- Pure: where a rectangle would settle. rect: the moving thing; screen:
-- { w, h }; others: rectangles to line up with.
--   -> { dx, dy (how far it moves; 0 when nothing's near), x (the upright
--        line's place, or nil), y (the level line's place, or nil) }
function G.Snap(rect, screen, others, snap)
    local xs, ys = { screen.w / 2 }, { screen.h / 2 }
    for _, o in ipairs(others or {}) do
        local ox, oy = G.Marks(o)
        for _, v in ipairs(ox) do xs[#xs + 1] = v end
        for _, v in ipairs(oy) do ys[#ys + 1] = v end
    end
    local mx, my = G.Marks(rect)
    local dx, x = G.Nearest(mx, xs, snap)
    local dy, y = G.Nearest(my, ys, snap)
    return { dx = dx or 0, dy = dy or 0, x = x, y = y }
end

-------------------------------------------------------------------------------
-- On screen
-------------------------------------------------------------------------------
-- A frame's rectangle in the screen's own units (UIParent's), whatever its scale.
function G.RectOf(frame)
    if not (frame and frame.GetLeft and frame:IsShown()) then return nil end
    local l, r, b, t = frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop()
    if not (l and r and b and t) then return nil end
    local s = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return { l = l * s, r = r * s, b = b * s, t = t * s }
end

-- Flow's other movable things to line up with.
G.FRAMES = { "FlowCastButton", "FlowBuffButton", "FlowNavArrow" }
function G.Others(target)
    local out = {}
    for _, name in ipairs(G.FRAMES) do
        local f = _G[name]
        if f and f ~= target then
            local r = G.RectOf(f)
            if r then out[#out + 1] = r end
        end
    end
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
    host.v = host:CreateTexture(nil, "OVERLAY")
    host.v:SetColorTexture(c[1], c[2], c[3], 0.9)
    host.v:SetWidth(G.THICK)
    host.h = host:CreateTexture(nil, "OVERLAY")
    host.h:SetColorTexture(c[1], c[2], c[3], 0.9)
    host.h:SetHeight(G.THICK)
    host:Hide()
    host:SetScript("OnUpdate", function(self)
        -- (A fight began mid-drag: the release won't move anything, so no promise.)
        if not self.target or InCombatLockdown() then self.target = nil; self:Hide() return end
        local ok, s = pcall(G.Now, self.target)
        G.Draw(ok and s or nil)
    end)
    return host
end

-- Draws (or hides) the two lines for a line-up.
function G.Draw(s)
    if not host then return end
    host.v:ClearAllPoints()
    host.h:ClearAllPoints()
    if s and s.x then
        host.v:SetPoint("TOP", UIParent, "TOPLEFT", s.x, 0)
        host.v:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", s.x, 0)
    end
    if s and s.y then
        host.h:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, s.y)
        host.h:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, s.y)
    end
    host.v:SetShown(s ~= nil and s.x ~= nil)
    host.h:SetShown(s ~= nil and s.y ~= nil)
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
    return s.dx, s.dy
end
G._Host = function() return host end   -- (tests)

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "screen",
        label = "Alignment lines while you move Flow's buttons",
        note = "(Ctrl + drag)",
        tip = "While you drag the target button or the self button, a line shows when its edge or middle is level with the middle of the screen, "
            .. "or with the edge or middle of Flow's other button or the arrow. Let go while a line shows and it settles exactly on it.",
        get = function() return G.On() end,
        set = function(on)
            ns.db.settings = ns.db.settings or {}
            ns.db.settings.moveGuides = on and true or false
        end,
    })
end
