-- SoothMod core: shared namespace, saved variables, and a tiny event bus
-- that modules hook into. Add new features as files in Modules\ and list
-- them in SoothMod.toc.

local ADDON_NAME, ns = ...

ns.name = ADDON_NAME
ns.modules = {}

local frame = CreateFrame("Frame")
local handlers = {}

-- ns:On("EVENT_NAME", function(...) end)
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then
            print("|cffff5555SoothMod error|r (" .. event .. "): " .. tostring(err))
        end
    end
end)

function ns:Print(msg)
    print("|cff66ccffSoothMod|r: " .. tostring(msg))
end

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    SoothModDB = SoothModDB or {}
    ns.db = SoothModDB
end)

-- /sooth slash command; modules can add subcommands to ns.commands.
ns.commands = {}
SLASH_SOOTHMOD1 = "/sooth"
SlashCmdList.SOOTHMOD = function(input)
    local cmd, rest = (input or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local fn = ns.commands[cmd]
    if fn then
        fn(rest)
    else
        ns:Print("commands:")
        for name in pairs(ns.commands) do
            print("  /sooth " .. name)
        end
    end
end
