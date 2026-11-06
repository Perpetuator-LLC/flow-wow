-- Skill books and other "+N skill" items: when to use them.
--
-- The first points of a skill are trivial; the last points before a cap are
-- the slow, expensive ones. So a "+2 Mining (up to 15)" book is worth most
-- when used at 13, and is partly wasted at 14 and mostly wasted at 1. Flow
-- spots these items in your bags, tells you to hold them, and tells you the
-- moment to use them (advisor + item tooltip).
--
-- Recognised text (English client), e.g.:
--   "Use: Increases your Mining skill by 2, up to a maximum of 15."
--   "+2 Mining (up to 15)"

local _, ns = ...

-- Skill names Flow knows to look for. Add more here (or from a class file).
local SKILLS = {
    "Mining", "Herbalism", "Skinning", "Blacksmithing", "Engineering", "Alchemy",
    "Leatherworking", "Tailoring", "Enchanting", "Jewelcrafting", "Inscription",
    "First Aid", "Cooking", "Fishing", "Lockpicking",
}

-- rank, max for a skill from the skills window (nil if not learned).
local function skill(name)
    if not GetNumSkillLines then return nil end
    for i = 1, GetNumSkillLines() do
        local n, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not isHeader and n == name then return rank or 0, maxRank or 0 end
    end
end

-- Parses an item's tooltip. Returns { skill, amount, cap } or nil.
local cache = {}
local function booster(link)
    local id = link and tonumber(link:match("item:(%d+)"))
    if not id then return nil end
    if cache[id] ~= nil then return cache[id] or nil end
    local found = false
    for _, l in ipairs(ns.gear:TooltipLines(link)) do
        local text = l.left or ""
        for _, s in ipairs(SKILLS) do
            if text:find(s, 1, true) then
                local amount = tonumber(text:match(s .. " skill by (%d+)"))
                    or tonumber(text:match("%+(%d+)%s+" .. s))
                    or tonumber(text:match(s .. "%s+%+(%d+)"))
                if amount then
                    local cap = tonumber(text:match("up to a maximum of (%d+)"))
                        or tonumber(text:match("maximum of (%d+)"))
                        or tonumber(text:match("up to (%d+)"))
                    found = { skill = s, amount = amount, cap = cap }
                end
            end
            if found then break end
        end
        if found then break end
    end
    cache[id] = found
    return found or nil
end

-- What to do with it right now: "use", "hold", "late" or "learn", plus the
-- best skill to use it at.
local function verdict(b)
    local rank, max = skill(b.skill)
    if not rank then return "learn", nil, nil end
    local cap = b.cap or max
    local best = math.max(0, cap - b.amount)
    if rank >= cap then return "wasted", best, rank end
    if rank == best then return "use", best, rank end
    if rank > best then return "late", best, rank end
    return "hold", best, rank
end

local function advice(link, b)
    local v, best, rank = verdict(b)
    local cap = b.cap and (" (up to " .. b.cap .. ")") or ""
    if v == "learn" then
        return 30, string.format("Hold %s: learn %s first", link, b.skill)
    elseif v == "use" then
        return 65, string.format("Use %s now: %s is %d, the best moment for +%d%s", link, b.skill, rank, b.amount, cap)
    elseif v == "late" then
        return 60, string.format("Use %s now: %s is %d; waiting longer wastes more of it", link, b.skill, rank)
    elseif v == "wasted" then
        return 25, string.format("%s does nothing now (%s %d is at its cap): sell it", link, b.skill, rank)
    end
    return 15, string.format("Hold %s until %s is %d (now %d): the last points are the slow ones", link, b.skill, best, rank)
end

local function bagLinks()
    local out = {}
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local linkOf = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    if not numSlots then return out end
    for bag = 0, 4 do
        for slot = 1, numSlots(bag) or 0 do
            local link = linkOf(bag, slot)
            if link then out[#out + 1] = link end
        end
    end
    return out
end

ns:Register("advisor", "skillBoosters", {
    check = function()
        local out = {}
        for _, link in ipairs(bagLinks()) do
            local b = booster(link)
            if b then
                local importance, text = advice(link, b)
                out[#out + 1] = { importance = importance, text = text, improves = { b.skill } }
            end
        end
        return out
    end,
})

ns:Register("itemTip", "skillBoosters", function(tooltip, link)
    local b = booster(link)
    if not b then return end
    local _, text = advice("it", b)
    tooltip:AddLine("Flow: " .. text, 1, 0.82, 0.25, true)
    tooltip:Show()
end)
