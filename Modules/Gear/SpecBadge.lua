-- The spec badge: one small icon per spec (Retribution / Holy / Protection,
-- role-coloured rim) with a mark right above each:
--   green arrow up   better than what that spec wears
--   red arrow down   worse
--   grey dash        about the same
-- Your levelling spec is brighter. Used wherever Flow marks an item: bag
-- slots, quest reward choices, the vendor drawer...
--
--   local b = ns:SpecBadge(parent, size)      -- size: icon size in pixels (default 10)
--   b:SetPoint(...)
--   b:Set(diffs)                               -- { dps = n, heal = n, tank = n } (Flow score vs worn)
--   b:Hide()

local _, ns = ...

local ROLES = { "dps", "heal", "tank" }
local RIM = { dps = { 1, 0.25, 0.25 }, heal = { 0.25, 0.9, 0.25 }, tank = { 0.25, 0.55, 1 } }
local THRESHOLD = 0.5   -- same "counts as better" step as the gear tooltip

-- "up", "down" or "same" for a score difference.
function ns.SpecTrend(diff)
    if not diff then return nil end
    if diff >= THRESHOLD then return "up" end
    if diff <= -THRESHOLD then return "down" end
    return "same"
end

-- One look everywhere: the game's own green bag arrow (the "equip this"
-- arrow on bag slots) pointing up = better; the same arrow turned over and
-- red = worse; a short grey dash = about the same. Clients without that
-- arrow art fall back to a drawn chevron in the same colours.
local UP, DOWN, SAME = { 0.3, 1, 0.3 }, { 1, 0.3, 0.3 }, { 0.7, 0.7, 0.7 }

local function arrow(slot, size)
    local a = CreateFrame("Frame", nil, slot)
    local h = math.max(6, math.floor(size * 0.8))
    a:SetSize(size, h)
    a:SetPoint("BOTTOM", slot, "TOP", 0, 1)
    a.tex = a:CreateTexture(nil, "OVERLAY")
    a.tex:SetSize(h + 2, h + 2)
    a.tex:SetPoint("CENTER")
    a.atlas = a.tex.SetAtlas and pcall(a.tex.SetAtlas, a.tex, "bags-greenarrow")
        and (not a.tex.GetAtlas or a.tex:GetAtlas() ~= nil) or false
    a.l1 = a:CreateLine(nil, "OVERLAY"); a.l1:SetThickness(2)
    a.l2 = a:CreateLine(nil, "OVERLAY"); a.l2:SetThickness(2)
    a.bar = a:CreateTexture(nil, "OVERLAY")
    a.bar:SetSize(math.max(4, size - 4), 2)
    a.bar:SetPoint("CENTER")
    a.bar:SetColorTexture(SAME[1], SAME[2], SAME[3], 0.9)
    function a:Show3(trend)
        local same = trend == "same"
        self.bar:SetShown(same)
        local up = trend == "up"
        local c = up and UP or DOWN
        if self.atlas then
            self.l1:Hide(); self.l2:Hide()
            self.tex:SetShown(not same)
            if same then return end
            -- Green as drawn for up; for down, greyed then tinted red and turned over.
            self.tex:SetDesaturated(not up)
            if up then self.tex:SetVertexColor(1, 1, 1, 1) else self.tex:SetVertexColor(c[1], c[2], c[3], 1) end
            if self.tex.SetRotation then self.tex:SetRotation(up and 0 or math.pi) end
            return
        end
        self.tex:Hide()
        self.l1:SetShown(not same); self.l2:SetShown(not same)
        if same then return end
        local w, hh = self:GetWidth(), self:GetHeight()
        local tipY, baseY = up and hh or 0, up and 0 or hh
        self.l1:SetStartPoint("BOTTOMLEFT", self, 1, baseY); self.l1:SetEndPoint("BOTTOMLEFT", self, w / 2, tipY)
        self.l2:SetStartPoint("BOTTOMLEFT", self, w - 1, baseY); self.l2:SetEndPoint("BOTTOMLEFT", self, w / 2, tipY)
        self.l1:SetColorTexture(c[1], c[2], c[3], 1); self.l2:SetColorTexture(c[1], c[2], c[3], 1)
    end
    return a
end

local Badge = {}

function Badge:Set(diffs)
    local main = ns:LevelingRole()
    local any = false
    for _, role in ipairs(ROLES) do
        local s = self.slots[role]
        local trend = ns.SpecTrend(diffs and diffs[role])
        s:SetShown(trend ~= nil)
        if trend then
            any = true
            s.arrow:Show3(trend)
            s:SetAlpha(role == main and 1 or 0.7)
        end
    end
    self:SetShown(any)
end

function ns:SpecBadge(parent, size)
    size = size or 10
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(3 * size + 4, size + math.max(6, math.floor(size * 0.8)) + 1)
    f:SetFrameLevel(parent:GetFrameLevel() + 6)
    f.slots = {}
    for i, role in ipairs(ROLES) do
        local s = CreateFrame("Frame", nil, f)
        s:SetSize(size, size)
        s:SetPoint("BOTTOMLEFT", (i - 1) * (size + 2), 0)
        s.rim = s:CreateTexture(nil, "BACKGROUND")
        s.rim:SetAllPoints()
        s.rim:SetColorTexture(RIM[role][1], RIM[role][2], RIM[role][3], 1)
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetPoint("TOPLEFT", 1, -1)
        s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        local path = ns:RoleIconPath(role)
        if path then s.icon:SetTexture(path); s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else s.icon:Hide() end
        s.arrow = arrow(s, size)
        s:Hide()
        f.slots[role] = s
    end
    for k, v in pairs(Badge) do f[k] = v end
    f:Hide()
    return f
end
