-- /flow help (also plain /flow). Topics are registered, so new features add
-- their own help without touching this file:
--   ns:Register("help", key, { order = n, title = "...", lines = { "...", ... } })

local _, ns = ...

local topics = {
    { "basics", 10, "Basics", {
        "Hold |cffffd200Shift|r and drag any Flow element to move it.",
        "/flow splash - replay the load splash (on/off)",
        "/flow api - what this game client lets addons see",
    } },
    { "rotation", 20, "Rotation (icon + glowing action button)", {
        "Green = attack, light blue = buff, gold = heal, fast gold pulse = heal now.",
        "Click the icon or press your Flow key to cast it (set the key in /flow settings).",
        "In combat the key keeps the spell it had at the pull; a small \"key:\" icon shows it.",
        "/flow rot why - why each spell is or isn't suggested",
        "/flow rot on|off|unlock|lock|stats|known|reset",
    } },
    { "advice", 30, "Advice (orange ! button)", {
        "Hover for ways to improve, click to print. Also /flow advice.",
    } },
    { "nav", 40, "Arrow", {
        "Plans your whole trip: objectives, turn-ins (after their objectives), quests to pick up,",
        "trainers, and fishing/gathering when it is on the way. Click for the full plan.",
        "Left-click: details. Right-click: next goal. Learns trails as you walk.",
        "/flow nav on|off|learn|forget",
    } },
    { "quests", 50, "Quests", {
        "Nameplate marks: skull = kill (count), diamond = drops what you need, star = talk.",
        "/flow quest (plates turns nameplates on), /flow missed - quests you skipped",
    } },
    { "gear", 60, "Gear", {
        "Tooltips: score per role and +/- vs what each item would replace (or your role's set).",
        "/flow gear sets | set <role> <set name> | save <role> | offspec | on|off",
        "/flow spec - levelling spec advice; /flow spec dps|heal|tank|auto",
        "Bags: green arrow = equip now, coloured dots = better for another role, $ sell, AH, DE. /flow bags on|off",
        "Vendors: Flow lists what to sell; sells 12 at a time on click, buy back any (it learns). /flow sell",
    } },
    { "learning", 70, "Learning from your fights", {
        "/flow fights - best vs worst fights per fight type",
        "/flow log auto - write the combat log file every session, for Claude's reports",
    } },
}
for _, t in ipairs(topics) do
    ns:Register("help", t[1], { order = t[2], title = t[3], lines = t[4] })
end

local function version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ns.name, "Version") or "?"
end
ns.Version = version

ns.commands.help = function()
    local list = {}
    for _, t in ns:Each("help") do list[#list + 1] = t end
    table.sort(list, function(a, b) return (a.order or 100) < (b.order or 100) end)
    ns:Print("v" .. version() .. " help")
    for _, t in ipairs(list) do
        print("|cffffd200" .. t.title .. "|r")
        for _, l in ipairs(t.lines) do print("   " .. l) end
    end
end
