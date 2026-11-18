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

-- The zone the map shows, by name, or nil. Only reads.
local function mapZone()
    local ok, id = pcall(function() return WorldMapFrame:GetMapID() end)
    local info = ok and id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name or (ok and id and tostring(id)) or nil
end

local overlay

function O.Disarm()
    if overlay and overlay:IsShown() and not InCombatLockdown() then overlay:Hide() end
    if overlay then overlay.link, overlay.before, overlay.after, overlay.quest = nil, nil, nil, nil end
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
        O.Disarm()
    end)
    -- Flow's part: before the game opens its window (each click event), and
    -- once after (on the release, when the window has opened either way).
    b:SetScript("PreClick", function(self, _, down)
        if down and self.quest then self.zoneBefore = mapZone() end
        if down and self.before then pcall(self.before) end
    end)
    b:SetScript("PostClick", function(self, _, down)
        if down then return end
        local after, link = self.after, self.link
        if self.quest then O.lastTurn = O.TurnText(self.quest, self.zoneBefore, mapZone()) end
        look(link, false)
        O.Disarm()
        if after then pcall(after) end
        O.used = (O.used or 0) + 1
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
function O.Arm(link, kind, before, after, questID)
    local target, path = O.Target(kind)
    local open = WorldMapFrame and WorldMapFrame:IsShown() and true or false
    local toLine = open and questID and not InCombatLockdown()
    if toLine then
        local ok, b = pcall(O.QuestButton, questID)
        target, path, open = ok and b or nil, "the quest's line in the log", false
        if not target then
            ns:Log("buttons", "quest log link: no line for quest " .. tostring(questID) .. " in the game's list (QuestScrollFrame " .. (QuestScrollFrame and "there" or "missing") .. ")")
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
    O.lastPath = path
    overlay:Show()
    return true
end

-- A fight starts: the secure button goes (it can't be moved or hidden once
-- the fight is on), and the link is the plain one again.
ns:On("PLAYER_REGEN_DISABLED", function()
    if overlay and overlay:IsShown() then overlay:Hide() end
    if overlay then overlay.link, overlay.before, overlay.after, overlay.quest = nil, nil, nil, nil end
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
    if O.lastTurn then out[#out + 1] = O.lastTurn end
    return out
end
