-------------------------------------------------------------------------------
-- Flow - Nav/Focus.lua
-- A custom route is the quest lines you picked, and nothing else (0.35.358).
--
-- "Once the user clicks an objective and says go here next, it would be cool
-- if it would pick the quest line that I am now watching and show me how to
-- complete that entire quest line ... when that thing is picked, that's all
-- you see. If you open up the Flow Router, it's just the route to complete
-- that quest line, not the 100 things they still need to do. [From Flow
-- Improvements] if the user clicks that button it should make that the
-- route; clicks it on another one, that also gets added: two quest lines,
-- optimal path between them. [And] remove this step, and then everything
-- after it in that quest line goes away; clear the whole quest line and
-- everything goes."
--
-- A line is what a pick stands for:
--   a quest step   its quest, the quests that must be done before it that
--                  you haven't done, and the quests the quest data chains
--                  after it. When it's part of a class quest that teaches a
--                  spell (Curing the Sick, for Cure Poison), the line runs to
--                  the quest that teaches it and is named after the spell.
--   anything else  that one step (a trainer, a profession step).
-- While you have lines, the route is only their steps, ordered as always
-- (shortest, the picked step first). The next quest of a line is added as a
-- step to pick up as soon as it can be, even where Flow wouldn't have offered
-- it. A line leaves by itself when its quests are done.
--
-- Picking: "Go here next" on any step (and its ^ in the Flow Router), or the
-- link button of a line in Flow Improvements. Each pick adds a line.
-- Removing: right-click a step: "Remove this step and what follows it"
-- (the line now ends before that quest) or "Remove its whole quest line".
-- Clearing: the bar under the Flow Tracker ("Custom route: ... x"), "Clear
-- your custom route" at the top of the Flow menu's Order, or picking
-- Shortest or Most XP.
-------------------------------------------------------------------------------

local _, ns = ...
local F = {}
ns.focus = F

F.MAX_BACK, F.MAX_AFTER = 12, 20

-------------------------------------------------------------------------------
-- Pure parts
-------------------------------------------------------------------------------

-- The quest a step belongs to ("875:1", "875:done", "pickup:875" -> 875).
function F.QuestOf(key)
    if type(key) ~= "string" then return nil end
    return tonumber(key:match("^pickup:(%d+)$") or key:match("^(%d+):"))
end

