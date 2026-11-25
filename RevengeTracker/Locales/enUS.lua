-- English strings: the base catalog. Other locales would override keys and fall back to these.
local _, ns = ...

local L = setmetatable({}, {
    -- A missing key shows the key itself rather than erroring.
    __index = function(_, key) return key end,
})
ns.L = L

L.TITLE = "Revenge"
L.PREFIX = "|cffff8c6eRevenge|r"

-- Tooltip
L.YOU = "You"
L.MORE = "+%d more"
L.AS_FRIEND = "%s (friend)"
L.AS_GUILD = "%s (guild)"
L.WANTED_BY = "Wanted by %s"
L.LIST_AND = ", "
L.AGO_MINUTES = "%dm ago"
L.AGO_HOURS = "%dh ago"
L.AGO_DAYS = "%dd ago"
L.UNKNOWN_ZONE = "Unknown zone"

-- Settings
L.SETTING_EXPIRY = "Show kills for"
L.SETTING_EXPIRY_TOOLTIP = "How long a kill stays on tooltips, nameplates, alerts and the map. Wanted players never expire."
L.DAYS_ONE = "1 day"
L.DAYS_MANY = "%d days"
L.SETTING_MODIFIER = "Tooltip details while holding"
L.SETTING_MODIFIER_TOOLTIP = "Hold this key while hovering a recorded enemy to list each recent kill."
L.MODIFIER_SHIFT = "Shift"
L.MODIFIER_CTRL = "Ctrl"
L.MODIFIER_ALT = "Alt"
L.MODIFIER_OFF = "Off (never)"
L.SETTINGS_UNAVAILABLE = "The game's settings panel isn't available, so Revenge's options can't be shown. Your saved settings are kept."
L.CANNOT_OPEN_IN_COMBAT = "Can't open settings during combat."

-- Slash command
L.HELP_HEADER = "Revenge commands:"
L.HELP_OPEN = "/revenge - open the settings"
L.HELP_TEST = "/revenge test - record a test kill on you by your current target (a player)"
L.HELP_TEST_CLEAR = "/revenge test clear - remove all test kills"
L.HELP_DEBUG = "/revenge debug - turn the debug log in chat on or off"
L.TEST_NEED_PLAYER = "Target a player first."
L.TEST_ADDED = "Added a test kill on you by %s."
L.TEST_CLEARED = "Removed %d test kills."
L.DEBUG_ON = "Debug log on."
L.DEBUG_OFF = "Debug log off."
