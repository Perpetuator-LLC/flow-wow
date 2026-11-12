-- Click casting check: "I click a party member and nothing happens, right
-- click and nothing".
--
-- The game's own Click Casting (the Click Bindings button in the spellbook)
-- lets a mouse button on a unit frame cast a spell instead of targeting. Two
-- of its bindings are the game's defaults: "Target" on the left button and
-- "Open menu" on the right. Bind a spell to the plain left or right button
-- and that default loses its button; move the spell to Shift + click later
-- and the plain button is left with nothing at all: a click on a party frame
-- then does nothing, no error, no message.
--
-- Flow can't (and shouldn't) change the game's click bindings, but it can
-- read them and say so:
--   /flow clicks        what each mouse button does on a unit frame
--   the diagnostics     the same, saved at every /reload
--   Flow Improvements   a line when the plain left or right click does nothing
--   /flow under         what is under the mouse right now (hover the frame that
--                       ignores your clicks first): a name starting with Flow
--                       would be ours, sitting on top of it

local _, ns = ...
local CC = {}
ns.clickCheck = CC

local BUTTON_NAME = { BUTTON1 = "Left button", BUTTON2 = "Right button", BUTTON3 = "Middle button",
                      BUTTON4 = "Button 4", BUTTON5 = "Button 5" }
-- (The game's own numbers: Enum.ClickBindingType and Enum.ClickBindingInteraction.)
local TYPE = { SPELL = 1, MACRO = 2, INTERACTION = 3, PET = 4 }
local INTERACTION = { [1] = "Target", [2] = "Open menu" }

-------------------------------------------------------------------------------
-- Pure parts (the tests pass lists in)
-------------------------------------------------------------------------------

-- What one binding does, in words. spellName(id) -> name.
function CC.What(b, spellName)
    if b.type == TYPE.INTERACTION then return INTERACTION[b.actionID] or ("interaction " .. tostring(b.actionID)) end
    if b.type == TYPE.SPELL then return "casts " .. tostring(spellName and spellName(b.actionID) or b.actionID) end
    if b.type == TYPE.MACRO then return "runs a macro" end
    if b.type == TYPE.PET then return "a pet action" end
    return "nothing"
end

-- The plain (no modifier) left and right buttons: what's wrong with them, as
-- a list of sentences; empty when clicking a unit frame works as usual.
-- bindings: { { type, actionID, button = "BUTTON1", modifiers = 0 }, ... }.
-- An empty list says nothing: a client may not list its defaults.
function CC.Problems(bindings)
    local out = {}
    if type(bindings) ~= "table" or #bindings == 0 then return out end
    local plain, anywhere = {}, {}
    for _, b in ipairs(bindings) do
        if (b.modifiers or 0) == 0 and b.button then plain[b.button] = b end
        if b.type == TYPE.INTERACTION then anywhere[b.actionID] = b end
    end
    local function look(button, id, name)
        local p = plain[button]
        if p and p.type == TYPE.INTERACTION and p.actionID == id then return end
        local has = anywhere[id]
        if not p then
            out[#out + 1] = string.format("A plain %s on a unit frame does nothing: \"%s\" %s.",
                BUTTON_NAME[button]:lower(), name,
                has and "is on another button or needs a modifier" or "has no button at all")
        elseif not has then
            out[#out + 1] = string.format("\"%s\" has no button: your %s does something else on unit frames.",
                name, BUTTON_NAME[button]:lower())
        end
    end
    look("BUTTON1", 1, "Target")
    look("BUTTON2", 2, "Open menu")
    return out
end

CC.FIX = "Fix it in the game's Click Bindings (the button at the top of your spellbook): give \"Target\" the left "
    .. "button and \"Open menu\" the right button again, or press Reset to Default there."

-- The report, as lines. modText(modifiers) -> "Shift + " (or "").
function CC.Report(bindings, spellName, modText)
    local out = {}
    if bindings == nil then
        out[1] = "this client has no click casting for Flow to read."
        return out
    end
    if #bindings == 0 then
        out[1] = "no click bindings listed (the game's defaults: left button targets, right button opens the menu)."
        return out
    end
    for _, b in ipairs(bindings) do
        out[#out + 1] = string.format("%s%s: %s", modText and modText(b.modifiers or 0) or "",
            BUTTON_NAME[b.button] or tostring(b.button), CC.What(b, spellName))
    end
    local problems = CC.Problems(bindings)
    for _, p in ipairs(problems) do out[#out + 1] = "!! " .. p end
    if #problems > 0 then out[#out + 1] = CC.FIX end
    return out
end

-------------------------------------------------------------------------------
-- Reading the game's
-------------------------------------------------------------------------------

-- The game's click bindings, or nil when this client has none to read.
function CC.Read()
    if not (C_ClickBindings and C_ClickBindings.GetProfileInfo) then return nil end
    local ok, list = pcall(C_ClickBindings.GetProfileInfo)
    if not ok or type(list) ~= "table" then return nil end
    local out = {}
    for _, b in ipairs(list) do
        out[#out + 1] = { type = b.type, actionID = b.actionID, button = b.button, modifiers = b.modifiers or 0 }
    end
    return out
end

local function modText(mods)
    if mods == 0 then return "" end
    if C_ClickBindings and C_ClickBindings.GetStringFromModifiers then
        local ok, s = pcall(C_ClickBindings.GetStringFromModifiers, mods)
        if ok and type(s) == "string" and s ~= "" then return (s:gsub("%-+$", "")) .. " + " end
    end
    return "modifier " .. tostring(mods) .. " + "
end

local function spellName(id) return (ns.api.SpellInfo(id or 0)) end

ns.commands.clicks = function()
    ns:Print("clicks on unit frames (party, player, target):")
    for _, line in ipairs(CC.Report(CC.Read(), spellName, modText)) do print("  " .. line) end
end

-- What's under the mouse right now, the frame that would get the click
-- first (a hand-made /fstack whose answer goes into the diagnostics). Hover
-- the thing that ignores your clicks, then type /flow under.
function CC.Under()
    local frames = {}
    if GetMouseFoci then
        local ok, foci = pcall(GetMouseFoci)
        if ok and type(foci) == "table" then for _, f in ipairs(foci) do frames[#frames + 1] = f end end
    elseif GetMouseFocus then
        local ok, f = pcall(GetMouseFocus)
        if ok and f then frames[1] = f end
    end
    local out = {}
    for _, f in ipairs(frames) do
        local ok, name = pcall(function()
            return (f.GetDebugName and f:GetDebugName()) or (f.GetName and f:GetName()) or "a frame with no name"
        end)
        out[#out + 1] = ok and tostring(name) or "a frame Flow may not look at"
    end
    return out
end

ns.commands.under = function()
    local names = CC.Under()
    local line = #names > 0 and table.concat(names, "  >  ") or "nothing that takes clicks (the game world)"
    ns:Print("under the mouse: " .. line)
    ns:Log("under", line)
end

-- Flow Improvements: only when a plain click is dead.
ns:Register("advisor", "clickBindings", {
    check = function()
        local problems = CC.Problems(CC.Read())
        if #problems == 0 then return {} end
        return { { importance = 85, text = problems[1] .. " " .. CC.FIX, improves = { "Group play" } } }
    end,
})

ns:Register("help", "clicks", { order = 49, title = "Clicks on unit frames", lines = {
    "/flow clicks: what each mouse button does on a party or player frame (the game's Click Bindings), and whether a plain click still targets.",
    "/flow under: what is under the mouse right now (hover a frame that ignores your clicks first).",
} })
