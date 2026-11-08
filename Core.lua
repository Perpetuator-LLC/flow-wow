-- Flow core: shared namespace, saved variables, and a tiny event bus
-- that modules hook into. Add new features as files in Modules\ and list
-- them in Flow.toc.

local ADDON_NAME, ns = ...

ns.name = ADDON_NAME
ns.modules = {}

-------------------------------------------------------------------------------
-- Registries: the extension points. New classes, specs, fight types, metrics,
-- advisors, gear considerations and fight probes are added by registering
-- them from their own files; existing code never needs editing.
-- See docs/ARCHITECTURE.md for every kind and its shape.
-------------------------------------------------------------------------------

local registries = {}

local function registry(kind)
    local r = registries[kind]
    if not r then
        r = { list = {}, byKey = {} }
        registries[kind] = r
    end
    return r
end

-- ns:Register("advisor", "trainer", def). Keys are unique per kind.
function ns:Register(kind, key, value)
    local r = registry(kind)
    if r.byKey[key] ~= nil then
        error(string.format("Flow: %s '%s' registered twice", kind, tostring(key)), 2)
    end
    r.byKey[key] = value
    r.list[#r.list + 1] = { key = key, value = value }
    return value
end

function ns:Get(kind, key)
    return registry(kind).byKey[key]
end

-- for key, value in ns:Each("metric") do ... end  (registration order)
function ns:Each(kind)
    local list, i = registry(kind).list, 0
    return function()
        i = i + 1
        local e = list[i]
        if e then return e.key, e.value end
    end
end

local frame = CreateFrame("Frame")
local handlers = {}

-- ns:On("EVENT_NAME", function(...) end)
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- pcall: not every client flavor has every event.
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then
            print("|cffff5555Flow error|r (" .. event .. "): " .. tostring(err))
        end
    end
    -- After every module's own logout work: this character's data goes back
    -- to FlowCharDB before the game writes the saved variables.
    if event == "PLAYER_LOGOUT" and ns.db and ns.charDb then
        local ok, err = pcall(ns.StoreCharacterData, ns, ns.db, ns.charDb)
        if not ok then print("|cffff5555Flow error|r (saving character data): " .. tostring(err)) end
    end
end)
frame:RegisterEvent("PLAYER_LOGOUT")

function ns:Print(msg)
    print("|cff66ccffFlow|r: " .. tostring(msg))
end

-------------------------------------------------------------------------------
-- Per-character data. FlowDB is shared by every character on the account
-- (settings, learned trails, NPC places). Anything about one character (its
-- fights, class trainer, recipes, hidden stops...) is declared per character
-- by the module that owns it, next to its ns:OnLoad:
--   ns:PerCharacter("trainer")                 a whole section of ns.db
--   ns:PerCharacter("quests.notOffered")       one field of a section
--   ns:PerCharacter(path, { adopt = fn })      plus what to keep from before
-- It's saved in FlowCharDB (SavedVariablesPerCharacter, so the game keeps one
-- per character) and sits at its usual place in ns.db while you play, so the
-- module's code doesn't change. At logout it goes back to FlowCharDB.
--
-- Data saved before this split was shared by every character. It's parked
-- in FlowDB.legacyShared, and the first time each character logs in it takes
-- what adopt(old, ctx) returns (a copy; nil = start fresh, the default).
-- ctx = { class, level, name }. later = true: adopt runs at PLAYER_LOGIN
-- instead, as adopt(old, ctx, current), for checks that need the game ready
-- (which professions you have); returning false there means "can't tell
-- yet", and it's tried again at the next login.
-------------------------------------------------------------------------------

