-- Opening the world map (or the quest log) from a Flow link, without Flow's
-- code running the map.
--
-- Flow never calls the game's map or quest-log functions (ToggleWorldMap,
-- ShowUIPanel, QuestMapFrame_OpenToQuestDetails...): run from add-on code
-- they taint the map, and in a later fight the map's own buttons are blocked
-- (0.35.47). So "Show on map" on a stop card could only say "press M".
--
-- The way round it: the game has its own buttons that open those windows
-- (the zone name over the minimap opens the map; the Quest Log button on the
-- menu bar opens the log). A secure button of Flow's, laid exactly over the
-- link while the mouse is on it, passes your click on to that button
-- (type = "click"), so the game opens its window itself, untainted. Flow's
-- part (select the quest, highlight the stop) runs before and after.
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

local overlay

function O.Disarm()
    if overlay and overlay:IsShown() and not InCombatLockdown() then overlay:Hide() end
    if overlay then overlay.link, overlay.before, overlay.after = nil, nil, nil end
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
        if down and self.before then pcall(self.before) end
    end)
    b:SetScript("PostClick", function(self, _, down)
        if down then return end
        local after, link = self.after, self.link
        look(link, false)
        O.Disarm()
        if after then pcall(after) end
        O.used = (O.used or 0) + 1
    end)
    return b
end
O._Overlay = function() return overlay end   -- (tests)

function O.Arm(link, kind, before, after)
    local target, path = O.Target(kind)
    local open = WorldMapFrame and WorldMapFrame:IsShown() and true or false
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
    O.lastPath = path
    overlay:Show()
    return true
end

-- A fight starts: the secure button goes (it can't be moved or hidden once
-- the fight is on), and the link is the plain one again.
ns:On("PLAYER_REGEN_DISABLED", function()
    if overlay and overlay:IsShown() then overlay:Hide() end
    if overlay then overlay.link, overlay.before, overlay.after = nil, nil, nil end
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
    return out
end
