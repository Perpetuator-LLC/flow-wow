-- Situational awareness: how hard am I being hit, how fast is my target
-- dying, and how big are my heals really (learned, crits excluded).
--
-- Uses the combat log when the client allows it. Otherwise it falls back
-- to watching the player's health go down.

local _, ns = ...
local T = {}
ns.tracker = T

local WINDOW = 5          -- seconds of recent damage used for DTPS
local TARGET_WINDOW = 4   -- seconds of target health history used for its TTD
local EMA = 0.3           -- learning rate for heal sizes and mob DPS

local playerGUID
local hits = {}           -- { {t, amount}, ... } damage taken recently
local combatStart         -- GetTime() when combat began, nil out of combat
local fightBySource = {}  -- [mobName] = damage done to us this fight
local targetSamples = {}  -- { {t, fraction}, ... }
local lastHealth
local cleuActive = false  -- true once we have seen a combat log event

local function db() return ns.db.rotation end

-------------------------------------------------------------------------------
-- Damage taken
-------------------------------------------------------------------------------

local function addDamage(amount, source, guid)
    if not amount or amount <= 0 then return end
    local now = GetTime()
    hits[#hits + 1] = { now, amount, guid }
    if source and combatStart then
        fightBySource[source] = (fightBySource[source] or 0) + amount
    end
end

local function prune(now)
    local cutoff = now - WINDOW
    local i = 1
    while hits[i] and hits[i][1] < cutoff do i = i + 1 end
    if i > 1 then
        local n = #hits
        for j = i, n do hits[j - i + 1] = hits[j] end
        for j = n - i + 2, n do hits[j] = nil end
    end
end

-- Expected damage per second against the player right now. Early in a
-- fight the measured window is short, so it is topped up with what this
-- mob has done to us in past fights.
function T:DTPS()
    local now = GetTime()
    prune(now)
    local sum = 0
    for _, h in ipairs(hits) do sum = sum + h[2] end
    if not combatStart then
        return sum / WINDOW
    end
    local elapsed = math.max(0.5, now - combatStart)
    if elapsed >= WINDOW then return sum / WINDOW end

    local name = UnitExists("target") and ns.api.Safe(UnitName("target"))
    local learned = T:LearnedMobDPS(name) or 0
    -- Blend: real damage for the time we have seen, learned rate for the rest.
    return (sum + learned * (WINDOW - elapsed)) / WINDOW
end

-- How many different enemies hit you in the last few seconds.
function T:AttackerCount()
    prune(GetTime())
    local seen, n = {}, 0
    for _, h in ipairs(hits) do
        if h[3] and not seen[h[3]] then seen[h[3]] = true; n = n + 1 end
    end
    return n
end

function T:LearnedMobDPS(name)
    if not name then return nil end
    local m = db().mobs[name]
    if m then return m.dps end
    local fromLog = ns:Get("learned", "combatlog")
    return fromLog and fromLog.mobs and fromLog.mobs[name]
end

-------------------------------------------------------------------------------
-- Target time-to-die (from its health fraction falling over time)
-------------------------------------------------------------------------------

function T:SampleTarget()
    if not UnitExists("target") or UnitIsDead("target") then
        wipe(targetSamples)
        return
    end
    local Safe = ns.api.Safe
    local max, hp = Safe(UnitHealthMax("target")), Safe(UnitHealth("target"))
    if not max or not hp or max <= 0 then return end  -- hidden in combat on some clients
    local now = GetTime()
    targetSamples[#targetSamples + 1] = { now, hp / max }
    while targetSamples[1] and targetSamples[1][1] < now - TARGET_WINDOW do
        table.remove(targetSamples, 1)
    end
end

-- Seconds until the target dies at the current rate, or math.huge.
function T:TargetTTD()
    local first, last = targetSamples[1], targetSamples[#targetSamples]
    if not first or first == last then return math.huge end
    local dt = last[1] - first[1]
    local dropped = first[2] - last[2]
    if dt < 1 or dropped <= 0 then return math.huge end
    return last[2] / (dropped / dt)
end

-------------------------------------------------------------------------------
-- Heal learning
-------------------------------------------------------------------------------

-- Expected (non-crit) size of a heal. Learned from real casts once we have
-- any; before that, the low end of the tooltip range.
local tooltipCache = {}

function T:HealAmount(spell)
    local learned = db().heals[spell]
    if learned and learned.n > 0 then return learned.avg, "learned" end
    local fromLog = ns:Get("learned", "combatlog")
    if fromLog and fromLog.heals and fromLog.heals[spell] then
        return fromLog.heals[spell], "combat log"
    end

    if tooltipCache[spell] == nil then
        local desc = ns.api.Description(spell) or ""
        desc = desc:gsub(",", "")
        local low = desc:match("(%d+) to %d+") or desc:match("for (%d+)")
        tooltipCache[spell] = tonumber(low) or false
    end
    if tooltipCache[spell] then return tooltipCache[spell], "tooltip" end
    return nil
end

function T:ResetTooltipCache() wipe(tooltipCache) end

-- Learned per spell name, from your top rank only (the rank Flow suggests
-- and that casting by name uses). A lower rank cast from a macro is ignored.
local function learnHeal(spellId, name, amount, critical)
    if critical or not spellId or not name or not amount or amount <= 0 then return end
    local _, _, _, topId = ns.api.SpellInfo(name)
    if topId and topId ~= spellId then return end
    local h = db().heals[name]
    if not h then
        db().heals[name] = { n = 1, avg = amount }
    else
        h.n = h.n + 1
        h.avg = h.avg + (amount - h.avg) * EMA
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local function onCombatLog()
    local _, sub, _, srcGUID, srcName, _, _, dstGUID, _, _, _,
          a12, a13, _, a15, _, _, a18 = CombatLogGetCurrentEventInfo()
    cleuActive = true
    playerGUID = playerGUID or UnitGUID("player")

    if dstGUID == playerGUID then
        if sub == "SWING_DAMAGE" then
            addDamage(a12, srcName, srcGUID)
        elseif sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE"
            or sub == "RANGE_DAMAGE" then
            addDamage(a15, srcName, srcGUID)
        elseif sub == "SPELL_HEAL" and srcGUID == playerGUID then
            -- a12 spellId, a13 name, a15 amount (incl. overheal), a18 critical
            learnHeal(a12, a13, a15, a18)
        end
    end
end

local function onHealth(unit)
    if unit ~= "player" then return end
    local hp = ns.api.Safe(UnitHealth("player"))
    if not hp then return end
    if lastHealth and hp < lastHealth and not cleuActive then
        addDamage(lastHealth - hp, UnitExists("target") and UnitName("target") or nil)
    end
    lastHealth = hp
end

local function onCombatStart()
    combatStart = GetTime()
    wipe(fightBySource)
end

local function onCombatEnd()
    if combatStart then
        local duration = GetTime() - combatStart
        if duration >= 3 then
            for name, total in pairs(fightBySource) do
                local dps = total / duration
                local m = db().mobs[name]
                if m then
                    m.dps = m.dps + (dps - m.dps) * EMA
                    m.n = m.n + 1
                else
                    db().mobs[name] = { dps = dps, n = 1 }
                end
            end
        end
    end
    combatStart = nil
end

ns:OnLoad(function(saved)
    saved.rotation = saved.rotation or {}
    local r = saved.rotation
    r.heals = r.heals or {}
    r.mobs = r.mobs or {}

    playerGUID = UnitGUID("player")
    lastHealth = UnitHealth("player")

    local f = CreateFrame("Frame")
    -- Some clients restrict the combat log for addons; then damage taken comes
    -- from watching your health bar instead.
    if ns.api.CombatLogAllowed() then
        pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
    end
    f:RegisterEvent("UNIT_HEALTH")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:SetScript("OnEvent", function(_, event, ...)
        local ok, err = pcall(function(...)
            if event == "COMBAT_LOG_EVENT_UNFILTERED" then onCombatLog()
            elseif event == "UNIT_HEALTH" then onHealth(...)
            elseif event == "PLAYER_REGEN_DISABLED" then onCombatStart()
            elseif event == "PLAYER_REGEN_ENABLED" then onCombatEnd()
            elseif event == "PLAYER_TARGET_CHANGED" then wipe(targetSamples)
            end
        end, ...)
        if not ok and ns.db.rotation.debug then ns:Print("tracker: " .. tostring(err)) end
    end)
end)

function T:Stats()
    return {
        dtps = self:DTPS(),
        targetTTD = self:TargetTTD(),
        combatLog = cleuActive,
        inCombat = combatStart ~= nil,
    }
end
