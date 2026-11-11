-- What's worth knowing about a quest before you walk to its giver, which
-- Questie doesn't say. Flow's own notes from play (mostly WoW: Forever's new
-- quests), not copied from any addon.
--   * Where the giver is, when it's a trek: "deep in Palemane Rock".
--   * What the giver wants you to carry first. While you don't have it, the
--     pickup waits: off the route, listed in the Flow Router with the reason.
--   * Escort quests (any, from Questie's "Escort ..." objective): the giver
--     may be away walking another player out, for a few minutes.
--
--   ns:Register("questNeed", <quest ID>, {
--       where = "deep in Palemane Rock", -- shown after the stop's name
--       note  = "...",                   -- first line of the stop's details
--       tool  = "Fishing",               -- carry that profession's tool (any fishing pole)
--       item  = 1234,                    -- or carry this item
--   })
local _, ns = ...
local Q = ns.quests

-- The Longwalkers (98430, level 8, Mulgore): an escort from the back of the
-- gnoll cave. A level 10 druid fought 17 gnolls to reach Perith, and he was
-- gone, walking another player out (2026-11-10). (0.35.128 blamed a fishing
-- pole; it was wrong, he needs nothing.)
ns:Register("questNeed", 98430, {
    where = "deep in Palemane Rock",
    note = "Perith Stormhoof is at the back of Palemane Rock, a gnoll cave: expect to fight your way in.",
})

-- An escort quest's note, from Questie's event objective ("Escort Perith
-- Stormhoof out of Palemane Rock"), or nil for other quests.
function Q.EscortNote(raw, giver)
    local te = type(raw) == "table" and raw.triggerEnd
    local text = type(te) == "table" and te[1]
    if type(text) ~= "string" or not text:lower():find("escort", 1, true) then return nil end
    return string.format("Escort quest: if another player is escorting %s, they're away for a few minutes. "
        .. "Wait by their spot, or come back later.", giver or "the giver")
end

-- What you still need for a quest, as text ("a Fishing Pole"), and who sells
-- it (a list of NPC names, or nil); nil when you have it all. `has` answers
-- from the game, or stand-ins in tests:
--   has.tool(prof) -> name of the missing tool, sellers (nil when you carry one)
--   has.item(id) -> true when you carry it;  has.itemName(id) -> its name
function Q.NeedMissing(need, has)
    if not need then return nil end
    if need.tool then
        local name, sellers = has.tool(need.tool)
        if name then return "a " .. name, sellers end
    end
    if need.item and not has.item(need.item) then
        return (has.itemName and has.itemName(need.item)) or ("item " .. need.item), nil
    end
    return nil
end

-- A pickup stop with what's worth knowing: "(escort, deep in Palemane Rock)"
-- after its name, the notes first in its details, and blockedBy while
-- something it needs is missing. `escort` is Q.EscortNote's text or nil.
function Q.ApplyNeed(goal, need, missing, sellers, escort)
    local tags, notes = {}, {}
    if escort then tags[#tags + 1] = "escort" end
    if need and need.where then tags[#tags + 1] = need.where end
    if #tags > 0 then goal.text = (goal.text or "") .. " (" .. table.concat(tags, ", ") .. ")" end
    if need and need.note then notes[#notes + 1] = need.note end
    if escort then notes[#notes + 1] = escort end
    if #notes > 0 then
        goal.details = goal.details or {}
        for i = #notes, 1, -1 do table.insert(goal.details, 1, notes[i]) end
    end
    if missing then
        local who = sellers and #sellers > 0
            and (" (sold by " .. table.concat({ sellers[1], sellers[2] }, " or ") .. ")") or ""
        goal.blockedBy = "needs " .. missing .. " first" .. who
    end
    return goal
end

-- The game's answers. A tool: the Fishing guide's pole (any pole counts),
-- via the skill planner, which also watches your bags for it. Can't tell:
-- nothing is held back.
local gameHas = {
    tool = function(prof)
        local SP = ns.skillPlan
        if not (SP and SP.ToolGoal) then return nil end
        local tool, name = SP:ToolGoal(prof)
        if tool then return name or prof .. " tool", tool.npcs end
        return nil
    end,
    item = function(id)
        return ns.api.Count(id) > 0 or (IsEquippedItem and IsEquippedItem(id)) or false
    end,
    itemName = function(id) return ns.api.ItemInfo and ns.api.ItemInfo(id) end,
}

-- Pickups waiting for something: looked at again when your bags or gear
-- change, so the stop comes back as soon as you have it.
local waiting = {}
-- `raw` is Questie's quest (for the escort check), `giver` its giver's name.
function Q:PickupNeed(goal, id, raw, giver)
    local need = ns:Get("questNeed", id)
    local escort = Q.EscortNote(raw, giver)
    if not (need or escort) then return goal end
    local missing, sellers
    if need then missing, sellers = Q.NeedMissing(need, gameHas) end
    waiting[id] = missing and need or nil
    return Q.ApplyNeed(goal, need, missing, sellers, escort)
end

local function recheck()
    for id, need in pairs(waiting) do
        local ok, missing = pcall(Q.NeedMissing, need, gameHas)
        if ok and not missing then
            waiting[id] = nil
            if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("a quest need met") end
            return
        end
    end
end
ns:On("BAG_UPDATE_DELAYED", recheck)
ns:On("PLAYER_EQUIPMENT_CHANGED", recheck)
