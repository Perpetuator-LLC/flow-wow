-------------------------------------------------------------------------------
-- Flow - Gear/SetRecipes.lua
-- Gear sets Flow can build for you, and the picture each one gets (0.35.375).
--
-- "You're building these equipment sets for the user, so you should pick an
-- icon that matches it. Feral cat should have a cat icon ... maybe you have
-- one for fishing: user opens the bag, clicks the fishing set, the easy
-- buttons detect it's now a fishing pole, and cast becomes the spell.
-- Abstract what we're doing here and standardize this, so we keep building
-- it automatically if we see opportunity."
--
-- A recipe is a set Flow knows how to put together:
--   ns:Register("gearSet", key, {
--       name  = "Fishing",                       -- the set's name in the game
--       icon  = "Interface\\Icons\\Trade_Fishing",
--       what  = "your fishing pole",             -- for the messages
--       offer = function() return true end,      -- worth building now?
--       wants = function() return { link } end,  -- what goes on, over what you wear
--   })
-- Building one (SR.Build): put the wanted pieces on, save what you're
-- wearing as the game's own equipment set under that name and icon, and put
-- your own gear back on. Out of a fight only. The set then has its icon on
-- your bags (SetIcons.lua): one click and it's on.
--
-- Built in: Fishing (your pole; the target button then casts, as it does
-- whenever a pole is in your hands). Your specs' sets are built by "Keep set
-- for" (KeepSets.lua) and get their spec's icon here.
--
-- The picture a set shows on your bags (SR.IconFor), first that applies:
-- one you picked (right-click its icon), its recipe's, its spec's, the
-- game's own. Picking one also asks the game to use it, so the Equipment
-- Manager shows the same where the game allows.
-------------------------------------------------------------------------------

local _, ns = ...
local G = ns.gear
local SR = {}
ns.setRecipes = SR

SR.STEP, SR.SETTLE = 0.4, 1.2

local CE = C_EquipmentSet
local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName

-- Pure: the picture for a set called `name`.
--   mine: { [set name] = texture } your own picks; recipes: { { name, icon } };
--   roles: { { name = the role's set name, icon = its spec's } }; game: the game's own
function SR.Pick(name, mine, recipes, roles, game)
    if mine and name and mine[name] then return mine[name], "yours" end
    for _, r in ipairs(recipes or {}) do
        if r.name == name and r.icon then return r.icon, "recipe" end
    end
    for _, r in ipairs(roles or {}) do
        if r.name == name and r.icon then return r.icon, "spec" end
    end
    return game, "game"
end

