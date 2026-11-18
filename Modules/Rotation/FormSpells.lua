-- Which spells take you out of a form (0.35.319).
--
-- "As I'm setting up my action bars, there's a lot of spells that will
-- change my form back to human, and there's a lot of spells that won't.
-- Faerie Fire does not change my form, but casting any of the heals seems
-- to change my form. Is there a clear way for me to know which ones will
-- and will not?"
--
-- The game doesn't say it of a spell, so Flow watches what happens: you cast
-- a spell in Bear Form and you're still in Bear Form after, the spell keeps
-- that form; the form drops as you cast it, the spell takes you out of it.
-- A form's own abilities (Maul and Bash in Bear Form: the class list's
-- `needs`) keep it from the start. A spell's tooltip (on your bars, in the
-- spellbook) then says "Flow: keeps you in Bear Form" or "Flow: takes you
-- out of Bear Form", or that Flow hasn't seen it cast in a form yet; and
-- /flow forms lists them all.
--
-- Kept for the whole account, by class (FlowDB.facts.forms): game facts
-- only, a class, a spell and a form. Only for classes whose rotation says
-- `shapeshifts = true` (the druid).

local _, ns = ...
local A = ns.api
local FS = {}
ns.formSpells = FS

FS.WINDOW = 1.0   -- seconds between a cast and its form dropping that belong together

ns:OnLoad(function(saved)
    saved.facts = saved.facts or {}
    saved.facts.forms = saved.facts.forms or {}
end)

local function myClass()
    local _, class = UnitClass("player")
    return ns.api.Safe(class)
end
-- Does this class shift? (Its rotation registration says so.)
function FS.Shifts(class)
    local rot = class and ns:Get("rotation", class)
    return rot ~= nil and rot.shapeshifts == true
end
-- This class's record: { [spell] = { keep = { [form] = true }, out = { [form] = true } } }.
function FS.Store(class)
    class = class or myClass()
    if not (class and ns.db and ns.db.facts) then return nil end
    ns.db.facts.forms = ns.db.facts.forms or {}
    ns.db.facts.forms[class] = ns.db.facts.forms[class] or {}
    return ns.db.facts.forms[class]
end

-- Pure: notes what a cast did. store: FS.Store's table; kept: still in the
-- form after it. -> true when it's news.
function FS.Note(store, spell, form, kept)
    if not (store and type(spell) == "string" and type(form) == "string") then return false end
    local r = store[spell] or {}
    store[spell] = r
    local side = kept and "keep" or "out"
    r[side] = r[side] or {}
    if r[side][form] then return false end
    r[side][form] = true
    -- (Seen both ways in one form: the latest wins; the game can change.)
    local other = kept and "out" or "keep"
    if r[other] then r[other][form] = nil end
    return true
end

-- The form abilities of the class list: { [spell] = form } (Maul = Bear Form).
function FS.FormAbilities(class)
    local out = {}
    for _, s in ipairs(ns:Get("classSpells", class or myClass() or "") or {}) do
        if s.spell and type(s.needs) == "string" and s.needs:find(" Form$") then out[s.spell] = s.needs end
    end
    return out
end