local function getPath(t, path)
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end
local function setPath(t, path, value)
    local parts = {}
    for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
        if type(t[parts[i]]) ~= "table" then
            if value == nil then return end
            t[parts[i]] = {}
        end
        t = t[parts[i]]
    end
    t[parts[#parts]] = value
end
local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = deepCopy(x) end
    return c
end
ns.DeepCopy = deepCopy

function ns:PerCharacter(path, def)
    return self:Register("charData", path, def or {})
end

local function context()
    local _, class = UnitClass("player")
    return { class = class, level = UnitLevel("player"), name = UnitName("player") }
end

local function adoptOne(path, def, old, ctx, current)
    if old == nil or not def.adopt then return nil end
    local ok, keep
    if def.later then ok, keep = pcall(def.adopt, deepCopy(old), ctx, current)
    else ok, keep = pcall(def.adopt, deepCopy(old), ctx) end
    if not ok then
        print("|cffff5555Flow|r: couldn't sort old data (" .. path .. "): " .. tostring(keep))
        return nil
    end
    return keep
end

-- At load: park pre-split shared data once, let this character adopt its
-- share, then put this character's data where the modules look for it.
-- (Tables passed in, so the tests can run it on their own.)
function ns:SplitCharacterData(account, char, ctx)
    account.charSplit = account.charSplit or {}
    account.legacyShared = account.legacyShared or {}
    char.data = char.data or {}
    char.adopted = char.adopted or {}
    local legacy, store = account.legacyShared, char.data
    for path in self:Each("charData") do
        if not account.charSplit[path] then
            local v = getPath(account, path)
            if v ~= nil then legacy[path] = v; setPath(account, path, nil) end
            account.charSplit[path] = true
        end
    end
    for path, def in self:Each("charData") do
        if not char.adopted[path] and not def.later then
            if store[path] == nil then store[path] = adoptOne(path, def, legacy[path], ctx) end
            char.adopted[path] = true
        end
        setPath(account, path, store[path])
    end
end

-- At login: adoption that needs the game ready, merged into the live value.
function ns:AdoptLaterCharacterData(account, char, ctx)
    local legacy = account.legacyShared or {}
    for path, def in self:Each("charData") do
        if def.later and not char.adopted[path] then
            local keep = adoptOne(path, def, legacy[path], ctx, getPath(account, path))
            -- false = the game isn't ready to tell yet: try again next login.
            if keep ~= false then
                if keep ~= nil then setPath(account, path, keep) end
                char.adopted[path] = true
            end
        end
    end
end

-- At logout: this character's data back to FlowCharDB, out of FlowDB.
function ns:StoreCharacterData(account, char)
    char.data = char.data or {}
    for path in self:Each("charData") do
        char.data[path] = getPath(account, path)
        setPath(account, path, nil)
    end
end
ns._getPath, ns._setPath = getPath, setPath   -- (tests)

-- ns:OnLoad(fn): run fn once saved variables (ns.db) are available.
local loaders = {}
function ns:OnLoad(fn)
    table.insert(loaders, fn)
end

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    FlowDB = FlowDB or {}
    FlowCharDB = FlowCharDB or {}
    ns.db, ns.charDb = FlowDB, FlowCharDB
    local splitOk, splitErr = pcall(ns.SplitCharacterData, ns, FlowDB, FlowCharDB, context())
    if not splitOk then print("|cffff5555Flow load error|r (character data): " .. tostring(splitErr)) end
    for _, fn in ipairs(loaders) do
        local ok, err = pcall(fn, ns.db)
        if not ok then
            print("|cffff5555Flow load error|r: " .. tostring(err))
        end
    end
end)

ns:On("PLAYER_LOGIN", function()
    if not (ns.db and ns.charDb) then return end
    ns:AdoptLaterCharacterData(ns.db, ns.charDb, context())
end)

-- ns:MakeMovable(frame, save, clickable): every Flow element moves the same
-- way: hold Shift and drag. Position is stored in save.point. Frames that
-- aren't clickable only take the mouse while Shift is held, so they never
-- block clicks in a fight.
local passive = {}
function ns:MakeMovable(frame, save, clickable)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, b, x, y = self:GetPoint()
        save.point = { a, b, x, y }
    end)
    if not clickable then
        frame:EnableMouse(false)
        passive[#passive + 1] = frame
    end
end

do
    local watcher, shiftWas = CreateFrame("Frame"), false
    watcher:SetScript("OnUpdate", function()
        local shift = IsShiftKeyDown() and true or false
        if shift == shiftWas then return end
        shiftWas = shift
        for _, f in ipairs(passive) do f:EnableMouse(shift) end
    end)
end

-- /flow api: what this game client lets addons do. Useful because Forever is
-- a new client and its restrictions aren't documented yet.
local function apiReport(arg)
    ns.db.api = ns.db.api or {}
    local a, b = (arg or ""):match("^(%S*)%s*(%S*)")
    if a == "combatlog" and (b == "on" or b == "off" or b == "auto") then
        if b == "auto" then ns.db.api.combatLog = nil else ns.db.api.combatLog = (b == "on") end
        ns:Print("combat log use set to " .. b .. ". /reload to apply.")
        return
    end
    local function has(v) return v ~= nil and "yes" or "no" end
    local Safe = ns.api and ns.api.Safe or function(v) return v end
    local function shown(v)
        if v == nil then return "nil" end
        if Safe(v) == nil then return "HIDDEN (secret)" end
        return tostring(v)
    end
    ns:Print("client check:")
    print("  build: " .. tostring((select(1, GetBuildInfo()))) .. " interface " .. tostring((select(4, GetBuildInfo()))))
    print("  secret values: " .. has(issecretvalue))
    print("  combat log function: " .. has(CombatLogGetCurrentEventInfo)
        .. ", Flow uses it: " .. tostring(ns.api and ns.api.CombatLogAllowed()))
    print("  damage meter API: " .. has(C_DamageMeter))
    -- Health is hidden from add-ons here; these say whether anything else
    -- could tell Flow how hurt you are (for the after-fight heal).
    if C_DamageMeter then
        local names = {}
        for k in pairs(C_DamageMeter) do names[#names + 1] = tostring(k) end
        table.sort(names)
        print("    damage meter functions: " .. table.concat(names, ", "))
    end
    local okBar, bar = pcall(function()
        local hb = PlayerFrame and (PlayerFrame.healthbar or (PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar))
        return hb and hb:GetValue()
    end)
    local okPct, pct = pcall(function() return UnitHealthPercent and UnitHealthPercent("player") end)
    print("  health bar value: " .. (okBar and shown(bar) or "error") .. ", UnitHealthPercent: " .. has(UnitHealthPercent)
        .. (UnitHealthPercent and (" = " .. (okPct and shown(pct) or "error")) or ""))
    local low = ns.api and ns.api.LowHealthWarning and ns.api.LowHealthWarning()
    print("  low-health warning: " .. (low == nil and "not readable" or tostring(low))
        .. ", stunned etc: " .. tostring(ns.api and ns.api.LossOfControl and ns.api.LossOfControl() or "no")
        .. ", auto attack on: " .. tostring(ns.api and ns.api.Swinging and ns.api.Swinging()))
    print("  C_Spell: " .. has(C_Spell) .. ", C_SpellBook: " .. has(C_SpellBook) .. ", C_Container: " .. has(C_Container))
    print("  quest waypoints: " .. has(C_QuestLog and C_QuestLog.GetNextWaypoint)
        .. ", equipment manager: " .. has(C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs))
    print("  your health: " .. shown(UnitHealth("player")) .. ", facing: " .. shown(GetPlayerFacing and GetPlayerFacing()))
    -- Heights: does this client give addons a height (z)? Needed for up/down hints.
    local okP, y, x, z = pcall(UnitPosition, "player")
    print("  position: " .. (okP and (shown(y) .. ", " .. shown(x) .. ", height " .. shown(z)) or "not available")
        .. ", indoors: " .. tostring(IsIndoors and IsIndoors()))
    if UnitExists("target") then print("  target health: " .. shown(UnitHealth("target"))) end
    print("  /flow api combatlog on|off|auto")
end

-- /flow slash command; modules can add subcommands to ns.commands.
ns.commands = { api = apiReport }
SLASH_FLOW1 = "/flow"
SlashCmdList.FLOW = function(input)
    local cmd, rest = (input or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local fn = ns.commands[cmd]
    if fn then
        fn(rest)
    elseif ns.commands.help then
        ns.commands.help()
    else
        ns:Print("commands:")
        for name in pairs(ns.commands) do
            print("  /flow " .. name)
        end
    end
end
