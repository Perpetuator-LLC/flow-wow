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
    local _, _, quality, _, minLevel, _, _, _, equipLoc, _, sellPrice, classID, subclassID = get(link)
    return quality, minLevel, sellPrice, classID, equipLoc, subclassID
end

-- Icons shown in bags for "keep" reasons.
D.ICON_QUEST = "Interface\\GossipFrame\\AvailableQuestIcon"
local PROF_ICON = {
    ["Mining"] = "Interface\\Icons\\Trade_Mining",
    ["Blacksmithing"] = "Interface\\Icons\\Trade_BlackSmithing",
    ["First Aid"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    ["Cooking"] = "Interface\\Icons\\INV_Misc_Food_15",
    ["Fishing"] = "Interface\\Icons\\Trade_Fishing",
    ["Tailoring"] = "Interface\\Icons\\Trade_Tailoring",
    ["Leatherworking"] = "Interface\\Icons\\Trade_LeatherWorking",
    ["Alchemy"] = "Interface\\Icons\\Trade_Alchemy",
    ["Engineering"] = "Interface\\Icons\\Trade_Engineering",
    ["Enchanting"] = "Interface\\Icons\\Trade_Engraving",
    ["Herbalism"] = "Interface\\Icons\\Trade_Herbalism",
    ["Skinning"] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
}
D.PROF_ICON = PROF_ICON

-- Trade goods (item class 7) subclass -> professions that use that kind of material.
local MATERIAL = {
    [1] = { "Engineering" }, [2] = { "Engineering" }, [3] = { "Engineering" },
    [5] = { "First Aid", "Tailoring" },
    [6] = { "Leatherworking" },
    [7] = { "Mining", "Blacksmithing", "Engineering" },
    [8] = { "Cooking" },
    [9] = { "Alchemy" },
    [12] = { "Enchanting" },
}
local MATERIAL_NAME = { [1] = "parts", [2] = "explosives", [3] = "devices", [5] = "cloth",
    [6] = "leather", [7] = "metal & stone", [8] = "meat", [9] = "herbs", [12] = "enchanting materials" }

-- Bag slot holding an item (first match), for tooltips.
function D:FindInBags(link)
    local id = tonumber(link:match("item:(%d+)"))
    local found
    self:EachBagItem(function(bag, slot, l)
        if not found and (l == link or tonumber(l:match("item:(%d+)")) == id) then found = { bag, slot, l } end
    end)
    if found then return found[1], found[2], found[3] end
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
    local quality, minLevel, sellPrice, classID, _, subclassID = itemInfo(link)
    if quality == nil then return nil end  -- not loaded yet
    return {
        bag = bag, slot = slot, link = link, id = tonumber(link:match("item:(%d+)")),
        quality = quality, minLevel = minLevel or 0, sellPrice = sellPrice or 0, classID = classID,
        subclassID = subclassID,
        bound = self:IsBound(bag, slot),
        gear = ns.gear and ns.gear:Compare(link) or nil,
    }
end

-- Rules whose "keep" is a fallback, not a reason worth listing with others.
local GENERIC = { notGear = true, unneededGear = true }
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
    local list = rules()
    for idx, e in ipairs(list) do
        local ok, v = pcall(e.r.check, item)
        if ok and v then
            v.rule = e.key
            v.item = item
            -- Keeping it: list every reason, not just the first (Linen Cloth
            -- can be for a class quest AND First Aid bandages).
            if v.action == "keep" and v.reason and not GENERIC[e.key] then
                local reasons, seen = { v.reason }, { [v.reason] = true }
                for j = idx + 1, #list do
                    local e2 = list[j]
                    if not GENERIC[e2.key] then
                        local ok2, w = pcall(e2.r.check, item)
                        if ok2 and w and w.action == "keep" and w.reason and not seen[w.reason] then
                            reasons[#reasons + 1] = w.reason
                            seen[w.reason] = true
                            v.icon = v.icon or w.icon
                        end
                    end
                end
                v.reasons = reasons
                v.reason = table.concat(reasons, "; ")
            end
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
    if i.classID == 12 then return { action = "keep", reason = "quest item", icon = D.ICON_QUEST } end
end)

-- Needed by a quest you're on, or one coming up within a few levels.
reg("questNeeds", 6, function(i)
    local need = ns.quests and ns.quests.QuestItems and ns.quests:QuestItems()[i.id]
    if need then
        return { action = "keep", icon = D.ICON_QUEST,
            reason = need.inLog and ("for your quest: " .. (need.quest or "?"))
                or string.format("for an upcoming quest: %s (level %d)", need.quest or "?", need.level or 0) }
    end
end)

-- Class data: items to hold for class quests, e.g. Linen Cloth for Redemption.
reg("classKeep", 7, function(i)
    local d = ns:ClassData()
    local k = d and d.keepItems and d.keepItems[i.id]
    if k and (not k.untilLevel or UnitLevel("player") < k.untilLevel) then
        return { action = "keep", reason = k.why, icon = D.ICON_QUEST }
    end
end)

-- Materials your professions use: exact recipes once you've opened that
-- profession's window, otherwise by kind of material.
reg("professionMaterial", 25, function(i)
    -- Every profession you have that uses it (recipes you've seen in a
    -- profession window, Flow's levelling guides, then by kind of material).
    local found, order, planned = {}, {}, {}
    for _, p in ipairs(ns:ProfessionPlan() or {}) do planned[p.name] = true end
    local function add(prof, what)
        -- Professions you have, and ones in your plan you haven't learned yet.
        if not (ns.api.Skill(prof) or planned[prof]) or found[prof] then return end
        found[prof] = what or true
        order[#order + 1] = prof
    end
    for prof, recipe in pairs(ns.reagents and ns.reagents:UsedBy(i.id) or {}) do
        add(prof, type(recipe) == "string" and recipe or nil)
    end
    for prof, g in ns:Each("profGuide") do
        for _, step in ipairs(g.steps or {}) do
            if step.mats and step.mats[i.id] then add(prof, step.recipe) end
        end
    end
    if i.classID == 7 and MATERIAL[i.subclassID] then
        for _, prof in ipairs(MATERIAL[i.subclassID]) do add(prof, MATERIAL_NAME[i.subclassID]) end
    end
    if #order == 0 then return nil end
    local parts = {}
    for _, prof in ipairs(order) do
        local what = found[prof]
        parts[#parts + 1] = "for " .. prof .. (type(what) == "string" and (": " .. what) or "")
    end
    return { action = "keep", icon = PROF_ICON[order[1]], reason = table.concat(parts, "; ") }
end)

-- Crafting materials (trade goods) that none of your professions, learned
-- or planned, use: sell the plain ones, auction the better ones. Quest and
-- class-quest needs were checked before this.
reg("unusedMaterial", 27, function(i)
    if i.classID ~= 7 or i.sellPrice <= 0 then return nil end
    if (i.quality or 1) >= 2 then
        return { action = "ah", reason = "crafting material none of your professions use (worth more at the auction house)" }
    end
    return { action = "sell", reason = "crafting material none of your professions use" }
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
