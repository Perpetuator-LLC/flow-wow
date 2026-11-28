-------------------------------------------------------------------------------
-- Flow - Nav/DungeonQuests.lua
-- A dungeon's quests, one row each, in its menu (0.35.426).
--
-- "I'd like to be able to see each of the quests ... an icon next to each
-- one that's like check mark for complete ... an icon for ones that we don't
-- have, and icons for ones that we're on but are not complete ... it should
-- be very clear to me which quests I can get, which ones I can't, which ones
-- I don't have the prerequisites for, and it should be telling me what the
-- next step is to get that ... Maybe I even have to do the instance first
-- ... but I need to know why."
--
-- The dungeon's menu had its quests as lines of a tooltip, and only the ones
-- of this run: the ones you'd done, couldn't do or weren't ready for were
-- numbers ("2 more next run", "Not for you (1)"). Here every quest Flow knows
-- for the dungeon is a row:
--   icon   what it is for you (DQ.Kind): done, ready to hand in, in your log,
--          to pick up, to pick up after other quests, starts inside, later,
--          not for you
--   name and level
--   hover  what it asks, who gives it and where, and the next thing to do to
--          get it (or why you can't)
--   click  a quest you can go and get: your waypoint goes to its giver (or
--          to the giver of the first quest of its chain)
-- Also the level range of a dungeon's quests, for the Dungeons list.
--
-- Reading only: the states come from Dungeons.lua (D.State), which reads
-- Questie. Nothing here is on the route.
-------------------------------------------------------------------------------

local _, ns = ...
local DQ = {}
ns.dungeonQuests = DQ

-- The game's own pictures (the ready check's, and the quest marks NPCs wear).
DQ.ICONS = {
    done = "Interface\\RaidFrame\\ReadyCheck-Ready",
    complete = "Interface\\GossipFrame\\ActiveQuestIcon",
    on = "Interface\\GossipFrame\\IncompleteQuestIcon",
    get = "Interface\\GossipFrame\\AvailableQuestIcon",
    chain = "Interface\\GossipFrame\\AvailableQuestIcon",
    inside = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    later = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    cant = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}
-- The order of the rows, and each kind in a few words.
DQ.ORDER = { "complete", "on", "get", "chain", "inside", "later", "cant", "done" }
DQ.WORDS = {
    done = "Done", complete = "In your log: ready to hand in", on = "In your log", get = "To pick up",
    chain = "To pick up, after other quests", inside = "Starts inside the dungeon", later = "Not yet", cant = "Not for you",
}

-- Pure: what a dungeon quest is for you.
--   e: { state, info, level } as Dungeons.lua has it (D.State); complete: it's in your log and finished;
--   level: yours; above: how many levels over you still count for this run
function DQ.Kind(e, complete, level, above)
    local s = e and e.state
    if s == "done" then return "done" end
    if s == "ready" then return complete and "complete" or "on" end
    if s == "notforyou" then return "cant" end
    if s == "nextrun" or s == "toolong" then return "later" end
    if level and (e.level or 0) > level + (above or 2) then return "later" end
    if s == "unlock" then return "chain" end
    if s == "inside" or s == "followup" then return "inside" end
    if s == "pickup" then return "get" end
    return "later"
end

