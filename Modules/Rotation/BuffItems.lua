-- Buff items on the Flow key: elixirs, scrolls and flasks you carry, and a
-- sharpening stone / weightstone / oil for your weapon, when you're about to
-- kill a lot: at a kill or loot stop (quest mobs, farming meat or cloth), or
-- right after a fight. Only when that buff isn't on you already (or your
-- weapon has no stone on it), out of combat, and not in inns or cities.
-- One press uses it (a Flow Action: Rotation/Actions.lua).

local _, ns = ...
local A = ns.api
local BI = {}
ns.buffItems = BI

local RECENT_FIGHT = 45   -- seconds after a fight that still count as "killing here"
local lastFight = -999
ns:On("PLAYER_REGEN_ENABLED", function() lastFight = GetTime() end)

-- Consumable (class 0) kinds that are buffs: 2 elixir, 3 flask, 4 scroll,
-- 6 item enhancement (stones and oils, on your weapon).
local BUFF_SUB = { [2] = true, [3] = true, [4] = true }
local ENHANCE_SUB = 6

-- What a weapon enhancement goes on: sharpening stones on edged weapons,
-- weightstones on blunt ones, oils on anything.
local EDGED = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [13] = true, [15] = true }
local BLUNT = { [4] = true, [5] = true, [10] = true }
function BI.FitsWeapon(itemName, weaponSub)
    if not weaponSub then return false end
    itemName = itemName or ""
    if itemName:find("Sharpening Stone") then return EDGED[weaponSub] == true end
    if itemName:find("Weightstone") then return BLUNT[weaponSub] == true end
    return itemName:find("Oil") ~= nil
end

-- The item to use now, or nil. items = { { id, sub, name, spell } },
-- active(spell) -> bool, weaponSub (main-hand subclass), enchanted (it has one).
function BI.Pick(items, active, weaponSub, enchanted)
    for _, it in ipairs(items) do
        if BUFF_SUB[it.sub] and it.spell and not active(it.spell) then return it end
    end
    if not enchanted then
        for _, it in ipairs(items) do
            if it.sub == ENHANCE_SUB and BI.FitsWeapon(it.name, weaponSub) then return it end
        end
    end
end

local function instant(id)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(id) end
    if GetItemInfoInstant then return GetItemInfoInstant(id) end
end

local function itemSpell(id)
    local get = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not get then return nil end
    local ok, name = pcall(get, id)
    return ok and name or nil
end

-- Buff items in your bags (usable now).
local function carried()
    local out, seen = {}, {}
    local C = C_Container
    local slots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
    local itemAt = (C and C.GetContainerItemID) or GetContainerItemID
    if not (slots and itemAt) then return out end
    for bag = 0, 4 do
        for slot = 1, (slots(bag) or 0) do
            local id = itemAt(bag, slot)
            if id and not seen[id] then
                seen[id] = true
                local _, _, _, _, _, classID, subID = instant(id)
                if classID == 0 and (BUFF_SUB[subID] or subID == ENHANCE_SUB)
                    and (not A.IsUsableItem or A.IsUsableItem(id)) then
                    out[#out + 1] = { id = id, sub = subID, name = A.ItemInfo and A.ItemInfo(id), spell = itemSpell(id) }
                end
            end
        end
    end
    return out
end

-- About to kill a lot: at a kill / loot stop, or just after a fight.
function BI.Killing(ctx, now)
    if IsResting and IsResting() then return false end
    local g = ctx and ctx.goal
    local kind = g and (g.kind or (ns.nav and ns.nav:StopKind(g)))
    if ctx and ctx.at and (kind == "kill" or kind == "collect") then return true end
    return (now or GetTime()) - lastFight < RECENT_FIGHT
end

local function mainHand()
    local id = GetInventoryItemID and GetInventoryItemID("player", 16)
    if not id then return nil end
    local _, _, _, _, _, classID, subID = instant(id)
    return classID == 2 and subID or nil
end

ns:Register("action", "buff:item", { order = 3, get = function(ctx)
    if UnitIsDeadOrGhost("player") or not BI.Killing(ctx) then return nil end
    local items = carried()
    if #items == 0 then return nil end
    local enchanted = GetWeaponEnchantInfo and GetWeaponEnchantInfo() and true or false
    local it = BI.Pick(items, function(spell) return (A.Buff("player", spell)) end, mainHand(), enchanted)
    if not it then return nil end
    local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id)) or (GetItemIcon and GetItemIcon(it.id))
    return { type = "item", item = "item:" .. it.id, icon = icon,
             targetSlot = it.sub == ENHANCE_SUB and 16 or nil,
             label = (it.sub == ENHANCE_SUB and "Put on your weapon: " or "Use: ") .. (it.name or "buff item"),
             reason = "You're killing here and that buff isn't on" }
end })
