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
L.YOU_LOWER = "you"            -- in "Wanted by you"
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
L.SECTION_KILLS = "Kills"
L.SECTION_SHARING = "Sharing"
L.SETTING_SHARE_GUILD = "Share my deaths and wanted players with my guild"
L.SETTING_SHARE_GUILD_TOOLTIP = "Guildmates who run Revenge see your recent deaths and the players you've marked Wanted. You see theirs either way."

-- Recent killers list (settings)
L.LIST_HEADER = "Recent killers"
L.LIST_TITLE = "Recent killers (%d)"
L.LIST_EMPTY = "No recent killers. Kills older than %s drop off by themselves."
L.ADD_LABEL = "Add by name"
L.ADD_PLACEHOLDER = "First Last"
L.ADD_BUTTON = "Add"
L.REMOVE_BUTTON = "Remove"
L.REMOVED = "Removed %s."
L.WHO_LEVEL_CLASS = "Level %d %s"
L.WHO_LEVEL = "Level %d"
L.WHO_UNSEEN = "Not seen yet"
L.ADD_EMPTY = "Type a player's name first."
L.ADD_INVALID = "That isn't a player name: use letters and spaces only."
L.ADD_NEED_FULL = "Type the player's first and last name."
L.ADD_SELF = "That's you."
L.ADD_SAME_FACTION = "%s is on your own faction."
L.ADD_ALREADY = "%s is already wanted by you."
L.ADD_DONE = "%s is now wanted by you."
L.ADD_FAILED = "Couldn't add that player. Try again in a moment."

-- Slash command
L.HELP_HEADER = "Revenge commands:"
L.HELP_OPEN = "/revenge - open the settings"
L.HELP_ADD = "/revenge add First Last - mark a player Wanted by you"
L.HELP_TEST = "/revenge test - record a test kill on you by your current target (a player)"
L.HELP_TEST_SHARE = "/revenge test share - the same, and send it to guildmates running Revenge, to try sharing"
L.HELP_TEST_CLEAR = "/revenge test clear - remove all test kills, including ones guildmates sent"
L.HELP_DEBUG = "/revenge debug - turn the debug log in chat on or off"
L.TEST_NEED_PLAYER = "Target a player first."
L.TEST_ADDED = "Added a test kill on you by %s."
L.TEST_ADDED_SHARED = "Added a test kill on you by %s, and sent it to guildmates running Revenge."
L.TEST_ADDED_NOT_SHARED = "Added a test kill on you by %s, but didn't send it: you're not in a guild, or guild sharing is off."
L.TEST_CLEARED = "Removed %d test kills."
L.DEBUG_ON = "Debug log on."
L.DEBUG_OFF = "Debug log off."
