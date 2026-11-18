-- Flow Prices: an item's auction price over time, as a chart.
--
-- "Can I have a way to click on an item and see its price over history like
-- commodities or stocks in a chart, time vs price and properly time scaled
-- for each scan?" (0.35.301)
--
-- Every time Flow reads the auction house it notes the cheapest buyout (each)
-- of what it saw (Auction.lua keeps up to AH.HIST_MAX points an item, one a
-- visit; the oldest are thinned, not dropped). This window draws them:
--   * across: time, to scale. Two scans an hour apart sit close together, a
--     week without a scan is a long flat stretch, so the slope is honest.
--   * up: the price each, with a little room above and below.
--   * a dot per scan: hover it for the price and when.
--   * above: the price now, the lowest, highest and average Flow has seen,
--     and how it moved from the first look to the last.
-- Open it with Alt + click on an item (bags, a chat link, the auction house),
-- a click on a line of Flow Banker's "Auction prices", or /flow price <item>.
-- It shows what Flow saw on this realm and faction, nothing else: an item
-- nobody listed while you were there has no point for that visit.

local _, ns = ...
local PC = {}
ns.priceChart = PC

PC.W, PC.H = 440, 250            -- the window
PC.PLOT = { left = 62, right = 14, top = 74, bottom = 30 }
PC.PAD = 0.12                    -- room above the highest and under the lowest, as a share of the spread
PC.TICKS = 4                     -- time labels under the chart

