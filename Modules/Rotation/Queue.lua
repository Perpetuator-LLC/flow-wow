-- The easy button's queue: four things on one key. The big icon is what
-- your key casts; beside it, each a little smaller, what the key casts with
-- a modifier held, the modifier written above it:
--   CTRL   your second attack (Moonfire while the key casts Wrath); between
--          fights the next way to heal up (food while the key bandages), or
--          the same heal or buff on your friendly target
--   SHIFT  your quickest heal, on you
--   ALT    your healthstone or healing potion; without one, the spell that
--          holds or stops your target (Entangling Roots)
--   C+S    (Ctrl and Shift together) another spell Flow may advise in the
--          fight that none of the above casts (Nature's Grasp): its advice
--          pulses on a slot you can press, not only on your action bar
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

-- "more" (0.35.194): Ctrl + Shift + key, for another spell Flow may advise in
-- the fight. The advice the key can't cast used to be a little icon in the
-- corner of the big one, to press from your action bar: "can the little icon
-- be in a modifier spot, so the user connects it with the modifier and hits
-- it to cast?" In a fight no slot can change, so the likeliest advice gets
-- a slot before the pull; when Flow advises it, that slot pulses.
-- The order of the icons beside the big one, nearest first: Shift, then Ctrl
-- (0.35.227: "swap the SHIFT and CTRL but leave the spells there": the
-- spell nearest the key is Shift's now, the next one Ctrl's).
Q.ORDER = { "shift", "ctrl", "alt", "more" }                              -- slots 2, 3, 4, 5
Q.LABEL = { ctrl = "CTRL", shift = "SHIFT", alt = "ALT", more = "C+S" }   -- written above them
Q.NAME = { ctrl = "CTRL", shift = "SHIFT", alt = "ALT", more = "CTRL + SHIFT" }   -- in a sentence

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
    -- Shift, for when your heal lives on the second key (CareKeys.lua): the
    -- class's shift list, never what Ctrl or Alt already cast.
    local shift
    for _, spell in ipairs(keys and keys.shift or {}) do
        if spell ~= keySpell and spell ~= ctrl and spell ~= alt and knows(spell) then shift = spell break end
    end
    return ctrl, alt, shift
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
    if not ctrl and o.ctrlSpell then ctrl = { spell = o.ctrlSpell, kind = "damage", reason = "Your second spell for the fight" } end
    if not alt and o.altSpell then alt = { spell = o.altSpell, kind = "damage", reason = "Your third spell for the fight" } end
    -- (Only without a heal on Shift: it moved to the second key.)
    if not shift and o.shiftSpell then shift = { spell = o.shiftSpell, kind = "damage", reason = "Your fourth spell for the fight" } end
    -- Ctrl + Shift: the first of the fight's other spells (o.more, in the
    -- class's order) that no other press already casts.
    local taken = {}
    if o.keySpell then taken[o.keySpell] = true end
    for _, s in pairs({ main = main, ctrl = ctrl, shift = shift, alt = alt }) do
        if s.spell then taken[s.spell] = true end
    end
    local more
    for _, spell in ipairs(o.more or {}) do
        if not taken[spell] then
            more = { spell = spell, kind = "damage", reason = "Another spell Flow may ask for in this fight" }
            break
        end
    end
    -- Your second attack is the nearest icon, which is Shift's: so it goes on
    -- Shift and what Shift had goes on Ctrl. Not while Shift is your heal
    -- ("Shift + key heals" stays true where the heal lives on this key).
    if not (shift and shift.kind == "heal") then ctrl, shift = shift, ctrl end
    local out = { key = main, ctrl = ctrl, shift = shift, alt = alt, more = more }
    return Q.NoRepeats(out, o.keySpell)
end

-- Pure: no spell on two presses ("Bash is showing as 2 of my spells on the
-- easy button: we should never allow a duplicate"). The key first, then the
-- icons in their order; a later press that would cast the same spell on the
-- same unit is left empty. (The same spell on another unit is another
-- press: your buff on you, and on your friendly target.)
function Q.NoRepeats(slots, keySpell)
    local seen = {}
    local function id(s) return s and s.spell and (s.spell .. "@" .. tostring(s.unit or "")) or nil end
    if keySpell then seen[keySpell .. "@"] = true end
    local k = id(slots.key)
    if k then seen[k] = true end
    for _, name in ipairs(Q.ORDER) do
        local key = id(slots[name])
        if key then
            if seen[key] then slots[name] = nil else seen[key] = true end
        end
    end
    return slots
end

-- The fight's other spells, for Ctrl + Shift: the ones you know, in the
-- class's order (fightKeys().more, else its Alt list, then its Ctrl list,
-- then its attacks).
function Q.MoreList(def, knows, engine)
    local keys = def and def.fightKeys and def.fightKeys(engine) or nil
    local out, seen = {}, {}
    local function add(list)
        for _, spell in ipairs(list or {}) do
            if not seen[spell] and knows(spell) then
                seen[spell] = true
                out[#out + 1] = spell
            end
        end
    end
    if keys and keys.more then add(keys.more) end
    add(keys and keys.alt)
    add(keys and keys.ctrl)
    add(Q.Attacks(def))
    return out
end

-- Which press does what Flow advises: "key", "ctrl", "shift", "alt", or nil
-- (none of them: it's on your bar). Any heal spell advised counts as Shift:
-- Shift + key heals you, if not with that very spell.
function Q.AdviceSlot(advice, slots)
    if not (advice and slots) then return nil end
    for _, name in ipairs({ "key", "ctrl", "shift", "alt", "more" }) do
        local s = slots[name]
        if s and ((s.item and s.item == advice.item) or (s.spell and s.spell == advice.spell)) then return name end
    end
    if slots.shift and slots.shift.kind == "heal" and advice.spell and (advice.kind == "heal" or advice.kind == "emergency") then return "shift" end
    return nil
end

-- The slot whose modifiers are held: "ctrl", "shift", "alt", or "more" for
-- Ctrl + Shift together; nil for none, or any other combination.
function Q.HeldMod(ctrl, shift, alt)
    if ctrl and shift and not alt then return "more" end
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
    out.label = Q.NAME[mod] .. " + key: " .. tostring(step.spell or step.label or "your item")
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
    local ctrlSpell, altSpell, shiftSpell = Q.FightSpells(def, function(spell) return E:Knows(spell) end, keySpell, E)
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
        ctrlSpell = ctrlSpell, altSpell = altSpell, shiftSpell = shiftSpell, friend = friend, options = options,
        keySpell = keySpell, more = Q.MoreList(def, function(spell) return E:Knows(spell) end, E),
    })
end
