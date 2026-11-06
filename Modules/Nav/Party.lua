-- Shared party route. Everyone in the party who has Flow can share one route
-- and edit it; nobody owns it.
--   /flow party share   share your current trip plan with the party
--   (others get a Join prompt; /flow party join also works)
--   Editing while joined, by anyone: click a checkpoint or advice row (moves
--   it to the front, or adds it), set a waypoint (added at the front),
--   arrive at a stop (it's removed for everyone).
--   /flow party leave   go back to your own route
--
-- Sync: every edit bumps a counter and sends the whole route over the hidden
-- addon channel. The highest counter wins; on a tie, the alphabetically
-- later name wins. So everyone ends up with the same route without anyone
-- owning it.

local _, ns = ...
local P = {}
ns.party = P

local PREFIX = "FlowWoW"
local MAX_STOPS = 15

local state = { joined = false, clock = 0, editor = "", stops = {} }
local offer          -- latest route shared by someone while you're not joined
local incoming = {}  -- sender -> { clock, total, stops }
local counter = 0

local function me() return UnitName("player") or "?" end

local function channel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
end

local function send(msg)
    local ch = channel()
    if not ch then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, ch)
    elseif SendAddonMessage then
        SendAddonMessage(PREFIX, msg, ch)
    end
end

local function clean(s) return (tostring(s or ""):gsub("[|~]", "")) end

local function encode(s)
    return table.concat({ s.id, s.map, string.format("%.4f", s.x), string.format("%.4f", s.y),
        s.level or "", s.kind or "", clean(s.label):sub(1, 60) }, "~")
end

