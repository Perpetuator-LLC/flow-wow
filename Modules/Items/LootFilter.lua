-- "Leave junk behind when looting" (off by default). The game's Auto Loot
-- takes everything and can't skip grey items, so while this is on Flow does
-- the auto-looting instead: it takes everything except grey (junk) items,
-- money and quest items always, and closes the window when only junk is
-- left. The game's own Auto Loot is switched off meanwhile and put back as it
-- was when you turn this off. Hold your auto-loot key (Shift) to loot by hand.
-- /flow settings, or /flow loot junk|nojunk.
--
-- Opening the same corpse again leaves the window open (0.35.320: "I'm trying
-- to loot and it just opens the loot window and immediately closes"). The
-- junk Flow left keeps the corpse sparkling, so you open it again, and Flow
-- shut it every time, before you could take anything. Now it closes the
-- window only the first time it looks at a corpse; open it again and the
-- window stays, for you to take the junk or anything else by hand. The first
-- time it leaves junk in a session, it says so in chat, and each time a short
-- note by your cursor names what it left.
--
-- With Skinning, this is a poor fit ("the fact that it left junk on them
-- means I can't skin them"): the game lets you skin a corpse only once
-- nothing is left on it. Flow doesn't work round it; it says so, when you
-- turn this on while you have Skinning, and once (for the account) when it
-- was already on and you have Skinning (L.SkinWarning).

local _, ns = ...
local L = {}
ns.lootFilter = L

function L.Enabled() return ns.db.loot.skipJunk == true end

-- Take this slot? Junk (grey items) stays; money, currency and quest items
-- are always taken; locked slots (someone else's roll) are left alone. A
-- value the game hides is unwrapped first (nil): an item whose quality Flow
-- can't read is taken, never left as junk.
-- skin (0.35.429): it's a corpse you can skin, so its junk is taken too (a
-- corpse can only be skinned once it's empty).
function L.Take(slotType, quality, isQuestItem, locked, skin)
    local Safe = ns.api and ns.api.Safe or function(v) return v end
    if Safe(locked) then return false end
    if Safe(isQuestItem) then return true end
    if skin then return true end
    local ITEM = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or LOOT_SLOT_ITEM or 1
    if Safe(slotType) == ITEM and Safe(quality) == 0 then return false end
    return true
end

-- Pure: close the window? Only junk is left, and this is the first look at
-- this corpse (seen: the corpses Flow already closed, by their source).
function L.ShouldClose(left, junk, source, seen)
    if not (left > 0 and left == junk) then return false end
    if source and seen and seen[source] then return false end
    return true
end
-- Pure: the words by your cursor when Flow closes the window ("it just is
-- weird that it opens and closes immediately ... can we make it more
-- intuitive why it's closing"): what it left, by name.
function L.JunkWords(names)
    names = names or {}
    local shown = {}
    for i = 1, math.min(2, #names) do shown[i] = names[i] end
    local list = #shown > 0 and table.concat(shown, ", ") or "grey items"
    if #names > 2 then list = list .. string.format(" and %d more", #names - 2) end
    return "Flow left the junk: " .. list, "(open it again to take it)"
end
L.NOTE_SECONDS = 2.5

-- Pure: the warning for a skinner, or nil. on: the setting; hasSkinning: you
-- have the profession.
L.SKIN_WARNING = "with \"Leave junk behind when looting\" on, Flow still takes the junk from a corpse you can skin "
    .. "(a dead beast you're looting), since the game lets you skin only an empty corpse. Other corpses keep their junk."
function L.SkinWarning(on, hasSkinning)
    if on and hasSkinning then return L.SKIN_WARNING end
    return nil
end
local function hasSkinning() return (ns.api.Skill and ns.api.Skill("Skinning")) ~= nil end
-- Pure: is the corpse you're looting one you'd skin? You have Skinning, your
-- target is dead, it's a kind that has a hide, and it's the corpse the loot
-- is from (source nil: can't tell, taken as yes).
L.SKINNED = { Beast = true, Dragonkin = true }
function L.SkinHere(skinning, dead, kind, targetGuid, source)
    if not (skinning and dead and kind and L.SKINNED[kind]) then return false end
    return source == nil or targetGuid == nil or targetGuid == source
end
local function skinHere(source)
    if not hasSkinning() then return false end
    local Safe = ns.api.Safe
    local ok, yes = pcall(function()
        return L.SkinHere(true, Safe(UnitIsDead("target")), Safe(UnitCreatureType("target")), Safe(UnitGUID("target")), source)
    end)
    return ok and yes == true
end
L.seen = {}        -- [loot source] = true: Flow closed this corpse's window once
L.told = false     -- the chat note went out this session
L.SEEN_MAX = 200

local function setGameAutoLoot(on)
    pcall(SetCVar, "autoLootDefault", on and "1" or "0")
end

function L:SetEnabled(on)
    local d = ns.db.loot
    if on == L.Enabled() then return end
    if on then
        -- Remember whether you auto-looted, then take over from the game.
        local ok, v = pcall(GetCVar, "autoLootDefault")
        d.auto = not (ok and v == "0")
        d.skipJunk = true
        setGameAutoLoot(false)
        local warn = L.SkinWarning(true, hasSkinning())
        if warn then ns:Print(warn); d.skinWarned = true end
    else
        d.skipJunk = false
        setGameAutoLoot(d.auto ~= false)
    end
end

-- Where the loot comes from (a corpse's GUID), or nil.
local function sourceOf()
    if not GetLootSourceInfo then return nil end
    local ok, guid = pcall(GetLootSourceInfo, 1)
    guid = ok and ns.api.Safe(guid) or nil
    return type(guid) == "string" and guid or nil
end

-- The note: two lines by your cursor, where the loot window was, fading out.
-- Flow's own frame; it takes no clicks.
local note
function L.ShowNote(names)
    if not note then
        note = CreateFrame("Frame", "FlowLootNote", UIParent)
        note:SetSize(320, 36)
        note:SetFrameStrata("TOOLTIP")
        note:EnableMouse(false)
        note.text = note:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        note.text:SetPoint("TOP")
        note.sub = note:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        note.sub:SetPoint("TOP", note.text, "BOTTOM", 0, -2)
        note.fade = note:CreateAnimationGroup()
        local a = note.fade:CreateAnimation("Alpha")
        a:SetFromAlpha(1); a:SetToAlpha(0)
        a:SetStartDelay(L.NOTE_SECONDS); a:SetDuration(0.6)
        note.fade:SetScript("OnFinished", function() note:Hide() end)
    end
    local title, sub = L.JunkWords(names)
    note.text:SetText(title)
    note.sub:SetText(sub)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    note:ClearAllPoints()
    note:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x / s, y / s + 24)
    note:SetAlpha(1)
    note:Show()
    note.fade:Stop()
    note.fade:Play()
    return note
end

local busy = false
local function loot()
    if busy or not L.Enabled() or ns.db.loot.auto == false then return end
    if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then return end   -- by hand this time
    busy = true
    local source = sourceOf()
    local again = source ~= nil and L.seen[source] == true
    local skin = skinHere(source)
    local left, junk, took, names = 0, 0, 0, {}
    for i = (ns.api.Safe(GetNumLootItems()) or 0), 1, -1 do
        local _, name, _, _, quality, locked, isQuestItem = GetLootSlotInfo(i)
        local slotType = GetLootSlotType and GetLootSlotType(i)
        if L.Take(slotType, quality, isQuestItem, locked, skin) then
            LootSlot(i)
            took = took + 1
        else
            left = left + 1
            if ns.api.Safe(quality) == 0 then
                junk = junk + 1
                name = ns.api.Safe(name)
                if type(name) == "string" then names[#names + 1] = name end
            end
        end
    end
    -- Only junk left, the first time: close the window (the corpse keeps it).
    -- Opened again: it stays open, for you to take what you like.
    local close = L.ShouldClose(left, junk, source, L.seen)
    ns:Log("loot", string.format("took %d, left %d (%d junk)%s%s%s", took, left, junk, skin and ", junk taken too: a corpse to skin" or "",
        close and ", closed the window" or "", again and " (opened again: left open for you)" or ""))
    if close then
        if source then
            L.seen[source] = true
            L.seenN = (L.seenN or 0) + 1
            if L.seenN > L.SEEN_MAX then L.seen, L.seenN = { [source] = true }, 1 end
        end
        pcall(L.ShowNote, names)
        if not L.told then
            L.told = true
            ns:Print(string.format("left %d grey item%s on the corpse (\"Leave junk behind when looting\" is on). "
                .. "Open it again to take them by hand; /flow loot junk to take everything.", junk, junk == 1 and "" or "s"))
        end
        CloseLoot()
    end
end

ns:On("LOOT_READY", function() pcall(loot) end)
ns:On("LOOT_OPENED", function() pcall(loot) end)
ns:On("LOOT_CLOSED", function() busy = false end)

ns:OnLoad(function(saved)
    saved.loot = saved.loot or {}
end)

-- If the game's Auto Loot got switched back on while this is on, it would
-- take the junk too: switch it off again (once per login).
ns:On("PLAYER_LOGIN", function()
    if not L.Enabled() then return end
    local ok, v = pcall(GetCVar, "autoLootDefault")
    if ok and v == "1" then setGameAutoLoot(false) end
    -- On already, with Skinning: said once (professions are read a little after login).
    if C_Timer and not ns.db.loot.skinWarned then
        C_Timer.After(10, function()
            local warn = L.Enabled() and L.SkinWarning(true, hasSkinning())
            if warn then ns:Print(warn); ns.db.loot.skinWarned = true end
        end)
    end
end)

ns.commands.loot = function(arg)
    arg = (arg or ""):lower()
    if arg == "nojunk" or arg == "on" then L:SetEnabled(true)
    elseif arg == "junk" or arg == "off" then L:SetEnabled(false) end
    ns:Print("leave junk behind when looting: " .. (L.Enabled() and "on (Flow loots everything else; hold Shift to loot by hand)" or "off")
        .. "  (/flow loot nojunk|junk)")
end
