-- Auction house prices and a watch list.
--   * Open an auction house and Flow looks up the cheapest buyout (per item)
--     of what matters to you: things in your bags it says to sell there, and
--     your watch list, one search every moment or so. Anything you browse
--     yourself is recorded too.
--   * Prices are kept per realm and faction (the last few looks, with when),
--     shown on item tooltips ("Auction house: 1g 20s each, 3 h ago"), and
--     used by the Flow Seller to choose auction house or vendor.
--   * Watch list: /flow ah watch <item> [price in gold]. When you open an
--     auction house and it's listed at or under your price, Flow says so
--     (with a sound). /flow ah unwatch <item>, /flow ah (list), /flow ah scan.
-- Works with the classic auction house (QueryAuctionItems); on a client with
-- the newer one Flow says so once (logged for the diagnostics).

local _, ns = ...
local AH = {}
ns.auction = AH

local KEEP = 8            -- looks kept per item
local queue, pending = {}, nil
local open = false

local function store()
    local realm = (GetRealmName and GetRealmName() or "?") .. "-" .. (UnitFactionGroup and UnitFactionGroup("player") or "?")
    ns.db.ah.prices[realm] = ns.db.ah.prices[realm] or {}
    return ns.db.ah.prices[realm]
end

-- Copper -> "1g 20s 5c".
function AH.Money(c)
    c = math.floor(tonumber(c) or 0)
    local g, s, cc = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "g" end
    if s > 0 then out[#out + 1] = s .. "s" end
    if cc > 0 or #out == 0 then out[#out + 1] = cc .. "c" end
    return table.concat(out, " ")
end

-- "1.5" or "1g50s" or "75s" -> copper (nil if it isn't a price).
function AH.ParseMoney(text)
    text = (text or ""):lower():gsub("%s", "")
    if text == "" then return nil end
    local n = tonumber(text)
    if n then return math.floor(n * 10000 + 0.5) end
    local total, any = 0, false
    for num, unit in text:gmatch("([%d%.]+)([gsc])") do
        any = true
        total = total + tonumber(num) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    end
    return any and math.floor(total + 0.5) or nil
end

-- Remember a look: cheapest per-unit buyout now. history = { { price, at } }.
function AH.Record(prices, id, unit, now)
    local e = prices[id] or { looks = {} }
    prices[id] = e
    table.insert(e.looks, 1, { price = math.floor(unit), at = now })
    for i = #e.looks, KEEP + 1, -1 do e.looks[i] = nil end
    e.price, e.at = math.floor(unit), now
    return e
end

function AH:Price(id)
    local e = id and store()[id]
    return e and e.price, e and e.at
end

-- How many items Flow has a price for, on this realm and faction.
function AH:Known()
    local n = 0
    for _ in pairs(store()) do n = n + 1 end
    return n
end

-------------------------------------------------------------------------------
-- Watch list
-------------------------------------------------------------------------------

local function itemId(text)
    local id = tonumber((text or ""):match("item:(%d+)")) or tonumber(text)
    if id then return id end
    local _, link = (ns.api.ItemInfo or GetItemInfo)(text or "")
    return link and tonumber(link:match("item:(%d+)"))
end

local function alertIfCheap(id, unit)
    local w = ns.db.ah.watch[id]
    if not (w and w.max and unit <= w.max) then return end
    ns:Print(string.format("|cff40ff40watch: %s is on the auction house for %s each|r (your price: %s)",
        w.name or ("item " .. id), AH.Money(unit), AH.Money(w.max)))
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
end

-------------------------------------------------------------------------------
-- Reading the auction house (classic API)
-------------------------------------------------------------------------------

local function classic() return QueryAuctionItems and GetAuctionItemInfo and GetNumAuctionItems end

-- Every result on the page: cheapest per unit by item, recorded.
local function readPage()
    local best = {}
    for i = 1, (GetNumAuctionItems("list") or 0) do
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = GetAuctionItemInfo("list", i)
        if id and buyout and buyout > 0 and count and count > 0 then
            local unit = buyout / count
            if not best[id] or unit < best[id] then best[id] = unit end
        end
    end
    local prices, now = store(), time()
    for id, unit in pairs(best) do
        AH.Record(prices, id, unit, now)
        alertIfCheap(id, unit)
    end
    -- New prices can change "auction it" vs "sell it" (Flow Seller, bag icons).
    if next(best) and ns.disposition and ns.disposition.Invalidate then ns.disposition:Invalidate() end
    return best
end

local function step()
    if not open or #queue == 0 then pending = nil return end
    if CanSendAuctionQuery and not CanSendAuctionQuery() then C_Timer.After(0.5, step) return end
    pending = table.remove(queue, 1)
    local ok = pcall(QueryAuctionItems, pending.name, nil, nil, 0, false, nil, false, true)
    if not ok then pending = nil; C_Timer.After(1, step) end
end

-- What to look up: bag items Flow says to auction, and the watch list.
function AH:Wanted()
    local out, seen = {}, {}
    local D = ns.disposition
    if D and D.EachBagItem then
        D:EachBagItem(function(bag, slot, link)
            local ok, v = pcall(D.Decide, D, bag, slot, link)
            local id = tonumber(link:match("item:(%d+)"))
            if ok and v and (v.action == "ah" or v.ahCandidate) and id and not seen[id] then
                seen[id] = true
                out[#out + 1] = { id = id, name = link:match("%[(.-)%]") }
            end
        end)
    end
    for id, w in pairs(ns.db.ah.watch) do
        if not seen[id] and w.name then seen[id] = true; out[#out + 1] = { id = id, name = w.name } end
    end
    return out
end

-------------------------------------------------------------------------------
-- The newer auction house (C_AuctionHouse), 0.35.202. WoW: Forever has only
-- this one, so Flow knew no prices at all. Two ways, both started when you
-- open the auction house:
--   * everything at once (ReplicateItems), where the client has it: the
--     game allows it about once in 15 minutes; the list is read a few
--     hundred a frame;
--   * one search an item, for what's in your bags and on your watch list:
--     slow (the game throttles searches), but it always works.
-- Which calls this client has goes into the log the first time, so the
-- diagnostics say what worked.
-------------------------------------------------------------------------------
local CA = C_AuctionHouse
AH.STEP, AH.TIMEOUT, AH.CHUNK, AH.FULL_EVERY = 0.7, 4, 400, 900

-- Pure: the price of one, from a search result row (a commodity's
-- { unitPrice }, or an item's { buyoutAmount, quantity }); nil: no buyout.
function AH.UnitFrom(row)
    if type(row) ~= "table" then return nil end
    if type(row.unitPrice) == "number" and row.unitPrice > 0 then return row.unitPrice end
    local buyout, n = row.buyoutAmount, row.quantity or 1
    if type(buyout) == "number" and buyout > 0 and type(n) == "number" and n > 0 then return buyout / n end
    return nil
end
-- Pure: the cheapest per item from a full list. rows: { { id, count, buyout } }.
function AH.Cheapest(rows, into)
    into = into or {}
    for _, r in ipairs(rows) do
        if r.id and (r.buyout or 0) > 0 and (r.count or 0) > 0 then
            local unit = r.buyout / r.count
            if not into[r.id] or unit < into[r.id] then into[r.id] = unit end
        end
    end
    return into
end
-- Which of the newer calls this client has, as text.
function AH.NewCalls()
    local out = {}
    for _, name in ipairs({ "SendSearchQuery", "MakeItemKey", "GetCommoditySearchResultInfo", "GetItemSearchResultInfo",
                            "GetNumItemSearchResults", "ReplicateItems", "GetNumReplicateItems", "GetReplicateItemInfo",
                            "IsThrottledMessageSystemReady", "SendBrowseQuery" }) do
        out[#out + 1] = name .. "=" .. ((CA and CA[name]) and "yes" or "no")
    end
    return table.concat(out, ", ")
end

local function keep(best)
    local prices, now, n = store(), time(), 0
    for id, unit in pairs(best) do
        AH.Record(prices, id, unit, now)
        alertIfCheap(id, unit)
        n = n + 1
    end
    if n > 0 and ns.disposition and ns.disposition.Invalidate then ns.disposition:Invalidate() end
    return n
end

-- Everything at once.
local full = { busy = false, i = 0, n = 0, best = nil }
local function readFull()
    if not (open and full.busy) then full.busy = false return end
    local last = math.min(full.n - 1, full.i + AH.CHUNK - 1)
    for i = full.i, last do
        local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = pcall(CA.GetReplicateItemInfo, i)
        if ok and id and buyout and buyout > 0 and count and count > 0 then
            local unit = buyout / count
            if not full.best[id] or unit < full.best[id] then full.best[id] = unit end
        end
    end
    full.i = last + 1
    if full.i < full.n then C_Timer.After(0, readFull) return end
    full.busy = false
    local kept = keep(full.best)
    ns.db.ah.lastFull = time()
    ns:Print(string.format("auction house: read %d listings, prices for %d different items.", full.n, kept))
    ns:Log("ah", string.format("full scan: %d listings, %d items", full.n, kept))
end
ns:On("REPLICATE_ITEM_LIST_UPDATE", function()
    if full.busy or not (CA and CA.GetNumReplicateItems) then return end
    local ok, n = pcall(CA.GetNumReplicateItems)
    if not ok or type(n) ~= "number" or n <= 0 then return end
    full.busy, full.i, full.n, full.best = true, 0, n, {}
    readFull()
end)

-- One search an item.
local one = { id = nil, at = 0, key = nil }
local function nextSearch()
    one.id = nil
    if not open or #queue == 0 then
        if open and AH.searched and AH.searched > 0 then
            ns:Print(string.format("auction house: looked up %d item(s) from your bags, %d with a price.", AH.searched, AH.priced or 0))
            ns:Log("ah", string.format("searches: %d asked, %d priced", AH.searched, AH.priced or 0))
            AH.searched = nil
        end
        return
    end
    if CA.IsThrottledMessageSystemReady and not CA.IsThrottledMessageSystemReady() then C_Timer.After(0.3, nextSearch) return end
    local item = table.remove(queue, 1)
    local okK, key = pcall(CA.MakeItemKey, item.id)
    if not okK or not key then C_Timer.After(0, nextSearch) return end
    one.id, one.at, one.key = item.id, GetTime(), key
    AH.searched = (AH.searched or 0) + 1
    local ok, err = pcall(CA.SendSearchQuery, key, {}, false)
    if not ok then ns:Log("ah", "search failed: " .. tostring(err)); one.id = nil end
    -- (No answer: on to the next.)
    local asked = one.at
    C_Timer.After(AH.TIMEOUT, function() if one.id == item.id and one.at == asked then nextSearch() end end)
end
local function answered(row)
    if not one.id then return end
    local unit = AH.UnitFrom(row)
    if unit then
        keep({ [one.id] = unit })
        AH.priced = (AH.priced or 0) + 1
    end
    one.id = nil
    C_Timer.After(AH.STEP, nextSearch)
end
ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    if not (one.id and CA and CA.GetCommoditySearchResultInfo) then return end
    local ok, row = pcall(CA.GetCommoditySearchResultInfo, itemID or one.id, 1)
    answered(ok and row or nil)
end)
ns:On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    if not (one.id and CA and CA.GetItemSearchResultInfo) then return end
    local ok, row = pcall(CA.GetItemSearchResultInfo, itemKey or one.key, 1)
    answered(ok and row or nil)
end)

-- Everything in your bags that could be sold there (not soulbound, not
-- junk), and your watch list: what Flow asks the price of.
function AH:WantedAll()
    local out, seen = {}, {}
    local D = ns.disposition
    if D and D.EachBagItem then
        D:EachBagItem(function(bag, slot, link)
            local id = tonumber(link:match("item:(%d+)"))
            local okB, bound = pcall(D.IsBound, D, bag, slot)
            if id and not seen[id] and not (okB and bound) then
                seen[id] = true
                out[#out + 1] = { id = id, name = link:match("%[(.-)%]") }
            end
        end)
    end
    for id, w in pairs(ns.db.ah.watch) do
        if not seen[id] then seen[id] = true; out[#out + 1] = { id = id, name = w.name } end
    end
    return out
end

function AH:ScanNew()
    if not (CA and CA.SendSearchQuery and CA.MakeItemKey) then
        if not AH.saidNoApi then
            AH.saidNoApi = true
            ns:Print("Flow can't read this auction house (neither the classic calls nor the newer ones are here). Logged for the diagnostics.")
        end
        ns:Log("ah", "no usable auction calls: " .. AH.NewCalls())
        return
    end
    if not AH.loggedCalls then AH.loggedCalls = true; ns:Log("ah", "newer auction house: " .. AH.NewCalls()) end
    -- Everything at once, where the client has it and enough time has passed.
    if CA.ReplicateItems and CA.GetReplicateItemInfo and time() - (ns.db.ah.lastFull or 0) > AH.FULL_EVERY then
        local ok, err = pcall(CA.ReplicateItems)
        ns:Log("ah", "asked for the whole list: " .. (ok and "sent" or tostring(err)))
    end
    queue = AH:WantedAll()
    AH.searched, AH.priced = 0, 0
    if #queue > 0 then
        ns:Print(string.format("auction house: looking up prices for %d item(s) from your bags...", #queue))
        nextSearch()
    end
end

function AH:Scan()
    if not classic() then return AH:ScanNew() end
    queue = AH:Wanted()
    if #queue > 0 then
        ns:Print(string.format("checking auction house prices for %d item(s)...", #queue))
        step()
    end
end

ns:On("AUCTION_HOUSE_SHOW", function()
    open = true
    C_Timer.After(1, function() if open then pcall(AH.Scan, AH) end end)
end)
ns:On("AUCTION_HOUSE_CLOSED", function() open = false; wipe(queue); pending = nil end)
ns:On("AUCTION_ITEM_LIST_UPDATE", function()
    if not open or not classic() then return end
    pcall(readPage)   -- your own browsing counts too
    if pending then
        pending = nil
        C_Timer.After(0.3, step)
    end
end)

-------------------------------------------------------------------------------
-- Tooltips
-------------------------------------------------------------------------------

local function addLine(tt, id)
    local price, at = AH:Price(id)
    if not price then return end
    local ago = math.max(0, time() - (at or time()))
    local when = ago < 3600 and string.format("%d min ago", math.floor(ago / 60))
        or ago < 86400 and string.format("%d h ago", math.floor(ago / 3600))
        or string.format("%d days ago", math.floor(ago / 86400))
    tt:AddLine(string.format("Auction house: %s each, %s", AH.Money(price), when), 0.9, 0.8, 0.5)
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if tt == GameTooltip and data and data.id then pcall(addLine, tt, data.id) end
    end)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tt)
        local _, link = tt:GetItem()
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then pcall(addLine, tt, id) end
    end)
end

-------------------------------------------------------------------------------

ns:OnLoad(function(saved)
    saved.ah = saved.ah or {}
    saved.ah.prices = saved.ah.prices or {}
    saved.ah.watch = saved.ah.watch or {}
end)

ns.commands.ah = function(arg)
    arg = arg or ""
    local cmd, rest = arg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "watch" then
        -- "<item> [price]": the price is the last word when it reads as money.
        local item, money = rest:match("^(.-)%s+(%S+)$")
        local max = AH.ParseMoney(money)
        if not max then item = rest end
        local id = itemId(item)
        if not id then ns:Print("couldn't find that item: shift-click it into the chat line, or use its name once you've seen it") return end
        local name = (ns.api.ItemInfo or GetItemInfo)(id) or item
        ns.db.ah.watch[id] = { name = name, max = max }
        ns:Print(string.format("watching %s%s", name, max and (" at or under " .. AH.Money(max)) or ""))
    elseif cmd == "unwatch" then
        local id = itemId(rest)
        if id and ns.db.ah.watch[id] then ns.db.ah.watch[id] = nil; ns:Print("stopped watching it") else ns:Print("not on your watch list") end
    elseif cmd == "scan" then
        if open then AH:Scan() else ns:Print("open an auction house first") end
    else
        ns:Print("auction house watch list:")
        local any = false
        for id, w in pairs(ns.db.ah.watch) do
            any = true
            local price = AH:Price(id)
            print(string.format("  %s%s  last seen: %s", w.name or id, w.max and (" (under " .. AH.Money(w.max) .. ")") or "",
                price and AH.Money(price) or "not yet"))
        end
        if not any then print("  (empty)") end
        print("  /flow ah watch <item> [gold] | unwatch <item> | scan")
    end
end
