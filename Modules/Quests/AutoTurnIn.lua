-- Finished quests are turned in for you when you talk to the NPC: Flow picks
-- the finished quest from their list, presses Complete, and takes the reward.
--   * Several rewards to choose from: Flow stops and lets you pick (the big
--     green arrow marks its pick, Gear/QuestRewards.lua).
--   * A quest that takes gold from you: left to you.
--   * Hold Shift while you talk to the NPC to do it yourself this time.
-- On by default; the box in /flow settings, or /flow turnin on|off.

local _, ns = ...
local AT = {}
ns.autoTurnIn = AT

function AT.Enabled()
    if ns.db.quests.autoTurnIn == false then return false end
    if IsShiftKeyDown and IsShiftKeyDown() then return false end
    return true
end

-- Which reward to take: 0 when there's nothing to choose, 1 when there's
-- only one, nil (you choose) when there are several.
function AT.Reward(nChoices)
    nChoices = nChoices or 0
    if nChoices == 0 then return 0 end
    if nChoices == 1 then return 1 end
    return nil
end

-- The first finished quest in an NPC's list ({ { id, complete }, ... }):
-- its position and id, or nil.
function AT.PickFinished(list)
    for i, q in ipairs(list or {}) do
        if q.complete then return i, q.id end
    end
end

local function log(what) ns:Log("quests", "auto turn-in: " .. what) end

-- Gossip NPC (the chat window with several options): open a finished quest.
ns:On("GOSSIP_SHOW", function()
    if not AT.Enabled() then return end
    local G = C_GossipInfo
    if G and G.GetActiveQuests and G.SelectActiveQuest then
        local list = {}
        for _, q in ipairs(G.GetActiveQuests() or {}) do
            list[#list + 1] = { id = q.questID, complete = q.isComplete, title = q.title }
        end
        local i, id = AT.PickFinished(list)
        if id then log("opening " .. tostring(list[i].title)); G.SelectActiveQuest(id) end
    elseif GetGossipActiveQuests and SelectGossipActiveQuest then
        -- Older clients: name, level, trivial, complete, ... (6 values per quest).
        local raw, list = { GetGossipActiveQuests() }, {}
        for k = 1, #raw, 6 do list[#list + 1] = { id = (k + 5) / 6, complete = raw[k + 3], title = raw[k] } end
        local i = AT.PickFinished(list)
        if i then log("opening " .. tostring(list[i].title)); SelectGossipActiveQuest(i) end
    end
end)

-- Quest NPC with a plain list of quests (no gossip).
ns:On("QUEST_GREETING", function()
    if not (AT.Enabled() and GetNumActiveQuests and GetActiveTitle and SelectActiveQuest) then return end
    local list = {}
    for i = 1, GetNumActiveQuests() or 0 do
        local title, complete = GetActiveTitle(i)
        list[#list + 1] = { id = i, complete = complete, title = title }
    end
    local i = AT.PickFinished(list)
    if i then log("opening " .. tostring(list[i].title)); SelectActiveQuest(i) end
end)

-- "Have you finished?": press Complete (not for quests that take your gold).
ns:On("QUEST_PROGRESS", function()
    if not (AT.Enabled() and IsQuestCompletable and IsQuestCompletable()) then return end
    if GetQuestMoneyToGet and (GetQuestMoneyToGet() or 0) > 0 then
        log("left to you (it takes gold): " .. tostring(GetTitleText and GetTitleText()))
        return
    end
    CompleteQuest()
end)

-- The reward page: take it, unless there's a choice to make.
ns:On("QUEST_COMPLETE", function()
    if not AT.Enabled() then return end
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    local pick = AT.Reward(n)
    local title = GetTitleText and GetTitleText()
    if not pick then
        ns:Print("pick your reward for " .. tostring(title) .. " (the green arrow is Flow's pick for you)")
        log("waiting for you to pick a reward: " .. tostring(title))
        return
    end
    log("turned in " .. tostring(title))
    GetQuestReward(pick)
end)

ns.commands.turnin = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then ns.db.quests.autoTurnIn = (arg == "on") end
    ns:Print("turn in finished quests for you: " .. (ns.db.quests.autoTurnIn == false and "off" or "on")
        .. "  (hold Shift at the NPC to do it yourself; /flow turnin on|off)")
end