-- Pure: the next thing to do for it, in a line or two.
--   who: { giver, zone, item } (D.QuestInfo of the quest); stepInfo(id) -> the same for a quest of its chain
function DQ.Next(e, kind, who, stepInfo, level)
    who = who or {}
    local from = who.giver and (who.giver .. (who.zone and (", " .. who.zone) or "")) or (who.item and "an item that starts it") or "its giver"
    if kind == "done" then return { "You've handed it in." } end
    if kind == "complete" then return { "Finished: hand it in." } end
    if kind == "on" then return { "In your quest log: its objectives are inside the dungeon." } end
    if kind == "get" then return { "Next: pick it up from " .. from .. "." } end
    if kind == "chain" then
        local out, n = {}, 0
        for _, st in ipairs(type(e.info) == "table" and e.info or {}) do
            n = n + 1
            local i = stepInfo and stepInfo(st.id) or {}
            local name = st.name or i.name or ("quest " .. tostring(st.id))
            if st.inLog then
                out[#out + 1] = string.format("%d. Finish %s (in your log).", n, name)
            else
                out[#out + 1] = string.format("%d. %s%s%s", n, name, st.level and string.format(" (%d)", st.level) or "",
                    i.giver and (": from " .. i.giver .. (i.zone and (", " .. i.zone) or "")) or "")
            end
        end
        table.insert(out, 1, string.format("It opens after %s:", n == 1 and "another quest" or (n .. " other quests")))
        out[#out + 1] = string.format("%d. Then pick it up from %s.", n + 1, from)
        return out
    end
    if kind == "inside" then
        if e.state == "followup" then return { "It opens during the run: after an earlier part, from someone at the entrance or inside." } end
        return { "It starts inside the dungeon (someone in there, or an item that drops there): nothing to do before you go in." }
    end
    if kind == "cant" then return { "You can't take it: " .. tostring(e.info or "it isn't for you") .. "." } end
    -- later
    if e.state == "toolong" then
        return { "Left out: " .. tostring(e.info or "a long chain of other quests comes first") .. ".",
                 "\"Only this dungeon\" takes chains twice as long." }
    end
    if e.state == "nextrun" then
        local why = tostring(e.info or "an earlier part comes first")
        if why == "after an earlier part" then
            return { "Not this run: an earlier part of this dungeon's own chain has to be done inside and handed in first." }
        end
        return { "Not yet: " .. why .. "." }
    end
    if level and (e.level or 0) > level then
        return { string.format("A level %d quest: too far above you for this run (you're %d).", e.level, level) }
    end
    return { "Not yet." }
end

-- Pure: the level range of a list of quests: "13-16", "15", or nil.
function DQ.Levels(list)
    local lo, hi
    for _, e in ipairs(list or {}) do
        local lv = tonumber(e.level)
        if lv and lv > 0 then
            if not lo or lv < lo then lo = lv end
            if not hi or lv > hi then hi = lv end
        end
    end
    if not lo then return nil end
    return lo == hi and tostring(lo) or (lo .. "-" .. hi)
end

-- Pure: the rows' order: by kind (DQ.ORDER), then level, then name.
function DQ.Sort(rows)
    local rank = {}
    for i, k in ipairs(DQ.ORDER) do rank[k] = i end
    table.sort(rows, function(a, b)
        local ra, rb = rank[a.kind] or 99, rank[b.kind] or 99
        if ra ~= rb then return ra < rb end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        return tostring(a.name) < tostring(b.name)
    end)
    return rows
end

-- Pure: how many of each kind: "2 done, 1 in your log, 3 to get, 1 not for you".
function DQ.Tally(rows)
    local n = {}
    for _, r in ipairs(rows or {}) do n[r.kind] = (n[r.kind] or 0) + 1 end
    local parts = {}
    local function add(count, words) if count > 0 then parts[#parts + 1] = count .. " " .. words end end
    add(n.done or 0, "done")
    add((n.on or 0) + (n.complete or 0), "in your log")
    add((n.get or 0) + (n.chain or 0), "to get")
    add(n.inside or 0, "inside")
    add(n.later or 0, "not yet")
    add(n.cant or 0, "not for you")
    return table.concat(parts, ", ")
end

local function icon(kind)
    return "|T" .. (DQ.ICONS[kind] or DQ.ICONS.later) .. ":14:14:0:0|t "
end
DQ.Icon = icon

-- Which of your log's quests are finished: { [id] = true }.
local function finished()
    local out = {}
    for _, q in ipairs(ns.quests and ns.quests.LogEntries and ns.quests.LogEntries() or {}) do
        if q.complete then out[q.id] = true end
    end
    return out
end

-- A run's quests as rows: { { id, name, level, kind, lines = { the hover }, point = where to go for it } }.
function DQ.Rows(run)
    local D = ns.dungeons
    local level = UnitLevel("player")
    local fin = finished()
    local rows = {}
    for _, e in ipairs(run and run.list or {}) do
        local kind = DQ.Kind(e, fin[e.id], level, D.LEVEL_ABOVE)
        local who = D.QuestInfo(e.id)
        local lines = { string.format("%s%s", tostring(e.name or who.name or ("quest " .. tostring(e.id))), e.level and string.format(" (level %d)", e.level) or ""),
                        DQ.WORDS[kind] or "" }
        local asks = D.QuestText and D.QuestText(e.id)
        if asks and asks ~= "" then lines[#lines + 1] = asks end
        for _, l in ipairs(DQ.Next(e, kind, who, D.QuestInfo, level)) do lines[#lines + 1] = l end
        -- Where to go for it: its giver, or the giver of the first quest of its chain you don't have.
        local goFor
        if kind == "get" then goFor = e.id
        elseif kind == "chain" then
            for _, st in ipairs(type(e.info) == "table" and e.info or {}) do
                if not st.inLog then goFor = st.id break end
            end
        end
        local point = goFor and D.GiverPoint and D.GiverPoint(goFor) or nil
        if point then lines[#lines + 1] = "Click: your waypoint goes to who gives " .. (goFor == e.id and "it" or "the first of those") .. "." end
        rows[#rows + 1] = { id = e.id, name = e.name or who.name, level = e.level, kind = kind, lines = lines, point = point, goFor = goFor }
    end
    return DQ.Sort(rows)
end

-- The rows as entries of the dungeon's menu.
function DQ.Items(run)
    local items = {}
    local ok, rows = pcall(DQ.Rows, run)
    if not ok then
        ns:Log("quests", "dungeon quest list failed: " .. tostring(rows))
        return items, {}
    end
    for _, r in ipairs(rows) do
        local dim = (r.kind == "done" or r.kind == "cant" or r.kind == "later")
        local text = icon(r.kind) .. (dim and "|cff999999" or "") .. tostring(r.name or "?") .. (dim and "|r" or "")
            .. (r.level and ("  |cff888888" .. r.level .. "|r") or "")
        items[#items + 1] = { text = text, stay = true, tipLines = r.lines, quest = r.id, kind = r.kind,
            func = function()
                if r.point and ns.waypoint then
                    local who = ns.dungeons.QuestInfo(r.goFor)
                    ns.waypoint:Set(r.point.map, r.point.x, r.point.y, (who.giver or "Quest giver") .. ": " .. tostring(who.name or r.name))
                end
            end }
    end
    return items, rows
end

-- /flow dungeonquests: the quests of each dungeon at your level, with what each is for you.
function DQ.Lines()
    local D = ns.dungeons
    local out = { "Flow: dungeon quests (every quest Flow knows for each dungeon at your level):" }
    local runs = D and D:Available() and D:Runs()
    if not runs then out[#out + 1] = "  not read yet (or no Questie)"; return out end
    for i, run in ipairs(runs) do
        if i > 6 then break end
        local ok, rows = pcall(DQ.Rows, run)
        out[#out + 1] = string.format("  %s (quests level %s): %s", tostring(run.name), DQ.Levels(run.list) or "?", ok and DQ.Tally(rows) or ("failed: " .. tostring(rows)))
        for _, r in ipairs(ok and rows or {}) do
            out[#out + 1] = string.format("    [%s] %s (%s) [%s]: %s", r.kind, tostring(r.name), tostring(r.level), tostring(r.id), tostring(r.lines[#r.lines - (r.point and 1 or 0)]))
        end
    end
    return out
end
ns.commands.dungeonquests = function() for _, l in ipairs(DQ.Lines()) do print(l) end end
