-- Hearthstone, as part of the levelling route (no pop-ups). When you're in a
-- zone with a known inn and your hearthstone is set somewhere else, the route
-- gets a step: "Set hearthstone: Innkeeper Farley (Goldshire)". Hide it like
-- any step (right-click it on the map) if you don't want it.
-- Innkeepers are data (registry kind "innkeeper"); more zones can be added
-- without touching this file. The NPC ID is checked against the name.
--
-- Which inn (0.35.178, "should you have told me to set my hearthstone ...
-- right when I got into Thunder Bluff? ... hearth set to Bloodhoof Village"):
--   * a city beats a village: in Thunder Bluff with your home in Bloodhoof
--     Village, the step is offered (H.Offer);
--   * a village near your city home isn't offered back (no flip-flop);
--   * a step a travel spell away (Teleport: Moonglade) waits for the "Set
--     hearthstone" step where you are (H.BeforeTrips): home first, then go.
-- Until 0.35.178 only Alliance inns were listed, so a Horde character never
-- got the step at all.

local _, ns = ...
local H = {}
ns.hearth = H

-- Levelling towns and cities (classic names and IDs). city: a capital.
-- also: other names the game may give for the same home (a city's district).
-- A wrong name here only means no step is offered: Flow also learns the
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
-- work: { here = n, home = n }: how many of your quests' steps (objectives
-- and turn-ins in your log) are nearer this inn, and nearer your home. With
-- more of them round your home, it stays: "I'm questing in the Crossroads
-- and just came to Orgrimmar for a dungeon; it tells me to set my hearth
-- here and I don't think I should" (0.35.212). A city doesn't beat that.
-- picked (0.35.379): is this inn's zone one of your questing zones (the
-- Flow Router's Zones)? false: you're passing through, so no step. "Undercity
-- is turned off in my zones ... I'm just coming through for Trial of the Sea
-- Lion, and one of my shortcuts is to hearth back to the Crossroads."
-- accepted (0.35.392): have you accepted a quest by this inn? false: no step
-- (you're not questing from here). true also lets a second inn of your
-- home's zone be offered, when more of your quests are round it.
function H.Offer(here, home, yards, work, picked, accepted)
    if not here then return false end
    if picked == false or accepted == false then return false end
    if not home then return true end                       -- as before: your home isn't a known inn
    if home == here then return false end
    if home.zone == here.zone then                         -- bound in this zone already
        return accepted == true and work ~= nil and (work.here or 0) > (work.home or 0)
    end
    if work and (work.home or 0) > (work.here or 0) then return false end   -- your quests are round your home
    if here.city and not home.city then return true end    -- a city beats a village
    if home.city and not here.city and (not yards or yards <= H.CITY_REACH) then return false end
    return true                                            -- another zone's inn, your home far away
end

-- Pure: of these steps, how many are nearer each inn. dist(inn, point) ->
-- yards or nil (can't tell: counted for neither).
function H.Nearer(goals, here, home, dist)
    local out = { here = 0, home = 0 }
    for _, g in ipairs(goals or {}) do
        local pt = type(g.key) == "string" and g.key:find("^%d+:") and g.points and g.points[1]
        if pt then
            local a, b = dist(here, pt), dist(home, pt)
            if a and b then
                if a < b then out.here = out.here + 1 elseif b < a then out.home = out.home + 1 end
            end
        end
    end
    return out
end
-- Your quests' steps right now (the route's and the ones not on this plan).
function H.Work(here, home)
    local N = ns.nav
    if not (N and N.Goals) then return nil end
    local ok, goals = pcall(N.Goals, N)
    if not ok or type(goals) ~= "table" then return nil end
    return H.Nearer(goals, here, home, function(inn, pt) return H.Between(inn, pt) end)
end

-- A step that's a travel spell away waits for the "Set hearthstone" step,
-- when the route has one: set your home before you're cast far from it.
--   isTrip(point) -> true when the spot is a cast away from where you are
-- -> how many steps now wait for it
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

-- For the arrow itself (0.35.198): how many seconds the hearthstone saves on
-- the way to a spot, when it's clearly the quicker way (H.Compare), and
-- where it's set; nil otherwise. tools\route-check.ps1 found a 2,100 yd walk
-- back to Thunder Bluff with the stone set there and ready: the estimate was
-- only in the arrow's panel, which you have to open to see.
function H:Saves(map, x, y, directYd)
    local ok, saving, bind = pcall(function()
        local nav = ns.nav
        local p, where = H:BindPoint()
        if not (nav and p) then return nil end
        local c1, ax, ay = nav:ToWorld(p.map, p.x, p.y)
        local c2, bx, by = nav:ToWorld(map, x, y)
        if not (c1 and c2 and c1 == c2 and ax and bx) then return nil end
        local c = H.Compare(directYd, math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2), H:CooldownLeft(), nav.RUN_SPEED or 7)
        if c and c.better then return c.saving, where end
        return nil
    end)
    if not ok then return nil end
    return saving, bind
end
-- Pure: the few words beside the arrow.
function H.Cue(saving, bind)
    if not saving then return nil end
    return string.format("Hearthstone (%s) is about %s quicker", bind or "your inn", span(saving))
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
        H.why = nil
        if not here or H:BoundTo(here, bind) then return nil end
        local _, home = H:Home(bind)
        local N = ns.nav
        local zoneId = N and N.ZoneOf and herePts[1].map and N.ZoneOf(herePts[1].map) or nil
        local picked = true
        if zoneId and N.ZoneOn then picked = N.ZoneOn(zoneId) and true or false end
        if not picked then H.why = string.format("no step at %s: %s isn't one of your zones (Flow Router, Zones)", here.name, tostring(here.zone)) end
        local accepted = H.AcceptedAt(hereKey)
        if picked and not accepted then H.why = string.format("no step at %s: you haven't accepted a quest by it", here.name) end
        if not H.Offer(here, home, home and H.Between(home, herePts[1]) or nil, home and H.Work(here, home) or nil, picked, accepted) then return nil end
        return { {
            key = "hearth:" .. hereKey, weight = 1.1, points = herePts,
            title = "Set hearthstone",
            text = string.format("Set hearthstone: %s (%s)", here.name, here.town),
            details = { string.format("Your hearthstone is set to %s. %s Set it here:", bind,
                            here.city and (here.town .. " is a city: your trainers and the bank are here, and it's the place to come back to from a far trip.")
                                or ("You've taken quests around " .. here.town .. ".")),
                        "talk to the innkeeper and choose \"Make this inn your home\".",
                        "Right-click this step on the map to hide it." },
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
    return string.format("hearthstone: set to %s (%s); %s%s", tostring(bind),
        home and (home.name .. (home.city and ", a city" or "")) or "not an inn Flow knows",
        left == nil and "cooldown unknown" or (left <= 0 and "ready" or string.format("ready in %d min", math.ceil(left / 60))),
        H.why and ("; " .. H.why) or "")
end

ns:OnLoad(function(saved)
    saved.hearth = saved.hearth or {}
    saved.hearth.accepted = saved.hearth.accepted or {}
end)

-------------------------------------------------------------------------------
-- Accepting quests by an inn is what asks for the step (0.35.392)
--
-- "I started doing quests in Camp Taurajo, and it didn't tell me to make my
-- hearthstone there ... when a user starts accepting quests in a new area,
-- that becomes the central point, and that's our trigger. Otherwise it can
-- be really annoying, telling them to set their hearthstone in all these
-- random locations."
--   * The step is only offered at an inn you've accepted a quest near
--     (within H.NEAR yards), remembered for this character.
--   * That also lets it be offered at a second inn of the zone your home is
--     in (Camp Taurajo with your home at the Crossroads), when more of your
--     quests' steps are round it than round your home.
-------------------------------------------------------------------------------
H.NEAR = 500
-- Pure: the inn a quest was accepted by: the nearest within reach, or nil.
--   inns: { { key, yards } } (yards: from you to it, nil: can't tell)
function H.NearestInn(inns, reach)
    local best
    for _, i in ipairs(inns or {}) do
        if i.yards and i.yards <= (reach or H.NEAR) and (not best or i.yards < best.yards) then best = i end
    end
    return best and best.key or nil
end
function H.AcceptedAt(key)
    local a = ns.db and ns.db.hearth and ns.db.hearth.accepted
    return key ~= nil and a ~= nil and (a[key] or 0) > 0
end
-- You accepted a quest: noted for the inn you're by. -> its key, or nil
function H.NoteAccept()
    if not (ns.db and ns.db.hearth and ns.places) then return nil end
    local inns = {}
    for key, inn in ns:Each("innkeeper") do
        local pts = ns.places:Points(inn.name)
        if pts and pts[1] then inns[#inns + 1] = { key = key, yards = H.YardsFromYou(pts[1]) } end
    end
    local key = H.NearestInn(inns)
    if not key then return nil end
    ns.db.hearth.accepted = ns.db.hearth.accepted or {}
    ns.db.hearth.accepted[key] = (ns.db.hearth.accepted[key] or 0) + 1
    if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("a quest accepted by an inn") end
    return key
end
ns:On("QUEST_ACCEPTED", function()
    if C_Timer and C_Timer.After then C_Timer.After(0.5, function() pcall(H.NoteAccept) end) end
end)
ns:PerCharacter("hearth.accepted")

-- Setting it removes the step. (The innkeeper you're talking to tells Flow
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
        ns:Print("hearthstone steps on the route " .. arg)
    else
        ns:Print("hearthstone: " .. tostring(GetBindLocation()) .. ". Route steps "
            .. (ns.db.hearth.off and "off" or "on") .. ". /flow hearth on|off")
    end
end
