-- Gear scores. Every item tooltip gets a score per role:
--   red = DPS, green = Heal, blue = Tank
-- plus the difference from what you're wearing in that slot, and a verdict:
-- equip it, keep it for another role, or sell it.

local _, ns = ...
local G = ns.gear
local ROLES = { "dps", "heal", "tank" }

local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    -- One-handers compare against the main hand only (paladins can't dual wield).
    -- PLACEHOLDER: dual-wield classes will need { 16, 17 }.
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}

local function itemStats(link)
    if C_Item and C_Item.GetItemStats then return C_Item.GetItemStats(link) or {} end
    if GetItemStats then return GetItemStats(link) or {} end
    return {}
end

local function itemInfo(link)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, _, _, minLevel, _, _, _, equipLoc, _, sellPrice, classID, subclassID, _, _, setID = get(link)
    return equipLoc, classID, subclassID, minLevel, setID, sellPrice
end

-- Builds the item description analyzers and scoring use.
function G:Describe(link)
    local equipLoc, classID, subclassID, minLevel, setID, sellPrice = itemInfo(link)
    if not equipLoc or not SLOTS[equipLoc] then return nil end
    return {
        link = link, stats = itemStats(link), equipLoc = equipLoc,
        classID = classID, subclassID = subclassID, minLevel = minLevel or 0,
        setID = setID, sellPrice = sellPrice or 0, slots = SLOTS[equipLoc],
    }
end

-- Full comparison of an item against what you wear.
-- Returns nil if it isn't gear (or isn't loaded yet), else
-- { item, canUse, scores = {role = n}, diffs = {role = n}, notes }
function G:Compare(link)
    local item = link and self:Describe(link)
    if not item then return nil end
    if not self:CanUse(item) then return { item = item, canUse = false } end
    local scores, notes = self:Score(item)
    local diffs = {}
    for _, role in ipairs(ROLES) do
        diffs[role] = self:RoleDiff(item, role, scores)
    end
    return { item = item, canUse = true, scores = scores, diffs = diffs, notes = notes }
end

-- "Simply better": at least as good in every stat (armor included) and
-- better in at least one. Then it's an upgrade for every role, whatever the
-- weights say (e.g. a belt with only more armor).
function G:Dominates(item, otherLink)
    if not otherLink then
        -- Empty slot: anything with stats beats nothing.
        return next(item.stats) ~= nil
    end
    if not otherLink:find("item:") then return false end
    local other = self:Describe(otherLink)
    if not other then return false end
    -- Only like with like (a belt vs a belt). A shield vs a two-hander isn't
    -- comparable this way: plain weapons may report no stats at all, which
    -- made any shield look "better in every stat".
    local same = item.equipLoc == other.equipLoc
        or (item.equipLoc == "INVTYPE_CHEST" and other.equipLoc == "INVTYPE_ROBE")
        or (item.equipLoc == "INVTYPE_ROBE" and other.equipLoc == "INVTYPE_CHEST")
    if not same then return false end
    local better = false
    local keys = {}
    for k in pairs(item.stats) do keys[k] = true end
    for k in pairs(other.stats) do keys[k] = true end
    for k in pairs(keys) do
        if not k:find("^EMPTY_SOCKET_") then
            local a, b = item.stats[k] or 0, other.stats[k] or 0
            if a < b then return false end
            if a > b then better = true end
        end
    end
    return better
end

-- Score difference for one role, against what this item would replace.
-- Returns diff, and what it was compared with.
local OFFHAND = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }

-- One-hander + shield vs a two-hander. While you wear a two-hander, a
-- one-hander alone looks weak against it (and a shield alone even more): it
-- only replaces it together with an off-hand. So it's valued as a pair with
-- the best partner in your bags for that role (a shield / off-hand for a
-- one-hander, a one-hander for a shield). Returns score, link of the partner.
local MAIN_1H = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local OFF = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }
G.MAIN_1H, G.OFF = MAIN_1H, OFF

