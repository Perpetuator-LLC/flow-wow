-- What some quests need before their giver will offer them, which Questie
-- doesn't say. Flow's own notes from play (mostly WoW: Forever's new
-- quests), not copied from any addon. While you don't have what a quest
-- needs, its pickup waits: it stays off the route and the Flow Router lists
-- it with the reason. Its stop also says where the giver is when that's
-- worth knowing before you set off (a cave full of mobs).
--
--   ns:Register("questNeed", <quest ID>, {
--       tool  = "Fishing",               -- carry that profession's tool (any fishing pole)
--       item  = 1234,                    -- or carry this item
--       where = "deep in Palemane Rock", -- shown after the stop's name
--       note  = "...",                   -- first line of the stop's details
--   })
local _, ns = ...
local Q = ns.quests

-- The Longwalkers (98430, level 8, Mulgore): Perith Stormhoof offers nothing
-- until you have a fishing pole, and he's at the back of the gnoll cave. A
-- level 10 druid fought 17 gnolls to reach him without one (2026-11-10).
ns:Register("questNeed", 98430, {
    tool = "Fishing",
    where = "deep in Palemane Rock",
    note = "Perith Stormhoof is at the back of Palemane Rock, a gnoll cave: expect to fight your way in. "
        .. "He only offers the quest once you have a fishing pole.",
})

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

-- A pickup stop with its quest's needs: where the giver is after its name,
-- the note first in its details, and blockedBy while something's missing.
function Q.ApplyNeed(goal, need, missing, sellers)
    if not need then return goal end
    if need.where then goal.text = (goal.text or "") .. " (" .. need.where .. ")" end
    if need.note then
        goal.details = goal.details or {}
        table.insert(goal.details, 1, need.note)
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
function Q:PickupNeed(goal, id)
    local need = ns:Get("questNeed", id)
    if not need then return goal end
    local missing, sellers = Q.NeedMissing(need, gameHas)
    waiting[id] = missing and need or nil
    return Q.ApplyNeed(goal, need, missing, sellers)
end

local function recheck()
    for id, need in pairs(waiting) do
        local ok, missing = pcall(Q.NeedMissing, need, gameHas)
        if ok and not missing then
            waiting[id] = nil
            if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect() end
            return
        end
    end
end
ns:On("BAG_UPDATE_DELAYED", recheck)
ns:On("PLAYER_EQUIPMENT_CHANGED", recheck)
