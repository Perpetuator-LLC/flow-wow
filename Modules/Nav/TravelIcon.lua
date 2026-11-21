-- The arrow becomes the thing to press: a travel spell or your hearthstone.
--
-- "It tells me to hearth or travel via Teleport: Moonglade, and it would be
-- cool if we could show the Teleport: Moonglade icon in place of the arrow,
-- or a hearthstone, making it clear that is the action and the destination
-- is next; maybe keep the arrow, minimized and offset, if they really want
-- to walk. The user could skip them and go on to the next waypoint."
-- (0.35.223)
--
-- When your next step is a cast away (TravelSpells.lua: N.port) or clearly
-- quicker by hearthstone (Hearth.lua H:Saves), the spell's or the stone's
-- icon stands where the arrow was, and the arrow, half its size, moves to
-- its right and still points the way on foot. The words under it are the
-- arrow's own ("... cast Teleport: Moonglade", "Hearthstone (the Crossroads)
-- is about 4 min quicker").
--
-- Walking instead: Flow menu, Arrow, "Walk there instead" drops the icon for
-- that step (the arrow is the arrow again); the same entry brings it back.
-- Since 0.35.224 your Flow key and a button on the Flow Tracker cast it too
-- (the end of this file).

local _, ns = ...
local N = ns.nav
if not N then return end

N.TRAVEL_ICON = 38
-- "Make the icon for the arrow not look like it is clickable: it looks like a
-- button (to cast) and it opens the arrow dialog" (0.35.302). A square icon
-- in a bright frame is what every action button looks like. So it's round
-- now, like a mark on a map, a little see-through, with a thin ring.
N.TRAVEL_ALPHA = 0.85
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
N.TRAVEL_ARROW_SCALE = 0.5
N.travelSkip = {}   -- [stop key] = true: you chose to walk to it (this session)

-- Pure: what to show in the arrow's place. port: the travel spell that
-- reaches the step (nil: none); saving: seconds the hearthstone saves (nil:
-- not clearly quicker); bind: where it's set; skipped: you chose to walk.
--   -> { kind = "spell" | "hearth", spell, text } or nil
function N.TravelAction(port, saving, bind, skipped)
    if skipped then return nil end
    if port then return { kind = "spell", spell = port, text = "Cast " .. port } end
    if saving then
        return { kind = "hearth", saving = saving, text = "Use your hearthstone" .. (bind and (" (" .. bind .. ")") or "") }
    end
    return nil
end

local HEARTH_ICON = "Interface\\Icons\\INV_Misc_Rune_01"
local function iconOf(act)
    if act.kind == "spell" then
        local _, tex = ns.api.SpellInfo(act.spell)
        return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    return (ns.api.ItemIcon and ns.api.ItemIcon(6948)) or HEARTH_ICON
end

local saves = { key = nil, at = 0 }
local function hearthSaving(key, pt, yards)
    local now = GetTime()
    if saves.key == key and now - saves.at < 3 then return saves.saving, saves.bind end
    saves.key, saves.at, saves.saving, saves.bind = key, now, nil, nil
    local H = ns.hearth
    if H and H.Saves and pt and pt.map and pt.x then
        local ok, saving, bind = pcall(H.Saves, H, pt.map, pt.x, pt.y, yards)
        if ok then saves.saving, saves.bind = saving, bind end
    end
    return saves.saving, saves.bind
end

