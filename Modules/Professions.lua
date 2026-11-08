-- Your profession plan. Flow suggests one (from class data: for a paladin
-- Mining + Blacksmithing, plus First Aid and Cooking, Fishing optional), but
-- you choose. No pop-up: from level 3 the advice list offers "Choose your
-- professions", and /flow setup has a row for it (/flow professions too).
-- The plan decides which trainers and skill-up stops appear on the route.

local _, ns = ...
local P = {}
ns.professions = P

local PRIMARY = { "Mining", "Herbalism", "Skinning", "Blacksmithing", "Engineering", "Alchemy",
                  "Leatherworking", "Tailoring", "Enchanting" }
local SECONDARY = { "First Aid", "Cooking", "Fishing" }
local IS_PRIMARY = {}
for _, n in ipairs(PRIMARY) do IS_PRIMARY[n] = true end

local function suggested()
    local d = ns:ClassData()
    return d and d.leveling and d.leveling.professions or {}
end

-- The plan in use: yours if you chose one, otherwise Flow's suggestion.
function ns:ProfessionPlan()
    local mine = ns.db.prof and ns.db.prof.plan
    if mine then return mine end
    return suggested()
end

-------------------------------------------------------------------------------
-- Picker
-------------------------------------------------------------------------------

local frame

local function build()
    local f = CreateFrame("Frame", "FlowProfessions", UIParent)
    f:SetSize(360, 330)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    tinsert(UISpecialFrames, "FlowProfessions")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    local top = f:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
    top:SetColorTexture(1, 0.82, 0.25, 0.9)
    ns:MakeMovable(f, ns.db.prof, true)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Your professions")
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.note:SetPoint("TOPLEFT", 14, -34)
    f.note:SetWidth(330)
    f.note:SetJustifyH("LEFT")

    f.checks = {}
    local function column(list, x, header)
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", x, -70)
        h:SetText(header)
        for i, name in ipairs(list) do
            local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            c:SetSize(22, 22)
            c:SetPoint("TOPLEFT", x - 4, -84 - (i - 1) * 22)
            c.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
            c.name = name
            c:SetScript("OnClick", function(self)
                -- At most two primary professions.
                if self:GetChecked() and IS_PRIMARY[name] then
                    local n = 0
                    for _, o in ipairs(f.checks) do if o:GetChecked() and IS_PRIMARY[o.name] then n = n + 1 end end
                    if n > 2 then
                        self:SetChecked(false)
                        f.status:SetText("|cffff9933Two primary professions at most.|r")
                        return
                    end
                end
                f.status:SetText("")
            end)
            f.checks[#f.checks + 1] = c
        end
    end
    column(PRIMARY, 18, "Primary (pick 2)")
    column(SECONDARY, 190, "Secondary (any)")

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 14, 44)

    local function btn(text, w, x, fn)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("BOTTOMLEFT", x, 12)
        b:SetText(text)
        b:SetScript("OnClick", fn)
    end
    btn("Flow suggests", 110, 12, function() P:Fill(suggested()) end)
    btn("Save", 90, 256, function()
        local plan, want = {}, {}
        for _, s in ipairs(suggested()) do want[s.name] = s end
        for _, c in ipairs(f.checks) do
            if c:GetChecked() then
                plan[#plan + 1] = { name = c.name, optional = want[c.name] and want[c.name].optional or nil }
            end
        end
        ns.db.prof.plan = plan
        ns.db.prof.chosen = true
        if ns.nav then ns.nav:Collect() end
        if ns.advisor then ns.advisor:Refresh() end
        ns:Print(#plan .. " profession(s) in your plan. The route will take you to their trainers.")
        f:Hide()
    end)
    f:Hide()
    return f
end

function P:Fill(plan)
    local on = {}
    for _, p in ipairs(plan) do on[p.name] = true end
    for _, c in ipairs(frame.checks) do
        local have = ns.api.Skill(c.name)
        c:SetChecked(on[c.name] or false)
        c.label:SetText(c.name .. (have and string.format(" |cff888888(%d)|r", have) or ""))
    end
end

function P:Open()
    frame = frame or build()
    local names = {}
    for _, s in ipairs(suggested()) do names[#names + 1] = s.name .. (s.optional and " (optional)" or "") end
    frame.note:SetText("Flow suggests: " .. table.concat(names, ", ")
        .. ". Untick what you don't want; the route only takes you to trainers for what's ticked.")
    self:Fill(ns:ProfessionPlan())
    frame:Show()
end

ns:OnLoad(function(saved) saved.prof = saved.prof or {} end)
ns:PerCharacter("prof")   -- your profession plan

-- Offered quietly from level 3 (advice list), never as a pop-up.
ns:Register("advisor", "choosePro", {
    check = function()
        if ns.db.prof.chosen or UnitLevel("player") < 3 then return nil end
        -- Already learned two main professions in game: that's a choice made.
        local primaries = 0
        for _, pr in ipairs(ns.api.Professions()) do
            if IS_PRIMARY[pr.name] then primaries = primaries + 1 end
        end
        if primaries >= 2 then return nil end
        return { { importance = 45, text = "Choose your professions (Flow has a suggestion)",
                   improves = { "Professions" }, onClick = function() P:Open() end } }
    end,
})

ns:Register("setupItem", "professions", {
    order = 95, label = "Professions plan", why = "Which professions the route takes you to train.",
    now = function() return ns.db.prof.chosen and "chosen" or "Flow's suggestion" end,
    action = "Choose...", run = function() P:Open() end,
})

ns.commands.professions = function(arg)
    if (arg or ""):lower():find("^plan") then return ns.skillPlan:Explain() end
    P:Open()
end
ns.commands.prof = ns.commands.professions
