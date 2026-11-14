-- Flow Auctions: post what Flow marks for the auction house, a click an item.
--
-- "Can we get it to auto-post my AH items? If they don't sell after some
-- time, where the fees are going to cost us more than just vendoring, it
-- handles that too and switches it to a vendor item with a note." (0.35.214)
--
-- The game wants a click of yours for every auction (its posting calls only
-- work from a key or mouse press), so it can't be fully automatic. What Flow
-- does: at the auction house a small window lists the items Flow marks
-- "auction house" (Disposition.lua: a price Flow has seen that beats the
-- vendor), each with the price it would ask and the deposit. "Post" on a
-- row, or "Post next" at the bottom, puts that one up: every one of that
-- item in your bags, at one silver under the cheapest buyout Flow last saw
-- (the game takes whole silver only), for the time you pick.
--
-- Giving up: Flow counts the deposits each item has cost you. A deposit is
-- lost when an auction runs out unsold ("Your auction of X has expired").
-- Once the deposits lost on an item reach what the auction house would have
-- earned over the vendor, Flow stops marking it for the auction house: it
-- becomes "sell", with the reason "didn't sell at auction N times (deposits
-- ...)". A sale ("A buyer has been found...") wipes the count.
--
-- Nothing is posted without your click. /flow auctions lists it all.

local _, ns = ...
local A = ns.api
local P = {}
ns.posting = P

P.UNDERCUT = 100            -- one silver under the cheapest seen
P.MIN = 100                 -- the game takes whole silver: nothing under one
P.CUT = 0.05                -- the house's cut of a sale
P.ROWS = 10
P.DURATIONS = { { 1, "12 h" }, { 2, "24 h" }, { 3, "48 h" } }

ns:OnLoad(function(saved)
    saved.ah = saved.ah or {}
    saved.ah.posts = saved.ah.posts or {}
end)
local function posts() return ns.db.ah.posts end
local CA = C_AuctionHouse

