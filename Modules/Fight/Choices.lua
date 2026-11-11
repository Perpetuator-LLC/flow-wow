-- Your casts against Flow's advice. In every fight, each spell you cast is
-- set beside what the easy button advised at that moment:
--   "advice"  you cast what it advised
--   "key"     you pressed your key (locked to one spell for the fight) while
--             the advice was another spell, on your bar
--   "own"     you cast something else: your own choice
-- For "key" and "own", Flow notes the situation (moving, the enemy on you,
-- the advice out of range...), so the pattern says WHY you chose otherwise,
-- and each fight remembers its choices, so fights with a choice can be set
-- beside fights without it (kill speed). /flow choices shows the tally; the
-- diagnostics keep it, and the rotation is changed from what it shows (a
-- reason first, never a blind copy).
--
-- Forever gives add-ons no combat log, so this goes by your own cast events
-- (a fightProbe: Profiler.lua runs it during fights).

local _, ns = ...
local A = ns.api
local C = {}
ns.choices = C

C.MAX = 60           -- kinds of choice kept (the rarest go first)
C.LOOKBACK = 0.3     -- an instant is judged against the advice this long before it landed
C.MIN_FIGHTS = 3     -- fights on each side before speeds are compared

local function db() return ns.db.choices end

-------------------------------------------------------------------------------
-- Pure parts (the tests pass values in)
-------------------------------------------------------------------------------

function C.Kind(cast, advice, keySpell)
    if advice and cast == advice then return "advice" end
    if keySpell and cast == keySpell then return "key" end
    return "own"
end

