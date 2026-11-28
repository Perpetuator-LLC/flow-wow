-------------------------------------------------------------------------------
-- Flow - Items/LootRoom.lua
-- Bags full at a corpse: one click makes room (0.35.429).
--
-- "Now my bags are full. I'd love to skin it, but there's a poor quality item
-- on it, and so I can't. Is there a way for us to destroy the item that's
-- currently on the dead mob so that I can skin it? ... a little icon on it,
-- like a trash bin that's red, that says click this, it'll destroy it."
--
-- The game has no way to destroy something that's still on a corpse: an item
-- can only be destroyed from your bags. And with full bags the corpse can't
-- be emptied, so it can't be skinned. What an add-on can do is the other end
-- of it: destroy the least valuable piece of junk you carry, which frees the
-- slot the corpse's item needs.
--
-- So while the loot window is open, your bags are full and something is still
-- on the corpse, a red button appears by the loot window:
--     Make room: destroy 3 x Cracked Bill (worth 12c)
-- It names exactly what it will destroy: the grey (poor) item in your bags
-- that a vendor would pay least for, never a quest item, never anything
-- better than grey. Your click is the go-ahead. Flow then destroys that one
-- stack and takes what's on the corpse, so it can be skinned. With no grey
-- item in your bags it says so and does nothing.
--
-- Whether this client lets an add-on destroy an item on a click isn't known
-- until it's tried here: if the game refuses, it shows under "Blocked
-- actions" in the diagnostics and the button says so.
-------------------------------------------------------------------------------

local _, ns = ...
local R = {}
ns.lootRoom = R

R.ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

-- Pure: the stack to destroy: the grey item a vendor pays least for (its
-- whole stack), never a quest item. items: { { bag, slot, id, name, quality,
-- price (each), count, quest } } -> one of them, or nil.
function R.Cheapest(items)
    local best, worth
    for _, it in ipairs(items or {}) do
        if it.quality == 0 and not it.quest and it.id then
            local w = (it.price or 0) * (it.count or 1)
            if not worth or w < worth then best, worth = it, w end
        end
    end
    return best, worth
end

-- Pure: show the button? Bags full, and something still on the corpse.
function R.Wants(free, left)
    return type(free) == "number" and free <= 0 and (left or 0) > 0
end

-- Pure: copper as "1g 20s 5c".
function R.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then return "nothing" end
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- Pure: the button's words.
function R.Text(it, worth)
    if not it then return "Bags full, and no grey item to destroy" end
    return string.format("Make room: destroy %d x %s (worth %s)", it.count or 1, tostring(it.name or "junk"), R.Money(worth))
end

-- Free slots in your bags.
function R.Free()
    local get = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if not get then return nil end
    local n = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local ok, free = pcall(get, bag)
        free = ok and ns.api.Safe(free) or nil
        if type(free) == "number" then n = n + free end
    end
    return n
end

-- What's in your bags, as R.Cheapest wants it.
function R.Scan()
    local out = {}
    local C = C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return out end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
            local info = C.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local name, price, classID
                if getInfo then
                    local ok, n, _, _, _, _, _, _, _, _, _, p, cls = pcall(getInfo, info.hyperlink or info.itemID)
                    if ok then name, price, classID = n, p, cls end
                end
                out[#out + 1] = { bag = bag, slot = slot, id = info.itemID, name = name, quality = ns.api.Safe(info.quality),
                                  price = ns.api.Safe(price) or 0, count = ns.api.Safe(info.stackCount) or 1, quest = classID == 12 }
            end
        end
    end
    return out
end

-- Items still on the corpse (not money).
function R.Left()
    local n = 0
    local ITEM = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or LOOT_SLOT_ITEM or 1
    for i = 1, (ns.api.Safe(GetNumLootItems and GetNumLootItems()) or 0) do
        if GetLootSlotType and ns.api.Safe(GetLootSlotType(i)) == ITEM then n = n + 1 end
    end
    return n
end

local button
local function lootAll()
    for i = (ns.api.Safe(GetNumLootItems and GetNumLootItems()) or 0), 1, -1 do pcall(LootSlot, i) end
end

-- The click: destroy the named stack (if it's still that item), then take the corpse's.
function R.Destroy(it)
    local C = C_Container
    if not (it and C and C.GetContainerItemInfo and C.PickupContainerItem and DeleteCursorItem) then return false, "this client has no way to" end
    local info = C.GetContainerItemInfo(it.bag, it.slot)
    if not (info and info.itemID == it.id) then return false, "that slot changed" end
    if ns.api.Safe(info.quality) ~= 0 then return false, "it isn't a grey item" end
    ClearCursor()
    C.PickupContainerItem(it.bag, it.slot)
    if not (CursorHasItem and CursorHasItem()) then ClearCursor() return false, "the game didn't pick it up" end
    DeleteCursorItem()
    ClearCursor()
    ns:Log("loot", string.format("made room: destroyed %d x %s", it.count or 1, tostring(it.name)))
    if C_Timer and C_Timer.After then C_Timer.After(0.4, function() pcall(lootAll); pcall(R.Update) end) end
    return true
end

local function build()
    local b = CreateFrame("Button", "FlowLootRoom", UIParent)
    b:SetSize(300, 28)
    b:SetFrameStrata("DIALOG")
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.35, 0.05, 0.05, 0.92)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22)
    b.icon:SetPoint("LEFT", 4, 0)
    b.icon:SetTexture(R.ICON)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Your bags are full", 1, 0.82, 0)
        GameTooltip:AddLine("What's on the corpse can't be taken, so it can't be skinned. An item still on a corpse can't be destroyed: only one in your bags can.", 1, 1, 1, true)
        if self.pick then
            GameTooltip:AddLine("Click: Flow destroys this grey stack from your bags (the one a vendor pays least for) and takes what's on the corpse.", 1, 0.5, 0.5, true)
        else
            GameTooltip:AddLine("There's no grey item in your bags, so Flow won't destroy anything. Free a slot yourself.", 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if not self.pick then return end
        local ok, done, why = pcall(R.Destroy, self.pick)
        if not (ok and done) then
            self.text:SetText("Couldn't destroy it: " .. tostring(ok and why or done))
            ns:Log("loot", "make room failed: " .. tostring(ok and why or done))
        end
    end)
    b:Hide()
    return b
end

-- Shows or hides the button for the loot window as it is now.
function R.Update()
    local open = (LootFrame and LootFrame:IsShown()) or (ns.api.Safe(GetNumLootItems and GetNumLootItems()) or 0) > 0
    local want = open and R.Wants(R.Free(), R.Left())
    if not want then
        if button then button:Hide() end
        return false
    end
    button = button or build()
    local pick, worth = R.Cheapest(R.Scan())
    button.pick = pick
    button.text:SetText(R.Text(pick, worth))
    button:ClearAllPoints()
    if LootFrame and LootFrame:IsShown() then
        button:SetPoint("TOPLEFT", LootFrame, "BOTTOMLEFT", 0, -4)
    else
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 20, y / s - 20)
    end
    button:Show()
    return true
end
R._button = function() return button end   -- (tests)

for _, ev in ipairs({ "LOOT_OPENED", "LOOT_SLOT_CLEARED", "BAG_UPDATE_DELAYED" }) do
    ns:On(ev, function() pcall(R.Update) end)
end
ns:On("LOOT_CLOSED", function() if button then button:Hide() end end)

ns.commands.lootroom = function()
    local pick, worth = R.Cheapest(R.Scan())
    ns:Print(string.format("bags: %s free slot(s). With full bags at a corpse Flow offers: %s", tostring(R.Free()), R.Text(pick, worth)))
end
