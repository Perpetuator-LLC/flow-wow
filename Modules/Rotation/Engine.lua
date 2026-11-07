-- Rotation engine: each tick, work out the single best thing to press.
--
-- 1. Self-preservation: should I heal myself right now?
--    - "efficient" heal: by the time the cast lands, I'll be missing at least
--      as much health as the heal restores (crits ignored), so nothing is wasted.
--    - "emergency" heal: at the current incoming damage I die before I could
--      safely act later, and the mob won't die first.
-- 2. Otherwise the class priority list (buffs, then damage).
--
-- This only SUGGESTS. WoW doesn't allow addons to cast for you; you press the key.

local _, ns = ...
local A, T = ns.api, ns.tracker
local E = {}
ns.rotation = E

local known = {}
local GCD = 1.5
local REACTION = 1.0  -- seconds we allow you to notice and press the key

-- The rotation definition for your class, registered with
-- ns:Register("rotation", CLASS_TOKEN, def). See docs/ARCHITECTURE.md.
function E:Definition()
    local _, class = UnitClass("player")
    return ns:Get("rotation", class)
end

function E:KnownSpells() return known end

function E:RefreshSpells()
    known = A.KnownSpells()
    T:ResetTooltipCache()
end

function E:Knows(spell) return known[spell] == true end

-- Ready = known, usable (mana/resources/conditions), off cooldown, in range.
function E:Ready(spell, unit)
    if not known[spell] then return false end
    local usable = A.Usable(spell)
    if not usable then return false end
    if A.Cooldown(spell) > A.Latency() then return false end
    if unit and not A.InRange(spell, unit) then return false end
    return true
end

local function hostileTarget()
    return UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDead("target")
end

-- Snapshot of the situation that class rules can read.
function E:Context()
    -- Health can be hidden from addons in combat; then heal advice is skipped
    -- (maxHp = 0) but damage and buff suggestions still work.
    -- If either value is hidden, health is UNKNOWN: report maxHp = 0 so no
    -- heal is suggested. (Treating hidden health as 0 made Flow think you
    -- were dying at full health.)
    local hp = A.Safe(UnitHealth("player"))
    local maxHp = A.Safe(UnitHealthMax("player"))
    if not hp or not maxHp or maxHp <= 0 then hp, maxHp = 0, 0 end
    local ok, dtps = pcall(T.DTPS, T)
    if not ok then dtps = 0 end
    local okT, ttd = pcall(T.TargetTTD, T)
    return {
        hp = hp,
        maxHp = maxHp,
        hpPct = maxHp > 0 and hp / maxHp or 1,
        dtps = dtps,
        selfTTD = dtps > 0 and hp / dtps or math.huge,
        targetTTD = okT and ttd or math.huge,
        latency = A.Latency(),
        inCombat = UnitAffectingCombat("player"),
        hostile = hostileTarget(),
        casting = A.Casting(),
        fightType = ns.fight and ns.fight:Classify() or "normal",
        role = ns.LevelingRole and ns:LevelingRole() or "dps",
        engine = self,
    }
end

-------------------------------------------------------------------------------
-- Heal decision
-------------------------------------------------------------------------------

-- Returns suggestion table or nil.
function E:HealDecision(ctx, heals)
    local cfg = ns.db.rotation
    if ctx.maxHp <= 0 or UnitIsDeadOrGhost("player") then return nil end

    -- Already casting a heal: let it land before suggesting another.
    if ctx.casting then
        for _, h in ipairs(heals) do
            if h == ctx.casting then return nil end
        end
    end

    local bestEfficient, bestEfficientAmt, fastest, fastestLand
    for _, spell in ipairs(heals) do
        if self:Ready(spell) then
            local amount = T:HealAmount(spell)
            local _, _, castMs = A.SpellInfo(spell)
            -- Time until the heal actually lands: cast + network round trip.
            local land = (castMs or 0) / 1000 + ctx.latency
            if amount and amount > 0 then
                local deficitAtLand = ctx.maxHp - (ctx.hp - ctx.dtps * land)
                if deficitAtLand >= amount * (1 - cfg.overheal) then
                    -- Prefer the biggest heal that still fits fully.
                    if not bestEfficientAmt or amount > bestEfficientAmt then
                        bestEfficient, bestEfficientAmt = spell, amount
                    end
                end
            end
            if not fastestLand or land < fastestLand then
                fastest, fastestLand = spell, land
            end
        end
    end
    if not fastest then return nil end

    -- Emergency: we'd die before we could finish this heal plus one more
    -- global cooldown of reaction time, unless the mob dies first.
    if ctx.inCombat then
        local danger = ctx.dtps > 0 and ctx.selfTTD < fastestLand + GCD + REACTION
        local mobDiesFirst = ctx.hostile and ctx.targetTTD + 0.5 < ctx.selfTTD
        -- Below the panic line always heal, even if incoming damage reads as 0.
        if (danger and not mobDiesFirst) or ctx.hpPct < cfg.panicPct then
            return { spell = fastest, kind = "emergency",
                     reason = ctx.selfTTD < math.huge
                         and string.format("Emergency: %.1fs to live", ctx.selfTTD)
                         or "Emergency: health very low" }
        end
    end

    if bestEfficient then
        -- In combat, don't stop to top up if the mob is about to die anyway
        -- and we're not under pressure: heal after (or let regen do it).
        if ctx.inCombat and ctx.hostile and ctx.targetTTD < ctx.selfTTD
            and ctx.targetTTD < 3 then
            return nil
        end
        return { spell = bestEfficient, kind = "heal",
                 reason = string.format("Heal: no overheal (%d)", bestEfficientAmt) }
    end
    return nil
