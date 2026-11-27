-------------------------------------------------------------------------------
-- Flow - Quests/Journal.lua
-- When you took and handed in each quest, and what the route said then (0.35.413).
--
-- "Are you able to get my quest accept/complete times/order? I am quite
-- certain that my quest journey has not been optimal ... can you see the
-- difference between what it suggests and what I have done, is it clear
-- where it is better?"
--
-- Nothing kept that until now: the game only remembers which quests are done,
-- not when or in what order, and Flow recorded nothing either. So the journey
-- so far can't be rebuilt. From this version on, Flow keeps a journal, for
-- this character:
--   * every quest accepted and handed in, and every level gained;
--   * when, where (map and spot), at what level, and the XP a hand-in gave;
--   * what Flow's route had as its next step at that moment, and where on
--     the route the thing you did stood (1 = it was the next step; nothing =
--     it wasn't on the route at all).
-- That last part is what lets the two be compared afterwards: where you left
-- the route, and whether the stretch after was quicker or slower than the
-- stretches where you followed it.
--
-- /flow journal shows the last events and a summary. The whole journal is in
-- this character's saved data (ns.db.journal), up to J.MAX events, oldest
-- dropped first. Nothing leaves your computer.
-------------------------------------------------------------------------------

local _, ns = ...
local J = {}
ns.journal = J

J.MAX = 4000

-- Pure: where on the route a quest stood: the place of its first step in
-- the plan (1 = next), or nil. plan: { { goal = { key } } }; questOf(key) -> id.
function J.Rank(plan, questID, questOf)
    for i, s in ipairs(plan or {}) do
        local key = s and s.goal and s.goal.key
        if key and questOf(key) == questID then return i end
    end
    return nil
end

-- Pure: one more event on the list, the oldest dropped past `max`.
function J.Add(list, e, max)
    list[#list + 1] = e
    while #list > (max or J.MAX) do table.remove(list, 1) end
    return list
end

-- Pure: what the journal says, from its events ({ e = "a" | "d" | "l", t, q, xp, rank }).
-- -> { accepted, done, levels, next (hand-ins that were the route's next step),
--      near (in its first three), off (not on the route), xp, hours (first to last),
--      held (average minutes from accepting a quest to handing it in), pairs }
function J.Summary(list)
    local s = { accepted = 0, done = 0, levels = 0, next = 0, near = 0, off = 0, xp = 0, hours = 0, held = nil, pairs = 0 }
    local took, sum = {}, 0
    for _, e in ipairs(list or {}) do
        if e.e == "a" then
            s.accepted = s.accepted + 1
            if e.q then took[e.q] = e.t end
        elseif e.e == "d" then
            s.done = s.done + 1
            s.xp = s.xp + (e.xp or 0)
            if e.rank == 1 then s.next = s.next + 1 end
            if e.rank and e.rank <= 3 then s.near = s.near + 1 end
            if not e.rank then s.off = s.off + 1 end
            if e.q and took[e.q] and e.t and e.t >= took[e.q] then
                sum, s.pairs = sum + (e.t - took[e.q]), s.pairs + 1
                took[e.q] = nil
            end
        elseif e.e == "l" then
            s.levels = s.levels + 1
        end
    end
    local first, last = list and list[1], list and list[#(list or {})]
    if first and last and first.t and last.t then s.hours = (last.t - first.t) / 3600 end
    if s.pairs > 0 then s.held = sum / s.pairs / 60 end
    return s
end

local function list()
    ns.db.journal = ns.db.journal or {}
    return ns.db.journal
end
local function questOf(key) return ns.focus and ns.focus.QuestOf and ns.focus.QuestOf(key) or nil end

-- One event, with where you are and what the route says.
function J.Note(kind, questID, xp)
    if not (ns.db and ns.nav) then return nil end
    local N = ns.nav
    local p = N.PlayerPos and N:PlayerPos() or nil
    local plan = N.plan
    local first = plan and plan[1] and plan[1].goal and plan[1].goal.key or nil
    local name
    if questID and ns.quests and ns.quests.QuestieGet then
        local ok, q = pcall(ns.quests.QuestieGet, ns.quests, "GetQuest", questID)
        name = ok and q and q.name or nil
    end
    local e = {
        e = kind, t = time(), q = questID, n = name, lv = UnitLevel("player"),
        map = p and p.map or nil, x = p and math.floor(p.x * 1000 + 0.5) / 10 or nil, y = p and math.floor(p.y * 1000 + 0.5) / 10 or nil,
        xp = xp, next = first, rank = questID and J.Rank(plan, questID, questOf) or nil,
        steps = plan and #plan or nil,
    }
    J.Add(list(), e)
    return e
end

-- (The game hands the quest's number over differently on old and new clients: the last number given.)
local function idOf(...)
    local id
    for i = 1, select("#", ...) do
        local v = ns.api.Safe((select(i, ...)))
        if type(v) == "number" and v > 0 then id = v end
    end
    return id
end
ns:On("QUEST_ACCEPTED", function(...) pcall(J.Note, "a", idOf(...)) end)
ns:On("QUEST_TURNED_IN", function(questID, xp)
    local id, gained = ns.api.Safe(questID), ns.api.Safe(xp)
    pcall(J.Note, "d", type(id) == "number" and id or nil, type(gained) == "number" and gained or nil)
end)
ns:On("PLAYER_LEVEL_UP", function() pcall(J.Note, "l", nil, nil) end)
ns:OnLoad(function(saved) saved.journal = saved.journal or {} end)
ns:PerCharacter("journal")

local WORD = { a = "took", d = "handed in", l = "level" }
function J.Lines(n)
    local l = (ns.db and ns.db.journal) or {}
    local s = J.Summary(l)
    local out = { string.format("quest journal: %d event(s): %d taken, %d handed in, %d level(s), over %.1f h", #l, s.accepted, s.done, s.levels, s.hours) }
    if s.done > 0 then
        out[#out + 1] = string.format("  hand-ins: %d were the route's next step, %d in its first three, %d not on the route at all; %d XP from them", s.next, s.near, s.off, s.xp)
    end
    if s.held then out[#out + 1] = string.format("  from taking a quest to handing it in: %.0f min on average (%d quest(s))", s.held, s.pairs) end
    for i = math.max(1, #l - (n or 15) + 1), #l do
        local e = l[i]
        out[#out + 1] = string.format("  %s %s %s%s at level %s, map %s %s, %s%s%s", date("%m-%d %H:%M", e.t or 0), WORD[e.e] or "?",
            e.e == "l" and tostring(e.lv) or tostring(e.n or e.q or "?"), e.q and (" [" .. e.q .. "]") or "", tostring(e.lv),
            tostring(e.map), e.x and string.format("%.1f, %.1f", e.x, e.y) or "?",
            e.rank and ("step " .. e.rank .. " of " .. tostring(e.steps or "?")) or (e.e == "l" and "" or "not on the route"),
            e.xp and (", " .. e.xp .. " XP") or "", e.next and ("; the route's next: " .. tostring(e.next)) or "")
    end
    if #l == 0 then out[#out + 1] = "  nothing yet: it starts with the next quest you take or hand in" end
    return out
end
ns.commands.journal = function(arg)
    for i, line in ipairs(J.Lines(tonumber(arg))) do if i == 1 then ns:Print(line) else print(line) end end
end