-- Pure: what a spell's tooltip says. rec: its record (or nil); ability: the
-- form it belongs to (or nil). -> text, r, g, b (nil when nothing to say).
local function names(set)
    local list = {}
    for f in pairs(set or {}) do list[#list + 1] = f end
    table.sort(list)
    if #list <= 1 then return list[1] end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end
function FS.Words(rec, ability)
    local keep = rec and names(rec.keep)
    local out = rec and names(rec.out)
    if out and keep then return string.format("Flow: takes you out of %s; keeps you in %s", out, keep), 1, 0.6, 0.2 end
    if out then return string.format("Flow: takes you out of %s", out), 1, 0.6, 0.2 end
    if keep then return string.format("Flow: keeps you in %s", keep), 0.4, 1, 0.4 end
    if ability then return string.format("Flow: a %s ability (keeps you in it)", ability), 0.4, 1, 0.4 end
    return "Flow: not seen cast in a form yet (Flow learns it the first time you do)", 0.6, 0.6, 0.6
end

-------------------------------------------------------------------------------
-- Watching. Flow's own functions, fed by the game's events below (the tests
-- call them with forms and times of their own).
-------------------------------------------------------------------------------

FS.pending = nil   -- { spell, form, at }: a cast sent while in a form
FS.dropped = nil   -- { form, at }: the form you were in, and when it went
local function isFormSpell(spell)
    for _, s in ipairs(A.StanceSpells and A.StanceSpells() or {}) do
        if s.name == spell then return true end
    end
    return spell == "Cancel Form"
end
FS._isFormSpell = isFormSpell

local function record(spell, form, kept)
    local store = FS.Store()
    if FS.Note(store, spell, form, kept) then
        ns:Log("forms", string.format("%s %s %s", spell, kept and "keeps you in" or "takes you out of", form))
    end
end

-- A cast was sent: the form you're in now (nil: none).
function FS.Sent(spell, form, now)
    if type(spell) ~= "string" or isFormSpell(spell) then return end
    -- The form may already have dropped as the cast went out.
    if not form and FS.dropped and now - FS.dropped.at <= FS.WINDOW then
        record(spell, FS.dropped.form, false)
        FS.dropped = nil
        return
    end
    if form then FS.pending = { spell = spell, form = form, at = now } end
end
-- Your form changed from `from` to `to`.
function FS.FormChanged(from, to, now)
    if not from or from == to then return end
    local p = FS.pending
    if p and p.form == from and now - p.at <= FS.WINDOW then
        record(p.spell, from, false)
        FS.pending = nil
        return
    end
    FS.dropped = { form = from, at = now }
end
-- A cast went off (or began): the form you're in now.
function FS.Cast(spell, form, now)
    local p = FS.pending
    if not (p and p.spell == spell) then return end
    if now - p.at > FS.WINDOW * 4 then FS.pending = nil return end
    if form == p.form then
        record(spell, form, true)
        FS.pending = nil
    end
end

local formNow
local function watching() return FS.Shifts(myClass()) end
ns:On("PLAYER_LOGIN", function() formNow = A.Form() end)
ns:On("UPDATE_SHAPESHIFT_FORM", function()
    if not watching() then return end
    local f = A.Form()
    if f ~= formNow then FS.FormChanged(formNow, f, GetTime()) end
    formNow = f
end)
local function spellOf(id)
    id = A.Safe(id)
    local name = id and A.SpellInfo(id)
    return type(name) == "string" and name or nil
end
ns:On("UNIT_SPELLCAST_SENT", function(unit, _, _, spellID)
    if unit ~= "player" or not watching() then return end
    local spell = spellOf(spellID)
    if spell then FS.Sent(spell, A.Form(), GetTime()) end
end)
for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED" }) do
    ns:On(ev, function(unit, _, spellID)
        if unit ~= "player" or not watching() then return end
        local spell = spellOf(spellID)
        if spell then FS.Cast(spell, A.Form(), GetTime()) end
    end)
end

-------------------------------------------------------------------------------
-- The tooltip line, and /flow forms.
-------------------------------------------------------------------------------

-- The line for a spell, for your class: text, r, g, b; nil for a form
-- spell itself, or a class that doesn't shift.
function FS.LineFor(spell)
    local class = myClass()
    if type(spell) ~= "string" or not FS.Shifts(class) or isFormSpell(spell) then return nil end
    local store = FS.Store(class) or {}
    return FS.Words(store[spell], FS.FormAbilities(class)[spell])
end
local function addLine(tt, spell)
    local text, r, g, b = FS.LineFor(spell)
    if text then tt:AddLine(text, r, g, b, true) end
end
FS._addLine = addLine   -- (tests)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tt, data)
        if tt ~= GameTooltip then return end
        local id = data and A.Safe(data.id)
        local spell = id and A.SpellInfo(id)
        if type(spell) == "string" then pcall(addLine, tt, spell) end
    end)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetSpell", function(tt)
        local ok, spell = pcall(tt.GetSpell, tt)
        spell = ok and A.Safe(spell) or nil
        if type(spell) == "string" then pcall(addLine, tt, spell) end
    end)
end

function FS.Lines()
    local class = myClass()
    if not FS.Shifts(class) then return { "forms: your class doesn't shift form" } end
    local store = FS.Store(class) or {}
    local keep, out = {}, {}
    for spell, r in pairs(store) do
        for form in pairs(r.out or {}) do out[#out + 1] = spell .. " (" .. form .. ")" end
        for form in pairs(r.keep or {}) do keep[#keep + 1] = spell .. " (" .. form .. ")" end
    end
    table.sort(keep); table.sort(out)
    local lines = { "forms: what Flow has seen your spells do (cast one in a form and it's learned)" }
    lines[#lines + 1] = "  takes you out of the form: " .. (#out > 0 and table.concat(out, ", ") or "none seen yet")
    lines[#lines + 1] = "  keeps you in it: " .. (#keep > 0 and table.concat(keep, ", ") or "none seen yet")
    local abil = {}
    for spell, form in pairs(FS.FormAbilities(class)) do abil[#abil + 1] = spell .. " (" .. form .. ")" end
    table.sort(abil)
    if #abil > 0 then lines[#lines + 1] = "  form abilities (keep it): " .. table.concat(abil, ", ") end
    return lines
end
ns.commands.forms = function()
    for i, l in ipairs(FS.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end
