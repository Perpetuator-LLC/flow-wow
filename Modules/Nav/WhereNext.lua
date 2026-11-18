-- Where next: the zones worth questing in at your level.
--
-- "I'm getting to level 20 and I can go to a lot of different areas, and I
-- don't know which is best for questing, for my XP, for my professions, for
-- my class quests. Can we give the user some information to help them know
-- where to go next?" (0.35.298)
--
-- The quest data is asked one plain question: of every quest you haven't
-- done and aren't on, that's for your race and class and around your level,
-- how many are in each zone, and what are they worth? A few hundred quests a
-- frame, once per level. For each zone:
--   * how many quests you could pick up, their levels, and about how much XP
--     they'd give you at your level (the same estimate the route uses; a
--     quest far below you counts for less);
--   * how many of them are class quests;
--   * for a gathering profession you have: what you can pick there that still
--     raises your skill, or the skill its nodes ask for when they're beyond you;
--   * whether it's on the continent you're on.
-- /flow where lists them, best first; the Flow menu's Zones section shows the
-- top few under your route's zones. Flow doesn't choose for you: quests that
-- are grey, a zone across the sea, or a dungeon's own list are all here, said
-- for what they are.
--
-- What it doesn't know: how the quests in a zone lie (a tight hub or spread
-- thin), elites, or travel time there. Those belong to the route once you go.

local _, ns = ...
local W = {}
ns.whereNext = W

W.CHUNK = 250
W.BELOW, W.ABOVE = 4, 3      -- quest levels this far under and over yours count
W.SHOW = 8                   -- zones listed
W.zones, W.scanning, W.forLevel = {}, false, nil

-- Pure: does a quest of this level count for a player of that level?
--   minLevel: the level it can be picked up at (nil: any)
function W.InWindow(questLevel, minLevel, myLevel)
    if not (questLevel and myLevel) or questLevel <= 0 then return false end
    if questLevel < myLevel - W.BELOW or questLevel > myLevel + W.ABOVE then return false end
    return (minLevel or 0) <= myLevel + 1
end

-- Pure: adds one quest to its zone's tally. zones: { [zoneId] = tally }.
--   xp: what the quest is worth to you now.
function W.Add(zones, zoneId, quest, xp)
    local z = zones[zoneId]
    if not z then
        z = { zone = zoneId, quests = 0, xp = 0, class = 0 }
        zones[zoneId] = z
    end
    z.quests = z.quests + 1
    z.xp = z.xp + (xp or 0)
    if quest.classOnly then z.class = z.class + 1 end
    local lv = quest.level
    z.min = math.min(z.min or lv, lv)
    z.max = math.max(z.max or lv, lv)
    return z
end

