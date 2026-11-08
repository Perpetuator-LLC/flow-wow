-- Follow a party member: the arrow points at them in the waypoint green and
-- keeps pointing as they move, until you stop it or they leave the group.
-- Your route carries on underneath (the arrow goes back to it when you stop,
-- or while Flow can't see where they are: another continent, an instance).
-- "Waypoint at <name>" instead drops your waypoint where they are right now.
-- Where the game won't tell add-ons a party member's position, a Flow player
-- sends theirs to whoever follows them (every 2 s while asked).
--   Route menu (right-click the arrow): Follow <name> / Waypoint at <name>;
--   /flow follow <name>|off. "Following Bob (click: stop)" under the arrow.
--
-- Messages (Party.lua's addon channel):
--   W|<name>       "<name>, send me where you are" (re-sent every 4 s)
--   X|map|x|y      my position, while someone asked in the last 8 s

local _, ns = ...
local F = {}
ns.follow = F

local target          -- who you follow
local posts = {}      -- name -> { map, x, y, at } (from their messages)
local askedAt = 0     -- when someone last asked for our position
local lostSince       -- when we stopped seeing them

local function plain(n) return n and (n:match("^([^%-]+)") or n) end

-- A group member's name, however this client gives it (nil if hidden).
local function unitName(u)
    local n = ns.api.Safe((UnitName(u)))
    if type(n) ~= "string" and GetUnitName then n = ns.api.Safe(GetUnitName(u, false)) end
    return type(n) == "string" and n ~= "" and n or nil
end

local function groupUnits()
    local out = {}
    local raid = IsInRaid and IsInRaid()
    for i = 1, raid and 40 or 4 do
        local u = (raid and "raid" or "party") .. i
        if UnitExists(u) and not UnitIsUnit(u, "player") then out[#out + 1] = u end
    end
    return out
end

-- The group unit (party1, raid3...) for a name, or nil.
function F.UnitOf(name)
    if not name then return nil end
    for _, u in ipairs(groupUnits()) do
        local n = unitName(u)
        if n and plain(n):lower() == plain(name):lower() then return u end
    end
end

-- Party members you could follow: { name, ... }. Flow players who shared
-- their progress count too, even if the game hides their unit's name.
function F.Members()
    local out, seen = {}, {}
    for _, u in ipairs(groupUnits()) do
        local n = unitName(u)
        if n and not seen[plain(n):lower()] then seen[plain(n):lower()] = true; out[#out + 1] = n end
    end
    for name in pairs(ns.partyHelp and ns.partyHelp.All() or {}) do
        if not seen[plain(name):lower()] then seen[plain(name):lower()] = true; out[#out + 1] = plain(name) end
    end
    table.sort(out)
    return out
end

-- The party member a typed name means ("zed", "Zed", "Zed-Realm"), or nil.
function F.MemberNamed(text)
    text = plain(text or ""):lower()
    if text == "" then return nil end
    for _, n in ipairs(F.Members()) do
        if plain(n):lower() == text then return n end
    end
end

-- Where a party member is: map, x, y (0-1), from the game or their messages.
local function liveFrom(unit)
    if not (unit and C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local map = C_Map.GetBestMapForUnit(unit)
    local pos = map and C_Map.GetPlayerMapPosition(map, unit)
    if not pos then return nil end
    local x, y = pos:GetXY()
    x, y = ns.api.Safe(x), ns.api.Safe(y)
    if not x or not y or (x == 0 and y == 0) then return nil end
    return map, x, y
end
function F.Where(name)
    local map, x, y = liveFrom(F.UnitOf(name))
    if map then return map, x, y, "live" end
    local p = posts[name] or posts[plain(name)]
    if p and GetTime() - p.at < 6 then return p.map, p.x, p.y, "sent" end
    return nil, nil, nil, "none"
end

-------------------------------------------------------------------------------
-- The arrow (Nav.lua asks every update)
-------------------------------------------------------------------------------

local goal = { key = "user:follow", kind = "waypoint", points = {} }
function F.Choice(p)
    if not (target and p) then return nil end
    local map, x, y, source = F.Where(target)
    -- (for the diagnostics: where their position comes from, when that changes)
    if source ~= F.source then
        F.source = source
        ns:Log("follow", string.format("%s's position: %s", target, source == "live" and "from the game"
            or source == "sent" and "sent by their Flow" or "unknown (no position from the game, nothing sent by their Flow)"))
    end
    local cont, wx, wy
    if map then cont, wx, wy = ns.nav:ToWorld(map, x, y) end
    if not wx or cont ~= p.cont then
        -- Can't see them now: back to the route meanwhile, say so once.
        lostSince = lostSince or GetTime()
        if GetTime() - lostSince > 8 and not F.saidLost then
            F.saidLost = true
            ns:Print("can't see where " .. target .. " is (another zone or an instance?). The arrow is on your route until they're back in view.")
        end
        return nil
    end
    lostSince, F.saidLost = nil, nil
    local pt = { map = map, x = x, y = y, cont = cont, wx = wx, wy = wy }
    local d = math.sqrt((wx - p.wx) ^ 2 + (wy - p.wy) ^ 2)
    goal.title = "Following " .. target
    goal.text = d < 10 and ("With " .. target) or ("Following " .. target)
    goal.details = { "The arrow follows " .. target .. " as they move. Your route carries on underneath.",
                     "Right-click the arrow (or the line under it) to stop." }
    goal.points[1] = pt
    return { goal = goal, point = pt, d = d, waypoint = true, follow = true }
end

-------------------------------------------------------------------------------
-- Start / stop
-------------------------------------------------------------------------------

function F:Target() return target end

function F:Start(name)
    if not F.MemberNamed(name) then ns:Print(tostring(name) .. " isn't in your group") return end
    target, lostSince, F.saidLost, F.source = F.MemberNamed(name), nil, nil, nil
    F.Ask()
    ns:Log("follow", "following " .. target .. " (unit " .. tostring(F.UnitOf(target)) .. ")")
    ns:Print("following " .. target .. ": the arrow points at them (green) until you stop it.")
    F:RefreshToggle()
    if ns.questMarks and ns.questMarks.Refresh then pcall(ns.questMarks.Refresh) end   -- their green (o)
end

-- For /flow party and the diagnostics.
function F:Status()
    if not target then return "not following anyone" end
    local _, _, _, source = F.Where(target)
    return string.format("following %s: position %s", target,
        source == "live" and "from the game" or source == "sent" and "sent by their Flow"
        or "unknown (they need Flow 0.35.73+ if the game hides it)")
end

function F:Stop(why)
    if not target then return end
    local was = target
    target = nil
    ns:Print("stopped following " .. was .. (why and (": " .. why) or "") .. "; the arrow is back on your route")
    F:RefreshToggle()
    if ns.questMarks and ns.questMarks.Refresh then pcall(ns.questMarks.Refresh) end   -- their green (o)
end

-- Your waypoint where they are right now (it stays there).
function F:WaypointAt(name)
    local map, x, y = F.Where(name)
    if not map then F.Ask(name); ns:Print("can't see where " .. name .. " is right now; try again in a moment") return end
    if ns.waypoint then ns.waypoint:Set(map, x, y, name) end
end

-- Ask the one you follow (or `name`) for their position, if the game hides it.
function F.Ask(name)
    name = name or target
    if not name or liveFrom(F.UnitOf(name)) then return end
    if ns.party and ns.party.Send then ns.party.Send("W|" .. plain(name)) end
end

-------------------------------------------------------------------------------
-- Messages
-------------------------------------------------------------------------------

if ns.party and ns.party.handlers then
    ns.party.handlers.W = function(_, who)
        if who and plain(who):lower() == (UnitName("player") or ""):lower() then askedAt = GetTime() end
    end
    ns.party.handlers.X = function(sender, rest)
        local map, x, y = rest:match("^(%d+)|([%d%.]+)|([%d%.]+)$")
        if map then
            local e = { map = tonumber(map), x = tonumber(x), y = tonumber(y), at = GetTime() }
            posts[sender], posts[plain(sender)] = e, e   -- ("Name-Realm" or "Name")
        end
    end
end

local acc, askAcc = 0, 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
    acc, askAcc = acc + dt, askAcc + dt
    -- Someone follows you: send where you are every 2 s.
    if acc >= 2 then
        acc = 0
        if GetTime() - askedAt < 8 and ns.party and ns.party:InGroup() then
            local p = ns.nav and ns.nav:PlayerPos()
            if p then ns.party.Send(string.format("X|%d|%.4f|%.4f", p.map, p.x, p.y)) end
        end
    end
    -- You follow someone the game won't show: keep asking.
    if askAcc >= 4 then
        askAcc = 0
        if target then F.Ask() end
    end
end)

-------------------------------------------------------------------------------
-- UI: menu items, the line under the arrow
-------------------------------------------------------------------------------

-- Menu entries (the route menu's "Your waypoint" section): follow each party
-- member, or drop your waypoint where they are.
function F:MenuItems()
    local items = {}
    if target then
        items[#items + 1] = { text = "Stop following " .. target, func = function() F:Stop() end }
    end
    for _, n in ipairs(F.Members()) do
        items[#items + 1] = { text = "Follow " .. n .. " (the arrow follows them)", radio = true, checked = target == n,
            func = function() if target == n then F:Stop() else F:Start(n) end end }
        items[#items + 1] = { text = "Waypoint at " .. n .. " (where they are now)", func = function() F:WaypointAt(n) end }
    end
    return items
end

function F:RefreshToggle()
    local arrow = _G.FlowNavArrow
    if not arrow then return end
    if not self.toggle then
        local t = CreateFrame("Button", nil, arrow)
        t:SetSize(180, 16)
        t:SetPoint("TOP", arrow, "BOTTOM", 0, -66)
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t.text:SetAllPoints()
        t:SetScript("OnClick", function() F:Stop() end)
        self.toggle = t
    end
    if not target then self.toggle:Hide() return end
    self.toggle.text:SetText(string.format("|cff%sFollowing %s|r  |cff888888(click: stop)|r", ns.theme.waypoint.hex, target))
    self.toggle:Show()
end

-- They left the group, or you did: stop.
ns:On("GROUP_ROSTER_UPDATE", function()
    -- (After a moment: the roster settles first. Out of the group entirely,
    -- or no longer a member by name.)
    C_Timer.After(1, function()
        if target and (not (ns.party and ns.party:InGroup()) or not F.MemberNamed(target)) then
            F:Stop("they're not in your group any more")
        end
    end)
end)

function F:Command(arg)
    arg = arg or ""
    if arg == "" then
        ns:Print(target and ("following " .. target) or "not following anyone")
        print("  /flow follow <name>|off   party: " .. table.concat(F.Members(), ", "))
        return
    end
    if arg:lower() == "off" or arg:lower() == "stop" then F:Stop() return end
    for _, n in ipairs(F.Members()) do
        if n:lower() == arg:lower() then F:Start(n) return end
    end
    ns:Print(arg .. " isn't in your group")
end
ns.commands.follow = function(arg) F:Command(arg) end
