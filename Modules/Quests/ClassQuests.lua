-- Class quests Flow doesn't know by name.
--
-- "It's telling me to train Rake, Prowl, Claw and Shred for Cat Form, but I
-- don't see anything telling me to go get Cat Form. If it could show me
-- where to get started on the Cat Form quest, I'd really like that."
-- (0.35.296)
--
-- Flow's class list said Cat Form is trained at level 20; on WoW: Forever
-- the trainer doesn't have it (Flow noted that at the trainer: Facts.lua),
-- and Flow knew of no quest for it, so the spells that wait for Cat Form
-- pointed nowhere. Flow can't know this game's quest for it by name, but the
-- quest data can be asked a plain question: which quests are only for your
-- class, and which of those haven't you done? Those are looked up once a
-- session (a few hundred quests a frame). When a spell of yours isn't at the
-- trainer and has no quest Flow knows, Flow Improvements says so and names
-- the class quests you haven't done, the lowest first, with a link to its
-- step where the route has one. /flow classquests lists them (also in the
-- diagnostics), so the right quest can be written into the class data.
--
-- A new form is weighted high: forms change how you travel and fight.

local _, ns = ...
local CQ = {}
ns.classQuests = CQ

CQ.CHUNK = 250
CQ.FORM_IMPORTANCE = 85   -- above ordinary training (80) and other class quests (75)
CQ.list, CQ.scanning, CQ.scanned = {}, false, false

-- Pure: is this a spell that changes your shape (worth more than a rank)?
function CQ.IsForm(spell)
    return type(spell) == "string" and (spell:find(" Form$") ~= nil or spell == "Ghost Wolf" or spell == "Stealth")
end

-- Pure: the class quests to name for a player of `level`: not done, not in
-- the log, for a level you've reached (or within `ahead` of it), lowest first.
--   quests: { { id, name, level, minLevel, done, inLog } }
function CQ.Open(quests, level, ahead, max)
    local out = {}
    for _, q in ipairs(quests or {}) do
        if not q.done and not q.inLog and (q.minLevel or 0) <= (level or 0) + (ahead or 0) then out[#out + 1] = q end
    end
    table.sort(out, function(a, b)
        local la, lb = a.minLevel or a.level or 0, b.minLevel or b.level or 0
        if la ~= lb then return la > lb end   -- the newest for your level first: the one you're likely missing
        return tostring(a.name) < tostring(b.name)
    end)
    for i = #out, (max or #out) + 1, -1 do out[i] = nil end
    return out
end

-- Pure: the words for a spell your trainer doesn't have and Flow has no quest for.
function CQ.Text(spell, open)
    if #open == 0 then
        return string.format("%s isn't at your class trainer on this game, and the quest data has no quest for your class that you haven't done. Ask your trainer where it's learned.", spell)
    end
    local names = {}
    for i, q in ipairs(open) do
        if i > 3 then break end
        names[#names + 1] = string.format("%s (level %d)", tostring(q.name), q.minLevel or q.level or 0)
    end
    return string.format("%s isn't at your class trainer on this game: a class quest may teach it. Class quests you haven't done: %s.",
        spell, table.concat(names, ", "))
end

-- Is the quest only for some classes (yours among them)?
local function classOnly(raw)
    return type(raw) == "table" and type(raw.requiredClasses) == "number" and raw.requiredClasses ~= 0
end

-- Looks through every quest once, a few hundred a frame.
function CQ.Scan()
    if CQ.scanning or CQ.scanned then return end
    local Q = ns.quests
    local src = Q and Q.Source and Q:Source()
    if not (src and src.allIds and src.get) then return end
    local ok, ids = pcall(src.allIds)
    if not ok or type(ids) ~= "table" then return end
    CQ.scanning = true
    local i, found = 1, {}
    local function step()
        local last = math.min(#ids, i + CQ.CHUNK - 1)
        for k = i, last do
            local okQ, q = pcall(src.get, ids[k])
            if okQ and q and classOnly(q.raw) then
                local okM, mine = pcall(function() return Q.ForMe == nil or Q.ForMe(q.raw) end)
                if okM and mine then
                    found[#found + 1] = { id = q.id, name = q.name, level = q.level, minLevel = q.minLevel,
                                          starter = q.starter and q.starter.name or nil }
                end
            end
        end
        i = last + 1
        if i <= #ids then C_Timer.After(0, step) return end
        CQ.list, CQ.scanning, CQ.scanned = found, false, true
    end
    C_Timer.After(0, step)
end

-- The list with what you've done and what's in your log, now.
function CQ.Now()
    local Q = ns.quests
    local log = Q and Q.LogIds and Q:LogIds() or {}
    local out = {}
    for _, q in ipairs(CQ.list) do
        out[#out + 1] = { id = q.id, name = q.name, level = q.level, minLevel = q.minLevel, starter = q.starter,
                          done = Q.IsCompleted and Q:IsCompleted(q.id) and true or false, inLog = log[q.id] == true }
    end
    return out
end

-- The spells of yours that aren't at the trainer and have no quest Flow knows.
function CQ.Orphans()
    local out = {}
    local _, token = UnitClass("player")
    local level = UnitLevel("player")
    local known = ns.rotation and ns.rotation:KnownSpells() or {}
    local F = ns.facts
    for _, s in ipairs(ns:Get("classSpells", token) or {}) do
        if (s.level or 0) <= level and not known[s.spell] and not s.quest
            and F and F.NotTaught and F.NotTaught(token, s.spell, s.level) then
            out[#out + 1] = s
        end
    end
    return out
end

ns:Register("advisor", "classQuests", {
    check = function()
        local out = {}
        local ok, orphans = pcall(CQ.Orphans)
        if not ok or #orphans == 0 then return out end
        if not CQ.scanned then pcall(CQ.Scan) return out end
        local open = CQ.Open(CQ.Now(), UnitLevel("player"), 0, 5)
        for _, s in ipairs(orphans) do
            out[#out + 1] = {
                importance = CQ.IsForm(s.spell) and CQ.FORM_IMPORTANCE or 75,
                text = CQ.Text(s.spell, open),
                improves = s.improves,
                goalKey = open[1] and ("pickup:" .. open[1].id) or nil,   -- (its link, when the route has that step)
            }
        end
        return out
    end,
})

function CQ.Lines()
    if not CQ.scanned then
        pcall(CQ.Scan)
        return { "class quests: looking through the quest data; ask again in a moment" }
    end
    local now = CQ.Now()
    local out = { string.format("class quests in the quest data for your class: %d", #now) }
    table.sort(now, function(a, b) return (a.minLevel or a.level or 0) < (b.minLevel or b.level or 0) end)
    for _, q in ipairs(now) do
        out[#out + 1] = string.format("  [%d] %s (level %s, from %s)%s: %s", q.id, tostring(q.name), tostring(q.level or "?"),
            tostring(q.minLevel or "?"), q.starter and (", " .. q.starter) or "", q.done and "done" or (q.inLog and "in your log" or "not done"))
    end
    local ok, orphans = pcall(CQ.Orphans)
    for _, s in ipairs(ok and orphans or {}) do
        out[#out + 1] = string.format("  not at the trainer, no quest known to Flow: %s (level %d in Flow's list)", s.spell, s.level or 0)
    end
    return out
end
ns.commands.classquests = function()
    for i, l in ipairs(CQ.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end

-- A first look a little after login, so the diagnostics have the list.
ns:On("PLAYER_ENTERING_WORLD", function()
    if C_Timer and not CQ.scanned then C_Timer.After(20, function() pcall(CQ.Scan) end) end
end)
