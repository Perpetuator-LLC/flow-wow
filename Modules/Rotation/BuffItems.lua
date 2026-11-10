-- Buff items on the Flow key: elixirs, scrolls and flasks you carry, and a
-- sharpening stone / weightstone / oil for your weapon. Elixirs and the like
-- only when you're about to kill a lot: at a kill or loot stop (quest mobs,
-- farming meat or cloth), or right after a fight, and only when that buff
-- isn't on you already. A stone or oil whenever your weapon has none on it.
-- Always out of combat and not in inns or cities.
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

-- Stones and oils by name too, in case the client files one as something
-- other than an item enhancement (item data on Forever can differ from
-- classic). Only real weapon oils: "Oily Blackmouth", "Fire Oil" and "Oil of
-- Immolation" are not.
local OILS = { "Wizard Oil", "Mana Oil", "^Frost Oil$", "^Shadow Oil$" }
function BI.IsWeaponBuff(name)
    if type(name) ~= "string" then return false end
    if name:find("Sharpening Stone") or name:find("Weightstone") then return true end
    for _, o in ipairs(OILS) do
        if name:find(o) then return true end
    end
    return false
end

-- What a weapon enhancement goes on: sharpening stones on edged weapons,
-- weightstones on blunt ones, oils on anything but a fishing pole.
local EDGED = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [13] = true, [15] = true }
local BLUNT = { [4] = true, [5] = true, [10] = true }
local FISHING_POLE = 20
function BI.FitsWeapon(itemName, weaponSub)
    if not weaponSub or weaponSub == FISHING_POLE then return false end
    itemName = itemName or ""
    if itemName:find("Sharpening Stone") then return EDGED[weaponSub] == true end
    if itemName:find("Weightstone") then return BLUNT[weaponSub] == true end
    return itemName:find("Oil") ~= nil
end

-- The item to use now, or nil. items = { { id, sub, name, spell } },
-- active(spell) -> bool, weaponSub (main-hand subclass), enchanted (it has one),
-- weaponOnly (not about to fight: skip elixirs, scrolls and flasks).
function BI.Pick(items, active, weaponSub, enchanted, weaponOnly)
    if not weaponOnly then
        for _, it in ipairs(items) do
            if BUFF_SUB[it.sub] and it.spell and not active(it.spell) then return it end
        end
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

-- Item names never change: look each one up once (nil until the game has it).
local names = {}
local function nameOf(id)
    local n = names[id]
    if n == nil and A.ItemInfo then
        n = A.ItemInfo(id)
        if n then names[id] = n end
    end
    return n
end

-- Buff items in your bags (usable now). A stone or oil found by its name counts
-- as an item enhancement, whatever the game files it as.
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
                local name = nameOf(id)
                local sub = (classID == 0 and (BUFF_SUB[subID] or subID == ENHANCE_SUB)) and subID
                    or (BI.IsWeaponBuff(name) and ENHANCE_SUB) or nil
                if sub and (not A.IsUsableItem or A.IsUsableItem(id)) then
                    out[#out + 1] = { id = id, sub = sub, name = name, spell = itemSpell(id) }
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

-- A weapon enhancement goes before the rotation's out-of-combat suggestion
-- (a paladin's seal, an aura), or it would only show when the rotation has
-- nothing at all. Not when an enemy is targeted (the opener first) or you're
-- under half health (the heal first). Order 2.5: before bag:learn (3), which
-- isn't urgent and, coming first, would keep this step off the icon.
function BI.WeaponFirst(enemy, health, maxHealth)
    return not enemy and (health or 0) > 0.5 * (maxHealth or 1)
end

local function enemyTargeted()
    return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") or false
end

ns:Register("action", "buff:item", { order = 2.5, get = function(ctx)
    if UnitIsDeadOrGhost("player") or (IsResting and IsResting()) then return nil end
    if ctx and ctx.fishing then return nil end
    local items = carried()
    if #items == 0 then return nil end
    local enchanted = GetWeaponEnchantInfo and GetWeaponEnchantInfo() and true or false
    local killing = BI.Killing(ctx)
    local it = BI.Pick(items, function(spell) return (A.Buff("player", spell)) end, mainHand(), enchanted, not killing)
    if not it then return nil end
    local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id)) or (GetItemIcon and GetItemIcon(it.id))
    local weapon = it.sub == ENHANCE_SUB
    return { type = "item", item = "item:" .. it.id, icon = icon,
             targetSlot = weapon and 16 or nil,
             urgent = weapon and BI.WeaponFirst(enemyTargeted(), UnitHealth("player"), UnitHealthMax("player")) or nil,
             label = (weapon and "Put on your weapon: " or "Use: ") .. (it.name or "buff item"),
             reason = weapon and "Your weapon has no stone or oil on it" or "You're killing here and that buff isn't on" }
end })
