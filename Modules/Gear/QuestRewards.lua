-- Badges on quest reward choices so you can pick at a glance:
--   red D   = best upgrade for DPS
--   green H = best upgrade for Heal
--   blue T  = best upgrade for Tank
--   gold $  = nothing is an upgrade for any role: take this one to sell
--              (highest vendor price)
-- One item can carry several badges. A badge is only shown for a role if
-- that choice actually beats what you wear for that role.

local _, ns = ...
local G = ns.gear

local BADGE = {
    dps  = { 1.0, 0.25, 0.25, "D" },
    heal = { 0.25, 0.9, 0.25, "H" },
    tank = { 0.25, 0.55, 1.0, "T" },
    sell = { 1.0, 0.65, 0.0, "$" },
}
local ORDER = { "dps", "heal", "tank", "sell" }

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

local function badgesFor(button)
    if button.flowBadges then return button.flowBadges end
    local list = {}
    local anchor = button.Icon or _G[(button:GetName() or "") .. "IconTexture"] or button
    for idx, key in ipairs(ORDER) do
        local c = BADGE[key]
        local f = CreateFrame("Frame", nil, button)
        f:SetSize(14, 14)
        f:SetFrameLevel(button:GetFrameLevel() + 5)
        f.bg = f:CreateTexture(nil, "OVERLAY")
        f.bg:SetAllPoints()
        f.bg:SetColorTexture(c[1], c[2], c[3], 0.95)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.text:SetPoint("CENTER", 0, 0)
        f.text:SetText(c[4])
        f:Hide()
        f.key = key
        list[idx] = f
    end
    list.anchor = anchor
    button.flowBadges = list
    return list
end

-- Clear badges from every reward button: buttons get reused between quests,
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
        for _, f in ipairs(b.flowBadges or {}) do f:Hide() end
    end
end

-- Returns { [choiceIndex] = { role = true, ... } }, missingInfo
local function pick(n)
    local best = {}       -- role -> { i, diff }
    local sell            -- { i, price }
    local missing = false
    for i = 1, n do
        local link = GetQuestItemLink("choice", i)
        local c = link and G:Compare(link)
        if link and not c then missing = true end
        if c then
            if c.canUse then
                for _, role in ipairs(G.ROLES) do
                    local d = c.diffs[role]
                    if d >= 0.5 and (not best[role] or d > best[role].diff) then
                        best[role] = { i = i, diff = d }
                    end
                end
            end
            if not sell or c.item.sellPrice > sell.price then
                sell = { i = i, price = c.item.sellPrice }
            end
        end
    end
    local marks = {}
    local any = false
    for role, b in pairs(best) do
        marks[b.i] = marks[b.i] or {}
        marks[b.i][role] = true
        any = true
    end
    if not any and sell then marks[sell.i] = { sell = true } end
    return marks, missing
end

local retried = false
local function update()
    if not ns.db.gear.enabled then return end
    hideAll()
    -- Only the NPC quest dialog: the quest log reuses the same reward
    -- buttons but the choice APIs below don't describe it.
    if not (QuestFrame and QuestFrame:IsShown()) then return end
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n < 2 then return end  -- nothing to choose between
    local marks, missing = pick(n)
    for i, roles in pairs(marks) do
        local b = rewardButton(i)
        if b then
            local list = badgesFor(b)
            local x = 0
            for _, f in ipairs(list) do
                if roles[f.key] then
                    f:ClearAllPoints()
                    f:SetPoint("TOPLEFT", list.anchor, "TOPLEFT", x - 2, 2)
                    f:Show()
                    x = x + 15
                end
            end
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
