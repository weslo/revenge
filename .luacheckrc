-- luacheck config for Revenge (WoW: Forever, Lua 5.1).
-- Note: luacheck 1.2.0 parses with Lua 5.4, so 5.2+ syntax like `//` isn't flagged here;
-- tools/check_lua51.py covers that.
std = "lua51"
max_line_length = false
self = false  -- module methods like Module:OnLogin() needn't use self
exclude_files = { ".luacheckrc", "tools/**", "docs/**", "tests/**", ".venv/**", ".release/**" }

-- Globals Revenge defines.
globals = {
    "RevengeTrackerDB",
    "RevengeTracker",
    "RevengeTrackerKillPinMixin",
    "SLASH_REVENGETRACKER1",
    "SlashCmdList",
}

-- Game API Revenge reads.
read_globals = {
    "bit", "wipe",
    "C_AddOns", "C_Timer", "C_Map", "C_DeathRecap", "C_FriendList", "C_ChatInfo",
    "CreateFrame", "DEFAULT_CHAT_FRAME", "GameTooltip", "TooltipDataProcessor", "Enum",
    "Settings", "MinimalSliderWithSteppersMixin", "CreateSettingsListSectionHeaderInitializer",
    "CreateScrollBoxListLinearView", "CreateDataProvider", "ScrollUtil", "ScrollBoxConstants",
    "LOCALIZED_CLASS_NAMES_MALE",
    "GetServerTime", "IsInInstance", "GetRealZoneText", "InCombatLockdown",
    "UnitFullName", "GetUnitName", "RegionalUniqueNamesEnabled", "UnitIsPlayer", "UnitGUID",
    "UnitClass", "UnitLevel", "UnitFactionGroup", "GetGuildInfo", "GetPlayerInfoByGUID", "IsGuildMember",
    "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown",
    "GetTime", "IsInGuild", "Ambiguate", "UIParent", "PlaySound", "SOUNDKIT",
    "C_NamePlate", "C_BattleNet", "BNGetNumFriends", "BNSendGameData", "BNET_CLIENT_WOW", "WOW_PROJECT_ID",
    "WorldMapFrame", "CreateFromMixins", "Mixin", "MapCanvasDataProviderMixin", "MapCanvasPinMixin", "MenuUtil",
    "IsInRaid", "GetNumGroupMembers",
}

-- The optional module reads other addons' saved data (never writes it), and Revenge's
-- small API through the RevengeTracker global.
files["RevengeTracker_OtherAddons/**"] = {
    globals = {},
    read_globals = {
        "RevengeTracker", "debugprofilestop", "GetRealmName", "GetNormalizedRealmName",
        "DeathNoteDB", "HeadHunter_DB", "KillOnSightDB",
    },
}
