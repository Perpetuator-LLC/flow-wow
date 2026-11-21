-- Opening the world map (or the quest log) from a Flow link, without Flow's
-- code running the map.
--
-- Flow never calls the game's map or quest-log functions (ToggleWorldMap,
-- ShowUIPanel, QuestMapFrame_OpenToQuestDetails...): run from add-on code
-- they taint the map, and in a later fight the map's own buttons are blocked
-- (0.35.47). So "Show on map" on a step card could only say "press M".
--
-- The way round it: the game has its own buttons that open those windows
-- (the zone name over the minimap opens the map; the Quest Log button on the
-- menu bar opens the log). A secure button of Flow's, laid exactly over the
-- link while the mouse is on it, passes your click on to that button
-- (type = "click"), so the game opens its window itself, untainted. Flow's
-- part (select the quest, highlight the step) runs before and after.
--
-- The secure button is never a child of the card nor anchored to it (that
-- would make the card protected, and it couldn't open or close in a fight):
-- it sits on the screen at the link's place, worked out when the mouse
-- comes over the link. In a fight it's hidden and the link does what it
-- always did.
--
--   ns.mapOpen.Arm(link, "map" | "log", before, after) -> armed?
--   ns.mapOpen.Disarm()

local _, ns = ...
local O = {}
ns.mapOpen = O

-- The game's own buttons, by window: the first that exists is used.
O.BUTTONS = {
    map = { "MinimapCluster.ZoneTextButton", "MinimapZoneTextButton", "MiniMapWorldMapButton" },
    log = { "QuestLogMicroButton", "MinimapCluster.ZoneTextButton", "MinimapZoneTextButton", "MiniMapWorldMapButton" },
}

-- The game's button for a window (and its path), or nil. env: the tests' own.
function O.Target(kind, env)
    local GB = ns.gameButtons
    if not GB then return nil end
    return GB.Find({ frames = O.BUTTONS[kind] or {} }, env)
end

-- Pure: can the link be armed now? Not in a fight (a secure button can't be
-- placed then), not when the window is already open (the game's button would
-- close it), and only with a button of the game's to pass the click to.
function O.CanArm(inCombat, windowOpen, target)
    return (not inCombat and not windowOpen and target ~= nil) and true or false
end

-- Pure: where the button goes, in the screen's own units: the link's place
-- with a pixel to spare all round. left, bottom, width, height: the link's;
-- scale: the link's scale over the screen's.
function O.Rect(left, bottom, width, height, scale)
    if not (left and bottom and width and height) then return nil end
    scale = scale or 1
    return left * scale - 1, bottom * scale - 1, width * scale + 2, height * scale + 2
end

-- "Can 'Show on map' open the zone the step is in?" (0.35.306). Flow can't
-- turn the game's map to another zone itself (0.35.49: the map's own buttons
-- were blocked in a later fight), so it would have to pass your click to one
-- of the map's own controls that does: a zone list at its top, its row of
-- parent maps, or the quest's line beside it (which on newer clients turns
-- the map to the quest's zone). Which of those WoW: Forever has isn't known
-- yet, so /flow buttons (and the diagnostics) say, before any of it is used.
O.ZONE_CONTROLS = {
    "WorldMapZoneDropDown", "WorldMapContinentDropDown", "WorldMapZoomOutButton",
    "WorldMapFrame.ZoneDropDown", "WorldMapFrame.ContinentDropDown", "WorldMapFrame.NavBar",
}

