-- Diagnostics (REQ-033): an optional log for reviewing organic play. While "Keep a
-- diagnostic log" is on (/revenge log on), Revenge saves one short, timed line for each
-- event worth checking later:
--   - session:  login, the version, the client and every switch; logout
--   - death:    your death recorded, or not recorded and why
--   - out:      what you shared, hellos and catch-up answers, messages the game refused
--   - in:       what arrived, by which route and from whom, and what was turned away, and why
--   - friends:  a friend found running Revenge
--   - alert:    alerts, and whether they showed as a popup, in chat, with a sound
--   - tooltip, skull, pins:  the first time a player's tooltip or nameplate showed
--               Revenge's lines this session; the map's pins when they change
--   - list:     players marked Wanted, taken off the list, kills dismissed
--   - others:   the other-addons module, each other addon's reports, breakers, imports
--   - error:    errors Revenge caught (each message three times, then counted)
-- Lines go to RevengeTrackerDB.log as "<server time> <kind> <text>", oldest first, the
-- newest MAX kept. Nothing is printed or shared. The lines are for review
-- (tools/review_log.py), so they're English only, like the debug lines (DEC-033).
local _, ns = ...

local Diagnostics = ns.RegisterModule("Diagnostics", {})
local L = ns.L
local Try = ns.Try

Diagnostics.MAX = 2000          -- lines kept
Diagnostics.SLACK = 200         -- trimmed in batches, so a line costs about a table insert
Diagnostics.MAX_TEXT = 240      -- bytes per line
Diagnostics.ERROR_REPEATS = 3   -- the same error is written this often, then only counted
local MAX_NAMES = 3

local errorCounts = {}          -- error text -> times seen this session

local function On()
    local db = ns.db
    return db ~= nil and type(db.settings) == "table" and db.settings.diagnosticLog == true
end
Diagnostics.On = On

-- A value as it may go into a line: never a secret.
local function Clean(value)
    value = ns.Accessible(value)
    local kind = type(value)
    if kind == "number" or kind == "string" then return value end
    if kind == "nil" then return "-" end
    if kind == "boolean" then return tostring(value) end
    return kind
end

local function Lines()
    local log = ns.db.log
    if type(log) ~= "table" then
        log = {}
        ns.db.log = log
    end
    return log
end

-- Keeps the newest MAX lines.
local function Trim(log)
    local n = #log
    local drop = n - Diagnostics.MAX
    if drop <= 0 then return end
    for i = 1, Diagnostics.MAX do log[i] = log[i + drop] end
    for i = n, Diagnostics.MAX + 1, -1 do log[i] = nil end
end

local function Format(fmt, ...)
    local n = select("#", ...)
    if n == 0 then return tostring(fmt) end
    local args = { ... }
    for i = 1, n do args[i] = Clean(args[i]) end
    local ok, text = pcall(string.format, fmt, unpack(args, 1, n))
    return ok and text or tostring(fmt)
end

