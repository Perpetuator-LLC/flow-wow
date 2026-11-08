-- Training nudges. The rotation helper ignores spells you haven't learned and
-- picks each one up as soon as you learn it. This module tells you when
-- there's something new to learn.

local _, ns = ...
local TR = {}
ns.trainer = TR

-- Is this your class trainer? Not a profession trainer, and not a riding (or
-- other) trainer: one of your class's trainers by name, or what it teaches
-- includes your class's spells. (Kar Stormsinger, the tauren riding trainer,
-- was taken for a druid's class trainer: every trainer that wasn't a
-- profession trainer counted, and his riding lessons replaced the spell list.)
--   services: names it teaches; classSet: { [spell] = true }; classTrainers: names
function TR.IsClassTrainer(name, services, classSet, classTrainers, isTrade)
    if isTrade then return false end
    for _, n in ipairs(classTrainers or {}) do if n == name then return true end end
    for _, s in ipairs(services or {}) do if classSet[s] then return true end end
    return false
end

local function classTrainerCheck(name, services, isTrade)
    local _, class = UnitClass("player")
    return TR.IsClassTrainer(name, services, ns:ClassSpellSet(class),
        ns.places and ns.places:TrainersFor("class:" .. class) or {}, isTrade)
end

local CATEGORIES = { available = true, unavailable = true, used = true, header = true }

-- Classic clients return (name, rankText, category); newer ones, Forever
-- included, return (name, category, icon). Returns name, category, rankText, modern.
local function serviceInfo(i)
    local name, a, b = GetTrainerServiceInfo(i)
    if CATEGORIES[a] then return name, a, nil, true end
    return name, b, a, false
end

local function listAvailable()
    if not GetNumTrainerServices then return end
    local money = GetMoney()
    local any = false
    for i = 1, GetNumTrainerServices() do
        local name, category, sub = serviceInfo(i)
        if category == "available" then
            local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
            local afford = cost <= money
            if not any then ns:Print("you can learn here:") end
            any = true
            print(string.format("  %s%s%s - %s%s|r",
                afford and "|cff66ff66" or "|cffff6666", name,
                (sub and sub ~= "") and (" (" .. sub .. ")") or "",
                GetCoinTextureString and GetCoinTextureString(cost) or tostring(cost),
                afford and "" or " (can't afford)"))
        end
    end
    if not any then ns:Print("nothing new to learn here right now.") end
end

-- Remember what the trainer offers, so the advisor can say "you can train X
-- now" later, using the real list for this game version.
local function record()
    if not GetNumTrainerServices then return end
    local list, names = {}, {}
    for i = 1, GetNumTrainerServices() do
        local name, category, sub, modern = serviceInfo(i)
        if name and category ~= "header" then
            names[#names + 1] = name
            list[#list + 1] = {
                name = name, sub = sub or "", category = category, modern = modern,
                level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0,
                cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0,
            }
        end
    end
    -- Class trainers only (where "go train" errands send you).
    local npc = ns.api.Safe(UnitName("npc"))
    if #list == 0 or not classTrainerCheck(npc, names, IsTradeskillTrainer and IsTradeskillTrainer()) then return end
    ns.db.trainer.npc = npc
    ns.db.trainer.services = list
    ns.db.trainer.seenAt = UnitLevel("player")
end

-- A riding (or other) trainer saved as your class trainer before 0.35.90:
-- forgotten, so the errands use your class's trainers again.
ns:On("PLAYER_LOGIN", function()
    local t = ns.db.trainer
    if not (t and t.npc) then return end
    local names = {}
    for _, s in ipairs(t.services or {}) do names[#names + 1] = s.name end
    if not classTrainerCheck(t.npc, names, false) then
        ns:Log("trainer", "forgot " .. tostring(t.npc) .. " as your class trainer (not a trainer for your class)")
        t.npc, t.services = nil, nil
    end
end)

ns:OnLoad(function(saved) saved.trainer = saved.trainer or {} end)
-- What your class trainer offers is your character's. The old shared copy
-- goes to the class it lists spells of.
ns:PerCharacter("trainer", { adopt = function(old, ctx)
    local mine = ns:ClassSpellSet(ctx.class)
    for _, s in ipairs(old.services or {}) do
        if mine[s.name] then return old end
    end
    return nil
end })

ns:On("TRAINER_SHOW", function()
    -- Trainer list fills in a moment after the window opens.
    C_Timer.After(0.2, function() pcall(listAvailable); pcall(record) end)
end)

ns:On("TRAINER_UPDATE", function() pcall(record) end)

ns:On("PLAYER_LEVEL_UP", function(level)
    ns:Print(string.format("level %d! Visit your class trainer: you may have new spells or ranks to learn.", level))
end)
