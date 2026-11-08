-- Group invites from friends are accepted for you: your WoW friends list and
-- Battle.net friends playing WoW. Anyone else gets the game's usual popup.
-- On by default; /flow invites on|off, or the box in /flow settings.

local _, ns = ...
local I = {}
ns.invites = I

local function plain(name)
    name = ns.api.Safe(name)
    if type(name) ~= "string" then return nil end
    return (name:match("^([^%-]+)") or name):lower()   -- "Name-Realm" -> "name"
end

-- Everyone you count as a friend right now: { names = { [name] = true }, guids = { [guid] = true } }.
function I.Friends()
    local names, guids = {}, {}
    local FL = C_FriendList
    if FL and FL.GetNumFriends and FL.GetFriendInfoByIndex then
        for i = 1, FL.GetNumFriends() or 0 do
            local ok, info = pcall(FL.GetFriendInfoByIndex, i)
            if ok and info then
                local n = plain(info.name)
                if n then names[n] = true end
                if info.guid then guids[info.guid] = true end
            end
        end
    elseif GetNumFriends and GetFriendInfo then
        for i = 1, GetNumFriends() or 0 do
            local n = plain(GetFriendInfo(i))
            if n then names[n] = true end
        end
    end
    local BN = C_BattleNet
    if BNGetNumFriends and BN and BN.GetFriendNumGameAccounts and BN.GetFriendGameAccountInfo then
        for i = 1, BNGetNumFriends() or 0 do
            for j = 1, BN.GetFriendNumGameAccounts(i) or 0 do
                local ok, g = pcall(BN.GetFriendGameAccountInfo, i, j)
                if ok and g then
                    local n = plain(g.characterName)
                    if n then names[n] = true end
                    if g.playerGuid then guids[g.playerGuid] = true end
                end
            end
        end
    end
    return { names = names, guids = guids }
end

-- Is this inviter a friend? (friends: from I.Friends, or a test list)
function I.IsFriend(name, guid, friends)
    guid = ns.api.Safe(guid)
    if guid and C_FriendList and C_FriendList.IsFriend and not friends then
        local ok, yes = pcall(C_FriendList.IsFriend, guid)
        if ok and yes then return true end
    end
    friends = friends or I.Friends()
    if guid and friends.guids[guid] then return true end
    local n = plain(name)
    return n ~= nil and friends.names[n] == true
end

-- The invite popup: once you're in the group, close it as accepted (its
-- "inviteAccepted" flag stops it declining when it hides).
local pending
local function closePopup()
    if not pending or InCombatLockdown() then return end
    pending = nil
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local f = _G["StaticPopup" .. i]
        if f and f:IsShown() and (f.which == "PARTY_INVITE" or f.which == "PARTY_INVITE_XREALM") then
            f.inviteAccepted = 1
            pcall(StaticPopup_Hide, f.which)
        end
    end
end

ns:On("PARTY_INVITE_REQUEST", function(name, _, _, _, _, _, guid)
    if ns.db.invites.friends == false or not AcceptGroup then return end
    if IsInGroup and IsInGroup() then return end
    if not I.IsFriend(name, guid) then return end
    pending = true
    AcceptGroup()
    ns:Print("joined " .. tostring(ns.api.Safe(name) or "your friend") .. "'s group (a friend's invite, accepted for you; /flow invites off to stop)")
    ns:Log("invite", "accepted a friend's invite: " .. tostring(ns.api.Safe(name)))
    C_Timer.After(1, closePopup)
end)
ns:On("GROUP_ROSTER_UPDATE", closePopup)

ns:OnLoad(function(saved)
    saved.invites = saved.invites or {}
end)

ns.commands.invites = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then ns.db.invites.friends = (arg == "on") end
    ns:Print("auto-accept group invites from friends: " .. (ns.db.invites.friends == false and "off" or "on")
        .. "  (/flow invites on|off)")
end
