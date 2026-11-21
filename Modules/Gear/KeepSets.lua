-------------------------------------------------------------------------------
-- Flow - Gear/KeepSets.lua
-- "Keep set for": a tick for each of your specs, under your bags
-- (0.35.342).
--
-- "At the top of my bag it should have check marks ... let me check if I
-- should keep the gear set for tanking, for feral, or for resto. If I uncheck
-- them, just sell those items that I don't need because I'm not keeping that
-- set. And if those are checked, it should build those into the gear sets
-- that are built into the game itself."
--
--   * A spec that's ticked: gear that's better for it than what its set has
--     is kept ("better for Tank"), and so is what's in its set.
--   * A spec that isn't: neither is a reason to keep anything, so that gear
--     goes by the usual rules (sold, auctioned or disenchanted), unless
--     another ticked spec wants it. The spec you level as is always kept.
--   * "Build sets" (and ticking a spec that has no set yet) makes the game's
--     own equipment sets, one a ticked spec, named after the spec. The game
--     can only save a set from what you're wearing, so for a spec you aren't
--     wearing Flow puts on what's better for it from your bags, saves the
--     set, and puts your own gear back on. Out of a fight only.
--
-- The choice is per character (ns.db.gear.keepSet). Before 0.35.342 there
-- was one switch for all other specs (/flow gear offspec): a spec you haven't
-- ticked or unticked still goes by it.
-------------------------------------------------------------------------------

local _, ns = ...
local G = ns.gear
local K = {}
ns.keepSets = K

