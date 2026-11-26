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
L.SETTING_SHARE_FRIENDS = "…with in-game friends"
L.SETTING_SHARE_FRIENDS_TOOLTIP = "In-game friends who run Revenge see your recent deaths and Wanted players. You see theirs either way."
L.SETTING_SHARE_BNET = "…with Battle.net friends"
L.SETTING_SHARE_BNET_TOOLTIP = "Battle.net friends playing WoW: Forever who run Revenge see your recent deaths and Wanted players. You see theirs either way."
L.SETTING_NAMEPLATES = "Skull beside recent killers' nameplates"
L.SETTING_NAMEPLATES_TOOLTIP = "A small skull beside the nameplate of anyone with a recent kill on you, a friend or a guildmate, or Wanted. The nameplate itself is left alone."
L.SETTING_MAP_PINS = "Show kills on the world map"
L.SETTING_MAP_PINS_TOOLTIP = "A skull where each recent death happened: yours, friends' and guildmates'. Hover for who and when; right-click to dismiss a kill."
L.SECTION_ALERTS = "Alerts"
L.SETTING_ALERT_NEARBY = "When a recent killer comes into view"
L.SETTING_ALERT_NEARBY_TOOLTIP = "When a recent killer or a Wanted player shows up on a nameplate, as your target or under the mouse. At most once every 5 minutes per player."
L.SETTING_ALERT_KILLED = "When an enemy kills a friend or guildmate"
L.SETTING_ALERT_KILLED_TOOLTIP = "As soon as their death is shared, wherever it happened in the open world. Once per death."
L.SETTING_ALERT_POPUP = "Show alerts as a small popup (silent, fades quickly)"
L.SETTING_ALERT_POPUP_TOOLTIP = "Near the top of the screen, with no sound or screen effects. It fades after about 4 seconds, or at once when clicked."
L.SETTING_ALERT_CHAT = "Show alerts in chat"
L.SETTING_ALERT_CHAT_TOOLTIP = "A line in your chat window."
L.SETTING_ALERT_SOUND = "Sound when a killer comes into view"
L.SETTING_ALERT_SOUND_TOOLTIP = "A short sound with the chat line for a killer nearby."

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

-- Alerts
L.ALERT_NEARBY = "%s is nearby"                          -- popup title
L.ALERT_NEARBY_CHAT = "%s is nearby: %s."
L.ALERT_KILLED = "%s was killed by %s"                    -- popup title; the zone goes below
L.ALERT_KILLED_CHAT = "%s was killed by %s."
L.ALERT_KILLED_CHAT_ZONE = "%s was killed by %s in %s."
L.ALERT_TEST = " (test)"

-- Map pins
L.PIN_KILLED_BY = "Killed by %s"
L.PIN_DISMISS_HINT = "Right-click to dismiss"
L.PIN_DISMISS = "Dismiss kill"
L.PIN_CANCEL = "Cancel"

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
