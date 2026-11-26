-- luacheck config for Revenge (WoW: Forever, Lua 5.1).
-- Note: luacheck 1.2.0 parses with Lua 5.4, so 5.2+ syntax like `//` isn't flagged here;
-- tools/check_lua51.py covers that.
std = "lua51"
max_line_length = false
self = false  -- module methods like Module:OnLogin() needn't use self
exclude_files = { ".luacheckrc", "tools/**", "docs/**", "tests/**", ".venv/**" }

-- Globals Revenge defines.
globals = {
    "RevengeTrackerDB",
    "RevengeTracker",
    "SLASH_REVENGETRACKER1",
    "SlashCmdList",
}

-- Game API Revenge reads.
read_globals = {
    "bit", "wipe",
    "C_AddOns", "C_Timer", "C_Map", "C_DeathRecap", "C_FriendList",
    "CreateFrame", "DEFAULT_CHAT_FRAME", "GameTooltip", "TooltipDataProcessor", "Enum",
    "Settings", "MinimalSliderWithSteppersMixin",
    "GetServerTime", "IsInInstance", "GetRealZoneText", "InCombatLockdown",
    "UnitFullName", "GetUnitName", "RegionalUniqueNamesEnabled", "UnitIsPlayer", "UnitGUID",
    "UnitClass", "UnitLevel", "UnitFactionGroup", "GetGuildInfo", "GetPlayerInfoByGUID", "IsGuildMember",
    "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown",
}