-- Pure: the price each to ask, in whole silver: `undercut` under what Flow
-- last saw, never under one silver. nil: no price seen, or it's worth under
-- a silver each (the game won't take copper prices).
function P.Price(seen, undercut, min)
    seen = tonumber(seen)
    min = min or P.MIN
    if not seen or seen < min then return nil end
    local ask = math.floor((seen - (undercut or P.UNDERCUT)) / 100) * 100
    if ask < min then ask = math.floor(seen / 100) * 100 end
    return math.max(min, ask)
end

-- Pure: keep posting, or give up? each: the price asked; vendor: the
-- vendor's price each; count: how many; lost: deposits lost on unsold
-- auctions of this item so far; deposit: the next one.
--   -> "post" or "vendor", and the gain over vendoring that's still there.
function P.Verdict(each, vendor, count, lost, deposit, cut)
    local gain = ((each or 0) * (1 - (cut or P.CUT)) - (vendor or 0)) * (count or 1)
    local left = gain - (lost or 0) - (deposit or 0)
    if left <= 0 then return "vendor", left end
    return "post", left
end

-- Pure: the game's "sold" or "expired" line -> "sold" | "expired", item name.
-- soldFmt / expiredFmt: the game's own texts with %s for the item.
function P.Parse(msg, soldFmt, expiredFmt)
    if type(msg) ~= "string" then return nil end
    local function try(fmt)
        if type(fmt) ~= "string" then return nil end
        local pat = "^" .. fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"
        return msg:match(pat)
    end
    local name = try(soldFmt)
    if name then return "sold", name end
    name = try(expiredFmt)
    if name then return "expired", name end
    return nil
end

-- Has Flow given up on this item at the auction house? -> true, why.
function P.GaveUp(id)
    local rec = id and ns.db and ns.db.ah and ns.db.ah.posts and ns.db.ah.posts[id]
    if not (rec and rec.gaveUp) then return false end
    local money = ns.auction and ns.auction.Money or tostring
    return true, string.format("didn't sell at auction %d time(s) (deposits %s)", rec.expired or 0, money(rec.lost or 0))
end

-- Pure: one more outcome on an item's record. gain: what the auction house
-- would have earned over the vendor for that auction (nil: unknown).
function P.Note(rec, what, deposit, gain)
    rec = rec or {}
    if what == "posted" then
        rec.posted = (rec.posted or 0) + 1
        rec.lastDeposit = deposit or 0
        rec.lastGain = gain
    elseif what == "expired" then
        rec.expired = (rec.expired or 0) + 1
        rec.lost = (rec.lost or 0) + (rec.lastDeposit or 0)
        if rec.lastGain and rec.lost >= rec.lastGain then rec.gaveUp = true end
    elseif what == "sold" then
        rec.expired, rec.lost, rec.gaveUp = 0, 0, nil
    end
    return rec
end

-------------------------------------------------------------------------------
-- What to post right now
-------------------------------------------------------------------------------
function P.Duration()
    local d = tonumber(ns.db.ah.duration)
    return (d == 1 or d == 3) and d or 2
end

-- Rows: { id, name, count, each (the price asked), seen, vendor }.
function P.List()
    local D = ns.disposition
    if not (D and D.Inventory) then return {} end
    local ok, rows = pcall(D.Inventory, D)
    if not ok or type(rows) ~= "table" then return {} end
    local out = {}
    for _, r in ipairs(rows) do
        local each = (r.action == "ah") and P.Price(r.ah) or nil
        if each and r.id and not r.bound then
            out[#out + 1] = { id = r.id, name = r.name, count = r.count or 1, each = each, seen = r.ah, vendor = r.sell or 0 }
        end
    end
    table.sort(out, function(a, b) return a.each * a.count > b.each * b.count end)
    return out
end

local function locate(id)
    local found
    ns.disposition:EachBagItem(function(bag, slot, link)
        if not found and tonumber(link:match("item:(%d+)")) == id then found = { bag, slot } end
    end)
    if not (found and ItemLocation and ItemLocation.CreateFromBagAndSlot) then return nil end
    return ItemLocation:CreateFromBagAndSlot(found[1], found[2])
end

local open = false
function P.AtHouse() return open end

-- The deposit for a row (nil: the game won't say yet).
function P.Deposit(row, loc, commodity)
    if not CA then return nil end
    local ok, d
    if commodity and CA.CalculateCommodityDeposit then ok, d = pcall(CA.CalculateCommodityDeposit, row.id, P.Duration(), row.count)
    elseif loc and CA.CalculateItemDeposit then ok, d = pcall(CA.CalculateItemDeposit, loc, P.Duration(), row.count) end
    return ok and tonumber(d) or nil
end

-- Posts one row. Only from your click, at an open auction house.
-- -> true, or false and why.
function P:Post(row)
    if not open then return false, "open the auction house first" end
    if not (CA and CA.PostItem and CA.GetItemCommodityStatus) then return false, "this client has no posting calls" end
    local loc = locate(row.id)
    if not loc then return false, "it isn't in your bags any more" end
    if CA.IsSellItemValid then
        local okV, valid = pcall(CA.IsSellItemValid, loc, false)
        if okV and valid == false then return false, "the auction house won't take it" end
    end
    local okS, status = pcall(CA.GetItemCommodityStatus, loc)
    status = okS and tonumber(status) or 0
    if status == 0 then return false, "the game is still loading it: click again in a moment" end
    local commodity = status == 2
    local deposit = P.Deposit(row, loc, commodity)
    local ok, needs
    if commodity then ok, needs = pcall(CA.PostCommodity, loc, P.Duration(), row.count, row.each)
    else ok, needs = pcall(CA.PostItem, loc, P.Duration(), row.count, nil, row.each) end
    if not ok then
        ns:Log("ah", "post failed: " .. tostring(row.name) .. ": " .. tostring(needs))
        return false, "the game refused: " .. tostring(needs)
    end
    if needs then   -- (the game wants it confirmed: its price is far from the others')
        local confirm = commodity and CA.ConfirmPostCommodity or CA.ConfirmPostItem
        if confirm then
            if commodity then pcall(confirm, loc, P.Duration(), row.count, row.each)
            else pcall(confirm, loc, P.Duration(), row.count, nil, row.each) end
        end
    end
    local gain = (row.each * (1 - P.CUT) - (row.vendor or 0)) * row.count
    posts()[row.id] = P.Note(posts()[row.id], "posted", deposit, gain)
    posts()[row.id].name = row.name
    ns:Log("ah", string.format("posted %d x %s at %d each (%s, deposit %s, duration %d)", row.count, tostring(row.name), row.each,
        commodity and "commodity" or "item", tostring(deposit), P.Duration()))
    return true
end

-- "A buyer has been found for your auction of X" / "Your auction of X has expired".
ns:On("CHAT_MSG_SYSTEM", function(msg)
    msg = A.Safe(msg)
    local what, name = P.Parse(msg, _G.ERR_AUCTION_SOLD_S, _G.ERR_AUCTION_EXPIRED_S)
    if not what then return end
    for id, rec in pairs(posts()) do
        if rec.name == name then
            posts()[id] = P.Note(rec, what)
            ns:Log("ah", string.format("%s: %s (expired %d, deposits lost %d%s)", name, what, rec.expired or 0, rec.lost or 0, rec.gaveUp and ", given up: vendor" or ""))
            if rec.gaveUp then
                ns:Print(string.format("%s didn't sell at auction (%d time(s)): the deposits now cost more than it would earn over a vendor. Flow marks it to sell to a vendor.", name, rec.expired or 0))
                if ns.disposition and ns.disposition.Invalidate then ns.disposition:Invalidate() end
            end
        end
    end
end)

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
local frame
local function money(c) return ns.auction and ns.auction.Money and ns.auction.Money(c) or tostring(c) end

local function build()
    local f = CreateFrame("Frame", "FlowAuctions", UIParent)
    f:SetSize(380, 96 + P.ROWS * 20)
    f:SetFrameStrata("DIALOG")
    local p = ns.db.ah.postPoint
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("LEFT", UIParent, "LEFT", 40, -120) end
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
    f.head = ns.theme:TitleBar(f, "Flow Auctions", "Interface\\Icons\\INV_Misc_Coin_01")
    f:EnableMouse(true)
    ns:MakeMovable(f, setmetatable({}, { __newindex = function(_, key, v)
        if key == "point" then ns.db.ah.postPoint = v end end }), true)
    tinsert(UISpecialFrames, "FlowAuctions")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)   -- (our own: the game's handler can't close an add-on window in a fight)
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.note:SetPoint("TOPLEFT", 10, -28)
    f.note:SetPoint("TOPRIGHT", -10, -28)
    f.note:SetJustifyH("LEFT")
    f.rows = {}
    for i = 1, P.ROWS do
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(360, 20)
        r:SetPoint("TOPLEFT", 10, -48 - (i - 1) * 20)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT")
        r.text:SetWidth(290)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r.post = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.post:SetSize(60, 18)
        r.post:SetPoint("RIGHT")
        r.post:SetText("Post")
        r.post:SetScript("OnClick", function() P:Click(r.row) end)
        f.rows[i] = r
    end
    -- How long: 12, 24 or 48 hours.
    f.durations = {}
    for i, d in ipairs(P.DURATIONS) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(46, 20)
        b:SetPoint("BOTTOMLEFT", 10 + (i - 1) * 50, 10)
        b:SetText(d[2])
        b:SetScript("OnClick", function() ns.db.ah.duration = d[1]; P:Fill() end)
        f.durations[i] = b
    end
    f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.next:SetSize(110, 22)
    f.next:SetPoint("BOTTOMRIGHT", -10, 9)
    f.next:SetText("Post next")
    f.next:SetScript("OnClick", function()
        local list = P.List()
        P:Click(list[1])
    end)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 10, 36)
    f.status:SetPoint("BOTTOMRIGHT", -10, 36)
    f.status:SetJustifyH("LEFT")
    f:Hide()
    return f
end

function P:Fill()
    local f = frame
    if not f then return end
    local list = P.List()
    f.note:SetText(#list == 0 and "Nothing in your bags that Flow would put on the auction house (it needs a price it has seen that beats the vendor)."
        or string.format("%d thing(s) for the auction house, a silver under the cheapest Flow last saw. One click each:", #list))
    for i = 1, P.ROWS do
        local r, row = f.rows[i], list[i]
        r.row = row
        if row then
            local rec = posts()[row.id]
            r.text:SetText(string.format("%d x %s  |cffffd100%s|r each%s", row.count, tostring(row.name), money(row.each),
                (rec and (rec.expired or 0) > 0) and string.format("  |cffff9933(unsold %dx)|r", rec.expired) or ""))
            r.post:SetEnabled(open)
            r:Show()
        else
            r:Hide()
        end
    end
    for i, d in ipairs(P.DURATIONS) do
        if d[1] == P.Duration() then f.durations[i]:LockHighlight() else f.durations[i]:UnlockHighlight() end
    end
    f.next:SetEnabled(open and #list > 0)
    f.next:SetText(open and "Post next" or "At an auction house")
end

-- A click on "Post" (or "Post next").
function P:Click(row)
    if not row then return false end
    local ok, why = P:Post(row)
    if frame then
        frame.status:SetText(ok and string.format("|cff66ff66Posted %d x %s at %s each.|r", row.count, tostring(row.name), money(row.each))
            or ("|cffff7070" .. tostring(row.name) .. ": " .. tostring(why) .. "|r"))
    end
    if ok and C_Timer then C_Timer.After(1, function() if frame and frame:IsShown() then P:Fill() end end) end
    return ok, why
end

function P:Open()
    frame = frame or build()
    P:Fill()
    frame:Show()
end
function P:Toggle()
    if frame and frame:IsShown() then frame:Hide() else P:Open() end
end
function P._Frame() return frame end

ns:On("AUCTION_HOUSE_SHOW", function()
    open = true
    if ns.db.ah.postOff then return end
    -- (Once the bag lookups have had a moment: the prices decide what's listed.)
    if C_Timer then C_Timer.After(3, function()
        if open and #P.List() > 0 then P:Open() end
    end) end
end)
ns:On("AUCTION_HOUSE_CLOSED", function()
    open = false
    if frame and frame:IsShown() then frame:Hide() end
end)

ns:Register("gameButton", "auctionhouse", {
    order = 60,
    frames = { "AuctionHouseFrame", "AuctionFrame" },
    label = "Flow Auctions",
    tip = "What in your bags Flow would put on the auction house, with the price it would ask: one click posts each.",
    isOpen = function() return frame ~= nil and frame:IsShown() end,
    click = function() P:Toggle() end,
})

-------------------------------------------------------------------------------
-- /flow auctions
-------------------------------------------------------------------------------
function P.Lines()
    local list = P.List()
    local out = { string.format("Flow Auctions: %d thing(s) to post%s; posting calls: %s", #list, ns.db.ah.postOff and " (window off)" or "",
        (CA and CA.PostItem and CA.PostCommodity) and "there" or "missing") }
    for _, r in ipairs(list) do
        out[#out + 1] = string.format("  %d x %s [%d]: ask %s each (seen %s, vendor %s)", r.count, tostring(r.name), r.id, money(r.each), money(r.seen), money(r.vendor))
    end
    for id, rec in pairs(posts()) do
        out[#out + 1] = string.format("  record %s [%d]: posted %d, unsold %d, deposits lost %s%s", tostring(rec.name), id, rec.posted or 0, rec.expired or 0,
            money(rec.lost or 0), rec.gaveUp and "; given up: to a vendor" or "")
    end
    return out
end
ns.commands.auctions = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then ns.db.ah.postOff = (arg == "off") or nil; ns:Print("Flow Auctions window " .. arg) return end
    if arg == "show" then P:Open() return end
    if arg == "forget" then ns.db.ah.posts = {}; ns:Print("Flow Auctions: forgot what didn't sell") return end
    for i, l in ipairs(P.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
    print("  /flow auctions show   /flow auctions on|off   /flow auctions forget (what didn't sell)")
end
ns:Register("help", "auctions", { order = 57, title = "Flow Auctions", lines = {
    "At the auction house, a window lists what Flow would post, with its price: one click posts each (the game needs your click).",
    "An item that keeps coming back unsold until the deposits outweigh the gain becomes a vendor item. /flow auctions.",
} })