-- Pure: an item's points, oldest first. e: its entry in the price store
-- ({ h = { at, price, at, price, ... } }, or the older { looks = { { price, at } } }, newest first).
function PC.Points(e)
    local out = {}
    if type(e) ~= "table" then return out end
    if type(e.h) == "table" and #e.h >= 2 then
        for i = 1, #e.h - 1, 2 do
            if tonumber(e.h[i]) and tonumber(e.h[i + 1]) then out[#out + 1] = { at = e.h[i], price = e.h[i + 1] } end
        end
    elseif type(e.looks) == "table" then
        for i = #e.looks, 1, -1 do
            local l = e.looks[i]
            if type(l) == "table" and tonumber(l.at) and tonumber(l.price) then out[#out + 1] = { at = l.at, price = l.price } end
        end
    elseif tonumber(e.price) and tonumber(e.at) then
        out[1] = { at = e.at, price = e.price }
    end
    table.sort(out, function(a, b) return a.at < b.at end)
    return out
end

-- Pure: first and last time, lowest and highest price. nil for no points.
function PC.Range(points)
    if not points or #points == 0 then return nil end
    local t0, t1, lo, hi = points[1].at, points[1].at, points[1].price, points[1].price
    for _, p in ipairs(points) do
        t0, t1 = math.min(t0, p.at), math.max(t1, p.at)
        lo, hi = math.min(lo, p.price), math.max(hi, p.price)
    end
    return t0, t1, lo, hi
end

-- Pure: the price at the bottom and at the top of the chart: the spread with
-- room around it (a flat price gets a tenth of itself each way), never under 0.
function PC.Axis(lo, hi, pad)
    local room = hi > lo and (hi - lo) * (pad or PC.PAD) or math.max(1, hi * 0.1)
    return math.max(0, lo - room), hi + room
end

-- Pure: where each point goes in a plot of w by h (x from the left, y from
-- the bottom). Time is to scale; one point alone sits in the middle.
function PC.Place(points, w, h, pad)
    local out = {}
    local t0, t1, lo, hi = PC.Range(points)
    if not t0 then return out end
    local bottom, top = PC.Axis(lo, hi, pad)
    for i, p in ipairs(points) do
        local x = (t1 > t0) and (p.at - t0) / (t1 - t0) * w or w / 2
        local y = (top > bottom) and (p.price - bottom) / (top - bottom) * h or h / 2
        out[i] = { x = x, y = y, at = p.at, price = p.price }
    end
    return out
end

-- Pure: now, lowest, highest, average, and the change from the first to the
-- last look as a share (0.25 = up a quarter; nil with one look).
function PC.Stats(points)
    if not points or #points == 0 then return nil end
    local _, _, lo, hi = PC.Range(points)
    local sum = 0
    for _, p in ipairs(points) do sum = sum + p.price end
    local first, last = points[1].price, points[#points].price
    return { now = last, low = lo, high = hi, avg = sum / #points, looks = #points,
             change = (#points > 1 and first > 0) and (last - first) / first or nil }
end

-- Pure: "up 25%", "down 8%", "unchanged".
function PC.ChangeText(change)
    if not change then return nil end
    local pct = math.floor(math.abs(change) * 100 + 0.5)
    if pct == 0 then return "unchanged" end
    return string.format("%s %d%%", change > 0 and "up" or "down", pct)
end

-- Pure: how long a stretch is, in words.
function PC.Span(seconds)
    seconds = math.max(0, seconds or 0)
    if seconds < 3600 then return string.format("%d min", math.floor(seconds / 60)) end
    if seconds < 2 * 86400 then return string.format("%d h", math.floor(seconds / 3600)) end
    return string.format("%d days", math.floor(seconds / 86400))
end

-- Pure: the times to label under the chart: `n` of them, evenly spread from
-- the first look to the last, each with where it sits (0..1). One look: one label.
function PC.Ticks(t0, t1, n)
    if not t0 then return {} end
    if t1 <= t0 then return { { at = t0, share = 0.5 } } end
    local out = {}
    for i = 0, n - 1 do
        local share = i / (n - 1)
        out[#out + 1] = { at = t0 + (t1 - t0) * share, share = share }
    end
    return out
end

-- A time as the label under the chart: the hour when the whole chart is
-- within two days, the day otherwise.
function PC.Stamp(at, span)
    if (span or 0) < 2 * 86400 then return date("%d %b %H:%M", at) end
    return date("%d %b", at)
end

local function money(c) return ns.Money(c) end
local function nameOf(id)
    local name = (ns.api and ns.api.ItemInfo or GetItemInfo)(id)
    return name or ("item " .. tostring(id))
end

-- The words above the chart. -> title line, stats line (or a line saying why there's no chart).
function PC.Words(id, points, now)
    local s = PC.Stats(points)
    if not s then
        return nameOf(id), "No auction price yet. Flow notes one each time you open the auction house and this item is listed."
    end
    local t0, t1 = PC.Range(points)
    local head = string.format("%s: |cffffd100%s|r each, %s ago", nameOf(id), money(s.now), PC.Span((now or time()) - t1))
    if s.looks == 1 then
        return head, "One look so far. The chart grows a point each time Flow reads the auction house."
    end
    local change = PC.ChangeText(s.change)
    return head, string.format("Low %s, high %s, average %s. %d looks over %s%s.", money(s.low), money(s.high), money(s.avg),
        s.looks, PC.Span(t1 - t0), change and (": " .. change) or "")
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
local function cfg()
    ns.db.ah = ns.db.ah or {}
    return ns.db.ah
end

local function build()
    local f = CreateFrame("Frame", "FlowPrices", UIParent)
    f:SetSize(PC.W, PC.H)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
    f.head = ns.theme:TitleBar(f, "Flow Prices", "Interface\\Icons\\INV_Misc_Coin_01")
    f:EnableMouse(true)
    local p = cfg().chartPoint
    if p then f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    ns:MakeMovable(f, setmetatable({}, { __newindex = function(_, key, v)
        if key == "point" then cfg().chartPoint = v end end }), true)
    tinsert(UISpecialFrames, "FlowPrices")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)   -- (our own: the game's handler can't close an add-on window in a fight)
    f.close = close
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOPLEFT", 10, -32); f.title:SetPoint("TOPRIGHT", -10, -32)
    f.title:SetJustifyH("LEFT"); f.title:SetWordWrap(false)
    f.stats = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.stats:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4); f.stats:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -4)
    f.stats:SetJustifyH("LEFT"); f.stats:SetTextColor(0.75, 0.75, 0.75)
    -- The plot: where the lines and dots live.
    local P = PC.PLOT
    f.plot = CreateFrame("Frame", nil, f)
    f.plot:SetPoint("TOPLEFT", P.left, -P.top)
    f.plot:SetPoint("BOTTOMRIGHT", -P.right, P.bottom)
    f.plot.bg = f.plot:CreateTexture(nil, "BACKGROUND")
    f.plot.bg:SetAllPoints()
    f.plot.bg:SetColorTexture(0, 0, 0, 0.35)
    f.lines, f.dots, f.grid, f.priceLabels, f.timeLabels = {}, {}, {}, {}, {}
    return f
end

local function line(f, i)
    local l = f.lines[i]
    if not l then
        l = f.plot:CreateLine(nil, "ARTWORK")
        l:SetThickness(2)
        f.lines[i] = l
    end
    return l
end
local function dot(f, i)
    local d = f.dots[i]
    if not d then
        d = CreateFrame("Frame", nil, f.plot)
        d:SetSize(9, 9)
        d.tex = d:CreateTexture(nil, "OVERLAY")
        d.tex:SetPoint("CENTER"); d.tex:SetSize(5, 5)
        d:EnableMouse(true)
        d:SetScript("OnEnter", function(self)
            if not self.at then return end
            self.tex:SetSize(8, 8)
            ns.Tip(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(money(self.price) .. " each", 1, 0.82, 0)
            GameTooltip:AddLine(date("%d %b %Y, %H:%M", self.at), 1, 1, 1)
            GameTooltip:AddLine(PC.Span(time() - self.at) .. " ago", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        d:SetScript("OnLeave", function(self) self.tex:SetSize(5, 5); GameTooltip:Hide() end)
        f.dots[i] = d
    end
    return d
end
local function label(list, f, i)
    local t = list[i]
    if not t then
        t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetTextColor(0.6, 0.6, 0.6)
        list[i] = t
    end
    return t
end

-- Draws item `id` (or what it showed last).
function PC:Fill()
    local f = PC.frame
    if not f then return end
    local id = PC.item
    local AH = ns.auction
    local e
    if AH and AH.Prices and id then
        local ok, prices = pcall(AH.Prices, AH)
        e = ok and type(prices) == "table" and prices[id] or nil
    end
    local points = PC.Points(e)
    local title, stats = PC.Words(id, points, time())
    f.title:SetText(title)
    f.stats:SetText(stats)
    local w, h = f.plot:GetWidth(), f.plot:GetHeight()
    if not w or w <= 0 then w, h = PC.W - PC.PLOT.left - PC.PLOT.right, PC.H - PC.PLOT.top - PC.PLOT.bottom end
    local placed = PC.Place(points, w, h)
    local c = ns.theme.arrow or { 1, 0.6, 0.1 }
    for i = 1, math.max(#f.lines, #placed - 1) do
        local a, b = placed[i], placed[i + 1]
        if a and b then
            local l = line(f, i)
            l:SetColorTexture(c[1], c[2], c[3], 0.95)
            l:SetStartPoint("BOTTOMLEFT", f.plot, a.x, a.y)
            l:SetEndPoint("BOTTOMLEFT", f.plot, b.x, b.y)
            l:Show()
        elseif f.lines[i] then
            f.lines[i]:Hide()
        end
    end
    for i = 1, math.max(#f.dots, #placed) do
        local p = placed[i]
        if p then
            local d = dot(f, i)
            d:ClearAllPoints()
            d:SetPoint("CENTER", f.plot, "BOTTOMLEFT", p.x, p.y)
            d.tex:SetColorTexture(1, 0.9, 0.5, 1)
            d.at, d.price = p.at, p.price
            d:Show()
        elseif f.dots[i] then
            f.dots[i]:Hide()
        end
    end
    -- Price lines across (bottom, middle, top of the axis) with their prices,
    -- and the times underneath.
    local t0, t1, lo, hi = PC.Range(points)
    local bottom, top = 0, 0
    if t0 then bottom, top = PC.Axis(lo, hi) end
    for i = 1, 3 do
        local share = (i - 1) / 2
        local g = f.grid[i]
        if not g then
            g = f.plot:CreateTexture(nil, "BORDER")
            g:SetColorTexture(1, 1, 1, 0.08)
            g:SetHeight(1)
            f.grid[i] = g
        end
        g:ClearAllPoints()
        g:SetPoint("BOTTOMLEFT", f.plot, "BOTTOMLEFT", 0, h * share)
        g:SetPoint("BOTTOMRIGHT", f.plot, "BOTTOMRIGHT", 0, h * share)
        g:SetShown(t0 ~= nil)
        local t = label(f.priceLabels, f, i)
        t:ClearAllPoints()
        t:SetPoint("RIGHT", f.plot, "BOTTOMLEFT", -5, h * share)
        t:SetText(t0 and money(math.floor(bottom + (top - bottom) * share + 0.5)) or "")
    end
    local ticks = PC.Ticks(t0, t1, PC.TICKS)
    for i = 1, math.max(#f.timeLabels, #ticks) do
        local tk = ticks[i]
        local t = (tk or f.timeLabels[i]) and label(f.timeLabels, f, i)
        if t then
            t:ClearAllPoints()
            if tk then
                local anchor = tk.share <= 0 and "TOPLEFT" or (tk.share >= 1 and "TOPRIGHT" or "TOP")
                t:SetPoint(anchor, f.plot, "BOTTOMLEFT", w * tk.share, -5)
                t:SetText(PC.Stamp(tk.at, t1 - t0))
            else
                t:SetText("")
            end
        end
    end
end

function PC:Show(id)
    if not id then return false end
    PC.item = id
    PC.frame = PC.frame or build()
    PC.frame:Show()
    PC:Fill()
    return true
end
function PC._Frame() return PC.frame end

-- Alt + click on an item opens its chart (bags, chat links, the auction
-- house: whatever hands the game a modified click on an item).
function PC.ClickOn() return cfg().chartClick ~= false end
-- Pure: is this the click that opens the chart? Alt alone, on an item link.
function PC.IsChartClick(link, alt, ctrl, shift, on)
    if not on or not alt or ctrl or shift then return nil end
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end
if hooksecurefunc and type(HandleModifiedItemClick) == "function" then
    hooksecurefunc("HandleModifiedItemClick", function(link)
        local ok, id = pcall(PC.IsChartClick, link, IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown(), PC.ClickOn())
        if ok and id then pcall(PC.Show, PC, id) end
    end)
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "loot",
        label = "Alt + click an item: its auction price chart",
        note = "(Flow Prices)",
        tip = "Alt + click on an item in your bags, in chat or at the auction house opens Flow Prices: the cheapest buyout Flow saw "
            .. "at each visit to the auction house, drawn over time. Also a click on a line of Flow Banker's Auction prices, and /flow price <item>.",
        get = function() return PC.ClickOn() end,
        set = function(on) cfg().chartClick = on and true or false end,
    })
end

ns.commands.price = function(arg)
    local AH = ns.auction
    local id = AH and AH.ItemId and AH.ItemId(arg or "")
    if not id then
        ns:Print("/flow price <item>: shift-click the item into the chat line, or type its name once you've seen it. Or Alt + click an item.")
        return
    end
    PC:Show(id)
end

ns:Register("help", "prices", { order = 57.5, title = "Flow Prices", lines = {
    "An item's auction price over time, as a chart: the cheapest buyout (each) Flow saw at each visit to the auction house.",
    "Open it: Alt + click an item (bags, chat, auction house), click a line in Flow Banker's Auction prices, or /flow price <item>.",
    "Time runs to scale: scans close together sit close together. Hover a dot for its price and when.",
    "It only knows what Flow saw on this realm and faction while you had the auction house open.",
} })
