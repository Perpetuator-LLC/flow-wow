-------------------------------------------------------------------------------
-- Flow - Quests/QuestBuy.lua
-- A quest's materials you could just buy (0.35.340).
--
-- "Gathering the Cure has me collect 5 Earthroot. Can't I just buy those at
-- the AH? It's telling me to go buy wool to do my first aid, so I figured it
-- would tell me to do this too." A collect objective was only ever a place to
-- farm. When Flow has seen the item for sale at the auction house, it can be
-- bought, so that's a step too: at the auctioneer, with what it should cost.
--
-- It's an optional step (the planner keeps one only when it's close to your
-- way: you're passing an auctioneer anyway, for wool, to sell), and it waits
-- until you can pay. Whichever you reach first settles it: buy them and the
-- farming step goes; farm them and this one does.
--
-- A price seen at the auction house is the test that it can be bought there:
-- a soulbound quest drop never has one.
-------------------------------------------------------------------------------

local _, ns = ...

local QB = {}
ns.questBuy = QB

function QB.On() return not (ns.db and ns.db.nav and ns.db.nav.questBuy == false) end

-- Pure: the steps.
--   quests: { { id, title, level, objectives = { { i, itemId, name, left } } } }
--   priceOf(itemId) -> copper each, or nil; points: where an auctioneer stands
--   text(n, name, cost) -> the step's words; coin(copper) -> "12s 40c"
function QB.Steps(quests, priceOf, points, text, coin)
    local out = {}
    if not points or #points == 0 then return out end
    for _, q in ipairs(quests or {}) do
        for _, o in ipairs(q.objectives or {}) do
            local price = o.itemId and priceOf(o.itemId)
            local left = o.left or 0
            if type(price) == "number" and price > 0 and left > 0 then
                local cost = math.ceil(left * price)
                local name = o.name or "what it asks for"
                out[#out + 1] = {
                    key = "qbuy:" .. q.id .. ":" .. o.i, kind = "buy", optional = true, weight = 1.5,
                    points = points, cost = cost, title = q.title, level = q.level, item = o.itemId,
                    text = text(left, name, cost) .. (q.title and (": " .. q.title) or ""),
                    details = {
                        "Quest: " .. (q.title or "?"),
                        string.format("Instead of collecting them: %s was about %s each at the auction house when Flow last looked.", name, coin(math.floor(price))),
                        "Optional: it's on your route only while an auctioneer is close to your way, and once you can pay. "
                            .. "Collect them first and this step goes; buy them and the collecting step goes.",
                        "The price there changes: look before you buy.",
                    },
                }
            end
        end
    end
    return out
end

-- Pure: the line a collect step's details get, or nil with no price.
function QB.Line(name, left, price, coin)
    if type(price) ~= "number" or price <= 0 or not left or left <= 0 then return nil end
    return string.format("Or buy them: %s was about %s each at the auction house when Flow last looked (about %s for the %d you still need).",
        name or "it", coin(math.floor(price)), coin(math.ceil(left * price)), left)
end
function QB.LineFor(itemId, name, left)
    local AH = ns.auction
    if not (QB.On() and AH and AH.Price and itemId) then return nil end
    local ok, price = pcall(AH.Price, AH, itemId)
    return QB.Line(name, left, ok and price or nil, AH.Money or ns.Money)
end

-- How many of objective i of a quest in your log are still to get (nil: the
-- game doesn't say, or it's done).
function QB.LeftOf(questId, i)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
    local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questId)
    local o = ok and type(objs) == "table" and objs[i]
    if not o then return nil end
    local have, need = tonumber(ns.api.Safe(o.numFulfilled)), tonumber(ns.api.Safe(o.numRequired))
    if not need then return nil end
    local left = math.max(0, need - (have or 0))
    return left > 0 and left or nil
end

-- Your log's item objectives that aren't done: what's still to get of each.
function QB.Log()
    local Q, out = ns.quests, {}
    if not (Q and Q.LogIds and Q.QuestieGet and C_QuestLog and C_QuestLog.GetQuestObjectives) then return out end
    for id in pairs(Q:LogIds() or {}) do
        local raw = Q:QuestieGet("GetQuest", id)
        local okO, objs = pcall(C_QuestLog.GetQuestObjectives, id)
        if raw and raw.ObjectiveData and okO and type(objs) == "table" then
            local q = { id = id, title = raw.name, level = raw.level, objectives = {} }
            for i, o in ipairs(objs) do
                local od = raw.ObjectiveData[i]
                local done = ns.rotation and ns.rotation.Yes and ns.rotation.Yes(o.finished, false) or false
                local have, need = tonumber(ns.api.Safe(o.numFulfilled)), tonumber(ns.api.Safe(o.numRequired))
                if od and od.Type == "item" and od.Id and not done and need then
                    local item = Q:QuestieGet("GetItem", od.Id)
                    q.objectives[#q.objectives + 1] = { i = i, itemId = od.Id, name = item and item.name, left = math.max(0, need - (have or 0)) }
                end
            end
            if #q.objectives > 0 then out[#out + 1] = q end
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

ns:Register("navGoal", "questbuy", {
    collect = function()
        local AH, SP = ns.auction, ns.skillPlan
        if not (QB.On() and AH and AH.Price and SP and SP.AuctionPoints and SP.AuctionText) then return nil end
        local okP, points = pcall(SP.AuctionPoints)
        if not okP or type(points) ~= "table" or #points == 0 then return nil end
        local money = AH.Money or ns.Money
        return QB.Steps(QB.Log(), function(id) return (AH:Price(id)) end, points,
            function(n, name, cost) return SP.AuctionText(n, name, cost, money) end, money)
    end,
})

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "route",
        label = "Offer the auction house for a quest's materials",
        note = "(when you pass an auctioneer)",
        tip = "When a quest asks you to collect something Flow has seen for sale at the auction house (5 Earthroot), buying it is a step too: "
            .. "at an auctioneer, with what it should cost, only while one is close to your way and you can pay. Off: only where to collect it.",
        get = function() return QB.On() end,
        set = function(on) ns.db.nav.questBuy = on and true or false end,
    })
end
