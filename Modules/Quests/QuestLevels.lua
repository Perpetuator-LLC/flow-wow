-------------------------------------------------------------------------------
-- Flow - Quests/QuestLevels.lua
-- A quest's level beside its step: shown and coloured by the game's own two
-- map-filter options (0.35.370).
--
-- "If you click on map filter ... you can pick Show quest levels, and there's
-- another one called Quest difficulty color. See if we can tap into that. If
-- so, make it control the quest levels, including the brackets, in the Flow
-- Router, the Flow Tracker, and anywhere else ... And let's also color code
-- them: too high, too low, max XP or less XP or no XP."
--
-- Show quest levels is a setting of the game's (the console variable
-- "showQuestLevel", kept per character): Flow reads it, so the "[16]" beside
-- a step is there when the game shows levels and gone when it doesn't.
-- Quest difficulty color is read the same way. Flow knows several names it
-- could have and otherwise looks through the game's own list of settings for
-- one about quests and difficulty or colour; /flow questlevels (and the
-- diagnostics) say which one it found, or that it found none (then levels
-- are coloured, as the game's default is).
--
-- The colours, for a quest's level against yours:
--   red      5 or more above you: you can't do it yet
--   orange   3 or 4 above: hard, its mobs hit and miss you a lot
--   yellow   within 2 of you: full XP
--   green    3 to 5 below: easy, still full XP
--   olive    6 to 9 below: the XP is dropping (80% down to 20%)
--   grey     10 or more below: next to no XP
-- (The XP steps are the ones Flow's route already goes by: XpValue.lua.)
-------------------------------------------------------------------------------

local _, ns = ...
local QL = {}
ns.questLevels = QL

QL.SHOW_CVAR = "showQuestLevel"
QL.COLOR_CVARS = { "questDifficultyColor", "showQuestDifficultyColor", "questDifficultyColors", "colorQuestDifficulty",
                   "showQuestDifficulty", "questLogDifficultyColor", "mapQuestDifficultyColor" }
QL.TIERS = {
    red    = { hex = "ff3030", says = "5 or more levels above you: you can't do it yet" },
    orange = { hex = "ff8040", says = "3 or 4 levels above you: hard" },
    yellow = { hex = "ffff00", says = "about your level: full XP" },
    green  = { hex = "40c040", says = "a few levels below you: easy, still full XP" },
    olive  = { hex = "9aa04a", says = "well below you: the XP is dropping" },
    grey   = { hex = "808080", says = "far below you: next to no XP" },
}
QL.PLAIN = "999999"

-- Pure: which colour a quest of `level` is for someone of `mine`.
function QL.Tier(level, mine)
    if not (level and mine) then return nil end
    local d = level - mine
    if d >= 5 then return "red" end
    if d >= 3 then return "orange" end
    if d >= -2 then return "yellow" end
    if d >= -5 then return "green" end
    if d >= -9 then return "olive" end
    return "grey"
end

-- Pure: the tag after a step's number or name: " [16]", coloured or plain,
-- or "" when levels are hidden. lead: what goes before the bracket.
function QL.Tag(level, mine, show, colored, lead)
    if not level or show == false then return "" end
    local tier = colored ~= false and QL.Tier(level, mine) or nil
    local hex = tier and QL.TIERS[tier].hex or nil
    if not hex then return string.format("%s[%d]", lead or " ", level) end
    return string.format("%s|cff%s[%d]|r", lead or " ", hex, level)
end

-- Pure: of a list of setting names, the one about a quest's difficulty
-- colour (nil: none looks like it).
function QL.PickColorCvar(names)
    for _, n in ipairs(names or {}) do
        local l = tostring(n):lower()
        if l:find("quest", 1, true) and l:find("difficult", 1, true) and (l:find("color", 1, true) or l:find("colour", 1, true)) then return n end
    end
    for _, n in ipairs(names or {}) do
        local l = tostring(n):lower()
        if l:find("quest", 1, true) and l:find("difficult", 1, true) then return n end
    end
    return nil
end

-------------------------------------------------------------------------------
-- The game's settings
-------------------------------------------------------------------------------
local function cvar(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not (get and name) then return nil end
    local ok, v = pcall(get, name)
    if ok and v ~= nil then return tostring(v) end
    return nil
end
local function truthy(v) return v ~= nil and v ~= "0" and v ~= "" end

-- The setting names the game has with "quest" in them (for the probe, and to
-- find the colour one where its name isn't one Flow knows).
function QL.QuestCvars()
    local out = {}
    local all = _G.C_Console and _G.C_Console.GetAllCommands
    if all then
        local ok, list = pcall(all)
        for _, c in ipairs(ok and type(list) == "table" and list or {}) do
            local name = type(c) == "table" and c.command or c
            if type(name) == "string" and name:lower():find("quest", 1, true) then out[#out + 1] = name end
        end
    end
    table.sort(out)
    return out
end

-- Which setting is the colour one on this client (looked for once a session).
local colorName, colorLooked = nil, false
function QL.ColorCvar()
    if colorLooked then return colorName end
    colorLooked = true
    for _, n in ipairs(QL.COLOR_CVARS) do
        if cvar(n) ~= nil then colorName = n return n end
    end
    colorName = QL.PickColorCvar(QL.QuestCvars())
    if colorName and cvar(colorName) == nil then colorName = nil end
    return colorName
end

-- The two answers, read at most twice a second (rows are redrawn often).
local at, show, colored = -10, true, true
function QL.Now()
    local t = GetTime()
    if t - at < 0.5 then return show, colored end
    at = t
    local s = cvar(QL.SHOW_CVAR)
    show = s == nil or truthy(s)                    -- (no such setting: levels show, as before)
    local c = QL.ColorCvar() and cvar(QL.ColorCvar()) or nil
    colored = c == nil or truthy(c)                 -- (not found: coloured, the game's default)
    return show, colored
end

-- " [16]" for a step, as the game's settings have it.
function QL.For(level, lead)
    local s, c = QL.Now()
    return QL.Tag(level, UnitLevel and UnitLevel("player") or nil, s, c, lead)
end
-- What the colour says, for a tooltip (nil: plain, or hidden).
function QL.Says(level)
    local s, c = QL.Now()
    if not (level and s and c) then return nil end
    local tier = QL.Tier(level, UnitLevel and UnitLevel("player") or nil)
    return tier and QL.TIERS[tier].says or nil, tier and QL.TIERS[tier].hex or nil
end

-- The game changed one of them (its map filter): redraw what shows levels.
ns:On("CVAR_UPDATE", function()
    local before, beforeC = show, colored
    at = -10
    local s, c = QL.Now()
    if (s ~= before or c ~= beforeC) and ns.nav then
        ns.nav.planDirty = true
        if ns.nav.RequestCollect then ns.nav.RequestCollect("quest level display changed") end
    end
end)

function QL.Lines()
    local s, c = QL.Now()
    local out = { string.format("quest levels beside steps: %s, %s", s and "shown" or "hidden", c and "coloured by difficulty" or "plain") }
    out[#out + 1] = string.format("  the game's Show quest levels (%s): %s", QL.SHOW_CVAR, tostring(cvar(QL.SHOW_CVAR) or "no such setting on this client"))
    local name = QL.ColorCvar()
    out[#out + 1] = "  the game's Quest difficulty color: " .. (name and (name .. " = " .. tostring(cvar(name))) or "not found under any name Flow knows (levels are coloured)")
    local names = QL.QuestCvars()
    out[#out + 1] = "  the game's settings about quests: " .. (#names > 0 and table.concat(names, ", "):sub(1, 700) or "this client doesn't list its settings")
    local mine = UnitLevel and UnitLevel("player") or 1
    local sample = {}
    for _, d in ipairs({ 6, 3, 0, -4, -7, -12 }) do
        if mine + d >= 1 then sample[#sample + 1] = QL.Tag(mine + d, mine, true, true, "") end
    end
    out[#out + 1] = "  at your level: " .. table.concat(sample, " ")
    return out
end
ns.commands.questlevels = function()
    for i, l in ipairs(QL.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end
ns:Register("help", "questlevels", { order = 39, title = "Quest levels beside steps", lines = {
    "The level in brackets beside a step follows the game's own map filter: Show quest levels hides or shows it, Quest difficulty color colours it or leaves it plain.",
    "Red: 5 or more levels above you. Orange: 3 or 4 above. Yellow: about your level, full XP. Green: a few below, still full XP. Olive: the XP is dropping. Grey: next to no XP.",
    "/flow questlevels says what Flow read from the game.",
} })
