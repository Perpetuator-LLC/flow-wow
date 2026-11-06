-- A small context menu in Flow's own style (dark panel, accent edge).
--   ns.menu:Open(items)   at the cursor
-- items: { text, func, checked = bool|nil, radio = bool, disabled = bool,
--          title = bool, sep = true }
-- Closes on a click outside it, on Escape, or after choosing an entry.

local _, ns = ...
local Menu = {}
ns.menu = Menu

local ROW_H, PAD, W = 18, 6, 230
local frame, catcher
local rows = {}

local function build()
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() Menu:Close() end)
    catcher:Hide()

    frame = CreateFrame("Frame", "FlowMenu", UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(catcher:GetFrameLevel() + 10)
    frame:SetWidth(W)
    frame:EnableMouse(true)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.05, 0.05, 0.08, 0.97)
    local o = ns.theme.arrow
    frame.accent = frame:CreateTexture(nil, "BORDER")
    frame.accent:SetPoint("TOPLEFT"); frame.accent:SetPoint("BOTTOMLEFT")
    frame.accent:SetWidth(3)
    frame.accent:SetColorTexture(o[1], o[2], o[3], 1)
    frame:SetScript("OnHide", function() catcher:Hide() end)
    tinsert(UISpecialFrames, "FlowMenu")  -- Escape closes it
    frame:Hide()
end

local function row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, frame)
    r:SetHeight(ROW_H)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.1)
    r.mark = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.mark:SetPoint("LEFT", 8, 0)
    r.mark:SetWidth(14)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 24, 0)
    r.text:SetPoint("RIGHT", -6, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.line = r:CreateTexture(nil, "ARTWORK")
    r.line:SetPoint("LEFT", 8, 0); r.line:SetPoint("RIGHT", -8, 0)
    r.line:SetHeight(1)
    r.line:SetColorTexture(1, 1, 1, 0.15)
    rows[i] = r
    return r
end

function Menu:Close() if frame then frame:Hide() end end

function Menu:Open(items)
    if not frame then build() end
    local y = -PAD
    local n = 0
    for i, it in ipairs(items) do
        n = i
        local r = row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 3, y)
        r:SetPoint("TOPRIGHT", 0, y)
        local h = it.sep and 7 or ROW_H
        r:SetHeight(h)
        r.line:SetShown(it.sep == true)
        r.text:SetShown(not it.sep)
        r.mark:SetShown(not it.sep)
        r.hl:SetShown(not (it.sep or it.title or it.disabled))
        if not it.sep then
            if it.title then
                r.text:SetText("|cffffd200" .. (it.text or "") .. "|r")
            elseif it.disabled then
                r.text:SetText("|cff777777" .. (it.text or "") .. "|r")
            else
                r.text:SetText(it.text or "")
            end
            local mark = ""
            -- Game fonts lack most symbols, so the tick is a texture.
            if it.checked then mark = "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t" end
            r.mark:SetText(mark)
        end
        r:SetScript("OnClick", function()
            if it.sep or it.title or it.disabled then return end
            Menu:Close()
            if it.func then
                local ok, err = pcall(it.func)
                if not ok then ns:Print("menu: " .. tostring(err)) end
            end
        end)
        r:Show()
        y = y - h
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    frame:SetHeight(-y + PAD)
    local scale = UIParent:GetEffectiveScale()
    local x, cy = GetCursorPosition()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 4, cy / scale - 4)
    frame:SetClampedToScreen(true)
    catcher:Show()
    frame:Show()
end

-- Route entries shared by every Flow menu (arrow, tracker rows).
function Menu:RouteItems()
    local nav = ns.nav
    local mode, profs = nav:Mode(), ns.db.nav.professions ~= false
    local sort = ns.xpValue:Mode()
    local nHidden = 0
    for _ in pairs(ns.db.nav.hidden or {}) do nHidden = nHidden + 1 end
    local function setRoute(m, p)
        return function()
            ns.db.nav.professions = p
            nav:SetMode(m)
            nav:Collect()
        end
    end
    return {
        { title = true, text = "Route" },
        { text = "Follow current quests", radio = true, checked = mode == "quests", func = setRoute("quests", profs) },
        { text = "Optimal with professions", radio = true, checked = mode == "optimal" and profs, func = setRoute("optimal", true) },
        { text = "Optimal without professions", radio = true, checked = mode == "optimal" and not profs, func = setRoute("optimal", false) },
        { sep = true },
        { title = true, text = "Order" },
        { text = ns.theme:ModeText("xp", "Most XP first"), radio = true, checked = sort == "xp", func = function() ns.xpValue:SetMode("xp") end },
        { text = ns.theme:ModeText("distance", "Shortest path"), radio = true, checked = sort == "distance", func = function() ns.xpValue:SetMode("distance") end },
        { text = (nav.selection and nav.selection.first) and ns.theme:ModeText("selected", "From selected stop") or "Select a waypoint (on the map)",
          radio = true, checked = sort == "selected",
          disabled = not (nav.selection and nav.selection.first), func = function() ns.xpValue:SetMode("selected") end },
        { sep = true },
        { text = string.format("Unhide all stops (%d)", nHidden), disabled = nHidden == 0,
          func = function() ns.commands.nav("unhide") end },
    }
end
