-- Icons on your bag slots (Blizzard bags; other bag addons aren't covered):
--   green arrow (top left)    = equip this now (better for your levelling role)
--   spec icons (top right)    = better for another role (Retribution / Holy / Protection icons, coloured rims)
--   bottom left               = gold coin = sell, AH, DE, or why it is kept:
--                               quest "!" (current/upcoming quest), profession icon (crafting material)
-- The item tooltip says what Flow would do and why.
-- /flow bags on|off

local _, ns = ...
local D = ns.disposition

local BADGE = {
    sell = { "$", 1.0, 0.75, 0.2 },
    ah   = { "AH", 0.4, 0.8, 1.0 },
    de   = { "DE", 0.75, 0.5, 1.0 },
}
local ROLE_RGB = { dps = { 1, 0.25, 0.25 }, heal = { 0.25, 0.9, 0.25 }, tank = { 0.25, 0.55, 1 } }

local function marks(button)
    if button.flowMarks then return button.flowMarks end
    local m = CreateFrame("Frame", nil, button)
    m:SetAllPoints()
    m:SetFrameLevel(button:GetFrameLevel() + 5)
    m.arrow = m:CreateTexture(nil, "OVERLAY")
    m.arrow:SetSize(16, 16)
    m.arrow:SetPoint("TOPLEFT", -2, 2)
    local ok = m.arrow.SetAtlas and pcall(m.arrow.SetAtlas, m.arrow, "bags-greenarrow")
    if not ok then
        m.arrow:SetColorTexture(0.2, 1, 0.2, 0.9)
        m.arrow:SetSize(8, 8)
    end
    -- Small spec icons (Retribution / Holy / Protection) with a role-coloured
    -- rim, for "better for another role". Coloured squares if no icon.
    m.dots = {}
    for i, role in ipairs({ "dps", "heal", "tank" }) do
        local d = CreateFrame("Frame", nil, m)
        d:SetSize(12, 12)
        d:SetPoint("TOPRIGHT", -1 - (i - 1) * 13, -1)
        d.rim = d:CreateTexture(nil, "BACKGROUND")
        d.rim:SetAllPoints()
        d.rim:SetColorTexture(ROLE_RGB[role][1], ROLE_RGB[role][2], ROLE_RGB[role][3], 1)
        d.icon = d:CreateTexture(nil, "ARTWORK")
        d.icon:SetPoint("TOPLEFT", 1, -1)
        d.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        local path = ns:RoleIconPath(role)
        if path then d.icon:SetTexture(path); d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else d.icon:Hide() end
        d:Hide()
        m.dots[role] = d
    end
    m.badge = m:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    m.badge:SetPoint("BOTTOMLEFT", 2, 2)
    -- Gold coin for "sell".
    m.coin = m:CreateTexture(nil, "OVERLAY")
    m.coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    m.coin:SetSize(14, 14)
    m.coin:SetPoint("BOTTOMLEFT", 1, 1)
    m.coin:Hide()
    -- Keep-for-a-reason icon (quest "!", or the profession's icon).
    m.keep = m:CreateTexture(nil, "OVERLAY")
    m.keep:SetSize(14, 14)
    m.keep:SetPoint("BOTTOMLEFT", 1, 1)
    m.keep:Hide()
    button.flowMarks = m
    return m
end

local function clear(button)
    local m = button.flowMarks
    if not m then return end
    m.arrow:Hide()
    for _, d in pairs(m.dots) do d:Hide() end
    m.badge:SetText("")
    m.coin:Hide()
    m.keep:Hide()
end

local function paint(button, bag, slot)
    local link = bag and slot and (C_Container and C_Container.GetContainerItemLink or GetContainerItemLink)(bag, slot)
    if not link or not ns.db.bags.enabled then clear(button) return end
    local v = D:Decide(bag, slot, link)
    if not v then clear(button) return end
    local m = marks(button)
    m.arrow:SetShown(v.action == "equip")
    local g = v.item.gear
    local main = ns:LevelingRole()
    for role, d in pairs(m.dots) do
        d:SetShown(g ~= nil and g.canUse and role ~= main and g.diffs[role] >= 0.5)
    end
    m.coin:SetShown(v.action == "sell")
    if v.action == "keep" and v.icon then
        m.keep:SetTexture(v.icon)
        m.keep:Show()
    else
        m.keep:Hide()
    end
    local b = v.action ~= "sell" and BADGE[v.action]
    if b then
        m.badge:SetText(b[1])
        m.badge:SetTextColor(b[2], b[3], b[4])
    else
        m.badge:SetText("")
    end
end

-- Calls fn(button, bag, slot) for every visible Blizzard bag slot button.
local function eachButton(fn)
    local frames = {}
    if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if f then frames[#frames + 1] = f end
    end
    for _, f in ipairs(frames) do
        if f:IsShown() then
            if f.EnumerateValidItems then
                for _, b in f:EnumerateValidItems() do
                    fn(b, b.GetBagID and b:GetBagID() or f:GetID(), b:GetID())
                end
            elseif f.Items then
                for _, b in ipairs(f.Items) do
                    if b:IsShown() then fn(b, b.GetBagID and b:GetBagID() or f:GetID(), b:GetID()) end
                end
            elseif f:GetName() then
                local bag = f:GetID()
                for j = 1, 36 do
                    local b = _G[f:GetName() .. "Item" .. j]
                    if b and b:IsShown() then fn(b, bag, b:GetID()) end
                end
            end
        end
    end
end

local dirty, acc, wasOpen = true, 0, false
local function refresh()
    eachButton(function(b, bag, slot) pcall(paint, b, bag, slot) end)
end

ns:OnLoad(function(saved)
    saved.bags = saved.bags or {}
    if saved.bags.enabled == nil then saved.bags.enabled = true end
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.3 then return end
        acc = 0
        -- Repaint when bags open, when something changed, and now and then
        -- while open (item info can arrive late).
        local open = (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown())
            or (ContainerFrame1 and ContainerFrame1:IsShown())
        if open and not wasOpen then dirty = true end
        wasOpen = open
        if dirty or (open and math.random() < 0.1) then
            dirty = false
            refresh()
        end
    end)
end)

for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
                      "EQUIPMENT_SETS_CHANGED", "GET_ITEM_INFO_RECEIVED", "BAG_OPEN" }) do
    ns:On(ev, function() dirty = true end)
end

ns.commands.bags = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.bags.enabled = (arg == "on")
        dirty = true
        ns:Print("bag icons " .. arg)
    else
        ns:Print("/flow bags on|off. Green arrow = equip now, dots = better for another role, $ sell, AH auction house, DE disenchant.")
    end
end

-- Tooltip line for items in your bags: what Flow would do, and why.
local ACTION_COLOR = { equip = "66ff66", keep = "ffd200", sell = "ffbf33", ah = "66ccff", de = "bf80ff" }
ns:Register("itemTip", "disposition", function(tooltip, link)
    if not ns.db.bags.enabled then return end
    local bag, slot, l = D:FindInBags(link)
    if not bag then return end
    local v = D:Decide(bag, slot, l)
    if not v then return end
    tooltip:AddLine(string.format("Flow: |cff%s%s|r: %s", ACTION_COLOR[v.action] or "ffffff",
        D.LABEL[v.action] or v.action, v.reason or ""), 0.9, 0.9, 0.9, true)
    tooltip:Show()
end)
