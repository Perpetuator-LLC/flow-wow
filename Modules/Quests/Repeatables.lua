-------------------------------------------------------------------------------
-- Flow - Quests/Repeatables.lua
-- Repeatable hand-ins are one optional step, not a row of quests (0.35.411).
--
-- "I'm over in Camp Taurajo and it is telling me to do this series of quests
-- at Mangletooth ... it just wants to turn in all of them, and they should be
-- specific. I want Flow to let me know I have a possible action here, but
-- putting 5/6 different quests on my route that I have to skip is super
-- annoying."
--
-- Mangletooth's six are repeatable: each takes Blood Shards and gives a
-- buff, as often as you like. Flow listed them as six quests to pick up, in
-- an order that meant nothing. Now, for any NPC:
--   * a repeatable quest (the quest data flags it; a daily is not one) is
--     never a step to pick up;
--   * an NPC's repeatables together are ONE optional step at that NPC: on
--     your route only when it's on your way, never something the route waits
--     for;
--   * only while you have what they take (in your bags, or in your bank:
--     then the step says so and Flow Banker offers to take it out);
--   * the step names the one that suits the role you play, where Flow knows
--     what each gives (the registry below), and lists the rest;
--   * Flow never accepts a repeatable for you (AutoTurnIn.lua): you pick.
--
--   ns:Register("repeatBuff", questID, { gives = "Strength", roles = { "dps", "tank" } })
-- roles: the roles it's for, best first. What's registered here is from
-- classic and not checked on WoW: Forever: the step says "check its text".
-------------------------------------------------------------------------------

local _, ns = ...
local R = {}
ns.repeatables = R

-- Mangletooth, Camp Taurajo (Blood Shards).
for id, def in pairs({
    [5042] = { gives = "Strength", roles = { "tank", "dps" } },        -- Agamaggan's Strength
    [5043] = { gives = "Agility", roles = { "dps", "tank" } },         -- Agamaggan's Agility
    [5044] = { gives = "Intellect", roles = { "heal" } },              -- Wisdom of Agamaggan
    [5045] = { gives = "Spirit", roles = { "heal" } },                 -- Rising Spirit
    [5046] = { gives = "damage to those who hit you", roles = { "tank" } },   -- Razorhide
    [889] = { gives = "run speed", roles = {} },                       -- Spirit of the Wind
}) do ns:Register("repeatBuff", id, def) end

-- Pure: is a quest repeatable (and not a daily)? raw: the quest as the data has it.
function R.Is(raw)
    if type(raw) ~= "table" then return false end
    if raw.IsRepeatable == true then return true end
    local flags = tonumber(raw.specialFlags)
    if flags and bit and bit.band(flags, 1) ~= 0 then return true end
    return false
end

