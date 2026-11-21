-------------------------------------------------------------------------------
-- Flow - Gear/SetIcons.lua
-- Your gear sets as icons on your bags, beside the Flow Banker tab (0.35.368).
--
-- "Just above the inventory it says Flow Banker. It would be nice if we had
-- an icon there of each of my gear sets, right next to Flow Banker ... each
-- has a different icon, it has a name when you hover it, and if the user
-- clicks it, it's so close."
--
-- One small icon for each of the game's own equipment sets (character
-- window, Equipment Manager), up to twelve, standing on the bag window's top
-- edge to the left of the Flow Banker tab. The icon is the set's own. The one
-- you're wearing has a gold edge. Hover: its name and how much of it you
-- have. Click: put it on (the game's own "equip set", so out of a fight;
-- in one the game only swaps weapons, and Flow says so instead of trying).
--
-- Flow only adds children to the bag window; it never moves, shows or hides
-- the game's frame.
-------------------------------------------------------------------------------

local _, ns = ...
local SI = {}
ns.setIcons = SI

SI.MAX = 12
SI.SIZE, SI.GAP = 20, 3
SI.FRAMES = { "ContainerFrameCombinedBags", "ContainerFrame1" }
SI.FALLBACK = "Interface\\Icons\\INV_Chest_Chain_04"

function SI.On() return not (ns.db and ns.db.gear and ns.db.gear.setIcons == false) end

