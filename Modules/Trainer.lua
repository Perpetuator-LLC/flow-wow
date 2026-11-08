-- Training nudges. The rotation helper ignores spells you haven't learned and
-- picks each one up as soon as you learn it. This module tells you when
-- there's something new to learn.

local _, ns = ...

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
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end  -- class trainers only
    local list = {}
    for i = 1, GetNumTrainerServices() do
        local name, category, sub, modern = serviceInfo(i)
        if name and category ~= "header" then
            list[#list + 1] = {
                name = name, sub = sub or "", category = category, modern = modern,
                level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0,
                cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0,
            }
        end
    end
    if #list > 0 then
        ns.db.trainer.services = list
        ns.db.trainer.seenAt = UnitLevel("player")
    end
end

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
