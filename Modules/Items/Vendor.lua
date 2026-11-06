-- Vendor panel: next to the merchant window, Flow lists what it would sell
-- (from the item decisions in Disposition.lua) and sells it in batches of
-- 12 when you click. 12 is how many items the merchant's buyback tab keeps,
-- so everything in a batch can still be bought back:
--   * click "Buy back" next to an item to get it back right away, and Flow
--     will never sell that item again (it learns from you);
--   * then sell the next 12, or close.
-- Items marked AH (auction house) or DE (disenchant) are never sold here;
-- the panel only counts them.

local _, ns = ...
local D = ns.disposition
local V = {}
ns.vendor = V

local BATCH = 12
local ROWS = 12
local panel
local mode = "list"    -- "list" = about to sell, "sold" = just sold (buyback view)
local soldBatch = {}

local CC = C_Container
local function stackCount(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        return info and info.stackCount or 1, info and info.isLocked
    end
    local _, count, locked = GetContainerItemInfo(bag, slot)
    return count or 1, locked
end
local useItem = (CC and CC.UseContainerItem) or UseContainerItem

local function money(c)
    return GetCoinTextureString and GetCoinTextureString(math.floor(c)) or tostring(c)
end

-- What Flow would sell now, junk first, then most valuable first.
function V:Candidates()
    local list, ah, de = {}, 0, 0
    D:EachBagItem(function(bag, slot, link)
        local v = D:Decide(bag, slot, link)
        if not v then return end
        if v.action == "ah" then ah = ah + 1 elseif v.action == "de" then de = de + 1 end
        if v.action == "sell" and v.item.sellPrice > 0 then
            local count, locked = stackCount(bag, slot)
            if not locked then
                list[#list + 1] = { bag = bag, slot = slot, link = link, id = v.item.id,
                    junk = v.item.quality == 0, price = v.item.sellPrice * count, reason = v.reason }
            end
        end
    end)
    table.sort(list, function(a, b)
        if a.junk ~= b.junk then return a.junk end
        return a.price > b.price
    end)
    return list, ah, de
end

-- Buyback slot holding this item (matched by item ID; newest first).
local function buybackIndex(link)
    local id = tonumber(link:match("item:(%d+)"))
    for i = (GetNumBuybackItems and GetNumBuybackItems() or 0), 1, -1 do
        local l = GetBuybackItemLink and GetBuybackItemLink(i)
        if l and (l == link or tonumber(l:match("item:(%d+)")) == id) then return i end
    end
end

-------------------------------------------------------------------------------
-- Panel
-------------------------------------------------------------------------------

local function build()
    local f = CreateFrame("Frame", "FlowVendorPanel", UIParent)
    f:SetSize(330, 90 + ROWS * 22)
    f:SetFrameStrata("HIGH")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
    local top = f:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
    top:SetColorTexture(1, 0.82, 0.25, 0.9)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -10)

    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(310, 20)
        r:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 22)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT")
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
        r.name:SetWidth(170)
        r.name:SetJustifyH("LEFT")
        r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.price:SetPoint("RIGHT", -70, 0)
        r.back = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.back:SetSize(66, 18)
        r.back:SetPoint("RIGHT")
        r.back:SetText("Buy back")
        r.back:GetFontString():SetFontObject("GameFontHighlightSmall")
        r:SetScript("OnEnter", function(self)
            if not self.link then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink(self.link)
            if self.reason then GameTooltip:AddLine("Flow: " .. self.reason, 1, 0.82, 0.25) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:EnableMouse(true)
        f.rows[i] = r
    end

    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.footer:SetPoint("BOTTOMLEFT", 10, 38)
    f.footer:SetWidth(310)
    f.footer:SetJustifyH("LEFT")

    f.sell = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.sell:SetSize(150, 24)
    f.sell:SetPoint("BOTTOMLEFT", 10, 10)
    f.close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.close:SetSize(80, 24)
    f.close:SetPoint("BOTTOMRIGHT", -10, 10)
    f.close:SetText("Close")
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.sell:SetScript("OnClick", function()
        if mode == "sold" then mode = "list"; V:Refresh() return end
        V:SellBatch()
    end)
    f:Hide()
    return f
end

local function setRow(r, e, showBack)
    if not e then r:Hide() return end
    r.link, r.reason = e.link, e.reason
    local get = (C_Item and C_Item.GetItemIcon) or GetItemIcon
    r.icon:SetTexture(get and get(e.link))
    r.name:SetText(e.link)
    r.price:SetText(money(e.price))
    r.back:SetShown(showBack and not e.boughtBack)
    r.back:SetScript("OnClick", function()
        local i = buybackIndex(e.link)
        if not i then ns:Print("couldn't find that item in the buyback tab") return end
        BuybackItem(i)
        e.boughtBack = true
        if e.id then ns.db.sell.never[e.id] = true end
        D:Invalidate()
        ns:Print(e.link .. " bought back. Flow won't sell it again.")
        r.back:Hide()
    end)
    r:Show()
end

function V:Refresh()
    if not panel or not panel:IsShown() then return end
    local rows = panel.rows
    if mode == "sold" then
        local total = 0
        for _, e in ipairs(soldBatch) do total = total + e.price end
        panel.title:SetText(string.format("Flow sold %d item(s) for %s", #soldBatch, money(total)))
        for i = 1, ROWS do setRow(rows[i], soldBatch[i], true) end
        local left = #(self:Candidates())
        panel.footer:SetText("Changed your mind? Buy back anything above (Flow learns not to sell it).")
        panel.sell:SetText(left > 0 and string.format("Next batch (%d left)", left) or "Done")
        panel.sell:SetEnabled(left > 0)
        return
    end
    local list, ah, de = self:Candidates()
    panel.title:SetText(#list > 0 and string.format("Flow would sell %d item(s)", #list) or "Nothing to sell")
    local batchTotal = 0
    for i = 1, ROWS do
        setRow(rows[i], list[i], false)
        if list[i] and i <= BATCH then batchTotal = batchTotal + list[i].price end
    end
    local extra = {}
    if ah > 0 then extra[#extra + 1] = ah .. " for the auction house (AH)" end
    if de > 0 then extra[#extra + 1] = de .. " to disenchant (DE)" end
    panel.footer:SetText((#extra > 0 and ("Kept, marked in your bags: " .. table.concat(extra, ", ") .. ". ") or "")
        .. "Hover an item to see why.")
    panel.sell:SetText(#list > 0 and string.format("Sell %d for %s", math.min(BATCH, #list), money(batchTotal)) or "Nothing to sell")
    panel.sell:SetEnabled(#list > 0)
end

-- Runs from the button click (a real click: some clients require one).
function V:SellBatch()
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    local list = self:Candidates()
    wipe(soldBatch)
    for i = 1, math.min(BATCH, #list) do
        local e = list[i]
        useItem(e.bag, e.slot)
        soldBatch[#soldBatch + 1] = e
    end
    mode = "sold"
    D:Invalidate()
    self:Refresh()
end

ns:On("MERCHANT_SHOW", function()
    if not ns.db.sell.enabled then return end
    panel = panel or build()
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0)
    mode = "list"
    wipe(soldBatch)
    D:Invalidate()
    panel:Show()
    V:Refresh()
end)

ns:On("MERCHANT_CLOSED", function() if panel then panel:Hide() end end)
ns:On("BAG_UPDATE_DELAYED", function()
    if panel and panel:IsShown() then D:Invalidate(); V:Refresh() end
end)

ns:OnLoad(function(saved)
    if saved.sell.enabled == nil then saved.sell.enabled = true end
end)

ns.commands.sell = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.sell.enabled = (arg == "on")
        ns:Print("vendor panel " .. arg)
    elseif arg == "forget" then
        wipe(ns.db.sell.never)
        D:Invalidate()
        ns:Print("forgot your never-sell list")
    else
        local n = 0
        for _ in pairs(ns.db.sell.never) do n = n + 1 end
        ns:Print(string.format("vendor panel %s; %d item(s) on your never-sell list. /flow sell on|off|forget",
            ns.db.sell.enabled and "on" or "off", n))
    end
end
