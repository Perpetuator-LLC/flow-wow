-- Learns which items your professions use. Every time you open a profession
-- window, Flow reads its recipes and remembers each reagent:
--   db.reagents[itemID] = { [profession] = "first recipe that uses it" }
-- Used by the keep rules (Disposition.lua) so materials you'll craft with
-- aren't sold.

local _, ns = ...
local R = {}
ns.reagents = R

local function itemID(link) return link and tonumber(link:match("item:(%d+)")) end

local function remember(profession, id, recipe)
    if not id or not profession then return end
    local r = ns.db.reagents[id] or {}
    if not r[profession] then r[profession] = recipe or true end
    ns.db.reagents[id] = r
end

-- Classic-style trade skill window.
local function scanClassic()
    if not (GetNumTradeSkills and GetTradeSkillLine) then return false end
    local profession = GetTradeSkillLine()
    if not profession or profession == "UNKNOWN" then return false end
    for i = 1, GetNumTradeSkills() do
        local name, kind = GetTradeSkillInfo(i)
        if kind ~= "header" and GetTradeSkillNumReagents then
            for j = 1, GetTradeSkillNumReagents(i) do
                remember(profession, itemID(GetTradeSkillReagentItemLink(i, j)), name)
            end
        end
    end
    return true
end

-- Modern trade skill UI.
local function scanModern()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeSchematic) then return false end
    local line = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    local profession = line and line.professionName
    if not profession then return false end
    for _, recipeID in ipairs(T.GetAllRecipeIDs() or {}) do
        local ok, s = pcall(T.GetRecipeSchematic, recipeID, false)
        if ok and s then
            for _, slot in ipairs(s.reagentSlotSchematics or {}) do
                for _, r in ipairs(slot.reagents or {}) do remember(profession, r.itemID, s.name) end
            end
        end
    end
    return true
end

local function scan()
    -- Each scanner checks for its own API; whichever this client has runs.
    pcall(scanModern)
    pcall(scanClassic)
    if ns.disposition then ns.disposition:Invalidate() end
end

-- Professions (by name) that use this item, from what Flow has learned.
function R:UsedBy(id)
    return id and ns.db.reagents[id]
end

ns:OnLoad(function(saved) saved.reagents = saved.reagents or {} end)
-- Reagents come from your recipes: per character, and from the old shared
-- data only for professions you have.
ns:PerCharacter("reagents", { later = true, adopt = function(old, _, current)
    local mine = ns.api.ProfessionSet()
    if next(mine) == nil then return false end
    current = current or {}
    for id, uses in pairs(old) do
        for prof, recipe in pairs(type(uses) == "table" and uses or {}) do
            if mine[prof] then
                current[id] = current[id] or {}
                if current[id][prof] == nil then current[id][prof] = recipe end
            end
        end
    end
    return current
end })

for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE" }) do
    ns:On(ev, function() C_Timer.After(0.3, scan) end)
end
