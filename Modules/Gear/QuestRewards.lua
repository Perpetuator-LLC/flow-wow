-- Marks on quest reward choices so you can pick at a glance:
--   spec badge (bottom of the icon) = one icon per spec with an arrow above:
--     up = better than what that spec wears, down = worse, flat = about the
--     same (Gear/SpecBadge.lua, the same marks as in your bags)
--   gold coin (top left) = nothing is an upgrade for any spec: take this one
--     to sell (highest vendor price)

local _, ns = ...
local G = ns.gear

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
        if b.flowMarks then b.flowMarks.specs:Hide(); b.flowMarks.coin:Hide() end
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
local function update()
    if not ns.db.gear.enabled then return end
    hideAll()
    -- Only the NPC quest dialog: the quest log reuses the same reward
    -- buttons but the choice APIs below don't describe it.
    if not (QuestFrame and QuestFrame:IsShown()) then return end
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n < 1 then return end
    local choices, sellIndex, missing = pick(n)
    for i, c in pairs(choices) do
        local b = rewardButton(i)
        if b then
            local m = marksFor(b)
            if c.canUse then m.specs:Set(c.diffs) else m.specs:Hide() end
            m.coin:SetShown(i == sellIndex and n > 1)
        end
    end
    -- Item info may not be loaded the first time; try once more shortly.
    if missing and not retried then
        retried = true
        C_Timer.After(0.5, function() pcall(update) end)
    end
end
local function schedule()
    retried = false
    C_Timer.After(0, function() pcall(update) end)
end

ns:On("QUEST_COMPLETE", schedule)
ns:On("QUEST_DETAIL", schedule)
if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", schedule) end
