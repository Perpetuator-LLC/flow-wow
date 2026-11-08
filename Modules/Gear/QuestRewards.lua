-- Marks on quest reward choices so you can pick at a glance:
--   spec badge (bottom of the icon) = one icon per spec with an arrow above:
--     up = better than what that spec wears, down = worse, flat = about the
--     same (Gear/SpecBadge.lua, the same marks as in your bags)
--   gold coin (top left) = nothing is an upgrade for any spec: take this one
--     to sell (highest vendor price)
--   big green arrow (top left) = the best pick for you: the biggest upgrade
--     for the spec you're levelling (the same arrow as "equip this" in your
--     bags). Shown when you're offered the quest and when you turn it in.

local _, ns = ...
local G = ns.gear
local R = {}
ns.questRewards = R

-- The choice to take: the biggest upgrade for `role` among the ones you can
-- use (choices[i] = G:Compare result). nil when none is an upgrade for it.
function R.Best(choices, role)
    local best, bestDiff
    for i, c in pairs(choices) do
        local d = c.canUse and c.diffs and c.diffs[role]
        if d and ns.SpecTrend(d) == "up" and (not bestDiff or d > bestDiff) then best, bestDiff = i, d end
    end
    return best
end

local function rewardButton(i)
    local frame = QuestInfoRewardsFrame
    if frame and frame.RewardButtons then
        for _, b in ipairs(frame.RewardButtons) do
            if b.type == "choice" and b:GetID() == i and b:IsShown() then return b end
        end
        return nil
    end
    -- Older layouts.
    return _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestInfoItem" .. i]
end

-- Per button: the shared spec badge (Gear/SpecBadge.lua) at the bottom of the
-- item icon, and a gold coin at its top left for "take this one to sell".
local function marksFor(button)
    if button.flowMarks then return button.flowMarks end
    local anchor = button.Icon or _G[(button:GetName() or "") .. "IconTexture"] or button
    local m = {}
    m.specs = ns:SpecBadge(button, 10)
    m.specs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 1, 1)
    m.coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
    m.coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    m.coin:SetSize(14, 14)
    m.coin:SetPoint("TOPLEFT", anchor, "TOPLEFT", -2, 2)
    m.coin:Hide()
    m.best = button:CreateTexture(nil, "OVERLAY", nil, 7)
    m.best:SetSize(22, 22)
    m.best:SetPoint("TOPLEFT", anchor, "TOPLEFT", -4, 4)
    if not (m.best.SetAtlas and pcall(m.best.SetAtlas, m.best, "bags-greenarrow")) then
        m.best:SetColorTexture(0.2, 1, 0.2, 0.9); m.best:SetSize(10, 10)
    end
    m.best:Hide()
    button.flowMarks = m
    return m
end

-- Clear marks from every reward button: buttons get reused between quests,
-- sometimes for fixed (non-choice) rewards.
local function hideAll()
    local buttons = {}
    local frame = QuestInfoRewardsFrame
    for _, b in ipairs(frame and frame.RewardButtons or {}) do buttons[#buttons + 1] = b end
    for i = 1, 10 do
        local b = _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestInfoItem" .. i]
        if b then buttons[#buttons + 1] = b end
    end
    for _, b in ipairs(buttons) do
        if b.flowMarks then b.flowMarks.specs:Hide(); b.flowMarks.coin:Hide(); b.flowMarks.best:Hide() end
    end
end

-- For each choice: its comparison (diffs per spec), and which one to take to
-- sell when none is an upgrade for any spec. Returns choices, sellIndex, missingInfo.
local function pick(n)
    local choices, sell, missing, anyUp = {}, nil, false, false
    for i = 1, n do
        local link = GetQuestItemLink("choice", i)
        local c = link and G:Compare(link)
        if link and not c then missing = true end
        if c then
            choices[i] = c
            if c.canUse then
                for _, role in ipairs(G.ROLES) do
                    if ns.SpecTrend(c.diffs[role]) == "up" then anyUp = true end
                end
            end
            if not sell or c.item.sellPrice > sell.price then sell = { i = i, price = c.item.sellPrice } end
        end
    end
    return choices, (not anyUp and sell) and sell.i or nil, missing
end

local retried = false
local lastLogged
local function update(why)
    if not ns.db.gear.enabled then return end
    hideAll()
    -- Only the NPC quest dialog: the quest log reuses the same reward
    -- buttons but the choice APIs below don't describe it.
    if not (QuestFrame and QuestFrame:IsShown()) then return end
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n < 1 then return end
    local choices, sellIndex, missing = pick(n)
    local best = n > 1 and R.Best(choices, ns:LevelingRole()) or nil
    local marked = 0
    for i, c in pairs(choices) do
        local b = rewardButton(i)
        if b then
            local m = marksFor(b)
            marked = marked + 1
            if c.canUse then m.specs:Set(c.diffs) else m.specs:Hide() end
            m.coin:SetShown(i == sellIndex and n > 1)
            m.best:SetShown(i == best)
        end
    end
    -- (for the diagnostics: which reward was marked, and whether its button was found)
    local line = string.format("%s: %d choice(s), best for you %s, marked %d", tostring(why), n, tostring(best), marked)
    if line ~= lastLogged then lastLogged = line; ns:Log("rewards", line) end
    -- Item info may not be loaded the first time; try once more shortly.
    if missing and not retried then
        retried = true
        C_Timer.After(0.5, function() pcall(update, why) end)
    end
end
local function schedule(why)
    retried = false
    C_Timer.After(0, function() pcall(update, why) end)
end

ns:On("QUEST_COMPLETE", function() schedule("turn in") end)
ns:On("QUEST_DETAIL", function() schedule("offered") end)
if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", function() schedule("shown") end) end
