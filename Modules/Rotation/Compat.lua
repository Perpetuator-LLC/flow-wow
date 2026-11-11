-- API shims so the rotation code runs on both modern (C_Spell / C_SpellBook /
-- C_UnitAuras) and classic-style (GetSpellInfo / UnitBuff) clients.

local _, ns = ...
local A = {}
ns.api = A

local C_Spell, C_SpellBook, C_UnitAuras = C_Spell, C_SpellBook, C_UnitAuras

-- Modern clients (Forever included) can hand addons "secret" values in
-- combat: you can display them but any maths or comparison errors. A.Safe
-- turns a secret into nil so callers treat it as "unknown".
local issecret = issecretvalue
function A.Safe(v)
    -- Ask issecretvalue first: it takes nil, and it's the one thing that's
    -- always allowed on a secret (no comparison before it).
    if issecret and issecret(v) then return nil end
    return v
end

-- Item functions: WoW: Forever moved some of the old globals into C_Item
-- (GetItemCount is gone as a global). One place that finds each wherever
-- this client has it; nil if neither exists. (Before this, Flow counted 0
-- of every item: crafting, lures and putting your weapon back all broke.)
local CI = C_Item or {}
A.ItemCount   = GetItemCount or CI.GetItemCount
A.ItemInfo    = GetItemInfo or CI.GetItemInfo
A.ItemIcon    = GetItemIcon or CI.GetItemIconByID
A.IsUsableItem = IsUsableItem or CI.IsUsableItem
-- How many you carry (bags; 0 if the client can't say).
function A.Count(id)
    if not (A.ItemCount and id) then return 0 end
    local ok, n = pcall(A.ItemCount, id)
    return ok and tonumber(n) or 0
end
local Safe = A.Safe

-- name, icon, castTimeMs, spellID
function A.SpellInfo(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        local i = C_Spell.GetSpellInfo(spell)
        if i then return i.name, i.iconID, i.castTime or 0, i.spellID end
        return nil
    end
    local name, _, icon, castTime, _, _, id = GetSpellInfo(spell)
    if name then return name, icon, castTime or 0, id end
end

-- start, duration of the spell's cooldown (including GCD)
function A.CooldownRaw(spell)
    local start, dur
    if C_Spell and C_Spell.GetSpellCooldown then
        local c = C_Spell.GetSpellCooldown(spell)
        if not c then return 0, 0 end
        start, dur = c.startTime, c.duration
    else
        start, dur = GetSpellCooldown(spell)
    end
    return Safe(start) or 0, Safe(dur) or 0
end

-- Seconds until the spell's own cooldown is up, ignoring the GCD.
function A.Cooldown(spell)
    local start, dur = A.CooldownRaw(spell)
    if start == 0 or dur <= 1.5 then return 0 end
    return math.max(0, start + dur - GetTime())
end

-- usable, notEnoughMana
-- Unknown (secret) counts as usable: better to suggest than to go silent.
function A.Usable(spell)
    local usable, noMana
    if C_Spell and C_Spell.IsSpellUsable then
        usable, noMana = C_Spell.IsSpellUsable(spell)
    else
        usable, noMana = IsUsableSpell(spell)
    end
    if usable ~= nil and Safe(usable) == nil then return true, false end
    return usable, Safe(noMana)
end

-- true when in range, or when the spell has no range to check.
function A.InRange(spell, unit)
    local r
    if C_Spell and C_Spell.IsSpellInRange then
        r = C_Spell.IsSpellInRange(spell, unit)
    elseif IsSpellInRange then
        r = IsSpellInRange(spell, unit)
    end
    r = Safe(r)
    if r == nil then return true end
    return r == true or r == 1
end

function A.Description(spell)
    if C_Spell and C_Spell.GetSpellDescription then
        return C_Spell.GetSpellDescription(spell)
    end
    if GetSpellDescription then
        local _, _, _, id = A.SpellInfo(spell)
        if id then return GetSpellDescription(id) end
    end
end

-- Your own buffs from what you cast, for when the game won't let addons read
-- auras (Forever hides them, often in combat: "Auras cannot be accessed when
-- secret"). Seals and blessings are timed; auras last until changed.
-- Druid: Mark of the Wild 30 min, Thorns 10 min.
local DURATION = { ["^Seal of"] = 30, ["^Blessing of"] = 300, [" Aura$"] = math.huge,
                   ["^Mark of the Wild$"] = 1800, ["^Thorns$"] = 600 }
local cast = {}   -- [spell name] = { at, ends }
local function remember(name)
    for pat, d in pairs(DURATION) do
        if name:find(pat) then
            if pat == " Aura$" then for n in pairs(cast) do if n:find(pat) then cast[n] = nil end end end
            cast[name] = { at = GetTime(), ends = GetTime() + d }
            return
        end
    end
end
A.RememberCast = remember
A._castMemory = cast  -- for /flow test

local function fromMemory(match)  -- also A._fromMemory (tests)
    local now = GetTime()
    for name, c in pairs(cast) do
        local hit
        if type(match) == "function" then hit = match(name) else hit = (name == match) end
        if hit and c.ends > now then return true, c.ends - now end
    end
    return false, 0
end
A._fromMemory = fromMemory

-- Finds a helpful aura on unit. match is an exact name or a function(name).
-- Returns found, secondsRemaining (math.huge for no expiry). When the game
-- refuses to show auras, falls back to what you cast (player only).
function A.Buff(unit, match)
    for i = 1, 40 do
        local name, expires
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok then
                if unit == "player" then return fromMemory(match) end
                return false, 0
            end
            if not a then break end
            name, expires = Safe(a.name), Safe(a.expirationTime)
            if name == nil and unit == "player" then return fromMemory(match) end
        else
            local n, _, _, _, _, e = UnitBuff(unit, i)
            if not n then break end
            name, expires = n, e
        end
        local hit
        if name == nil then hit = false
        elseif type(match) == "function" then hit = match(name) else hit = (name == match) end
        if hit then
            if expires and expires > 0 then return true, expires - GetTime() end
            return true, math.huge
        end
    end
    return false, 0
end

-- Set of spell names the player actually knows (active, not future/passive).
function A.KnownSpells()
    local known = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and Enum and Enum.SpellBookSpellBank then
        local bank = Enum.SpellBookSpellBank.Player
        local SPELL = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        for t = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(t)
            if line and not line.offSpecID then
                for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local info = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if info and info.name and not info.isPassive
                        and (not SPELL or info.itemType == SPELL) then
                        known[info.name] = true
                    end
                end
            end
        end
    else
        local bt = BOOKTYPE_SPELL or "spell"
        for t = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(t)
            for i = offset + 1, offset + num do
                local kind = GetSpellBookItemInfo and GetSpellBookItemInfo(i, bt)
                local name = GetSpellBookItemName(i, bt)
                if name and kind ~= "FUTURESPELL"
                    and not (IsPassiveSpell and IsPassiveSpell(i, bt)) then
                    known[name] = true
                end
            end
        end
    end
    return known
end

-- True while the spell is active/queued (e.g. auto attack switched on).
function A.IsCurrent(spell)
    local r
    if C_Spell and C_Spell.IsCurrentSpell then
        local _, _, _, id = A.SpellInfo(spell)
        if id then r = C_Spell.IsCurrentSpell(id) end
    elseif IsCurrentSpell then
        r = IsCurrentSpell(spell)
    end
    return Safe(r) and true or false
end


-- Auto attack switched on (either name: "Auto Attack" on newer clients,
-- "Attack" on older ones).
function A.Swinging()
    return A.IsCurrent("Auto Attack") or A.IsCurrent("Attack")
end

-- Your health is hidden from add-ons on Forever, but the game's own
-- low-health warning (the red screen flash, about a third of your health or
-- less) is drawn by Blizzard's code, and whether it's showing can be read.
-- true / false, or nil when this client has no such warning (or hides it).
function A.LowHealthWarning()
    local f = _G.LowHealthFrame
    if not f then return nil end
    local ok, shown = pcall(f.IsShown, f)
    shown = ok and Safe(shown)
    if shown == nil then return nil end
    if not shown then return false end
    local okA, alpha = pcall(f.GetAlpha, f)
    alpha = okA and Safe(alpha)
    return alpha == nil or alpha > 0.05
end

-- What's stopping you right now (stunned, feared...): the game's
-- loss-of-control type ("STUN", "FEAR", "CHARM", "ROOT"...), or nil.
function A.LossOfControl()
    local L = C_LossOfControl
    if not (L and L.GetActiveLossOfControlDataCount and L.GetActiveLossOfControlData) then return nil end
    local okN, n = pcall(L.GetActiveLossOfControlDataCount)
    n = okN and Safe(n)
    for i = 1, (n or 0) do
        local okD, d = pcall(L.GetActiveLossOfControlData, i)
        local t = okD and d and Safe(d.locType)
        if t then return t end
    end
end
-- Can this client give addons the combat log? Newer clients (the ones with
-- "secret" values, which includes Forever) treat registering for it as an
-- action only the Blizzard UI may take, and show an "Interface action
-- failed because of an AddOn" error. Default: off on those clients.
-- /flow api combatlog on|off overrides it.
function A.CombatLogAllowed()
    local force = ns.db and ns.db.api and ns.db.api.combatLog
    if force ~= nil then return force end
    if issecretvalue then return false end
    return CombatLogGetCurrentEventInfo ~= nil
end

-- Spells on the stance bar (paladin auras live there on newer clients).
-- Returns { { name, active, index }, ... }.
function A.StanceSpells()
    local out = {}
    if not GetNumShapeshiftForms then return out end
    for i = 1, GetNumShapeshiftForms() or 0 do
        local _, active, _, spellID = GetShapeshiftFormInfo(i)
        local name = spellID and A.SpellInfo(spellID)
        if name then out[#out + 1] = { name = name, active = Safe(active) and true or false, index = i } end
    end
    return out
end

-- Where a profession should be at your level (from the levelling guide):
-- 75 by 10, 125 by 20, 175 by 30, 200 by 35, 225 by 40, 275 by 50, 300 by 60.
function A.ProfessionTarget(level)
    local marks = { { 1, 1 }, { 10, 75 }, { 20, 125 }, { 30, 175 }, { 35, 200 },
                    { 40, 225 }, { 50, 275 }, { 60, 300 } }
    for i = 2, #marks do
        local a, b = marks[i - 1], marks[i]
        if level <= b[1] then
            return math.floor(a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1]))
        end
    end
    return 300
end

-- Skill rank and max from the skills window; nil if you don't have it.
-- Your professions: { { name, rank, max, primary } }. Uses the newer
-- profession API where it exists (Forever), else the classic skills window.
-- (Reading only the classic API made Flow miss professions you'd learned.)
-- The professions you have, by name: { ["Mining"] = true } (no weapon skills).
function A.ProfessionSet()
    local set = {}
    for _, p in ipairs(A.Professions()) do
        if p.name and not p.other then set[p.name] = true end
    end
    return set
end

function A.Professions()
    local out = {}
    if GetProfessions and GetProfessionInfo then
        local list = { GetProfessions() }
        for i = 1, 6 do
            local idx = list[i]
            if idx then
                local name, _, rank, max = GetProfessionInfo(idx)
                if name then out[#out + 1] = { name = name, rank = rank or 0, max = max or 0, primary = i <= 2 } end
            end
        end
        if #out > 0 then return out end
    end
    if GetNumSkillLines then
        local section
        for i = 1, GetNumSkillLines() do
            local n, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if isHeader then section = n
            elseif section == "Professions" or section == "Secondary Skills" then
                out[#out + 1] = { name = n, rank = rank or 0, max = maxRank or 0, primary = section == "Professions" }
            elseif n then
                -- Other sections (weapons etc.) aren't professions, but keep
                -- them findable by name for A.Skill.
                out[#out + 1] = { name = n, rank = rank or 0, max = maxRank or 0, other = true }
            end
        end
    end
    return out
end

function A.Skill(name)
    for _, p in ipairs(A.Professions()) do
        if p.name == name then return p.rank, p.max end
    end
end

-- World latency in seconds.
function A.Latency()
    local _, _, home, world = GetNetStats()
    local ms = (world and world > 0 and world) or home or 100
    return ms / 1000
end

-- Name of the spell the player is currently casting, if any.
function A.Casting()
    local name, _, _, _, endMs = UnitCastingInfo("player")
    name, endMs = Safe(name), Safe(endMs)
    if name then return name, endMs and ((endMs / 1000) - GetTime()) or 0 end
end

-- Your own debuffs on a target (Moonfire, Rake...): found, seconds left.
-- When the game hides the target's auras, falls back to what you cast on
-- it (A.RememberDebuff): the same target, within the debuff's duration.
local DEBUFF_DURATION = { ["Moonfire"] = 9, ["Rake"] = 9, ["Rip"] = 12,
                          ["Demoralizing Roar"] = 30, ["Faerie Fire"] = 40, ["Insect Swarm"] = 12 }
local debuffs = {}   -- [spell] = { guid, ends }
function A.RememberDebuff(name, guid, now)
    local d = DEBUFF_DURATION[name]
    if not d then return end
    now = now or GetTime()
    debuffs[name] = { guid = guid, ends = now + d }
end
function A.DebuffFromMemory(name, guid, now)
    local e = debuffs[name]
    now = now or GetTime()
    if not (e and e.ends > now) then return false, 0 end
    if e.guid and guid and e.guid ~= guid then return false, 0 end   -- a different mob
    return true, e.ends - now
end
A._debuffMemory = debuffs  -- (tests)

function A.Debuff(unit, name)
    local guid = Safe(UnitGUID(unit))
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL|PLAYER")
            if not ok then return A.DebuffFromMemory(name, guid) end
            if not a then return false, 0 end
            local n, expires = Safe(a.name), Safe(a.expirationTime)
            if n == nil then return A.DebuffFromMemory(name, guid) end
            if n == name then
                if expires and expires > 0 then return true, expires - GetTime() end
                return true, math.huge
            end
        end
        return false, 0
    end
    if UnitDebuff then
        for i = 1, 40 do
            local n, _, _, _, _, e, caster = UnitDebuff(unit, i)
            if not n then break end
            if n == name and (caster == nil or caster == "player") then
                return true, (e and e > 0) and (e - GetTime()) or math.huge
            end
        end
        return false, 0
    end
    return A.DebuffFromMemory(name, guid)
end

-- Combo points on your target (Cat Form), 0 if hidden.
function A.ComboPoints()
    local n
    if GetComboPoints then n = Safe(GetComboPoints("player", "target")) end
    if not n and UnitPower and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
        n = Safe(UnitPower("player", Enum.PowerType.ComboPoints))
    end
    return tonumber(n) or 0
end

-- The shapeshift form you're in (its spell name), or nil.
function A.Form()
    for _, s in ipairs(A.StanceSpells()) do
        if s.active then return s.name end
    end
end

-- Feeds A.Buff's and A.Debuff's fallbacks: your successful casts.
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    local id = A.Safe(spellID)
    local name = id and A.SpellInfo(id)
    if type(name) == "string" then
        A.RememberCast(name)
        A.RememberDebuff(name, Safe(UnitGUID("target")))
    end
end)
