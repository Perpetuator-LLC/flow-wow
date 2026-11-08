-- Ask Claude from inside the game: a poor man's chat through files, with
-- tools\claude-bridge.ps1 running on your PC.
--   /claude make the arrow green      (or /flow ask ...)
--     Flow saves the message and reloads the UI: WoW only writes add-on
--     data to disk on a reload. The bridge sees it, asks Claude Code (in the
--     Flow folder, so it can change Flow itself), and writes the answer to
--     Learned\ClaudeInbox.lua.
--   /claude          check for answers (reloads: that's when WoW reads the
--                    answer file, and any code Claude changed)
-- Answers show in chat as "Claude: ...". Nothing goes anywhere but files on
-- your own PC; the bridge only runs while you start it.

local _, ns = ...
local AC = {}
ns.askClaude = AC

local MAX_OUTBOX = 20
local ORANGE = "d97757"

function AC.Entry(id, text, now)
    local _, class = UnitClass("player")
    return { id = id, text = text, at = now or time(), char = UnitName("player"), class = class,
             level = UnitLevel("player"), zone = GetZoneText and GetZoneText() or "?" }
end

-- Answers you haven't seen, in order; marks them seen and drops the
-- messages they answer from the outbox.
function AC.TakeNew(inbox, chat)
    local new = {}
    for _, r in ipairs(inbox or {}) do
        if r.id and not chat.seen[r.id] then
            chat.seen[r.id] = true
            new[#new + 1] = r
        end
        if r.replyTo then
            for i = #chat.outbox, 1, -1 do
                if chat.outbox[i].id == r.replyTo then table.remove(chat.outbox, i) end
            end
        end
    end
    table.sort(new, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return new
end

local function show(r)
    local first = true
    for line in tostring(r.text or ""):gmatch("[^\n]+") do
        print((first and ("|cff" .. ORANGE .. "Claude:|r ") or "  ") .. line)
        first = false
    end
end

function AC:Send(text)
    local chat = ns.db.chat
    local id = chat.nextId
    chat.nextId = id + 1
    chat.outbox[#chat.outbox + 1] = AC.Entry(id, text)
    while #chat.outbox > MAX_OUTBOX do table.remove(chat.outbox, 1) end
    ns:Print("sent to Claude (reloading so it's saved where Claude can read it)...")
    ReloadUI()   -- (from your slash command: allowed)
end

local function check()
    local chat = ns.db.chat
    for _, r in ipairs(AC.TakeNew(ns.claudeInbox, chat)) do show(r) end
    if #chat.outbox > 0 then
        ns:Print(string.format("waiting for Claude on %d message(s). /claude to check (it reloads). Is tools\\claude-bridge.ps1 running?", #chat.outbox))
    end
end
ns:On("PLAYER_LOGIN", function() C_Timer.After(3, function() pcall(check) end) end)

ns:OnLoad(function(saved)
    saved.chat = saved.chat or {}
    saved.chat.outbox = saved.chat.outbox or {}
    saved.chat.seen = saved.chat.seen or {}
    saved.chat.nextId = saved.chat.nextId or 1
end)

local function command(arg)
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "" then
        ns:Print("checking for Claude's answers (reloading)...")
        ReloadUI()
        return
    end
    AC:Send(arg)
end
ns.commands.ask = command

-- /claude, unless another add-on already owns it.
ns:On("PLAYER_LOGIN", function()
    if SlashCmdList and not (hash_SlashCmdList and hash_SlashCmdList["/CLAUDE"]) then
        _G.SLASH_FLOWCLAUDE1 = "/claude"
        SlashCmdList.FLOWCLAUDE = command
    end
end)

ns:Register("help", "claude", { order = 90, title = "Ask Claude", lines = {
    "/claude <message>: ask Claude from the game (with tools\\claude-bridge.ps1 running on your PC). It reloads to send.",
    "/claude: check for answers (reloads; any change Claude made to Flow loads too).",
} })
