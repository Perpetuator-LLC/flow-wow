-- The easy button's queue: four things on one key. The big icon is what
-- your key casts; beside it, each a little smaller, what the key casts with
-- a modifier held, the modifier written above it:
--   CTRL   your second attack (Moonfire while the key casts Wrath); between
--          fights the next way to heal up (food while the key bandages), or
--          the same heal or buff on your friendly target
--   SHIFT  your quickest heal, on you
--   ALT    your healthstone or healing potion; without one, the spell that
--          holds or stops your target (Entangling Roots)
-- Hold a modifier and the big icon becomes that spell. In a fight the game
-- lets no add-on change what a key casts, so all four are set before the
-- pull and stay for the fight; Flow lights the one to press now.
--
-- Why: you play on the key. In one evening's combat log, of 221 casts none
-- was Moonfire though Flow advised it all night (it was only on the bar),
-- and in one death a heal was advised 65 times with Shift + key never
-- pressed. A spell that isn't on the key doesn't get cast.
--
-- A class says what its fights use (rotation definition):
--   fightKeys = function(engine) return { ctrl = { "Moonfire" },
--       alt = { "Entangling Roots", "War Stomp" } } end
-- (first one you know, never the key's own spell). Without it, Ctrl takes
-- the class's next attack in priority order.
-- The secure side (attributes, bindings) is in Cast.lua.

local _, ns = ...
local E = ns.rotation
local Q = {}
ns.queue = Q

Q.ORDER = { "ctrl", "shift", "alt" }                          -- slots 2, 3, 4
Q.LABEL = { ctrl = "CTRL", shift = "SHIFT", alt = "ALT" }     -- written above them

local function helpful(s) return s and s.spell and (s.kind == "buff" or s.kind == "heal" or s.kind == "emergency") end

-- The same press? (the same spell on the same unit, or the same item)
function Q.Same(a, b)
    if not (a and b) then return false end
    if a.item or b.item then return a.item ~= nil and a.item == b.item end
    return a.spell ~= nil and a.spell == b.spell and (a.unit or "") == (b.unit or "")
end

-- A class without fightKeys: its attacks on a target, in priority order.
function Q.Attacks(def)
    local out, seen = {}, {}
    for _, r in ipairs(def and def.priority or {}) do
        if r.target and r.kind ~= "buff" and not seen[r.spell] and r.spell ~= "Attack" and r.spell ~= "Auto Attack" then
            seen[r.spell] = true
            out[#out + 1] = r.spell
        end
    end
    return out
end

-- The fight's second attack (Ctrl) and its hold-or-stop spell (Alt): the
-- first of each list you know that isn't what the key itself casts.
-- knows(spell) -> bool; keySpell: what the key holds (or will) in a fight.
function Q.FightSpells(def, knows, keySpell, engine)
    local keys = def and def.fightKeys and def.fightKeys(engine) or nil
    local function first(list, skip)
        for _, spell in ipairs(list or {}) do
            if spell ~= keySpell and spell ~= skip and knows(spell) then return spell end
        end
    end
    local ctrl = first(keys and keys.ctrl or Q.Attacks(def))
    local alt = first(keys and keys.alt, ctrl)
    return ctrl, alt
end

-- The four slots, from plain values (the tests pass their own).
--   main: what the key does now (the suggestion; in a fight its locked spell)
--   o.heal        Shift's heal spell (nil: none known, or switched off)
--   o.emergency   "item:123", your healthstone or potion (nil: none carried)
--   o.ctrlSpell, o.altSpell   the fight's spells (Q.FightSpells)
--   o.friend      a friendly target that isn't you, and Ctrl may cast on it
--   o.options     other ways to heal up right now (E:RecoverOptions, without main)
-- Returns { key, ctrl, shift, alt }: each a step ({ spell | item, kind, unit,
-- reason }) or nil.
function Q.Slots(main, o)
    o = o or {}
    local shift = o.heal and { spell = o.heal, kind = "heal", unit = "player", reason = "Your quickest heal, on you" } or nil
    local ctrl, alt
    if o.emergency then
        alt = { type = "item", item = o.emergency, kind = "emergency", reason = "Your healthstone or healing potion" }
    end
    if o.friend and helpful(main) then
        ctrl = { spell = main.spell, kind = main.kind, unit = "target", reason = main.spell .. " on your target" }
    end
    -- Hurt between fights: the other ways to heal up, in your order. Ctrl
    -- first, then Alt when no healthstone holds it. (Shift already heals.)
    for _, s in ipairs(o.options or {}) do
        if not (shift and s.spell == shift.spell) and not Q.Same(s, main) then
            if not ctrl then ctrl = s elseif not alt then alt = s end
        end
    end
    if not ctrl and o.ctrlSpell then ctrl = { spell = o.ctrlSpell, kind = "damage", reason = "Your second attack" } end
    if not alt and o.altSpell then alt = { spell = o.altSpell, kind = "damage", reason = "Holds or stops your target" } end
    return { key = main, ctrl = ctrl, shift = shift, alt = alt }
end

-- Which press does what Flow advises: "key", "ctrl", "shift", "alt", or nil
-- (none of them: it's on your bar). Any heal spell advised counts as Shift:
-- Shift + key heals you, if not with that very spell.
function Q.AdviceSlot(advice, slots)
    if not (advice and slots) then return nil end
    for _, name in ipairs({ "key", "ctrl", "shift", "alt" }) do
        local s = slots[name]
        if s and ((s.item and s.item == advice.item) or (s.spell and s.spell == advice.spell)) then return name end
    end
    if slots.shift and advice.spell and (advice.kind == "heal" or advice.kind == "emergency") then return "shift" end
    return nil
end

-- The one modifier held ("ctrl", "shift", "alt"), or nil: none, or several
-- (Ctrl + Shift + key is no slot).
function Q.HeldMod(ctrl, shift, alt)
    local n = (ctrl and 1 or 0) + (shift and 1 or 0) + (alt and 1 or 0)
    if n ~= 1 then return nil end
    return (ctrl and "ctrl") or (shift and "shift") or "alt"
end

-- Holding a modifier: the big icon becomes that slot's step (while the key
-- would do anything at all: in a fight, or with something to press).
-- Returns the view and the modifier that swapped in (nil: none).
function Q.ModView(view, slots, mod, inCombat)
    local step = mod and slots and slots[mod]
    if not (step and (view or inCombat)) then return view, nil end
    local out = { kind = step.kind, mod = mod }
    for k, v in pairs(step) do out[k] = v end
    out.label = Q.LABEL[mod] .. " + key: " .. tostring(step.spell or step.label or "your item")
    return out, mod
end

-- Is the queue worth showing? In a fight, with an enemy targeted, while you
-- heal up, or while you hold a modifier to see what it would cast. Not while
-- idle: three more icons for nothing would be clutter.
function Q.Shows(main, inCombat, hostile, mod)
    if inCombat or hostile or mod then return true end
    return main ~= nil and main.kind == "heal"
end

-- What the slots are right now (reads the game). locked: the spell the key
-- holds for the fight that is starting or on (nil out of one: the class's
-- pull lock says what it will hold).
function Q.Now(main, locked)
    local def = E:Definition()
    local C = ns.cast
    local keySpell = locked
    if not keySpell and def and def.pullLock then
        local ok, spell = pcall(def.pullLock, nil, E)
        if ok then keySpell = spell end
    end
    local ctrlSpell, altSpell = Q.FightSpells(def, function(spell) return E:Knows(spell) end, keySpell, E)
    local options
    local ctx = E.lastCtx
    if not locked and not InCombatLockdown() and main and main.kind == "heal" and def and ctx then
        local ok, list = pcall(E.RecoverOptions, E, ctx, def)
        if ok then options = list end
    end
    local friend = false
    if ns.db.cast.ctrlTarget ~= false and UnitExists("target") then
        friend = E.Yes(UnitIsFriend("player", "target"), false) and not E.Yes(UnitIsUnit("target", "player"), false)
    end
    return Q.Slots(main, {
        heal = C and C.HealSpell and C:HealSpell() or nil,
        emergency = C and C.EmergencyItem and C:EmergencyItem() or nil,
        ctrlSpell = ctrlSpell, altSpell = altSpell, friend = friend, options = options,
    })
end
