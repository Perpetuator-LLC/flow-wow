-- Puts a marker above nameplates of units your quests need.
--   Skull   = kill it, with your count (e.g. 3/10)
--   Diamond = it drops an item you need, with your count (e.g. 0/1)
--   Star    = talk to / interact with it (an objective mentions its name)
--   (o)     = Flow's target marker: the unit your current step is about (the
--             mob to kill or loot, the turn-in, quest giver or trainer), and
--             every mob or NPC of the other steps right by it (your waypoint's
--             area), in the route colour (purple on Most XP), INSTEAD of the
--             icons above (its count stays beside it); green on the party
--             member you follow. Every other unit keeps its skull / diamond / star.
-- One mob can show several, side by side: e.g. skull 3/10 and diamond 0/1
-- when one quest wants it dead and another wants something it drops.
--
-- Markers sit on nameplates, so nameplates must be on: V toggles enemy
-- nameplates, Shift+V friendly ones (needed for NPC markers).
--
-- Which mob drops which item comes from Questie + QuestieDB when installed;
-- without them it's learned the first time you loot the item from a mob.

local _, ns = ...

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local KIND_ICON = { kill = 8, item = 3, talk = 1 }   -- (the route step's NPC gets Flow's (o): targetMark)
-- A yellow "!": this mob drops an item that starts a quest you can take
-- (instead of Questie's "!" at every spawn on the map: QuestData.lua).
local KIND_TEXTURE = { drop = "Interface\\GossipFrame\\AvailableQuestIcon" }
local dropStarts = {}  -- [lower mob name] = item name

local kills = {}       -- [lower mob name] = { "3/10", ... } (one per quest)
local items = {}       -- [lower item name] = "2/6"
local dropsBy = {}     -- [lower mob name] = { [lower item name] = true } from Questie
local texts = {}       -- { lower objective text, ... } for name mentions
local plates = {}      -- [unit token] = true
local routeNames = {}  -- [lower name] = true: NPCs of your current route step

local function db() return ns.db.quests end
ns.questMarks = ns.questMarks or {}

-------------------------------------------------------------------------------
-- Mobs a profession wants (0.35.319). "It is telling me that along my path I
-- should be collecting Kodo meat and Strider meat. And I was just by some and
-- I didn't realize I should have been killing them. Can we put a different
-- kind of icon above them that shows the profession ... and add to the
-- tooltip that we need to kill this for cooking." The route's "Loot Kodo
-- Meat" steps (SkillPlan.lua: key farm:<item>, with prof, loot, have, need
-- and the mobs that drop it) are along the way, never a step of their own,
-- so nothing marked their mobs. Now each of them gets the profession's icon
-- over its nameplate, with your count, and a Flow line in its tooltip.
-------------------------------------------------------------------------------

ns.questMarks.PROF_FALLBACK = "Interface\\GossipFrame\\TrainerGossipIcon"
-- Pure: { [lower mob name] = { prof, loot, have, need, icon } } from route
-- steps. iconOf(prof) -> the profession's icon.
function ns.questMarks.ProfMobs(goals, iconOf)
    local out = {}
    for _, g in ipairs(goals or {}) do
        if type(g) == "table" and type(g.key) == "string" and g.key:find("^farm:") and g.prof then
            for _, mob in ipairs(g.npcs or {}) do
                local k = tostring(mob):lower()
                if not out[k] then
                    out[k] = { prof = g.prof, loot = g.loot, have = g.have, need = g.need,
                               icon = (iconOf and iconOf(g.prof)) or ns.questMarks.PROF_FALLBACK }
                end
            end
        end
    end
    return out
end
-- Pure: the tooltip's line: "Flow: loot Kodo Meat for Cooking, 0 -> 8".
function ns.questMarks.TipLine(pm)
    local count = (pm.have and pm.need) and (", " .. ns.Progress(pm.have, pm.need)) or ""
    return string.format("Flow: loot %s for %s%s", tostring(pm.loot or "what it drops"), tostring(pm.prof), count)