local function recipes()
    local out = {}
    for key, r in ns:Each("gearSet") do out[#out + 1] = { key = key, name = r.name, icon = r.icon, def = r } end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end
local function roleSets()
    local out = {}
    for _, role in ipairs(G.ROLES) do
        local name = G.sets and G.sets.SetFor and G.sets:SetFor(role)
        local gs = G.sets and G.sets.GameSet and G.sets:GameSet(role)
        if gs or name then out[#out + 1] = { name = gs and gs.name or name, icon = ns:RoleIconPath(role), role = role } end
    end
    return out
end
function SR.IconFor(name, game)
    local mine = ns.db and ns.db.gear and ns.db.gear.setIcon
    return SR.Pick(name, mine, recipes(), roleSets(), game)
end

-- What the game takes for a picture: its file number where it can be looked up, else the path.
function SR.GameIcon(texture)
    if type(texture) == "number" then return texture end
    if type(texture) == "string" and GetFileIDFromPath then
        local ok, id = pcall(GetFileIDFromPath, texture)
        if ok and type(id) == "number" and id > 0 then return id end
    end
    return texture
end

-- You picked a picture for a set (nil: back to Flow's own choice). Kept for
-- this character, and handed to the game so its Equipment Manager matches.
function SR.SetIcon(set, texture)
    if not (set and set.name) then return false end
    ns.db.gear.setIcon = ns.db.gear.setIcon or {}
    ns.db.gear.setIcon[set.name] = texture
    local asked = false
    if texture and set.id and CE and CE.ModifyEquipmentSet and not InCombatLockdown() then
        local ok, err = pcall(CE.ModifyEquipmentSet, set.id, set.name, SR.GameIcon(texture))
        asked = ok
        ns:Log("gear", string.format("set icon: %s -> %s (the game: %s)", tostring(set.name), tostring(texture), ok and "asked" or tostring(err)))
    end
    if ns.setIcons then ns.setIcons.Refresh() end
    return true, asked
end

-- The pictures offered in a set icon's menu: your specs', then a few plain ones.
function SR.Choices()
    local out, seen = {}, {}
    local function add(label, texture)
        if texture and not seen[texture] then seen[texture] = true; out[#out + 1] = { label = label, texture = texture } end
    end
    for _, role in ipairs(G.ROLES) do add(ns:RoleName(role), ns:RoleIconPath(role)) end
    for _, r in ipairs(recipes()) do add(r.name, r.icon) end
    add("Shield", "Interface\\Icons\\INV_Shield_04")
    add("Sword", "Interface\\Icons\\INV_Sword_04")
    add("Staff", "Interface\\Icons\\INV_Staff_08")
    add("Chest armor", "Interface\\Icons\\INV_Chest_Chain_04")
    add("Bag", "Interface\\Icons\\INV_Misc_Bag_08")
    return out
end

-------------------------------------------------------------------------------
-- Building a recipe's set
-------------------------------------------------------------------------------

-- Pure: of the wanted links, the ones you aren't wearing. worn: { [link] = true }
function SR.ToPutOn(wants, worn)
    local out = {}
    for _, link in ipairs(wants or {}) do
        if link and not (worn and worn[link]) then out[#out + 1] = link end
    end
    return out
end

local function wornLinks()
    local worn, bySlot = {}, {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then worn[link] = true; bySlot[slot] = link end
    end
    return worn, bySlot
end

-- The game's set you have on now ({ id, name }), or nil.
local function wornSet()
    if not (CE and CE.GetEquipmentSetIDs and CE.GetEquipmentSetInfo) then return nil end
    local ok, ids = pcall(CE.GetEquipmentSetIDs)
    for _, id in ipairs(ok and ids or {}) do
        local okI, name, _, _, on = pcall(CE.GetEquipmentSetInfo, id)
        if okI and on then return { id = id, name = name } end
    end
end

-- Saves what you're wearing as the game's set `name` (new, or brought up to date).
local function saveAs(name, icon)
    local id = CE.GetEquipmentSetID and CE.GetEquipmentSetID(name) or nil
    local ok, err
    if id then ok, err = pcall(CE.SaveEquipmentSet, id)
    else ok, err = pcall(CE.CreateEquipmentSet, name, SR.GameIcon(icon) or 134400) end
    ns:Log("gear", string.format("set recipe: %s '%s': %s", id and "updated" or "made", tostring(name), ok and "ok" or tostring(err)))
    return ok, err
end

-- Builds a recipe's set. done(ok, text) at the end.
function SR.Build(key, done)
    done = done or function(_, text) if text then ns:Print(text) end end
    local r = ns:Get("gearSet", key)
    if not r then return done(false, "Flow has no gear set called " .. tostring(key) .. ".") end
    if not (CE and CE.CreateEquipmentSet and G.sets:HasEquipmentManager()) then return done(false, "This game has no equipment sets to build.") end
    if InCombatLockdown() then return done(false, "Flow builds gear sets out of a fight.") end
    if SR.building or (ns.keepSets and ns.keepSets.building) then return done(false, "Flow is still building another set.") end
    local okW, wants = pcall(r.wants)
    if not okW or type(wants) ~= "table" or #wants == 0 then return done(false, string.format("Flow found nothing to make a %s set from (%s).", r.name, tostring(r.what or "its pieces"))) end
    local worn, before = wornLinks()
    local toPut = SR.ToPutOn(wants, worn)
    if #toPut == 0 then
        -- You're wearing it all: the set is what you have on.
        local ok, err = saveAs(r.name, r.icon)
        if ns.setIcons then C_Timer.After(0.8, function() ns.setIcons.Refresh() end) end
        return done(ok, ok and string.format("Saved what you're wearing as your %s set.", r.name) or ("Couldn't save the " .. r.name .. " set: " .. tostring(err)))
    end
    if not equip then return done(false, "This game doesn't let Flow put gear on.") end
    local back = wornSet()
    SR.building = key
    for i, link in ipairs(toPut) do
        C_Timer.After((i - 1) * SR.STEP, function()
            if SR.building == key and not InCombatLockdown() then pcall(equip, link) end
        end)
    end
    C_Timer.After((#toPut - 1) * SR.STEP + SR.SETTLE, function()
        if InCombatLockdown() then
            SR.building = nil
            return done(false, string.format("A fight started while Flow was building your %s set: it isn't saved, and you may be wearing some of it.", r.name))
        end
        local ok, err = saveAs(r.name, r.icon)
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then
                if back and CE.UseEquipmentSet then pcall(CE.UseEquipmentSet, back.id)
                else for slot = 1, 19 do if before[slot] then pcall(equip, before[slot], slot) end end end
            end
            SR.building = nil
            C_Timer.After(SR.SETTLE, function()
                if G.sets and G.sets.Refresh then G.sets:Refresh() end
                if ns.setIcons then ns.setIcons.Refresh() end
            end)
            done(ok, ok and string.format("Built your %s set (%s) and put your own gear back on. Its icon is on your bags: one click puts it on.", r.name, tostring(r.what or "its pieces"))
                or ("Couldn't save the " .. r.name .. " set: " .. tostring(err)))
        end)
    end)
end

-- Does the game have a set by this name already?
function SR.Exists(name)
    if not (CE and CE.GetEquipmentSetID) then return false end
    local ok, id = pcall(CE.GetEquipmentSetID, name)
    return ok and id ~= nil
end

-- The recipes worth building now that you don't have yet: { { key, name, icon } }.
function SR.Offers()
    local out = {}
    for _, r in ipairs(recipes()) do
        local ok, yes = pcall(r.def.offer or function() return true end)
        if ok and yes and not SR.Exists(r.name) then out[#out + 1] = r end
    end
    return out
end
-- Builds each of them, one after the other.
function SR.BuildOffered()
    local list = SR.Offers()
    local function nextOne(i)
        local r = list[i]
        if not r then return end
        SR.Build(r.key, function(_, text)
            if text then ns:Print(text) end
            C_Timer.After(SR.SETTLE + 0.5, function() nextOne(i + 1) end)
        end)
    end
    nextOne(1)
    return #list
end

-------------------------------------------------------------------------------
-- Built in: Fishing
-------------------------------------------------------------------------------
-- Your fishing pole: the one in your hands, else the first in your bags.
function SR.FishingPole()
    local D = ns.disposition
    if not (D and D.ToolProfession) then return nil end
    local worn = GetInventoryItemLink("player", 16)
    if worn and D:ToolProfession(tonumber(worn:match("item:(%d+)")), worn:match("%[(.-)%]")) == "Fishing" then return worn, true end
    local found
    if D.EachBagItem then
        D:EachBagItem(function(_, _, link)
            if not found and D:ToolProfession(tonumber(link:match("item:(%d+)")), link:match("%[(.-)%]")) == "Fishing" then found = link end
        end)
    end
    return found, false
end
ns:Register("gearSet", "fishing", {
    name = "Fishing", icon = "Interface\\Icons\\Trade_Fishing", what = "your fishing pole",
    offer = function() return ns.api.Skill("Fishing") ~= nil and SR.FishingPole() ~= nil end,
    wants = function()
        local pole = SR.FishingPole()
        return pole and { pole } or {}
    end,
})

ns:OnLoad(function(saved)
    saved.gear = saved.gear or {}
    saved.gear.setIcon = saved.gear.setIcon or {}
end)
ns:PerCharacter("gear.setIcon")
