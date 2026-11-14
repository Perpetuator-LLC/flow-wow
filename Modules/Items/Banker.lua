-- Flow Banker: what to put in the bank, and one button that does it.
--
-- "When I pass through major cities, mention to stop by the bank to deposit
-- things I won't need until later ... a mode to bank suggested items, like
-- Flow Banker. Just make sure it isn't stuff I need right now or soon for
-- crafting." (0.35.200)
--
-- What goes to the bank: things Flow keeps for you but that nothing on your
-- route uses now: profession materials, trade goods you told Flow never to
-- sell. What never goes: quest items, tools, recipes, your
-- hearthstone, food, water, bandages, potions, scrolls and anything to
-- equip; and any material a crafting stop on your route asks for (those you
-- need now or soon).
--
--   * At a bank: the Flow Banker window lists them; "Deposit" puts them in,
--     a stack at a time. Nothing moves until you click.
--   * On the route: "Bank: put N stacks away" when a banker is close to the
--     way you're going and there's enough to make it worth the stop
--     (B.MIN_STACKS). Its own tick under Route includes.
--   * /flow banker: the list, in chat (also in the diagnostics).
--   * Away from a bank: the window's "In your bank" view lists what Flow saw
--     there last time it was open, and "Auction prices" what Flow last saw at
--     the auction house. A "Flow Banker" tab on your bags opens it (0.35.203).
--
-- Not built yet: fetching things back as a stop before the crafting that
-- needs them (the profession plan already reads what's in your bank).

local _, ns = ...
local B = {}
ns.banker = B

B.MIN_STACKS = 4    -- a bank stop on the route is worth it from this many stacks
B.ROWS = 14         -- lines in the window
B.STEP = 0.25       -- seconds between two stacks going in

-- The rules that mark something Flow keeps for later (Disposition.lua).
B.LATER_RULES = { professionMaterial = true, neverSell = true }
-- Kinds that stay with you whatever the rule says.
local function stays(kind)
    kind = kind or ""
    return kind:find("^Quest") ~= nil or kind:find("^Consumable") ~= nil or kind:find("^Weapon") ~= nil
        or kind:find("^Armor") ~= nil or kind:find("^Container") ~= nil or kind:find("^Key") ~= nil
        -- (A recipe stays too: Flow only has you buy one when you can nearly
        -- learn it, and a banked one read as "not bought" (0.35.203).)
        or kind:find("^Recipe") ~= nil
end

-- Pure: bank this row of the inventory? row: D.InventoryRows' ({ id, name,
-- action, rule, kind, count, stacks }); needed: { [itemID] = true } for what
-- a stop on your route uses. -> true / false, and why.
-- rules: your own choices, { [itemID] = "bank" | "carry" } (Flow sets the
-- default, you can change it: click an item in the window, 0.35.216).
function B.Banks(row, needed, rules)
    if type(row) ~= "table" or row.action ~= "keep" then return false, "not something Flow keeps" end
    local mine = rules and row.id and rules[row.id]
    if mine == "carry" then return false, "you chose to carry it" end
    if mine == "bank" then return true, "you chose to bank it" end
    if needed and row.id and needed[row.id] then return false, "a stop on your route uses it" end
    if stays(row.kind) then return false, "you carry it" end
    if B.LATER_RULES[row.rule or ""] then return true, "kept for later" end
    local kind = row.kind or ""
    if kind:find("^Trade Goods") then return true, "kept for later" end
    return false, "you carry it"
end

