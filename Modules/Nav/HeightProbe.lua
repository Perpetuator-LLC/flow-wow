-------------------------------------------------------------------------------
-- Flow - Nav/HeightProbe.lua
-- Does the game say "above you" or "below you"? A probe, not a feature
-- (0.35.353).
--
-- "I thought we were adding the little grey arrow to indicate that the target
-- is above or below me ... I know you can't tell character elevation, but I
-- thought they would say that the target was significantly above or below."
--
-- What an add-on is given on this client: no height (UnitPosition's is always
-- 0), no nameplate positions ("restricted"), and the little up and down
-- arrows on the minimap are drawn by the game for its own tracked things,
-- with no call that says which way they point. The one thing that could tell
-- is the game's marker in the world for the spot it's tracking
-- (C_Navigation): if that marker is a frame Flow may measure, where it sits
-- on the screen says above or below. At a reload it has never had a frame
-- (0.35.303). That's one moment; this watches while you play and writes down
-- every time what the game answers changes, so the diagnostics show whether
-- it's ever there, and at what distance.
--
-- Nothing is set or changed: Flow doesn't track a spot of its own here.
-------------------------------------------------------------------------------

local _, ns = ...
local HP = {}
ns.heightProbe = HP

HP.EVERY = 2      -- seconds between looks
HP.MAX = 25       -- lines a session
HP.seen = { looks = 0, frame = 0, measured = 0, valid = 0, lines = 0 }

-- Pure: what one look found, as a short text (the log keeps it when it changes).
--   has: C_Navigation is there; frame: it gave a frame; y, h: the frame's
--   middle and the screen's height (nil: not measurable); valid, clamped,
--   state, dist: the other calls' answers.
function HP.Text(has, frame, y, h, valid, clamped, state, dist)
    if not has then return "no C_Navigation" end
    local where = "no frame"
    if frame then
        where = (y and h and h > 0) and string.format("frame at %d%% of the screen's height", math.floor(y / h * 100 + 0.5)) or "a frame Flow can't measure"
    end
    return string.format("%s; on screen %s; clamped %s; state %s; %s", where, tostring(valid), tostring(clamped), tostring(state),
        (dist and dist > 0) and (math.floor(dist / 25 + 0.5) * 25 .. " yd") or "no distance")
end

-- Pure: above or below, from where the marker sits: over the middle of the
-- screen it's above your eye line, under it below. nil: can't say.
function HP.Side(y, h, slack)
    if not (y and h and h > 0) then return nil end
    local off = y / h - 0.5
    if math.abs(off) < (slack or 0.12) then return "level" end
    return off > 0 and "above" or "below"
end

local last
function HP.Look()
    local nav = _G.C_Navigation
    local s = HP.seen
    s.looks = s.looks + 1
    local frame, y, valid, clamped, state, dist
    if type(nav) == "table" then
        local okF, f = pcall(function() return nav.GetFrame and nav.GetFrame() end)
        frame = okF and f or nil
        if frame and frame.GetCenter then
            local okC, _, cy = pcall(frame.GetCenter, frame)
            y = okC and tonumber(cy) or nil
        end
        local function ask(name)
            local ok, v = pcall(function() return nav[name] and nav[name]() end)
            return ok and v or nil
        end
        valid, clamped, state, dist = ask("HasValidScreenPosition"), ask("WasClampedToScreen"), ask("GetTargetState"), tonumber(ask("GetDistance"))
    end
    if frame then s.frame = s.frame + 1 end
    if y then s.measured = s.measured + 1 end
    if valid then s.valid = s.valid + 1 end
    local text = HP.Text(type(nav) == "table", frame ~= nil, y, UIParent and UIParent:GetHeight(), valid, clamped, state, dist)
    if text ~= last and s.lines < HP.MAX then
        last = text
        s.lines = s.lines + 1
        ns:Log("height", text .. (y and (" -> " .. tostring(HP.Side(y, UIParent:GetHeight()))) or ""))
    end
end

ns:OnLoad(function()
    -- (Not in a raid or dungeon: lite mode.)
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(HP.EVERY, function() if not (ns.Lite and ns.Lite()) then pcall(HP.Look) end end) end
end)

ns.commands.height = function()
    local s = HP.seen
    ns:Print(string.format("above/below probe: %d look(s) this session; the game's marker was a frame in %d, measurable in %d, on screen in %d",
        s.looks, s.frame, s.measured, s.valid))
    print("  now: " .. tostring(last or "not looked yet"))
    print("  (an up or down arrow on Flow's arrow needs 'measurable' to be more than 0)")
end