end

-------------------------------------------------------------------------------
-- Main evaluation
-------------------------------------------------------------------------------

-- A rotation can give a different priority list per fight type
-- (def.priorities.boss, .elite, .aoe, ...), falling back to def.priority.
local function priorityFor(def, ctx)
    return (def.priorities and def.priorities[ctx.fightType]) or def.priority or {}
end

local function ruleReady(self, rule, ctx)
    -- No buff nagging in inns and cities (resting): you rebuff on the way out.
    if rule.kind == "buff" and not ctx.inCombat and IsResting and IsResting() then return false end
    if not self:Knows(rule.spell) then return false end
    if rule.when then
        -- One failing check (e.g. a buff the game hides in combat) skips that
        -- rule only, instead of stopping every suggestion.
        local ok, w = pcall(rule.when, ctx)
        if not ok then self.lastError, self.lastErrorAt = tostring(w), GetTime() return false end
        if not w then return false end
    end
    return self:Ready(rule.spell, rule.target and "target" or nil)
end

local function suggest(rule, ctx, note)
    return { spell = rule.spell, kind = rule.kind or "damage",
             reason = (rule.reason or rule.spell) .. (note or ""),
             fightType = ctx.fightType }
end

-- The after-fight heal prompt. Flow can't see your health in Forever, so it
-- only offers a heal when it's likely useful and never gets in the way:
--   * after any real fight (6 s or more), for 15 s: your health is hidden
--     from add-ons on Forever, so Flow can't tell how hurt you are; a 7 s
--     fight that left you at half health used to get no offer at all
--   * never in combat, and never once you target an enemy (you're pulling:
--     attacks come first)
--   * gone once you heal or fight again
function E:AfterFightHeal(ctx, def, now)
    now = now or GetTime()
    if ctx.inCombat or ctx.hostile then return nil end
    if not (self.afterFight and now < self.afterFight) then return nil end
    for _, spell in ipairs(def and def.afterFightHeals or { "Holy Light", "Flash of Light" }) do
        if self:Knows(spell) and self:Ready(spell) then
            return { spell = spell, kind = "heal", fightType = ctx.fightType,
                     reason = "After a long fight: top up if you're hurt (Flow can't see your health)" }
        end
    end
end

function E:Choose()
    local def = self:Definition()
    if not def then return nil end

    pcall(T.SampleTarget, T)
    local ctx = self:Context()

    if def.heals then
        local h = self:HealDecision(ctx, def.heals)
        if h then h.fightType = ctx.fightType; return h end
    end

    local h = self:AfterFightHeal(ctx, def)
    if h then return h end

    local list = priorityFor(def, ctx)
    local i = 1
    while i <= #list do
        local rule = list[i]
        if rule.adaptive then
            -- A run of adaptive rules is a group of roughly equal options. Pick
            -- the ready one the profiler found most linked to your best fights of
            -- this type. Ties keep the written order.
            local best, bestBias
            local j = i
            while list[j] and list[j].adaptive do
                local r = list[j]
                if ruleReady(self, r, ctx) then
                    local b = ns.profiler and ns.profiler:Bias(ctx.fightType, r.spell) or 0
                    if not best or b > bestBias + 0.05 then best, bestBias = r, b end
                end
                j = j + 1
            end
            if best then
                local note = (bestBias or 0) > 0.05 and " (learned)" or nil
                return suggest(best, ctx, note)
            end
            i = j
        else
            if ruleReady(self, rule, ctx) then return suggest(rule, ctx) end
            i = i + 1
        end
    end
    return nil
end

