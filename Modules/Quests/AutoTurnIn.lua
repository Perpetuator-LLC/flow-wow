-- Finished quests are turned in for you when you talk to the NPC: Flow picks
-- the finished quest from their list, presses Complete, and takes the reward.
--   * Several rewards to choose from: Flow stops and lets you pick (the big
--     green arrow marks its pick, Gear/QuestRewards.lua).
--   * A quest that takes gold from you: left to you.
--   * Hold Ctrl (or Shift) while you talk to the NPC to do it yourself this time.
-- On by default; the box in /flow settings, or /flow turnin on|off.
--
-- New quests are accepted for you too (since 0.35.106; before, only quests
-- your party shared were): after any turn-ins, Flow opens the NPC's first
-- new quest (not grey, not repeatable) and accepts it. A quest offered any
-- other way (an item that starts one) is accepted too. Not with your quest
-- log full, and not quests another player offers (QuestShare.lua does your
-- party's). Hold Shift to do it yourself. /flow accept on|off.

local _, ns = ...
local AT = {}
ns.autoTurnIn = AT

function AT.AcceptEnabled()
    if ns.db.quests.autoAccept == false then return false end
    if AT.Paused() then return false end   -- (Shift or Ctrl held: yours to do)
    return true
end

-- The first new quest worth opening in an NPC's list
-- ({ { id, trivial, repeatable }, ... }): its position and id, or nil.
-- Grey (trivial) and repeatable quests are left to you.
function AT.PickAvailable(list)
    for i, q in ipairs(list or {}) do
        if not q.trivial and not q.repeatable then return i, q.id end
    end
end

-- Accept the quest on screen? Only when it's on, not one another player
-- offers, and with room in your quest log (nil: can't tell, go ahead).
function AT.ShouldAccept(enabled, fromPlayer, freeSlots)
    return (enabled and not fromPlayer and (freeSlots == nil or freeSlots > 0)) and true or false
end

local function freeSlots() return ns.quests and ns.quests.FreeSlots and ns.quests:FreeSlots() end
local function canTakeMore() return AT.ShouldAccept(AT.AcceptEnabled(), false, freeSlots()) end

function AT.Enabled()
    if ns.db.quests.autoTurnIn == false then return false end
    if AT.Paused() then return false end   -- (Shift or Ctrl held: yours to do)
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

-- The first finished quest in an NPC's list ({ { id, complete, repeatable }, ... }):
-- its position and id, or nil. A repeatable hand-in is left to you.
function AT.PickFinished(list)
    for i, q in ipairs(list or {}) do
        if q.complete and not q.repeatable then return i, q.id end
    end
end

-- Pure: is a quest a repeatable hand-in? flagged: the game's own word for it;
-- rawOf(id) -> the quest as the quest data has it; is(raw) -> repeatable.
-- (0.35.420: "on the Razorhide quests it accepted it twice in a row ... we
-- wasted 1 buff/mats". Only the list of new quests left repeatables alone,
-- and only by the game's flag. With Blood Shards in your bags Mangletooth's
-- blessings can be handed in at once, and every later page went through:
-- Complete, then the reward, then the next one when his window came back.)
function AT.IsRepeat(id, flagged, rawOf, is)
    if flagged then return true end
    if type(id) ~= "number" or not rawOf or not is then return false end
    local raw = rawOf(id)
    return raw ~= nil and is(raw) == true
end
-- The same, from the game's flag and Flow's quest data.
function AT.RepeatNow(id, flagged)
    local R = ns.repeatables
    local ok, yes = pcall(AT.IsRepeat, id, flagged,
        function(i) return ns.quests and ns.quests.QuestieGet and ns.quests:QuestieGet("GetQuest", i) end,
        R and R.Is)
    return ok and yes == true
end
-- On a quest's own page (offered, "have you finished?", the reward): is it a
-- repeatable hand-in? Then it's yours to press. say: tell the player once.
local toldRepeat
local function leftRepeat(say)
    local id = GetQuestID and GetQuestID()
    if not AT.RepeatNow(id) then return false end
    local title = tostring(GetTitleText and GetTitleText())
    ns:Log("quests", "auto turn-in: left to you (a repeatable hand-in): " .. title)
    if say and toldRepeat ~= title then
        toldRepeat = title
        ns:Print(title .. " is a repeatable hand-in: Flow leaves those to you, so nothing is spent that you didn't choose.")
    end
    return true
end

local function log(what) ns:Log("quests", "auto turn-in: " .. what) end

local function logAccept(what) ns:Log("quests", "auto accept: " .. what) end

-- Gossip NPC (the chat window with several options): open a finished quest;
-- with none, open a new one (accepted on the next page, QUEST_DETAIL).
local function gossipTurnIn(G)
    if G and G.GetActiveQuests and G.SelectActiveQuest then
        local list = {}
        for _, q in ipairs(G.GetActiveQuests() or {}) do
            list[#list + 1] = { id = q.questID, complete = q.isComplete, title = q.title, repeatable = AT.RepeatNow(q.questID, q.repeatable) }
        end
        local i, id = AT.PickFinished(list)
        if id then log("opening " .. tostring(list[i].title)); G.SelectActiveQuest(id); return true end
    elseif GetGossipActiveQuests and SelectGossipActiveQuest then
        -- Older clients: name, level, trivial, complete, ... (6 values per quest).
        local raw, list = { GetGossipActiveQuests() }, {}
        for k = 1, #raw, 6 do list[#list + 1] = { id = (k + 5) / 6, complete = raw[k + 3], title = raw[k] } end
        local i = AT.PickFinished(list)
        if i then log("opening " .. tostring(list[i].title)); SelectGossipActiveQuest(i); return true end
    end
end
local function gossipNew(G)
    if G and G.GetAvailableQuests and G.SelectAvailableQuest then
        local list = {}
        for _, q in ipairs(G.GetAvailableQuests() or {}) do
            list[#list + 1] = { id = q.questID, title = q.title, trivial = q.isTrivial,
                                repeatable = AT.RepeatNow(q.questID, q.repeatable or (q.frequency and q.frequency > 0)) }
        end
        local i, id = AT.PickAvailable(list)
        if id then logAccept("opening " .. tostring(list[i].title)); G.SelectAvailableQuest(id) end
    elseif GetGossipAvailableQuests and SelectGossipAvailableQuest then
        -- Older clients: name, level, trivial, frequency, repeatable, legendary, ignored (7 per quest).
        local raw, list = { GetGossipAvailableQuests() }, {}
        for k = 1, #raw, 7 do
            list[#list + 1] = { id = (k + 6) / 7, title = raw[k], trivial = raw[k + 2], repeatable = raw[k + 4] }
        end
        local i = AT.PickAvailable(list)
        if i then logAccept("opening " .. tostring(list[i].title)); SelectGossipAvailableQuest(i) end
    end
end
ns:On("GOSSIP_SHOW", function()
    local G = C_GossipInfo
    if AT.Enabled() and gossipTurnIn(G) then return end
    if canTakeMore() then gossipNew(G) end
end)

-- Quest NPC with a plain list of quests (no gossip): a finished one, else a new one.
ns:On("QUEST_GREETING", function()
    if AT.Enabled() and GetNumActiveQuests and GetActiveTitle and SelectActiveQuest then
        local list = {}
        for i = 1, GetNumActiveQuests() or 0 do
            local title, complete = GetActiveTitle(i)
            list[#list + 1] = { id = i, complete = complete, title = title }
        end
        local i = AT.PickFinished(list)
        if i then log("opening " .. tostring(list[i].title)); SelectActiveQuest(i); return end
    end
    if not (canTakeMore() and GetNumAvailableQuests and GetAvailableTitle and SelectAvailableQuest) then return end
    local list = {}
    for i = 1, GetNumAvailableQuests() or 0 do
        local trivial, frequency, repeatable
        if GetAvailableQuestInfo then trivial, frequency, repeatable = GetAvailableQuestInfo(i) end
        list[#list + 1] = { id = i, title = GetAvailableTitle(i), trivial = trivial,
                            repeatable = repeatable or (type(frequency) == "number" and frequency > 0) }
    end
    local i = AT.PickAvailable(list)
    if i then logAccept("opening " .. tostring(list[i].title)); SelectAvailableQuest(i) end
end)

-- A quest offered to you (from an NPC, or an item that starts one): accept it.
ns:On("QUEST_DETAIL", function()
    local fromPlayer = UnitExists("npc") and UnitIsPlayer("npc") and true or false
    if not AT.ShouldAccept(AT.AcceptEnabled(), fromPlayer, freeSlots()) then return end
    if QuestGetAutoAccept and QuestGetAutoAccept() then return end   -- the game took it already
    if leftRepeat() then return end
    logAccept("accepted " .. tostring(GetTitleText and GetTitleText()))
    AcceptQuest()
end)

-- "Have you finished?": press Complete (not for quests that take your gold).
ns:On("QUEST_PROGRESS", function()
    if not (AT.Enabled() and IsQuestCompletable and IsQuestCompletable()) then return end
    if leftRepeat(true) then return end
    if GetQuestMoneyToGet and (GetQuestMoneyToGet() or 0) > 0 then
        log("left to you (it takes gold): " .. tostring(GetTitleText and GetTitleText()))
        return
    end
    CompleteQuest()
end)

-- The reward page: take it, unless there's a choice to make.
ns:On("QUEST_COMPLETE", function()
    if not AT.Enabled() then return end
    if leftRepeat() then return end
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

ns.commands.accept = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then ns.db.quests.autoAccept = (arg == "on") end
    ns:Print("accept new quests for you: " .. (ns.db.quests.autoAccept == false and "off" or "on")
        .. "  (not grey or repeatable ones; hold Ctrl at the NPC to do it yourself; /flow accept on|off)")
end

ns.commands.turnin = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then ns.db.quests.autoTurnIn = (arg == "on") end
    ns:Print("turn in finished quests for you: " .. (ns.db.quests.autoTurnIn == false and "off" or "on")
        .. "  (hold Ctrl at the NPC to do it yourself; /flow turnin on|off)")
end

-------------------------------------------------------------------------------
-- Hold Ctrl (or Shift) to look first (0.35.400)
--
-- "When I get to Mangletooth and try to talk to him, there's like six quests
-- ... it just automatically goes through the quest. If we hit Control, it
-- would not automatically go into the quest, because I can't pick what
-- quests. I just want to look at them. Show it in the tooltip: hold Control
-- to not auto complete." Shift did this already; Ctrl does now too, and the
-- NPC's tooltip says so for anyone Flow would act at.
-------------------------------------------------------------------------------
-- Pure: is a key held that tells Flow to leave the NPC's quests to you?
function AT.Held(shift, ctrl) return (shift or ctrl) and true or false end
function AT.Paused()
    return AT.Held(IsShiftKeyDown and IsShiftKeyDown() or false, IsControlKeyDown and IsControlKeyDown() or false)
end
AT.TIP = "Flow accepts and hands in quests here for you. Hold Ctrl as you click to look at them yourself."
-- Pure: the tooltip's line for an NPC, or nil. quests: Flow has a step at them
-- to accept or hand in; accept, turnIn: the two settings.
function AT.TipFor(quests, accept, turnIn)
    if not quests or not (accept or turnIn) then return nil end
    return AT.TIP
end

-- The NPCs your route has you accept from or hand in to: { [lower name] = true }.
local npcs, npcsAt = {}, 0
function AT.QuestNpcs()
    local now = GetTime()
    if now - npcsAt < 2 then return npcs end
    npcsAt = now
    wipe(npcs)
    local N = ns.nav
    for _, list in ipairs({ N and N.Goals and N:Goals() or {}, N and N.blockedGoals or {} }) do
        for _, g in ipairs(list) do
            local key = type(g.key) == "string" and g.key or ""
            if g.kind == "accept" or key:find("^pickup:") or key:find(":done$") or key:find(":giver:", 1, true) then
                for _, name in ipairs(type(g.npcs) == "table" and g.npcs or {}) do
                    if type(name) == "string" then npcs[name:lower()] = true end
                end
            end
        end
    end
    return npcs
end
local function addTip(tt)
    if not (tt and tt.GetUnit) then return end
    local ok, _, unit = pcall(tt.GetUnit, tt)
    unit = ok and ns.api.Safe(unit) or nil
    if type(unit) ~= "string" or ns.api.Safe(UnitIsPlayer(unit)) then return end
    local name = ns.api.Safe(UnitName(unit))
    if type(name) ~= "string" then return end
    local line = AT.TipFor(AT.QuestNpcs()[name:lower()] == true, ns.db.quests.autoAccept ~= false, ns.db.quests.autoTurnIn ~= false)
    if line then tt:AddLine(line, 0.6, 0.8, 1, true) end
end
AT._addTip = addTip   -- (tests)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt ~= GameTooltip then return end
        pcall(addTip, tt)
    end)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(addTip, tt) end)
end
