-------------------------------------------------------------------------------
-- Flow - Nav/Tracking.lua
-- The minimap shows what your next step needs, and only that (0.35.380).
--
-- "Right now it's telling me to go and find the banker. It should
-- automatically show the banker on the minimap. That way I'm not looking at
-- all these icons all the time: only the thing I'm currently focused on. In
-- the game's tracking menu, at the bottom, another checkbox: let Flow manage
-- this. If the user has checked a box, leave it alone; it's only where
-- everything's off that we turn on the one thing at a time. If the user turns
-- on Flight Masters, they just always stay on."
--
-- The game's minimap tracking (the magnifying glass by the minimap) has a
-- tick per kind of townsfolk: Banker, Auctioneer, Class Trainer, Flight
-- Master... While your next step is at one of those, Flow ticks that kind,
-- and unticks it when the step is done. The rule that keeps your own choices
-- yours (T.Plan):
--   * a kind that's already on is left alone, and stays on afterwards;
--   * Flow only ever unticks a kind it ticked itself.
-- Flow never touches the tracking that is a spell (Find Herbs, Find
-- Minerals), and changes nothing in a fight.
--
-- Which kind goes with which step is a registration:
--   ns:Register("trackFor", key, {
--       words = { "banker" },                 -- part of the game's name for the kind
--       match = function(goal) return goal.provider == "banker" end,
--   })
-- The game's own names are matched by those words, lower case, so a client
-- that words one differently only needs a word added. /flow tracking lists
-- the kinds this client has and what Flow matched.
--
-- "Let Flow show what your next step needs" is a tick at the bottom of the
-- game's tracking menu (added through the game's own Menu.ModifyMenu, the way
-- it's meant for add-ons) and in Flow Settings, Finding your way.
-------------------------------------------------------------------------------

local _, ns = ...
local T = {}
ns.tracking = T

T.MENU_TAG = "MENU_MINIMAP_TRACKING"
T.LABEL = "Let Flow show what your next step needs"

-------------------------------------------------------------------------------
-- Which kind a step needs
-------------------------------------------------------------------------------
local function keyOf(g) return type(g.key) == "string" and g.key or "" end
-- (A waypoint from "Nearest...": its words say what it is.)
local function says(g, word)
    return g.waypoint == true and type(g.text) == "string" and g.text:lower():find(word, 1, true) ~= nil
end

ns:Register("trackFor", "banker", { words = { "banker" },
    match = function(g) return g.provider == "banker" or keyOf(g) == "bank" or keyOf(g):find("^bank:") ~= nil or keyOf(g):find("^bankget:") ~= nil or says(g, "bank") end })
ns:Register("trackFor", "auctioneer", { words = { "auction" },
    match = function(g) return g.provider == "questbuy" or keyOf(g):find("^qbuy:") ~= nil or g.kind == "buy" and g.provider == "trader" or says(g, "auction") end })
ns:Register("trackFor", "classTrainer", { words = { "class trainer" },
    match = function(g) return keyOf(g) == "train:class" end })
ns:Register("trackFor", "professionTrainer", { words = { "profession" },
    match = function(g) return keyOf(g):find("^train:") ~= nil and keyOf(g) ~= "train:class" end })
ns:Register("trackFor", "flightMaster", { words = { "flight" },
    match = function(g) return g.provider == "flightpath" or keyOf(g):find("^flightpath:") ~= nil or says(g, "flight") end })
ns:Register("trackFor", "repair", { words = { "repair" },
    match = function(g) return g.provider == "repair" or keyOf(g) == "repair" or says(g, "repair") end })
ns:Register("trackFor", "innkeeper", { words = { "innkeeper" },
    match = function(g) return g.provider == "hearth" or keyOf(g):find("^hearth:") ~= nil or says(g, "innkeeper") end })
ns:Register("trackFor", "mailbox", { words = { "mailbox" },
    match = function(g) return keyOf(g):find("^mail") ~= nil or says(g, "mail") end })

