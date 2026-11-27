-- Flow Batch: make several things at once in any profession window
-- (smelting, curing hides, bandages, anything with materials). It lists
-- every recipe your bags hold the materials for, with how many you can make.
-- Tick the ones you want (three of the eight, say), leave the count empty
-- for "all you can" or type a number, then press Make: each press starts
-- the next ticked recipe for its count, through the game's own crafting call.
--
-- One press per recipe, never a chain: crafting has to start from your click,
-- so Flow can't start the next recipe by itself when one finishes. The button
-- says what the next press makes, and waits while a batch is still going.
--
-- Opened from the "Flow Batch" tab on the profession window. The picks are
-- for this session only: what you hold changes, so a saved pick would be stale.

local _, ns = ...
local A = ns.api
local B = {}
ns.craftBatch = B

B.MAX_ROWS = 18     -- rows shown; more than that are counted under the list
local WIDTH, ROW_H = 300, 20
local frame
B.picks = {}        -- [recipe] = count (a number) or "all"

-------------------------------------------------------------------------------
-- Pure parts (the tests pass their own tables in)
-------------------------------------------------------------------------------

-- How many of one recipe your bags make: the material you run out of first.
-- nil reagents, an empty list or a partly read one: 0 (Flow can't tell).
function B.CanMake(r, bagsOf)
    if not (r and r.reagents and next(r.reagents)) or r.partial then return 0 end
    local n
    for id, q in pairs(r.reagents) do
        if q and q > 0 then
            local k = math.floor((bagsOf(id) or 0) / q)
            n = n and math.min(n, k) or k
        end
    end
    return math.max(0, n or 0)
end

-- Every recipe you can make at least one of now, by name:
-- { recipe, count, reagents, diff }. known: ns.recipes:Known(prof).
function B.Rows(known, bagsOf)
    bagsOf = bagsOf or A.Count
    local out = {}
    for name, r in pairs(known or {}) do
        local n = B.CanMake(r, bagsOf)
        if n > 0 then out[#out + 1] = { recipe = name, count = n, reagents = r.reagents, diff = r.diff } end
    end
    table.sort(out, function(a, b) return a.recipe < b.recipe end)
    return out
end

-- What the ticks make, in the list's order: { { recipe, n } }. A count over
-- what your bags make is cut to that; "all" (or no number) is all of it.
function B.Queue(rows, picks)
    local out = {}
    for _, row in ipairs(rows or {}) do
        local want = picks and picks[row.recipe]
        if want then
            local n = (want == "all" or not tonumber(want)) and row.count or math.min(row.count, math.floor(tonumber(want)))
            if n > 0 then out[#out + 1] = { recipe = row.recipe, n = n } end
        end
    end
    return out
end

-- The Make button's text: what the next press does.
function B.ButtonText(queue, busy)
    if busy then return "Making..." end
    local q = queue and queue[1]
    if not q then return "Tick what to make" end
    if #queue == 1 then return string.format("Make %d x %s", q.n, q.recipe) end
    return string.format("Make %d x %s (1 of %d)", q.n, q.recipe, #queue)
end

-- "all", a whole number of at least 1, or nil (no tick) from a count box's text.
function B.ParseCount(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    if text == "" then return "all" end
    local n = tonumber(text)
    if n and n >= 1 then return math.floor(n) end
    return nil
end

-------------------------------------------------------------------------------
-- In the game
-------------------------------------------------------------------------------

-- A batch (or one craft) is still being made: the next press must wait, or
-- the game says "Another action is in progress" and the pick is lost.
function B.Busy()
    local CB = ns.craftBar
    local b = CB and CB.Current and CB.Current()
    if b and not b.stopped and b.done < b.total then return true end
    return (A.Casting and A.Casting()) and true or false
end

local function profession()
    local H = ns.craftHint
    if H and H.OpenProfession then return H.OpenProfession() end
end

function B.CurrentRows()
    local prof, win = profession()
    if not prof then return {}, nil, nil end
    local known = ns.recipes and ns.recipes:Known(prof)
    return B.Rows(known), prof, win
end

-- One press of Make: starts the next ticked recipe and unticks it, so the
-- list shows what's still to do. True when something was started.
function B.MakeNext(rows, craft)
    craft = craft or (ns.craftHint and ns.craftHint.Craft)
    if B.Busy() then
        ns:Print("Flow Batch: still making the last one. Press Make again when it's done.")
        return false
    end
    local q = B.Queue(rows, B.picks)[1]
    if not q then return false end
    if not (craft and craft(q.recipe, q.n)) then
        ns:Print("Flow Batch: couldn't start " .. q.recipe .. " in this profession window.")
        return false
    end
    -- (Kept for a moment: if the game refuses the craft, its tick comes back.)
    B.started = { recipe = q.recipe, pick = B.picks[q.recipe], at = GetTime() }
    B.picks[q.recipe] = nil
    return true
end

-- The game refused what Make just started ("Requires Forge", no room in your
-- bags): the recipe was found, so it was unticked, and nothing was made.
-- Pure: the tick to put back ({ recipe, pick }), or nil. started: what Make
-- last started; now: the time; busy: a craft is under way (then it took).
B.REFUSE_WINDOW = 1.5
function B.Refused(started, now, busy)
    if not started or busy then return nil end
    if (now or 0) - (started.at or 0) > B.REFUSE_WINDOW then return nil end
    return started
end
ns:On("UI_ERROR_MESSAGE", function()
    local back = B.Refused(B.started, GetTime(), B.Busy())
    if not back then return end
    B.started = nil
    B.picks[back.recipe] = back.pick
    if B.Refresh then pcall(B.Refresh, B) end
end)

local function rowFor(i)
    local r = frame.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, frame)
    r:SetSize(WIDTH - 16, ROW_H)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(20, 20); r.check:SetPoint("LEFT")
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetPoint("LEFT", r.check, "RIGHT", 2, 0)
    r.label:SetPoint("RIGHT", r, "RIGHT", -52, 0)
    r.label:SetJustifyH("LEFT")
    r.count = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
    r.count:SetSize(36, 16); r.count:SetPoint("RIGHT", -4, 0)
    r.count:SetAutoFocus(false); r.count:SetNumeric(true); r.count:SetMaxLetters(4)
    r.check:SetScript("OnClick", function(self)
        if not r.recipe then return end
        if self:GetChecked() then B.picks[r.recipe] = B.ParseCount(r.count:GetText()) or "all"
        else B.picks[r.recipe] = nil end
        B:Refresh()
    end)
    local function countChanged(self)
        if r.recipe and B.picks[r.recipe] then B.picks[r.recipe] = B.ParseCount(self:GetText()) or "all" end
        self:ClearFocus()
        B:Refresh()
    end
    r.count:SetScript("OnEnterPressed", countChanged)
    r.count:SetScript("OnEditFocusLost", function(self)
        if r.recipe and B.picks[r.recipe] then B.picks[r.recipe] = B.ParseCount(self:GetText()) or "all" end
    end)
    r.count:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        if not self.row then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.row.recipe, 1, 1, 1)
        GameTooltip:AddLine(string.format("Your bags make %d.", self.row.count), 0.8, 0.8, 0.8)
        local ids = {}
        for id in pairs(self.row.reagents or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local H = ns.craftHint
            local name = (H and H._itemName and H._itemName(id)) or ("item " .. id)
            GameTooltip:AddLine(string.format("%d x %s (you have %d)", self.row.reagents[id], name, A.Count(id) or 0), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("Leave the count empty for all you can make.", 0.6, 0.9, 1, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.rows[i] = r
    return r
end

local function build()
    local f = CreateFrame("Frame", "FlowBatch", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(WIDTH, 120)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.06, 0.05, 0.08, 0.92)
        local o = ns.theme.arrow
        f:SetBackdropBorderColor(o[1], o[2], o[3], 1)
    end
    f.title = ns.theme:TitleBar(f, "Flow Batch", "Interface\\Icons\\Trade_BlackSmithing")
    f.close = CreateFrame("Button", nil, f.title, "UIPanelCloseButton")
    f.close:SetSize(20, 20); f.close:SetPoint("RIGHT", -2, 0)
    f.close:SetScript("OnClick", function() f:Hide() end)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("TOPLEFT", 8, -(ns.theme.TITLE_H + 4))
    f.hint:SetWidth(WIDTH - 16); f.hint:SetJustifyH("LEFT")
    f.hint:SetText("Tick what to make. Count: empty for all you can.")
    f.all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.all:SetSize(70, 20)
    f.all:SetText("Tick all")
    f.all:SetScript("OnClick", function()
        for _, row in ipairs(B.CurrentRows()) do B.picks[row.recipe] = B.picks[row.recipe] or "all" end
        B:Refresh()
    end)
    f.clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.clear:SetSize(60, 20)
    f.clear:SetText("Clear")
    f.clear:SetScript("OnClick", function() wipe(B.picks); B:Refresh() end)
    f.more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.make = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.make:SetSize(WIDTH - 16, 24)
    f.make:SetScript("OnClick", function()
        -- (Only the rows: B.CurrentRows also returns the profession and its window,
        -- and handed on whole the profession's name became MakeNext's `craft`, so
        -- every press of Make ended in an error and made nothing. 0.35.408.)
        local rows = B.CurrentRows()
        B.MakeNext(rows)
        B:Refresh()
    end)
    f.rows = {}
    f:SetScript("OnHide", function() GameTooltip:Hide() end)
    f:Hide()
    frame = f
    return f
end

function B._Frame() return frame end
function B.Frame() return frame or build() end

function B:Refresh()
    if not (frame and frame:IsShown()) then return end
    local rows, prof, win = B.CurrentRows()
    if not prof then frame:Hide() return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", win, "TOPRIGHT", 4, 0)
    -- Ticks for what you can't make any more go: no stale "1 of 3".
    local can = {}
    for _, row in ipairs(rows) do can[row.recipe] = true end
    for recipe in pairs(B.picks) do if not can[recipe] then B.picks[recipe] = nil end end
    local y = ns.theme.TITLE_H + 4 + 14
    local shown = math.min(#rows, B.MAX_ROWS)
    for i = 1, shown do
        local row, r = rows[i], rowFor(i)
        r.row, r.recipe = row, row.recipe
        r.label:SetText(string.format("%s |cff999999(%d)|r", row.recipe, row.count))
        local pick = B.picks[row.recipe]
        r.check:SetChecked(pick and true or false)
        if not r.count:HasFocus() then r.count:SetText(type(pick) == "number" and tostring(pick) or "") end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -y)
        r:Show()
        y = y + ROW_H
    end
    for i = shown + 1, #frame.rows do frame.rows[i]:Hide(); frame.rows[i].row, frame.rows[i].recipe = nil, nil end
    frame.more:ClearAllPoints()
    if #rows == 0 then
        frame.more:SetText("Your bags hold the materials for nothing in " .. prof .. " yet.")
        frame.more:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -y); frame.more:Show(); y = y + 16
    elseif #rows > shown then
        frame.more:SetText(string.format("+%d more you can make", #rows - shown))
        frame.more:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -y); frame.more:Show(); y = y + 16
    else
        frame.more:Hide()
    end
    y = y + 4
    frame.all:ClearAllPoints(); frame.all:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -y)
    frame.clear:ClearAllPoints(); frame.clear:SetPoint("LEFT", frame.all, "RIGHT", 4, 0)
    y = y + 24
    local queue, busy = B.Queue(rows, B.picks), B.Busy()
    frame.make:ClearAllPoints(); frame.make:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -y)
    frame.make:SetText(B.ButtonText(queue, busy))
    frame.make:SetEnabled(#queue > 0 and not busy and not InCombatLockdown())
    frame:SetHeight(y + 32)
end

function B:Open()
    B.Frame():Show()
    B:Refresh()
end

function B:Toggle()
    local f = B.Frame()
    if f:IsShown() then f:Hide() else B:Open() end
end

-- What you hold changes as you make things: the counts and the button follow.
local pending
local function soon()
    if pending or not (frame and frame:IsShown()) then return end
    pending = true
    C_Timer.After(0.4, function() pending = nil; pcall(B.Refresh, B) end)
end
for _, ev in ipairs({ "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "BAG_UPDATE_DELAYED",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
    ns:On(ev, soon)
end
ns:On("TRADE_SKILL_CLOSE", function() if frame then frame:Hide() end end)

ns:Register("gameButton", "batch", {
    order = 31,
    frames = { "ProfessionsFrame", "TradeSkillFrame" },
    label = "Flow Batch",
    x = -180,
    tip = "Make several things at once: tick the recipes you want (smelting, curing hides, anything your bags have the materials for), set a count or leave it for all you can, and press Make for each.",
    isOpen = function() return frame and frame:IsShown() end,
    click = function() B:Toggle() end,
})

ns.commands.batch = function() B:Toggle() end

ns:Register("help", "batch", { order = 48, title = "Flow Batch", lines = {
    "The Flow Batch tab on a profession window lists what your bags can make. Tick some, set a count (empty = all), press Make once per recipe.",
    "/flow batch: open or close it while a profession window is open.",
} })