end
-- The route's steps that ask for a profession's drops, looked at every 2 s.
local profMobs, profAt = {}, -10
local function profMobsNow()
    local now = GetTime()
    if now - profAt < 2 then return profMobs end
    profAt = now
    local N, D = ns.nav, ns.disposition
    local goals = {}
    for _, g in ipairs(N and N.alongGoals or {}) do goals[#goals + 1] = g end
    for _, s in ipairs(N and N.plan or {}) do goals[#goals + 1] = s.goal end
    profMobs = ns.questMarks.ProfMobs(goals, function(p) return D and D.PROF_ICON and D.PROF_ICON[p] end)
    return profMobs
end

-- "Kobold Vermin slain: 3/10" or "3/10 Kobold Vermin slain" -> "Kobold Vermin", "3/10"
local function parseObjective(text)
    local count = text:match("(%d+%s*/%s*%d+)")
    local s = text:gsub("%d+%s*/%s*%d+", "")
    s = s:gsub("%s*:%s*$", ""):gsub("^%s*:?%s*", "")
    s = s:gsub("%s+[Ss]lain$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return s, count and count:gsub("%s", "") or nil
end

-- odItem: Questie's objective data for this objective (if available), so
-- item objectives know which mobs drop the item without having to learn it.
-- Pure: "3/5" -> have, need (nil, nil when it isn't a count).
function ns.questMarks.Count(count)
    local have, need = tostring(count or ""):match("^(%d+)/(%d+)$")
    return tonumber(have), tonumber(need)
end
-- Is enough of an objective's item in your bank (with what's in your bags)?
function ns.questMarks.InBank(itemId, count)
    local QB = ns.questBags
    if not (QB and QB.InBank and itemId) then return false end
    local have, need = ns.questMarks.Count(count)
    return QB.InBank(itemId, need, have) and true or false
end
local banked = {}   -- [item name, lower case] = its count: asked for, and in your bank
ns.questMarks._banked = banked   -- (tests, the diagnostics)
local function addObjective(text, kind, finished, od)
    if finished or not text or text == "" then return end
    local name, count = parseObjective(text)
    local lname = name:lower()
    if kind == "monster" then
        kills[lname] = kills[lname] or {}
        table.insert(kills[lname], count or "")
    elseif kind == "item" then
        -- (0.35.398: enough of it lies in your bank: you have it. No mark on the
        -- mobs that drop it, no "0/1" in their tooltips: you wouldn't even get
        -- the drop. The route has a step to take it out instead, Goals.lua.)
        if od and od.Type == "item" and ns.questMarks.InBank(od.Id, count) then
            banked[lname] = count or ""
            return
        end
        items[lname] = count or ""
        local item = od and od.Type == "item" and ns.quests:QuestieGet("GetItem", od.Id)
        for _, npcId in ipairs(item and item.npcDrops or {}) do
            local npc = ns.quests:QuestieGet("GetNPC", npcId)
            if npc and npc.name then
                local key = npc.name:lower()
                dropsBy[key] = dropsBy[key] or {}
                dropsBy[key][lname] = true
            end
        end
    end
    texts[#texts + 1] = text:lower()
end

local function questieObjectives(questID)
    local q = questID and ns.quests.QuestieGet and ns.quests:QuestieGet("GetQuest", questID)
    return q and q.ObjectiveData or {}
end

local function readQuests()
    wipe(kills); wipe(items); wipe(texts); wipe(dropsBy); wipe(banked)
    if C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local ods = questieObjectives(info.questID)
                for j, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                    addObjective(o.text, o.type, o.finished, ods[j])
                end
            end
        end
    elseif GetNumQuestLogEntries then
        for i = 1, GetNumQuestLogEntries() do
            local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
            if not isHeader then
                local ods = questieObjectives(questID)
                for j = 1, GetNumQuestLeaderBoards(i) do
                    local text, kind, finished = GetQuestLogLeaderBoard(j, i)
                    addObjective(text, kind, finished, ods[j])
                end
            end
        end
    end
end

-- Returns a list of { kind, label } marks for a unit. One mob can need
-- several: e.g. a kill count for one quest and a book drop for another.
local function classify(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return {} end
    local name = ns.api.Safe(UnitName(unit))
    if not name then return {} end
    local lname = name:lower()
    local marks = {}

    for _, label in ipairs(kills[lname] or {}) do
        marks[#marks + 1] = { kind = "kill", label = label }
    end

    -- Items this mob drops: from Questie, or learned when you looted one.
    local seen = {}
    for _, source in ipairs({ dropsBy[lname] or {}, db().drops[lname] or {} }) do
        for item in pairs(source) do
            if items[item] and not seen[item] then
                seen[item] = true
                marks[#marks + 1] = { kind = "item", label = items[item] }
            end
        end
    end

    -- A profession wants what it drops (Kodo Meat for Cooking): its icon, your count.
    local pm = profMobsNow()[lname]
    if pm and UnitCanAttack("player", unit) then
        marks[#marks + 1] = { kind = "prof", icon = pm.icon,
                              label = (pm.have and pm.need) and (pm.have .. "/" .. pm.need) or "" }
    end

    -- Objective text mentions this NPC, e.g. "Speak with Marshal McBride".
    if #marks == 0 and not UnitCanAttack("player", unit) then
        for _, t in ipairs(texts) do
            if t:find(lname, 1, true) then
                marks[#marks + 1] = { kind = "talk" }
                break
            end
        end
    end

    -- (The NPC your current route step is about gets Flow's (o) on top: targetOf.)

    -- It drops an item that starts a quest you can take: a yellow "!".
    if dropStarts[lname] then marks[#marks + 1] = { kind = "drop" } end

    -- Modern clients can tell us directly (no count available).
    if #marks == 0 and C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
        and C_QuestLog.UnitIsRelatedToActiveQuest(unit) then
        marks[#marks + 1] = { kind = UnitCanAttack("player", unit) and "kill" or "talk" }
    end
    return marks
end

local MAX_MARKS = 3

-- Who wears Flow's (o): the NPC your current route step is about (a turn-in,
-- a quest giver, a trainer), in the route colour (purple on Most XP); the
-- NPCs of your next few steps, a smaller and fainter (o) (walking into a
-- camp, everyone you need there is marked: Pyall Silentstride, the cooking
-- trainer, was step 2 and got no mark); or the party member you follow
-- (Nav/Follow.lua), in your waypoint's green.
-- Returns "route", "next", "follow" or nil.
local function targetOf(unit)
    local name = ns.api.Safe(UnitName(unit))
    if type(name) ~= "string" then return nil end
    local lname = name:lower()
    if UnitIsPlayer(unit) then
        local f = ns.follow and ns.follow:Target()
        if f and (f:match("^([^%-]+)") or f):lower() == lname then return "follow" end
        return nil
    end
    local rank = routeNames[lname]
    if not rank or UnitIsDead(unit) then return nil end
    -- Units of the steps at your waypoint (mobs, and NPCs to heal or talk to:
    -- Yang's Injured Deathguards were step 2): the (o) too.
    if rank == "here" then return "route" end
    if rank ~= "next" then return "route" end
    -- Later steps: friendly NPCs only (mobs to kill keep their skull/diamond).
    if UnitCanAttack("player", unit) then return nil end
    return "next"
end

-- Flow's target marker: a ring in the colour, a dark gap, the dot (as on the
-- map and minimap), with a thin black outline so it reads on any background.
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function targetMark(m)
    if m.target then return m.target end
    local t = CreateFrame("Frame", nil, m)
    t:SetSize(24, 24)
    t.edge = t:CreateTexture(nil, "BACKGROUND")
    t.edge:SetPoint("TOPLEFT", -2, 2); t.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    t.edge:SetTexture(CIRCLE); t.edge:SetVertexColor(0, 0, 0, 0.9)
    t.ring = t:CreateTexture(nil, "BORDER")
    t.ring:SetAllPoints(); t.ring:SetTexture(CIRCLE)
    t.hole = t:CreateTexture(nil, "ARTWORK", nil, 1)
    t.hole:SetPoint("TOPLEFT", 3, -3); t.hole:SetPoint("BOTTOMRIGHT", -3, 3)
    t.hole:SetTexture(CIRCLE); t.hole:SetVertexColor(0.05, 0.05, 0.08, 1)
    t.dot = t:CreateTexture(nil, "ARTWORK", nil, 2)
    t.dot:SetPoint("TOPLEFT", 7, -7); t.dot:SetPoint("BOTTOMRIGHT", -7, 7)
    t.dot:SetTexture(CIRCLE)
    -- The objective's count stays next to it (the skull's or diamond's "3/10").
    t.count = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.count:SetPoint("LEFT", t, "RIGHT", 2, 0)
    t:Hide()
    m.target = t
    return t
end

-- What a nameplate shows: the unit you're heading to gets only the (o), with
-- the count of its objective beside it (no skull or diamond on top of it as
-- well); every other unit keeps its skull / diamond / star.
-- Returns the marks to draw and the (o)'s count text.
function ns.QuestMarksLayout(marks, tgt)
    if not tgt then return marks, nil end
    return {}, marks[1] and marks[1].label or nil
end

-- Pure: the picture for a mark: its own (a profession's icon), its kind's,
-- or the raid icon of its kind; and whether it's an icon to trim the edge of.
function ns.questMarks.MarkTexture(mark)
    if mark.icon then return mark.icon, true end
    if KIND_TEXTURE[mark.kind] then return KIND_TEXTURE[mark.kind], false end
    return ICON:format(KIND_ICON[mark.kind] or 1), false
end

-- A row of up to 3 icons above the nameplate, each with its own count.
local function markerFor(plate)
    if plate.FlowQuestMark then return plate.FlowQuestMark end
    local m = CreateFrame("Frame", nil, plate)
    m:SetSize(1, 22)
    m:SetPoint("BOTTOM", plate, "TOP", 0, 4)
    m:SetFrameLevel(plate:GetFrameLevel() + 10)
    m.slots = {}
    for i = 1, MAX_MARKS do
        local s = CreateFrame("Frame", nil, m)
        s:SetSize(20, 20)
        s.icon = s:CreateTexture(nil, "OVERLAY")
        s.icon:SetAllPoints()
        s.count = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s.count:SetPoint("LEFT", s, "RIGHT", 1, 0)
        s:Hide()
        m.slots[i] = s
    end
    plate.FlowQuestMark = m
    return m
end

local function updateUnit(unit)
    if not C_NamePlate then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local on = ns.db.quests.enabled
    local marks = on and classify(unit) or {}
    local tgt = on and targetOf(unit) or nil
    if #marks == 0 and not tgt then
        if plate.FlowQuestMark then plate.FlowQuestMark:Hide() end
        return
    end
    local m = markerFor(plate)
    -- The unit you're heading to: just the (o), with its objective's count.
    local count
    marks, count = ns.QuestMarksLayout(marks, tgt)
    local t = targetMark(m)
    if tgt then
        local c = tgt == "follow" and ns.theme.waypoint or ns.theme.route
        local soon = tgt == "next"   -- a later step: smaller, fainter
        t.ring:SetVertexColor(c[1], c[2], c[3], soon and 0.6 or 1)
        t.dot:SetVertexColor(c[1], c[2], c[3], soon and 0.6 or 1)
        t:SetSize(soon and 17 or 24, soon and 17 or 24)
        t.count:SetText(count or "")
        t:ClearAllPoints()
        t:SetPoint("CENTER", m, "CENTER", 0, 0)
        t:Show()
    else
        t:Hide()
    end
    -- Lay the icons out left to right, centred over the nameplate.
    local widths, total = {}, 0
    for i = 1, MAX_MARKS do
        local s, mark = m.slots[i], marks[i]
        if mark then
            local tex, trim = ns.questMarks.MarkTexture(mark)
            s.icon:SetTexture(tex)
            if trim then s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else s.icon:SetTexCoord(0, 1, 0, 1) end
            s.count:SetText(mark.label or "")
            widths[i] = 20 + (mark.label and mark.label ~= "" and (s.count:GetStringWidth() + 4) or 0)
            total = total + widths[i]
            s:Show()
        else
            s:Hide()
        end
    end
    local x = -total / 2
    for i = 1, MAX_MARKS do
        if marks[i] then
            m.slots[i]:ClearAllPoints()
            m.slots[i]:SetPoint("LEFT", m, "CENTER", x, 0)
            x = x + widths[i]
        end
    end
    m:Show()
end

local safeUpdate
local function updateAll()
    for unit in pairs(plates) do safeUpdate(unit) end
end

-- Learn which mobs drop which quest items.
local function onLoot()
    if not (UnitExists("target") and UnitIsDead("target")) then return end
    -- (The game may hide a name: indexing a hidden one was blocked and
    -- logged as taint from Flow, 0.35.315. Unwrapped first; nil = hidden.)
    local mob = ns.api.Safe(UnitName("target"))
    if type(mob) ~= "string" then return end
    for slot = 1, (ns.api.Safe(GetNumLootItems()) or 0) do
        local _, itemName = GetLootSlotInfo(slot)
        itemName = ns.api.Safe(itemName)
        if type(itemName) == "string" and items[itemName:lower()] then
            local key = mob:lower()
            db().drops[key] = db().drops[key] or {}
            if not db().drops[key][itemName:lower()] then
                db().drops[key][itemName:lower()] = true
                ns:Print(string.format("learned: %s drops %s", mob, itemName))
            end
        end
    end
end

ns:OnLoad(function(saved)
    saved.quests = saved.quests or {}
    saved.quests.drops = saved.quests.drops or {}
    if saved.quests.enabled == nil then saved.quests.enabled = true end
end)

-- (A marker that fails says so in the log, once per reason: "the Greater
-- Plainstriders have no icon but they drop the items", 0.35.204.)
local failed = {}
function safeUpdate(unit)
    local ok, err = pcall(updateUnit, unit)
    if not ok and not failed[tostring(err)] then
        failed[tostring(err)] = true
        ns:Log("marks", "a nameplate marker failed: " .. tostring(err))
    end
end
ns:On("NAME_PLATE_UNIT_ADDED", function(unit) plates[unit] = true; safeUpdate(unit) end)
ns:On("NAME_PLATE_UNIT_REMOVED", function(unit)
    plates[unit] = nil
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if plate and plate.FlowQuestMark then plate.FlowQuestMark:Hide() end
end)
-- Mobs that drop a quest-starting item you could use (QuestData.lua).
local function readDrops()
    wipe(dropStarts)
    local ok, list = pcall(ns.quests.Drops, ns.quests)
    for _, d in ipairs(ok and list or {}) do
        for _, mob in ipairs(d.info.mobs) do dropStarts[mob:lower()] = d.info.item end
    end
end
ns.questMarks = ns.questMarks or {}
ns.questMarks._dropStarts = dropStarts   -- (tests)
-- The icons sit on nameplates. With enemy nameplates off there is nothing to
-- put them on ("still not seeing the icons, no mark on quest mobs": the
-- diagnostics said "0 nameplates in view; enemy nameplates off", 0.35.205).
-- Flow says so once a session, when a quest of yours wants mobs.
-- Pure: say it? wants: you have a kill or collect objective.
function ns.questMarks.PlatesNote(enabled, wants, cvar, told)
    return (enabled and wants and not told and tostring(cvar) == "0") and true or false
end
local toldPlates = false
local function platesNote()
    if not next(kills) and not next(items) then return end
    local cvar = GetCVar and GetCVar("nameplateShowEnemies")
    if not ns.questMarks.PlatesNote(db().enabled, true, cvar, toldPlates) then return end
    toldPlates = true
    ns:Print("your enemy nameplates are off, so Flow can't mark quest mobs (the skull, diamond and count sit on nameplates). Press V to turn them on, or type /flow quest plates.")
end
ns:On("QUEST_LOG_UPDATE", function() readQuests(); pcall(readDrops); updateAll(); pcall(platesNote) end)
ns:On("PLAYER_LEVEL_UP", function() C_Timer.After(5, function() pcall(readDrops); updateAll() end) end)
ns:On("PLAYER_ENTERING_WORLD", function() readQuests(); updateAll() end)
ns:On("LOOT_OPENED", onLoot)
-- (Looted some Kodo Meat: the profession mobs' counts follow.)
ns:On("BAG_UPDATE_DELAYED", function() if next(profMobs) then profAt = -10; updateAll() end end)

-- What /flow quest prints (and the diagnostics keep): your open objectives,
-- who drops what, and each nameplate in view with the marks it got.
ns.questMarks = ns.questMarks or {}
function ns.questMarks.Lines()
    local out = {}
    local function add(l) out[#out + 1] = l end
    local n = 0
    for name, c in pairs(kills) do add("  kill: " .. name .. " " .. table.concat(c, ", ")); n = n + 1 end
    for name, c in pairs(items) do
        local from = {}
        for mob, list in pairs(dropsBy) do if list[name] then from[#from + 1] = mob end end
        add("  collect: " .. name .. " " .. c .. (#from > 0 and (" (drops from " .. table.concat(from, ", ") .. ")") or ""))
        n = n + 1
    end
    for name, c in pairs(banked) do add("  in your bank: " .. name .. " " .. c .. " (enough with what you carry: not marked on the mobs that drop it)") end
    if n == 0 then add("  no open kill/collect objectives") end
    for mob, pm in pairs(profMobsNow()) do
        add(string.format("  for %s: %s drops %s (%s)", tostring(pm.prof), mob, tostring(pm.loot),
            (pm.have and pm.need) and (pm.have .. "/" .. pm.need) or "?"))
    end
    -- What Flow learned from your own looting, for the items you need now.
    for mob, list in pairs(db().drops or {}) do
        for item in pairs(list) do
            if items[item] then add("  learned: " .. mob .. " drops " .. item) end
        end
    end
    -- The nameplates in view and what each got (for "this mob has no icon").
    local shown = 0
    for unit in pairs(plates) do
        local okN, name = pcall(function() return ns.api.Safe(UnitName(unit)) end)
        local okM, marks = pcall(classify, unit)
        local okT, tgt = pcall(targetOf, unit)
        local kinds = {}
        for _, m in ipairs(okM and marks or {}) do kinds[#kinds + 1] = m.kind .. (m.label and m.label ~= "" and (" " .. m.label) or "") end
        add(string.format("  plate %s: %s -> %s%s%s", unit, okN and tostring(name) or "name hidden",
            #kinds > 0 and table.concat(kinds, ", ") or "no mark",
            okT and tgt and (", (o) " .. tgt) or "", okM and "" or (" [failed: " .. tostring(marks) .. "]")))
        shown = shown + 1
    end
    local cvar = GetCVar and GetCVar("nameplateShowEnemies")
    add(string.format("  %d nameplate(s) in view; markers %s; enemy nameplates %s", shown, db().enabled and "on" or "off", tostring(cvar) == "1" and "on" or "off (V)"))
    return out
end

ns.commands.quest = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.quests.enabled = (arg == "on")
        updateAll()
        ns:Print("quest markers " .. arg)
    elseif arg == "plates" then
        if InCombatLockdown and InCombatLockdown() then
            ns:Print("can't change nameplate settings in combat; try again after the fight")
            return
        end
        SetCVar("nameplateShowEnemies", 1)
        SetCVar("nameplateShowFriends", 1)
        ns:Print("enemy and friendly nameplates turned on")
    else
        ns:Print("/flow quest on|off|plates")
        for _, l in ipairs(ns.questMarks.Lines()) do print(l) end
    end
end

-- Called by the route (Nav.lua) when the current step changes: the current
-- step's NPCs, the NPCs of the next few steps, and the mobs of the steps at
-- your waypoint (names).
ns.questMarks = ns.questMarks or {}
function ns.questMarks.SetRouteTarget(names, nextNames, hereNames)
    wipe(routeNames)
    for _, n in ipairs(nextNames or {}) do routeNames[n:lower()] = "next" end
    for _, n in ipairs(hereNames or {}) do routeNames[n:lower()] = "here" end
    for _, n in ipairs(names or {}) do routeNames[n:lower()] = "current" end
    updateAll()
end
function ns.questMarks.RouteRank(name) return routeNames[(name or ""):lower()] end   -- (tests)
-- Redraw every marker (following someone started or stopped, colours changed).
function ns.questMarks.Refresh() updateAll() end
ns.questMarks._targetOf = targetOf   -- (tests)

-- Their tooltip: a Flow line under the game's own ("the tooltip normally
-- doesn't show for these kinds of things, it only shows the quest mobs").
local function unitOf(tt)
    if not tt.GetUnit then return nil end
    local ok, _, unit = pcall(tt.GetUnit, tt)
    unit = ok and ns.api.Safe(unit) or nil
    return type(unit) == "string" and unit or nil
end
local function addProfLine(tt)
    if not db().enabled then return end
    local unit = unitOf(tt)
    if not unit or ns.api.Safe(UnitIsPlayer(unit)) then return end
    local name = ns.api.Safe(UnitName(unit))
    if type(name) ~= "string" then return end
    local pm = profMobsNow()[name:lower()]
    if not pm then return end
    tt:AddLine(string.format("|T%s:14:14|t %s", pm.icon, ns.questMarks.TipLine(pm)), 1, 0.82, 0.25)
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt ~= GameTooltip then return end
        pcall(addProfLine, tt)
    end)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(addProfLine, tt) end)
end
ns.questMarks._addProfLine = addProfLine   -- (tests)
ns.questMarks._routeNames = routeNames
