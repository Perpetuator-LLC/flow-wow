-- Advisor: "what should I change to get better?" Collects advice from every
-- registered advisor (train this spell, equip that item, raise a profession,
-- spend talent points, rotation habits from your best fights) and shows it
-- as a small "!" button with a count. Hover for the list; /flow advice prints it.
--
-- Add an advisor:
--   ns:Register("advisor", "key", { check = function() return { advice, ... } end })
-- advice = { importance = 0-100, text = "...", improves = { "DPS", ... } }

local _, ns = ...
local Adv = {}
ns.advisor = Adv

local items = {}
local button

function Adv:Collect()
    local out = {}
    for key, a in ns:Each("advisor") do
        local ok, list = pcall(a.check)
        if ok then
            for _, item in ipairs(list or {}) do
                item.source = key
                out[#out + 1] = item
            end
        elseif ns.db.rotation.debug then
            ns:Print("advisor " .. key .. ": " .. tostring(list))
        end
    end
    table.sort(out, function(a, b) return (a.importance or 0) > (b.importance or 0) end)
    return out
end

local function line(item)
    local tags = item.improves and #item.improves > 0
        and (" |cff888888(improves " .. table.concat(item.improves, ", ") .. ")|r") or ""
    return item.text .. tags
end

function Adv:Print(limit)
    if #items == 0 then ns:Print("nothing to improve right now.") return end
    ns:Print("ways to improve:")
    for i = 1, math.min(limit or #items, #items) do print("  " .. i .. ". " .. line(items[i])) end
end

local function buildButton()
    local b = CreateFrame("Button", "FlowAdviceButton", UIParent)
    b:SetSize(26, 26)
    b:SetFrameStrata("HIGH")
    local p = ns.db.advisor.point
    if p then b:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else b:SetPoint("CENTER", UIParent, "CENTER", 48, -160) end
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1.0, 0.65, 0.0, 0.9)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetPoint("CENTER")
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, r, x, y = self:GetPoint()
        ns.db.advisor.point = { a, r, x, y }
    end)
    b:SetScript("OnClick", function() Adv:Print() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Flow: ways to improve")
        for i = 1, math.min(10, #items) do
            GameTooltip:AddLine(i .. ". " .. line(items[i]), 1, 1, 1, true)
        end
        GameTooltip:AddLine("Click to print. Shift-drag to move.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

function Adv:Refresh()
    if InCombatLockdown and InCombatLockdown() then return end
    items = self:Collect()
    if not button then return end
    if ns.db.advisor.enabled and #items > 0 then
        button.text:SetText("!" .. #items)
        button:Show()
    else
        button:Hide()
    end
end

-- Many events fire in bursts; refresh once things settle.
local pending = false
local function schedule()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        pcall(Adv.Refresh, Adv)
    end)
end

ns:OnLoad(function(saved)
    saved.advisor = saved.advisor or {}
    if saved.advisor.enabled == nil then saved.advisor.enabled = true end
    button = buildButton()
end)

for _, ev in ipairs({ "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
                      "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "TRAINER_CLOSED",
                      "PLAYER_REGEN_ENABLED", "ACTIONBAR_SLOT_CHANGED",
                      "CHARACTER_POINTS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    ns:On(ev, schedule)
end

ns:On("PLAYER_LOGIN", function()
    C_Timer.After(6, function()
        pcall(Adv.Refresh, Adv)
        if #items > 0 then Adv:Print(3) end
    end)
end)

ns:On("PLAYER_LEVEL_UP", function()
    C_Timer.After(2, function() pcall(Adv.Refresh, Adv); Adv:Print(5) end)
end)

ns.commands.advice = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.advisor.enabled = (arg == "on")
        Adv:Refresh()
        ns:Print("advice button " .. arg)
    else
        Adv:Refresh()
        Adv:Print()
    end
end
