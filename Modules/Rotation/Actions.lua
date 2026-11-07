-- Flow Actions: what your Flow key does out of combat when there's no spell
-- to suggest, based on the route stop you're at. One press per step:
--
--   at a fishing stop:  equip your Fishing Pole -> put a lure on it ->
--                       cast Fishing -> (while fishing) reel in the bobber
--   at a mining/herb stop: turn on Find Minerals / Find Herbs -> gather
--   after you leave:    put your weapons back (main hand, then off hand)
--
-- Each step is a registration (ns:Register("action", key, { order, get })),
-- so new ones (skinning, a hearthstone at the end of the route...) are new
-- entries. get(ctx) returns nil or a suggestion:
--   { type = "spell"|"item"|"interact", spell = name, item = "item:ID",
--     targetSlot = 16, icon = texture, label = "Equip your Fishing Pole",
--     urgent = true (beats the rotation's buff suggestion) }
--
-- Why one press per step and not one macro: WoW: Forever ignores macro-type
-- secure buttons (see CLAUDE.md), and the game only lets an add-on equip,
-- use or cast from a key press. So the key moves through the steps instead.

local _, ns = ...
local A = ns.api
local X = {}
ns.actions = X

local MAIN, OFF = 16, 17
local NEAR = 45   -- yards from the stop: "you're there"

-------------------------------------------------------------------------------
-- Items
-------------------------------------------------------------------------------

local function instant(id)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(id) end
    if GetItemInfoInstant then return GetItemInfoInstant(id) end
end

-- Fishing poles: weapon class 2, subclass 20 (any pole, any client's IDs).
local POLES = { [6256] = true, [6365] = true, [6366] = true, [6367] = true, [12225] = true, [19022] = true, [19970] = true }
function X.IsPole(id)
    if not id then return false end
    if POLES[id] then return true end
    local _, _, _, _, _, classID, subclassID = instant(id)
    return classID == 2 and subclassID == 20
end

-- Lures, best first (fishing bonus): Aquadynamic Fish Attractor, Bright
-- Baubles, Flesh Eating Worm, Nightcrawlers, Aquadynamic Fish Lens, Shiny Bauble.
X.LURES = { 6533, 6532, 7307, 6530, 6811, 6529 }

local function bagItems()
    local out = {}
    local C = C_Container
    local slots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
    local itemAt = (C and C.GetContainerItemID) or GetContainerItemID
    if not (slots and itemAt) then return out end
    for bag = 0, 4 do
        for slot = 1, (slots(bag) or 0) do
            local id = itemAt(bag, slot)
            if id then out[#out + 1] = id end
        end
    end
    return out
end

local function equipped(slot) return GetInventoryItemID and GetInventoryItemID("player", slot) end

local function count(id) return (GetItemCount and GetItemCount(id)) or 0 end

local function itemIcon(id)
    local _, _, _, _, icon = instant(id)
    return icon or (GetItemIcon and GetItemIcon(id))
end

local function usable(id)
    if not IsUsableItem then return true end
    local ok, u = pcall(IsUsableItem, id)
    return not ok or u ~= false
end

-- A lure on your main hand right now?
local function lured()
    if not GetWeaponEnchantInfo then return false end
    local ok, has = pcall(GetWeaponEnchantInfo)
    return ok and A.Safe(has) and true or false
end

-------------------------------------------------------------------------------
-- Spells, tracking, interact
-------------------------------------------------------------------------------

local function knows(spell) return A.SpellInfo(spell) ~= nil end

local function spellIcon(spell)
    local _, icon = A.SpellInfo(spell)
    return icon
end

-- Is this minimap tracking (Find Minerals, Find Herbs) on? nil = can't tell.
local function tracking(spell)
    local M = C_Minimap
    if M and M.GetNumTrackingTypes and M.GetTrackingInfo then
        for i = 1, (M.GetNumTrackingTypes() or 0) do
            local a, _, c = M.GetTrackingInfo(i)
            local name, active
            if type(a) == "table" then name, active = a.name, a.active else name, active = a, c end
            if name == spell then return active and true or false end
        end
    end
    if GetTrackingTexture then
        local cur = GetTrackingTexture()
        if not cur then return false end            -- nothing tracked
        local icon = spellIcon(spell)
        if icon then return cur == icon end
    end
    return nil
end

-- The game's Interact key reaches the nearest bobber / vein / herb once
-- "soft target interact" is on (a suggested WoW setting).
function X.CanInteract()
    if InCombatLockdown() then return false end
    local ok, v = pcall(GetCVar, "SoftTargetInteract")
    return ok and v ~= nil and tonumber(v) and tonumber(v) > 0 or false
end

local function channeling(spell)
    if not UnitChannelInfo then return false end
    local name = A.Safe(UnitChannelInfo("player"))
    return name == spell
end

-------------------------------------------------------------------------------
-- Where you are on the route
-------------------------------------------------------------------------------

local function near(goal, p, yards)
    if not (goal and p and ns.nav) then return false end
    for _, pt in ipairs(goal.points or {}) do
        if pt.wx and pt.cont == p.cont then
            local e, s = ns.nav:Offset(p, pt.wx, pt.wy)
            if e and e * e + s * s < yards * yards then return true end
        end
    end
    return false
end

-- Which profession a stop is for. Stops from the skill planner say so
-- (goal.prof); others are recognised by their key ("skill:Fishing") or, for
-- quest stops like "catch 5 fish", by their text.
function X.GoalProf(goal)
    if not goal then return nil end
    if goal.prof then return goal.prof end
    local p = goal.key and goal.key:match("^skill:(.+)$")
    if p then return p end
    if goal.kind ~= "merchant" and type(goal.text) == "string"
        and (goal.text:find("[Ff]ish[^i]") or goal.text:find("[Ff]ish$") or goal.text:find("[Cc]atch ")) then
        return "Fishing"
    end
end

-- Where you last fished. Fishing goes on wherever the pole is on and you've
-- been casting, not just at Flow's own stop (any lake, any fishing quest),
-- until you walk away from it.
local FISH_NEAR, FISH_LEFT = 120, 60
local function dist(p, at)
    if not (p and at and p.cont == at.cont and ns.nav) then return math.huge end
    local e, s = ns.nav:Offset(p, at.wx, at.wy)
    return e and math.sqrt(e * e + s * s) or math.huge
end
local function markFishingSpot()
    local p = ns.nav and ns.nav:PlayerPos()
    if p then ns.db.actions.fishedAt = { cont = p.cont, wx = p.wx, wy = p.wy } end
end
X._markFishingSpot = markFishingSpot  -- (tests)

-- Weapons you had before Flow put the pole on (to put back afterwards).
local function saved() return ns.db.actions.weapons end
local function saveWeapons()
    markFishingSpot()
    local mh, oh = equipped(MAIN), equipped(OFF)
    if X.IsPole(mh) then return end
    ns.db.actions.weapons = { main = mh, off = oh }
end

function X:Context()
    local p = ns.nav and ns.nav:PlayerPos()
    local choice = ns.nav and ns.nav.current
    local goal = choice and choice.goal
    local prof = X.GoalProf(goal)
    local pole = X.IsPole(equipped(MAIN))
    local atFish = prof == "Fishing" and near(goal, p, FISH_NEAR) or false
    local spot = ns.db.actions.fishedAt
    return {
        p = p, goal = goal, prof = prof, pole = pole,
        at = goal and near(goal, p, NEAR) or false,
        atFish = atFish,
        -- Fishing now: at a fishing stop, or the pole is on and you're still
        -- where you put it on / last cast (or haven't said where yet).
        fishing = atFish or (pole and (not spot or dist(p, spot) < FISH_LEFT)) or false,
    }
end

-- Every cast marks the spot (so moving along the shore keeps you fishing).
ns:On("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
    if unit ~= "player" then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if name == "Fishing" then markFishingSpot() end
end)

-------------------------------------------------------------------------------
-- The steps
-------------------------------------------------------------------------------

-- Fishing: equip the pole.
ns:Register("action", "fish:equip", { order = 10, get = function(ctx)
    if not ctx.atFish or ctx.pole then return nil end
    for _, id in ipairs(bagItems()) do
        if X.IsPole(id) then
            return { type = "item", item = "item:" .. id, icon = itemIcon(id), label = "Equip your Fishing Pole",
                     before = saveWeapons }
        end
    end
end })

-- Fishing: a lure on the pole (best one you carry that you can use).
ns:Register("action", "fish:lure", { order = 20, get = function(ctx)
    if not (ctx.fishing and ctx.pole) or lured() or channeling("Fishing") then return nil end
    for _, id in ipairs(X.LURES) do
        if count(id) > 0 and usable(id) then
            local name = (GetItemInfo and GetItemInfo(id)) or "a lure"
            return { type = "item", item = "item:" .. id, targetSlot = MAIN, icon = itemIcon(id),
                     label = "Put " .. name .. " on your pole" }
        end
    end
end })

-- Fishing: reel in. While the line is out, the key presses Interact, which
-- clicks your bobber (press when it splashes).
ns:Register("action", "fish:reel", { order = 30, get = function(ctx)
    if not (ctx.pole and channeling("Fishing") and X.CanInteract()) then return nil end
    return { type = "interact", icon = spellIcon("Fishing"), label = "Press when the bobber splashes", urgent = true }
end })

-- Fishing: cast.
ns:Register("action", "fish:cast", { order = 40, get = function(ctx)
    if not (ctx.fishing and ctx.pole) or channeling("Fishing") then return nil end
    if not knows("Fishing") then return nil end
    return { type = "spell", spell = "Fishing", icon = spellIcon("Fishing"), label = "Cast your line" }
end })

-- Mining / Herbalism: tracking on, then the key gathers (Interact).
local FIND = { Mining = "Find Minerals", Herbalism = "Find Herbs" }
ns:Register("action", "gather:find", { order = 50, get = function(ctx)
    local spell = ctx.goal and ctx.goal.kind ~= "merchant" and FIND[ctx.prof]
    if not spell or not knows(spell) or tracking(spell) ~= false then return nil end
    return { type = "spell", spell = spell, icon = spellIcon(spell), label = "Turn on " .. spell }
end })
ns:Register("action", "gather:interact", { order = 60, get = function(ctx)
    if not (ctx.at and FIND[ctx.prof] and ctx.goal.kind ~= "merchant" and X.CanInteract()) then return nil end
    local verb = ctx.prof == "Mining" and "Mine" or "Gather"
    return { type = "interact", icon = spellIcon(ctx.prof == "Mining" and "Mining" or "Herb Gathering")
                 or "Interface\\Icons\\Trade_Mining",
             label = verb .. " (stand next to it and press)" }
end })

-- Left the fishing spot with the pole still on: weapons back, main hand first.
ns:Register("action", "fish:restore", { order = 70, get = function(ctx)
    local w = saved()
    if not w or ctx.fishing or channeling("Fishing") then return nil end
    local mh, oh = equipped(MAIN), equipped(OFF)
    if w.main and mh ~= w.main and count(w.main) > 0 then
        return { type = "item", item = "item:" .. w.main, icon = itemIcon(w.main), label = "Put your weapon back" }
    end
    if w.off and oh ~= w.off and count(w.off) > 0 then
        return { type = "item", item = "item:" .. w.off, icon = itemIcon(w.off), label = "Put your off-hand back" }
    end
    -- All back (or gone from your bags): done.
    if not X.IsPole(mh) then ns.db.actions.weapons = nil; ns.db.actions.fishedAt = nil end
end })

-------------------------------------------------------------------------------

local ordered
local function list()
    if not ordered then
        ordered = {}
        for key, a in ns:Each("action") do ordered[#ordered + 1] = { key = key, a = a } end
        table.sort(ordered, function(x, y) return (x.a.order or 50) < (y.a.order or 50) end)
    end
    return ordered
end

-- The action for right now (out of combat only), or nil.
function X:Current()
    if InCombatLockdown() or UnitIsDeadOrGhost("player") or ns.db.actions.enabled == false then return nil end
    local ctx = self:Context()
    for _, e in ipairs(list()) do
        local ok, s = pcall(e.a.get, ctx)
        if ok and s then
            s.kind, s.key = "action", e.key
            return s
        end
    end
end

ns:OnLoad(function(saved)
    saved.actions = saved.actions or {}
end)

ns.commands.action = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.actions.enabled = (arg == "on")
        ns:Print("Flow Actions " .. arg)
        return
    end
    local ctx = X:Context()
    local s = X:Current()
    ns:Print(string.format("Flow Action now: %s", s and (s.label .. " [" .. s.key .. "]") or "nothing"))
    print(string.format("  stop %s (%s), at it: %s, fishing here: %s, pole on: %s, interact key reaches objects: %s",
        tostring(ctx.goal and ctx.goal.key), tostring(ctx.prof), tostring(ctx.at), tostring(ctx.fishing), tostring(ctx.pole), tostring(X.CanInteract())))

    print("  /flow action on|off")
end