local function Write(kind, text)
    -- No control bytes or escape codes: one line each, readable anywhere.
    text = text:gsub("[%c|]", " ")
    if #text > Diagnostics.MAX_TEXT then text = text:sub(1, Diagnostics.MAX_TEXT - 3) .. "..." end
    local log = Lines()
    log[#log + 1] = ("%d %s %s"):format(ns.Now(), kind, text)
    if #log > Diagnostics.MAX + Diagnostics.SLACK then Trim(log) end
end

local function Add(kind, fmt, ...)
    local text = Format(fmt, ...)
    if kind == "error" then
        local seen = (errorCounts[text] or 0) + 1
        errorCounts[text] = seen
        if seen > Diagnostics.ERROR_REPEATS then return end
    end
    Write(kind, text)
end

-- Saves one line while the log is on. kind: a short word ("death", "in", "alert"...);
-- fmt and ... as for string.format. Never errors, and costs next to nothing while off.
function ns.Log(kind, fmt, ...)
    if not On() then return end
    pcall(Add, tostring(kind), fmt, ...)
end

-- "Gorvak Ashmane, Darrok Vane +2": names of identities, for a line.
function Diagnostics.Names(identities)
    if type(identities) ~= "table" then return "-" end
    local names = {}
    for i = 1, math.min(#identities, MAX_NAMES) do
        local identity = identities[i]
        names[i] = type(identity) == "table" and identity.name or "?"
    end
    local text = table.concat(names, ", ")
    if #identities > MAX_NAMES then text = text .. " +" .. (#identities - MAX_NAMES) end
    return text
end

---------------------------------------------------------------------------
-- Session lines: what a review needs to know about the setup
---------------------------------------------------------------------------
local function Switch(key)
    return ns.Store.Setting(key) == true and "on" or "off"
end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function SessionLines()
    local version, build = Try(GetBuildInfo)
    local me = ns.Identity.Self()
    local own = 0
    for _, kill in pairs(ns.Store.AllKills()) do
        if kill.own then own = own + 1 end
    end
    ns.Log("session", "Revenge %s, client %s (%s); %s, level %s, %s; in a guild: %s; stored: %d deaths (%d from Revenge), %d Wanted marks",
        ns.VERSION, version, build, me and me.name, Try(UnitLevel, "player"), me and me.faction,
        Try(IsInGuild) and "yes" or "no", Count(ns.Store.AllKills()), own, Count(ns.Store.AllWanted()))
    ns.Log("session", "switches: sharing guild %s, friends %s, Battle.net %s; alerts nearby %s, killed %s, popup %s, chat %s, sound %s; skulls %s, map pins %s; expiry %s days",
        Switch("shareGuild"), Switch("shareFriends"), Switch("shareBattleNet"), Switch("alertNearby"),
        Switch("alertFriendKilled"), Switch("alertPopup"), Switch("alertChat"), Switch("alertSound"),
        Switch("nameplates"), Switch("mapPins"), ns.Store.Setting("expiryDays"))
    ns.Log("session", "other addons %s: Revenge Book %s, Grudgekeeper %s, HeadHunter %s, Kill on Sight %s",
        Switch("otherAddons"), Switch("otherRevengeBook"), Switch("otherGrudgekeeper"), Switch("otherHeadHunter"),
        Switch("otherKillOnSight"))
end

local function RepeatedErrors()
    for text, seen in pairs(errorCounts) do
        if seen > Diagnostics.ERROR_REPEATS then
            Write("error", ("(%d more times this session) %s"):format(seen - Diagnostics.ERROR_REPEATS, text))
        end
    end
end

---------------------------------------------------------------------------
-- The switch: the settings page, or /revenge log on|off|clear
---------------------------------------------------------------------------
function Diagnostics.OnSwitch()
    if On() then
        ns.Log("log", "on (%d lines kept from before)", #Lines())
        SessionLines()
    end
end

function Diagnostics.SetEnabled(on)
    if ns.Settings and ns.Settings.Set then
        ns.Settings.Set("diagnosticLog", on)
    else
        ns.db.settings.diagnosticLog = on
        Diagnostics.OnSwitch()
    end
end

function Diagnostics.Count()
    return type(ns.db.log) == "table" and #ns.db.log or 0
end

function Diagnostics.Command(rest)
    if rest == "on" or rest == "off" then
        Diagnostics.SetEnabled(rest == "on")
        ns.Print(rest == "on" and L.LOG_ON or L.LOG_OFF)
    elseif rest == "clear" then
        ns.db.log = {}
        wipe(errorCounts)
        ns.Print(L.LOG_CLEARED)
    else
        ns.Print(L.LOG_STATUS:format(On() and L.LOG_STATE_ON or L.LOG_STATE_OFF, Diagnostics.Count()))
    end
end

function Diagnostics:Init()
    -- Keep only well-formed lines, and no more than MAX.
    local log = ns.db.log
    if log == nil then return end
    if type(log) ~= "table" then
        ns.db.log = nil
        return
    end
    local kept = {}
    for i = 1, #log do
        if type(log[i]) == "string" then kept[#kept + 1] = log[i] end
    end
    Trim(kept)
    ns.db.log = kept
end

function Diagnostics:OnLogin()
    SessionLines()
    ns.On("PLAYER_LOGOUT", function()
        if not On() then return end
        RepeatedErrors()
        Write("session", "logout")
    end)
end
