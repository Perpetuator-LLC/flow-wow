-- Ask Claude from inside the game, with tools\claude-bridge.ps1 running on
-- your PC and a Claude session watching it.
--   /si              Claude connected: the chat window (your questions and
--                    the answers, a box to type in, Send, Reload). Not
--                    connected yet: how to connect, with a prompt to copy
--                    into Claude.
--   /si <message>    ask straight away (or /ai, /claude, /flow ask)
--   /si setup        the connect prompt again
--
-- Sending, without a reload: WoW never lets an add-on read or write a file
-- while the game runs (its saved data is written at a reload or logout), but
-- the game writes its chat log (Logs\WoWChatLog.txt) as chat arrives. So
-- Flow turns the chat log on and whispers your message to you, tagged
-- "[FlowAsk:...]" and hidden from your chat window; the bridge reads it from
-- the log straight away. Where that doesn't work, Send reloads instead (the
-- message is in Flow's saved data too, so it's never lost).
--
-- Answers still need a reload: that's the only time WoW reads Flow's files
-- (Learned\ClaudeInbox.lua, written by the bridge). Reload in the chat
-- window when you want them, and any change Claude made to Flow with them.
-- Nothing goes anywhere but files on your own PC (and the whisper to
-- yourself); the bridge only runs while you start it.

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

-------------------------------------------------------------------------------
-- Connected? The bridge writes when it last ran into Learned\ClaudeInbox.lua
-- (ns.claudeBridge = { at = unix time }) every few minutes; WoW reads that
-- at a reload, so this is "watching as of your last reload".
-------------------------------------------------------------------------------

AC.FRESH = 30 * 60   -- seconds: the bridge writes every 10 minutes while it runs
function AC.Connected(bridge, now)
    return (type(bridge) == "table" and bridge.at and (now - bridge.at) <= AC.FRESH) and true or false
end
function AC:IsConnected() return AC.Connected(ns.claudeBridge, time()) end

-------------------------------------------------------------------------------
-- Live sending: tagged whispers to yourself, which WoW's chat log records.
-------------------------------------------------------------------------------

AC.TAG = "[FlowAsk:"
AC.PART = 220   -- letters per whisper (WoW's limit is 255, the tag included)

-- Chat can't carry "|" (WoW's escape character) or line breaks.
function AC.Clean(text) return ((tostring(text or "")):gsub("|", "/"):gsub("[\r\n]+", " ")) end

