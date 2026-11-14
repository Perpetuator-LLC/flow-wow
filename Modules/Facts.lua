-- What the game itself told Flow: facts that correct Flow's built-in lists.
--
-- "Can you be collecting these kinds of things? How can we start to gather
-- this data so it keeps getting better?" (0.35.220) Flow's class lists and
-- the quest data are approximate on WoW: Forever: Cure Poison isn't taught
-- at 14 here, some quests have no place at all. Each time the game shows
-- the truth, Flow keeps it:
--
--   spells   what a class trainer lists: the spell, its rank, the level it
--            asks, its price                      (read at every trainer)
--   lacks    a spell of Flow's class list that a trainer, read at a level
--            where the list says it's due, doesn't have at all
--   spots    where a quest's objective was done or the quest handed in,
--            for quests the data can't place      (Quests/LearnedSpots.lua)
--
-- Kept for the whole account (FlowDB.facts): game facts only, a class, a
-- level, a spell name, a price, a quest number, a map spot. Nothing about
-- you or your characters. Flow uses them at once: the advice follows what
-- trainers really teach, whichever of your characters saw it.
--
-- Sharing is the same opt-in as the NPC spots: /flow places share lists
-- them in your saved data, tools\share-facts.ps1 merges that list into
-- Learned\Facts.lua, and a pull request brings it to every Flow player
-- (docs/SHARE-PLACES.md). Nothing leaves your computer by itself.
--
--   /flow facts    what Flow has learned, and what came with Flow

local _, ns = ...
local F = {}
ns.facts = F

ns:OnLoad(function(saved)
    saved.facts = saved.facts or {}
    saved.facts.spells = saved.facts.spells or {}
    saved.facts.lacks = saved.facts.lacks or {}
end)

-- A spell's key: its name, with its rank where the game gives one.
function F.SpellKey(name, rank)
    if type(rank) == "string" and rank ~= "" then return name .. " (" .. rank .. ")" end
    return name
end

-- Pure: one trainer line into the table. The lowest level and price seen
-- win (a trainer never asks more than another for the same rank).
function F.NoteSpell(spells, class, name, rank, level, cost)
    if not (spells and class and type(name) == "string" and name ~= "") then return false end
    spells[class] = spells[class] or {}
    local key = F.SpellKey(name, rank)
    local old = spells[class][key]
    level, cost = tonumber(level) or 0, tonumber(cost) or 0
    if old and (old.level or 0) > 0 and (level == 0 or old.level <= level) then
        if cost > 0 and ((old.cost or 0) == 0 or cost < old.cost) then old.cost = cost end
        return false
    end
    spells[class][key] = { name = name, rank = (type(rank) == "string" and rank ~= "") and rank or nil, level = level, cost = cost }
    return true
end

-- Pure: a class-list spell a trainer doesn't have, read at `level`. Kept at
-- the highest level it was seen missing: "not taught up to level N".
function F.NoteLack(lacks, class, name, level)
    if not (lacks and class and name and level) then return false end
    lacks[class] = lacks[class] or {}
    if (lacks[class][name] or 0) >= level then return false end
    lacks[class][name] = level
    return true
end

