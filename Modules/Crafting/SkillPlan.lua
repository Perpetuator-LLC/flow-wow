-- Profession skill plans as route stops. For each profession you need to
-- raise (a quest such as "Raise your blacksmithing skill to 20", or a planned
-- profession that's behind your level) it works out, from what you have NOW:
--   what to make     cheapest skill-ups per material at your skill (Guides.lua,
--                    corrected by your real profession window, Recipes.lua)
--   what that needs  materials, minus what's in your bags
--   how to get them  smelt ore you carry, mine veins / kill mobs on this map,
--                    buy from a vendor
-- and hands the route planner the stops: gather, smelt, craft, learn, buy.
-- The planner mixes them with your quests by distance, so you mine the veins
-- that are on the way. Bags change -> plan changes (re-planned live).
-- Stops that can't happen yet (no Mining, no hammer, skill too low) are
-- listed as blocked, with the reason, instead of disappearing.

local _, ns = ...
local SP = {}
ns.skillPlan = SP

local A = ns.api
local MAX_POINTS = 60

local function count(id) return (GetItemCount and GetItemCount(id)) or 0 end
-- A tool for this profession in your bags or equipped (any version of it).
local function hasTool(prof, id)
    if id and count(id) > 0 then return true end
    return ns.disposition and ns.disposition.HasTool and ns.disposition:HasTool(prof) or false
end
local function src(id) return ns:Get("itemSource", id) end
local function itemName(id)
    local s = src(id)
    return (s and s.name) or (GetItemInfo and GetItemInfo(id)) or ("item " .. id)
end

-- Profession name as the guides spell it ("first aid" -> "First Aid").
local function profName(lower)
    for name in ns:Each("profGuide") do
        if name:lower() == lower then return name end
    end
    for _, p in ipairs(A.Professions()) do
        if p.name:lower() == lower then return p.name end
    end
end

-- "Raise your blacksmithing skill to 20" -> "Blacksmithing", 20
function SP.ParseObjective(text)
    if type(text) ~= "string" then return nil end
    local what, n = text:lower():match("raise your ([%a ]-) skill to (%d+)")
    if not what then n, what = text:lower():match("reach (%d+) ([%a ]-) skill") end
    if not what then return nil end
    local name = profName(what)
    if name then return name, tonumber(n) end
end

-------------------------------------------------------------------------------
-- Places
-------------------------------------------------------------------------------

local function here()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

local function playerPoint()
    local p = ns.nav and ns.nav.PlayerPos and ns.nav:PlayerPos()
    if p then return { map = p.map, x = p.x, y = p.y, cont = p.cont, wx = p.wx, wy = p.wy } end
end

-- Questie spawns -> map points; on this map if any are here, else anywhere.
local function spawnPoints(spawnTables)
    local mine, all = {}, {}
    local map = here()
    for _, spawns in ipairs(spawnTables) do
        for areaId, list in pairs(spawns or {}) do
            local m = ns.quests:UiMapForArea(areaId)
            if m then
                for _, c in ipairs(list) do
                    if c[1] and c[1] >= 0 and c[2] and c[2] >= 0 then
                        local pt = { map = m, x = c[1] / 100, y = c[2] / 100 }
                        if m == map and #mine < MAX_POINTS then mine[#mine + 1] = pt end
                        if #all < MAX_POINTS then all[#all + 1] = pt end
                    end
                end
            end
        end
    end
    return #mine > 0 and mine or all, #mine > 0
end

local function objectPoints(ids)
    local spawns = {}
    for _, id in ipairs(ids or {}) do
        local o = ns.quests:QuestieGet("GetObject", id)
        if o and o.spawns then spawns[#spawns + 1] = o.spawns end
    end
    return spawnPoints(spawns)
end

local function npcPoints(names)
    if ns.quests.NPCsByName then ns.quests:NPCsByName(names) end
    local map, mine, all = here(), {}, {}
    for _, n in ipairs(names or {}) do
        for _, pt in ipairs(ns.places:Points(n)) do
            if pt.map == map then mine[#mine + 1] = pt end
            all[#all + 1] = pt
        end
    end
    return #mine > 0 and mine or all, #mine > 0
end

-- What an item costs at a vendor (copper): the price you last saw there,
-- else the guide's estimate. Buy stops carry it as `cost`, so the route
-- lists them as blocked until you can pay (Nav.lua).
function SP.Price(id)
    local seen = ns.db.prices and ns.db.prices[id]
    if seen then return seen end
    local s = src(id)
    return s and s.price
end

local function recordPrices()
    if not (GetMerchantNumItems and GetMerchantItemInfo) then return end
    ns.db.prices = ns.db.prices or {}
    for i = 1, GetMerchantNumItems() do
        local _, _, price, qty = GetMerchantItemInfo(i)
        local id = GetMerchantItemID and GetMerchantItemID(i)
        if not id and GetMerchantItemLink then
            local link = GetMerchantItemLink(i)
            id = link and tonumber(link:match("item:(%d+)"))
        end
        if id and price and price > 0 then ns.db.prices[id] = math.ceil(price / math.max(qty or 1, 1)) end
    end
end
ns:On("MERCHANT_SHOW", function() C_Timer.After(0.3, function() pcall(recordPrices) end) end)

local function vendorPoints(itemId)
    local item = ns.quests:QuestieGet("GetItem", itemId)
    local spawns, names = {}, {}
    for _, id in ipairs(item and item.vendors or {}) do
        local npc = ns.quests:QuestieGet("GetNPC", id)
        if npc and npc.spawns then spawns[#spawns + 1] = npc.spawns; names[#names + 1] = npc.name end
    end
    local pts, onMap = spawnPoints(spawns)
    return pts, onMap, names
end

-- Anvils and forges stand by the blacksmiths; Flow uses those as the spot.
local function stationPoints(station)
    if station == "anvil" or station == "forge" then
        return npcPoints(ns.places:TrainersFor("Blacksmithing"))
    end
end

-------------------------------------------------------------------------------
-- Skill-up maths
-------------------------------------------------------------------------------

-- Chance of a skill point per craft at `rank`. The colour your profession
-- window showed wins when Flow saw it at this same skill.
local CHANCE = { optimal = 1, medium = 0.6, easy = 0.2, trivial = 0 }
local function chance(prof, step, rank)
    local known, seenRank = ns.recipes:Known(prof)
    local r = known and known[step.recipe]
    if r and seenRank == math.floor(rank) and CHANCE[r.diff] then return CHANCE[r.diff] end
    if rank < step.learn then return 0 end
    if rank < step.yellow then return 1 end
    if rank < step.green then return 0.6 end
    if rank < step.grey then return 0.2 end
    return 0
end

local function matUnits(step)
    local n = 0
    for _, q in pairs(step.mats or {}) do n = n + q end
    return math.max(n, 1)
end

-- Expected crafts per step to go from rank to target: at each point, the
-- step with the most skill per material. When two are as good (Charred Wolf
-- Meat, Roasted Boar Meat), the one whose materials are in your bags wins, so
-- what you already carry gets used before anything is farmed.
-- `have` (optional): item ID -> count in bags; defaults to your bags.
local simulate
function simulate(prof, steps, rank, target, have)
    local crafts, order = {}, {}
    local left = {}
    local function bag(id)
        if left[id] == nil then left[id] = (have and have[id]) or (not have and count(id)) or 0 end
        return left[id]
    end
    local function canMake(s)
        for id, q in pairs(s.mats or {}) do if bag(id) < q then return false end end
        return true
    end
    local guard = 0
    while rank < target and guard < 600 do
        guard = guard + 1
        local best, bestV, bestC, bestHave
        for _, s in ipairs(steps) do
            local c = chance(prof, s, rank)
            local v = c / matUnits(s)
            local h = canMake(s)
            if c > 0 and (not bestV or v > bestV or (v == bestV and h and not bestHave)) then
                best, bestV, bestC, bestHave = s, v, c, h
            end
        end
        if not best then break end
        if not crafts[best] then crafts[best] = 0; order[#order + 1] = best end
        crafts[best] = crafts[best] + 1
        if bestHave then for id, q in pairs(best.mats or {}) do left[id] = bag(id) - q end end
        rank = rank + bestC
    end
    return crafts, order, rank >= target
end

-- Materials that stand in for `id`: dropped materials of other steps that
-- skill up exactly like the step using `id` (same colours, one material each).
-- `id` itself comes first.
function SP.Alternatives(steps, id)
    local mine
    for _, s in ipairs(steps or {}) do
        if s.mats and s.mats[id] then mine = s break end
    end
    local out = { id }
    if not mine then return out end
    local function single(s)
        local only, n = nil, 0
        for mid in pairs(s.mats or {}) do only = mid; n = n + 1 end
        return n == 1 and only or nil
    end
    if not single(mine) then return out end
    for _, s in ipairs(steps) do
        local other = single(s)
        local os = other and src(other)
        if s ~= mine and other and other ~= id and os and os.drops
            and s.learn == mine.learn and s.yellow == mine.yellow and s.green == mine.green and s.grey == mine.grey then
            out[#out + 1] = other
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- Drop rates: how many kills a dropped material really takes. Starts from the
-- guide's rough rate and moves to yours as you loot those mobs.
-------------------------------------------------------------------------------

local PRIOR_KILLS = 5           -- how much the guide's rate counts, in kills
local DEFAULT_RATE = 0.4

function SP.DropRate(id)
    local s = src(id)
    local prior = (s and s.rate) or DEFAULT_RATE
    local d = ns.db.crafting.drops and ns.db.crafting.drops[id]
    local kills, got = d and d.kills or 0, d and d.got or 0
    return (got + prior * PRIOR_KILLS) / (kills + PRIOR_KILLS), kills
end

-- Looting a mob that's listed as dropping a material: one kill for each such
-- material, and one "got" for each that was in the loot. Once per corpse.
local lastCorpse
function SP.RecordLoot(mob, guid, looted)
    if not mob or (guid and guid == lastCorpse) then return end
    lastCorpse = guid
    ns.db.crafting.drops = ns.db.crafting.drops or {}
    local lower = mob:lower()
    for id, s in ns:Each("itemSource") do
        if type(id) == "number" and s.drops then
            for _, n in ipairs(s.drops) do
                if n:lower() == lower then
                    local d = ns.db.crafting.drops[id] or { kills = 0, got = 0 }
                    ns.db.crafting.drops[id] = d
                    d.kills = d.kills + 1
                    if looted[id] or (s.name and looted[s.name:lower()]) then d.got = d.got + 1 end
                    break
                end
            end
        end
    end
end

ns:On("LOOT_OPENED", function() pcall(function()
    if not (UnitExists("target") and UnitIsDead("target")) then return end
    local looted = {}
    for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then looted[id] = true end
        local _, name = GetLootSlotInfo(slot)
        if name then looted[name:lower()] = true end
    end
    SP.RecordLoot(A.Safe and A.Safe(UnitName("target")) or UnitName("target"), UnitGUID("target"), looted)
end) end)

-------------------------------------------------------------------------------
-- Targets: quests first, then planned professions behind your level.
-------------------------------------------------------------------------------

function SP:Targets()
    -- Professions switched off (map list, arrow menu): no profession stops at all,
    -- not even for quests that ask for a skill, nor tools to buy.
    if ns.db.nav.professions == false then return {} end
    local out = {}
    for _, q in ipairs(ns.quests.LogEntries and ns.quests.LogEntries() or {}) do
        for _, o in ipairs(q.objectives or {}) do
            local prof, n = SP.ParseObjective(o.text)
            if prof and not o.finished and (not out[prof] or out[prof].target < n) then
                out[prof] = { target = n, quest = q.title, required = true }
            end
        end
    end
    if ns.db.nav.professions ~= false then
        local want = A.ProfessionTarget(UnitLevel("player"))
        for _, p in ipairs(ns:ProfessionPlan() or {}) do
            local g = ns:Get("profGuide", p.name)
            local rank = A.Skill(p.name)
            -- Gathering behind your level is the errands' optional skill-up stop.
            if g and g.kind == "craft" and rank and rank + 10 < want and not out[p.name] then
                out[p.name] = { target = want, optional = true }
            end
        end
    end
    return out
end

-- Professions whose stops come from here (Goals.lua skips its own skill-up).
local handled = {}
function SP:Handles(prof)
    if handled[prof] then return true end
    local ok, t = pcall(SP.Targets, SP)
    return ok and t[prof] ~= nil or false
end

-------------------------------------------------------------------------------
-- Stops
-------------------------------------------------------------------------------

local function why(t, prof, rank)
    if t.quest then return string.format("%s: %s %d -> %d", t.quest, prof, rank, t.target) end
    return string.format("%s %d -> %d (right for your level)", prof, rank, t.target)
end

local watched = {}  -- item IDs whose counts change the plan

local function planProfession(prof, t, out)
    local g = ns:Get("profGuide", prof)
    local rank, max = A.Skill(prof)
    local label = why(t, prof, rank or 0)
    local weight = t.optional and 1.5 or 1.0
    local base = { title = t.quest or prof, optional = t.optional, weight = weight }
    local function add(goal)
        for k, v in pairs(base) do if goal[k] == nil then goal[k] = v end end
        goal.details = goal.details or {}
        table.insert(goal.details, 1, label)
        out[#out + 1] = goal
    end

    if not rank then
        add({ key = "skillplan:" .. prof, kind = "proftrainer", points = { playerPoint() },
              text = prof .. ": learn it at a trainer first",
              blockedBy = "you don't have " .. prof })
        return
    end
    if rank >= t.target then return end
    if max and max > 0 and t.target > max then
        add({ key = "skillplan:cap:" .. prof, kind = "proftrainer", points = { playerPoint() },
              text = string.format("%s is capped at %d: train the next tier", prof, max),
              blockedBy = string.format("%s capped at %d", prof, max) })
    end
    if not g then
        add({ key = "skillplan:" .. prof, kind = "skill", points = { playerPoint() },
              text = string.format("Raise %s to %d", prof, t.target),
              blockedBy = "Flow has no levelling data for " .. prof .. " yet" })
        return
    end
    handled[prof] = true

    -- Fishing, Herbalism: go to the known spots.
    if g.spots then
        local points = {}
        for _, spot in ipairs(ns.places:SpotsFor(prof)) do
            local p = npcPoints(spot.npcs or {})
            for _, pt in ipairs(p) do points[#points + 1] = pt end
            local o = objectPoints((function()
                local ids = {}
                for _, ob in ipairs(spot.objects or {}) do if rank >= (ob.skill or 1) then ids[#ids + 1] = ob.id end end
                return ids
            end)())
            for _, pt in ipairs(o) do points[#points + 1] = pt end
        end
        add({ key = "skill:" .. prof, kind = "skill", points = points,
              text = string.format("%s: %d -> %d", prof == "Fishing" and "Fish" or prof, rank, t.target),
              blockedBy = #points == 0 and ("no known " .. prof .. " spot on this map") or nil })
        return
    end

    -- Tool in your bags?
    local toolMissing
    if g.tool and not hasTool(prof, g.tool) then
        toolMissing = itemName(g.tool)
        watched[g.tool] = true
        local pts, _, sellers = vendorPoints(g.tool)
        add({ key = "buy:" .. g.tool, kind = "merchant", points = pts, npcs = sellers, cost = SP.Price(g.tool),
              text = "Buy a " .. toolMissing,
              details = { "Needed for " .. prof .. "." },
              blockedBy = #pts == 0 and ("Flow doesn't know who sells a " .. toolMissing .. " (try a trade supplies vendor)") or nil })
    end

    -- Mining also levels from the veins themselves.
    local steps = g.steps or {}
    local crafts, order, reaches = simulate(prof, steps, rank, t.target)
    local need = {}
    for _, s in ipairs(order) do
        local n = math.ceil(crafts[s])
        for id, q in pairs(s.mats or {}) do need[id] = (need[id] or 0) + n * q end
    end

    -- Learn recipes the plan uses that your profession window doesn't list.
    local known = ns.recipes:Known(prof)
    for _, s in ipairs(order) do
        if known and not known[s.recipe] and s.learn <= rank then
            local pts = npcPoints(ns.places:TrainersFor(prof))
            add({ key = "learn:" .. prof .. ":" .. s.recipe, kind = "proftrainer", points = pts, npcs = ns.places:TrainersFor(prof),
                  text = string.format("Learn %s (%s trainer)", s.recipe, prof),
                  blockedBy = #pts == 0 and ("no known " .. prof .. " trainer") or nil })
        end
    end

    -- Craft what you can now.
    for _, s in ipairs(order) do
        local n = math.ceil(crafts[s])
        for id, q in pairs(s.mats or {}) do
            watched[id] = true
            n = math.min(n, math.floor(count(id) / q))
        end
        if n > 0 then
            local pts, anywhere = stationPoints(s.station), false
            if not pts or #pts == 0 then pts, anywhere = { playerPoint() }, true end
            local blocked = toolMissing and ("needs a " .. toolMissing)
                or (known and not known[s.recipe] and ("learn " .. s.recipe .. " first"))
            add({ key = "craft:" .. prof .. ":" .. s.recipe, kind = "craft", points = pts, anywhere = anywhere,
                  weight = 0.5,
                  text = s.recipe:find("^Smelt ") and string.format("%s x%d at a forge", s.recipe, n)
                      or string.format("Make %d x %s", n, s.recipe),
                  details = { anywhere and "You have the materials: do it now, wherever you are."
                                  or ("At the " .. s.station .. " (by the blacksmith).") },
                  blockedBy = blocked or nil })
        end
    end

    -- Materials you still need: smelt what you carry, then gather the rest.
    local raw = {}
    for id, n in pairs(need) do
        local missing = n - count(id)
        local s = src(id)
        if missing > 0 and s and s.smelt then
            local from = s.smelt.from
            watched[from] = true
            local canSmelt = math.min(missing, math.floor(count(from) / s.smelt.n))
            if canSmelt > 0 then
                local mining = A.Skill("Mining")
                local pts = stationPoints("forge") or {}
                add({ key = "smelt:" .. id, kind = "craft", points = pts,
                      text = string.format("Smelt %d %s at a forge", canSmelt, itemName(id)),
                      details = { "Forges stand by the blacksmiths." },
                      blockedBy = (not mining and "needs Mining to smelt")
                          or (mining < s.smelt.skill and string.format("needs Mining %d to smelt", s.smelt.skill))
                          or (#pts == 0 and "no known forge") or nil })
            end
            missing = missing - canSmelt
            if missing > 0 then raw[from] = (raw[from] or 0) + missing * s.smelt.n end
        elseif missing > 0 then
            raw[id] = (raw[id] or 0) + missing
        end
    end

    -- Group by where it comes from: one stop per node type / mob group.
    local nodes = {}
    for id, n in pairs(raw) do
        watched[id] = true
        local s = src(id)
        local name = itemName(id)
        if s and s.gather then
            local key = s.node or s.gather
            local nd = nodes[key] or { src = s, items = {}, count = 0 }
            nodes[key] = nd
            nd.items[#nd.items + 1] = string.format("%d %s", n, name)
            nd.count = math.max(nd.count, math.ceil(n / (s.yield or 1)))
        elseif s and s.drops then
            -- Other materials that level the same (wolf meat or boar meat): any of them will
            -- do, so their mobs count too.
            local ids = SP.Alternatives(steps, id)
            local names, mobs, rates = {}, {}, 0
            for _, aid in ipairs(ids) do
                local as = src(aid)
                names[#names + 1] = itemName(aid)
                for _, m in ipairs(as.drops) do mobs[#mobs + 1] = m end
                rates = rates + SP.DropRate(aid)
            end
            local rate = rates / #ids
            local kills = math.ceil(n / math.max(rate, 0.05))
            local _, seenKills = SP.DropRate(id)
            local pts, onMap = npcPoints(mobs)
            local details = {
                string.format("About %d kills: roughly 1 in %d drops one%s.", kills, math.floor(1 / rate + 0.5),
                    seenKills >= 5 and " (from your own loot)" or ""),
                "Drops from: " .. table.concat(mobs, ", ") .. ".",
            }
            if t.optional then
                table.insert(details, 1, prof .. " isn't needed for a quest: loot these as you quest. No need to stop just for this.")
            end
            add({ key = "farm:" .. id, kind = "kill", points = pts, npcs = mobs, area = true,
                  weight = t.optional and 3 or nil,   -- optional: only when the mobs are on your way
                  -- Progress like a quest objective: what you carry / what the plan uses.
                  text = (function()
                      local have = 0
                      for _, aid in ipairs(ids) do watched[aid] = true; have = have + count(aid) end
                      return string.format("Loot %s %d/%d (~%d kills)", table.concat(names, " or "), have, have + n, kills)
                  end)(),
                  details = details,
                  blockedBy = #pts == 0 and ("no known " .. name .. " drops nearby") or nil })
        elseif s and s.vendor then
            local pts, _, sellers = vendorPoints(id)
            add({ key = "buy:" .. id, kind = "merchant", points = pts, npcs = sellers,
                  cost = SP.Price(id) and SP.Price(id) * n or nil,
                  text = string.format("Buy %d %s", n, name),
                  blockedBy = #pts == 0 and ("Flow doesn't know who sells " .. name) or nil })
        else
            add({ key = "need:" .. id, kind = "collect", points = { playerPoint() },
                  text = string.format("Get %d %s", n, name),
                  blockedBy = "Flow doesn't know where " .. name .. " comes from (Auction House?)" })
        end
    end
    for node, nd in pairs(nodes) do
        local s = nd.src
        local gr = A.Skill(s.gather)
        local pts, onMap = objectPoints(s.objects)
        local blocked
        if not gr then blocked = "needs " .. s.gather .. " (or buy them)"
        elseif gr < (s.skill or 1) then blocked = string.format("needs %s %d", s.gather, s.skill)
        elseif #pts == 0 then blocked = "no known " .. node .. " in Flow's data"
        end
        if s.gather == "Mining" and not hasTool("Mining", 2901) and not blocked then blocked = "needs a Mining Pick" end
        handled[s.gather] = true
        add({ key = "gather:" .. node, kind = "gather", points = pts,
              text = string.format("%s %s (about %d) for %s", s.gather == "Mining" and "Mine" or "Gather",
                  node, nd.count, table.concat(nd.items, ", ")),
              details = { onMap and "Nearest ones on this map; the route picks the ones on your way."
                              or "None on this map: these are elsewhere." },
              blockedBy = blocked })
    end

    -- Gathering profession with nodes (Mining): the veins themselves skill up.
    if g.nodes then
        local best
        for _, nd in ipairs(g.nodes) do
            if rank >= nd.learn and rank < nd.grey then best = nd end
        end
        if best and not nodes[src(best.item).node] then
            local s = src(best.item)
            local c = rank < best.yellow and 1 or (rank < best.green and 0.6 or 0.2)
            local pts, onMap = objectPoints(s.objects)
            add({ key = "gather:" .. s.node, kind = "gather", points = pts,
                  text = string.format("Mine %s (about %d) for skill", s.node, math.ceil((t.target - rank) / c)),
                  details = { "Smelting the ore at a forge raises Mining too." },
                  blockedBy = (not hasTool("Mining", 2901) and "needs a Mining Pick")
                      or (#pts == 0 and ("no known " .. s.node .. " in Flow's data")) or nil })
        end
    end

    if not reaches then
        add({ key = "skillplan:more:" .. prof, kind = "skill", points = { playerPoint() },
              text = string.format("%s past %d: open the %s window so Flow learns your recipes", prof, rank, prof),
              blockedBy = "Flow's guide data runs out here" })
    end
end

ns:Register("navGoal", "skillplan", {
    collect = function()
        wipe(handled)
        wipe(watched)
        local out = {}
        for prof, t in pairs(SP:Targets()) do
            local ok, err = pcall(planProfession, prof, t, out)
            if not ok then ns:Log("skillplan", prof .. ": " .. tostring(err)) end
        end
        -- Drop stops with no place at all, unless blocked (those are listed, not routed).
        local kept, seen = {}, {}
        for _, g in ipairs(out) do
            g.points = g.points or {}
            if seen[g.key] then
                -- Two professions want the same stop (e.g. Copper Veins): one stop, both reasons.
                for _, d in ipairs(g.details or {}) do table.insert(seen[g.key].details, d) end
            elseif #g.points > 0 or g.blockedBy then
                kept[#kept + 1] = g; seen[g.key] = g
            end
        end
        SP.lastStops = kept
        return kept
    end,
})

-- Re-plan when an item the plan counts changes (ore mined, bar smelted...).
local lastCounts = {}
ns:On("BAG_UPDATE_DELAYED", function()
    local changed = false
    for id in pairs(watched) do
        local c = count(id)
        if lastCounts[id] ~= c then lastCounts[id] = c; changed = true end
    end
    if changed and ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect() end
end)
ns:On("SKILL_LINES_CHANGED", function() if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect() end end)

-- /flow prof plan: what the planner thinks, profession by profession.
function SP:Explain()
    local any = false
    for prof, t in pairs(SP:Targets()) do
        any = true
        local rank = A.Skill(prof)
        ns:Print(string.format("%s %s -> %d%s", prof, tostring(rank), t.target, t.quest and (" (" .. t.quest .. ")") or ""))
        local g = ns:Get("profGuide", prof)
        if g and g.steps and rank then
            local crafts, order = simulate(prof, g.steps, rank, t.target)
            for _, s in ipairs(order) do
                local mats = {}
                for id, q in pairs(s.mats or {}) do
                    mats[#mats + 1] = string.format("%d %s (have %d)", math.ceil(crafts[s]) * q, itemName(id), count(id))
                end
                print(string.format("  %d x %s: %s", math.ceil(crafts[s]), s.recipe, table.concat(mats, ", ")))
            end
        end
    end
    if not any then ns:Print("no profession needs raising right now.") end
    for _, g in ipairs(SP.lastStops or {}) do
        print(string.format("  stop: %s%s", g.text or g.key, g.blockedBy and ("  [blocked: " .. g.blockedBy .. "]") or ""))
    end
end

SP._simulate = simulate  -- for /flow test
