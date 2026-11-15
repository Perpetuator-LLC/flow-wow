-- Making several at once (Create All, or a count): a second bar under your
-- cast bar shows the whole batch, "Making Charred Wolf Meat 3/10"; the cast
-- bar itself only shows the one in progress. It fills as each one finishes,
-- says "Stopped at 3/10" if you move or cancel, and fades a moment after.
--
-- It can never stay up (0.35.235: "I got attacked in the middle of making my
-- bandages and the total progress bar got stuck on, had to reload to make it
-- go away: that should never happen"). The batch ended without the game
-- naming the interrupted cast, so nothing closed the bar. Now a batch also
-- ends when a fight starts, when an interruption comes with no readable
-- name, and when nothing has been cast for CB.IDLE seconds: whatever the
-- game does or doesn't say, the bar goes.
--
-- It says how long is left too: "Making Linen Bandage 3/10 (about 21 s)",
-- from how long one takes.

local _, ns = ...
local CB = {}
ns.craftBar = CB

local batch          -- { name, total, done, icon, stopped, lastAt, castSecs, castStart }
CB.IDLE = 2.5        -- seconds with nothing being made before the batch is taken as over
local bar

local function build()
    local f = CreateFrame("StatusBar", "FlowCraftBar", UIParent)
    f:SetSize(220, 14)
    local cast = _G.PlayerCastingBarFrame or _G.CastingBarFrame
    if cast then f:SetPoint("TOP", cast, "BOTTOM", 0, -14) else f:SetPoint("CENTER", UIParent, "CENTER", 0, -230) end
    f:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f:SetStatusBarColor(1, 0.7, 0.2)
    f:SetMinMaxValues(0, 1)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.6)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("CENTER")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(16, 16)
    f.icon:SetPoint("RIGHT", f, "LEFT", -4, 0)
    f:Hide()
    return f
end

-- Pure: seconds until the batch is done, or nil when one cast's length
-- isn't known yet. castSecs: how long one takes; into: seconds into the
-- one being made now.
function CB.Left(total, done, castSecs, into)
    if not (castSecs and castSecs > 0) then return nil end
    local left = (total - done) * castSecs - math.max(0, math.min(castSecs, into or 0))
    return math.max(0, left)
end
-- Pure: "21 s", "1 min 30 s".
function CB.Span(seconds)
    seconds = math.floor((seconds or 0) + 0.5)
    if seconds >= 60 then
        local s = seconds % 60
        return string.format("%d min%s", math.floor(seconds / 60), s > 0 and string.format(" %d s", s) or "")
    end
    return seconds .. " s"
end
-- "Making X 3/10 (about 21 s)", "Made 10 X", "Stopped at 3/10". now: the
-- time, for how long is left (nil: no time shown).
function CB.Text(b, now)
    if not b then return "" end
    if b.stopped then return string.format("Stopped: %s %d/%d", b.name, b.done, b.total) end
    if b.done >= b.total then return string.format("Made %d %s", b.total, b.name) end
    local left = now and CB.Left(b.total, b.done, b.castSecs, b.castStart and (now - b.castStart) or 0) or nil
    return string.format("Making %s %d/%d%s", b.name, b.done, b.total, left and (" (about " .. CB.Span(left) .. ")") or "")
end

-- Pure: is the batch over without a word from the game? Nothing is being
-- cast, and nothing has been for `idle` seconds.
function CB.Stalled(b, now, casting, idle)
    if not b or b.stopped or b.done >= b.total then return false end
    if casting then return false end
    return (now - (b.lastAt or now)) > (idle or CB.IDLE)
end

local function show()
    if not batch then return end
    bar = bar or build()
    bar:SetMinMaxValues(0, batch.total)
    bar:SetValue(batch.done)
    bar.text:SetText(CB.Text(batch, GetTime()))
    bar.icon:SetTexture(batch.icon)
    bar:SetAlpha(1)
    bar:Show()
end

local function finish()
    local b = batch
    C_Timer.After(2.5, function()
        if batch == b then batch = nil; if bar then bar:Hide() end end
    end)
end

