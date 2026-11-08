-- luacheck config for Flow (WoW: Forever, Lua 5.1). Run: tools\lint.ps1
-- The game's API is thousands of globals, so reading a capitalised global
-- (UnitHealth, C_Map, GameTooltip...) is allowed. What's flagged:
--   * reading an unknown lowercase global (usually a local used before it's
--     declared, or a typo)
--   * setting ANY global Flow doesn't mean to (a missing "local")
--   * unused variables and values, shadowing, unreachable code
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "dist/**" }   -- release staging copies

ignore = {
    "113/[A-Z].*",   -- reading a capitalised global: the WoW API
    "113/_G",
    "143/[A-Z].*",   -- reading fields of WoW API tables (C_Map.Foo, string.bar...)
    "212",           -- unused argument (event handlers get more than they use)
    "213",           -- unused loop variable
    "542",           -- empty if branch
    "431", "432",    -- a nested function reusing an outer name (common, and harmless here)
}

-- Lowercase globals the game provides.
read_globals = {
    "bit", "date", "time", "tinsert", "tremove", "wipe", "strsplit", "strtrim", "strjoin",
    "strlower", "strupper", "format", "floor", "ceil", "max", "min", "abs", "sqrt",
    "issecretvalue", "issecret", "issecurevariable", "hooksecurefunc", "debugprofilestop",
    "getprinthandler", "setprinthandler", "geterrorhandler", "seterrorhandler", "securecall",
    "debugstack", "tContains", "hash_SlashCmdList",
}

-- Globals Flow sets on purpose (slash commands, key binding names, saved
-- variables) and Blizzard tables it adds its own entries to.
globals = {
    "FlowDB", "FlowCharDB",
    "SLASH_FLOW1", "SLASH_FLOW2", "SLASH_FLOWWAY1",
    "BINDING_HEADER_FLOW",
    "SlashCmdList", "StaticPopupDialogs", "UISpecialFrames",
}
