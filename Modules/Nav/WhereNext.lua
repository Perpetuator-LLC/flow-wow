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
-- And since 0.35.316, how the zone levels ("some areas have mobs closer
-- together and quests more in a condensed fashion so that they can level
-- faster"):
--   * where its quest givers stand: in how many places (givers within
--     W.HUB_YD of each other are one place), and how many at the biggest;
--   * how far apart the mobs its quests send you to stand (the middle of
--     each mob's distance to its nearest twin, in yards);
--   * the levels of those mobs, and how many quests need an elite.
-- The Flow Router's Zones list (Nav.lua, N.ZoneMenuItems) shows all of it on
-- each zone's row and tooltip, and marks a few "suggested". Flow never picks:
-- you tick the zones you want ("I don't really want [Flow] intelligently
-- picking what zone was next ... show the user what the options were and
-- what was suggested ... and then let them pick", 0.35.316).
--
-- What it doesn't know: terrain, travel time there, or how crowded it is.

local _, ns = ...
local W = {}
ns.whereNext = W

W.CHUNK = 200
W.BELOW, W.ABOVE = 4, 3      -- quest levels this far under and over yours count
W.SHOW = 8                   -- zones listed by /flow where
W.KEEP = 14                  -- zones looked at closely (gathering, the Zones list)
W.HUB_YD = 150               -- quest givers this close are one place
W.SAMPLE = 24                -- a mob's spawns looked at, at most
W.SUGGEST = 3                -- zones marked "suggested"
W.SUGGEST_MIN = 5            -- quests a zone needs to be suggested
W.zones, W.scanning, W.forLevel = {}, false, nil
W.byUi = {}                  -- { [zone map] = tally }: the same, by the map the route uses

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
        z = { zone = zoneId, quests = 0, xp = 0, class = 0, elites = 0, givers = {}, spacings = {} }
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

-------------------------------------------------------------------------------
-- How a zone levels: its quest givers' places, how far apart its mobs stand.
-------------------------------------------------------------------------------

-- Pure: points ({ x, y } in yards) in places: points within `yd` of one in
-- a place are in it too. -> how many places, and how many at the biggest.
function W.Hubs(points, yd)
    yd = yd or W.HUB_YD
    local n = #(points or {})
    if n == 0 then return 0, 0 end
    local place, places, sizes = {}, 0, {}
    for i = 1, n do
        if not place[i] then
            places = places + 1
            place[i] = places
            local queue, size = { i }, 1
            local qi = 1
            while queue[qi] do
                local a = points[queue[qi]]
                for j = 1, n do
                    if not place[j] then
                        local b = points[j]
                        if (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 <= yd * yd then
                            place[j] = places
                            queue[#queue + 1] = j
                            size = size + 1
                        end
                    end
                end
                qi = qi + 1
            end
            sizes[places] = size
        end
    end
    local biggest = 0
    for _, s in ipairs(sizes) do if s > biggest then biggest = s end end
    return places, biggest
end

-- Pure: how far apart a mob's spawns stand: the middle of each one's
-- distance to its nearest other (yards). nil with fewer than two.
function W.Spacing(points)
    local n = #(points or {})
    if n < 2 then return nil end
    local near = {}
    for i = 1, n do
        local a, best = points[i], nil
        for j = 1, n do
            if i ~= j then
                local b = points[j]
                local d = (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2
                if not best or d < best then best = d end
            end
        end
        near[#near + 1] = math.sqrt(best)
    end
    table.sort(near)
    return near[math.floor((#near + 1) / 2)]
end

-- Pure: the middle of a list of numbers (nil when empty).
function W.Middle(list)
    if not list or #list == 0 then return nil end
    local c = {}
    for i, v in ipairs(list) do c[i] = v end
    table.sort(c)
    return c[math.floor((#c + 1) / 2)]
end

-- Pure: words for how far apart the mobs stand.
W.CLOSE_YD, W.FAR_YD = 45, 110
function W.SpacingWords(yd)
    if not yd then return nil end
    local how = (yd <= W.CLOSE_YD and "close together") or (yd >= W.FAR_YD and "spread out") or "a fair walk apart"
    return string.format("about %d yd apart (%s)", math.floor(yd + 0.5), how)
end

-- Pure: which zones to mark "suggested", and why. list: tallies (with
-- quests, xp, places, biggest, spacing, elites, class, away); max: how many.
-- The most XP for your level, worth more when the quests sit together and
-- the mobs stand close, less when many need a group; never across the sea
-- while there's a zone on your continent. Sets z.suggested, z.why.
function W.Suggest(list, max)
    local scored = {}
    for _, z in ipairs(list or {}) do
        z.suggested, z.why = nil, nil
        if (z.quests or 0) >= W.SUGGEST_MIN then
            local s = z.xp or 0
            local tight = z.biggest and z.quests > 0 and z.biggest / z.quests >= 0.5
            local close = z.spacing and z.spacing <= W.CLOSE_YD
            local group = (z.elites or 0) > 0 and z.elites / z.quests >= 0.3
            if tight then s = s * 1.2 end
            if close then s = s * 1.1 end
            if group then s = s * 0.8 end
            if z.away then s = s * 0.5 end
            scored[#scored + 1] = { z = z, s = s, tight = tight, close = close }
        end
    end
    table.sort(scored, function(a, b)
        if a.s ~= b.s then return a.s > b.s end
        return tostring(a.z.name) < tostring(b.z.name)
    end)
    for i = 1, math.min(max or W.SUGGEST, #scored) do
        local e = scored[i]
        local why = { string.format("about %s XP for your level", W.Short(e.z.xp)) }
        if e.tight then why[#why + 1] = "most quests in one place" end
        if e.close then why[#why + 1] = "mobs close together" end
        if (e.z.class or 0) > 0 then why[#why + 1] = "quests for your class" end
        e.z.suggested, e.z.why = true, table.concat(why, ", ")
    end
    return scored
end

-- Pure: a zone's lines for the Zones list's tooltip.
function W.TipLines(z)
    local out = {}
    if not z then return out end
    local levels = z.min == z.max and string.format("level %d", z.min) or string.format("levels %d-%d", z.min, z.max)
    out[#out + 1] = string.format("To pick up: %d quest%s, %s, about %s XP", z.quests, z.quests == 1 and "" or "s", levels, W.Short(z.xp))
    if (z.places or 0) > 0 then
        out[#out + 1] = z.places == 1 and "Quest givers: all in one place"
            or string.format("Quest givers: in %d places, %d at the biggest", z.places, z.biggest or 0)
    end
    local sp = W.SpacingWords(z.spacing)
    if sp then out[#out + 1] = "Their mobs: " .. sp end
    if z.mobMin then
        out[#out + 1] = "Mob levels: " .. (z.mobMin == z.mobMax and tostring(z.mobMin) or (z.mobMin .. "-" .. (z.mobMax or z.mobMin)))
    end
    if (z.elites or 0) > 0 then
        out[#out + 1] = string.format("Elite: %d quest%s (bring a group)", z.elites, z.elites == 1 and "" or "s")
    end
    if (z.class or 0) > 0 then out[#out + 1] = string.format("For your class: %d quest%s", z.class, z.class == 1 and "" or "s") end
    if z.gather then out[#out + 1] = z.gather end
    if z.away then out[#out + 1] = "On another continent" end
    return out
end

-------------------------------------------------------------------------------
-- The scan.
-------------------------------------------------------------------------------

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

-- Yards across and down a zone's map (nil when the game can't say).
local sizes = {}
local function yardsOf(areaId)
    if sizes[areaId] ~= nil then return sizes[areaId] or nil end
    local Q = ns.quests
    local map = Q and Q.UiMapForArea and Q:UiMapForArea(areaId)
    local found = false
    if map and C_Map and C_Map.GetMapWorldSize then
        local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
        if ok and w and h and w > 0 and h > 0 then found = { w, h } end
    end
    sizes[areaId] = found
    return found or nil
end

-- Spots ({ x, y } in yards) from a spawn list of the zone (percent).
local function spots(list, yd, max)
    local out = {}
    for _, c in ipairs(list or {}) do
        if #out >= (max or W.SAMPLE) then break end
        if type(c) == "table" and c[1] and c[1] >= 0 then out[#out + 1] = { c[1] / 100 * yd[1], c[2] / 100 * yd[2] } end
    end
    return out
end

-- A quest's giver and mobs, added to its zone's tally.
local function looksAt(z, q)
    local Q = ns.quests
    local yd = yardsOf(q.zoneId)
    local st = q.starter
    if yd and st and st.spawns and st.spawns[q.zoneId] then
        local g = spots(st.spawns[q.zoneId], yd, 1)[1]
        if g then z.givers[#z.givers + 1] = g end
    end
    local raw, elite = q.raw or {}, false
    for _, od in ipairs(type(raw.ObjectiveData) == "table" and raw.ObjectiveData or {}) do
        local npcs = {}
        if od.Type == "monster" then npcs[1] = od.Id
        elseif od.Type == "item" then
            local item = Q:QuestieGet("GetItem", od.Id)
            for i, id in ipairs(item and item.npcDrops or {}) do
                if i > 3 then break end
                npcs[#npcs + 1] = id
            end
        end
        for _, id in ipairs(npcs) do
            local npc = Q:QuestieGet("GetNPC", id)
            if npc then
                if (tonumber(npc.rank) or 0) >= 1 then elite = true end
                local lo, hi = tonumber(npc.minLevel), tonumber(npc.maxLevel)
                if lo and lo > 0 then z.mobMin = math.min(z.mobMin or lo, lo) end
                if hi and hi > 0 then z.mobMax = math.max(z.mobMax or hi, hi) end
                local here = yd and npc.spawns and npc.spawns[q.zoneId]
                if here then
                    local d = W.Spacing(spots(here, yd))
                    if d then z.spacings[#z.spacings + 1] = d end
                end
            end
        end
    end
    if elite then z.elites = z.elites + 1 end
end

local function finish(zones)
    local Q, N = ns.quests, ns.nav
    local list = W.Rank(zones, 2)
    for i = #list, W.KEEP + 1, -1 do list[i] = nil end
    local me = N and N:PlayerPos()
    local byUi = {}
    for _, z in ipairs(list) do
        z.name = Q:ZoneName(z.zone)
        local map = Q.UiMapForArea and Q:UiMapForArea(z.zone)
        if map and me and N.ToWorld then
            local cont = N:ToWorld(map, 0.5, 0.5)
            z.away = cont ~= nil and me.cont ~= nil and cont ~= me.cont or nil
        end
        z.places, z.biggest = W.Hubs(z.givers)
        z.spacing = W.Middle(z.spacings)
        local ok, text = pcall(gatherFor, z.zone)
        z.gather = ok and text or nil
        local ui = map and N and N.ZoneOf and N.ZoneOf(map) or map
        if ui and (not byUi[ui] or byUi[ui].xp < z.xp) then
            z.ui = ui
            byUi[ui] = z
        end
    end
    W.Suggest(list)
    W.zones, W.byUi = list, byUi
    -- The Zones list in an open menu reads it next time; a note for the log.
    local names = {}
    for _, z in ipairs(list) do if z.suggested then names[#names + 1] = tostring(z.name) end end
    ns:Log("route", string.format("zones for level %s: %d with quests; suggested %s", tostring(W.forLevel), #list,
        #names > 0 and table.concat(names, ", ") or "none"))
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
                local z = W.Add(zones, q.zoneId, { level = q.level, classOnly = type(raw.requiredClasses) == "number" and raw.requiredClasses ~= 0 }, xp)
                pcall(looksAt, z, q)
            end
        end
        i = last + 1
        if i <= #ids then C_Timer.After(0, step) return end
        W.scanning, W.forLevel = false, level
        pcall(finish, zones)
    end
    C_Timer.After(0, step)
end

-- The zones with quests for your level, by the zone map the route uses
-- ({ [zone] = tally }); starts a look when it's for another level.
function W.ByZone()
    if W.forLevel ~= UnitLevel("player") then pcall(W.Scan) end
    return W.byUi or {}
end

function W.Lines()
    if W.forLevel ~= UnitLevel("player") then
        pcall(W.Scan)
        if #W.zones == 0 then return { "where next: looking through the quest data; ask again in a moment" } end
    end
    if #W.zones == 0 then return { "where next: the quest data has no zone with quests for your level that you haven't done" } end
    local out = { string.format("where next (quests you haven't done, around level %d; most XP first):", UnitLevel("player")) }
    for i, z in ipairs(W.zones) do
        if i > W.SHOW then break end
        out[#out + 1] = "  " .. W.Line(z) .. (z.suggested and (" - suggested: " .. z.why) or "")
        local sp = W.SpacingWords(z.spacing)
        if (z.places or 0) > 0 or sp then
            out[#out + 1] = string.format("      quest givers in %d place(s)%s%s", z.places or 0,
                sp and ("; mobs " .. sp) or "", (z.elites or 0) > 0 and string.format("; %d elite", z.elites) or "")
        end
    end
    out[#out + 1] = "  Pick the zones you want in the Flow Router (Route, Zones). Not judged: terrain or the trip there."
    return out
end
ns.commands.where = function()
    for i, l in ipairs(W.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end

-- The top few as lines to read (the Zones list itself shows every zone with
-- its details since 0.35.316; kept for anything that wants the short form).
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
