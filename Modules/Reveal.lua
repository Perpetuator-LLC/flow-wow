-- First time with Flow: nothing on screen at login. Flow's pieces come in one
-- at a time as you start to play, each fading in with one line saying what
-- it is, so a new player isn't faced with everything at once:
--   arrow    you walk a few steps        the arrow (and the minimap marks)
--   tracker  20 s later, or a quest      the Flow Tracker (your next stop)
--   icon     you target an enemy / fight the easy button's icon
--   advice   you level up, or 10 minutes the "!" list of ways to improve
-- Only on a fresh install: anyone who already used Flow sees it all at once.
-- Seen once per account. /flow reveal all shows everything now; /flow reveal
-- reset starts the tour again.

local _, ns = ...
local R = {}
ns.reveal = R

local STAGES = { "arrow", "tracker", "icon", "advice" }
R.STAGES = STAGES
local FRAMES = { arrow = "FlowNavArrow", tracker = "FlowTracker", icon = "FlowRotationIcon", advice = "FlowAdviceButton" }
local HINT = {
    arrow = "this arrow points to your next stop. Follow it; right-click it for options.",
    tracker = "the Flow Tracker (top right) shows your next stop. Click it to open the stop.",
    icon = "this icon shows what to press in a fight. Pick a key for it in /flow settings.",
    advice = "the ! button lists ways to improve your character. Hover it.",
}

-- Is this piece on screen yet?
function R:Shown(stage)
    local d = ns.db and ns.db.reveal
    if not d or d.all then return true end
    return d[stage] == true
end

-- A gentle fade in (an animation on the frame itself: nothing shared).
local function fadeIn(frame)
    if not frame then return end
    frame.flowReveal = frame.flowReveal or frame:CreateAnimationGroup()
    local ag = frame.flowReveal
    if not ag.alpha then
        ag.alpha = ag:CreateAnimation("Alpha")
        ag.alpha:SetFromAlpha(0); ag.alpha:SetToAlpha(1); ag.alpha:SetDuration(1.5)
    end
    ag:Stop(); ag:Play()
end

function R:Show(stage, quiet)
    local d = ns.db.reveal
    if self:Shown(stage) then return end
    d[stage] = true
    local f = _G[FRAMES[stage]]
    if f then fadeIn(f) end
    if not quiet and HINT[stage] then ns:Print(HINT[stage]) end
    ns:Log("reveal", stage)
    -- Pieces that update on their own timers: show them now.
    if stage == "tracker" and ns.routeTracker then pcall(ns.routeTracker.Refresh, ns.routeTracker) end
    if stage == "advice" and ns.advisor and ns.advisor.Refresh then pcall(ns.advisor.Refresh, ns.advisor) end
    local all = true
    for _, s in ipairs(STAGES) do if not d[s] then all = false end end
    if all then d.all = true end
end

function R:ShowAll()
    for _, s in ipairs(STAGES) do self:Show(s, true) end
    ns.db.reveal.all = true
end

-- Has the player walked `yards` from where they started?
function R.Moved(start, p, yards)
    if not (start and p) or start.cont ~= p.cont then return false end
    return (p.wx - start.wx) ^ 2 + (p.wy - start.wy) ^ 2 >= (yards or 10) ^ 2
end

-------------------------------------------------------------------------------
-- What brings each piece in
-------------------------------------------------------------------------------

local start, arrowAt, loginAt
local watcher = CreateFrame("Frame")
local acc = 0
watcher:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.5 then return end
    acc = 0
    local d = ns.db and ns.db.reveal
    if not d or d.all then watcher:SetScript("OnUpdate", nil) return end
    local now = GetTime()
    loginAt = loginAt or now
    if not d.arrow then
        local p = ns.nav and ns.nav:PlayerPos()
        if p and not start then start = p end
        if R.Moved(start, p, 10) then R:Show("arrow"); arrowAt = now end
        return
    end
    arrowAt = arrowAt or now
    if not d.tracker and now - arrowAt > 20 then R:Show("tracker") end
    if not d.advice and now - arrowAt > 600 then R:Show("advice") end
end)

ns:On("QUEST_ACCEPTED", function()
    if R:Shown("tracker") then return end
    if not R:Shown("arrow") then R:Show("arrow") end
    R:Show("tracker")
end)
ns:On("PLAYER_TARGET_CHANGED", function()
    if R:Shown("icon") then return end
    if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then R:Show("icon") end
end)
ns:On("PLAYER_REGEN_DISABLED", function() if not R:Shown("icon") then R:Show("icon") end end)
ns:On("PLAYER_LEVEL_UP", function() if not R:Shown("advice") then R:Show("advice") end end)

ns:OnLoad(function(saved)
    -- New to Flow (no saved data before this login): the tour. Already using
    -- Flow: everything, as before.
    if saved.reveal == nil then saved.reveal = ns.freshInstall and {} or { all = true } end
end)

ns.commands.reveal = function(arg)
    arg = (arg or ""):lower()
    if arg == "all" then R:ShowAll(); ns:Print("everything's on screen now")
    elseif arg == "reset" then
        ns.db.reveal = {}
        start, arrowAt = nil, nil
        ns:Print("Flow's pieces will come in one at a time again: /reload and start walking")
    else
        local list = {}
        for _, s in ipairs(STAGES) do list[#list + 1] = s .. (R:Shown(s) and " (on)" or " (not yet)") end
        ns:Print("on screen: " .. table.concat(list, ", ") .. "  (/flow reveal all|reset)")
    end
end
