-- Party quest progress: Flow players in a group send each other how far they
-- are on every quest in their log (each objective's count, e.g. 3/10, and
-- whether it's ready to hand in). Whose quests your route covers:
--   Mine      your own quests only (the default)
--   <name>'s  just that party member's: what they still need (kill credit
--             is shared in a party), where they hand in, and your own stops
--             only where they need the same thing
--   Combined  yours and every Flow party member's, planned as one optimal
--             route (each spot once, saying who it's for)
-- Their stops say whose they are ("Bob: ..."), and "(done for you)" when
-- you've already finished that part yourself. When someone's progress first
-- comes in, Flow asks once: Combined, Just <name>'s, or Not now. Change it
-- any time: the line under the arrow, the route menu (right-click the
-- arrow), or /flow party quests mine|combined|<name>. Leaving the group
-- goes back to Mine.
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
local scope = "mine"  -- "mine" | "theirs" | "combined"
local focus           -- the party member for "theirs"

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
function H:Scope() return scope, focus end
-- Anyone's quests besides yours on the route? (name for "theirs", "your party" for combined)
function H:Helping()
    if scope == "theirs" then return focus end
    if scope == "combined" then return "your party" end
end

local function changed()
    if ns.nav then ns.nav:Collect(); ns.nav.planDirty = true end
    if H.RefreshToggle then H:RefreshToggle() end
end

-- What the route covers: "mine", "theirs" (with a name) or "combined".
function H:SetScope(s, name, why)
    if s == "theirs" and not progress[name] then
        ns:Print("no quest progress from " .. tostring(name) .. " yet (they need Flow too)")
        return
    end
    if s == "combined" and not next(progress) then
        ns:Print("nobody in your group has shared quest progress yet (they need Flow too)")
        return
    end
    local was = scope
    scope, focus = s, (s == "theirs") and name or nil
    if self.prompt then self.prompt:Hide() end
    changed()
    if s == "theirs" then
        ns:Print(string.format("route: just %s's quests (%d to do). Change it under the arrow.", name, H.ToDo(progress[name])))
    elseif s == "combined" then
        ns:Print("route: yours and your party's quests, planned together. Change it under the arrow.")
    elseif was ~= "mine" then
        ns:Print("route: your own quests" .. (why and (" (" .. why .. ")") or ""))
    end
end
function H:Help(name) self:SetScope("theirs", name) end
function H:Stop(why) if scope ~= "mine" then self:SetScope("mine", nil, why) end end

-- Ask once per person per group, when they have something left to do (not
-- when your route already covers other people's quests).
function H:MaybeAsk(name)
    if asked[name] or scope ~= "mine" or ns.party.IsMe(name) then return end
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
    if scope ~= "mine" then changed() else H:MaybeAsk(sender); H:RefreshToggle() end
    -- Quests you have and they don't: shared one at a time (Quests/QuestShare.lua).
    if ns.questShare then pcall(ns.questShare.ShareMissing, ns.questShare) end
end
ns.party.handlers.R = function() if GetTime() - lastSentAt > 2 then H.SendMine(true) end end

-------------------------------------------------------------------------------
-- Route: whose quests it covers
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

-- A party member's stop that you've already done yourself: that objective
-- (or the whole quest) is finished in your log, or you handed the quest in
-- before. Their stop then says "(done for you)".
function H.DoneForYou(key, mineE, doneBefore)
    local rest = key:match("^help:%d+:(.+)$")
    if not rest then return false end
    if mineE then
        if mineE.complete then return true end
        local o = rest ~= "done" and mineE.objectives[tonumber(rest)]
        return o and o.finished or false
    end
    return doneBefore and true or false
end

-- Whose progress the route covers now: { [name] = progress } or nil.
local function covered()
    if scope == "theirs" then return focus and progress[focus] and { [focus] = progress[focus] } or nil end
    if scope == "combined" and next(progress) then return progress end
end

ns:Register("navGoal", "partyhelp", {
    collect = function()
        local who = covered()
        local db = who and ns.quests.QuestieDB and ns.quests.QuestieDB()
        if not (db and ns.quests.QuestGoals) then return nil end
        local mine = H.Mine()
        local names, byKey, out = {}, {}, {}
        for name in pairs(who) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local list = {}
            for id, e in pairs(who[name]) do
                ns.quests.QuestGoals(db, { id = id, complete = e.complete, objectives = e.objectives }, list,
                    { prefix = "help:", who = name, skip = function(key) return H.Skip(key, mine) end })
            end
            for _, g in ipairs(list) do
                local had = byKey[g.key]
                if had then
                    had.forNames[#had.forNames + 1] = name   -- the same spot for two of them: one stop
                else
                    g.forNames = { name }
                    byKey[g.key] = g
                    out[#out + 1] = g
                end
            end
        end
        for _, g in ipairs(out) do
            local id = tonumber(g.key:match("^help:(%d+):"))
            local whoText = table.concat(g.forNames, ", ")
            g.helping = whoText
            -- QuestGoals wrote "<first name>: "; with more names, all of them.
            if #g.forNames > 1 then g.text = whoText .. g.text:sub(#g.forNames[1] + 1) end
            if H.DoneForYou(g.key, mine[id], ns.quests:IsCompleted(id)) then
                g.doneForYou = true
                g.text = g.text .. " |cff40ff40(done for you)|r"
                g.details = g.details or {}
                table.insert(g.details, 1, "You've done this part yourself: it's for " .. whoText .. ".")
            end
        end
        return out
    end,
})

-- "Just <name>'s": their stops, your own where they need the same objective
-- or you both hand in the same quest, and party-route stops. Nothing else.
function H.Keep(list, their)
    local out = {}
    for _, g in ipairs(list) do
        local k = g.key
        local keep = k:find("^help:") ~= nil or k:find("^party:") ~= nil
        if not keep then
            local id, rest = k:match("^(%d+):(.+)$")
            local e = id and their[tonumber(id)]
            if e then
                if rest == "done" then keep = true
                else
                    local o = not e.complete and e.objectives[tonumber(rest)]
                    keep = (o and not o.finished) and true or false
                end
            end
        end
        if keep then out[#out + 1] = g end
    end
    return out
end
-- (Nav.lua, after collecting every provider's goals)
function H:FilterGoals(list)
    if scope ~= "theirs" or not (focus and progress[focus]) then return list end
    return H.Keep(list, progress[focus])
end

-------------------------------------------------------------------------------
-- UI: the question, the line under the arrow, the route menu
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
        f:SetSize(380, 84)
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
        f.text:SetWidth(360)
        f.both = button(f, "Combined", 110)
        f.both:SetPoint("BOTTOMLEFT", 14, 10)
        f.both:SetScript("OnClick", function() H:SetScope("combined") end)
        f.theirs = button(f, "Just theirs", 120)
        f.theirs:SetPoint("BOTTOM", 0, 10)
        f.theirs:SetScript("OnClick", function() H:SetScope("theirs", f.name) end)
        local no = button(f, "Not now", 110)
        no:SetPoint("BOTTOMRIGHT", -14, 10)
        no:SetScript("OnClick", function() f:Hide() end)
        self.prompt = f
    end
    local f = self.prompt
    f.name = name
    f.theirs:SetText("Just " .. name .. "'s")
    f.text:SetText(string.format("%s shared their quest progress: %d quest(s) to do.\nPlan your route for both of you, or just %s's quests?", name, todo, name))
    f:Show()
end

-- The choices, for the route menu and the line under the arrow.
function H:MenuItems()
    if not next(progress) then return {} end
    local items = {
        { sep = true },
        { title = true, text = "Whose quests" },
        { text = "Mine", radio = true, checked = scope == "mine", func = function() H:SetScope("mine") end },
        { text = "Combined (everyone's, one route)", radio = true, checked = scope == "combined",
          func = function() H:SetScope("combined") end },
    }
    local names = {}
    for name in pairs(progress) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        items[#items + 1] = { text = string.format("Just %s's (%d to do)", name, H.ToDo(progress[name])), radio = true,
            checked = scope == "theirs" and focus == name, func = function() H:SetScope("theirs", name) end }
    end
    return items
end

function H.ScopeText()
    if scope == "theirs" then return focus .. "'s" end
    if scope == "combined" then return "Combined" end
    return "Mine"
end

function H:RefreshToggle()
    local arrow = _G.FlowNavArrow
    if not arrow then return end
    if not self.toggle then
        local t = CreateFrame("Button", nil, arrow)
        t:SetSize(180, 16)
        t:SetPoint("TOP", arrow, "BOTTOM", 0, -50)
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t.text:SetAllPoints()
        t:SetScript("OnClick", function()
            local items = { { title = true, text = "Whose quests" } }
            for i, it in ipairs(H:MenuItems()) do if i > 2 then items[#items + 1] = it end end
            ns.menu:Open(items)
        end)
        self.toggle = t
    end
    if not next(progress) then self.toggle:Hide() return end
    local c = ns.theme.user
    self.toggle.text:SetText(string.format("Quests: |cff%s%s|r  |cff888888(click: change)|r",
        scope == "mine" and "ffffff" or c.hex, H.ScopeText()))
    self.toggle:Show()
end

function H:Status()
    local names = {}
    for name, prog in pairs(progress) do names[#names + 1] = string.format("%s (%d to do)", name, H.ToDo(prog)) end
    print("  quest progress from: " .. (#names > 0 and table.concat(names, ", ") or "nobody yet (they need Flow)")
        .. "; route covers: " .. H.ScopeText())
end

-- /flow party quests mine|combined|<name>  (and the older help <name>|off)
function H:Command(arg)
    arg = (arg or ""):lower()
    if arg == "" then self:Status() return end
    if arg == "off" or arg == "stop" or arg == "mine" then self:SetScope("mine") return end
    if arg == "combined" or arg == "both" or arg == "all" then self:SetScope("combined") return end
    for name in pairs(progress) do
        if name:lower() == arg or name:lower():match("^([^%-]+)") == arg then self:SetScope("theirs", name) return end
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
        H:Stop("you left the group")
        wipe(progress); wipe(buffers); wipe(asked)
        inGroup = false
        H:RefreshToggle()
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
            if scope == "theirs" and focus == name then H:Stop(name .. " left the group") end
        end
    end
    if scope == "combined" and not next(progress) then H:Stop("nobody else in the group shares quests now") end
    H:RefreshToggle()
    if GetTime() - lastSentAt > 5 then H.SendMine(true) end   -- (roster updates come in bursts)
end

ns:On("GROUP_ROSTER_UPDATE", function() C_Timer.After(1, onRoster) end)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, onRoster) end)
ns:On("QUEST_LOG_UPDATE", soon)
ns:On("QUEST_ACCEPTED", soon)
ns:On("QUEST_TURNED_IN", soon)
