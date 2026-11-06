-- Max camera zoom: lets the camera pull back as far as the game allows.
-- On by default; turn it off in /flow settings to restore the game's default.
-- (The limit differs per client, so Flow tries the largest values first and
-- keeps the first one the game accepts.)

local _, ns = ...
local C = {}
ns.camera = C

local CVAR = "cameraDistanceMaxZoomFactor"
local TRY = { 4.0, 3.4, 2.6 }

local function current() return tonumber(GetCVar(CVAR)) end

function C:ApplyMax()
    if InCombatLockdown() then return false end
    local before = current()
    for _, v in ipairs(TRY) do
        SetCVar(CVAR, v)
        local now = current()
        if now and math.abs(now - v) < 0.01 then return true end
    end
    return (current() or 0) > (before or 0)
end

function C:RestoreDefault()
    if InCombatLockdown() then return false end
    local def = GetCVarDefault and GetCVarDefault(CVAR)
    if def then SetCVar(CVAR, def) end
    return true
end

-- on = true: max zoom; false: game default.
function C:Set(on)
    ns.db.camera.maxZoom = on
    if on then self:ApplyMax() else self:RestoreDefault() end
end

function C:IsOn() return ns.db.camera.maxZoom ~= false end

ns:OnLoad(function(saved) saved.camera = saved.camera or {} end)

ns:On("PLAYER_LOGIN", function()
    if C:IsOn() then C:ApplyMax() end
end)

ns.commands.zoom = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        C:Set(arg == "on")
        ns:Print(arg == "on" and ("max camera zoom on (" .. tostring(current()) .. ")") or "camera zoom back to the game default")
    else
        ns:Print("max camera zoom is " .. (C:IsOn() and "on" or "off") .. " (factor " .. tostring(current()) .. "). /flow zoom on|off, or /flow settings")
    end
end