function AC.IsTagged(msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return false end
    return msg:sub(1, #AC.TAG) == AC.TAG
end

-- The whispers for one message: who you are first ("[FlowAsk:12:0/2]
-- Yang;PALADIN;2;Tirisfal Glades"), then the text in parts of at most
-- AC.PART letters, never cutting a letter in two (UTF-8).
function AC.Parts(id, text, who)
    text = AC.Clean(text)
    local chunks, i = {}, 1
    while i <= #text do
        local j = math.min(#text, i + AC.PART - 1)
        while j < #text and j > i do
            local b = text:byte(j + 1)
            if b < 128 or b >= 192 then break end   -- the next byte starts a letter
            j = j - 1
        end
        -- Chat may drop a space at the end of a message: it starts the next part instead.
        while j < #text and j > i and text:byte(j) == 32 do j = j - 1 end
        chunks[#chunks + 1] = text:sub(i, j)
        i = j + 1
    end
    local n = #chunks
    local out = { string.format("%s%d:0/%d] %s", AC.TAG, id, n, AC.Clean(who)) }
    for k, c in ipairs(chunks) do out[#out + 1] = string.format("%s%d:%d/%d] %s", AC.TAG, id, k, n, c) end
    return out
end

function AC.Who(e)
    return string.format("%s;%s;%s;%s", tostring(e.char), tostring(e.class), tostring(e.level), tostring(e.zone))
end

-- You, as a whisper target ("Name-Realm").
function AC.Me()
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end   -- (not `x and f()`: that keeps one value)
    name = name or UnitName("player")
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName())
    return (realm and realm ~= "") and (name .. "-" .. realm) or name
end

function AC.CanLive()
    return ns.db.chat.live ~= false and type(LoggingChat) == "function" and type(SendChatMessage) == "function"
end

-- Whispers sent and seen back from the server ("To you: ..."): { [id] = { n, seen, at } }.
local pending = {}
local status   -- forward: the chat window's status line

-- The whispers never show in your chat window (both "To ..." and "... whispers").
local function hideTagged(_, _, msg) return AC.IsTagged(msg) end
local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if addFilter then
    addFilter("CHAT_MSG_WHISPER", hideTagged)
    addFilter("CHAT_MSG_WHISPER_INFORM", hideTagged)
end

ns:On("CHAT_MSG_WHISPER_INFORM", function(msg)
    if not AC.IsTagged(msg) then return end
    local id = tonumber(msg:match("^%[FlowAsk:(%d+):"))
    local p = id and pending[id]
    if not p then return end
    p.seen = p.seen + 1
    if p.seen >= p.n then
        pending[id] = nil
        ns.db.chat.liveWorks = true
        status(AC:IsConnected() and "Sent, no reload needed: Claude reads it now. Its answer shows when you press Reload."
            or "Sent, no reload needed. Claude reads it once it's connected (/si setup); answers show when you press Reload.")
    end
end)

-- Sends message `e` live; false if this client can't.
function AC:SendLive(e)
    if not AC.CanLive() then return false end
    if not LoggingChat() then
        LoggingChat(true)
        if not ns.db.chat.toldLog then
            ns.db.chat.toldLog = true
            ns:Print("turned on WoW's chat log (Logs\\WoWChatLog.txt) so Claude reads your messages without a reload. It records your chat on your PC only; /flow chat live off stops this.")
        end
    end
    local lines = AC.Parts(e.id, e.text, AC.Who(e))
    pending[e.id] = { n = #lines, seen = 0 }
    local me = AC.Me()
    for k, line in ipairs(lines) do
        C_Timer.After((k - 1) * 0.25, function() pcall(SendChatMessage, line, "WHISPER", nil, me) end)
    end
    -- Not back from the server in a few seconds: say so (Reload sends it the old way).
    C_Timer.After(#lines * 0.25 + 4, function()
        if pending[e.id] then
            pending[e.id] = nil
            status("|cffff7070Couldn't send it without a reload.|r Press Reload to send it (it's saved).")
            ns:Log("chat", "live send got no whisper back for message " .. e.id)
        end
    end)
    return true
end

function AC:Send(text)
    local chat = ns.db.chat
    local id = chat.nextId
    chat.nextId = id + 1
    local e = AC.Entry(id, text)
    -- In Flow's saved data too: a reload passes it on if the live send didn't.
    chat.outbox[#chat.outbox + 1] = e
    while #chat.outbox > MAX_OUTBOX do table.remove(chat.outbox, 1) end
    -- What you asked, kept (the last 20) so the chat window can show it next
    -- to Claude's answer.
    chat.sent[id] = text
    for old in pairs(chat.sent) do if old <= id - MAX_OUTBOX then chat.sent[old] = nil end end
    if AC:SendLive(e) then
        status("Sending (no reload)...")
        if AC.box and AC.box:IsShown() then AC:Open() end
        return
    end
    ns:Print("sent to Claude (reloading so it's saved where Claude can read it)...")
    ReloadUI()   -- (from your slash command or the Send button: allowed)
end

-------------------------------------------------------------------------------
-- Connecting Claude: a prompt to paste into a Claude Code session (Claude
-- desktop's Code tab, or `claude` in a terminal) on the PC you play on.
-------------------------------------------------------------------------------

AC.REPO = "https://github.com/Perpetuator-LLC/flow-wow"
function AC.SetupPrompt(char, class, level, realm)
    return table.concat({
        "Connect yourself to my WoW addon Flow's in-game chat, then watch it for me. Explain each step in plain words, and ask me before changing anything that starts with Windows.",
        "",
        string.format("I play WoW: Forever as %s (%s %s) on %s, with the Flow addon (%s).", tostring(char), tostring(class), tostring(level), tostring(realm), AC.REPO),
        "",
        "1. Find my Flow source: a git clone of that repo (often %USERPROFILE%\\projects\\flow-wow). If I have none, clone it there. If my WoW folder's _forever_\\Interface\\AddOns\\Flow isn't a link to that clone, tell me how to link it, or pass -AddonDir <that AddOns\\Flow folder> to the bridge below.",
        "2. Read CLAUDE.md (the \"Watch Flow's in-game chat\" section) and docs\\ASK-CLAUDE.md in it.",
        "3. Run: powershell -ExecutionPolicy Bypass -File tools\\claude-bridge.ps1 -SelfTest  (it should say \"self-test OK\").",
        "4. Start: powershell -ExecutionPolicy Bypass -File tools\\claude-bridge.ps1  with your Monitor tool, and start it again each time it expires. It finds my WoW folder by itself and reads my messages from _forever_\\Logs\\WoWChatLog.txt as I send them (no reload), and from Flow's saved data (_forever_\\WTF\\Account\\<account>\\SavedVariables\\Flow.lua) at a reload.",
        "5. Each ASK line is a message from me: do what it asks in my Flow folder, then answer: powershell -ExecutionPolicy Bypass -File tools\\claude-bridge.ps1 -Reply <id> -Text \"...\"  (at most 3 short sentences, plain text; say if I need to reload). DEATH and UPDATE lines: CLAUDE.md says what to do.",
        "6. When it prints READY, tell me to press Reload in Flow Chat (/si) and say hello.",
    }, "\n")
end
function AC:MyPrompt()
    local _, class = UnitClass("player")
    return AC.SetupPrompt(UnitName("player"), class, UnitLevel("player"), GetRealmName and GetRealmName() or "?")
end

-------------------------------------------------------------------------------
-- The chat window (/si): your questions and Claude's answers, a box to type
-- in, Send and Reload; or, not connected, the prompt to connect Claude.
-------------------------------------------------------------------------------

-- The conversation as lines, oldest first, at most `max` exchanges:
-- answers (with what you asked), then messages still waiting.
function AC.History(inbox, chat, max)
    local out = {}
    for _, r in ipairs(inbox or {}) do
        local q = r.replyTo and chat.sent and chat.sent[r.replyTo]
        out[#out + 1] = { q = q, a = r.text, id = r.id or 0 }
    end
    table.sort(out, function(x, y) return x.id < y.id end)
    for _, m in ipairs(chat.outbox or {}) do out[#out + 1] = { q = m.text, waiting = true, id = 1e9 + (m.id or 0) } end
    local lines = {}
    for i = math.max(1, #out - (max or 6) + 1), #out do
        local e = out[i]
        if e.q then lines[#lines + 1] = "|cff88ccffYou:|r " .. e.q end
        if e.waiting then lines[#lines + 1] = "|cff888888(waiting for Claude: Reload shows its answer)|r"
        elseif e.a then lines[#lines + 1] = "|cff" .. ORANGE .. "Claude:|r " .. e.a end
    end
    return lines
end

local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22); b:SetText(text)
    return b
end

local box
local function buildBox()
    local f = CreateFrame("Frame", "FlowAskClaude", UIParent)
    f:SetSize(480, 320)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.head = ns.theme:TitleBar(f, "Flow Chat", "Interface\\Icons\\INV_Misc_Book_09")
    ns:MakeMovable(f, ns.db.chat, true)
    tinsert(UISpecialFrames, "FlowAskClaude")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.status:SetPoint("BOTTOMLEFT", 12, 40); f.status:SetPoint("BOTTOMRIGHT", -12, 40)
    f.status:SetJustifyH("LEFT")
    -- Reload: when you want Claude's answers (and any change it made to Flow).
    f.reload = button(f, "Reload", 70)
    f.reload:SetPoint("BOTTOMRIGHT", -12, 10)
    f.reload:SetScript("OnClick", function()
        ns:Print("reloading to show Claude's answers (and load any change it made to Flow)...")
        ReloadUI()
    end)
    f.reload:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reload", 1, 1, 1)
        GameTooltip:AddLine("WoW only reads Flow's files at a reload: Claude's answers, and any change it made to Flow, show after one.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.reload:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Chat view.
    f.chat = CreateFrame("Frame", nil, f)
    f.chat:SetAllPoints()
    f.log = f.chat:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.log:SetPoint("TOPLEFT", 12, -32); f.log:SetPoint("TOPRIGHT", -12, -32)
    f.log:SetHeight(200)
    f.log:SetJustifyH("LEFT"); f.log:SetJustifyV("BOTTOM")
    f.edit = CreateFrame("EditBox", nil, f.chat, "InputBoxTemplate")
    f.edit:SetSize(215, 22)
    f.edit:SetPoint("BOTTOMLEFT", 18, 10)
    f.edit:SetAutoFocus(false)
    f.edit:SetMaxLetters(1000)   -- (the game's chat box stops at 255)
    local function send()
        local text = (f.edit:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then f.status:SetText("Type a message first.") return end
        f.edit:SetText(""); f.edit:ClearFocus()
        AC:Send(text)
    end
    f.edit:SetScript("OnEnterPressed", send)
    f.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.send = button(f.chat, "Send", 60)
    f.send:SetPoint("LEFT", f.edit, "RIGHT", 6, 0)
    f.send:SetScript("OnClick", send)
    f.connect = button(f.chat, "Connect", 70)
    f.connect:SetPoint("LEFT", f.send, "RIGHT", 4, 0)
    f.connect:SetScript("OnClick", function() AC:OpenSetup() end)

    -- Setup view: the prompt to paste into Claude.
    f.setup = CreateFrame("Frame", nil, f)
    f.setup:SetAllPoints()
    f.setup.intro = f.setup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.setup.intro:SetPoint("TOPLEFT", 12, -32); f.setup.intro:SetPoint("TOPRIGHT", -12, -32)
    f.setup.intro:SetJustifyH("LEFT")
    f.setup.intro:SetText("Claude isn't connected yet. Copy this (Ctrl+C: it's selected) into a Claude Code session on this PC (Claude desktop's Code tab). It sets Claude up to read your messages and change Flow for you. Then press Reload.")
    local sf = CreateFrame("ScrollFrame", nil, f.setup, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -74); sf:SetPoint("BOTTOMRIGHT", -30, 62)
    f.prompt = CreateFrame("EditBox", nil, sf)
    f.prompt:SetMultiLine(true)
    f.prompt:SetAutoFocus(false)
    f.prompt:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    f.prompt:SetWidth(420)
    f.prompt:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Read-only: typing puts the prompt back.
    f.prompt:SetScript("OnTextChanged", function(self, user)
        if user and self.text and self:GetText() ~= self.text then self:SetText(self.text); self:HighlightText() end
    end)
    sf:SetScrollChild(f.prompt)
    f.copy = button(f.setup, "Select all", 80)
    f.copy:SetPoint("BOTTOMLEFT", 12, 10)
    f.copy:SetScript("OnClick", function() f.prompt:SetFocus(); f.prompt:HighlightText() end)
    f.toChat = button(f.setup, "Chat anyway", 100)
    f.toChat:SetPoint("LEFT", f.copy, "RIGHT", 4, 0)
    f.toChat:SetScript("OnClick", function() ns.db.chat.setupSkipped = true; AC:Open() end)
    f:Hide()
    return f
end

function status(text)   -- (declared above)
    if box and text then box.status:SetText(text) end
end

local function liveHint()
    if not AC.CanLive() then return "Send reloads your UI for a moment so Claude can read it." end
    return "Send needs no reload (WoW's chat log carries it)."
end

-- `draft`: text to put in the box to finish (a message too long for the chat box).
function AC:Open(draft)
    box = box or buildBox()
    AC.box = box
    box.setup:Hide(); box.chat:Show()
    local chat = ns.db.chat
    local lines = AC.History(ns.claudeInbox, chat, 6)
    box.log:SetText(#lines > 0 and table.concat(lines, "\n")
        or "|cff888888Ask anything about Flow or your character. A Claude session on your PC answers (docs/ASK-CLAUDE.md).|r")
    box.connect:SetShown(not AC:IsConnected())
    box.status:SetText(draft and "The chat box stops at 255 letters, so the end may be cut off: finish your message here (it takes 1000) and press Enter."
        or not AC:IsConnected() and ("Claude wasn't watching at your last reload: Connect shows how. " .. liveHint())
        or #chat.outbox > 0
        and string.format("Waiting on %d message(s). Reload shows Claude's answers.", #chat.outbox)
        or (liveHint() .. " Reload shows Claude's answers."))
    box:Show()
    if draft then box.edit:SetText(draft) end
    box.edit:SetFocus()
    if draft then box.edit:SetCursorPosition(#draft) end
end

function AC:OpenSetup()
    box = box or buildBox()
    AC.box = box
    box.chat:Hide(); box.setup:Show()
    local text = AC:MyPrompt()
    box.prompt.text = text
    box.prompt:SetText(text)
    box.status:SetText(ns.claudeBridge and string.format("Claude was last watching %d min before your last reload.",
        math.floor((time() - (ns.claudeBridge.at or 0)) / 60)) or "Claude hasn't connected on this PC yet.")
    box:Show()
    box.prompt:SetFocus(); box.prompt:HighlightText()
end

local function check()
    local chat = ns.db.chat
    local new = AC.TakeNew(ns.claudeInbox, chat)
    for _, r in ipairs(new) do show(r) end
    if #new > 0 then ns:Print("(/si opens the chat window)") end
    if #chat.outbox > 0 then
        ns:Print(string.format("waiting for Claude on %d message(s). Reload in Flow Chat (/si) looks again.%s", #chat.outbox,
            AC:IsConnected() and "" or " Claude isn't connected: /si setup shows how."))
    end
end
ns:On("PLAYER_LOGIN", function() C_Timer.After(3, function() pcall(check) end) end)

ns:OnLoad(function(saved)
    saved.chat = saved.chat or {}
    saved.chat.outbox = saved.chat.outbox or {}
    saved.chat.seen = saved.chat.seen or {}
    saved.chat.nextId = saved.chat.nextId or 1
    saved.chat.sent = saved.chat.sent or {}
end)

-- The game's chat box stops at 255 letters ("/claude " included), so a
-- message this long was probably cut off as you typed (Yang's was).
AC.CHAT_BOX_FULL = 240
function AC.MaybeCut(text) return #(text or "") >= AC.CHAT_BOX_FULL end

local function command(arg)
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "" then   -- connected (or you chose to chat anyway): the chat; else how to connect
        if AC:IsConnected() or ns.db.chat.setupSkipped then AC:Open() else AC:OpenSetup() end
        return
    end
    if arg == "setup" or arg == "connect" then AC:OpenSetup() return end
    if arg == "check" or arg == "reload" then ns:Print("checking for Claude's answers (reloading)..."); ReloadUI() return end
    -- Too long for the chat box: finish it in the Flow Chat window instead
    -- of sending the cut-off part.
    if AC.MaybeCut(arg) then AC:Open(arg) return end
    AC:Send(arg)
end
ns.commands.ask = command

-- /flow chat live on|off: send through the chat log (no reload) or by reloading.
ns.commands.chat = function(arg)
    local on = (arg or ""):lower():match("^live%s+(o[nf]f?)$")
    if on == "on" or on == "off" then ns.db.chat.live = (on == "on") end
    ns:Print(string.format("Flow Chat sends %s. Claude connected (as of your last reload): %s. /flow chat live on|off",
        AC.CanLive() and "without a reload (WoW's chat log)" or "by reloading", AC:IsConnected() and "yes" or "no"))
end

-- /claude, and the short /ai and /si, unless another add-on already owns them.
AC.SLASHES = { "/claude", "/ai", "/si" }
ns:On("PLAYER_LOGIN", function()
    if not SlashCmdList then return end
    local n = 0
    for _, cmd in ipairs(AC.SLASHES) do
        if not (hash_SlashCmdList and hash_SlashCmdList[cmd:upper()]) then
            n = n + 1
            _G["SLASH_FLOWCLAUDE" .. n] = cmd
        end
    end
    if n > 0 then SlashCmdList.FLOWCLAUDE = command end
end)

ns:Register("help", "claude", { order = 90, title = "Ask Claude", lines = {
    "/si (or /ai, /claude): Flow Chat with Claude; not connected yet, it shows a prompt to connect Claude.",
    "/si <message>: ask straight away (no reload where WoW's chat log works). Reload in the window shows answers.",
    "/si setup: the connect prompt again. /flow chat live on|off: send without or with a reload.",
} })
