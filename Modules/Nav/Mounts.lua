-- Mount milestone. A mount speeds up every trip after it, so it's the
-- biggest milestone there is:
--   * 5 levels before riding level: the advice list tells you to start saving
--     (how much, and what you have).
--   * At riding level: "Learn riding" goes on the route as a milestone (always
--     planned, weighted as a short detour), blocked with the price until you
--     can pay; then the mount itself (unless your class gets one from a
--     class quest, like the paladin's warhorse).
--   * Done once you know riding / own a mount.
--
-- WoW: Forever's exact riding level and prices aren't confirmed yet, so the
-- numbers below are the classic ones, marked as estimates in what you see.
-- Change them here (or register a "mount" entry for another race) when the
-- game shows something different.
--
--   ns:Register("mount", "<Race token>", { trainer = "NPC", vendor = "NPC", what = "a horse" })
--   ns:Register("mountRule", "default", { level, ridingCost, mountCost, saveFrom, classMount = { CLASS = "spell" } })

local _, ns = ...
local MT = {}
ns.mounts = MT

ns:Register("mountRule", "default", {
    level = 40,                  -- riding level (classic)
    ridingCost = 20 * 10000,     -- copper, estimate
    mountCost = 80 * 10000,      -- copper, estimate (before reputation discounts)
    saveFrom = 5,                -- start the savings reminder this many levels before
    classMount = { PALADIN = "Summon Warhorse", WARLOCK = "Summon Felsteed" },  -- from a class quest: no mount to buy
})

ns:Register("mount", "Human",    { trainer = "Randal Hunter",       vendor = "Katie Hunter",        what = "a horse" })
ns:Register("mount", "Dwarf",    { trainer = "Ultham Ironhorn",     vendor = "Veron Amberstill",    what = "a ram" })
ns:Register("mount", "NightElf", { trainer = "Jartsam",             vendor = "Lelanai",             what = "a nightsaber" })
ns:Register("mount", "Gnome",    { trainer = "Binjy Featherwhistle", vendor = "Milli Featherwhistle", what = "a mechanostrider" })
ns:Register("mount", "Orc",      { trainer = "Kildar",              vendor = "Ogunaro Wolfrunner",  what = "a wolf" })
ns:Register("mount", "Troll",    { trainer = "Xar'Ti",              vendor = "Zjolnir",             what = "a raptor" })
ns:Register("mount", "Tauren",   { trainer = "Kar Stormsinger",     vendor = "Harb Clawhoof",       what = "a kodo" })
ns:Register("mount", "Scourge",  { trainer = "Velma Warnam",        vendor = "Zachariah Post",      what = "a skeletal horse" })

local RIDING_SPELLS = { 33388, 33391, 34090, 34091, 90265 }   -- riding ranks (newer clients)

local function rule() return ns:Get("mountRule", "default") end

-- Riding known: a riding spell, or a "Riding" skill line (classic-style clients).
function MT:HasRiding()
    for _, id in ipairs(RIDING_SPELLS) do
        if IsPlayerSpell and IsPlayerSpell(id) then return true end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, header = GetSkillLineInfo(i)
            if name and not header and name:find("Riding") then return true end
        end
    end
    return false
end

-- Any mount you can summon: the mount journal, or a class mount spell.
function MT:HasMount()
    if C_MountJournal and C_MountJournal.GetNumDisplayedMounts and C_MountJournal.GetMountIDs then
        for _, id in ipairs(C_MountJournal.GetMountIDs() or {}) do
            local ok, _, _, _, _, _, _, _, _, _, _, collected = pcall(C_MountJournal.GetMountInfoByID, id)
            if ok and collected then return true end
        end
    end
    local _, class = UnitClass("player")
    local spell = rule().classMount[class]
    if spell and GetSpellInfo and GetSpellInfo(spell) and IsSpellKnown then
        local _, _, _, _, _, _, id = GetSpellInfo(spell)
        if id and IsSpellKnown(id) then return true end
    end
    return false
end

-- What's left to do, in order: "save", "riding", "mount", or nil (done / too early).
-- Pure on its inputs, so it can be tested: { level, hasRiding, hasMount, classMount }.
function MT.Next(s)
    local r = rule()
    if s.hasMount and s.hasRiding then return nil end
    if s.level < r.level - r.saveFrom then return nil end
    if s.level < r.level then return "save" end
    if not s.hasRiding then return "riding" end
    if not s.hasMount and not s.classMount then return "mount" end
    return nil
end

-- Copper still to spend: riding (if not known) + the mount (if bought).
function MT.Total(s)
    local r = rule()
    return (s.hasRiding and 0 or r.ridingCost) + ((s.hasMount or s.classMount) and 0 or r.mountCost)
end

function MT:State()
    local _, class = UnitClass("player")
    return {
        level = UnitLevel("player"),
        hasRiding = self:HasRiding(),
        hasMount = self:HasMount(),
        classMount = rule().classMount[class],
    }
end

local function coin(c) return (ns.nav and ns.nav.Coin and ns.nav:Coin(c)) or (math.floor(c / 10000) .. "g") end

local function npcPoints(name)
    if not name then return {} end
    if ns.quests.NPCsByName then ns.quests:NPCsByName({ name }) end
    return ns.places:Points(name)
end

ns:Register("navGoal", "mount", {
    collect = function()
        local s = MT:State()
        local step = MT.Next(s)
        if step ~= "riding" and step ~= "mount" then return nil end
        local _, race = UnitRace("player")
        local data = ns:Get("mount", race) or {}
        local r = rule()
        local who = step == "riding" and data.trainer or data.vendor
        local points = npcPoints(who)
        local cost = step == "riding" and r.ridingCost or r.mountCost
        local text = step == "riding" and "Learn riding" or ("Buy your mount (" .. (data.what or "a mount") .. ")")
        local details = {
            "Your mount makes every trip after it faster: the biggest milestone there is.",
            string.format("About %s (estimate: Flow hasn't seen this price in game yet).", coin(cost)),
        }
        if who then details[#details + 1] = "From " .. who .. "." end
        if step == "riding" and s.classMount then
            details[#details + 1] = "Your mount itself comes from a class quest (" .. s.classMount .. ")."
        end
        return { {
            key = "mount:" .. step, kind = "classtrainer", milestone = true, weight = 0.3,
            points = points, npcs = who and { who } or nil,
            title = "Mount", text = text, cost = cost,
            details = details,
            blockedBy = #points == 0 and ("Flow doesn't know where " .. (who or "the riding trainer") .. " is yet") or nil,
        } }
    end,
})

ns:Register("advisor", "mount", {
    check = function()
        local s = MT:State()
        if MT.Next(s) ~= "save" then return {} end
        local r = rule()
        local need, have = MT.Total(s), GetMoney and GetMoney() or 0
        return { {
            importance = 70,
            text = string.format("Save for your mount at level %d: about %s (you have %s)", r.level, coin(need), coin(have)),
            improves = { "Every trip after it is much faster" },
        } }
    end,
})