-- Diagnostics for /flow rot why: why each rule is or isn't suggested.
function E:Explain()
    local out = {}
    local def = self:Definition()
    if not def then return { "No rotation registered for your class." } end
    local n = 0
    for _ in pairs(known) do n = n + 1 end
    out[#out + 1] = string.format("Known spells: %d. Last error: %s", n, tostring(self.lastError or "none"))
    local ok, ctx = pcall(self.Context, self)
    if not ok then
        out[#out + 1] = "Context failed: " .. tostring(ctx)
        return out
    end
    out[#out + 1] = string.format("Fight type %s, hostile target %s, in combat %s, health %s/%s",
        ctx.fightType, tostring(ctx.hostile), tostring(ctx.inCombat), tostring(ctx.hp), tostring(ctx.maxHp))
    local s = self.current
    out[#out + 1] = "Suggesting now: " .. (s and (s.spell .. " (" .. s.reason .. ")") or "nothing")
    for _, rule in ipairs(priorityFor(def, ctx)) do
        local state
        if not known[rule.spell] then
            state = "not known (skipped)"
        else
            local okW, w = pcall(function() return not rule.when or rule.when(ctx) end)
            local usable = A.Usable(rule.spell)
            if not okW then state = "condition error: " .. tostring(w)
            elseif not w then state = "condition not met"
            elseif not usable then state = "not usable now (mana/requirements)"
            elseif A.Cooldown(rule.spell) > A.Latency() then state = "on cooldown"
            elseif rule.target and not A.InRange(rule.spell, "target") then state = "out of range"
            else state = "READY" end
            local buttons = self.ButtonsFor and #self:ButtonsFor(rule.spell) or 0
            if buttons == 0 then state = state .. ", NOT on your action bars (can't glow)" end
        end
        out[#out + 1] = "  " .. rule.spell .. ": " .. state
    end
    return out
end

-- What to press now. Also remembered as E.current so the profiler can tell
-- whether you followed the suggestion.
function E:Evaluate()
    local s = self:Choose()
    self.current = s
    return s
end

-------------------------------------------------------------------------------
-- Setup and slash commands
-------------------------------------------------------------------------------

ns:OnLoad(function(saved)
    local r = saved.rotation
    if r.enabled == nil then r.enabled = true end
    if r.locked == nil then r.locked = true end
    r.overheal = r.overheal or 0.05   -- tolerate up to 5% overheal
    r.panicPct = r.panicPct or 0.15   -- always heal below 15% in combat
end)

ns:On("SPELLS_CHANGED", function() E:RefreshSpells() end)
ns:On("PLAYER_LOGIN", function() E:RefreshSpells() end)

ns.commands.rot = function(arg)
    local r = ns.db.rotation
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        r.enabled = (arg == "on")
        ns:Print("rotation helper " .. (r.enabled and "on" or "off"))
    elseif arg == "unlock" or arg == "lock" then
        r.locked = (arg == "lock")
        ns:Print(r.locked and "icon hidden when there is nothing to press" or "icon always shown: hold Shift and drag it where you want")
    elseif arg == "debug" then
        r.debug = not r.debug
        ns:Print("debug " .. (r.debug and "on" or "off"))
    elseif arg == "reset" then
        wipe(r.heals); wipe(r.mobs)
        ns:Print("forgot learned heals and mob damage")
    elseif arg == "why" then
        ns:Print("rotation check:")
        for _, line in ipairs(E:Explain()) do print(line) end
    elseif arg == "guide" then
        local def = E:Definition()
        if not (def and def.guide) then ns:Print("no rotation guide for your class yet") return end
        ns:Print("your rotation (with the spells you have now):")
        for _, line in ipairs(def.guide(E)) do print("  " .. line) end
    elseif arg == "known" then
        -- Check that the helper only sees spells you really have.
        local names = {}
        for name in pairs(known) do names[#names + 1] = name end
        table.sort(names)
        ns:Print("spells Flow thinks you know: " .. table.concat(names, ", "))
    elseif arg == "stats" then
        local ctx = E:Context()
        ns:Print(string.format("latency %dms, incoming %.1f dps, you die in %s, target dies in %s, combat log %s",
            ctx.latency * 1000, ctx.dtps,
            ctx.selfTTD == math.huge and "never" or string.format("%.1fs", ctx.selfTTD),
            ctx.targetTTD == math.huge and "?" or string.format("%.1fs", ctx.targetTTD),
            T:Stats().combatLog and "yes" or "no"))
        print("  fight type now: " .. ctx.fightType)
        local def = E:Definition()
        for _, spell in ipairs(def and def.heals or {}) do
            if E:Knows(spell) then
                local amt, src = T:HealAmount(spell)
                print(string.format("  %s: %s (%s)", spell, amt and tostring(math.floor(amt)) or "?", src or "unknown"))
            end
        end
        for name, m in pairs(r.mobs) do
            print(string.format("  %s hits for %.1f dps (%d fights)", name, m.dps, m.n))
        end
    else
        ns:Print("/flow rot guide|why|on|off|lock|unlock|stats|known|debug|reset")
    end
end

-- After-fight heal window (see Choose): opens when a fight of 6 s or more
-- ends, closes when you cast a heal or start another fight.
local fightStart
ns:On("PLAYER_REGEN_DISABLED", function() fightStart = GetTime(); E.afterFight = nil end)
ns:On("PLAYER_REGEN_ENABLED", function()
    if fightStart and GetTime() - fightStart >= 6 then E.afterFight = GetTime() + 15 end
    fightStart = nil
end)
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not E.afterFight then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if name == "Holy Light" or name == "Flash of Light" then E.afterFight = nil end
end)