-- Under the bag window, below its money line (0.35.349: "move it to be below
-- the bag instead of on top where the Flow Banker tab is ... right below
-- where it shows my money"). It was above the top edge, over Flow's tabs.
K.Y = -2            -- the row hangs this far under the bag's bottom edge
K.STEP = 0.4        -- seconds between two pieces going on
K.SETTLE = 1.2      -- and after the last one, before the set is saved
K.MIN_DIFF = 0.5    -- "better" (as the keep rules have it)
K.autoBuild = true  -- ticking a spec with no set builds it (the tests turn this off)

-------------------------------------------------------------------------------
-- The ticks
-------------------------------------------------------------------------------

-- Pure: is this spec's gear kept? saved: your ticks ({ [role] = bool });
-- offspec: the old switch for every other spec; main: the spec you level as.
function K.Kept(role, saved, offspec, main)
    if role == main then return true end
    local v = saved and saved[role]
    if v ~= nil then return v and true or false end
    return offspec ~= false
end
function K.Keeps(role)
    local g = ns.db and ns.db.gear or {}
    return K.Kept(role, g.keepSet, g.keepOffspec, ns:LevelingRole())
end
-- Pure: the roles of a list that are kept. keeps(role) -> bool.
function K.KeptOf(roles, keeps)
    local out = {}
    for _, r in ipairs(roles or {}) do if keeps(r) then out[#out + 1] = r end end
    return out
end

local function changed()
    if ns.disposition then ns.disposition:Invalidate() end
    if ns.bagIcons and ns.bagIcons.MarkDirty then ns.bagIcons.MarkDirty() end
end

-- A tick was set. noBuild: don't make the game's set for it.
function K:Tick(role, on, noBuild)
    ns.db.gear.keepSet = ns.db.gear.keepSet or {}
    ns.db.gear.keepSet[role] = on and true or false
    changed()
    K:Refresh()
    if on and not noBuild and K.autoBuild and G.sets:HasEquipmentManager() and not G.sets:GameSet(role) then
        K:Build(role)
    end
end

-------------------------------------------------------------------------------
-- The game's equipment sets
-------------------------------------------------------------------------------

-- Pure: the set's name (the game allows 16 letters).
function K.SetName(specName) return tostring(specName or "Flow"):sub(1, 16) end

-- Pure: of things in your bags that are better for a spec, the best one a
-- kind of slot. cands: { { link, loc, diff } } -> the picks, best first.
function K.Best(cands, min)
    local byLoc, out = {}, {}
    for _, c in ipairs(cands or {}) do
        if c.link and c.loc and (c.diff or 0) >= (min or K.MIN_DIFF) then
            local cur = byLoc[c.loc]
            if not cur or c.diff > cur.diff then byLoc[c.loc] = c end
        end
    end
    for _, c in pairs(byLoc) do out[#out + 1] = c end
    table.sort(out, function(a, b)
        if a.diff ~= b.diff then return a.diff > b.diff end
        return tostring(a.link) < tostring(b.link)
    end)
    return out
end

-- What's in your bags that you can wear now and is better for this spec.
function K.Wants(role)
    local D, cands = ns.disposition, {}
    if not (D and D.EachBagItem) then return cands end
    local level = UnitLevel("player") or 1
    D:EachBagItem(function(_, _, link)
        local ok, g = pcall(G.Compare, G, link)
        if ok and g and g.canUse and g.item and g.diffs and (g.item.minLevel or 0) <= level then
            cands[#cands + 1] = { link = link, loc = g.item.equipLoc, diff = g.diffs[role] or 0 }
        end
    end)
    return K.Best(cands)
end

local CE = C_EquipmentSet
local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName

-- The spec whose set you're wearing now (the game says which set is on);
-- with none on, the one you level as.
function K.WornRole()
    if CE and CE.GetEquipmentSetInfo then
        for _, role in ipairs(G.ROLES) do
            local s = G.sets:GameSet(role)
            if s then
                local ok, _, _, _, isOn = pcall(CE.GetEquipmentSetInfo, s.id)
                if ok and isOn then return role end
            end
        end
    end
    return ns:LevelingRole()
end

-- Saves what you're wearing as this spec's set in the game (a new set named
-- after the spec, or the one the spec already has). -> the set's name, or nil and why.
function K.Save(role)
    if not G.sets:HasEquipmentManager() then return nil, "this game has no equipment sets" end
    if InCombatLockdown() then return nil, "in a fight" end
    local has = G.sets:GameSet(role)
    local name = has and has.name or K.SetName(ns:RoleName(role))
    -- A spec's set gets its spec's picture (0.35.375: "feral cat should have a cat icon"), else your chest's.
    local specIcon = ns.setRecipes and ns.setRecipes.GameIcon(ns:RoleIconPath(role)) or nil
    local icon = specIcon or (GetInventoryItemTexture and (GetInventoryItemTexture("player", 5) or GetInventoryItemTexture("player", 16))) or 134400
    local id = has and has.id or (CE.GetEquipmentSetID and CE.GetEquipmentSetID(name)) or nil
    local ok, err
    if id then ok, err = pcall(CE.SaveEquipmentSet, id)
    else ok, err = pcall(CE.CreateEquipmentSet, name, icon) end
    if not ok then
        ns:Log("gear", string.format("saving the %s set failed: %s", name, tostring(err)))
        return nil, tostring(err)
    end
    ns.db.gear.setRoles[role] = name
    G.sets:Refresh()
    changed()
    ns:Log("gear", string.format("%s the game's set '%s' for %s from what you wear", id and "updated" or "made", name, role))
    return name
end

-- Makes (or brings up to date) the game's set for a spec. For the spec
-- you're wearing: what you wear. For another: puts on what's better for it
-- from your bags, saves, and puts your own back on. done(ok, text) at the end.
function K:Build(role, done)
    done = done or function(_, text) if text then ns:Print(text) end end
    if not G.sets:HasEquipmentManager() then return done(false, "This game has no equipment sets to build.") end
    if InCombatLockdown() then return done(false, "Flow builds gear sets out of a fight.") end
    if K.building then return done(false, "Flow is still building your " .. ns:RoleName(K.building) .. " set.") end
    local label = ns:RoleName(role)
    local worn = K.WornRole()
    if role == worn then
        local name, why = K.Save(role)
        return done(name ~= nil, name and string.format("Your %s set is what you're wearing now (the game's set '%s').", label, name)
            or ("Couldn't save your " .. label .. " set: " .. tostring(why)))
    end
    local wants = K.Wants(role)
    if #wants == 0 then
        local name, why = K.Save(role)
        return done(name ~= nil, name and string.format("Nothing in your bags is better for %s than what you wear: the game's set '%s' is what you wear now.", label, name)
            or ("Couldn't save your " .. label .. " set: " .. tostring(why)))
    end
    if not equip then return done(false, "This game doesn't let Flow put gear on.") end
    -- What to come back to: your own set in the game (made now if it has none).
    if not G.sets:GameSet(worn) then K.Save(worn) end
    local back = G.sets:GameSet(worn)
    local before = {}
    for slot = 1, 19 do before[slot] = GetInventoryItemLink("player", slot) end
    K.building = role
    ns:Log("gear", string.format("building the %s set: putting on %d piece(s)", role, #wants))
    for i, w in ipairs(wants) do
        C_Timer.After((i - 1) * K.STEP, function()
            if K.building == role and not InCombatLockdown() then pcall(equip, w.link) end
        end)
    end
    C_Timer.After((#wants - 1) * K.STEP + K.SETTLE, function()
        if InCombatLockdown() then
            K.building = nil
            return done(false, string.format("A fight started while Flow was building your %s set: it isn't saved, and you may be wearing some of it.", label))
        end
        local name, why = K.Save(role)
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then
                if back and CE.UseEquipmentSet then pcall(CE.UseEquipmentSet, back.id)
                else for slot = 1, 19 do if before[slot] then pcall(equip, before[slot], slot) end end end
            end
            K.building = nil
            C_Timer.After(K.SETTLE, function() G.sets:Refresh(); changed(); K:Refresh() end)
            done(name ~= nil, name and string.format("Built your %s set (the game's set '%s') with %d piece(s) from your bags, and put your own gear back on.", label, name, #wants)
                or ("Couldn't save your " .. label .. " set: " .. tostring(why)))
        end)
    end)
end

-- Every ticked spec, one after the other: the one you wear first.
function K:BuildAll()
    local worn, queue = K.WornRole(), {}
    if K.Keeps(worn) then queue[#queue + 1] = worn end
    for _, role in ipairs(G.ROLES) do
        if role ~= worn and K.Keeps(role) then queue[#queue + 1] = role end
    end
    local function nextOne(i)
        local role = queue[i]
        -- (After your specs: the other sets Flow can build, Fishing: SetRecipes.lua.)
        if not role then
            if ns.setRecipes then ns.setRecipes.BuildOffered() end
            return
        end
        K:Build(role, function(ok, text)
            if text then ns:Print(text) end
            if ok then C_Timer.After(K.SETTLE + 0.5, function() nextOne(i + 1) end) end
        end)
    end
    nextOne(1)
    return #queue
end

-------------------------------------------------------------------------------
-- The row on your bags
-------------------------------------------------------------------------------
K.FRAMES = { "ContainerFrameCombinedBags", "ContainerFrame1" }
local bars = {}   -- [frame path] = the row

function K.On() return not (ns.db and ns.db.gear and ns.db.gear.keepBar == false) end

local function makeBar(frame)
    local win = ns.gameButtons.Window(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetHeight(20)
    bar:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 4, K.Y)
    bar:SetFrameLevel(math.min((win:GetFrameLevel() or 1) + 520, 9990))
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    local c = ns.theme.BAR
    bar.bg:SetColorTexture(c[1], c[2], c[3], c[4])
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.label:SetPoint("LEFT", 6, 0)
    bar.label:SetText("Keep set for:")
    local x = 6 + (bar.label:GetStringWidth() or 70) + 4
    bar.ticks = {}
    for _, role in ipairs(G.ROLES) do
        local cb = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("LEFT", x, 0)
        cb.role = role
        cb.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 0, 0)
        cb.label:SetText(ns:RoleName(role))
        cb:SetScript("OnClick", function(self)
            if self.role == ns:LevelingRole() then self:SetChecked(true) return end   -- (the spec you level as is always kept)
            K:Tick(self.role, self:GetChecked() and true or false)
        end)
        cb:SetScript("OnEnter", function(self)
            ns.Tip(self, "ANCHOR_TOPLEFT")
            GameTooltip:AddLine("Keep set for " .. ns:RoleName(self.role), 1, 1, 1)
            if self.role == ns:LevelingRole() then
                GameTooltip:AddLine("The spec you level as: always kept (/flow spec changes it).", 0.8, 0.8, 0.8, true)
            else
                GameTooltip:AddLine("Ticked: Flow keeps gear that's better for this spec, and what's in its set.", 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine("Unticked: that gear is sold, auctioned or disenchanted like any other you don't need.", 0.8, 0.8, 0.8, true)
            end
            local name, from = G.sets:SetFor(self.role)
            GameTooltip:AddLine(name and ("Its set: " .. name .. " (" .. tostring(from) .. ").") or "It has no set yet: Build sets makes one.", 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.ticks[role] = cb
        x = x + 20 + (cb.label:GetStringWidth() or 50) + 8
    end
    bar.build = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    bar.build:SetText("Build sets")
    bar.build:SetSize(math.max(70, ((bar.build:GetFontString() and bar.build:GetFontString():GetStringWidth()) or 60) + 18), 20)
    bar.build:SetPoint("LEFT", x, 0)
    bar.build:SetScript("OnClick", function() K:BuildClick() end)
    bar.build:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Build sets", 1, 1, 1)
        GameTooltip:AddLine("Makes the game's own equipment set for each ticked spec (character window, Equipment Manager), named after the spec.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("The spec you're wearing: saved as it is. Another: Flow puts on what's better for it from your bags, saves the set, and puts your own gear back on. Out of a fight only.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    bar.build:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar:SetWidth(x + bar.build:GetWidth() + 6)
    bar:SetScript("OnShow", function() K:Refresh() end)
    return bar
end

function K:BuildClick()
    if InCombatLockdown() then ns:Print("Flow builds gear sets out of a fight.") return 0 end
    return K:BuildAll()
end

-- The ticks as they stand.
function K:Refresh()
    local on = K.On()
    for _, bar in pairs(bars) do
        bar:SetShown(on)
        for role, cb in pairs(bar.ticks) do cb:SetChecked(K.Keeps(role)) end
        bar.build:SetEnabled(G.sets:HasEquipmentManager())
    end
end

function K:Attach()
    if not (ns.db and ns.db.gear and ns.gameButtons) then return end
    for _, path in ipairs(K.FRAMES) do
        if not bars[path] then
            local frame = ns.gameButtons.Resolve(path)
            if frame then
                local ok, bar = pcall(makeBar, frame)
                if ok then bars[path] = bar else ns:Log("gear", "keep-set row: " .. tostring(bar)) end
            end
        end
    end
    K:Refresh()
end
K._Bars = function() return bars end   -- (tests)

ns:On("ADDON_LOADED", function() K:Attach() end)
ns:On("PLAYER_ENTERING_WORLD", function() K:Attach() end)
ns:OnLoad(function(saved)
    saved.gear = saved.gear or {}
    saved.gear.keepSet = saved.gear.keepSet or {}
end)
ns:PerCharacter("gear.keepSet")

-- /flow keepsets: how it stands (also in the diagnostics).
function K.Lines()
    local out = { "Keep set for (ticks on your bags" .. (K.On() and "" or ", row off") .. "):" }
    for _, role in ipairs(G.ROLES) do
        local name, from = G.sets:SetFor(role)
        local okW, wants = pcall(K.Wants, role)
        out[#out + 1] = string.format("  %s: %s; set: %s; better for it in your bags: %s", ns:RoleName(role),
            K.Keeps(role) and "kept" or "not kept", name and (name .. " (" .. tostring(from) .. ")") or "none",
            okW and tostring(#wants) or "?")
    end
    out[#out + 1] = "  wearing: " .. tostring(K.WornRole()) .. "; rows on: " .. (function()
        local n = {}
        for path in pairs(bars) do n[#n + 1] = path end
        table.sort(n)
        return #n > 0 and table.concat(n, ", ") or "no bag window yet"
    end)()
    return out
end
ns.commands.keepsets = function(arg)
    arg = (arg or ""):lower()
    if arg == "build" then K:BuildClick() return end
    for i, l in ipairs(K.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
    print("  /flow keepsets build")
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "loot",
        label = "\"Keep set for\" ticks on your bags",
        note = "(a tick for each spec)",
        tip = "A row under your bags with a tick for each of your specs. Unticked: gear that's only good for that spec is sold like any other you don't need. "
            .. "Build sets makes the game's own equipment sets for the ticked ones. Off: the row is hidden; your ticks stay as they are.",
        get = function() return K.On() end,
        set = function(on) ns.db.gear.keepBar = on and true or false; K:Refresh() end,
    })
end
