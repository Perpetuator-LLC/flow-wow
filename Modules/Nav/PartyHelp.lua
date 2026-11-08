-- Party quest progress: Flow players in a group send each other how far they
-- are on every quest in their log (each objective's count, e.g. 3/10, and
-- whether it's ready to hand in). When a party member's progress comes in,
-- Flow asks once: help them? Yes puts their priority list first on your
-- route: the objectives they still need (kill credit is shared in a party)
-- and where they hand in, before your own stops. Their stops say whose they
-- are ("Bob: ..."). One question per person per group; /flow party help
-- <name> or /flow party help off any time. Leaving the group stops it.
--
-- Message (on Party.lua's addon channel):
--   G|part|parts|body   body = entries joined by ",":
--                       "83=c" ready to hand in, "86=2/4.0/1" objective counts
--   R|0                 "send me your progress" (just joined)

local _, ns = ...
local H = {}
ns.partyHelp = H

local MAX_PART = 220
local progress = {}   -- name -> { [questId] = { complete, objectives = { { have, need, finished } } } }
local buffers = {}    -- name -> progress being received
local asked = {}      -- name -> true: already asked this group
local helping         -- the name you're helping, or nil

-------------------------------------------------------------------------------
-- Encoding
-------------------------------------------------------------------------------

-- prog = { [id] = { complete, objectives = { { have, need } } } } -> parts.
function H.Encode(prog)
    local ids = {}
    for id in pairs(prog) do ids[#ids + 1] = id end
    table.sort(ids)
    local entries = {}
    for _, id in ipairs(ids) do
        local e = prog[id]
        local body
        if e.complete then body = "c"
        else
            local objs = {}
            for _, o in ipairs(e.objectives or {}) do
                objs[#objs + 1] = string.format("%d/%d", o.have or 0, o.need or 1)
            end
            body = table.concat(objs, ".")
        end
        entries[#entries + 1] = id .. "=" .. body
    end
    local parts, cur = {}, ""
    for _, en in ipairs(entries) do
        if cur ~= "" and #cur + 1 + #en > MAX_PART then parts[#parts + 1] = cur; cur = "" end
        cur = cur == "" and en or (cur .. "," .. en)
    end
    parts[#parts + 1] = cur
    return parts
end

-- One part's body -> entries added to `into`.
function H.Decode(body, into)
    into = into or {}
    for id, rest in (body or ""):gmatch("(%d+)=([^,]*)") do
        local e = { complete = rest == "c", objectives = {} }
        if not e.complete then
            for have, need in rest:gmatch("(%d+)/(%d+)") do
                have, need = tonumber(have), tonumber(need)
                e.objectives[#e.objectives + 1] = { have = have, need = need, finished = have >= need }
            end
        end
        into[tonumber(id)] = e
    end
    return into
end

-------------------------------------------------------------------------------
-- Your progress, sent to the party
-------------------------------------------------------------------------------

function H.Mine()
    local out = {}
    for _, q in ipairs(ns.quests.LogEntries and ns.quests.LogEntries() or {}) do
        local e = { complete = q.complete and true or false, objectives = {} }
        local counts = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q.id)
        for i, o in ipairs(q.objectives) do
            local c = counts and counts[i]
            local have, need = c and c.numFulfilled, c and c.numRequired
            if not need then
                have, need = (o.text or ""):match("(%d+)%s*/%s*(%d+)")
                have, need = tonumber(have), tonumber(need)
            end
            if not need or need < 1 then have, need = o.finished and 1 or 0, 1 end
            e.objectives[#e.objectives + 1] = { have = have or 0, need = need, finished = o.finished and true or false }
        end
        out[q.id] = e
    end
    return out
end

local lastSent, lastSentAt = nil, 0
function H.SendMine(force)
    if not (ns.party and ns.party:InGroup()) then return end
    local parts = H.Encode(H.Mine())
    local whole = table.concat(parts, ",")
    if not force and whole == lastSent and GetTime() - lastSentAt < 60 then return end
    lastSent, lastSentAt = whole, GetTime()
    for i, p in ipairs(parts) do ns.party.Send(string.format("G|%d|%d|%s", i, #parts, p)) end
end

-- Quest log changes come in bursts: send 2 s after the last one.
local pending = false
local function soon()
    if pending then return end
    pending = true
    C_Timer.After(2, function() pending = false; pcall(H.SendMine) end)
end

-------------------------------------------------------------------------------
-- Their progress
-------------------------------------------------------------------------------

-- Quests they still have something to do for (not ready to hand in).
function H.ToDo(prog)
    local n = 0
    for _, e in pairs(prog or {}) do
        if not e.complete then n = n + 1 end
    end
    return n
end

function H.Progress(name) return progress[name] end
function H.All() return progress end   -- name -> progress (QuestShare.lua reads who has what)
function H:Helping() return helping end

local function changed()
    if ns.nav then ns.nav:Collect(); ns.nav.planDirty = true end
    if H.RefreshToggle then H:RefreshToggle() end
end

function H:Help(name)
    if not progress[name] then ns:Print("no quest progress from " .. tostring(name) .. " yet (they need Flow too)") return end
    helping = name
    if self.prompt then self.prompt:Hide() end
    changed()
    ns:Print(string.format("helping %s: their quests come first on your route (%d to do). /flow party help off to stop.",
        name, H.ToDo(progress[name])))
end

function H:Stop(why)
    if not helping then return end
    local was = helping
    helping = nil
    changed()
    ns:Print("stopped helping " .. was .. (why and (": " .. why) or "") .. "; back to your own route")
end

-- Ask once per person per group, when they have something left to do.
function H:MaybeAsk(name)
    if asked[name] or helping == name or ns.party.IsMe(name) then return end
    local todo = H.ToDo(progress[name])
    if todo == 0 then return end
    asked[name] = true
    self:ShowPrompt(name, todo)
end

ns.party.handlers.G = function(sender, rest)
    local part, parts, body = rest:match("^(%d+)|(%d+)|(.*)$")
    part, parts = tonumber(part), tonumber(parts)
    if not part then return end
    if ns.party.IsMe(sender) then return end   -- (never your own progress)
    if part == 1 then buffers[sender] = {} end
    local buf = buffers[sender]
    if not buf then return end
    H.Decode(body, buf)
    if part < parts then return end
    buffers[sender] = nil
    progress[sender] = buf
    if helping == sender then changed() else H:MaybeAsk(sender) end
    -- Quests you have and they don't: shared one at a time (Quests/QuestShare.lua).
    if ns.questShare then pcall(ns.questShare.ShareMissing, ns.questShare) end
end
ns.party.handlers.R = function() if GetTime() - lastSentAt > 2 then H.SendMine(true) end end

-------------------------------------------------------------------------------
-- Route: their quests as goals, first in the plan
-------------------------------------------------------------------------------

-- Leave out what your own quests already cover: an objective you still need
-- yourself (your own stop is there) and the turn-in of a quest you have too.
function H.Skip(key, mine)
    local id, rest = key:match("^help:(%d+):(.+)$")
    local own = mine[tonumber(id)]
    if not own then return false end
    if rest == "done" then return true end
    local o = own.objectives[tonumber(rest)]
    return o ~= nil and not o.finished
end

ns:Register("navGoal", "partyhelp", {
    collect = function()
        local their = helping and progress[helping]
        local db = their and ns.quests.QuestieDB and ns.quests.QuestieDB()
        if not (db and ns.quests.QuestGoals) then return nil end
        local mine = H.Mine()
        local goals = {}
        for id, e in pairs(their) do
            local q = { id = id, complete = e.complete, objectives = e.objectives }
            ns.quests.QuestGoals(db, q, goals, { prefix = "help:", who = helping,
                skip = function(key) return H.Skip(key, mine) end })
        end
        return goals
    end,
})

-- Keys that go first (Nav.lua N:Options): their stops, and your own stops for
-- objectives they still need too.
function H.Tour(present, their)
    local tour = {}
    for key in pairs(present) do
        if key:find("^help:") then tour[key] = true
        else
            local id, i = key:match("^(%d+):(%d+)$")
            local e = id and their and their[tonumber(id)]
            local o = e and not e.complete and e.objectives[tonumber(i)]
            if o and not o.finished then tour[key] = true end
        end
    end
    return tour
end
function H:TourNow(present) return H.Tour(present, helping and progress[helping]) end

-------------------------------------------------------------------------------
-- UI: the question, and "Helping Bob" under the arrow
-------------------------------------------------------------------------------

local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    return b
end

function H:ShowPrompt(name, todo)
    if not self.prompt then
        local f = CreateFrame("Frame", "FlowHelpPrompt", UIParent)
        f:SetSize(360, 84)
        f:SetPoint("TOP", 0, -290)
        f:SetFrameStrata("DIALOG")
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()
        f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
        local top = f:CreateTexture(nil, "BORDER")
        top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
        local c = ns.theme.user
        top:SetColorTexture(c[1], c[2], c[3], 0.9)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOP", 0, -10)
        f.text:SetWidth(340)
        f.yes = button(f, "Help", 150)
        f.yes:SetPoint("BOTTOMLEFT", 20, 10)
        f.yes:SetScript("OnClick", function() H:Help(f.name) end)
        local no = button(f, "Not now", 150)
        no:SetPoint("BOTTOMRIGHT", -20, 10)
        no:SetScript("OnClick", function() f:Hide() end)
        self.prompt = f
    end
    local f = self.prompt
    f.name = name
    f.yes:SetText("Help " .. name)
    f.text:SetText(string.format("%s shared their quest progress: %d quest(s) to do.\nPut %s's priority list first on your route?", name, todo, name))
    f:Show()
end

function H:RefreshToggle()
    local arrow = _G.FlowNavArrow
    if not arrow then return end
    if not self.toggle then
        local t = CreateFrame("Button", nil, arrow)
        t:SetSize(160, 16)
        t:SetPoint("TOP", arrow, "BOTTOM", 0, -50)
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t.text:SetAllPoints()
        t:SetScript("OnClick", function() H:Stop() end)
        self.toggle = t
    end
    if not helping then self.toggle:Hide() return end
    self.toggle.text:SetText(string.format("|cff%sHelping %s|r  |cff888888(click: stop)|r", ns.theme.user.hex, helping))
    self.toggle:Show()
end

function H:Status()
    local names = {}
    for name, prog in pairs(progress) do names[#names + 1] = string.format("%s (%d to do)", name, H.ToDo(prog)) end
    print("  quest progress from: " .. (#names > 0 and table.concat(names, ", ") or "nobody yet (they need Flow)")
        .. (helping and ("; helping " .. helping) or ""))
end

function H:Command(arg)
    arg = arg or ""
    if arg == "off" or arg == "stop" then
        if helping then self:Stop() else ns:Print("you're not helping anyone") end
        return
    end
    if arg == "" then self:Status() return end
    for name in pairs(progress) do
        if name:lower() == arg:lower() then self:Help(name) return end
    end
    ns:Print("no quest progress from " .. arg .. " (are they in your group, with Flow?)")
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------

local inGroup = false
local function onRoster()
    local now = ns.party and ns.party:InGroup()
    if not now then
        if helping then H:Stop("you left the group") end
        wipe(progress); wipe(buffers); wipe(asked)
        inGroup = false
        return
    end
    if not inGroup then
        inGroup = true
        ns.party.Send("R|0")
        H.SendMine(true)
        return
    end
    -- Someone left: drop their progress; someone joined: they get ours.
    for name in pairs(progress) do
        if not ((UnitInParty and UnitInParty(name)) or (UnitInRaid and UnitInRaid(name))) then
            progress[name] = nil
            if helping == name then H:Stop(name .. " left the group") end
        end
    end
    if GetTime() - lastSentAt > 5 then H.SendMine(true) end   -- (roster updates come in bursts)
end

ns:On("GROUP_ROSTER_UPDATE", function() C_Timer.After(1, onRoster) end)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, onRoster) end)
ns:On("QUEST_LOG_UPDATE", soon)
ns:On("QUEST_ACCEPTED", soon)
ns:On("QUEST_TURNED_IN", soon)
