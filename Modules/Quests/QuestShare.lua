-- Quest sharing in a party, using what Flow players tell each other about
-- their quest logs (Nav/PartyHelp.lua):
--   * A quest you pick up is shared with the party when someone with Flow
--     doesn't have it yet (or someone without Flow could use it).
--   * When a Flow player joins, or their quest list comes in, the quests
--     you have and they don't are shared one at a time, a few seconds apart.
--   * Quests a party member shares with you are accepted for you (escort
--     quests they start too), unless your quest log is full.
-- The game decides who can take a quest ("not eligible", "already has it");
-- each quest is offered to each person once per group. Out of combat only.
-- On by default; the box in /flow settings, or /flow share on|off.

local _, ns = ...
local QS = {}
ns.questShare = QS

local GAP = 4          -- seconds between two shares (each one is a popup for them)
local queue, queued = {}, {}
local offered = {}     -- [name] = { [questId] = true }: shared with them already

function QS.Enabled() return ns.db.quests.share ~= false end

-------------------------------------------------------------------------------
-- Who has what
-------------------------------------------------------------------------------

-- Flow players in your group and their quests: { [name] = { [id] = true } }.
local function known()
    local out = {}
    for name, prog in pairs(ns.partyHelp and ns.partyHelp.All() or {}) do
        out[name] = {}
        for id in pairs(prog) do out[name][id] = true end
    end
    return out
end

local function groupSize()
    if GetNumGroupMembers then return GetNumGroupMembers() or 0 end
    if GetNumPartyMembers then return (GetNumPartyMembers() or 0) + 1 end
    return 0
end

-- Should quest `id` be shared? Yes if a Flow player lacks it (and hasn't
-- been offered it), or, for a quest you just picked up, if someone in the
-- group isn't using Flow (they might want it too).
--   members: { [name] = { [id] = true } }, others: group members without Flow
--   canTake(name, id): false when they can't take it yet (level too low)
function QS.ShouldShare(id, members, others, offeredTo, justAccepted, canTake)
    for name, quests in pairs(members) do
        if not quests[id] and not (offeredTo[name] and offeredTo[name][id])
            and (not canTake or canTake(name, id)) then
            return true
        end
    end
    return justAccepted and others > 0 or false
end

-- Too low a level for it (Questie's required level vs theirs): don't offer.
function QS.CanTake(name, id)
    local level = UnitLevel and UnitLevel(name)
    local q = ns.quests:QuestieGet("GetQuest", id)
    local need = q and q.requiredLevel
    return not (need and level and level > 0 and need > level)
end

local function pushable(id)
    if C_QuestLog and C_QuestLog.IsPushableQuest then
        local ok, yes = pcall(C_QuestLog.IsPushableQuest, id)
        if ok then return yes == true end
    end
    return true   -- (older clients: the game says if it can't be shared)
end

-------------------------------------------------------------------------------
-- Sharing (one at a time)
-------------------------------------------------------------------------------

-- Share one quest from your log with the party, then put the quest log's
-- selection back where it was.
local function push(id)
    if C_QuestLog and C_QuestLog.SetSelectedQuest and QuestLogPushQuest then
        local prev = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
        C_QuestLog.SetSelectedQuest(id)
        QuestLogPushQuest()
        if prev and prev ~= id then C_QuestLog.SetSelectedQuest(prev) end
        return true
    elseif GetQuestLogIndexByID and SelectQuestLogEntry and QuestLogPushQuest then
        local index = GetQuestLogIndexByID(id)
        if not index or index == 0 then return false end
        local prev = GetQuestLogSelection and GetQuestLogSelection()
        SelectQuestLogEntry(index)
        QuestLogPushQuest()
        if prev and prev > 0 then SelectQuestLogEntry(prev) end
        return true
    end
    return false
end

local running = false
local function step()
    if #queue == 0 then running = false return end
    if InCombatLockdown() then C_Timer.After(2, step) return end
    local id = table.remove(queue, 1)
    local fresh = queued[id]   -- true: you just picked it up
    queued[id] = nil
    if QS.Enabled() and ns.party:InGroup() and ns.quests:InLog(id) and pushable(id) then
        local members = known()
        if QS.ShouldShare(id, members, math.max(0, groupSize() - 1 - QS.Count(members)), offered, fresh, QS.CanTake) then
            if push(id) then
                for name, quests in pairs(members) do
                    if not quests[id] then offered[name] = offered[name] or {}; offered[name][id] = true end
                end
                ns:Log("share", "shared quest " .. id .. " with the party")
            end
        end
    end
    C_Timer.After(GAP, step)
end

function QS.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- fresh: a quest you just picked up (also offered to group members without Flow).
function QS.Queue(id, fresh)
    if not id then return end
    if queued[id] ~= nil then queued[id] = queued[id] or fresh and true or false return end
    queued[id] = fresh and true or false
    queue[#queue + 1] = id
    if not running then running = true; C_Timer.After(1, step) end
end

-- Your quests that the Flow players in the group don't have (and weren't
-- offered): queued to share. Called when their quest lists arrive.
function QS:ShareMissing()
    if not (QS.Enabled() and ns.party:InGroup()) then return end
    local members = known()
    for id in pairs(ns.quests:LogIds()) do
        if QS.ShouldShare(id, members, 0, offered, false, QS.CanTake) and pushable(id) then QS.Queue(id, false) end
    end
end

-- A quest you just picked up: share it (after a moment, so a quest someone
-- shared with you isn't shared straight back: their list says they have it).
ns:On("QUEST_ACCEPTED", function(a, b)
    if not (QS.Enabled() and ns.party and ns.party:InGroup()) then return end
    local id = tonumber(b) or tonumber(a)   -- (questLogIndex, questID) on older clients, (questID) on newer
    if id then C_Timer.After(3, function() QS.Queue(id, true) end) end
end)

-------------------------------------------------------------------------------
-- Accepting what your party shares
-------------------------------------------------------------------------------

local function fromParty(unit)
    return UnitExists(unit) and UnitIsPlayer(unit)
        and ((UnitInParty and UnitInParty(unit)) or (UnitInRaid and UnitInRaid(unit)))
end

ns:On("QUEST_DETAIL", function()
    if not QS.Enabled() or not fromParty("npc") then return end
    if ns.quests.FreeSlots and ns.quests:FreeSlots() == 0 then return end
    local title = GetTitleText and GetTitleText()
    ns:Log("share", "accepted a shared quest from " .. tostring(ns.api.Safe(UnitName("npc"))) .. ": " .. tostring(title))
    AcceptQuest()
end)

-- "<name> has started the escort quest ... Join?": yes, for your party.
ns:On("QUEST_ACCEPT_CONFIRM", function(name)
    if not QS.Enabled() or not ConfirmAcceptQuest then return end
    if not (name and ((UnitInParty and UnitInParty(name)) or (UnitInRaid and UnitInRaid(name)))) then return end
    ConfirmAcceptQuest()
    if StaticPopup_Hide then pcall(StaticPopup_Hide, "QUEST_ACCEPT") end
end)

-------------------------------------------------------------------------------

-- A new group: forget who was offered what.
ns:On("GROUP_ROSTER_UPDATE", function()
    if ns.party and not ns.party:InGroup() then wipe(offered); wipe(queue); wipe(queued) end
end)

ns.commands.share = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then ns.db.quests.share = (arg == "on") end
    ns:Print("quest sharing in a party (share yours, accept theirs): " .. (QS.Enabled() and "on" or "off")
        .. "  (/flow share on|off)")
end
