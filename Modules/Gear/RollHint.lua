-- Need or Greed? Flow's verdict on the loot roll window.
--
-- "When loot drops in a dungeon it would be nice to have our upgrade
-- indicators, like in our inventory and at vendors, so I can easily tell if
-- I should roll Need or Greed." (0.35.212)
--
-- The same verdict as the bag icons (Gear/Score.lua: at least +0.5 for your
-- levelling role, and something you can wear): a line on the game's roll
-- window, green "Flow: upgrade +2.1: Need" or grey "Flow: not an upgrade:
-- Greed", and for an upgrade one line in chat too, since the roll window can
-- be gone in a moment. Flow never rolls for you.
--
-- Flow only adds a line of text to the game's window: it doesn't move, show,
-- hide or click anything of it. "Roll hints" in Flow Settings (In a group)
-- turns it off. /flow roll <item link> says the verdict for any item.

local _, ns = ...
local R = {}
ns.rollHint = R

R.MIN_GAIN = 0.5   -- as the bag icons: below this it isn't called an upgrade

function R.On() return not (ns.db.gear and ns.db.gear.rollHints == false) end

-- Pure: the verdict. cmp: ns.gear:Compare's ({ canUse, diffs = { [role] = n } })
-- or nil (not gear, or not loaded). -> { roll = "need" | "greed", text, r, g, b } or nil.
function R.Verdict(cmp, role, minGain)
    if not cmp then return nil end
    if not cmp.canUse then
        return { roll = "greed", text = "you can't wear it: Greed", r = 0.7, g = 0.7, b = 0.7 }
    end
    local gain = cmp.diffs and cmp.diffs[role or "dps"]
    if gain and gain >= (minGain or R.MIN_GAIN) then
        return { roll = "need", text = string.format("upgrade +%.1f: Need", gain), gain = gain, r = 0.3, g = 1, b = 0.3 }
    end
    return { roll = "greed", text = "not an upgrade: Greed", r = 0.7, g = 0.7, b = 0.7 }
end

function R.For(link)
    if not (link and ns.gear and ns.gear.Compare) then return nil end
    local ok, cmp = pcall(ns.gear.Compare, ns.gear, link)
    if not ok then return nil end
    return R.Verdict(cmp, ns.LevelingRole and ns:LevelingRole() or "dps")
end

-- The game's roll windows showing this roll (GroupLootFrame1..4 on this
-- kind of client; a container's children on newer ones).
local function framesFor(rollID)
    local out = {}
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        local f = _G["GroupLootFrame" .. i]
        if f and f.rollID == rollID then out[#out + 1] = f end
    end
    local c = _G.GroupLootContainer
    if #out == 0 and c and c.GetChildren then
        for _, f in ipairs({ c:GetChildren() }) do
            if f.rollID == rollID then out[#out + 1] = f end
        end
    end
    return out
end

-- The green arrow of the bag icons, on the roll window's item (0.35.275: "it
-- would be nice to see the icon too, so when I click roll I see it right
-- there"), with how much better beside it. Only for an upgrade.
R.ARROW = 22
-- Pure: does this verdict get the arrow, and its figure ("+2.1").
function R.ArrowFor(v)
    if not (v and v.roll == "need") then return false, "" end
    return true, v.gain and string.format("+%.1f", v.gain) or ""
end
local function arrow(f, v)
    local show, gain = R.ArrowFor(v)
    if not f.FlowRollArrow then
        if not show then return end
        local host = f.IconFrame or f
        local a = f:CreateTexture(nil, "OVERLAY", nil, 7)
        a:SetSize(R.ARROW, R.ARROW)
        a:SetPoint("TOPLEFT", host, "TOPLEFT", -6, 6)
        local ok = a.SetAtlas and pcall(a.SetAtlas, a, "bags-greenarrow")
        if not ok then a:SetColorTexture(0.2, 1, 0.2, 0.9); a:SetSize(10, 10) end
        f.FlowRollArrow = a
        local g = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        g:SetPoint("LEFT", a, "RIGHT", -2, 0)
        g:SetTextColor(0.3, 1, 0.3)
        f.FlowRollGain = g
    end
    f.FlowRollArrow:SetShown(show)
    f.FlowRollGain:SetText(gain)
end
R._arrow = arrow   -- (tests)

local function mark(f, v)
    pcall(arrow, f, v)
    if not f.FlowRollHint then
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("BOTTOM", f, "TOP", 0, 2)
        f.FlowRollHint = t
    end
    f.FlowRollHint:SetText(v and ("Flow: " .. v.text) or "")
    if v then f.FlowRollHint:SetTextColor(v.r, v.g, v.b) end
end

R.said = {}   -- [rollID] = true: the chat line went out
local function onRoll(rollID)
    if not R.On() or not GetLootRollItemLink then return end
    local link = GetLootRollItemLink(rollID)
    local v = R.For(link)
    ns:Log("gear", string.format("loot roll %s: %s -> %s", tostring(rollID), tostring(link), v and v.text or "no verdict (not gear, or not loaded yet)"))
    for _, f in ipairs(framesFor(rollID)) do pcall(mark, f, v) end
    if v and v.roll == "need" and not R.said[rollID] then
        R.said[rollID] = true
        ns:Print(string.format("%s is an upgrade for you (+%.1f): Flow suggests Need. (It never rolls for you.)", tostring(link), v.gain or 0))
    end
end
ns:On("START_LOOT_ROLL", function(rollID)
    rollID = ns.api.Safe(rollID)
    if not rollID then return end
    -- (The window fills a moment after the event; the item may load later still.)
    for _, wait in ipairs({ 0.1, 1 }) do
        if C_Timer then C_Timer.After(wait, function() pcall(onRoll, rollID) end) end
    end
end)

ns.commands.roll = function(arg)
    local link = (arg or ""):match("(|c.-|h|r)") or (arg or ""):match("(|H.-|h.-|h)")
    if not link then ns:Print("/flow roll <shift-click an item>: is it an upgrade for you (Need) or not (Greed)? Flow only says; it never rolls.") return end
    local v = R.For(link)
    ns:Print(link .. ": " .. (v and v.text or "not gear Flow can judge (or not loaded yet)"))
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "group",
        label = "Roll hints: Need or Greed on loot rolls",
        tip = "When a roll comes up, Flow writes on the roll window whether the item is an upgrade for you (Need) or not (Greed), "
            .. "by the same scores as the icons in your bags. It never rolls for you.",
        get = function() return R.On() end,
        set = function(on)
            ns.db.gear = ns.db.gear or {}
            ns.db.gear.rollHints = on and true or false
        end,
    })
end