-- Pure: the icons to show. ids: the game's set IDs; info(id) -> name, icon,
-- worn (bool), items, wearing (counts, may be nil). By name, at most `max`.
--   -> { { id, name, icon, worn, items, wearing } }, how many were left out
function SI.List(ids, info, max)
    local out = {}
    for _, id in ipairs(ids or {}) do
        local name, icon, worn, items, wearing = info(id)
        if type(name) == "string" and name ~= "" then
            out[#out + 1] = { id = id, name = name, icon = icon, worn = worn and true or false, items = items, wearing = wearing }
        end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    local left = math.max(0, #out - (max or SI.MAX))
    for i = #out, (max or SI.MAX) + 1, -1 do out[i] = nil end
    return out, left
end

-- Pure: an icon's tooltip lines.
function SI.Tip(set, inCombat)
    local out = { set.name }
    if set.worn then out[#out + 1] = "You're wearing it."
    elseif set.items and set.wearing then out[#out + 1] = string.format("You're wearing %d of its %d pieces.", set.wearing, set.items) end
    out[#out + 1] = inCombat and "In a fight the game only swaps weapons: click it after the fight." or (set.worn and "Click: put it on again." or "Click: put it on.")
    return out
end

local CE = C_EquipmentSet
function SI.Has() return CE ~= nil and CE.GetEquipmentSetIDs ~= nil and CE.GetEquipmentSetInfo ~= nil end

-- Your sets, as the game has them now.
function SI.Sets()
    if not SI.Has() then return {}, 0 end
    local ok, ids = pcall(CE.GetEquipmentSetIDs)
    return SI.List(ok and ids or {}, function(id)
        -- name, icon, setID, isEquipped, numItems, numEquipped
        local okI, name, icon, _, worn, items, wearing = pcall(CE.GetEquipmentSetInfo, id)
        if not okI then return nil end
        return name, icon, worn, tonumber(items), tonumber(wearing)
    end)
end

-- An icon was clicked: put the set on. -> true when asked of the game.
function SI.Use(set, quiet)
    if not (set and set.id and SI.Has() and CE.UseEquipmentSet) then return false end
    if InCombatLockdown() then
        if not quiet then ns:Print(tostring(set.name) .. ": the game only swaps gear sets out of a fight.") end
        return false
    end
    local ok, err = pcall(CE.UseEquipmentSet, set.id)
    ns:Log("gear", string.format("gear set icon: %s -> %s", tostring(set.name), ok and "asked" or tostring(err)))
    if not ok and not quiet then ns:Print("couldn't put on " .. tostring(set.name) .. ": " .. tostring(err)) end
    return ok and true or false
end

-------------------------------------------------------------------------------
-- The icons
-------------------------------------------------------------------------------
local bars = {}   -- [frame path] = the row of icons

local function makeIcon(bar, i)
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(SI.SIZE, SI.SIZE)
    b:SetPoint("RIGHT", bar, "RIGHT", -(i - 1) * (SI.SIZE + SI.GAP), 0)
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.25)
    b:SetScript("OnClick", function(self)
        if SI.Use(self.set) then C_Timer.After(0.6, function() SI.Refresh() end) end
    end)
    b:SetScript("OnEnter", function(self)
        if not self.set then return end
        ns.Tip(self, "ANCHOR_TOPLEFT")
        for n, line in ipairs(SI.Tip(self.set, InCombatLockdown())) do
            if n == 1 then GameTooltip:AddLine(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function makeBar(frame)
    local GB = ns.gameButtons
    local win = GB.Window(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetSize(10, SI.SIZE)
    bar:SetFrameLevel(math.min((win:GetFrameLevel() or 1) + 520, 9990))
    bar.win = win
    bar.icons = {}
    bar:SetScript("OnShow", function() SI.Refresh() end)
    return bar
end

-- Where the row stands: on the bag window's top edge, to the left of the
-- Flow Banker tab (when that tab is there), its bottom on the edge like the tab's.
local function place(bar)
    local GB = ns.gameButtons
    local tab = GB._Buttons and GB._Buttons().bags
    bar:ClearAllPoints()
    if tab and tab:IsShown() and tab:GetParent() == bar:GetParent() then
        bar:SetPoint("BOTTOMRIGHT", tab, "BOTTOMLEFT", -6, 1)
    else
        bar:SetPoint("BOTTOMRIGHT", bar.win, "TOPRIGHT", GB.X, GB.Y + 1)
    end
end

function SI.Refresh()
    local on = SI.On() and SI.Has()
    local sets = on and SI.Sets() or {}
    for _, bar in pairs(bars) do
        place(bar)
        for i = 1, math.max(#sets, #bar.icons) do
            local s = sets[i]
            local b = bar.icons[i]
            if s then
                b = b or makeIcon(bar, i)
                bar.icons[i] = b
                b.set = s
                b.tex:SetTexture(s.icon or SI.FALLBACK)
                -- Gold round the one you're wearing; a thin dark edge round the rest.
                if s.worn then b.edge:SetColorTexture(1, 0.82, 0, 1) else b.edge:SetColorTexture(0, 0, 0, 0.9) end
                b:Show()
            elseif b then
                b.set = nil
                b:Hide()
            end
        end
        bar:SetWidth(math.max(10, #sets * (SI.SIZE + SI.GAP) - SI.GAP))
        bar:SetShown(on and #sets > 0)
    end
    SI.count = #sets
end

function SI.Attach()
    if not (ns.db and ns.db.gear and ns.gameButtons) then return end
    for _, path in ipairs(SI.FRAMES) do
        if not bars[path] then
            local frame = ns.gameButtons.Resolve(path)
            if frame then
                local ok, bar = pcall(makeBar, frame)
                if ok then bars[path] = bar else ns:Log("gear", "gear set icons: " .. tostring(bar)) end
            end
        end
    end
    SI.Refresh()
end
SI._Bars = function() return bars end   -- (tests)

for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD" }) do
    ns:On(ev, function() pcall(SI.Attach) end)
end
for _, ev in ipairs({ "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SWAP_FINISHED" }) do
    ns:On(ev, function() pcall(SI.Refresh) end)
end

function SI.Lines()
    local sets, left = SI.Sets()
    local out = { string.format("gear set icons on your bags: %s; %d set(s)%s", SI.On() and "on" or "off", #sets, left > 0 and string.format(" (%d more not shown)", left) or "") }
    for _, s in ipairs(sets) do
        out[#out + 1] = string.format("  %s%s", s.name, s.worn and " (wearing it)" or (s.items and s.wearing and string.format(" (%d of %d on)", s.wearing, s.items) or ""))
    end
    local n = 0
    for _ in pairs(bars) do n = n + 1 end
    out[#out + 1] = string.format("  on %d bag window(s); the game's equipment sets: %s", n, SI.Has() and "there" or "not on this client")
    return out
end
ns.commands.setsicons = function()
    for i, l in ipairs(SI.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "screen",
        label = "Gear set icons on your bags",
        note = "(beside the Flow Banker tab)",
        tip = "An icon for each of the game's equipment sets on top of your bag window, left of the Flow Banker tab: hover for its name, click to put it on (out of a fight). "
            .. "The one you're wearing has a gold edge. Off: no icons; your sets are untouched.",
        get = function() return SI.On() end,
        set = function(on) ns.db.gear.setIcons = on and true or false; SI.Refresh() end,
    })
end
