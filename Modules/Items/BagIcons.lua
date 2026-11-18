-- Icons on your bag slots (Blizzard bags; other bag addons aren't covered):
--   (o) target (top left)     = your current route step wants you to use this item
--   bank (top left)           = Flow Banker puts it in your bank at your next visit (0.35.300)
--   top right                 = gold coin = sell, the auctioneer's mark = auction house, DE, or why it is kept:
--                               quest "!" (current/upcoming quest), profession icon (crafting material)
--   bottom row (gear)         = one icon per spec, with a mark above: green arrow up = better
--                               than that spec's gear, red arrow down = worse, grey dash = about the same
-- The item tooltip says what Flow would do and why.
-- /flow bags on|off

local _, ns = ...
local D = ns.disposition
local B = {}
ns.bagIcons = B

-- The item your current route step wants you to use (a recipe to learn...).
function B.FocusItem()
    local c = ns.nav and ns.nav.current
    return c and c.goal and c.goal.useItem or nil
end

-- What goes into your bank at your next visit (Flow Banker's own list, so the
-- icon and the Deposit button always agree; your choices in its window count).
-- Pure: the list's rows as a set. rows: { { id } } -> { [itemID] = true }
function B.BankSet(rows)
    local set = {}
    for _, r in ipairs(rows or {}) do
        if type(r) == "table" and r.id then set[r.id] = true end
    end
    return set
end
-- Pure: does this bag item get the bank icon? Never the item your current
-- step uses (that one has the (o) in the same corner).
function B.ToBank(id, set, focus)
    if not (id and set and set[id]) then return false end
    return not (focus and focus == id)
end
B.bankSet = {}
function B.RefreshBankSet()
    local K = ns.banker
    local ok, rows = pcall(function() return K and K.List and K.List() or {} end)
    B.bankSet = B.BankSet(ok and rows or {})
    return B.bankSet
end
B.BANK_TIP = "Flow Banker: goes into your bank at your next visit (Deposit there; change it in the Flow Banker)."

local BADGE = {
    sell = { "$", 1.0, 0.75, 0.2 },
    ah   = { "AH", 0.4, 0.8, 1.0 },
    de   = { "DE", 0.75, 0.5, 1.0 },
}

-- Puts the auctioneer's picture on a texture. -> true when the game has one.
B.AH_ATLASES = { "Auctioneer", "auctioneer" }
B.AH_FILE = "Interface\\Minimap\\Tracking\\Auctioneer"
function B.SetAuctionIcon(tex)
    if tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo then
        for _, name in ipairs(B.AH_ATLASES) do
            if C_Texture.GetAtlasInfo(name) and pcall(tex.SetAtlas, tex, name) then return true end
        end
    end
    tex:SetTexture(B.AH_FILE)
    return tex:GetTexture() ~= nil
end
-- Pure: what the top right corner shows for an action: "coin" (sell), "ah"
-- (the auctioneer's mark), "letters" (DE, or AH without the picture), nil.
function B.CornerFor(action, ahPicture)
    if action == "sell" then return "coin" end
    if action == "ah" then return ahPicture and "ah" or "letters" end
    if action == "de" then return "letters" end
    return nil
end

local function marks(button)
    if button.flowMarks then return button.flowMarks end
    local m = CreateFrame("Frame", nil, button)
    m:SetAllPoints()
    m:SetFrameLevel(button:GetFrameLevel() + 5)
    m.arrow = m:CreateTexture(nil, "OVERLAY")
    m.arrow:SetSize(16, 16)
    m.arrow:SetPoint("TOPLEFT", -2, 2)
    local ok = m.arrow.SetAtlas and pcall(m.arrow.SetAtlas, m.arrow, "bags-greenarrow")
    if not ok then
        m.arrow:SetColorTexture(0.2, 1, 0.2, 0.9)
        m.arrow:SetSize(8, 8)
    end
    -- Bottom: the spec badge (Gear/SpecBadge.lua): an icon per spec with an
    -- arrow right above it (better / worse / same as that spec's gear).
    m.specs = ns:SpecBadge(m, 10)
    m.specs:SetPoint("BOTTOMRIGHT", -1, 1)
    m.badge = m:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    m.badge:SetPoint("TOPRIGHT", -2, -2)
    -- Gold coin for "sell".
    m.coin = m:CreateTexture(nil, "OVERLAY")
    m.coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    m.coin:SetSize(14, 14)
    m.coin:SetPoint("TOPRIGHT", -1, -1)
    m.coin:Hide()
    -- The auction house: the game's auctioneer mark instead of the letters
    -- "AH" (0.35.304). A client without that picture keeps the letters.
    m.ah = m:CreateTexture(nil, "OVERLAY")
    m.ah:SetSize(15, 15)
    m.ah:SetPoint("TOPRIGHT", 0, 0)
    m.ahOk = B.SetAuctionIcon(m.ah)
    m.ah:Hide()
    -- Keep-for-a-reason icon (quest "!", or the profession's icon).
    m.keep = m:CreateTexture(nil, "OVERLAY")
    m.keep:SetSize(14, 14)
    m.keep:SetPoint("TOPRIGHT", -1, -1)
    m.keep:Hide()
    -- Flow's target marker (o) in the route colour, top-left: this is the
    -- item your current step wants you to use ("Learn Brilliant Smallfish:
    -- use the recipe in your bags").
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    m.focus = CreateFrame("Frame", nil, m)
    m.focus:SetSize(14, 14)
    m.focus:SetPoint("TOPLEFT", -3, 3)
    m.focus:SetFrameLevel(m:GetFrameLevel() + 2)
    local function disc(sub, inset)
        local t = m.focus:CreateTexture(nil, "OVERLAY", nil, sub)
        t:SetTexture(CIRCLE)
        t:SetPoint("TOPLEFT", inset, -inset); t:SetPoint("BOTTOMRIGHT", -inset, inset)
        return t
    end
    m.focus.edge, m.focus.ring, m.focus.hole, m.focus.dot = disc(1, -1), disc(2, 0), disc(3, 2), disc(4, 4)
    m.focus.edge:SetVertexColor(0, 0, 0, 0.9)
    m.focus.hole:SetVertexColor(0.05, 0.05, 0.08, 1)
    -- The bank: this goes in at your next visit (same corner as the (o); a
    -- step's item is never banked, so they don't meet).
    m.bank = m:CreateTexture(nil, "OVERLAY")
    m.bank:SetSize(14, 14)
    m.bank:SetPoint("TOPLEFT", -2, 2)
    local okAtlas = m.bank.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Banker")
        and pcall(m.bank.SetAtlas, m.bank, "Banker")
    if not okAtlas then m.bank:SetTexture("Interface\\Icons\\INV_Misc_Bag_10") end
    m.bank:Hide()
    m.focus:Hide()
    button.flowMarks = m
    return m
end

local function clear(button)
    local m = button.flowMarks
    if not m then return end
    m.arrow:Hide()
    m.focus:Hide()
    m.bank:Hide()
    m.specs:Hide()
    m.badge:SetText("")
    m.coin:Hide()
    m.keep:Hide()
    m.ah:Hide()
end

local function paint(button, bag, slot)
    local link = bag and slot and (C_Container and C_Container.GetContainerItemLink or GetContainerItemLink)(bag, slot)
    if not link or not ns.db.bags.enabled then clear(button) return end
    local v = D:Decide(bag, slot, link)
    if not v then clear(button) return end
    local m = marks(button)
    -- (The old top-left "equip now" arrow is gone: the spec marks below say
    -- better / worse per spec, with your levelling spec brightest.)
    m.arrow:Hide()
    local id = tonumber(link:match("item:(%d+)"))
    local focus = id and id == ns.bagIcons.FocusItem()
    if focus then
        local c = ns.theme.route
        m.focus.ring:SetVertexColor(c[1], c[2], c[3], 1)
        m.focus.dot:SetVertexColor(c[1], c[2], c[3], 1)
    end
    m.focus:SetShown(focus or false)
    m.bank:SetShown(v.action == "keep" and B.ToBank(id, B.bankSet, B.FocusItem()))
    local g = v.item.gear
    if g and g.canUse then m.specs:Set(g.diffs) else m.specs:Hide() end
    m.coin:SetShown(v.action == "sell")
    if v.action == "keep" and v.icon then
        m.keep:SetTexture(v.icon)
        m.keep:Show()
    else
        m.keep:Hide()
    end
    local corner = B.CornerFor(v.action, m.ahOk)
    m.ah:SetShown(corner == "ah")
    local b = corner == "letters" and BADGE[v.action]
    if b then
        m.badge:SetText(b[1])
        m.badge:SetTextColor(b[2], b[3], b[4])
    else
        m.badge:SetText("")
    end
end

-- Calls fn(button, bag, slot) for every visible Blizzard bag slot button.
local function eachButton(fn)
    local frames = {}
    if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if f then frames[#frames + 1] = f end
    end
    for _, f in ipairs(frames) do
        if f:IsShown() then
            if f.EnumerateValidItems then
                for _, b in f:EnumerateValidItems() do
                    fn(b, b.GetBagID and b:GetBagID() or f:GetID(), b:GetID())
                end
            elseif f.Items then
                for _, b in ipairs(f.Items) do
                    if b:IsShown() then fn(b, b.GetBagID and b:GetBagID() or f:GetID(), b:GetID()) end
                end
            elseif f:GetName() then
                local bag = f:GetID()
                for j = 1, 36 do
                    local b = _G[f:GetName() .. "Item" .. j]
                    if b and b:IsShown() then fn(b, bag, b:GetID()) end
                end
            end
        end
    end
end

local dirty, acc, wasOpen = true, 0, false
local function refresh()
    B.RefreshBankSet()
    eachButton(function(b, bag, slot) pcall(paint, b, bag, slot) end)
end

ns:OnLoad(function(saved)
    saved.bags = saved.bags or {}
    if saved.bags.enabled == nil then saved.bags.enabled = true end
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.3 then return end
        acc = 0
        -- Repaint when bags open, when something changed, and now and then
        -- while open (item info can arrive late).
        local open = (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown())
            or (ContainerFrame1 and ContainerFrame1:IsShown())
        if open and not wasOpen then dirty = true end
        local focus = B.FocusItem()
        if focus ~= B.lastFocus then B.lastFocus = focus; dirty = true end
        wasOpen = open
        if dirty or (open and math.random() < 0.1) then
            dirty = false
            refresh()
        end
    end)
end)

for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
                      "EQUIPMENT_SETS_CHANGED", "GET_ITEM_INFO_RECEIVED", "BAG_OPEN" }) do
    ns:On(ev, function() dirty = true end)
end

function B.MarkDirty() dirty = true end

ns.commands.bags = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.bags.enabled = (arg == "on")
        dirty = true
        ns:Print("bag icons " .. arg)
    else
        ns:Print("/flow bags on|off. Spec icons with marks: green arrow up = better, red down = worse, grey dash = same, per spec. (o) = your current step uses this. Bank icon = goes into your bank at your next visit. $ sell, the auctioneer's mark = auction house, DE disenchant.")
    end
end

-- Tooltip line for items in your bags: what Flow would do, and why.
local ACTION_COLOR = { equip = "66ff66", keep = "ffd200", sell = "ffbf33", ah = "66ccff", de = "bf80ff" }
ns:Register("itemTip", "disposition", function(tooltip, link)
    if not ns.db.bags.enabled then return end
    local bag, slot, l = D:FindInBags(link)
    if not bag then return end
    local v = D:Decide(bag, slot, l)
    if not v then return end
    tooltip:AddLine(string.format("Flow: |cff%s%s|r: %s", ACTION_COLOR[v.action] or "ffffff",
        D.LABEL[v.action] or v.action, v.reason or ""), 0.9, 0.9, 0.9, true)
    local id = tonumber(tostring(l):match("item:(%d+)"))
    if v.action == "keep" and B.ToBank(id, B.bankSet, B.FocusItem()) then
        tooltip:AddLine(B.BANK_TIP, 0.6, 0.8, 1, true)
    end
    tooltip:Show()
end)