local function decode(str)
    local f = {}
    for part in (str .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
    if #f < 7 then return nil end
    return { id = f[1], map = tonumber(f[2]), x = tonumber(f[3]), y = tonumber(f[4]),
             level = tonumber(f[5]), kind = f[6] ~= "" and f[6] or nil, label = f[7] }
end

local function newId()
    counter = counter + 1
    return me() .. counter .. "-" .. (state.clock + 1)
end

local function changed()
    if ns.nav then ns.nav:Collect(); ns.nav.planDirty = true end
end

-------------------------------------------------------------------------------
-- Sending and receiving
-------------------------------------------------------------------------------

function P:Broadcast()
    send(string.format("B|%d|%d", state.clock, #state.stops))
    for i, s in ipairs(state.stops) do
        send(string.format("S|%d|%d|%s", state.clock, i, encode(s)))
    end
    send(string.format("E|%d", state.clock))
end

-- Newer edit wins; ties go to the later name.
local function newer(clock, editor)
    return clock > state.clock or (clock == state.clock and editor > state.editor)
end

local function received(sender, msg)
    local kind, rest = msg:match("^(%a)|(.*)$")
    if kind == "B" then
        local clock, total = rest:match("^(%d+)|(%d+)$")
        incoming[sender] = { clock = tonumber(clock), total = tonumber(total), stops = {} }
    elseif kind == "S" then
        local clock, i, body = rest:match("^(%d+)|(%d+)|(.*)$")
        local inc = incoming[sender]
        if inc and inc.clock == tonumber(clock) then inc.stops[tonumber(i)] = decode(body) end
    elseif kind == "E" then
        local inc = incoming[sender]
        incoming[sender] = nil
        if not inc or inc.clock ~= tonumber(rest) then return end
        local stops = {}
        for i = 1, inc.total do if inc.stops[i] then stops[#stops + 1] = inc.stops[i] end end
        if state.joined then
            if newer(inc.clock, sender) then
                state.stops, state.clock, state.editor = stops, inc.clock, sender
                changed()
                ns:Print(sender .. " updated the shared route (" .. #stops .. " stops)")
            end
        else
            offer = { clock = inc.clock, editor = sender, stops = stops }
            P:ShowPrompt(sender, #stops)
        end
    elseif kind == "Q" then
        -- Someone asked for the current route (just joined the group).
        if state.joined then P:Broadcast() end
    end
end

-------------------------------------------------------------------------------
-- Editing (any member)
-------------------------------------------------------------------------------

local function edit(fn)
    fn(state.stops)
    while #state.stops > MAX_STOPS do table.remove(state.stops) end
    state.clock = state.clock + 1
    state.editor = me()
    P:Broadcast()
    changed()
end

function P:Active() return state.joined end
function P:Stops() return state.stops end

function P:MoveFirst(id)
    edit(function(stops)
        for i, s in ipairs(stops) do
            if s.id == id then table.insert(stops, 1, table.remove(stops, i)) return end
        end
    end)
end

-- Adds a place at the front of the shared route.
function P:AddFront(map, x, y, label, level, kind)
    edit(function(stops)
        table.insert(stops, 1, { id = newId(), map = map, x = x, y = y, label = label, level = level, kind = kind })
    end)
end

-- One of your own goals -> shared stop (uses its spot closest to you).
function P:AddGoal(goal)
    local p = ns.nav:PlayerPos()
    local best, bd
    for _, pt in ipairs(goal.points or {}) do
        if pt.map and pt.wx and p and pt.cont == p.cont then
            local d = (pt.wx - p.wx) ^ 2 + (pt.wy - p.wy) ^ 2
            if not bd or d < bd then best, bd = pt, d end
        end
    end
    if best then self:AddFront(best.map, best.x, best.y, goal.text or goal.title, goal.level, "shared") end
end

function P:Done(id)
    edit(function(stops)
        for i, s in ipairs(stops) do if s.id == id then table.remove(stops, i) return end end
    end)
end

-- Share your current trip plan as the party route.
function P:Share()
    if not channel() then ns:Print("you're not in a group") return end
    local stops = {}
    for _, s in ipairs(ns.nav.plan or {}) do
        local pt = s.point
        if pt and pt.map and pt.x and #stops < MAX_STOPS and not s.goal.key:find("^party:") then
            stops[#stops + 1] = { id = newId(), map = pt.map, x = pt.x, y = pt.y,
                label = s.goal.text or s.goal.title, level = s.goal.level, kind = "shared" }
        end
    end
    if #stops == 0 then ns:Print("nothing in your trip plan to share yet") return end
    state.joined = true
    edit(function(st)
        wipe(st)
        for _, s in ipairs(stops) do st[#st + 1] = s end
    end)
    ns:Print("shared your route with the party (" .. #stops .. " stops). Anyone can edit it.")
end

function P:Join()
    if not offer then ns:Print("no shared route to join yet") return end
    state.joined = true
    state.stops, state.clock, state.editor = offer.stops, offer.clock, offer.editor
    offer = nil
    if self.prompt then self.prompt:Hide() end
    changed()
    ns:Print("joined the shared route. Your edits go to everyone in it.")
end

function P:Leave(quiet)
    state.joined = false
    wipe(state.stops)
    changed()
    if not quiet then ns:Print("left the shared route; back to your own plan") end
end

-------------------------------------------------------------------------------
-- Navigation: shared stops are goals, in the shared order, before your own.
-------------------------------------------------------------------------------

ns:Register("navGoal", "party", {
    collect = function()
        if not state.joined then return nil end
        local out, prev = {}, nil
        for i, s in ipairs(state.stops) do
            local key = "party:" .. s.id
            out[#out + 1] = {
                key = key, weight = 0.5, level = s.level,
                points = { { map = s.map, x = s.x, y = s.y } },
                title = s.label, text = "Party: " .. (s.label or "stop " .. i),
                details = { "Shared route stop " .. i .. " of " .. #state.stops .. ".",
                            "Anyone in the party can move it, add stops, or reach it to clear it." },
                deps = prev and { prev } or nil,
            }
            prev = key
        end
        return out
    end,
})

-------------------------------------------------------------------------------
-- Join prompt
-------------------------------------------------------------------------------

function P:ShowPrompt(sender, n)
    if not self.prompt then
        local f = CreateFrame("Frame", "FlowPartyPrompt", UIParent)
        f:SetSize(320, 74)
        f:SetPoint("TOP", 0, -200)
        f:SetFrameStrata("DIALOG")
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()
        f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOP", 0, -10)
        f.text:SetWidth(300)
        local join = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        join:SetSize(110, 22)
        join:SetPoint("BOTTOMLEFT", 40, 10)
        join:SetText("Join")
        join:SetScript("OnClick", function() P:Join() end)
        local no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        no:SetSize(110, 22)
        no:SetPoint("BOTTOMRIGHT", -40, 10)
        no:SetText("Not now")
        no:SetScript("OnClick", function() f:Hide() end)
        self.prompt = f
    end
    self.prompt.text:SetText(string.format("%s shared a route (%d stops).\nJoin it? Anyone in it can edit it.", sender, n))
    self.prompt:Show()
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------

ns:OnLoad(function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
    end
end)

ns:On("CHAT_MSG_ADDON", function(prefix, msg, _, sender)
    if prefix ~= PREFIX or not msg or not sender then return end
    local name = Ambiguate and Ambiguate(sender, "none") or sender
    if name == me() then return end
    received(name, msg)
end)

local lastRoster = 0
ns:On("GROUP_ROSTER_UPDATE", function()
    if not channel() then
        if state.joined then P:Leave(true); ns:Print("left the group, so the shared route ended") end
        return
    end
    -- New members: joined players re-share (throttled); a newcomer asks.
    if GetTime() - lastRoster < 5 then return end
    lastRoster = GetTime()
    if state.joined then P:Broadcast() else send("Q|0") end
end)

ns.commands.party = function(arg)
    arg = (arg or ""):lower()
    if arg == "share" then P:Share()
    elseif arg == "join" then P:Join()
    elseif arg == "leave" then P:Leave()
    else
        if state.joined then
            ns:Print(string.format("on a shared route: %d stops, last edit by %s.", #state.stops, state.editor))
        elseif offer then
            ns:Print(offer.editor .. " shared a route: /flow party join")
        else
            ns:Print("no shared route. /flow party share sends yours to the group.")
        end
        print("  /flow party share|join|leave")
    end
end

ns:Register("help", "party", { order = 45, title = "Party routes", lines = {
    "/flow party share - share your route; party members get a Join prompt",
    "Anyone on it can edit: click checkpoints/advice rows, set waypoints, reach stops. /flow party leave",
} })
