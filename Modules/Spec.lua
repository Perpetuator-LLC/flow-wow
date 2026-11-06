-- Levelling spec advice. /flow spec shows the recommendation and why.
-- It reminds you when you have unspent talent points.

local _, ns = ...

ns.ROLE_COLOR = { dps = "ff4040", heal = "40ff40", tank = "4090ff" }
ns.ROLE_LABEL = { dps = "DPS", heal = "Heal", tank = "Tank" }

function ns:ClassData()
    local _, class = UnitClass("player")
    return ns:Get("class", class)
end

-- The role you're levelling as: your own choice (/flow spec dps|heal|tank)
-- or the class recommendation.
function ns:LevelingRole()
    local d = self:ClassData()
    return (ns.db.spec and ns.db.spec.role) or (d and d.leveling.role) or "dps"
end

local function unspentPoints()
    if UnitCharacterPoints then return UnitCharacterPoints("player") or 0 end
    return 0
end

local function describe()
    local d = ns:ClassData()
    if not d then ns:Print("no spec advice for your class yet."); return end
    local rec = d.leveling.role
    ns:Print(string.format("recommended levelling spec: |cff%s%s|r (%s)",
        ns.ROLE_COLOR[rec], d.specs[rec].name, ns.ROLE_LABEL[rec]))
    for _, line in ipairs(d.leveling.why) do print("  - " .. line) end
    local mine = ns:LevelingRole()
    if mine ~= rec then
        print(string.format("  You chose |cff%s%s|r: gear advice uses that.", ns.ROLE_COLOR[mine], d.specs[mine].name))
    end
    if #d.leveling.talentPlan == 0 then
        print("  Point-by-point talent plan: coming once we confirm this game version's talent tree.")
    end
end

ns:OnLoad(function(saved) saved.spec = saved.spec or {} end)

ns:On("PLAYER_LOGIN", function()
    if UnitLevel("player") >= 10 and unspentPoints() > 0 then
        ns:Print(string.format("you have %d unspent talent point(s). /flow spec for advice.", unspentPoints()))
    end
end)

ns:On("PLAYER_LEVEL_UP", function(level)
    if level == 10 then
        ns:Print("talents unlocked!")
        describe()
    end
end)

ns.commands.spec = function(arg)
    arg = (arg or ""):lower()
    if arg == "dps" or arg == "heal" or arg == "tank" then
        ns.db.spec.role = arg
        ns:Print("gear advice will favour " .. ns.ROLE_LABEL[arg])
    elseif arg == "auto" then
        ns.db.spec.role = nil
        ns:Print("gear advice follows the recommended levelling spec")
    else
        describe()
        print("  /flow spec dps|heal|tank|auto to choose which role gear advice favours")
    end
end
