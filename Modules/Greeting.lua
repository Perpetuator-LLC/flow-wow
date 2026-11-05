-- Shows a "hello sooth" dialog when you log in to a character.

local _, ns = ...

StaticPopupDialogs["SOOTHMOD_HELLO"] = {
    text = "hello sooth",
    button1 = OKAY,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function showHello()
    StaticPopup_Show("SOOTHMOD_HELLO")
end

local shown = false
ns:On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
    -- Only on real login/reload, not every zone change or instance load.
    -- (Older clients don't pass these args; fall back to once per session.)
    if isInitialLogin or isReloadingUi or (isInitialLogin == nil and not shown) then
        shown = true
        showHello()
    end
end)

ns.commands.hello = showHello