local partnerCache, partnerAt = {}, 0
function G:BestPartner(item, role, bagItems)
    -- Bag scan cached for 2 s (bag icons ask once per item and role).
    local group = MAIN_1H[item.equipLoc] and "off" or "main"
    if not bagItems then
        if GetTime() - partnerAt > 2 then wipe(partnerCache); partnerAt = GetTime() end
        local c = partnerCache[role .. group]
        if c then return c[1], c[2] end
    end
    local want = MAIN_1H[item.equipLoc] and OFF or (OFF[item.equipLoc] and MAIN_1H) or nil
    if not want then return nil end
    local best, bestLink
    local function consider(link)
        local other = self:Describe(link)
        if other and want[other.equipLoc] and self:CanUse(other) and (other.minLevel or 0) <= UnitLevel("player") then
            local s = (self:Score(other))[role]
            if not best or s > best then best, bestLink = s, link end
        end
    end
    if bagItems then
        for _, link in ipairs(bagItems) do consider(link) end
    elseif ns.disposition and ns.disposition.EachBagItem then
        ns.disposition:EachBagItem(function(_, _, link) consider(link) end)
    end
    if not bagItems then partnerCache[role .. group] = { best, bestLink } end
    return best, bestLink
end

local function wearingTwoHander(self, role)
    local mh = self:CompareLink(role, 16)
    local mhItem = mh and self:Describe(mh)
    return mhItem and mhItem.equipLoc == "INVTYPE_2HWEAPON"
end

function G:RoleDiff(item, role, scores)
    local base, what = self:EquippedScore(item, role)
    local d = ns:ClassData()
    local rules = d and d.roleRules and d.roleRules[role]
    -- Against a two-hander, a one-hander or shield counts as a pair (see
    -- BestPartner); a role that doesn't use off-hands keeps the one-hander alone.
    local pairBonus, cmp = 0, what
    if (MAIN_1H[item.equipLoc] or OFF[item.equipLoc]) and not (rules and rules.noOffhand) and wearingTwoHander(self, role) then
        local ps, plink = self:BestPartner(item, role)
        if ps then
            pairBonus = ps
            what = (what or "?") .. " (as a pair with " .. plink .. ")"
        end
    end
    local diff = scores[role] + pairBonus - base
    -- Class data can say a role doesn't use an off-hand (Retribution uses
    -- two-handers): then shields/off-hands are never upgrades for it.
    if rules and rules.noOffhand and OFFHAND[item.equipLoc] then
        return math.min(diff, 0), what
    end
    if diff < 0.5 and pairBonus == 0 and (cmp == nil or not cmp:find(" %+ ")) and self:Dominates(item, cmp) then
        diff = 0.5  -- counts as an upgrade
    end
    return diff, what
end

G.ROLES = ROLES

function G:CanUse(item)
    local d = ns:ClassData()
    if not d then return true end
    local allowed = d.proficiency[item.classID]
    if allowed and not allowed[item.subclassID] then return false end
    return true
end

