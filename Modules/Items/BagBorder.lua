-------------------------------------------------------------------------------
-- Flow - Items/BagBorder.lua
-- A clear border round every item in your bags, in its quality's colour
-- (0.35.429).
--
-- "Can we make the border on each of the items in my bags a little more
-- prominent so I can clearly see white for normal items, gray for poor
-- quality, green for uncommon, blue for rare, purple for epic, in a very
-- clear, prominent border?"
--
-- The game draws a thin glow for green and better, and nothing for white or
-- grey. Flow draws a solid edge of its own on every item: BB.THICK pixels of
-- the quality's colour, with a dark line inside it so the colour reads
-- against any icon. Drawn by BagIcons.lua's painter, under Flow's marks.
-- Flow Settings, Loot and selling; /flow bagborders on|off.
-------------------------------------------------------------------------------

local _, ns = ...
local BB = {}
ns.bagBorder = BB

BB.THICK = 2
-- Poor, common, uncommon, rare, epic, legendary, artifact, heirloom.
BB.COLORS = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}

function BB.On() return not (ns.db and ns.db.bags and ns.db.bags.borders == false) end

-- Pure: a quality's colour (r, g, b), or nil for one Flow doesn't know.
function BB.Color(quality)
    local c = type(quality) == "number" and BB.COLORS[quality] or nil
    if not c then return nil end
    return c[1], c[2], c[3]
end

local SOLID = "Interface\\Buttons\\WHITE8X8"
local function build(button)
    local f = CreateFrame("Frame", nil, button)
    f:SetAllPoints()
    f:SetFrameLevel(button:GetFrameLevel() + 4)   -- (under Flow's marks, over the icon)
    f.edges, f.lines = {}, {}
    local function strip(list, inset, size, layer)
        local function one(p1, p2, horizontal)
            local t = f:CreateTexture(nil, "OVERLAY", nil, layer)
            t:SetTexture(SOLID)
            local sx = (p1:find("LEFT") and inset or -inset)
            local sy = (p1:find("TOP") and -inset or inset)
            t:SetPoint(p1, f, p1, sx, sy)
            local ex = (p2:find("LEFT") and inset or -inset)
            local ey = (p2:find("TOP") and -inset or inset)
            t:SetPoint(p2, f, p2, ex, ey)
            if horizontal then t:SetHeight(size) else t:SetWidth(size) end
            list[#list + 1] = t
        end
        one("TOPLEFT", "TOPRIGHT", true)
        one("BOTTOMLEFT", "BOTTOMRIGHT", true)
        one("TOPLEFT", "BOTTOMLEFT", false)
        one("TOPRIGHT", "BOTTOMRIGHT", false)
    end
    strip(f.edges, 0, BB.THICK, 2)        -- the colour
    strip(f.lines, BB.THICK, 1, 1)        -- a dark line inside it
    for _, t in ipairs(f.lines) do t:SetVertexColor(0, 0, 0, 0.75) end
    button.flowBorder = f
    return f
end

function BB.Clear(button)
    if button and button.flowBorder then button.flowBorder:Hide() end
end

-- The border for a quality (nil: none).
function BB.Paint(button, quality)
    local r, g, b = BB.Color(quality)
    if not (r and BB.On()) then BB.Clear(button) return false end
    local f = button.flowBorder or build(button)
    for _, t in ipairs(f.edges) do t:SetVertexColor(r, g, b, 1) end
    f:Show()
    return true
end

-- The border for the item in a slot, by its link (nil: an empty slot).
function BB.PaintLink(button, link)
    if not link then BB.Clear(button) return false end
    local quality
    if C_Item and C_Item.GetItemQualityByID then
        local ok, q = pcall(C_Item.GetItemQualityByID, link)
        if ok then quality = ns.api.Safe(q) end
    end
    if quality == nil then
        local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if get then
            local ok, _, _, q = pcall(get, link)
            if ok then quality = ns.api.Safe(q) end
        end
    end
    return BB.Paint(button, quality)
end

ns.commands.bagborders = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.bags = ns.db.bags or {}
        ns.db.bags.borders = (arg == "on")
        if ns.bagIcons and ns.bagIcons.MarkDirty then ns.bagIcons.MarkDirty() end
    end
    ns:Print("quality borders on your bag items: " .. (BB.On() and "on" or "off") .. " (/flow bagborders on|off)")
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "loot",
        label = "A clear quality border on every bag item",
        note = "(grey, white, green, blue, purple)",
        tip = "A solid edge round each item in your bags in its quality's colour: grey for poor, white for common, green, blue, purple and up. "
            .. "The game only draws a thin glow, and none for white or grey.",
        get = function() return BB.On() end,
        set = function(on)
            ns.db.bags = ns.db.bags or {}
            ns.db.bags.borders = on and true or false
            if ns.bagIcons and ns.bagIcons.MarkDirty then ns.bagIcons.MarkDirty() end
        end,
    })
end
