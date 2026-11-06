-- Hearthstone, as part of the levelling route (no pop-ups). When you're in a
-- zone with a known inn and your hearthstone is set somewhere else, the route
-- gets a stop: "Set hearthstone: Innkeeper Farley (Goldshire)". Hide it like
-- any stop (right-click it on the map) if you don't want it.
-- Innkeepers are data (registry kind "innkeeper"); more zones can be added
-- without touching this file. The NPC ID is checked against the name.

local _, ns = ...
local H = {}
ns.hearth = H

-- Alliance levelling towns (classic IDs).
for key, inn in pairs({
    goldshire  = { name = "Innkeeper Farley", id = 295, town = "Goldshire", zone = "Elwynn Forest" },
    sentinel   = { name = "Innkeeper Heather", id = 8931, town = "Sentinel Hill", zone = "Westfall" },
    thelsamar  = { name = "Innkeeper Hearthstove", id = 6734, town = "Thelsamar", zone = "Loch Modan" },
    lakeshire  = { name = "Innkeeper Brianna", id = 6727, town = "Lakeshire", zone = "Redridge Mountains" },
    darkshire  = { name = "Innkeeper Trelayne", id = 6790, town = "Darkshire", zone = "Duskwood" },
}) do ns:Register("innkeeper", key, inn) end

ns:Register("npcIds", "innkeepers", {
    ["Innkeeper Farley"] = 295, ["Innkeeper Heather"] = 8931, ["Innkeeper Hearthstove"] = 6734,
    ["Innkeeper Brianna"] = 6727, ["Innkeeper Trelayne"] = 6790,
})

ns:Register("navGoal", "hearth", {
    collect = function()
        if ns.db.hearth and ns.db.hearth.off then return nil end
        local zone = GetZoneText and GetZoneText()
        local bind = GetBindLocation and GetBindLocation()
        if not zone or not bind then return nil end
        for key, inn in ns:Each("innkeeper") do
            if inn.zone == zone and bind ~= inn.town then
                local points = ns.places:Points(inn.name)
                if #points > 0 then
                    return { {
                        key = "hearth:" .. key, weight = 1.1, points = points,
                        title = "Set hearthstone",
                        text = string.format("Set hearthstone: %s (%s)", inn.name, inn.town),
                        details = { string.format("Your hearthstone is set to %s. Questing around %s? Set it here:", bind, inn.town),
                                    "talk to the innkeeper and choose \"Make this inn your home\".",
                                    "Right-click this stop on the map to hide it." },
                    } }
                end
            end
        end
    end,
})

ns:OnLoad(function(saved) saved.hearth = saved.hearth or {} end)

-- Setting it removes the stop.
ns:On("HEARTHSTONE_BOUND", function()
    ns:Print("hearthstone set to " .. tostring(GetBindLocation()))
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
