-- Flow Banker: what to put in the bank, and one button that does it.
--
-- "When I pass through major cities, mention to stop by the bank to deposit
-- things I won't need until later ... a mode to bank suggested items, like
-- Flow Banker. Just make sure it isn't stuff I need right now or soon for
-- crafting." (0.35.200)
--
-- What goes to the bank: things Flow keeps for you but that nothing on your
-- route uses now: profession materials, trade goods you told Flow never to
-- sell, recipes waiting for skill. What never goes: quest items, tools, your
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
end

-- Pure: bank this row of the inventory? row: D.InventoryRows' ({ id, name,
-- action, rule, kind, count, stacks }); needed: { [itemID] = true } for what
-- a stop on your route uses. -> true / false, and why.
function B.Banks(row, needed)
    if type(row) ~= "table" or row.action ~= "keep" then return false, "not something Flow keeps" end
    if needed and row.id and needed[row.id] then return false, "a stop on your route uses it" end
    if stays(row.kind) then return false, "you carry it" end
    if B.LATER_RULES[row.rule or ""] then return true, "kept for later" end
    local kind = row.kind or ""
    if kind:find("^Trade Goods") or kind:find("^Recipe") then return true, "kept for later" end
    return false, "you carry it"
end

-- Pure: the rows to bank, biggest first.
function B.Pick(rows, needed)
    local out = {}
    for _, r in ipairs(rows or {}) do
        if B.Banks(r, needed) then out[#out + 1] = r end
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

-- The list right now: rows to bank.
function B.List()
    local D = ns.disposition
    if not (D and D.Inventory) then return {} end
    local ok, rows = pcall(D.Inventory, D)
    if not ok then return {} end
    return B.Pick(rows, B.Needed())
end

-------------------------------------------------------------------------------
-- Depositing (at an open bank)
-------------------------------------------------------------------------------
local bankOpen = false
local useItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem

function B.AtBank() return bankOpen end

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
        C_Timer.After(#slots * B.STEP + 0.5, function() if B.frame and B.frame:IsShown() then B:Fill() end end)
    end
    return #slots
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
local function build()
    local f = CreateFrame("Frame", "FlowBanker", UIParent)
    f:SetSize(330, 74 + B.ROWS * 15)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("LEFT", UIParent, "LEFT", 380, 60)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
    f.head = ns.theme:TitleBar(f, "Flow Banker", "Interface\\Icons\\INV_Misc_Bag_10")
    f:EnableMouse(true)
    tinsert(UISpecialFrames, "FlowBanker")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)   -- (our own: the game's handler can't close an add-on window in a fight)
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.note:SetPoint("TOPLEFT", 10, -28)
    f.note:SetPoint("TOPRIGHT", -10, -28)
    f.note:SetJustifyH("LEFT")
    f.rows = {}
    for i = 1, B.ROWS do
        local r = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r:SetPoint("TOPLEFT", 10, -46 - (i - 1) * 15)
        r:SetPoint("TOPRIGHT", -10, -46 - (i - 1) * 15)
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

function B:Fill()
    local f = B.frame
    if not f then return end
    local list = B.List()
    f.note:SetText(#list == 0 and "Nothing to put away: what's in your bags you carry or need soon."
        or string.format("%d stack(s) Flow keeps for later and nothing on your route uses now:", B.Stacks(list)))
    for i = 1, B.ROWS do
        local r = list[i]
        if r and i == B.ROWS and #list > B.ROWS then
            f.rows[i]:SetText(string.format("|cff999999... and %d more|r", #list - B.ROWS + 1))
        elseif r then
            f.rows[i]:SetText(string.format("%d x %s  |cff999999(%s)|r", r.count or 1, tostring(r.name), tostring(r.reason or "")))
        else
            f.rows[i]:SetText("")
        end
    end
    f.go:SetEnabled(bankOpen and #list > 0)
    f.go:SetText(bankOpen and "Deposit" or "At a bank")
end

function B:Open()
    B.frame = B.frame or build()
    B:Fill()
    B.frame:Show()
end
function B._Frame() return B.frame end

ns:On("BANKFRAME_OPENED", function()
    bankOpen = true
    if ns.db.banker.off then return end
    -- (Shown only when there's something to put away.)
    if #B.List() > 0 then B:Open() end
end)
ns:On("BANKFRAME_CLOSED", function()
    bankOpen = false
    if B.frame and B.frame:IsShown() then B.frame:Hide() end
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
    for i, l in ipairs(B.Lines()) do if i == 1 then ns:Print(l) else print("  " .. l) end end
    print("  /flow banker show (the window)   /flow banker on|off")
end
ns:Register("help", "banker", { order = 58, title = "Flow Banker", lines = {
    "At a bank, Flow Banker lists what you won't need soon (materials kept for later that no stop on your route uses) and deposits it at a click.",
    "/flow banker: the list. /flow banker show. /flow banker on|off.",
} })
