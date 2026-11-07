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
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then
            print("|cffff5555Flow error|r (" .. event .. "): " .. tostring(err))
        end
    end
end)

function ns:Print(msg)
    print("|cff66ccffFlow|r: " .. tostring(msg))
end

-- ns:OnLoad(fn): run fn once saved variables (ns.db) are available.
local loaders = {}
function ns:OnLoad(fn)
    table.insert(loaders, fn)
end

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    FlowDB = FlowDB or {}
    ns.db = FlowDB
    for _, fn in ipairs(loaders) do
        local ok, err = pcall(fn, ns.db)
        if not ok then
            print("|cffff5555Flow load error|r: " .. tostring(err))
        end
    end
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
    local okP, pct = pcall(function() return UnitHealthPercent and UnitHealthPercent("player") end)
    print("  health bar value: " .. (okBar and shown(bar) or "error") .. ", UnitHealthPercent: " .. has(UnitHealthPercent)
        .. (UnitHealthPercent and (" = " .. (okP and shown(pct) or "error")) or ""))
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
