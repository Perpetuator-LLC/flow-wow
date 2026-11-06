-- Levelling spec advice. /flow spec shows the recommendation and why.
-- It reminds you when you have unspent talent points.

local _, ns = ...

ns.ROLE_COLOR = { dps = "ff4040", heal = "40ff40", tank = "4090ff" }
ns.ROLE_LABEL = { dps = "DPS", heal = "Heal", tank = "Tank" }

-- Spec icon for a role (from class data), e.g. Retribution for dps.
function ns:RoleIconPath(role)
    local d = self:ClassData()
    local s = d and d.specs and d.specs[role]
    return s and s.icon
end

-- Inline icon for text ("|T...|t"), or the coloured role name if the class
-- has no icon for it.
function ns:RoleIcon(role, size)
    local path = self:RoleIconPath(role)
    if path then return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", path, size or 14, size or 14) end
    return string.format("|cff%s%s|r", ns.ROLE_COLOR[role] or "ffffff", ns.ROLE_LABEL[role] or role)
end

-- Spec name for a role, e.g. "Retribution" (falls back to DPS/Heal/Tank).
function ns:RoleName(role)
    local d = self:ClassData()
    local s = d and d.specs and d.specs[role]
    return s and s.name or ns.ROLE_LABEL[role]
end

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

-- /flow talents: this client's talent trees (tab, tier, column, ranks), so
-- the talent plan can be written for Forever's real trees. Also in the
-- diagnostics snapshot.
ns.commands.talents = function()
    if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then
        ns:Print("this client has no classic talent API" .. (C_ClassTalents and " (it has C_ClassTalents)" or ""))
        return
    end
    local tabs = GetNumTalentTabs() or 0
    ns:Print(string.format("talents: %d tab(s), %d point(s) to spend", tabs,
        UnitCharacterPoints and UnitCharacterPoints("player") or 0))
    for tab = 1, tabs do
        local name = GetTalentTabInfo and GetTalentTabInfo(tab)
        if type(name) == "number" then name = select(2, GetTalentTabInfo(tab)) end
        print(string.format("  tab %d: %s", tab, tostring(name)))
        for i = 1, GetNumTalents(tab) or 0 do
            local tname, _, tier, column, rank, maxRank = GetTalentInfo(tab, i)
            print(string.format("    %d.%d %s  tier %s col %s  %s/%s", tab, i, tostring(tname),
                tostring(tier), tostring(column), tostring(rank), tostring(maxRank)))
        end
    end
end

-- Modern talents (C_ClassTalents / C_Traits): each node with its position,
-- ranks and spell names. Used by /flow talents when the classic API is gone.
local function dumpTraits()
    local cfg = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    if not cfg then ns:Print("talents: no active talent loadout yet (talents may unlock at a later level)") return end
    local info = C_Traits.GetConfigInfo(cfg)
    local unspent = 0
    for _, treeID in ipairs(info and info.treeIDs or {}) do
        local ok, currencies = pcall(C_Traits.GetTreeCurrencyInfo, cfg, treeID, false)
        for _, c in ipairs(ok and currencies or {}) do unspent = unspent + (c.quantity or 0) end
    end
    ns:Print(string.format("talents (modern): config %s, unspent %d", tostring(cfg), unspent))
    local n = 0
    for _, treeID in ipairs(info and info.treeIDs or {}) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
            local node = C_Traits.GetNodeInfo(cfg, nodeID)
            if node and node.ID ~= 0 and (node.maxRanks or 0) > 0 then
                local names = {}
                for _, entryID in ipairs(node.entryIDs or {}) do
                    local e = C_Traits.GetEntryInfo(cfg, entryID)
                    local def = e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
                    local spell = def and (def.overrideName or (def.spellID and ns.api.SpellInfo(def.spellID)))
                    names[#names + 1] = tostring(spell or ("entry " .. entryID))
                end
                n = n + 1
                if n <= 120 then
                    print(string.format("    node %d at %d,%d  %d/%d  %s", nodeID, node.posX or 0, node.posY or 0,
                        node.currentRank or 0, node.maxRanks or 0, table.concat(names, " | ")))
                end
            end
        end
    end
    if n > 120 then print(string.format("    ...and %d more nodes", n - 120)) end
end

local classicTalents = ns.commands.talents
ns.commands.talents = function()
    if not (GetNumTalentTabs and GetTalentInfo) and C_ClassTalents and C_Traits then
        local ok, err = pcall(dumpTraits)
        if not ok then ns:Print("talents: " .. tostring(err)) end
        return
    end
    classicTalents()
end
