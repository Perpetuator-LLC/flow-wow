-- Hearthstone, as part of the levelling route (no pop-ups). When you're in a
-- zone with a known inn and your hearthstone is set somewhere else, the route
-- gets a stop: "Set hearthstone: Innkeeper Farley (Goldshire)". Hide it like
-- any stop (right-click it on the map) if you don't want it.
-- Innkeepers are data (registry kind "innkeeper"); more zones can be added
-- without touching this file. The NPC ID is checked against the name.
--
-- Which inn (0.35.178, "should you have told me to set my hearthstone ...
-- right when I got into Thunder Bluff? ... hearth set to Bloodhoof Village"):
--   * a city beats a village: in Thunder Bluff with your home in Bloodhoof
--     Village, the stop is offered (H.Offer);
--   * a village near your city home isn't offered back (no flip-flop);
--   * a stop a travel spell away (Teleport: Moonglade) waits for the "Set
--     hearthstone" stop where you are (H.BeforeTrips): home first, then go.
-- Until 0.35.178 only Alliance inns were listed, so a Horde character never
-- got the stop at all.

local _, ns = ...
local H = {}
ns.hearth = H

-- Levelling towns and cities (classic names and IDs). city: a capital.
-- also: other names the game may give for the same home (a city's district).
-- A wrong name here only means no stop is offered: Flow also learns the
-- game's own wording when you set your home at an innkeeper it knows.
for key, inn in pairs({
    -- Alliance
    goldshire  = { name = "Innkeeper Farley", id = 295, town = "Goldshire", inn = "Lion's Pride Inn", zone = "Elwynn Forest" },
    sentinel   = { name = "Innkeeper Heather", id = 8931, town = "Sentinel Hill", inn = "Sentinel Hill Inn", zone = "Westfall" },
    thelsamar  = { name = "Innkeeper Hearthstove", id = 6734, town = "Thelsamar", inn = "Stoutlager Inn", zone = "Loch Modan" },
    lakeshire  = { name = "Innkeeper Brianna", id = 6727, town = "Lakeshire", inn = "Lakeshire Inn", zone = "Redridge Mountains" },
    darkshire  = { name = "Innkeeper Trelayne", id = 6790, town = "Darkshire", inn = "Scarlet Raven Tavern", zone = "Duskwood" },
    stormwind  = { name = "Innkeeper Allison", id = 6740, town = "Stormwind City", inn = "The Gilded Rose", zone = "Stormwind City",
                   city = true, also = { "Trade District" } },
    kharanos   = { name = "Innkeeper Belm", id = 1247, town = "Kharanos", inn = "Thunderbrew Distillery", zone = "Dun Morogh" },
    ironforge  = { name = "Innkeeper Firebrew", id = 5111, town = "Ironforge", inn = "The Stonefire Tavern", zone = "Ironforge",
                   city = true, also = { "The Commons" } },
    menethil   = { name = "Innkeeper Helbrek", id = 1464, town = "Menethil Harbor", inn = "Deepwater Tavern", zone = "Wetlands" },
    dolanaar   = { name = "Innkeeper Keldamyr", id = 6736, town = "Dolanaar", zone = "Teldrassil" },
    darnassus  = { name = "Innkeeper Saelienne", id = 6735, town = "Darnassus", zone = "Darnassus",
                   city = true, also = { "Craftsmen's Terrace" } },
    auberdine  = { name = "Innkeeper Shaussiy", id = 6737, town = "Auberdine", zone = "Darkshore" },
    astranaar  = { name = "Innkeeper Kimlya", id = 6738, town = "Astranaar", zone = "Ashenvale" },
    -- Horde
    bloodhoof    = { name = "Innkeeper Kauth", id = 6747, town = "Bloodhoof Village", zone = "Mulgore" },
    thunderbluff = { name = "Innkeeper Pala", id = 6746, town = "Thunder Bluff", zone = "Thunder Bluff", city = true },
    razorhill    = { name = "Innkeeper Grosk", id = 6928, town = "Razor Hill", zone = "Durotar" },
    orgrimmar    = { name = "Innkeeper Gryshka", id = 6929, town = "Orgrimmar", zone = "Orgrimmar",
                     city = true, also = { "Valley of Strength" } },
    crossroads   = { name = "Innkeeper Boorand Plainswind", id = 3934, town = "The Crossroads", zone = "The Barrens" },
    taurajo      = { name = "Innkeeper Byula", id = 7714, town = "Camp Taurajo", zone = "The Barrens" },
    brill        = { name = "Innkeeper Renee", id = 5688, town = "Brill", inn = "Gallows' End Tavern", zone = "Tirisfal Glades" },
    undercity    = { name = "Innkeeper Norman", id = 6741, town = "Undercity", zone = "Undercity",
                     city = true, also = { "The Trade Quarter" } },
    sepulcher    = { name = "Innkeeper Bates", id = 6739, town = "The Sepulcher", zone = "Silverpine Forest" },
    sunrock      = { name = "Innkeeper Jayka", id = 7731, town = "Sun Rock Retreat", zone = "Stonetalon Mountains" },
}) do ns:Register("innkeeper", key, inn) end

do
    local ids = {}
    for _, inn in ns:Each("innkeeper") do if inn.id then ids[inn.name] = inn.id end end
    ns:Register("npcIds", "innkeepers", ids)
end

-- Is the hearthstone already set at this inn? The game may report the town
-- ("Goldshire"), the inn ("Lion's Pride Inn") or a city's district ("Valley
-- of Strength"); any counts, and so does the wording Flow saw the game use
-- when you set your home at this innkeeper (H.Learn).
function H:BoundTo(inn, bind)
    if not bind then return false end
    local b = bind:lower()
    local learned = ns.db and ns.db.hearth and ns.db.hearth.binds
    if learned and learned[b] then return learned[b] == inn.name end
    local names = {}
    if inn.town then names[#names + 1] = inn.town end
    if inn.inn then names[#names + 1] = inn.inn end
    for _, a in ipairs(inn.also or {}) do names[#names + 1] = a end
    for _, name in ipairs(names) do
        local n = name:lower()
        if b == n or b:find(n, 1, true) or n:find(b, 1, true) then return true end
    end
    return false
end

-- The inn your hearthstone is set at, when it's one Flow knows: key, inn.
function H:Home(bind)
    bind = bind or (GetBindLocation and GetBindLocation())
    if not bind then return nil end
    for key, inn in ns:Each("innkeeper") do
        if H:BoundTo(inn, bind) then return key, inn end
    end
    return nil
end

-- You set your home while talking to an innkeeper Flow knows: remember what
-- the game calls that home (it may name a district, or the inn).
function H.Learn(bind, npcName)
    if not (bind and npcName and ns.db and ns.db.hearth) then return false end
    for _, inn in ns:Each("innkeeper") do
        if inn.name == npcName then
            ns.db.hearth.binds = ns.db.hearth.binds or {}
            ns.db.hearth.binds[bind:lower()] = inn.name
            return true
        end
    end
    return false
end

-- Pure: offer "Set hearthstone" at the inn `here`? home: the inn you're
-- bound to (nil: not one Flow knows); yards: between the two (nil: unknown).
H.CITY_REACH = 1500   -- a city home this close to a village's inn: keep the city
function H.Offer(here, home, yards)
    if not here then return false end
    if not home then return true end                       -- as before: your home isn't a known inn
    if home == here or home.zone == here.zone then return false end   -- bound in this zone already
    if here.city and not home.city then return true end    -- a city beats a village
    if home.city and not here.city and (not yards or yards <= H.CITY_REACH) then return false end
    return true                                            -- another zone's inn, your home far away
end

-- A stop that's a travel spell away waits for the "Set hearthstone" stop,
-- when the route has one: set your home before you're cast far from it.
--   isTrip(point) -> true when the spot is a cast away from where you are
-- -> how many stops now wait for it
function H.BeforeTrips(goals, isTrip)
    local key
    for _, g in ipairs(goals) do
        if type(g.key) == "string" and g.key:find("^hearth:") then key = g.key end
    end
    if not key then return 0 end
    local n = 0
    for _, g in ipairs(goals) do
        local pt = g.points and g.points[1]
        if g.key ~= key and pt and isTrip(pt) then
            local has = false
            for _, d in ipairs(g.deps or {}) do if d == key then has = true end end
            if not has then
                -- (a list of its own: a goal's deps may be shared with others)
                local deps = {}
                for _, d in ipairs(g.deps or {}) do deps[#deps + 1] = d end
                deps[#deps + 1] = key
                g.deps = deps
            end
            n = n + 1
        end
    end
    return n
end

-- Would the hearthstone get you there sooner? An estimate, never an action:
-- Flow does not use the hearthstone for you.
--   straight: the distance at your speed
--   hearthstone: what's left of its cooldown + the cast + the loading screen
--                + the run from your inn to the same place
-- Anything unknown (which inn, where it is, the cooldown) means no estimate.
H.ITEM = 6948
H.CAST, H.LOAD = 10, 10          -- seconds: the cast, and a guess at the loading screen
H.MIN_SAVE, H.MIN_SHARE = 120, 0.25   -- say it only when it saves 2 minutes and a quarter of the trip

function H.Compare(directYd, bindYd, cooldownLeft, speed)
    if not (type(directYd) == "number" and type(bindYd) == "number" and type(cooldownLeft) == "number"
        and type(speed) == "number" and speed > 0) then return nil end
    local direct = directYd / speed
    local hearth = cooldownLeft + H.CAST + H.LOAD + bindYd / speed
    local saving = direct - hearth
    return { direct = direct, hearth = hearth, saving = saving, wait = cooldownLeft,
             better = saving >= H.MIN_SAVE and saving >= direct * H.MIN_SHARE }
end

local function span(s)
    if s >= 90 then return string.format("%d min", math.floor(s / 60 + 0.5)) end
    return string.format("%d s", math.floor(s + 0.5))
end

-- The line to show, or nil when the hearthstone isn't clearly quicker.
function H.AdviceText(c, bind)
    if not (c and c.better) then return nil end
    return string.format("Estimate: hearthstone to %s, then run, is about %s quicker (%s against %s%s). Your call: Flow never uses it for you.",
        bind or "your inn", span(c.saving), span(c.hearth), span(c.direct),
        c.wait > 0 and (", counting " .. span(c.wait) .. " left on its cooldown") or "")
end

-- Where your hearthstone goes, as a point: only when it's an inn Flow knows.
function H:BindPoint()
    local bind = GetBindLocation and GetBindLocation()
    if not bind then return nil end
    for _, inn in ns:Each("innkeeper") do
        if H:BoundTo(inn, bind) then
            local p = ns.places and ns.places:Points(inn.name)[1]
            if p and p.map then return p, bind end
        end
    end
    return nil
end

-- Seconds left on the hearthstone's cooldown; nil when you carry none or the game won't say.
function H:CooldownLeft()
    -- (ns.api.Count: GetItemCount is gone as a global on Forever, so the bare
    -- call made every estimate "no hearthstone".)
    if ns.api.Count(H.ITEM) <= 0 then return nil end
    local get = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not get then return nil end
    local ok, start, duration = pcall(get, H.ITEM)
    local A = ns.api
    start, duration = ok and A.Safe(start) or nil, ok and A.Safe(duration) or nil
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    if start == 0 or duration == 0 then return 0 end
    return math.max(0, start + duration - GetTime())
end

-- The estimate line for a place directYd away, or nil.
function H:Advice(map, x, y, directYd)
    local ok, text = pcall(function()
        local nav = ns.nav
        local p, bind = H:BindPoint()
        if not (nav and p) then return nil end
        local c1, ax, ay = nav:ToWorld(p.map, p.x, p.y)
        local c2, bx, by = nav:ToWorld(map, x, y)
        if not (c1 and c2 and c1 == c2 and ax and bx) then return nil end
        local bindYd = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
        return H.AdviceText(H.Compare(directYd, bindYd, H:CooldownLeft(), nav.RUN_SPEED or 7), bind)
    end)
    return ok and text or nil
end

ns:Register("navGoal", "hearth", {
    collect = function()
        if ns.db.hearth and ns.db.hearth.off then return nil end
        local zone = GetZoneText and GetZoneText()
        local bind = GetBindLocation and GetBindLocation()
        if not zone or not bind then return nil end
        -- The inn of this zone (the nearest, where a zone has two).
        local here, hereKey, herePts, hereD
        for key, inn in ns:Each("innkeeper") do
            if inn.zone == zone then
                local points = ns.places:Points(inn.name)
                if #points > 0 then
                    local d = H.YardsFromYou(points[1]) or 0
                    if not here or d < hereD then here, hereKey, herePts, hereD = inn, key, points, d end
                end
            end
        end
        if not here or H:BoundTo(here, bind) then return nil end
        local _, home = H:Home(bind)
        if not H.Offer(here, home, home and H.Between(home, herePts[1]) or nil) then return nil end
        return { {
            key = "hearth:" .. hereKey, weight = 1.1, points = herePts,
            title = "Set hearthstone",
            text = string.format("Set hearthstone: %s (%s)", here.name, here.town),
            details = { string.format("Your hearthstone is set to %s. %s Set it here:", bind,
                            here.city and (here.town .. " is a city: your trainers and the bank are here, and it's the place to come back to from a far trip.")
                                or ("Questing around " .. here.town .. "?")),
                        "talk to the innkeeper and choose \"Make this inn your home\".",
                        "Right-click this stop on the map to hide it." },
        } }
    end,
})

-- Yards from you to a map spot, and between an inn and a map spot; nil when
-- they can't be measured (another continent, no position).
local function worldOf(pt)
    local nav = ns.nav
    if not (nav and nav.ToWorld and pt and pt.map) then return nil end
    local ok, cont, wx, wy = pcall(nav.ToWorld, nav, pt.map, pt.x, pt.y)
    if ok and cont and wx then return cont, wx, wy end
    return nil
end
function H.YardsFromYou(pt)
    local p = ns.nav and ns.nav.PlayerPos and ns.nav:PlayerPos()
    local cont, wx, wy = worldOf(pt)
    if not (p and p.wx and cont and p.cont == cont) then return nil end
    return math.sqrt((p.wx - wx) ^ 2 + (p.wy - wy) ^ 2)
end
function H.Between(inn, pt)
    local a = ns.places and ns.places:Points(inn.name)[1]
    local c1, ax, ay = worldOf(a)
    local c2, bx, by = worldOf(pt)
    if not (c1 and c2 and c1 == c2) then return nil end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- One line for /flow nav why and the diagnostics: where your home is and
-- whether the stone is ready.
function H.Line()
    local bind = GetBindLocation and GetBindLocation()
    local _, home = H:Home(bind)
    local left = H:CooldownLeft()
    return string.format("hearthstone: set to %s (%s); %s", tostring(bind),
        home and (home.name .. (home.city and ", a city" or "")) or "not an inn Flow knows",
        left == nil and "cooldown unknown" or (left <= 0 and "ready" or string.format("ready in %d min", math.ceil(left / 60))))
end

ns:OnLoad(function(saved) saved.hearth = saved.hearth or {} end)

-- Setting it removes the stop. (The innkeeper you're talking to tells Flow
-- what the game calls this home.)
ns:On("HEARTHSTONE_BOUND", function()
    local bind = GetBindLocation and GetBindLocation()
    ns:Print("hearthstone set to " .. tostring(bind))
    local who = UnitName and (UnitName("npc") or UnitName("target"))
    if type(who) == "string" then pcall(H.Learn, bind, who) end
    if ns.nav then ns.nav:Collect() end
end)

ns.commands.hearth = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.hearth.off = (arg == "off")
        if ns.nav then ns.nav:Collect() end
        ns:Print("hearthstone stops on the route " .. arg)
    else
        ns:Print("hearthstone: " .. tostring(GetBindLocation()) .. ". Route stops "
            .. (ns.db.hearth.off and "off" or "on") .. ". /flow hearth on|off")
    end
end
