-- Weapon skills you can learn: when a weapon in your bags would be an upgrade
-- for your levelling spec but you haven't trained its skill yet (a sword
-- before you've learned Swords), the route gets a stop at a weapon master who
-- teaches it. Weapons your class can never use (guns for a paladin) never
-- get one: the gear check marks those "your class can't use this".
--
-- Weapon masters and what they teach (classic data, approximate; extend):
--   ns:Register("weaponMaster", "<NPC name>", { skills = { [itemSubclassID] = true }, cost = copper })
-- Item subclasses: 0 Axes, 1 Two-Handed Axes, 2 Bows, 3 Guns, 4 Maces,
-- 5 Two-Handed Maces, 6 Polearms, 7 Swords, 8 Two-Handed Swords, 10 Staves,
-- 13 Fist Weapons, 15 Daggers, 16 Thrown, 18 Crossbows, 19 Wands.

local _, ns = ...
local W = {}
ns.weaponSkills = W

local TRAIN_COST = 1000   -- 10 silver: what a weapon skill costs at low level

local function teaches(...)
    local t = {}
    for _, s in ipairs({ ... }) do t[s] = true end
    return t
end
-- Alliance
ns:Register("weaponMaster", "Woo Ping", { skills = teaches(6, 7, 8, 10, 15, 18) })          -- Stormwind
ns:Register("weaponMaster", "Buliwyf Stonehand", { skills = teaches(0, 1, 3, 4, 5, 13) })   -- Ironforge
ns:Register("weaponMaster", "Bixi Wobblebonk", { skills = teaches(15, 16, 18) })             -- Ironforge
ns:Register("weaponMaster", "Ilyenia Moonfire", { skills = teaches(2, 10, 13, 15) })         -- Darnassus
-- Horde
ns:Register("weaponMaster", "Hanashi", { skills = teaches(0, 1, 2, 10, 16) })                -- Orgrimmar
ns:Register("weaponMaster", "Sayoc", { skills = teaches(0, 1, 2, 13, 15, 16) })              -- Orgrimmar
ns:Register("weaponMaster", "Ansekhwa", { skills = teaches(3, 4, 5, 10) })                   -- Thunder Bluff
ns:Register("weaponMaster", "Archibald", { skills = teaches(6, 7, 8, 15, 18) })              -- Undercity

-- Weapon masters who teach item subclass `sub`.
function W.MastersFor(sub)
    local out = {}
    for name, m in ns:Each("weaponMaster") do
        if m.skills[sub] then out[#out + 1] = name end
    end
    return out
end

-- Skills worth training now: { [subclassID] = { skill, item, diff } } for
-- weapons in your bags that would be upgrades once trained.
function W.Wanted()
    local D, G = ns.disposition, ns.gear
    local want = {}
    if not (D and G and D.EachBagItem) then return want end
    local role, level = ns:LevelingRole(), UnitLevel("player")
    D:EachBagItem(function(_, _, link)
        local ok, g = pcall(G.Compare, G, link)
        if ok and g and g.needsTraining and g.diffs and (g.diffs[role] or 0) >= 0.5
            and (g.item.minLevel or 0) <= level then
            local cur = want[g.subclassID]
            if not cur or g.diffs[role] > cur.diff then
                want[g.subclassID] = { skill = g.skill, item = link:match("%[(.-)%]") or "it", diff = g.diffs[role] }
            end
        end
    end)
    return want
end

ns:Register("navGoal", "weaponskill", {
    collect = function()
        local out = {}
        for sub, w in pairs(W.Wanted()) do
            local names = W.MastersFor(sub)
            if #names > 0 then
                if ns.quests.NPCsByName then ns.quests:NPCsByName(names) end
                local points = {}
                for _, n in ipairs(names) do
                    for _, pt in ipairs(ns.places:Points(n)) do points[#points + 1] = pt end
                end
                out[#out + 1] = {
                    key = "weaponskill:" .. sub, kind = "classtrainer", points = points, npcs = names,
                    optional = true, weight = 1.2, cost = TRAIN_COST,
                    text = string.format("Learn %s (weapon master) to use %s", w.skill or "the skill", w.item),
                    details = { string.format("%s is an upgrade for you (+%d) once you've trained %s.",
                                    w.item, math.floor(w.diff + 0.5), w.skill or "its weapon skill"),
                                "Weapon masters: " .. table.concat(names, ", ") .. ". About 10 silver." },
                    blockedBy = #points == 0 and ("Flow doesn't know where " .. table.concat(names, " / ") .. " is yet") or nil,
                }
            end
        end
        return out
    end,
})