-- Pure: the rows to bank, biggest first.
function B.Pick(rows, needed, rules)
    local out = {}
    for _, r in ipairs(rows or {}) do
        if B.Banks(r, needed, rules) then out[#out + 1] = r end
    end
    table.sort(out, function(a, b)
        if (a.stacks or 0) ~= (b.stacks or 0) then return (a.stacks or 0) > (b.stacks or 0) end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end
function B.Stacks(rows)
    local n = 0
    for _, r in ipairs(rows or {}) do n = n + (r.stacks or 1) end
    return n
end

-- Pure: item IDs the stops ask for. goals: stops with .reagents, either
-- { [itemID] = count } or a list of { id = itemID }.
function B.NeededBy(goals)
    local out = {}
    for _, g in ipairs(goals or {}) do
        if type(g.reagents) == "table" then
            for k, v in pairs(g.reagents) do
                if type(k) == "number" and type(v) == "number" and k > 100 then out[k] = true
                elseif type(v) == "table" and v.id then out[v.id] = true end
            end
        end
        if g.useItem then out[g.useItem] = true end
    end
    return out
end

-- What a stop on your route needs now (route, locked and hidden stops alike).
function B.Needed()
    local N = ns.nav
    if not N then return {} end
    local all = {}
    for _, list in ipairs({ N:Goals() or {}, N.blockedGoals or {}, N.hiddenGoals or {} }) do
        for _, g in ipairs(list) do all[#all + 1] = g end
    end
    return B.NeededBy(all)
end

-- Your own banking choices (saved for all your characters).
function B.Rules()
    ns.db.banker.rules = ns.db.banker.rules or {}
    return ns.db.banker.rules
end
-- Pure: the next choice for an item on a click. banks: it goes to the bank
-- now; mine: your choice so far (nil: Flow's). Left click flips it; a right
-- click (reset) goes back to Flow's own.
function B.NextRule(banks, mine, reset)
    if reset then return nil end
    if mine then return (mine == "bank") and "carry" or "bank" end
    return banks and "carry" or "bank"
end
-- Pure: every item Flow keeps, for the window: what goes to the bank first,
-- then what stays with you, each by name. -> { { id, name, count, bank,
-- why, mine } }
function B.PutCells(rows, needed, rules)
    local out = {}
    for _, r in ipairs(rows or {}) do
        if type(r) == "table" and r.action == "keep" and r.id then
            local bank, why = B.Banks(r, needed, rules)
            out[#out + 1] = { id = r.id, name = r.name, count = r.count or 1, bank = bank and true or false, why = why,
                              mine = rules and rules[r.id] or nil }
        end
    end
    table.sort(out, function(a, b)
        if a.bank ~= b.bank then return a.bank end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- The list right now: rows to bank.
function B.List()
    local D = ns.disposition
    if not (D and D.Inventory) then return {} end
    local ok, rows = pcall(D.Inventory, D)
    if not ok then return {} end
    return B.Pick(rows, B.Needed(), B.Rules())
end

-------------------------------------------------------------------------------
-- Depositing (at an open bank)
-------------------------------------------------------------------------------
local bankOpen = false
local useItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem

function B.AtBank() return bankOpen end

-- Auto-cleanup: after a deposit, the game's Clean Up on the bank, then on
-- your bags. The tick is in the window's header (on).
local function sortBank() return (C_Container and C_Container.SortBankBags) or _G.SortBankBags end
local function sortBags() return (C_Container and C_Container.SortBags) or _G.SortBags end
function B.AutoCleanup() return ns.db.banker.autoCleanup ~= false end
function B.CanCleanup() return sortBank() ~= nil or sortBags() ~= nil end
-- Pure: run it? moved: stacks just deposited.
function B.ShouldCleanup(moved, on, canSort, atBank, inCombat)
    return (moved or 0) > 0 and on ~= false and canSort and atBank and not inCombat
end
function B:Cleanup(moved)
    if not B.ShouldCleanup(moved, B.AutoCleanup(), B.CanCleanup(), B.AtBank(), InCombatLockdown()) then return false end
    local bank, bags = sortBank(), sortBags()
    local ok, err = true, nil
    if bank then ok, err = pcall(bank) end
    -- (The bags a moment later: the game does one tidy-up at a time.)
    if bags then C_Timer.After(1.5, function() if not InCombatLockdown() then pcall(bags) end end) end
    ns:Log("bank", ok and string.format("cleaned up after putting %d stack(s) away", moved) or ("bank cleanup failed: " .. tostring(err)))
    return true
end

-- Puts the listed items into the bank, one stack every B.STEP seconds.
-- Stops when the bank closes or a fight starts.
function B:Deposit()
    if not bankOpen or not useItem or InCombatLockdown() then return 0 end
    local want = {}
    for _, r in ipairs(B.List()) do if r.id then want[r.id] = true end end
    local slots = {}
    ns.disposition:EachBagItem(function(bag, slot, link)
        local id = tonumber(link:match("item:(%d+)"))
        if id and want[id] then slots[#slots + 1] = { bag, slot } end
    end)
    for i, s in ipairs(slots) do
        C_Timer.After((i - 1) * B.STEP, function()
            if bankOpen and not InCombatLockdown() then pcall(useItem, s[1], s[2]) end
        end)
    end
    if #slots > 0 then
        ns:Print(string.format("Flow Banker: putting %d stack(s) in the bank.", #slots))
        C_Timer.After(#slots * B.STEP + 0.5, function()
            if B.frame and B.frame:IsShown() then B:Fill() end
            B:Cleanup(#slots)
        end)
    end
    return #slots
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
local function build()
    local f = CreateFrame("Frame", "FlowBanker", UIParent)
    f:SetSize(330, 96 + B.ROWS * 15)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("LEFT", UIParent, "LEFT", 380, 60)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
    f.head = ns.theme:TitleBar(f, "Flow Banker", "Interface\\Icons\\INV_Misc_Bag_10")
    -- Auto-cleanup, as in the Flow Seller's header: after a deposit the game's
    -- own tidy-up runs on the bank and your bags (0.35.217).
    f.clean = CreateFrame("CheckButton", nil, f.head, "UICheckButtonTemplate")
    f.clean:SetSize(20, 20)
    f.clean:SetPoint("RIGHT", f.head, "RIGHT", -24, 0)
    f.clean.label = f.head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.clean.label:SetPoint("RIGHT", f.clean, "LEFT", 0, 0)
    f.clean.label:SetText("Auto-cleanup")
    f.clean:SetChecked(B.AutoCleanup())
    f.clean:SetScript("OnClick", function(self)
        ns.db.banker.autoCleanup = self:GetChecked() and true or false
        ns:Print("clean up the bank and your bags after a deposit " .. (B.AutoCleanup() and "on" or "off"))
    end)
    f.clean:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Auto-cleanup", 1, 1, 1)
        GameTooltip:AddLine(B.CanCleanup() and "After Deposit, Flow tidies your bank and your bags with the game's own Clean Up (the broom)."
            or "This client has no Clean Up for the bank or bags, so there's nothing for Flow to run.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.clean:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:EnableMouse(true)
    -- Ctrl-drag moves it, like Flow's other windows; where you put it is kept.
    local p = ns.db.banker.point
    if p then f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    ns:MakeMovable(f, setmetatable({}, { __newindex = function(_, key, v)
        if key == "point" then ns.db.banker.point = v end end }), true)
    tinsert(UISpecialFrames, "FlowBanker")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)   -- (our own: the game's handler can't close an add-on window in a fight)
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- The three views, as words under the title: the one showing is gold.
    f.tabs = {}
    for i, v in ipairs(B.VIEWS) do
        local tb = CreateFrame("Button", nil, f)
        tb:SetSize(100, 16)
        tb:SetPoint("TOPLEFT", 8 + (i - 1) * 104, -27)
        tb.text = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tb.text:SetPoint("LEFT")
        tb.text:SetText(v.label)
        tb:SetScript("OnClick", function() B:Show(v.key) end)
        f.tabs[v.key] = tb
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) B:Scroll(delta) end)
    f.note:SetPoint("TOPLEFT", 10, -50)
    f.note:SetPoint("TOPRIGHT", -10, -50)
    f.note:SetJustifyH("LEFT")
    f.rows = {}
    for i = 1, B.ROWS do
        local r = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r:SetPoint("TOPLEFT", 10, -68 - (i - 1) * 15)
        r:SetPoint("TOPRIGHT", -10, -68 - (i - 1) * 15)
        r:SetJustifyH("LEFT")
        r:SetWordWrap(false)
        f.rows[i] = r
    end
    f.go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.go:SetSize(120, 22)
    f.go:SetPoint("BOTTOM", 0, 8)
    f.go:SetText("Deposit")
    f.go:SetScript("OnClick", function() B:Deposit() end)
    f:Hide()
    return f
end

-- The window's views. "put": what to put away (the Deposit button). "bank":
-- what Flow saw in your bank when it was last open, readable anywhere.
-- "prices": what Flow last saw at the auction house.
B.VIEWS = {
    { key = "put", label = "To put away" },
    { key = "bank", label = "In your bank" },
    { key = "prices", label = "Auction prices" },
}
B.view, B.offset = "put", 0

-- Pure: "just now", "25 min ago", "3 h ago", "2 days ago".
function B.Ago(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds < 0 then return "some time ago" end
    if seconds < 90 then return "just now" end
    if seconds < 5400 then return math.floor(seconds / 60 + 0.5) .. " min ago" end
    if seconds < 129600 then return math.floor(seconds / 3600 + 0.5) .. " h ago" end
    return math.floor(seconds / 86400 + 0.5) .. " days ago"
end

local function nameOf(id)
    local ok, name = pcall(function() return ns.api.ItemInfo and ns.api.ItemInfo(id) end)
    if ok and type(name) == "string" and name ~= "" then return name end
    -- (Not loaded yet: ask the game for it, the next fill has the name.)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return nil
end

-- Pure: the bank's rows, by name. items: { [itemID] = count }; name(id) ->
-- its name or nil. -> { { id, name, count } }.
function B.BankRows(items, name)
    local out = {}
    for id, c in pairs(items or {}) do
        if type(id) == "number" and type(c) == "number" and c > 0 then
            out[#out + 1] = { id = id, name = (name and name(id)) or ("item " .. id), count = c }
        end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

-- Pure: the auction prices' rows, by name. prices: { [itemID] = { price, at } }.
function B.PriceRows(prices, name)
    local out = {}
    for id, e in pairs(prices or {}) do
        if type(id) == "number" and type(e) == "table" and tonumber(e.price) then
            out[#out + 1] = { id = id, name = (name and name(id)) or ("item " .. id), price = e.price, at = e.at }
        end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

-- Pure: the lines for a window of `rows` lines over `n` things, starting
-- after `offset`: first and last index shown, and how many are below.
function B.Window(n, offset, rows)
    local maxOff = math.max(0, n - rows)
    offset = math.max(0, math.min(offset or 0, maxOff))
    local last = math.min(n, offset + rows)
    return offset + 1, last, n - last, offset
end

-- What a view shows now: the line above the list, and its lines of text.
function B.ViewLines(view)
    local now = time()
    if view == "bank" then
        local bank = ns.db.bank or {}
        local rows = B.BankRows(bank.items, nameOf)
        local out = {}
        for _, r in ipairs(rows) do out[#out + 1] = string.format("%d x %s", r.count, r.name) end
        if not bank.seenAt then
            return "Flow hasn't seen inside your bank yet. Open it once and Flow remembers what's there.", out
        end
        return string.format("%d thing(s) in your bank, as Flow saw it %s:", #rows, B.Ago(now - bank.seenAt)), out
    elseif view == "prices" then
        local AH = ns.auction
        local prices = {}
        if AH and AH.Prices then
            local ok, p = pcall(AH.Prices, AH)
            if ok and type(p) == "table" then prices = p end
        end
        local rows = B.PriceRows(prices, nameOf)
        local out = {}
        for _, r in ipairs(rows) do
            out[#out + 1] = string.format("%s  |cffffd100%s|r each  |cff999999(%s)|r", r.name, AH.Money(r.price), B.Ago(now - (r.at or 0)))
        end
        if #rows == 0 then
            return "No auction prices yet: Flow reads them when you open the auction house.", out
        end
        return string.format("The cheapest buyout Flow last saw, for %d item(s):", #rows), out
    end
    local list = B.List()
    local out = {}
    for _, r in ipairs(list) do
        out[#out + 1] = string.format("%d x %s  |cff999999(%s)|r", r.count or 1, tostring(r.name), tostring(r.reason or ""))
    end
    if #list == 0 then return "Nothing to put away: what's in your bags you carry or need soon.", out end
    return string.format("%d stack(s) Flow keeps for later and nothing on your route uses now:", B.Stacks(list)), out
end

-------------------------------------------------------------------------------
-- "In your bank", drawn as the bank looks: a grid of slots, read only
-------------------------------------------------------------------------------
-- "Flow Banker ... to look like it does when I'm at the actual bank, just
-- read-only" (0.35.215). Each slot in the bank's own order, with its icon
-- and count; empty slots stay empty squares. Hover a slot for the item.
-- Nothing can be moved from here: it's a picture of what Flow last saw.
-- (A bank Flow saw before 0.35.215 has no slot order kept: its things are
-- shown by name, without the empty slots, until you open the bank again.)
B.COLS, B.GRID_ROWS, B.CELL = 8, 6, 34

-- Pure: the grid's cells. layout: the bank slot by slot ({ id, count } or
-- false); without one, items ({ [id] = count }) by name. -> { { id, count }
-- or false }, and whether it's the bank's own order.
function B.Cells(layout, items, name)
    if type(layout) == "table" and #layout > 0 then
        local out = {}
        for i, s in ipairs(layout) do
            out[i] = (type(s) == "table" and s[1]) and { id = s[1], count = s[2] or 1 } or false
        end
        return out, true
    end
    local out = {}
    for _, r in ipairs(B.BankRows(items, name)) do out[#out + 1] = { id = r.id, count = r.count } end
    return out, false
end

-- Pure: which cells show. n cells, scrolled down `offset` rows.
--   -> first cell, the offset in range, rows below the last one shown
function B.GridWindow(n, offset, cols, rows)
    local total = math.ceil((n or 0) / cols)
    local maxOff = math.max(0, total - rows)
    offset = math.max(0, math.min(offset or 0, maxOff))
    return offset * cols + 1, offset, maxOff - offset
end

local function makeCell(f, i)
    local c = CreateFrame("Frame", nil, f)
    c:SetSize(B.CELL - 2, B.CELL - 2)
    local col, row = (i - 1) % B.COLS, math.floor((i - 1) / B.COLS)
    c:SetPoint("TOPLEFT", 14 + col * B.CELL, -68 - row * B.CELL)
    c.edge = c:CreateTexture(nil, "BACKGROUND", nil, 1)
    c.edge:SetPoint("TOPLEFT", -1, 1); c.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    c.edge:SetColorTexture(0.3, 0.3, 0.33, 0.9)
    c.back = c:CreateTexture(nil, "BACKGROUND", nil, 2)
    c.back:SetAllPoints()
    c.back:SetColorTexture(0.08, 0.08, 0.1, 1)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetAllPoints()
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.count = c:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    c.count:SetPoint("BOTTOMRIGHT", -1, 1)
    c:EnableMouse(true)
    c:SetScript("OnEnter", function(self)
        if not self.id then return end
        ns.Tip(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) end
        GameTooltip:AddLine(" ")
        local cell = self.cell
        if cell then
            GameTooltip:AddLine(cell.bank and "Goes to the bank" or "Stays with you", cell.bank and 0.2 or 0.8, cell.bank and 0.9 or 0.8, cell.bank and 0.3 or 0.8)
            GameTooltip:AddLine((cell.mine and "Your choice. " or "Flow's choice: ") .. tostring(cell.why) .. ".", 1, 1, 1, true)
            GameTooltip:AddLine("Click: " .. (cell.bank and "keep it with you" or "put it in the bank") .. ". Right-click: Flow's own choice.", 0.6, 0.6, 0.6, true)
        else
            GameTooltip:AddLine("In your bank, as Flow last saw it. Go to a bank to take it out.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:SetScript("OnMouseUp", function(self, button) B:CellClick(self, button) end)
    c:Hide()
    return c
end

-- A cell of the "to put away" view: green edge = goes to the bank, grey and
-- dimmed = stays with you, gold = your own choice. (nil: a plain bank slot.)
function B.StyleCell(c, cell)
    if not cell then
        c.edge:SetColorTexture(0.3, 0.3, 0.33, 0.9)
        c.icon:SetDesaturated(false)
        c.icon:SetAlpha(1)
        return
    end
    if cell.mine then c.edge:SetColorTexture(1, 0.82, 0.1, 1)
    elseif cell.bank then c.edge:SetColorTexture(0.2, 0.9, 0.3, 1)
    else c.edge:SetColorTexture(0.3, 0.3, 0.33, 0.9) end
    c.icon:SetDesaturated(not cell.bank)
    c.icon:SetAlpha(cell.bank and 1 or 0.6)
end
-- A click on a cell of that view: bank it or carry it; right-click: Flow's own choice.
function B:CellClick(c, button)
    local cell = c and c.cell
    if not cell then return false end
    B.Rules()[cell.id] = B.NextRule(cell.bank, cell.mine, button == "RightButton")
    if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("banking choice") end
    B:Fill()
    return true
end

-- Fills (or hides) the grid. -> the line above it, when it shows.
function B:FillGrid(show)
    local f = B.frame
    if not f then return nil end
    f.cells = f.cells or {}
    if not show then
        for _, c in ipairs(f.cells) do c:Hide() end
        return nil
    end
    local bank = ns.db.bank or {}
    local cells, own
    if show == "put" then
        -- What Flow keeps in your bags: to the bank (green) or with you (grey).
        local D = ns.disposition
        local okR, rows = pcall(D.Inventory, D)
        cells = B.PutCells(okR and rows or {}, B.Needed(), B.Rules())
    else
        cells, own = B.Cells(bank.layout, bank.items, nameOf)
    end
    local first, offset, below = B.GridWindow(#cells, B.offset, B.COLS, B.GRID_ROWS)
    B.offset = offset
    local used = 0
    for _, s in ipairs(cells) do if s then used = used + 1 end end
    for i = 1, B.COLS * B.GRID_ROWS do
        local c = f.cells[i] or makeCell(f, i)
        f.cells[i] = c
        local s = cells[first + i - 1]
        if s == nil then
            c:Hide()
        else
            c.id = s and s.id or nil
            c.cell = (show == "put") and s or nil
            B.StyleCell(c, c.cell)
            if s then
                c.icon:SetTexture((ns.api.ItemIcon and ns.api.ItemIcon(s.id))
                    or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(s.id))
                    or "Interface\\Icons\\INV_Misc_QuestionMark")
                c.icon:Show()
                c.count:SetText((s.count or 1) > 1 and s.count or "")
            else
                c.icon:Hide()
                c.count:SetText("")
            end
            c:Show()
        end
    end
    if show == "put" then
        local n = 0
        for _, s in ipairs(cells) do if s.bank then n = n + 1 end end
        return string.format("Green: to the bank (%d). Grey: stays with you. Click one to change it; right-click: Flow's own choice.%s", n,
            (below > 0 or offset > 0) and " Scroll for more." or "")
    end
    if not bank.seenAt then return "Flow hasn't seen inside your bank yet. Open it once and Flow remembers what's there." end
    return string.format("Your bank as Flow saw it %s: %d slot(s) used%s.%s", B.Ago(time() - bank.seenAt), used,
        own and string.format(" of %d", #cells) or "", (below > 0 or offset > 0) and " Scroll for more." or "")
end

function B:Fill()
    local f = B.frame
    if not f then return end
    local note, lines = B.ViewLines(B.view)
    -- The bank is a grid of slots, not a list (FillGrid, above).
    local gridView = B.view == "bank" or B.view == "put"
    local grid = B:FillGrid(gridView and B.view or nil)
    local putCount = B.view == "put" and #lines or 0
    if gridView then note, lines = grid or note, {} end
    f.note:SetText(note)
    local first, last, below = 1, 0, 0
    if not gridView then
        local offset
        first, last, below, offset = B.Window(#lines, B.offset, B.ROWS)
        B.offset = offset
    end
    for i = 1, B.ROWS do
        local at = first + i - 1
        local text = at <= last and lines[at] or ""
        if i == B.ROWS and below > 0 then
            text = string.format("|cff999999... and %d more (scroll)|r", below + 1)
        end
        f.rows[i]:SetText(text)
    end
    for key, tb in pairs(f.tabs) do
        if key == B.view then tb.text:SetTextColor(1, 0.82, 0) else tb.text:SetTextColor(0.6, 0.6, 0.6) end
    end
    f.go:SetShown(B.view == "put")
    f.go:SetEnabled(bankOpen and putCount > 0)
    f.go:SetText(bankOpen and "Deposit" or "At a bank")
end

function B:Scroll(delta)
    -- (The bank's grid moves a row of slots a notch; the lists three lines.)
    B.offset = math.max(0, (B.offset or 0) - (delta or 0) * ((B.view == "bank" or B.view == "put") and 1 or 3))
    B:Fill()
end

-- Opens the window on a view ("put" when none is named).
function B:Show(view)
    B.frame = B.frame or build()
    local known = false
    for _, v in ipairs(B.VIEWS) do if v.key == view then known = true end end
    B.view, B.offset = known and view or "put", 0
    B:Fill()
    B.frame:Show()
end
function B:Open() B:Show("put") end
-- The tab on your bags: at a bank, what to put away; anywhere else, what's
-- in your bank. A second click closes it.
function B:Toggle()
    if B.frame and B.frame:IsShown() then B.frame:Hide() return end
    B:Show(bankOpen and "put" or "bank")
end
function B._Frame() return B.frame end

ns:Register("gameButton", "bags", {
    order = 50,
    frames = { "ContainerFrameCombinedBags", "ContainerFrame1" },
    label = "Flow Banker",
    tip = "What's in your bank (as Flow last saw it), what to put away at the next bank, and the auction prices Flow last saw.",
    isOpen = function() return B.frame and B.frame:IsShown() end,
    click = function() B:Toggle() end,
})

ns:On("BANKFRAME_OPENED", function()
    bankOpen = true
    if ns.db.banker.off then return end
    -- (Shown only when there's something to put away.)
    if #B.List() > 0 then B:Open() end
end)
ns:On("BANKFRAME_CLOSED", function()
    bankOpen = false
    -- (The list of what to put away closes with the bank; a look at what's in
    -- the bank or at prices stays.)
    if B.frame and B.frame:IsShown() then
        if B.view == "put" then B.frame:Hide() else B:Fill() end
    end
end)
ns:OnLoad(function(saved) saved.banker = saved.banker or {} end)

-------------------------------------------------------------------------------
-- On the route: a bank stop when one is on your way and it's worth it
-------------------------------------------------------------------------------
-- Pure: worth a stop? stacks to put away; free: bag slots left (nil: unknown).
function B.WorthAStop(stacks, free, min)
    if (stacks or 0) >= (min or B.MIN_STACKS) then return true end
    return (stacks or 0) > 0 and free ~= nil and free <= 2
end

local cache = { at = 0, goals = nil }
ns:Register("navGoal", "banker", {
    collect = function()
        if ns.db.banker.off then return nil end
        local now = GetTime()
        if now - cache.at < 5 then return cache.goals end
        cache.at, cache.goals = now, nil
        local S = ns.services
        if not (S and S.All) or bankOpen then return nil end
        local stacks = B.Stacks(B.List())
        local free = ns.export and ns.export.BagsFree and ns.export.BagsFree() or nil
        if not B.WorthAStop(stacks, free) then return nil end
        local ok, bankers = pcall(S.All, S, "bank", 6)
        if not ok or #bankers == 0 then return nil end
        local points = {}
        for _, b in ipairs(bankers) do points[#points + 1] = { map = b.map, x = b.x, y = b.y } end
        cache.goals = { {
            key = "bank", kind = "merchant", optional = true, weight = 1, points = points,
            title = "Flow Banker", text = string.format("Bank: put %d stack(s) away", stacks),
            details = { "Things Flow keeps for later that nothing on your route uses now. At the banker, Flow Banker lists them: one click puts them in.",
                        "Only on the route while a bank is close to the way you're going." },
        } }
        return cache.goals
    end,
})
ns:Register("routeKind", "banker", { order = 62, default = true,
    label = "The bank (when you pass one with things to put away)", short = "bank",
    tip = "A stop at a banker that's close to your way, when your bags hold a few stacks Flow keeps for later and nothing on your route needs now.",
    match = function(g) return g.provider == "banker" end })

-- /flow banker: the list (on|off: the window and the stop).
function B.Lines()
    local list = B.List()
    local out = { string.format("Flow Banker: %d stack(s) to put away%s", B.Stacks(list), ns.db.banker.off and " (off)" or "") }
    for _, r in ipairs(list) do
        out[#out + 1] = string.format("%d x %s [%s] in %d slot(s): %s", r.count or 1, tostring(r.name), tostring(r.id), r.stacks or 1, tostring(r.reason))
    end
    return out
end
ns.commands.banker = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.banker.off = (arg == "off") or nil
        ns:Print("Flow Banker " .. arg)
        return
    end
    if arg == "show" then B:Open() return end
    if arg == "bank" or arg == "prices" then B:Show(arg) return end
    for i, l in ipairs(B.Lines()) do if i == 1 then ns:Print(l) else print("  " .. l) end end
    print("  /flow banker show (the window)   /flow banker bank (what's in your bank)   /flow banker prices   /flow banker on|off")
end
ns:Register("help", "banker", { order = 58, title = "Flow Banker", lines = {
    "At a bank, Flow Banker lists what you won't need soon (materials kept for later that no stop on your route uses) and deposits it at a click.",
    "Away from a bank, its \"In your bank\" view lists what was there when you last opened it, and \"Auction prices\" what Flow last saw at the auction house. The Flow Banker tab on your bags opens it.",
    "/flow banker: the list. /flow banker show | bank | prices. /flow banker on|off.",
} })