local ruleList
local function rules()
    if not ruleList then
        ruleList = {}
        for key, def in ns:Each("trackFor") do ruleList[#ruleList + 1] = { key = key, def = def } end
        table.sort(ruleList, function(a, b) return a.key < b.key end)
    end
    return ruleList
end

-- Pure: the rule a step falls under ({ key, def }), or nil. list: { { key, def } }
function T.RuleFor(goal, list)
    if type(goal) ~= "table" then return nil end
    for _, r in ipairs(list or {}) do
        local ok, yes = pcall(r.def.match, goal)
        if ok and yes then return r end
    end
    return nil
end

-- Pure: the game's kinds whose name has one of the words: { [name] = true }.
--   types: { { name, active, spell } }
function T.Match(types, words)
    local out = {}
    for _, ty in ipairs(types or {}) do
        local name = type(ty.name) == "string" and ty.name:lower() or nil
        if name and not ty.spell then
            for _, w in ipairs(words or {}) do
                if name:find(w, 1, true) then out[ty.name] = true end
            end
        end
    end
    return out
end

-- Pure: what to tick and untick now.
--   types: { { name, active, spell } } as the game has them
--   want:  { [name] = true } the kinds the step needs (empty: none)
--   mine:  { [name] = true } the kinds Flow ticked and hasn't unticked
--   on:    is Flow managing at all
-- -> { names to tick }, { names to untick }, the new `mine`
function T.Plan(types, want, mine, on)
    local tick, untick, keep = {}, {}, {}
    want, mine = want or {}, mine or {}
    for _, ty in ipairs(types or {}) do
        local name = ty.name
        if name and not ty.spell then
            if on and want[name] then
                if not ty.active then
                    tick[#tick + 1] = name
                    keep[name] = true
                elseif mine[name] then
                    keep[name] = true          -- ours from before, still wanted
                end                            -- (on and not ours: yours, left alone)
            elseif mine[name] then
                if ty.active then untick[#untick + 1] = name end   -- (unticked by hand already: just forgotten)
            end
        end
    end
    return tick, untick, keep
end

-------------------------------------------------------------------------------
-- The game's tracking
-------------------------------------------------------------------------------
local CM = C_Minimap
function T.Has() return CM ~= nil and CM.GetNumTrackingTypes ~= nil and CM.GetTrackingInfo ~= nil and CM.SetTracking ~= nil end

-- The kinds as the game has them: { { index, name, active, spell } }.
function T.Types()
    local out = {}
    if not T.Has() then return out end
    local okN, n = pcall(CM.GetNumTrackingTypes)
    for i = 1, (okN and tonumber(n)) or 0 do
        -- (A table on newer clients; name, texture, active, category on older ones.)
        local ok, a, _, c, d = pcall(CM.GetTrackingInfo, i)
        if ok and a ~= nil then
            local name, active, category
            if type(a) == "table" then name, active, category = a.name, a.active, a.type else name, active, category = a, c, d end
            name = ns.api.Safe(name)
            if type(name) == "string" then
                out[#out + 1] = { index = i, name = name, active = ns.rotation.Yes(active, false), spell = category == "spell" }
            end
        end
    end
    return out
end

function T.On() return not (ns.db and ns.db.nav and ns.db.nav.trackManage == false) end
function T.Set(on)
    if not (ns.db and ns.db.nav) then return end
    ns.db.nav.trackManage = on and true or false
    T.Tick(true)
end

local function mine()
    ns.db.nav.trackMine = ns.db.nav.trackMine or {}
    return ns.db.nav.trackMine
end

-- The step the arrow is on now.
function T.Goal()
    local cur = ns.nav and ns.nav.current
    local g = cur and cur.goal
    if g and cur.waypoint and g.waypoint == nil then g.waypoint = true end
    return g
end

-- Looks at your next step and brings the game's ticks in line.
function T.Tick()
    if not (T.Has() and ns.db and ns.db.nav) or InCombatLockdown() then return end
    local types = T.Types()
    if #types == 0 then return end
    local rule = T.On() and T.RuleFor(T.Goal(), rules()) or nil
    local want = rule and T.Match(types, rule.def.words) or {}
    local tick, untick, keep = T.Plan(types, want, mine(), T.On())
    T.rule, T.want = rule and rule.key or nil, want
    local index = {}
    for _, ty in ipairs(types) do index[ty.name] = ty.index end
    for _, name in ipairs(tick) do
        local ok, err = pcall(CM.SetTracking, index[name], true)
        ns:Log("nav", string.format("tracking: %s on for your step (%s)%s", name, tostring(T.rule), ok and "" or (": " .. tostring(err))))
        if not ok then keep[name] = nil end
    end
    for _, name in ipairs(untick) do
        local ok, err = pcall(CM.SetTracking, index[name], false)
        ns:Log("nav", string.format("tracking: %s off again%s", name, ok and "" or (": " .. tostring(err))))
    end
    ns.db.nav.trackMine = keep
end

-------------------------------------------------------------------------------
-- The tick in the game's own tracking menu, and in Flow Settings
-------------------------------------------------------------------------------
function T.Toggle() T.Set(not T.On()) return T.On() end

-- (The game's menus let an add-on add entries: Menu.ModifyMenu(tag, fn).)
function T.Hook()
    local GM = _G.Menu
    if T.hooked or not (GM and GM.ModifyMenu) then return false end
    local ok, err = pcall(GM.ModifyMenu, T.MENU_TAG, function(_, root)
        T.menuSeen = true
        if root.CreateDivider then root:CreateDivider() end
        if root.CreateCheckbox then
            root:CreateCheckbox(T.LABEL, function() return T.On() end, function() T.Toggle() end)
        end
    end)
    T.hooked = ok
    if not ok then ns:Log("nav", "tracking menu: " .. tostring(err)) end
    return ok
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck{ group = "route", label = "The minimap shows what your next step needs",
        note = "(banker, trainer, flight master...)",
        tip = "While your next step is at a banker, an auctioneer, a trainer, a flight master, a repairer, an innkeeper or a mailbox, Flow ticks that kind in the game's minimap tracking, and unticks it after. "
            .. "A kind you ticked yourself is left alone and stays on. The same tick is at the bottom of the game's tracking menu.",
        get = function() return T.On() end,
        set = function(on) T.Set(on) end }
end

ns:OnLoad(function(saved)
    saved.nav = saved.nav or {}
    saved.nav.trackMine = saved.nav.trackMine or {}
    T.Hook()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() pcall(T.Tick) end) end
end)
ns:PerCharacter("nav.trackMine")

function T.Lines()
    local out = { string.format("minimap tracking managed by Flow: %s; the game's tracking: %s; its menu: %s", T.On() and "on" or "off",
        T.Has() and "there" or "not on this client",
        T.hooked and (T.menuSeen and "Flow's tick added (seen open)" or "Flow's tick asked for (not opened yet, or this client names the menu differently)") or "can't be added to on this client") }
    local g = T.Goal()
    out[#out + 1] = string.format("  your step: %s -> %s", tostring(g and (g.text or g.key) or "none"), tostring(T.rule or "no kind of tracking"))
    local types = T.Has() and T.Types() or {}
    local m = (ns.db and ns.db.nav and ns.db.nav.trackMine) or {}
    for _, ty in ipairs(types) do
        out[#out + 1] = string.format("  %d. %s: %s%s%s%s", ty.index, ty.name, ty.active and "on" or "off", ty.spell and " (a spell: not Flow's to change)" or "",
            m[ty.name] and " (ticked by Flow)" or "", (T.want and T.want[ty.name]) and " (your step needs it)" or "")
    end
    if #types == 0 then out[#out + 1] = "  the game lists no kinds of tracking" end
    return out
end
ns.commands.tracking = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then T.Set(arg == "on") end
    for i, l in ipairs(T.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
    print("  /flow tracking on|off")
end
ns:Register("help", "tracking", { order = 39, title = "The minimap shows your next step's townsfolk", lines = {
    "While your next step is at a banker, auctioneer, trainer, flight master, repairer, innkeeper or mailbox, Flow ticks that kind in the game's minimap tracking and unticks it after. What you ticked yourself stays on.",
    "Turn it off at the bottom of the game's tracking menu or in Flow Settings (Finding your way). /flow tracking lists the kinds.",
} })
