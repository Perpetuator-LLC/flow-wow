-- "Leave junk behind when looting" (off by default). The game's Auto Loot
-- takes everything and can't skip grey items, so while this is on Flow does
-- the auto-looting instead: it takes everything except grey (junk) items,
-- money and quest items always, and closes the window when only junk is
-- left. The game's own Auto Loot is switched off meanwhile and put back as it
-- was when you turn this off. Hold your auto-loot key (Shift) to loot by hand.
-- /flow settings, or /flow loot junk|nojunk.

local _, ns = ...
local L = {}
ns.lootFilter = L

function L.Enabled() return ns.db.loot.skipJunk == true end

-- Take this slot? Junk (grey items) stays; money, currency and quest items
-- are always taken; locked slots (someone else's roll) are left alone.
function L.Take(slotType, quality, isQuestItem, locked)
    if locked then return false end
    if isQuestItem then return true end
    local ITEM = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or LOOT_SLOT_ITEM or 1
    if slotType == ITEM and quality == 0 then return false end
    return true
end

local function setGameAutoLoot(on)
    pcall(SetCVar, "autoLootDefault", on and "1" or "0")
end

function L:SetEnabled(on)
    local d = ns.db.loot
    if on == L.Enabled() then return end
    if on then
        -- Remember whether you auto-looted, then take over from the game.
        local ok, v = pcall(GetCVar, "autoLootDefault")
        d.auto = not (ok and v == "0")
        d.skipJunk = true
        setGameAutoLoot(false)
    else
        d.skipJunk = false
        setGameAutoLoot(d.auto ~= false)
    end
end

local busy = false
local function loot()
    if busy or not L.Enabled() or ns.db.loot.auto == false then return end
    if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then return end   -- by hand this time
    busy = true
    local left, junk = 0, 0
    for i = (GetNumLootItems() or 0), 1, -1 do
        local _, _, _, _, quality, locked, isQuestItem = GetLootSlotInfo(i)
        local slotType = GetLootSlotType and GetLootSlotType(i)
        if L.Take(slotType, quality, isQuestItem, locked) then
            LootSlot(i)
        else
            left = left + 1
            if quality == 0 then junk = junk + 1 end
        end
    end
    -- Only junk left: close the window (the corpse keeps it if you want it later).
    if left > 0 and left == junk then CloseLoot() end
end

ns:On("LOOT_READY", function() pcall(loot) end)
ns:On("LOOT_OPENED", function() pcall(loot) end)
ns:On("LOOT_CLOSED", function() busy = false end)

ns:OnLoad(function(saved)
    saved.loot = saved.loot or {}
end)

-- If the game's Auto Loot got switched back on while this is on, it would
-- take the junk too: switch it off again (once per login).
ns:On("PLAYER_LOGIN", function()
    if not L.Enabled() then return end
    local ok, v = pcall(GetCVar, "autoLootDefault")
    if ok and v == "1" then setGameAutoLoot(false) end
end)

ns.commands.loot = function(arg)
    arg = (arg or ""):lower()
    if arg == "nojunk" or arg == "on" then L:SetEnabled(true)
    elseif arg == "junk" or arg == "off" then L:SetEnabled(false) end
    ns:Print("leave junk behind when looting: " .. (L.Enabled() and "on (Flow loots everything else; hold Shift to loot by hand)" or "off")
        .. "  (/flow loot nojunk|junk)")
end
