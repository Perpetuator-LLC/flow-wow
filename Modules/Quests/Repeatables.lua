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

function R.Lines()
    local out = { "repeatable hand-ins as one step: " .. tostring(#(R.last or {})) }
    for _, g in ipairs(R.last or {}) do out[#out + 1] = "  " .. tostring(g.text) .. (g.fetch and " [in your bank]" or "") end
    for _, n in ipairs(R.skipped or {}) do out[#out + 1] = "  not offered (you have nothing they take): " .. n end
    return out
end
ns.commands.repeatables = function()
    for i, l in ipairs(R.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end
