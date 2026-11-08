-- Puts a marker above nameplates of units your quests need.
--   Skull   = kill it, with your count (e.g. 3/10)
--   Diamond = it drops an item you need, with your count (e.g. 0/1)
--   Star    = talk to / interact with it (an objective mentions its name)
--   (o)     = Flow's target marker: the unit your current stop is about (the
--             mob to kill or loot, the turn-in, quest giver or trainer), in
--             the route colour (purple on Most XP), INSTEAD of the icons
--             above (its count stays beside it); green on the party member
--             you follow. Every other unit keeps its skull / diamond / star.
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
local KIND_ICON = { kill = 8, item = 3, talk = 1 }   -- (the route stop's NPC gets Flow's (o): targetMark)

local kills = {}       -- [lower mob name] = { "3/10", ... } (one per quest)
local items = {}       -- [lower item name] = "2/6"
local dropsBy = {}     -- [lower mob name] = { [lower item name] = true } from Questie
local texts = {}       -- { lower objective text, ... } for name mentions
local plates = {}      -- [unit token] = true
local routeNames = {}  -- [lower name] = true: NPCs of your current route stop

local function db() return ns.db.quests end

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
local function addObjective(text, kind, finished, od)
    if finished or not text or text == "" then return end
    local name, count = parseObjective(text)
    local lname = name:lower()
    if kind == "monster" then
        kills[lname] = kills[lname] or {}
        table.insert(kills[lname], count or "")
    elseif kind == "item" then
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
    wipe(kills); wipe(items); wipe(texts); wipe(dropsBy)
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

    -- Objective text mentions this NPC, e.g. "Speak with Marshal McBride".
    if #marks == 0 and not UnitCanAttack("player", unit) then
        for _, t in ipairs(texts) do
            if t:find(lname, 1, true) then
                marks[#marks + 1] = { kind = "talk" }
                break
            end
        end
    end

    -- (The NPC your current route stop is about gets Flow's (o) on top: targetOf.)

    -- Modern clients can tell us directly (no count available).
    if #marks == 0 and C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
        and C_QuestLog.UnitIsRelatedToActiveQuest(unit) then
        marks[#marks + 1] = { kind = UnitCanAttack("player", unit) and "kill" or "talk" }
    end
    return marks
end

local MAX_MARKS = 3

-- Who wears Flow's (o): the NPC your current route stop is about (a turn-in,
-- a quest giver, a trainer), in the route colour (purple on Most XP), or the
-- party member you follow (Nav/Follow.lua), in your waypoint's green.
-- Returns "route", "follow" or nil.
local function targetOf(unit)
    local name = ns.api.Safe(UnitName(unit))
    if type(name) ~= "string" then return nil end
    local lname = name:lower()
    if UnitIsPlayer(unit) then
        local f = ns.follow and ns.follow:Target()
        if f and (f:match("^([^%-]+)") or f):lower() == lname then return "follow" end
        return nil
    end
    if routeNames[lname] and not UnitIsDead(unit) then return "route" end
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
        t.ring:SetVertexColor(c[1], c[2], c[3], 1)
        t.dot:SetVertexColor(c[1], c[2], c[3], 1)
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
            s.icon:SetTexture(ICON:format(KIND_ICON[mark.kind]))
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

local function updateAll()
    for unit in pairs(plates) do pcall(updateUnit, unit) end
end

-- Learn which mobs drop which quest items.
local function onLoot()
    if not (UnitExists("target") and UnitIsDead("target")) then return end
    local mob = UnitName("target")
    if not mob then return end
    for slot = 1, GetNumLootItems() do
        local _, itemName = GetLootSlotInfo(slot)
        if itemName and items[itemName:lower()] then
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

ns:On("NAME_PLATE_UNIT_ADDED", function(unit) plates[unit] = true; updateUnit(unit) end)
ns:On("NAME_PLATE_UNIT_REMOVED", function(unit)
    plates[unit] = nil
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if plate and plate.FlowQuestMark then plate.FlowQuestMark:Hide() end
end)
ns:On("QUEST_LOG_UPDATE", function() readQuests(); updateAll() end)
ns:On("PLAYER_ENTERING_WORLD", function() readQuests(); updateAll() end)
ns:On("LOOT_OPENED", onLoot)

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
        local n = 0
        for name, c in pairs(kills) do print("  kill: " .. name .. " " .. table.concat(c, ", ")); n = n + 1 end
        for name, c in pairs(items) do
            local from = {}
            for mob, list in pairs(dropsBy) do if list[name] then from[#from + 1] = mob end end
            print("  collect: " .. name .. " " .. c .. (#from > 0 and (" (drops from " .. table.concat(from, ", ") .. ")") or ""))
            n = n + 1
        end
        if n == 0 then print("  no open kill/collect objectives") end
    end
end

-- Called by the route (Nav.lua) when the current stop changes.
ns.questMarks = ns.questMarks or {}
function ns.questMarks.SetRouteTarget(names)
    wipe(routeNames)
    for _, n in ipairs(names or {}) do routeNames[n:lower()] = true end
    updateAll()
end
-- Redraw every marker (following someone started or stopped, colours changed).
function ns.questMarks.Refresh() updateAll() end
ns.questMarks._targetOf = targetOf   -- (tests)
ns.questMarks._routeNames = routeNames