local function build(frame)
    local t = CreateFrame("Frame", nil, frame)
    t:SetSize(N.TRAVEL_ICON, N.TRAVEL_ICON)
    t:SetPoint("CENTER")
    t:SetAlpha(N.TRAVEL_ALPHA)
    t.edge = t:CreateTexture(nil, "BACKGROUND")
    t.edge:SetTexture(DISC)
    t.edge:SetPoint("TOPLEFT", -1.5, 1.5); t.edge:SetPoint("BOTTOMRIGHT", 1.5, -1.5)
    t.tex = t:CreateTexture(nil, "ARTWORK")
    t.tex:SetAllPoints()
    t.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- Cut round. (A client without masks keeps the square picture and drops
    -- the ring, which would stick out at its sides.)
    if t.CreateMaskTexture and t.tex.AddMaskTexture then
        local mask = t:CreateMaskTexture()
        mask:SetTexture(DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(t.tex)
        t.tex:AddMaskTexture(mask)
        t.mask, t.round = mask, true
    else
        t.edge:Hide()
    end
    -- (No mouse of its own: a click goes to the arrow under it, as always.)
    t:EnableMouse(false)
    t:Hide()
    return t
end

-- Called at each arrow update with the step it leads to. frame: the arrow's.
function N.ShowTravel(frame, key, pt, yards)
    if not (frame and frame.arrow) then return nil end
    local saving, bind = hearthSaving(key, pt, yards)
    local act = N.TravelAction(N.port, saving, bind, N.travelSkip[key])
    -- A crossing done by a cast (0.35.379, Crossings.lua): the step is the cast.
    local cast = ns.crossings and ns.crossings.CastOf and ns.crossings.CastOf(key)
    if cast and not N.travelSkip[key] then act = cast end
    N.travelAct, N.travelKey = act, key
    local arrow = frame.arrow
    if not act then
        if frame.travel and frame.travel:IsShown() then
            frame.travel:Hide()
            arrow:SetScale(1)
            arrow:ClearAllPoints()
            arrow:SetPoint("CENTER")
        end
        return nil
    end
    frame.travel = frame.travel or build(frame)
    local t = frame.travel
    t.tex:SetTexture(iconOf(act))
    local c = ns.theme.route or { 1, 0.82, 0.1 }
    t.edge:SetVertexColor(c[1], c[2], c[3], 0.9)
    -- (Also when the arrow itself was made anew: another arrow style.)
    if not t:IsShown() or t.arrow ~= arrow then
        t:Show()
        t.arrow = arrow
        -- The arrow steps aside, small: the way on foot, if you'd rather.
        arrow:SetScale(N.TRAVEL_ARROW_SCALE)
        arrow:ClearAllPoints()
        arrow:SetPoint("LEFT", t, "RIGHT", 6, 0)
    end
    return act
end

-- You'd rather walk to this step (or want the icon back).
function N.SetTravelSkip(key, skip)
    if not key then return end
    N.travelSkip[key] = skip and true or nil
    saves.at = 0
end

-- The Flow menu's entry (under Arrow), only while there's something to skip
-- or to bring back.
function N.TravelMenuItems()
    local key = N.travelKey
    if not key then return {} end
    if N.travelSkip[key] then
        return { { text = "Show the teleport or hearthstone for this step again",
            func = function() N.SetTravelSkip(key, false) end } }
    end
    local act = N.travelAct
    if not act then return {} end
    return { { text = "Walk there instead (hide \"" .. act.text .. "\" for this step)",
        tip = "The arrow goes back to pointing the way on foot for this step. Flow still plans the route as if you'd travel that way.",
        func = function() N.SetTravelSkip(key, true) end } }
end

-------------------------------------------------------------------------------
-- On your Flow key and on the Flow Tracker (0.35.224)
-------------------------------------------------------------------------------
-- "Can we make the Flow target button become the spell in those cases of
-- hearth or teleport; could we even show it on the Flow Tracker, just like
-- quest item casting?" Out of a fight, with no enemy targeted and nothing
-- else for the key to do, the key casts the travel spell (or uses the
-- hearthstone) that the arrow shows. Both are ten-second casts: moving
-- stops them, so a slip of the finger costs nothing. The same press is a
-- button on that step's row of the Flow Tracker (QuestItems.lua).
-- "Walk there instead" (Flow menu, Arrow) takes it off both for that step.
-- "The Flow key casts your teleport or hearthstone" in Flow Settings
-- (Finding your way) turns both off.

function N.TravelKeyOn() return not (ns.db.actions and ns.db.actions.travel == false) end
function N.TravelOnTracker() return N.TravelKeyOn() and N.travelAct ~= nil end

-- Pure: does the key take it now? act: N.travelAct; goalKey: the step the
-- key's context is about; travelKey: the step the travel step is for.
function N.TravelOnKey(act, goalKey, travelKey, enemy, inCombat, on, stones)
    if on == false or not act or inCombat or enemy then return false end
    if not goalKey or goalKey ~= travelKey then return false end
    if act.kind == "hearth" and (stones or 0) <= 0 then return false end
    return true
end

ns:Register("action", "travel:go", { order = 80, get = function(ctx)
    local act = N.travelAct
    local g = ctx and ctx.goal
    -- (Each answer unwrapped on its own: the game may hide either.)
    local Yes = ns.rotation.Yes
    local enemy = Yes(UnitExists("target"), false) and Yes(UnitCanAttack("player", "target"), false)
    local stones = ns.api.Count and ns.api.Count(6948) or 0
    if not N.TravelOnKey(act, g and g.key, N.travelKey, enemy, InCombatLockdown() and true or false, N.TravelKeyOn(), stones) then return nil end
    if act.kind == "spell" then
        local _, tex = ns.api.SpellInfo(act.spell)
        return { type = "spell", spell = act.spell, unit = "player", icon = tex, label = act.text,
                 reason = "Your next step is a cast away: " .. act.spell .. " takes you there. (Flow menu, Arrow: walk there instead.)" }
    end
    return { type = "item", item = "item:6948", icon = ns.api.ItemIcon and ns.api.ItemIcon(6948) or nil, label = act.text,
             reason = "Your hearthstone is clearly the quicker way to your next step. (Flow menu, Arrow: walk there instead.)" }
end })

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck{ group = "route", label = "The Flow key casts your teleport or hearthstone",
        note = "(when it's the way to your next step)",
        tip = "When your next step is a cast away (Teleport: Moonglade) or clearly quicker by hearthstone, your Flow key casts it, out of a fight "
            .. "and with no enemy targeted, and the Flow Tracker shows a button for it on that step. Off: only the icon by the arrow.",
        get = function() return N.TravelKeyOn() end,
        set = function(on)
            ns.db.actions = ns.db.actions or {}
            ns.db.actions.travel = on and true or false
        end }
end