-- The ones this client has, by path. env: the tests' own.
function O.ZoneControls(env)
    local GB, out = ns.gameButtons, {}
    if not GB then return out end
    for _, path in ipairs(O.ZONE_CONTROLS) do
        if GB.Resolve(path, env) then out[#out + 1] = path end
    end
    return out
end

-- What's laid over the map (its overlayFrames: on newer clients the zone list
-- and the row of parent maps are among them). Most have no name, so each
-- also gives a few of its own functions, which say what it is. Only reads.
-- map: the tests' own.
function O.MapOverlays(map)
    if map == nil then map = WorldMapFrame end
    local list = map and type(map.overlayFrames) == "table" and map.overlayFrames or {}
    local out = {}
    for i, f in ipairs(list) do
        local okN, name = pcall(function() return f:GetDebugName() end)
        local okT, kind = pcall(function() return f:GetObjectType() end)
        local fns = {}
        for k, v in pairs(f) do
            if type(k) == "string" and type(v) == "function" then fns[#fns + 1] = k end
        end
        table.sort(fns)
        while #fns > 6 do table.remove(fns) end
        out[#out + 1] = string.format("%s %s [%s]", (okT and kind) or "?", (okN and name) or ("#" .. i), table.concat(fns, " "))
    end
    return out
end

-- Pure: what the map did after a click passed to a quest's line. from, to:
-- the zone names before and after (nil when unknown).
function O.TurnText(questID, from, to)
    if not (from and to) then return string.format("a click passed to quest %s's line: the map's zone wasn't readable", tostring(questID)) end
    if from == to then return string.format("a click passed to quest %s's line: the map stayed on %s", tostring(questID), from) end
    return string.format("a click passed to quest %s's line: the map turned from %s to %s", tostring(questID), from, to)
end

-- The map's own bar of parent maps ("World > Kalimdor > The Barrens"), found
-- on WoW: Forever by the 0.35.306 look (WorldMapFrame.NavBar). Its buttons
-- are the game's: a click passed to one makes the game turn its map there,
-- untainted. So "Show on map" for a step in another zone can do this much
-- (0.35.331, "it needs to open to the right zone"): the first click opens
-- the map, as before, on the zone you're in; a second click on the same link
-- goes to the bar's button for the nearest map both zones are on (the
-- continent), where the step's dot shows. The zone itself is then one click
-- on the map, the game's own. (Straight to the zone would need Flow to turn
-- the map, which is what breaks its buttons in a later fight.)
-- Pure: a map and its parents, nearest first. info(id) -> { parentMapID }.
function O.Ancestors(mapID, info)
    local out, seen = {}, {}
    while mapID and mapID ~= 0 and not seen[mapID] and #out < 8 do
        out[#out + 1] = mapID
        seen[mapID] = true
        local i = info and info(mapID)
        mapID = type(i) == "table" and i.parentMapID or nil
    end
    return out
end
-- Pure: the bar's button to pass a click to, and the map it leads to. nil
-- when the map shown is the step's own or one it lies on (nothing to turn).
--   navList: the bar's buttons ({ id } or { data = { id } }), the first is "home"
function O.NavPick(stepMap, shownMap, navList, info)
    if not (stepMap and shownMap) then return nil end
    local lineage = O.Ancestors(stepMap, info)
    for _, id in ipairs(lineage) do
        if id == shownMap then return nil end
    end
    for _, id in ipairs(lineage) do
        for _, b in ipairs(navList or {}) do
            local bid = b.id or (type(b.data) == "table" and b.data.id) or nil
            if bid == id then return b, id end
        end
    end
    -- (No map in common on the bar: all the way out.)
    local home = navList and navList[1]
    if home then return home, home.id or (type(home.data) == "table" and home.data.id) or nil end
    return nil
end
-- Pure: what a click passed to the bar did.
function O.NavText(name, from, to)
    if not (from and to) then return string.format("a click passed to the map's bar (%s): the map's zone wasn't readable", tostring(name)) end
    if from == to then return string.format("a click passed to the map's bar (%s): the map stayed on %s", tostring(name), from) end
    return string.format("a click passed to the map's bar (%s): the map turned from %s to %s", tostring(name), from, to)
end
-- Pure: the words shown while a second click is ready.
function O.FollowText(kind, navName)
    if kind == "log" then return "Click again: open this quest in the log" end
    return "Click again: zoom the map out to " .. (navName or "where this step is")
end
local function mapName(id)
    local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name or (id and ("map " .. tostring(id))) or nil
end
-- The bar's button for a step on `stepMap`, with the map open. -> button, name
function O.NavTarget(stepMap)
    local bar = WorldMapFrame and WorldMapFrame.NavBar
    local list = bar and type(bar.navList) == "table" and bar.navList or nil
    if not (stepMap and list) then return nil end
    local okS, shown = pcall(function() return WorldMapFrame:GetMapID() end)
    if not okS then return nil end
    local b, id = O.NavPick(stepMap, shown, list, C_Map and C_Map.GetMapInfo)
    if not b then return nil end
    return b, mapName(id) or "the world"
end

-- The zone the map shows, by name, or nil. Only reads.
local function mapZone()
    local ok, id = pcall(function() return WorldMapFrame:GetMapID() end)
    local info = ok and id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name or (ok and id and tostring(id)) or nil
end


-------------------------------------------------------------------------------
-- The quest's section in the log, opened (0.35.391)
--
-- "I click Select in quest log ... half the time everything's collapsed and
-- I have to click like 4 things to get to it." The link's second click goes
-- to the quest's own line in the game's list, and a quest under a collapsed
-- section has no line: the link gave up and you were left to open the
-- section, find the quest and click it. Flow now opens the section first.
-- That's the game's own quest log call (ExpandQuestHeader), not a map or
-- panel function, so the map stays untainted: the game redraws its list
-- itself when the log changes.
-------------------------------------------------------------------------------
-- Pure: where a quest is in the log.
--   n: entries; info(i) -> { isHeader, isCollapsed, questID } or nil
-- -> its section's index (nil: none), is that section collapsed, is the quest
--    listed at all, the collapsed sections' indexes (last first)
function O.HeaderFor(n, info, questID)
    local header, collapsed, found = nil, false, false
    local shut = {}
    local mine, mineShut
    for i = 1, n or 0 do
        local e = info(i)
        if type(e) == "table" then
            if e.isHeader then
                header, collapsed = i, e.isCollapsed and true or false
                if collapsed then table.insert(shut, 1, i) end
            elseif e.questID == questID and questID ~= nil then
                found, mine, mineShut = true, header, collapsed
            end
        end
    end
    return mine, mineShut or false, found, shut
end
-- Pure: the sections to open, last first (so the earlier indexes still hold).
function O.ToExpand(header, collapsed, found, shut)
    if found then return (header and collapsed) and { header } or {} end
    return shut or {}       -- (not listed: it's under one of the collapsed ones)
end

local function logEntry(i)
    if C_QuestLog and C_QuestLog.GetInfo then
        local ok, e = pcall(C_QuestLog.GetInfo, i)
        if ok and type(e) == "table" then return e end
    end
    if GetQuestLogTitle then
        local ok, _, _, _, isHeader, isCollapsed, _, _, questID = pcall(GetQuestLogTitle, i)
        if ok then return { isHeader = isHeader, isCollapsed = isCollapsed, questID = questID } end
    end
    return nil
end
local function logCount()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
        if ok and type(n) == "number" then return n end
    end
    if GetNumQuestLogEntries then
        local ok, n = pcall(GetNumQuestLogEntries)
        if ok and type(n) == "number" then return n end
    end
    return 0
end

-- Opens the section a quest is under, when it's collapsed. -> how many it opened
function O.ExpandFor(questID)
    if not questID then return 0 end
    local expand = ExpandQuestHeader or (C_QuestLog and C_QuestLog.ExpandQuestHeader) or nil
    local header, collapsed, found, shut = O.HeaderFor(logCount(), logEntry, questID)
    local list = O.ToExpand(header, collapsed, found, shut)
    if #list == 0 then
        O.lastExpand = string.format("quest %s: %s", tostring(questID), found and "its section was open already" or "not in the log's list, and no section is collapsed")
        return 0
    end
    if not expand then
        O.lastExpand = string.format("quest %s: %d section(s) to open, but this client has no call to open one", tostring(questID), #list)
        return 0
    end
    local n = 0
    for _, i in ipairs(list) do
        local ok = pcall(expand, i)
        if ok then n = n + 1 end
    end
    O.lastExpand = string.format("quest %s: opened %d collapsed section(s) (%s)", tostring(questID), n, found and "its own" or "it wasn't listed, so every collapsed one")
    ns:Log("buttons", "quest log link: " .. O.lastExpand)
    return n
end

local overlay

function O.Disarm()
    if overlay and overlay:IsShown() and not InCombatLockdown() then overlay:Hide() end
    if overlay then
        overlay.link, overlay.before, overlay.after, overlay.quest = nil, nil, nil, nil
        overlay.kind, overlay.questArg, overlay.stepMap, overlay.navName, overlay.follow = nil, nil, nil, nil, nil
    end
end

local function look(link, hover)
    if not (link and link.text) then return end
    if hover then link.text:SetTextColor(1, 1, 1) else link.text:SetTextColor(0.35, 0.7, 1) end
    if ns.nav and ns.nav.ClickCursor then ns.nav:ClickCursor(hover) end
end

local function build()
    local b = CreateFrame("Button", "FlowMapOpener", UIParent, "SecureActionButtonTemplate")
    b:SetFrameStrata("TOOLTIP")
    -- (The game acts on the press or the release, by its own setting: both.)
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("type", "click")
    b:Hide()
    b:SetScript("OnEnter", function(self) look(self.link, true) end)
    b:SetScript("OnLeave", function(self)
        look(self.link, false)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        O.Disarm()
    end)
    -- Flow's part: before the game opens its window (each click event), and
    -- once after (on the release, when the window has opened either way).
    b:SetScript("PreClick", function(self, _, down)
        if down and (self.quest or self.navName) then self.zoneBefore = mapZone() end
        if down and self.before then pcall(self.before) end
    end)
    b:SetScript("PostClick", function(self, _, down)
        if down then return end
        local after, link = self.after, self.link
        local kind, before, questArg, stepMap, follow = self.kind, self.before, self.questArg, self.stepMap, self.follow
        if self.quest then O.lastTurn = O.TurnText(self.quest, self.zoneBefore, mapZone()) end
        if self.navName then O.lastNav = O.NavText(self.navName, self.zoneBefore, mapZone()) end
        look(link, false)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        O.Disarm()
        if after then pcall(after) end
        O.used = (O.used or 0) + 1
        -- The window is open now: with the mouse still on the link, the next
        -- click is made ready (the quest's line; the map's bar), and said so.
        -- (Once: the click after that is the link's own again.)
        if link and not follow and C_Timer and C_Timer.After then
            C_Timer.After(0.15, function()
                if InCombatLockdown() or not (link.IsVisible and link:IsVisible() and link:IsMouseOver()) then return end
                local ok, armed = pcall(O.Arm, link, kind, before, after, questArg, stepMap, true)
                if ok and armed and overlay then
                    look(link, true)
                    GameTooltip:SetOwner(overlay, "ANCHOR_TOP")
                    GameTooltip:AddLine(O.FollowText(kind, overlay.navName), 1, 1, 1)
                    GameTooltip:Show()
                end
            end)
        end
    end)
    return b
end
O._Overlay = function() return overlay end   -- (tests)

-- The quest's own line in the game's quest log (the list beside the map),
-- or nil: a click on it opens the quest's details, the game's way. frame:
-- the tests' own list.
function O.QuestButton(questID, frame)
    if frame == nil then frame = QuestScrollFrame end
    local pool = frame and frame.titleFramePool
    if not (questID and pool and pool.EnumerateActive) then return nil end
    for b in pool:EnumerateActive() do
        if b.questID == questID then return b end
    end
    return nil
end

-- questID (the "log" link): with the log already open, the click goes to
-- that quest's line in the game's list, so the game opens its details
-- ("it would be nice if it opened the quest log expanded, with the quest
-- selected", 0.35.204). So: one click opens the log with the quest
-- selected, the next opens the quest itself.
-- stepMap (the "map" link): with the map already open on a zone the step
-- isn't in, the click goes to the map's own bar (O.NavTarget).
-- follow: this is the second click made ready after the first.
function O.Arm(link, kind, before, after, questID, stepMap, follow)
    local target, path = O.Target(kind)
    local open = WorldMapFrame and WorldMapFrame:IsShown() and true or false
    local toLine = open and questID and not InCombatLockdown()
    local navName
    if open and kind == "map" and stepMap and not InCombatLockdown() then
        local okN, b, name = pcall(O.NavTarget, stepMap)
        if not (okN and b) then return false end   -- (the map shows the step already, or has no such bar)
        target, path, open, navName = b, "the map's own bar: " .. tostring(name), false, name
    end
    if toLine then
        local ok, b = pcall(O.QuestButton, questID)
        target, path, open = ok and b or nil, "the quest's line in the log", false
        if not target then
            -- Its section is collapsed (no line for it): open it, and be ready
            -- for the click a moment later, once the game has redrawn its list.
            local okX, opened = pcall(O.ExpandFor, questID)
            ns:Log("buttons", "quest log link: no line for quest " .. tostring(questID) .. " in the game's list (QuestScrollFrame " .. (QuestScrollFrame and "there" or "missing") .. ")")
            if okX and (opened or 0) > 0 and not follow and C_Timer and C_Timer.After then
                C_Timer.After(0.3, function()
                    if InCombatLockdown() or not (link.IsVisible and link:IsVisible() and link:IsMouseOver()) then return end
                    pcall(O.Arm, link, kind, before, after, questID, stepMap, true)
                end)
            end
            return false
        end
    end
    if not O.CanArm(InCombatLockdown() and true or false, open, target) then return false end
    local s = link:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x, y, w, h = O.Rect(link:GetLeft(), link:GetBottom(), link:GetWidth(), link:GetHeight(), s)
    if not x then return false end
    overlay = overlay or build()
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    overlay:SetSize(w, h)
    overlay:SetAttribute("clickbutton", target)
    overlay.link, overlay.before, overlay.after = link, before, after
    overlay.quest = toLine and questID or nil   -- (to note whether the game turns the map)
    overlay.kind, overlay.questArg, overlay.stepMap, overlay.navName, overlay.follow = kind, questID, stepMap, navName, follow and true or nil
    O.lastPath = path
    overlay:Show()
    return true
end

-- A fight starts: the secure button goes (it can't be moved or hidden once
-- the fight is on), and the link is the plain one again.
ns:On("PLAYER_REGEN_DISABLED", function()
    if overlay and overlay:IsShown() then overlay:Hide() end
    O.Disarm()
end)

-- /flow buttons also says which of the game's buttons these links use.
function O.Lines()
    local out = {}
    for _, kind in ipairs({ "map", "log" }) do
        local _, path = O.Target(kind)
        out[#out + 1] = string.format("%s link: %s", kind == "map" and "\"Show on map\"" or "\"Select in quest log\"",
            path and ("opens it through " .. path) or "no button of the game's found (it says which key to press)")
    end
    out[#out + 1] = string.format("opened a window through them %d time(s) this session", O.used or 0)
    local zc = O.ZoneControls()
    out[#out + 1] = "the map's own controls for other zones: " .. (#zc > 0 and table.concat(zc, ", ") or "none of the known ones")
    local okO, ov = pcall(O.MapOverlays)
    out[#out + 1] = "laid over the map: " .. ((okO and #ov > 0) and table.concat(ov, "; ") or (okO and "nothing" or ("unreadable: " .. tostring(ov))))
    out[#out + 1] = "the quest log's sections: " .. ((ExpandQuestHeader or (C_QuestLog and C_QuestLog.ExpandQuestHeader)) and "Flow can open a collapsed one" or "this client has no call to open one")
        .. (O.lastExpand and ("; last: " .. O.lastExpand) or "")
    if O.lastTurn then out[#out + 1] = O.lastTurn end
    if O.lastNav then out[#out + 1] = O.lastNav end
    local bar = WorldMapFrame and WorldMapFrame.NavBar
    out[#out + 1] = "the map's bar of parent maps: " .. ((bar and type(bar.navList) == "table") and (#bar.navList .. " button(s)") or "no list of buttons")
    return out
end