-- Pure: the items a quest takes: { itemID, ... } (its item objectives and what it needs first).
function R.Takes(raw)
    local out, seen = {}, {}
    local function add(id) if type(id) == "number" and id > 0 and not seen[id] then seen[id] = true; out[#out + 1] = id end end
    for _, od in pairs(type(raw) == "table" and type(raw.ObjectiveData) == "table" and raw.ObjectiveData or {}) do
        if type(od) == "table" and od.Type == "item" then add(od.Id) end
    end
    for _, id in ipairs(type(raw) == "table" and type(raw.requiredSourceItems) == "table" and raw.requiredSourceItems or {}) do add(id) end
    return out
end

-- Pure: the one for your role: the quest whose registered roles name yours
-- earliest; nil when none is for it. quests: { { id, name } }; buffOf(id) -> def.
function R.Pick(quests, role, buffOf)
    local best, rank
    for _, q in ipairs(quests or {}) do
        local def = buffOf(q.id)
        for i, r in ipairs(def and def.roles or {}) do
            if r == role and (not rank or i < rank) then best, rank = q, i end
        end
    end
    return best
end

-- Pure: the step's words.
--   who: the NPC; n: how many repeatables; best: { name, gives } or nil;
--   carried, banked: how many of what they take you have in bags / in the bank; item: its name
function R.Text(who, n, best, carried, banked, item)
    local have = ""
    if (carried or 0) > 0 then have = string.format(" (you carry %d %s)", carried, tostring(item or "of what they take"))
    elseif (banked or 0) > 0 then have = string.format(" (%d %s in your bank)", banked, tostring(item or "of what they take")) end
    if best then
        return string.format("%s: %s for %s%s", tostring(who), tostring(best.name), tostring(best.gives or "a buff"), have)
    end
    return string.format("%s: %d repeatable hand-in%s%s", tostring(who), n, n == 1 and "" or "s", have)
end

-- Pure: one NPC's repeatables as a step, or nil when you have nothing they take.
--   group: { who, quests = { { id, name, level, takes = { ids } } }, points }
--   count(id), bank(id) -> how many; role; buffOf(id); itemName(id)
function R.Step(group, count, bank, role, buffOf, itemName)
    local carried, banked, item = 0, 0, nil
    local seen = {}
    for _, q in ipairs(group.quests) do
        for _, id in ipairs(q.takes or {}) do
            if not seen[id] then
                seen[id] = true
                local c, b = count(id) or 0, bank(id) or 0
                if c + b > 0 and not item then item = id end
                carried, banked = carried + c, banked + b
            end
        end
    end
    -- (Nothing they take is known: the data doesn't say. Then it's offered as it is.)
    local known = next(seen) ~= nil
    if known and carried + banked <= 0 then return nil end
    local best = R.Pick(group.quests, role, buffOf)
    local bestDef = best and buffOf(best.id) or nil
    local details = { string.format("%s has %d repeatable hand-in%s: each takes something from you and gives something back, as often as you like.",
        tostring(group.who), #group.quests, #group.quests == 1 and "" or "s") }
    for _, q in ipairs(group.quests) do
        local def = buffOf(q.id)
        details[#details + 1] = string.format("- %s%s%s", tostring(q.name), def and def.gives and (": " .. def.gives) or "",
            (best and q.id == best.id) and "  <- for the role you play" or "")
    end
    if best then details[#details + 1] = "(What each gives is as in classic: check its text before you hand anything in.)" end
    if carried <= 0 and banked > 0 then details[#details + 1] = "What they take is in your bank: Flow Banker's To sell list has a Take out button for it." end
    details[#details + 1] = "Flow never does these for you: talk to them and pick. It's only on your route when it's on your way."
    local fetch
    if carried <= 0 and banked > 0 and item then fetch = { [item] = 1 } end
    return {
        key = "repeat:" .. tostring(group.who), kind = "accept", optional = true, weight = 1.3,
        points = group.points, npcs = group.who and { group.who } or nil,
        title = tostring(group.who), level = group.quests[1] and group.quests[1].level or nil,
        text = R.Text(group.who, #group.quests, best and { name = best.name, gives = bestDef and bestDef.gives } or nil,
            carried, banked, item and itemName(item) or nil),
        details = details, fetch = fetch, repeatable = true,
    }
end

-- The quests to pick up, sorted: the ordinary ones, and the repeatables by NPC.
--   list: { { id, name, level, raw, starter = { name, spawns } } }
-- -> ordinary ({ q }), groups ({ { who, quests, spawns } })
function R.Split(list, isRepeat, takes)
    local ordinary, groups, byWho = {}, {}, {}
    for _, q in ipairs(list or {}) do
        if isRepeat(q.raw) and q.starter and q.starter.name then
            local g = byWho[q.starter.name]
            if not g then
                g = { who = q.starter.name, quests = {}, spawns = q.starter.spawns }
                byWho[q.starter.name] = g
                groups[#groups + 1] = g
            end
            g.quests[#g.quests + 1] = { id = q.id, name = q.name, level = q.level, takes = takes(q.raw) }
        else
            ordinary[#ordinary + 1] = q
        end
    end
    for _, g in ipairs(groups) do table.sort(g.quests, function(a, b) return tostring(a.name) < tostring(b.name) end) end
    return ordinary, groups
end


-------------------------------------------------------------------------------
-- What an item in your bags buys from repeatable hand-ins (0.35.430).
--
-- "I hover over Blood Shards and it tells me Flow: keep, to your bank at the
-- next visit. We don't want to keep these items in my bank if they're not
-- useful ... it should be my option, which one of those repeatable quests are
-- we going to do that's going to give me the buff? And if not, then I should
-- choose to destroy the item ... if I get rid of this blood shard, what am I
-- giving up?"
--
-- A Blood Shard was "kept for a quest you haven't done" (Spirit of the Wind,
-- one of Mangletooth's six), and so on its way to the bank. Now an item that
-- repeatable hand-ins take says so: who takes it and where, every hand-in it
-- can buy with what each gives, which one suits the role you play, and that
-- you can sell it instead. It stays in your bags (it's no use in the bank),
-- and its line in Flow Improvements sets your waypoint on the NPC.
-------------------------------------------------------------------------------

-- The words the Banker and the bags' advice know such an item by.
R.ANY_TIME = "as often as you like"

-- Pure: what an item buys.
--   quests: { { id, name, who } } the repeatable quests that take it (one NPC's)
--   role: the role you play; buffOf(id) -> { gives, roles } or nil;
--   where: "The Barrens 44.5, 59.3" or nil; price: copper a vendor pays each
-- -> { who, best = quest or nil, list = { "Name (what it gives)" ... }, text }, or nil
function R.ItemUse(quests, role, buffOf, where, price)
    if not quests or #quests == 0 then return nil end
    local sorted = {}
    for _, q in ipairs(quests) do sorted[#sorted + 1] = q end
    table.sort(sorted, function(a, b) return tostring(a.name) < tostring(b.name) end)
    local who = sorted[1].who or "someone"
    local best = R.Pick(sorted, role, buffOf)
    local list = {}
    for _, q in ipairs(sorted) do
        local def = buffOf(q.id)
        list[#list + 1] = tostring(q.name) .. ((def and def.gives) and (" (" .. def.gives .. ")") or "")
            .. ((best and q.id == best.id) and " <- for the role you play" or "")
    end
    local text = string.format("%s%s takes it for a hand-in of your choice, %s: %s. Keep it with you for those; if you'd sooner have the slot, %s: no other quest uses it",
        tostring(who), where and (" (" .. where .. ")") or "", R.ANY_TIME, table.concat(list, "; "),
        (price or 0) > 0 and "sell it" or "destroy it")
    return { who = who, best = best, list = list, text = text }
end

-- The repeatable quests that take an item, from the quests the quest data
-- ties it to. related: { { id } } (Leftovers.lua's L.Related).
local uses = {}
function R.ForItem(itemId, related, price)
    local now = GetTime and GetTime() or 0
    local kept = uses[itemId]
    if kept and now - kept.at < 20 then return kept.use or nil end
    local Q = ns.quests
    local quests, point
    for _, e in ipairs(related or {}) do
        local raw = Q and Q.QuestieGet and Q:QuestieGet("GetQuest", e.id)
        if raw and R.Is(raw) then
            local takes = false
            for _, id in ipairs(R.Takes(raw)) do if id == itemId then takes = true end end
            if takes then
                local npcId = type(raw.Starts) == "table" and type(raw.Starts.NPC) == "table" and raw.Starts.NPC[1]
                local npc = npcId and Q:QuestieGet("GetNPC", npcId)
                quests = quests or {}
                quests[#quests + 1] = { id = e.id, name = raw.name, level = tonumber(raw.level), who = npc and npc.name }
                if npc and npc.spawns and not point and Q.SpawnPoints then
                    local okP, pts = pcall(Q.SpawnPoints, npc.spawns)
                    point = okP and pts and pts[1] or nil
                end
            end
        end
    end
    local use
    if quests then
        local where
        if point and point.map then
            local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(point.map)
            where = string.format("%s %.1f, %.1f", info and info.name or "map " .. tostring(point.map), (point.x or 0) * 100, (point.y or 0) * 100)
        end
        use = R.ItemUse(quests, ns.LevelingRole and ns:LevelingRole() or nil, function(id) return ns:Get("repeatBuff", id) end, where, price)
        if use then use.point = point end
    end
    uses[itemId] = { at = now, use = use or false }
    return use
end

function R.Lines()
    local out = { "repeatable hand-ins as one step: " .. tostring(#(R.last or {})) }
    for _, g in ipairs(R.last or {}) do out[#out + 1] = "  " .. tostring(g.text) .. (g.fetch and " [in your bank]" or "") end
    for _, n in ipairs(R.skipped or {}) do out[#out + 1] = "  not offered (you have nothing they take): " .. n end
    return out
end
ns.commands.repeatables = function()
    for i, l in ipairs(R.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end