-- The situation as short tags. s: { opening, moving, targetCasting, onYou
-- (1 / 0 / 0.5 unknown), near (true / false / nil), hurt, mana (0..1),
-- targetHp (0..1), attackers, shifted, adviceRange, adviceUsable, adviceCooldown }.
function C.Tags(s)
    local t = {}
    local function add(tag) t[#t + 1] = tag end
    if s.opening then add("opening cast") end
    if s.moving then add("moving") end
    if s.targetCasting then add("target casting") end
    if s.onYou == 1 then add("enemy on you") elseif s.onYou == 0 then add("enemy not on you") end
    if s.near == true then add("target close") elseif s.near == false then add("target far") end
    if (s.hurt or 0) >= 8 then add("hurt") end
    if s.mana and s.mana < 0.3 then add("low mana") end
    if s.targetHp and s.targetHp < 0.25 then add("target nearly dead")
    elseif s.targetHp and s.targetHp > 0.8 then add("target healthy") end
    if (s.attackers or 0) >= 2 then add("several enemies") end
    if s.shifted then add("shapeshifted") end
    if s.adviceRange == false then add("advice out of range") end
    if s.adviceUsable == false then add("advice not usable") end
    if (s.adviceCooldown or 0) > 1.5 then add("advice on cooldown") end
    return t
end

-- One cast into the tally (data: the saved table). Returns the choice's key
-- (nil when you followed the advice) and its kind.
function C.Note(data, cast, advice, keySpell, tags, now)
    local kind = C.Kind(cast, advice, keySpell)
    data.casts = (data.casts or 0) + 1
    data.kinds = data.kinds or {}
    data.kinds[kind] = (data.kinds[kind] or 0) + 1
    if kind == "advice" then return nil, kind end
    local key = kind .. ": " .. cast .. " < " .. (advice or "nothing")
    local rec = data.list[key]
    if not rec then
        rec = { cast = cast, advice = advice, kind = kind, n = 0, tags = {} }
        data.list[key] = rec
    end
    rec.n, rec.last = rec.n + 1, now
    for _, tag in ipairs(tags or {}) do rec.tags[tag] = (rec.tags[tag] or 0) + 1 end
    return key, kind
end

-- Keeps the tally small: over `max` kinds, the rarest (then oldest) go.
function C.Trim(data, max)
    local keys = {}
    for key in pairs(data.list) do keys[#keys + 1] = key end
    if #keys <= max then return 0 end
    table.sort(keys, function(a, b)
        local x, y = data.list[a], data.list[b]
        if x.n ~= y.n then return x.n > y.n end
        return (x.last or 0) > (y.last or 0)
    end)
    for i = max + 1, #keys do data.list[keys[i]] = nil end
    return #keys - max
end

-- "enemy on you 92%, moving 67%": a choice's commonest situations.
function C.TagLine(rec, n)
    local list = {}
    for tag, count in pairs(rec.tags or {}) do list[#list + 1] = { tag = tag, share = count / math.max(1, rec.n) } end
    table.sort(list, function(a, b) if a.share ~= b.share then return a.share > b.share end return a.tag < b.tag end)
    local bits = {}
    for i = 1, math.min(n or 4, #list) do
        if list[i].share >= 0.3 then bits[#bits + 1] = string.format("%s %d%%", list[i].tag, math.floor(list[i].share * 100 + 0.5)) end
    end
    return table.concat(bits, ", ")
end

-- Fights with this choice beside fights of the same types without it:
-- { with = n, without = n, speedWith, speedWithout } (speeds nil when too
-- few fights have one), or nil with fewer than C.MIN_FIGHTS on a side.
-- value(fight) -> its kill speed, or nil.
function C.Outcome(key, fights, value)
    local types, with, without = {}, {}, {}
    for _, f in ipairs(fights) do
        if f.own and f.own[key] then types[f.type or "normal"] = true; with[#with + 1] = f end
    end
    for _, f in ipairs(fights) do
        if types[f.type or "normal"] and not (f.own and f.own[key]) then without[#without + 1] = f end
    end
    if #with < C.MIN_FIGHTS or #without < C.MIN_FIGHTS then return nil end
    local function avg(list, fn)
        local sum, n = 0, 0
        for _, f in ipairs(list) do
            local v = fn(f)
            if v then sum, n = sum + v, n + 1 end
        end
        return n >= C.MIN_FIGHTS and sum / n or nil
    end
    return { with = #with, without = #without,
             speedWith = avg(with, value), speedWithout = avg(without, value),
             secsWith = avg(with, function(f) return f.duration end),
             secsWithout = avg(without, function(f) return f.duration end) }
end

-- The report's lines.
function C.Report(data, fights, value)
    local out = {}
    local total = data.casts or 0
    if total == 0 then
        out[1] = "no casts recorded yet: fight a few mobs with the easy button up."
        return out
    end
    local k = data.kinds or {}
    local function pct(n) return math.floor((n or 0) / total * 100 + 0.5) end
    out[#out + 1] = string.format("%d casts in fights: %d%% what Flow advised, %d%% your key while it advised a bar spell, %d%% your own choice",
        total, pct(k.advice), pct(k.key), pct(k.own))
    local list = {}
    for key, rec in pairs(data.list) do list[#list + 1] = { key = key, rec = rec } end
    table.sort(list, function(a, b) if a.rec.n ~= b.rec.n then return a.rec.n > b.rec.n end return a.key < b.key end)
    for _, kind in ipairs({ "own", "key" }) do
        local shown = 0
        for _, e in ipairs(list) do
            local rec = e.rec
            if rec.kind == kind and shown < 8 then
                if shown == 0 then
                    out[#out + 1] = kind == "own" and "  your own choices:" or "  your key instead of the advice on your bar:"
                end
                shown = shown + 1
                local line = string.format("    %s when Flow advised %s: %dx", rec.cast, rec.advice or "nothing", rec.n)
                local tags = C.TagLine(rec)
                if tags ~= "" then line = line .. ". Mostly: " .. tags end
                local o = C.Outcome(e.key, fights or {}, value or function() return nil end)
                if o and o.speedWith and o.speedWithout and o.speedWithout > 0 then
                    line = line .. string.format(". Kill speed %+d%% in the %d fights with it (%d without)",
                        math.floor((o.speedWith / o.speedWithout - 1) * 100 + 0.5), o.with, o.without)
                elseif o and o.secsWith and o.secsWithout then
                    line = line .. string.format(". Fights with it lasted %.0f s, without %.0f s (%d and %d fights)",
                        o.secsWith, o.secsWithout, o.with, o.without)
                end
                out[#out + 1] = line
            end
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- Recording (a fight probe)
-------------------------------------------------------------------------------

local classSpells   -- the spells that count (your class's), for the fight in progress
local atStart = {}  -- castGUID -> { advice, keySpell, tags } when a cast with a cast time began
local casts = 0     -- casts noted in this fight

local function adviceName(s) return s and (s.spell or s.label or s.item) or nil end

local function keySpell()
    local held = ns.cast and ns.cast.Held and ns.cast:Held()
    return held and held.spell or nil
end

-- The situation right now, for C.Tags.
local function situation(f, advice)
    local E = ns.rotation
    local s = { opening = casts == 0, hurt = E.hurt or 0, attackers = f.maxAttackers or 1 }
    local speed = GetUnitSpeed and A.Safe(GetUnitSpeed("player"))
    s.moving = (speed or 0) > 0
    s.targetCasting = E.TargetCasting() ~= nil
    s.onYou = E.BeingHit()
    local okN, near = pcall(E.Near, "target")
    if okN then s.near = near end
    s.mana = E.ManaShare()
    local hp, max = A.Safe(UnitHealth("target")), A.Safe(UnitHealthMax("target"))
    if hp and max and max > 0 then s.targetHp = hp / max end
    s.shifted = (GetShapeshiftForm and (GetShapeshiftForm() or 0) > 0) or false
    if advice and E:Knows(advice) then
        if UnitExists("target") then s.adviceRange = A.InRange(advice, "target") and true or false end
        s.adviceUsable = A.Usable(advice) and true or false
        s.adviceCooldown = A.Cooldown(advice)
    end
    return s
end

ns:Register("fightProbe", "choices", {
    start = function()
        local _, class = UnitClass("player")
        classSpells = ns:ClassSpellSet(class)
        -- (Racials the rotation advises count too: War Stomp to stop a cast.)
        for _, r in ipairs(ns.rotation.INTERRUPTS or {}) do classSpells[r.spell] = true end
        casts = 0
        wipe(atStart)
    end,
    finish = function()
        classSpells = nil
        C.Trim(db(), C.MAX)
    end,
    events = {
        -- A spell with a cast time: the advice (and the situation) when you
        -- began it, since both move on while you cast.
        UNIT_SPELLCAST_START = function(f, unit, castGUID)
            if unit ~= "player" or not castGUID then return end
            local advice = adviceName(ns.rotation.current)
            atStart[castGUID] = { advice = advice, key = keySpell(), tags = C.Tags(situation(f, advice)) }
        end,
        UNIT_SPELLCAST_SUCCEEDED = function(f, unit, castGUID, spellID)
            if unit ~= "player" or not spellID then return end
            local name = A.SpellInfo(A.Safe(spellID) or 0)
            if not (name and classSpells and classSpells[name]) then return end
            local began = castGUID and atStart[castGUID]
            if castGUID then atStart[castGUID] = nil end
            local advice, key, tags
            if began then
                advice, key, tags = began.advice, began.key, began.tags
            else
                -- An instant: the advice just before it landed (it changes
                -- the moment the spell does).
                advice = ns.rotation.AdviceAt(GetTime(), C.LOOKBACK)
                key = keySpell()
                tags = C.Tags(situation(f, advice))
            end
            local choice = C.Note(db(), name, advice, key, tags, time())
            casts = casts + 1
            if choice then
                f.own = f.own or {}
                f.own[choice] = (f.own[choice] or 0) + 1
            end
        end,
    },
})

ns:OnLoad(function(saved)
    saved.choices = saved.choices or {}
    saved.choices.list = saved.choices.list or {}
    saved.choices.since = saved.choices.since or time()
end)
ns:PerCharacter("choices")   -- one character's fights

ns.commands.choices = function(arg)
    arg = (arg or ""):lower()
    if arg == "reset" then
        local d = db()
        wipe(d.list)
        d.casts, d.kinds, d.since = nil, nil, time()
        ns:Print("forgot your recorded choices")
        return
    end
    local P = ns.profiler
    local value
    if P and P.PrimaryMetric then
        local _, metric = P:PrimaryMetric(ns:LevelingRole())
        value = metric and metric.value
    end
    ns:Print("your casts against Flow's advice (since " .. date("%d %b", db().since or time()) .. "):")
    for _, line in ipairs(C.Report(db(), ns.db.profiler and ns.db.profiler.fights or {}, value)) do print("  " .. line) end
    print("  /flow choices reset")
end

ns:Register("help", "choices", { order = 47, title = "Your choices", lines = {
    "/flow choices: what you cast in fights beside what the easy button advised, and the situations you chose otherwise in.",
    "Flow's rotation is tuned from this (with the diagnostics): a pattern with a reason becomes a rule.",
} })