-- Returns { dps = n, heal = n, tank = n }, notes
function G:Score(item)
    local d = ns:ClassData()
    local scores, notes = {}, {}
    for _, role in ipairs(ROLES) do
        local s = 0
        local w = d and d.weights[role] or {}
        for stat, value in pairs(item.stats) do
            s = s + (w[stat] or 0) * value
        end
        scores[role] = s
    end
    for _, fn in ns:Each("gearAnalyzer") do
        local ok, bonus, extra = pcall(fn, item)
        if ok then
            if bonus then
                for _, role in ipairs(ROLES) do scores[role] = scores[role] + (bonus[role] or 0) end
            end
            for _, n in ipairs(extra or {}) do notes[#notes + 1] = n end
        end
    end
    return scores, notes
end

-- The item a role is compared against in a slot: that role's gear set if
-- you have one (see Sets.lua), otherwise what you're wearing.
function G:CompareLink(role, slot)
    if self.sets and self.sets:Has(role) then return self.sets:Link(role, slot) end
    return GetInventoryItemLink("player", slot)
end

-- Score of what you'd be replacing: the weaker of two ring/trinket slots;
-- main + off hand when looking at a two-hander. Empty slots score 0.
-- Returns score, and what it was compared with (a link, or text such as
-- "an empty slot"), for the tooltip.
function G:EquippedScore(item, role)
    local function slotScore(slot)
        local link = self:CompareLink(role, slot)
        if not link then return 0, nil end
        local eq = self:Describe(link)
        if not eq then return 0, link end
        return (self:Score(eq))[role], link
    end
    if item.equipLoc == "INVTYPE_2HWEAPON" then
        local a, la = slotScore(16)
        local b, lb = slotScore(17)
        local what = la and lb and (la .. " + " .. lb) or la or lb
        return a + b, what
    end
    -- Wearing a two-hander: a one-hander or shield would replace it (on its
    -- own), so compare against the two-hander rather than an empty slot.
    -- PLACEHOLDER (combos): value one-hander + shield as a pair.
    local mh = self:CompareLink(role, 16)
    local mhItem = mh and self:Describe(mh)
    if mhItem and mhItem.equipLoc == "INVTYPE_2HWEAPON" and (item.slots[1] == 16 or item.slots[1] == 17) then
        return slotScore(16)
    end
    local worst, worstLink
    for _, slot in ipairs(item.slots) do
        local s, l = slotScore(slot)
        if not worst or s < worst then worst, worstLink = s, l end
    end
    return worst or 0, worstLink
end

-------------------------------------------------------------------------------
-- Tooltip
-------------------------------------------------------------------------------

local function fmtDiff(diff)
    if math.abs(diff) < 0.5 then return "|cffaaaaaa+0|r" end
    if diff > 0 then return string.format("|cff66ff66+%d|r", diff + 0.5) end
    return string.format("|cffff6666%d|r", diff - 0.5)
end

local function isEquipped(link)
    for slot = 1, 19 do
        if GetInventoryItemLink("player", slot) == link then return true end
    end
end

local function addToTooltip(tooltip, link)
    if not link or not ns.db or not ns.db.gear.enabled then return end
    local item = G:Describe(link)
    if not item then return end

    if not G:CanUse(item) then
        tooltip:AddLine("Flow: your class can't use this (sell it)", 1, 0.4, 0.4)
        tooltip:Show()
        return
    end

    local scores, notes = G:Score(item)
    local worn = isEquipped(link)
    local sets = G.sets
    local inSets = sets and sets:RolesContaining(link) or {}

    -- Line 1: the item's own score per role.
    local parts, better = {}, {}
    for _, role in ipairs(ROLES) do
        parts[#parts + 1] = string.format("%s |cff%s%d|r", ns:RoleIcon(role), ns.ROLE_COLOR[role], scores[role] + 0.5)
    end
    tooltip:AddLine("Flow score  " .. table.concat(parts, "   "))

    -- Then one line per thing it's compared with, e.g.
    --   vs [Worn Sword]: DPS +5  Heal -3  Tank +1
    --   vs Tank set [Old Shield]: Tank +12
    -- Roles compared with the same item share a line.
    local groups, order = {}, {}
    for _, role in ipairs(ROLES) do
        local hasSet = sets and sets:Has(role)
        local diff, what = G:RoleDiff(item, role, scores)
        if diff >= 0.5 then better[role] = true end
        if not worn or hasSet then
            local label = (hasSet and (sets:SetFor(role) .. " set ") or "")
                .. (what or "an empty slot")
            if not groups[label] then groups[label] = {}; order[#order + 1] = label end
            table.insert(groups[label], string.format("%s %s", ns:RoleIcon(role, 12), fmtDiff(diff)))
        end
    end
    for _, label in ipairs(order) do
        tooltip:AddLine("  vs " .. label .. ":  " .. table.concat(groups[label], "  "), 0.85, 0.85, 0.85)
    end
    if worn and #order == 0 then
        tooltip:AddLine("  You're wearing this.", 0.6, 0.6, 0.6)
    end

    if #inSets > 0 then
        local names = {}
        for _, role in ipairs(inSets) do names[#names + 1] = ns:RoleIcon(role, 12) .. " " .. ns:RoleName(role) end
        tooltip:AddLine("  |cffffd200Keep|r: part of your " .. table.concat(names, " / ") .. " set")
    elseif not worn then
        local main = ns:LevelingRole()
        local tooLow = item.minLevel > UnitLevel("player")
        local verdict
        if better[main] then
            verdict = tooLow
                and string.format("|cff66ff66Upgrade at level %d|r: keep it", item.minLevel)
                or string.format("|cff66ff66Upgrade|r for %s: equip it", ns:RoleIcon(main, 12) .. " " .. ns:RoleName(main))
        else
            local others = {}
            for _, role in ipairs(ROLES) do
                if role ~= main and better[role] then others[#others + 1] = ns:RoleIcon(role, 12) .. " " .. ns:RoleName(role) end
            end
            if #others > 0 and ns.db.gear.keepOffspec then
                verdict = "|cffffd200Keep|r: better for " .. table.concat(others, " / ")
            else
                verdict = "|cffaaaaaaSell|r: not better than what you wear"
            end
        end
        tooltip:AddLine("  " .. verdict)
    end
    for _, n in ipairs(notes) do tooltip:AddLine("  " .. n, 0.6, 0.6, 0.6) end
    tooltip:Show()
end

-- Gear scores, then any other registered item tips:
--   ns:Register("itemTip", key, function(tooltip, link) ... end)
local function onItem(tooltip, link)
    if not link then return end
    pcall(addToTooltip, tooltip, link)
    for _, fn in ns:Each("itemTip") do pcall(fn, tooltip, link) end
end

local function hookTooltips()
    if TooltipDataProcessor and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            if tooltip.GetItem then
                local _, link = tooltip:GetItem()
                onItem(tooltip, link)
            end
        end)
    else
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            -- OnTooltipSetItem can fire twice for one hover; add our lines once.
            tt:HookScript("OnTooltipSetItem", function(self)
                if self.flowDone then return end
                self.flowDone = true
                local _, link = self:GetItem()
                onItem(self, link)
            end)
            tt:HookScript("OnTooltipCleared", function(self) self.flowDone = nil end)
        end
    end
end

ns:OnLoad(function(saved)
    saved.gear = saved.gear or {}
    if saved.gear.enabled == nil then saved.gear.enabled = true end
    if saved.gear.keepOffspec == nil then saved.gear.keepOffspec = true end
    hookTooltips()
end)

ns.commands.gear = function(raw)
    raw = raw or ""
    local arg = raw:lower()
    local g = ns.db.gear
    if arg == "why" then
        -- Every gear item in your bags: its stats, Flow score per role, and the
        -- difference against what it's compared with (also in diagnostics).
        ns:Print("gear check (bags):")
        local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
        local linkOf = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
        for bag = 0, 4 do
            for slot = 1, (numSlots and numSlots(bag) or 0) do
                local link = linkOf(bag, slot)
                local item = link and G:Describe(link)
                if item then
                    local scores = G:Score(item)
                    local stats = {}
                    for k, v in pairs(item.stats) do
                        stats[#stats + 1] = k:gsub("ITEM_MOD_", ""):gsub("_SHORT", ""):gsub("RESISTANCE0_NAME", "ARMOR") .. "=" .. v
                    end
                    print(string.format("  %s (%s) stats: %s", link, item.equipLoc, table.concat(stats, " ")))
                    for _, role in ipairs(ROLES) do
                        local diff, what = G:RoleDiff(item, role, scores)
                        print(string.format("    %s: score %.1f, diff %+.1f vs %s", role, scores[role], diff, tostring(what or "empty")))
                    end
                end
            end
        end
        return
    elseif arg == "on" or arg == "off" then
        g.enabled = (arg == "on")
        ns:Print("gear scores " .. arg)
    elseif arg:find("^sets") or arg:find("^set ") or arg:find("^save") or arg:find("^forget") then
        -- Pass the original text: set names are case-sensitive.
        G.sets:Command((raw:gsub("^%s*[Ss][Ee][Tt][Ss]", "")))
    elseif arg == "offspec" then
        g.keepOffspec = not g.keepOffspec
        ns:Print("keep gear for other roles: " .. (g.keepOffspec and "yes" or "no, sell it"))
    else
        ns:Print("/flow gear on|off|offspec. Hover any item to see its scores.")
    end
end
