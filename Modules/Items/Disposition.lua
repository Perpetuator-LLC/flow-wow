-- What to do with each item in your bags: equip, keep, sell, auction house
-- (AH) or disenchant (DE). Used by the bag icons and the vendor panel.
--
-- Rules are registered and checked in order (lowest `order` first); the
-- first rule that returns a verdict decides. Add your own:
--   ns:Register("disposition", key, { order = n, check = function(item) -> verdict end })
-- item   = { bag, slot, link, id, quality, classID, sellPrice, bound, minLevel, gear = Compare result }
-- verdict = { action = "equip"|"keep"|"sell"|"ah"|"de", reason = "..." }

local _, ns = ...
local D = {}
ns.disposition = D

local ACTION_LABEL = { equip = "Equip", keep = "Keep", sell = "Sell", ah = "Auction house", de = "Disenchant" }
D.LABEL = ACTION_LABEL

-------------------------------------------------------------------------------
-- Bag helpers
-------------------------------------------------------------------------------

local CC = C_Container
local numSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
local linkOf = (CC and CC.GetContainerItemLink) or GetContainerItemLink

function D:EachBagItem(fn)
    if not numSlots then return end
    for bag = 0, 4 do
        for slot = 1, numSlots(bag) or 0 do
            local link = linkOf(bag, slot)
            if link then fn(bag, slot, link) end
        end
    end
end

-- Is the item in this bag slot soulbound? true/false, or nil if unknown.
function D:IsBound(bag, slot)
    if C_Item and C_Item.IsBound and ItemLocation then
        local ok, r = pcall(C_Item.IsBound, ItemLocation:CreateFromBagAndSlot(bag, slot))
        if ok then return r end
    end
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        if info and info.isBound ~= nil then return info.isBound end
    end
    return nil
end

local function itemInfo(link)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality, _, minLevel, _, _, _, equipLoc, _, sellPrice, classID = get(link)
    return quality, minLevel, sellPrice, classID, equipLoc
end

-- Market price from an auction addon if one is installed (Auctionator), else nil.
function D:AuctionPrice(link)
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink then
        local ok, p = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, "Flow", link)
        if ok and type(p) == "number" then return p end
    end
end

-------------------------------------------------------------------------------
-- Deciding
-------------------------------------------------------------------------------

local cache = {}
function D:Invalidate() wipe(cache) end

function D:Describe(bag, slot, link)
    local quality, minLevel, sellPrice, classID = itemInfo(link)
    if quality == nil then return nil end  -- not loaded yet
    return {
        bag = bag, slot = slot, link = link, id = tonumber(link:match("item:(%d+)")),
        quality = quality, minLevel = minLevel or 0, sellPrice = sellPrice or 0, classID = classID,
        bound = self:IsBound(bag, slot),
        gear = ns.gear and ns.gear:Compare(link) or nil,
    }
end

local sorted
local function rules()
    if not sorted then
        sorted = {}
        for key, r in ns:Each("disposition") do sorted[#sorted + 1] = { key = key, r = r } end
        table.sort(sorted, function(a, b) return (a.r.order or 100) < (b.r.order or 100) end)
    end
    return sorted
end

-- Verdict for the item in a bag slot (cached per link + bound state).
function D:Decide(bag, slot, link)
    local key = link .. ":" .. bag .. ":" .. slot
    if cache[key] then return cache[key] end
    local item = self:Describe(bag, slot, link)
    if not item then return nil end
    for _, e in ipairs(rules()) do
        local ok, v = pcall(e.r.check, item)
        if ok and v then
            v.rule = e.key
            v.item = item
            cache[key] = v
            return v
        end
    end
    local v = { action = "keep", reason = "no rule matched", item = item }
    cache[key] = v
    return v
end

for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
                      "EQUIPMENT_SETS_CHANGED", "SKILL_LINES_CHANGED" }) do
    ns:On(ev, function() D:Invalidate() end)
end

ns:OnLoad(function(saved)
    saved.sell = saved.sell or {}
    saved.sell.never = saved.sell.never or {}
end)

-------------------------------------------------------------------------------
-- Built-in rules
-------------------------------------------------------------------------------

local function reg(key, order, check) ns:Register("disposition", key, { order = order, check = check }) end

-- You bought it back after Flow sold it once: never sell it again.
reg("neverSell", 1, function(i)
    if ns.db.sell.never[i.id] then return { action = "keep", reason = "you bought it back before" } end
end)

reg("unsellable", 2, function(i)
    if i.sellPrice <= 0 and i.quality ~= 0 then return { action = "keep", reason = "vendors won't buy it" } end
end)

-- Quest items (classID 12).
reg("quest", 5, function(i)
    if i.classID == 12 then return { action = "keep", reason = "quest item" } end
end)

-- Gear you should wear now.
reg("equip", 10, function(i)
    local g = i.gear
    if not (g and g.canUse) then return nil end
    local role = ns:LevelingRole()
    if g.diffs[role] >= 0.5 and i.minLevel <= UnitLevel("player") then
        return { action = "equip", reason = string.format("+%d %s", g.diffs[role] + 0.5, ns.ROLE_LABEL[role]) }
    end
end)

-- Part of a gear set.
reg("inSet", 15, function(i)
    local sets = ns.gear and ns.gear.sets
    local roles = sets and sets:RolesContaining(i.link) or {}
    if #roles > 0 then return { action = "keep", reason = "in a gear set" } end
end)

-- Grey items: always junk.
reg("junk", 20, function(i)
    if i.quality == 0 then return { action = "sell", reason = "junk" } end
end)

-- Non-gear: trade goods, reagents, consumables, recipes, bags, gems... keep.
-- (PLACEHOLDER: sell trade goods none of your professions use.)
reg("notGear", 30, function(i)
    if not i.gear then return { action = "keep", reason = "not gear (materials, food, potions...)" } end
end)

-- Upgrade later, or better for another role.
reg("laterOrOtherRole", 40, function(i)
    local g = i.gear
    if not g.canUse then return nil end
    local main = ns:LevelingRole()
    if g.diffs[main] >= 0.5 then return { action = "keep", reason = "upgrade at level " .. i.minLevel } end
    if ns.db.gear.keepOffspec then
        for _, role in ipairs(ns.gear.ROLES) do
            if role ~= main and g.diffs[role] >= 0.5 then
                return { action = "keep", reason = "better for " .. ns.ROLE_LABEL[role] }
            end
        end
    end
end)

-- Unneeded gear: disenchant if you can, auction if it's worth more there,
-- otherwise vendor.
reg("unneededGear", 50, function(i)
    if ns.api.Skill("Enchanting") and i.quality >= 2 then
        return { action = "de", reason = "you can disenchant it" }
    end
    if i.bound == false and i.quality >= 2 then
        local ah = D:AuctionPrice(i.link)
        if ah then
            -- AH takes a 5% cut; only worth it if clearly more than the vendor.
            if ah * 0.95 > i.sellPrice * 1.5 + 5000 then
                return { action = "ah", reason = string.format("sells for about %s on the AH",
                    GetCoinTextureString and GetCoinTextureString(math.floor(ah)) or ah) }
            end
        else
            return { action = "ah", reason = "tradeable " .. (i.quality >= 3 and "rare" or "uncommon")
                .. " gear: check the AH before vendoring" }
        end
    end
    return { action = "sell", reason = "not better than your gear for any role" }
end)