-- Pure: the tallies as a list, the most XP first; at least `least` quests.
function W.Rank(zones, least)
    local out = {}
    for _, z in pairs(zones or {}) do
        if z.quests >= (least or 1) then out[#out + 1] = z end
    end
    table.sort(out, function(a, b)
        if a.xp ~= b.xp then return a.xp > b.xp end
        return a.zone < b.zone
    end)
    return out
end

-- Pure: thousands as "24k", small numbers as they are.
function W.Short(n)
    n = math.floor((n or 0) + 0.5)
    if n >= 10000 then return string.format("%dk", math.floor(n / 1000 + 0.5)) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

-- Pure: a zone's line.
--   z: its tally, with name, away (another continent) and gather (words about a profession, or nil)
function W.Line(z)
    local levels = z.min == z.max and string.format("level %d", z.min) or string.format("levels %d-%d", z.min, z.max)
    local parts = { string.format("%s: %d quest%s, %s, about %s XP", tostring(z.name), z.quests, z.quests == 1 and "" or "s", levels, W.Short(z.xp)) }
    if z.class > 0 then parts[#parts + 1] = string.format("%d for your class", z.class) end
    if z.gather then parts[#parts + 1] = z.gather end
    if z.away then parts[#parts + 1] = "on another continent" end
    return table.concat(parts, "; ")
end

-- Pure: the words about a gathering profession in a zone.
--   picks: names you can gather there that still raise your skill; need:
--   { name, skill } the easiest node there beyond you (or nil); rank: yours.
function W.GatherText(prof, picks, need, rank)
    if picks and #picks > 0 then
        return prof .. ": " .. table.concat(picks, ", ", 1, math.min(3, #picks))
    end
    if need then return string.format("%s there needs %d (you have %d)", prof, need.skill, rank or 0) end
    return nil
end

local function gatherFor(zoneId)
    local SP, Q = ns.skillPlan, ns.quests
    if not (SP and SP.NodesHere and Q and Q.UiMapForArea) then return nil end
    local map = Q:UiMapForArea(zoneId)
    if not map then return nil end
    for _, prof in ipairs({ "Herbalism", "Mining" }) do
        local rank = ns.api.Skill and ns.api.Skill(prof)
        if rank then
            local ok, nodes = pcall(SP.NodesHere, prof, map)
            if ok and nodes and #nodes > 0 then
                local text = W.GatherText(prof, SP.PickNames(nodes, rank, ns.nearby and ns.nearby.SkillUp), SP.ZoneNeed(rank, nodes), rank)
                if text then return text end
            end
        end
    end
    return nil
end

local function finish(zones)
    local Q, N = ns.quests, ns.nav
    local list = W.Rank(zones, 2)
    for i = #list, W.SHOW + 1, -1 do list[i] = nil end
    local me = N and N:PlayerPos()
    for _, z in ipairs(list) do
        z.name = Q:ZoneName(z.zone)
        local map = Q.UiMapForArea and Q:UiMapForArea(z.zone)
        if map and me and N.ToWorld then
            local cont = N:ToWorld(map, 0.5, 0.5)
            z.away = cont ~= nil and me.cont ~= nil and cont ~= me.cont or nil
        end
        local ok, text = pcall(gatherFor, z.zone)
        z.gather = ok and text or nil
    end
    W.zones = list
end

-- Looks through every quest for your level, a few hundred a frame.
function W.Scan(force)
    local level = UnitLevel("player")
    if W.scanning or (not force and W.forLevel == level) then return end
    local Q, X = ns.quests, ns.xpValue
    local src = Q and Q.Source and Q:Source()
    if not (src and src.allIds and src.get) then return end
    local ok, ids = pcall(src.allIds)
    if not ok or type(ids) ~= "table" then return end
    W.scanning = true
    local log = Q:LogIds() or {}
    local i, zones = 1, {}
    local function step()
        local last = math.min(#ids, i + W.CHUNK - 1)
        for k = i, last do
            local id = ids[k]
            local okQ, q = pcall(src.get, id)
            if okQ and q and q.zoneId and W.InWindow(q.level, q.minLevel, level) and not log[id]
                and not Q:IsCompleted(id) and (Q.ForMe == nil or Q.ForMe(q.raw)) and Q:Offered(id, q.raw) then
                local xp = X and X.Estimate and X.Share and (X.Estimate(q.level) * (X.Share(q.level, level) or 1)) or 0
                local raw = q.raw or {}
                W.Add(zones, q.zoneId, { level = q.level, classOnly = type(raw.requiredClasses) == "number" and raw.requiredClasses ~= 0 }, xp)
            end
        end
        i = last + 1
        if i <= #ids then C_Timer.After(0, step) return end
        W.scanning, W.forLevel = false, level
        pcall(finish, zones)
    end
    C_Timer.After(0, step)
end

function W.Lines()
    if W.forLevel ~= UnitLevel("player") then
        pcall(W.Scan)
        if #W.zones == 0 then return { "where next: looking through the quest data; ask again in a moment" } end
    end
    if #W.zones == 0 then return { "where next: the quest data has no zone with quests for your level that you haven't done" } end
    local out = { string.format("where next (quests you haven't done, around level %d; most XP first):", UnitLevel("player")) }
    for _, z in ipairs(W.zones) do out[#out + 1] = "  " .. W.Line(z) end
    out[#out + 1] = "  Not judged: how close together a zone's quests lie, elites, or the trip there."
    return out
end
ns.commands.where = function()
    for i, l in ipairs(W.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end

-- The Flow menu's Zones section: the top few, to read (nothing to click).
function W.MenuItems(max)
    local items = {}
    if #W.zones == 0 then pcall(W.Scan) return items end
    items[1] = { text = "|cffffd100Where next (most XP first):|r", disabled = true }
    for i, z in ipairs(W.zones) do
        if i > (max or 5) then break end
        items[#items + 1] = { text = "|cffbbbbbb" .. W.Line(z) .. "|r", disabled = true }
    end
    return items
end

ns:On("PLAYER_ENTERING_WORLD", function() if C_Timer then C_Timer.After(35, function() pcall(W.Scan) end) end end)
ns:On("PLAYER_LEVEL_UP", function() if C_Timer then C_Timer.After(10, function() pcall(W.Scan, true) end) end end)