-- Pure: which of a class list's spells a trainer's list lacks. list: the
-- class's spells ({ spell, level, quest, note }); names: { [name] = true }
-- the trainer listed; known: your spells; level: yours. Only spells the
-- list says a trainer teaches (no quest, no note) and that are due.
function F.Lacking(list, names, known, level)
    local out = {}
    for _, s in ipairs(list or {}) do
        if s.spell and (s.level or 0) <= level and not s.quest and not s.note
            and not (known and known[s.spell]) and not names[s.spell] then
            out[#out + 1] = s.spell
        end
    end
    return out
end

-- What came with Flow (Learned\Facts.lua, from players who shared).
local shared
function F.Shared()
    if shared then return shared end
    shared = { spells = {}, lacks = {}, spots = {} }
    for _, data in ns:Each("sharedFacts") do
        for class, list in pairs(data.spells or {}) do
            shared.spells[class] = shared.spells[class] or {}
            for key, s in pairs(list) do shared.spells[class][key] = s end
        end
        for class, list in pairs(data.lacks or {}) do
            shared.lacks[class] = shared.lacks[class] or {}
            for name, lv in pairs(list) do shared.lacks[class][name] = math.max(shared.lacks[class][name] or 0, lv) end
        end
        for quest, by in pairs(data.spots or {}) do
            shared.spots[quest] = shared.spots[quest] or {}
            for index, pts in pairs(by) do shared.spots[quest][index] = pts end
        end
    end
    return shared
end
function F.ResetShared() shared = nil end   -- (tests)

-- Is this class-list spell known not to be taught up to `level`? Yours
-- first, then what came with Flow. (A spell seen at a trainer since beats
-- an older "lacks".)
function F.NotTaught(class, name, level, own, sharedFacts)
    own = own or (ns.db and ns.db.facts) or {}
    sharedFacts = sharedFacts or F.Shared()
    for _, src in ipairs({ own, sharedFacts }) do
        for _, s in pairs(src.spells and src.spells[class] or {}) do
            if s.name == name then return false end   -- a trainer does list it
        end
    end
    for _, src in ipairs({ own, sharedFacts }) do
        local lv = src.lacks and src.lacks[class] and src.lacks[class][name]
        if lv and lv >= level then return true end
    end
    return false
end

-- A learned spot for a quest that came with Flow (yours are in LearnedSpots).
function F.SharedSpots(questID, index)
    local by = F.Shared().spots[questID]
    local pts = by and by[index]
    if type(pts) ~= "table" or #pts == 0 then return nil end
    local out = {}
    for _, p in ipairs(pts) do out[#out + 1] = { map = p[1] or p.map, x = p[2] or p.x, y = p[3] or p.y } end
    return out
end

-- A class trainer was read (Trainer.lua): its lines, and what it lacks.
--   services: { { name, sub, level, cost } }
function F.TrainerRead(class, services, level, known)
    if not (ns.db and ns.db.facts and class) then return 0 end
    local n, names = 0, {}
    for _, s in ipairs(services or {}) do
        names[s.name] = true
        if F.NoteSpell(ns.db.facts.spells, class, s.name, s.sub, s.level, s.cost) then n = n + 1 end
    end
    for _, name in ipairs(F.Lacking(ns:Get("classSpells", class), names, known, level)) do
        if F.NoteLack(ns.db.facts.lacks, class, name, level) then
            n = n + 1
            ns:Log("facts", string.format("%s: a level %d trainer has no %s (Flow's list said it would)", class, level, name))
        end
    end
    if n > 0 then ns:Log("facts", string.format("%s trainer read at level %d: %d new fact(s)", class, level, n)) end
    return n
end

-------------------------------------------------------------------------------
-- Sharing (with /flow places share; tools\share-facts.ps1)
-------------------------------------------------------------------------------
--   "S|CLASS|spell|rank|level|cost"   a trainer's line (rank may be empty)
--   "L|CLASS|spell|level"             a class-list spell no trainer had up to that level
--   "Q|questID|index|map|x|y"         where an objective was done (index: a number, or "done")
function F.ShareLines(facts, spots)
    local lines = {}
    local function clean(s) return type(s) == "string" and not s:find("[|\n\"\\]") and #s <= 64 end
    for class, list in pairs(facts and facts.spells or {}) do
        for _, s in pairs(list) do
            if clean(class) and clean(s.name) and (s.rank == nil or clean(s.rank)) then
                lines[#lines + 1] = string.format("S|%s|%s|%s|%d|%d", class, s.name, s.rank or "", s.level or 0, s.cost or 0)
            end
        end
    end
    for class, list in pairs(facts and facts.lacks or {}) do
        for name, lv in pairs(list) do
            if clean(class) and clean(name) then lines[#lines + 1] = string.format("L|%s|%s|%d", class, name, lv) end
        end
    end
    for quest, by in pairs(spots or {}) do
        for index, pts in pairs(by) do
            for _, p in ipairs(pts) do
                if type(quest) == "number" and p.map and p.x and p.y then
                    lines[#lines + 1] = string.format("Q|%d|%s|%d|%.4f|%.4f", quest, tostring(index), p.map, p.x, p.y)
                end
            end
        end
    end
    table.sort(lines)
    return lines
end

-------------------------------------------------------------------------------
-- /flow facts
-------------------------------------------------------------------------------
local function count(t)
    local n = 0
    for _, list in pairs(t or {}) do for _ in pairs(list) do n = n + 1 end end
    return n
end
function F.Lines()
    local own, sh = ns.db.facts or {}, F.Shared()
    local spots = 0
    for _, by in pairs(ns.db.learnedSpots or {}) do for _, pts in pairs(by) do spots = spots + #pts end end
    local out = { string.format("Flow has learned from the game: %d trainer line(s), %d spell(s) trainers don't have, %d quest spot(s)",
        count(own.spells), count(own.lacks), spots) }
    out[#out + 1] = string.format("  came with Flow (shared by players): %d trainer line(s), %d missing spell(s), %d quest(s) with spots",
        count(sh.spells), count(sh.lacks), (function() local n = 0; for _ in pairs(sh.spots) do n = n + 1 end; return n end)())
    for class, list in pairs(own.lacks or {}) do
        for name, lv in pairs(list) do
            out[#out + 1] = string.format("  %s: no trainer had %s up to level %d", class, name, lv)
        end
    end
    out[#out + 1] = "  share them with every Flow player: /flow places share (game facts only, nothing about you)"
    return out
end
ns.commands.facts = function()
    for i, l in ipairs(F.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end
ns:Register("help", "facts", { order = 61, title = "What Flow learns from the game", lines = {
    "What trainers really teach, which listed spells they don't have, and where unplaced quests were done: kept and used at once.",
    "/flow facts: the count. /flow places share lists them for sharing (docs/SHARE-PLACES.md).",
} })
