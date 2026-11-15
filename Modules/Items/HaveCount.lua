-- How many of an item you have, on its tooltip.
--
-- "When I hover over an item it should tell me if I have any in my
-- bank / bags / total." (0.35.267)
--
-- One line on every item tooltip, wherever the item is shown (your bags, a
-- vendor, a quest reward, the auction house, a link in chat):
--   You have 52: 12 in your bags, 40 in your bank
--   You have 12 (in your bags)
--   You have 40, all in your bank
-- Nothing when you have none. The bank's count is what Flow saw the last time
-- you had it open (the game only tells add-ons the bank's contents there).
-- Setting: "How many you have, on item tooltips" (Flow Settings, Loot and
-- selling).

local _, ns = ...
local H = {}
ns.haveCount = H

function H.On() return not (ns.db and ns.db.settings and ns.db.settings.haveCount == false) end

-- Pure: the line, or nil when you have none.
function H.Text(bags, bank)
    bags, bank = math.max(0, tonumber(bags) or 0), math.max(0, tonumber(bank) or 0)
    local total = bags + bank
    if total == 0 then return nil end
    if bank == 0 then return string.format("You have %d (in your bags)", total) end
    if bags == 0 then return string.format("You have %d, all in your bank", total) end
    return string.format("You have %d: %d in your bags, %d in your bank", total, bags, bank)
end

-- Bags and bank for an item.
function H.Counts(id)
    local A = ns.api
    local bags = (A and A.Count and A.Count(id)) or 0
    local bank = 0
    local SP = ns.skillPlan
    if SP and SP.BankCount then
        local ok, n = pcall(SP.BankCount, id)
        if ok and type(n) == "number" then bank = n end
    elseif A and A.ItemCount then
        local ok, all = pcall(A.ItemCount, id, true)
        if ok and type(all) == "number" then bank = math.max(0, all - bags) end
    end
    return bags, bank
end

local function addLine(tt, id)
    if not H.On() then return end
    local text = H.Text(H.Counts(id))
    if text then tt:AddLine(text, 0.6, 0.85, 1) end
end
H._addLine = addLine   -- (tests)

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

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "loot",
        label = "How many you have, on item tooltips",
        note = "(bags, bank, total)",
        tip = "A line on every item's tooltip saying how many you have, split between your bags and your bank. "
            .. "The bank's count is from the last time you had it open.",
        get = function() return H.On() end,
        set = function(on)
            ns.db.settings = ns.db.settings or {}
            ns.db.settings.haveCount = on and true or false
        end,
    })
end