-- The quests to do before `id` that aren't done, the earliest first.
--   get(id) -> { id, name, raw = { preQuestGroup, preQuestSingle, nextQuestInChain } } or nil
function F.Before(id, get, isDone, out, seen, depth)
    out, seen, depth = out or {}, seen or {}, depth or 0
    local q = get(id)
    if not q or depth >= F.MAX_BACK then return out end
    local raw = q.raw or {}
    local pres = {}
    for _, p in ipairs(type(raw.preQuestGroup) == "table" and raw.preQuestGroup or {}) do
        if not isDone(p) then pres[#pres + 1] = p end                 -- all of these
    end
    local single = type(raw.preQuestSingle) == "table" and raw.preQuestSingle or {}
    local any = false
    for _, p in ipairs(single) do if isDone(p) then any = true end end
    if not any and #single > 0 then pres[#pres + 1] = single[1] end   -- and one of these
    for _, p in ipairs(pres) do
        if not seen[p] and get(p) then
            seen[p] = true
            F.Before(p, get, isDone, out, seen, depth + 1)
            out[#out + 1] = p
        end
    end
    return out
end

-- The quests the quest data chains after `id`, in order.
function F.After(id, get)
    local out, seen, cur = {}, { [id] = true }, get(id)
    for _ = 1, F.MAX_AFTER do
        local nextId = cur and cur.raw and tonumber(cur.raw.nextQuestInChain)
        if not nextId or nextId == 0 or seen[nextId] then break end
        cur = get(nextId)
        if not cur then break end
        seen[nextId] = true
        out[#out + 1] = nextId
    end
    return out
end

-- A pick's line: the quests in the order you do them, and its name.
--   teach: { { spell, id } } the quests that teach your class a spell you lack
function F.Line(id, get, isDone, teach)
    local ids, seen = {}, {}
    local function add(x) if not seen[x] then seen[x] = true; ids[#ids + 1] = x end end
    for _, p in ipairs(F.Before(id, get, isDone)) do add(p) end
    add(id)
    for _, n in ipairs(F.After(id, get)) do add(n) end
    local title
    -- Part of a class quest's chain: the line runs to the quest that teaches the spell.
    for _, t in ipairs(teach or {}) do
        local chain = F.Before(t.id, get, isDone)
        chain[#chain + 1] = t.id
        local mine = false
        for _, x in ipairs(chain) do if seen[x] then mine = true end end
        if mine then
            for _, x in ipairs(chain) do add(x) end
            title = title or t.spell
        end
    end
    if not title then
        local last = get(ids[#ids]) or get(id)
        title = last and last.name or ("quest " .. tostring(id))
    end
    return ids, title
end

-- A line cut short: the quests before `stop` (nil: all of them).
function F.Cut(ids, stop)
    if not stop then return ids end
    local out = {}
    for _, x in ipairs(ids) do
        if x == stop then break end
        out[#out + 1] = x
    end
    return out
end

-- Does a step belong to your lines? quests: { [questID] = true }; keys: { [step key] = true }
function F.Keeps(goal, quests, keys)
    if type(goal) ~= "table" or type(goal.key) ~= "string" then return false end
    if keys and keys[goal.key] then return true end
    local id = F.QuestOf(goal.key)
    return id ~= nil and quests ~= nil and quests[id] == true
end
function F.FilterBy(list, quests, keys)
    local out = {}
    for _, g in ipairs(list or {}) do
        if F.Keeps(g, quests, keys) then out[#out + 1] = g end
    end
    return out
end

-- The bar's words: "Custom route: Cure Poison + Aquatic Form".
function F.Text(titles)
    if #titles == 0 then return "Custom route" end
    local shown = {}
    for i = 1, math.min(3, #titles) do shown[i] = tostring(titles[i]) end
    return "Custom route: " .. table.concat(shown, " + ") .. (#titles > 3 and string.format(" + %d more", #titles - 3) or "")
end

-------------------------------------------------------------------------------
-- Your lines
-------------------------------------------------------------------------------
local function lines()
    ns.db.nav.focus = ns.db.nav.focus or {}
    return ns.db.nav.focus
end
local function source()
    local Q = ns.quests
    local src = Q and Q.Source and Q:Source()
    if not (src and src.get) then return nil end
    return src.get, function(id) return Q.IsCompleted and Q:IsCompleted(id) and true or false end
end
local function teaching()
    local out = {}
    local _, token = UnitClass("player")
    local known = ns.rotation and ns.rotation.KnownSpells and ns.rotation:KnownSpells() or {}
    for _, s in ipairs(ns:Get("classSpells", token or "") or {}) do
        if type(s.quest) == "table" and not known[s.spell] then
            for _, id in ipairs(s.quest) do out[#out + 1] = { spell = s.spell, id = id } end
        end
    end
    return out
end

-- One line's quests now ({ ids }, title), or nil for a single step.
function F.IdsOf(line)
    if not line.quest then return nil, line.title end
    local get, isDone = source()
    if not get then return { line.quest }, line.title end
    local ids, title = F.Line(line.quest, get, isDone, teaching())
    return F.Cut(ids, line.stop), title
end

function F.Custom() return ns.xpValue and ns.xpValue.IsCustom and ns.xpValue:IsCustom() or false end
function F.Active() return #lines() > 0 and F.Custom() end

-- What the route keeps: the quests and the steps of every line; each line's titles.
function F.Sets()
    local quests, keys, titles = {}, {}, {}
    for _, line in ipairs(lines()) do
        local ids, title = F.IdsOf(line)
        line.title = title or line.title
        titles[#titles + 1] = line.title or "a step"
        if ids then for _, id in ipairs(ids) do quests[id] = true end
        elseif line.key then keys[line.key] = true end
    end
    return quests, keys, titles
end

local function changed(why)
    if ns.theme and ns.theme.UpdateRoute then ns.theme:UpdateRoute() end
    if ns.nav then
        ns.nav.planDirty = true
        if ns.nav.RequestCollect then ns.nav.RequestCollect(why) end
    end
    F.UpdateBar()
end

-- A step picked: its line joins your custom route. -> the line's name, or nil when it was there already
function F.AddKey(key, text)
    if type(key) ~= "string" then return nil end
    local qid = F.QuestOf(key)
    local quests, keys = F.Sets()
    if (qid and quests[qid]) or keys[key] then return nil end
    local line = qid and { quest = qid } or { key = key, title = text or key }
    table.insert(lines(), line)
    local _, title = F.IdsOf(line)
    line.title = title or line.title
    ns.db.nav.sorter = "custom"
    changed("custom route: a line added")
    return line.title
end

-- The line a step is in (its index), or nil.
function F.LineOf(key)
    local qid = F.QuestOf(key)
    for i, line in ipairs(lines()) do
        if line.key and line.key == key then return i end
        if qid and line.quest then
            for _, id in ipairs(F.IdsOf(line) or {}) do if id == qid then return i end end
        end
    end
end
-- "Remove this step and what follows it": the line ends before that quest
-- (a single step, or the line's first quest: the line goes).
function F.RemoveFrom(key)
    local i = F.LineOf(key)
    if not i then return false end
    local line = lines()[i]
    local qid = F.QuestOf(key)
    local ids = F.IdsOf(line)
    if not (line.quest and qid and ids) or ids[1] == qid then
        table.remove(lines(), i)
    else
        line.stop = qid
    end
    changed("custom route: a step removed")
    return true
end
function F.RemoveLine(key)
    local i = F.LineOf(key)
    if not i then return false end
    table.remove(lines(), i)
    changed("custom route: a line removed")
    return true
end
function F.Clear()
    if #lines() == 0 then return false end
    wipe(lines())
    F.UpdateBar()
    return true
end

-- The menu entries for a step of your custom route (right-click it).
function F.MenuItems(goal)
    local out = {}
    if not (goal and F.Active() and F.LineOf(goal.key)) then return out end
    local line = lines()[F.LineOf(goal.key)]
    out[#out + 1] = { text = "Remove this step and what follows it (custom route)", func = function() F.RemoveFrom(goal.key) end }
    if line.quest then
        out[#out + 1] = { text = string.format("Remove its whole quest line: %s", tostring(line.title or "this line")), func = function() F.RemoveLine(goal.key) end }
    end
    return out
end

-- The route's steps, cut down to your lines (Nav.lua calls this as it
-- gathers them). Lines whose quests are all done leave; with none left the
-- route goes back to what it was planned by before.
function F.Filter(list)
    local mine = lines()
    if #mine == 0 then return list end
    if not F.Custom() then          -- you chose Shortest or Most XP: the lines go
        wipe(mine)
        F.UpdateBar()
        return list
    end
    local get, isDone = source()
    local inLog = ns.quests and ns.quests.LogIds and ns.quests:LogIds() or {}
    for i = #mine, 1, -1 do
        local ids = F.IdsOf(mine[i])
        if ids and get then
            local left = false
            for _, id in ipairs(ids) do if inLog[id] or not isDone(id) then left = true end end
            if not left then
                ns:Print("Custom route: " .. tostring(mine[i].title or "a quest line") .. " is done.")
                table.remove(mine, i)
            end
        end
    end
    if #mine == 0 then
        -- (After this gathering: changing the order gathers again.)
        C_Timer.After(0, function()
            if #lines() == 0 and F.Custom() and ns.nav and not (ns.nav.selection and ns.nav.selection.first) then
                ns.xpValue:SetMode(ns.xpValue:Base())
                ns:Print("Custom route finished: back to " .. (ns.xpValue:Base() == "xp" and "Most XP" or "Shortest path") .. ".")
            end
            F.UpdateBar()
        end)
        return list
    end
    local quests, keys = F.Sets()
    local out = F.FilterBy(list, quests, keys)
    -- The next quest of a line, where the route wasn't offering it.
    local Q = ns.quests
    if get and Q and Q.ChainNow and Q.AddClassQuests and Q.SpawnPoints then
        local has = {}
        for _, g in ipairs(out) do has[g.key] = true end
        for _, line in ipairs(mine) do
            local ids = F.IdsOf(line)
            for _, id in ipairs(ids or {}) do
                if not isDone(id) and not inLog[id] then
                    local okC, state, q = pcall(Q.ChainNow, Q, id)
                    if okC and state == "accept" and q and q.id and quests[q.id] and not has["pickup:" .. q.id] then
                        pcall(Q.AddClassQuests, out, { { state = "accept", quest = q, spell = line.title or "your custom route" } }, Q.SpawnPoints)
                        has["pickup:" .. q.id] = true
                    end
                    break   -- (only the first quest of the line that's still to pick up)
                end
            end
        end
    end
    F.kept, F.of = #out, #list
    return out
end

-------------------------------------------------------------------------------
-- The bar under the Flow Tracker: what you're on, and one click to leave it
-------------------------------------------------------------------------------
function F.UpdateBar()
    local tracker = _G.FlowTracker
    if not tracker then return end
    local bar = F.bar
    if not bar then
        bar = CreateFrame("Button", "FlowCustomRouteBar", tracker)
        bar:SetHeight(16)
        bar:SetPoint("TOPLEFT", tracker, "BOTTOMLEFT", 0, -2)
        bar:SetPoint("TOPRIGHT", tracker, "BOTTOMRIGHT", 0, -2)
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        local c = ns.theme.BAR
        bar.bg:SetColorTexture(c[1], c[2], c[3], c[4])
        bar.hl = bar:CreateTexture(nil, "HIGHLIGHT")
        bar.hl:SetAllPoints(); bar.hl:SetColorTexture(1, 1, 1, 0.1)
        bar.x = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bar.x:SetPoint("RIGHT", -5, 0)
        bar.x:SetText("|cffff8080x clear|r")
        bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bar.text:SetPoint("LEFT", 6, 0); bar.text:SetPoint("RIGHT", bar.x, "LEFT", -6, 0)
        bar.text:SetJustifyH("LEFT"); bar.text:SetWordWrap(false)
        bar.text:SetTextColor(1, 0.6, 0.2)
        bar:SetScript("OnClick", function() F.ClearClick() end)
        bar:SetScript("OnEnter", function(self)
            ns.Tip(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:AddLine("Custom route", 1, 0.6, 0.2)
            local _, _, titles = F.Sets()
            for _, tl in ipairs(titles) do GameTooltip:AddLine("- " .. tostring(tl), 1, 1, 1, true) end
            GameTooltip:AddLine("Your route is only these lines' steps. \"Go here next\" on a step, or a line's link in Flow Improvements, adds another.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Click: clear it, back to your usual route. Right-click a step to remove it or its line.", 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
        F.bar = bar
    end
    local on = F.Active()
    if on then
        local _, _, titles = F.Sets()
        bar.text:SetText(F.Text(titles))
    end
    bar:SetShown(on)
end

-- The bar (or the menu's line) was clicked: the custom route goes.
function F.ClearClick()
    F.Clear()
    if ns.nav and ns.nav.ClearSelection then ns.nav:ClearSelection() end
    if ns.xpValue and ns.xpValue:IsCustom() then ns.xpValue:SetMode(ns.xpValue:Base()) end
    F.UpdateBar()
end

-- "Go here next" (N:Select) adds the step's line; clearing your pick clears the lines.
ns:OnLoad(function(saved)
    saved.nav = saved.nav or {}
    saved.nav.focus = saved.nav.focus or {}
    local N = ns.nav
    if N and N.Select and not F.hooked then
        F.hooked = true
        local select = N.Select
        function N:Select(key)
            local following = ns.party and ns.party.Following and ns.party:Following()
            select(self, key)
            if following then return end
            if key then
                local text
                for _, g in ipairs(self:Goals() or {}) do if g.key == key then text = g.text or g.title end end
                local title = F.AddKey(key, text)
                if title then ns:Print("Custom route: " .. tostring(title) .. ". Only its steps are on your route now; click the bar under the Flow Tracker to clear it.") end
            else
                F.Clear()
            end
        end
    end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2, function() pcall(F.UpdateBar) end) end
end)
ns:PerCharacter("nav.focus")

function F.DumpLines()
    local mine = lines()
    local out = { string.format("custom route lines: %d%s", #mine, F.Active() and "" or (#mine > 0 and " (not in force: the order isn't Custom)" or "")) }
    for i, line in ipairs(mine) do
        local ids = F.IdsOf(line)
        out[#out + 1] = string.format("  %d. %s: %s%s", i, tostring(line.title or "?"),
            ids and ("quests " .. table.concat(ids, ", ")) or ("step " .. tostring(line.key)), line.stop and (" (ends before " .. line.stop .. ")") or "")
    end
    if F.of then out[#out + 1] = string.format("  the last gathering kept %d of %d step(s)", F.kept or 0, F.of) end
    return out
end
ns.commands.focus = function(arg)
    if (arg or ""):lower() == "clear" then F.ClearClick() ns:Print("custom route cleared") return end
    for i, l in ipairs(F.DumpLines()) do if i == 1 then ns:Print(l) else print(l) end end
    print("  /flow focus clear")
end