-- The batch is over, whatever the game said (or didn't): "Stopped at 3/10",
-- then gone.
function CB.Stop(why)
    if not batch or batch.stopped or batch.done >= batch.total then return false end
    batch.stopped = true
    ns:Log("craft", string.format("batch of %s stopped at %d/%d (%s)", tostring(batch.name), batch.done, batch.total, tostring(why)))
    show()
    finish()
    return true
end

-- A batch starts: only worth a bar for 2 or more.
function CB.Start(name, total, icon)
    total = tonumber(total) or 1
    if not name or total < 2 then batch = nil; if bar then bar:Hide() end return end
    batch = { name = name, total = total, done = 0, icon = icon, lastAt = GetTime() }
    show()
end

-- One cast finished (or was interrupted) with this spell name. (The spell
-- can be named differently from the recipe: the first cast after the batch
-- starts tells, batch.cast.)
function CB.Step(name, ok)
    if not (batch and name and (name == batch.name or name == batch.cast) and not batch.stopped) then return end
    if ok then batch.done = batch.done + 1 else batch.stopped = true end
    batch.lastAt, batch.castStart = GetTime(), nil
    show()
    if batch.stopped or batch.done >= batch.total then finish() end
end
function CB.Current() return batch end

-- Where batches start: the old trade skill window (DoTradeSkill(index, n))
-- and the newer one (C_TradeSkillUI.CraftRecipe(recipeID, n)).
if DoTradeSkill and hooksecurefunc then
    hooksecurefunc("DoTradeSkill", function(index, n)
        local name = GetTradeSkillInfo and GetTradeSkillInfo(index)
        local icon = GetTradeSkillIcon and GetTradeSkillIcon(index)
        CB.Start(name, n, icon)
    end)
end
if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe and hooksecurefunc then
    hooksecurefunc(C_TradeSkillUI, "CraftRecipe", function(recipeID, n)
        local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
        CB.Start(info and info.name, n, info and info.icon)
    end)
end

local function spellName(id) return id and (ns.api.SpellInfo(ns.api.Safe(id) or 0)) end
ns:On("UNIT_SPELLCAST_START", function(unit, _, id)
    if unit ~= "player" or not batch then return end
    if batch.done == 0 and not batch.cast then batch.cast = spellName(id) end
    batch.lastAt, batch.castStart = GetTime(), GetTime()
    -- How long one takes, from the game's own cast times.
    if UnitCastingInfo then
        local _, _, _, s, e = UnitCastingInfo("player")
        s, e = ns.api.Safe(s), ns.api.Safe(e)
        if type(s) == "number" and type(e) == "number" and e > s then batch.castSecs = (e - s) / 1000 end
    end
end)
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, id)
    if unit == "player" and batch then CB.Step(spellName(id), true) end
end)
-- (Only interrupted: "failed" also fires for a key pressed mid-cast.)
ns:On("UNIT_SPELLCAST_INTERRUPTED", function(unit, _, id)
    if unit ~= "player" or not batch then return end
    local name = spellName(id)
    -- (A name the game hides, as in a fight: it's the batch's, there's nothing
    -- else you'd be casting while making things.)
    if name then CB.Step(name, false) else CB.Stop("an interruption the game didn't name") end
end)
-- A fight starts: making things is over.
ns:On("PLAYER_REGEN_DISABLED", function() CB.Stop("a fight started") end)
-- And whatever else ends it without a word: nothing cast for a while. Also
-- keeps the time left counting down.
local watch, acc = CreateFrame("Frame"), 0
watch:SetScript("OnUpdate", function(_, dt)
    if not batch then return end
    acc = acc + dt
    if acc < 0.25 then return end
    acc = 0
    local casting = ns.api.Casting and ns.api.Casting() or nil
    if casting then batch.lastAt = GetTime() end
    if CB.Stalled(batch, GetTime(), casting ~= nil) then CB.Stop("nothing made for " .. CB.IDLE .. " s") return end
    if bar and bar:IsShown() and not batch.stopped and batch.done < batch.total then bar.text:SetText(CB.Text(batch, GetTime())) end
end)
