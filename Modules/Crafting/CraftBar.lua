-- Making several at once (Create All, or a count): a second bar under your
-- cast bar shows the whole batch, "Making Charred Wolf Meat 3/10"; the cast
-- bar itself only shows the one in progress. It fills as each one finishes,
-- says "Stopped at 3/10" if you move or cancel, and fades a moment after.

local _, ns = ...
local CB = {}
ns.craftBar = CB

local batch          -- { name, total, done, icon, stopped }
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

-- "Making X 3/10", "Made 10 X", "Stopped at 3/10".
function CB.Text(b)
    if not b then return "" end
    if b.stopped then return string.format("Stopped: %s %d/%d", b.name, b.done, b.total) end
    if b.done >= b.total then return string.format("Made %d %s", b.total, b.name) end
    return string.format("Making %s %d/%d", b.name, b.done, b.total)
end

local function show()
    if not batch then return end
    bar = bar or build()
    bar:SetMinMaxValues(0, batch.total)
    bar:SetValue(batch.done)
    bar.text:SetText(CB.Text(batch))
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

-- A batch starts: only worth a bar for 2 or more.
function CB.Start(name, total, icon)
    total = tonumber(total) or 1
    if not name or total < 2 then batch = nil; if bar then bar:Hide() end return end
    batch = { name = name, total = total, done = 0, icon = icon }
    show()
end

-- One cast finished (or was interrupted) with this spell name. (The spell
-- can be named differently from the recipe: the first cast after the batch
-- starts tells, batch.cast.)
function CB.Step(name, ok)
    if not (batch and name and (name == batch.name or name == batch.cast) and not batch.stopped) then return end
    if ok then batch.done = batch.done + 1 else batch.stopped = true end
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
    if unit == "player" and batch and batch.done == 0 and not batch.cast then batch.cast = spellName(id) end
end)
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, id)
    if unit == "player" and batch then CB.Step(spellName(id), true) end
end)
-- (Only interrupted: "failed" also fires for a key pressed mid-cast.)
ns:On("UNIT_SPELLCAST_INTERRUPTED", function(unit, _, id)
    if unit == "player" and batch then CB.Step(spellName(id), false) end
end)
