-- XP-first route sorting (the default; "Shortest path" switches it off).
-- The planner minimises sum(distance x weight). This scales each quest
-- stop's weight by how much it's worth to you right now:
--   more XP              -> lighter (worth walking further for)
--   quest above you      -> heavier (slower kills, more deaths): 3+ levels up
--                           costs a lot, so level-appropriate quests come first
--   quest about to grey  -> a little lighter (do it before its XP drops)
-- Same stops, same shortest-path planner: it just stops treating a level-10
-- quest at level 7 the same as a level-6 one next door.
-- Every quest stop's tooltip gets an XP line.

local _, ns = ...
local X = {}
ns.xpValue = X

-- Rough full quest XP by quest level (classic-style curve). Real numbers
-- from your quest log are used where the client gives them.
function X.Estimate(level)
    level = math.max(1, level or 1)
    if level <= 10 then return 80 + 55 * level end
    return 630 + 95 * (level - 10)
end

-- Share of XP you still get, by how far below you the quest is.
local DECAY = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }
function X.Share(questLevel, myLevel)
    local below = myLevel - questLevel
    if below <= 5 then return 1 end
    return DECAY[below] or 0.1
end

local function logXP(questID)
    if not GetQuestLogRewardXP then return nil end
    local ok, xp = pcall(GetQuestLogRewardXP, questID)
    if ok and type(xp) == "number" and xp > 0 then return xp end
end

local function questOf(goal)
    local k = goal.key
    local id = k:match("^pickup:(%d+)$") or k:match("^(%d+):done$") or k:match("^(%d+):%d+$")
    return id and tonumber(id), k:find("^pickup:") ~= nil
end

function X:On() return (ns.db.nav.sorter or "xp") == "xp" end
function X:Set(on) ns.db.nav.sorter = on and "xp" or "distance"; ns.nav:Collect() end

function X:Apply(goals)
    local me = UnitLevel("player")
    local ref = X.Estimate(me)
    local on = self:On()
    for _, g in ipairs(goals) do
        local id, isPickup = questOf(g)
        if id and g.level then
            local xp = (not isPickup) and logXP(id) or nil
            local share = X.Share(g.level, me)
            local real = xp ~= nil
            xp = xp or math.floor(X.Estimate(g.level) * share + 0.5)
            local above = g.level - me
            local note
            if above >= 3 then note = string.format("%d levels above you: slower and riskier", above)
            elseif above == 2 then note = "2 levels above you"
            elseif share < 1 then note = string.format("%d%% XP: going grey", share * 100)
            elseif me - g.level >= 3 then note = "full XP for now; it starts to drop at level " .. (g.level + 6)
            else note = "full XP" end
            g.details = g.details or {}
            table.insert(g.details, string.format("XP: %s%d (%s)", real and "" or "about ", xp, note))
            g.xp = xp
            if on then
                local m = math.sqrt(ref / math.max(xp, 1))
                m = math.max(0.6, math.min(1.6, m))
                if above >= 3 then m = m * (1 + 0.4 * (above - 2))
                elseif above == 2 then m = m * 1.15 end
                if me - g.level >= 3 and share == 1 then m = m * 0.9 end
                g.weight = (g.weight or 1) * m
            end
        end
    end
end
