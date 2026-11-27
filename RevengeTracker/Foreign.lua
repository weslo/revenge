-- Foreign: the only door for data from other addons.
--
-- The optional module RevengeTracker_OtherAddons (loaded on demand, and only while
-- "Use data from other addons" is on) decodes other addons' messages and saved data,
-- and hands the results to RevengeTracker.SubmitForeign. Everything is checked here
-- before it reaches the merge:
--   - who sent it: a guildmate (the guild channel), an online friend (in-game or
--     Battle.net), or a group member who is one of those. Never a stranger (DEC-021);
--   - that it's the sender's own: a death's victim, a mark's adder. Saved data from
--     your own copy of the other addon is exempt, since that addon checked it already;
--   - known record types, field types, string lengths, number ranges and sane times.
-- Anything wrong is dropped silently. Revenge's own data always wins (Merge.lua), and
-- data known only from other addons is hidden while their use is switched off
-- (Store.lua). docs/plans/revenge/OTHER-ADDONS.md has the plan.
local _, ns = ...

local Foreign = ns.RegisterModule("Foreign", {})
local L = ns.L
local Identity, Store = ns.Identity, ns.Store
local Try, AccessibleString, AccessibleNumber = ns.Try, ns.AccessibleString, ns.AccessibleNumber

local MODULE = "RevengeTracker_OtherAddons"
local MODULE_DELAY = 5              -- seconds after login: Revenge's own start-up goes first
local MAX_TEXT = 64
local MAX_KILLERS = 5
local MAX_RECORDS = 50              -- per call
local MAX_PER_SESSION = 3000        -- records accepted per session, from all other addons
local MAX_AGE = 30 * 86400
local MARKS_SINCE = 1000000000      -- marks never expire, but a time before 2001 is junk
local MAX_FUTURE = 300
local MAX_SENDER = 80
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

-- The other addons Revenge can read; the module has an adapter for each.
Foreign.ADAPTERS = {
    { id = "revengebook", title = "Revenge Book", setting = "otherRevengeBook", tooltip = "SETTING_OTHER_REVENGEBOOK_TOOLTIP" },
    { id = "grudgekeeper", title = "Grudgekeeper", setting = "otherGrudgekeeper", tooltip = "SETTING_OTHER_GRUDGEKEEPER_TOOLTIP" },
    { id = "headhunter", title = "HeadHunter", setting = "otherHeadHunter", tooltip = "SETTING_OTHER_HEADHUNTER_TOOLTIP" },
    { id = "killonsight", title = "Kill on Sight", setting = "otherKillOnSight", tooltip = "SETTING_OTHER_KILLONSIGHT_TOOLTIP" },
}
local byId = {}
for _, adapter in ipairs(Foreign.ADAPTERS) do byId[adapter.id] = adapter end

local acceptedThisSession = 0

-- "Revenge Book" for "revengebook"; an unknown source shows as its ID.
function Foreign.Title(sourceId)
    local adapter = byId[sourceId]
    return adapter and adapter.title or sourceId
end

-- The other addon a kill came from, when no Revenge user reported it ("via Revenge Book").
function Foreign.Via(kill)
    if kill.own or type(kill.sources) ~= "table" then return nil end
    local names = {}
    for source in pairs(kill.sources) do
        if type(source) == "string" then names[#names + 1] = source end
    end
    if #names == 0 then return nil end
    table.sort(names)
    return Foreign.Title(names[1])
end

local function Enabled()
    return ns.db ~= nil and Store.Setting("otherAddons") == true
end

local function AdapterOn(sourceId)
    local adapter = byId[sourceId]
    return not adapter or Store.Setting(adapter.setting) ~= false
end

---------------------------------------------------------------------------
-- Trust
---------------------------------------------------------------------------
local function GroupMember(sender)
    local units = {}
    if Try(IsInRaid) then
        for i = 1, math.min(AccessibleNumber(Try(GetNumGroupMembers)) or 0, 40) do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    for _, unit in ipairs(units) do
        local identity = Identity.FromUnit(unit)
        if identity and identity.key and Identity.SenderIs(sender, identity.key) then return identity end
    end
    return nil
end

-- Whether a name the game gave is an online friend, or a group member who is a
-- guildmate or friend.
local function TrustedName(name)
    if ns.Friends and ns.Friends.IsFriendName(name) then return true end
    local member = GroupMember(name)
    local group = member and Identity.Group(member)
    return group == "guild" or group == "friend"
end

-- Whether a message that came on `channel` from `sender` (the name the game gave)
-- comes from someone Revenge takes data from.
function Foreign.Trusted(sender, channel)
    sender = AccessibleString(sender)
    if not sender or #sender > MAX_SENDER then return false end
    if channel == "GUILD" then return Try(IsInGuild) and true or false end
    if channel == "WHISPER" or GROUP_CHANNELS[channel] then return TrustedName(sender) end
    return false
end

---------------------------------------------------------------------------
-- Checking records
---------------------------------------------------------------------------
local function Text(value)
    return type(value) == "string" and #value > 0 and #value <= MAX_TEXT and not value:find("[%c|]") and value or nil
end

local function Number(value, low, high)
    return type(value) == "number" and value >= low and value <= high and value or nil
end

local function CleanIdentity(raw)
    if type(raw) ~= "table" then return nil end
    local name = Text(raw.name)
    local guid = Text(raw.guid)
    if guid and not guid:match("^Player%-") then guid = nil end
    local identity = Identity.Make(name, guid)
    if not identity then return nil end
    identity.class = Text(raw.class)
    if identity.class and not identity.class:match("^%u+$") then identity.class = nil end
    identity.level = Number(raw.level, 1, 100)
    identity.guild = Text(raw.guild)
    return identity
end

local function CleanKill(raw, sourceId, now)
    local at = Number(raw.at, now - MAX_AGE, now + MAX_FUTURE)
    local victim = CleanIdentity(raw.victim)
    if not (at and victim and victim.key and type(raw.killers) == "table") then return nil end
    local killers = {}
    for i = 1, math.min(#raw.killers, MAX_KILLERS) do
        local killer = CleanIdentity(raw.killers[i])
        if killer and not Identity.IsSelf(killer) then killers[#killers + 1] = killer end
    end
    if #killers == 0 then return nil end
    local precision = raw.precision
    if precision ~= "exact" and precision ~= "client" then precision = "received" end
    local x, y = Number(raw.x, 0, 1), Number(raw.y, 0, 1)
    if not (x and y) then x, y = nil, nil end
    return {
        victim = victim,
        killers = killers,
        at = at,
        precision = precision,
        mapID = Number(raw.mapID, 1, 100000),
        x = x,
        y = y,
        zone = Text(raw.zone),
        sources = { [sourceId] = true },
    }
end

local function CleanMark(raw, sourceId, now)
    local target, by = CleanIdentity(raw.target), CleanIdentity(raw.by)
    local at = Number(raw.at, MARKS_SINCE, now + MAX_FUTURE)
    if not (target and target.key and by and by.key and at) or Identity.IsSelf(target) then return nil end
    -- Some addons' marks lapse (Grudgekeeper's kill orders); Revenge's own never do.
    local expires = Number(raw.expires, now, now + MAX_AGE)
    return { target = target, by = by, at = at, expires = expires, sources = { [sourceId] = true } }
end

-- Whose own a record must be: the victim of a death, the adder of a mark. Nothing
-- second-hand: a copy relayed by someone else is a stranger's report (DEC-021).
local function OwnedBySender(ownerKey, sender, channel)
    return channel == "SAVED" or Identity.SenderIs(sender, ownerKey)
end

-- Returns whether the record was taken, and what happened, for the diagnostic log
-- (described in full only when `noting`, so it costs nothing while the log is off).
local function SubmitOne(raw, sourceId, sender, channel, now, noting)
    if type(raw) ~= "table" then return false, "not a record" end
    if raw.type == "kill" then
        local kill = CleanKill(raw, sourceId, now)
        if not kill then return false, "a death that failed the checks" end
        if not OwnedBySender(kill.victim.key, sender, channel) then
            return false, ("%s's death: not the sender's own"):format(tostring(kill.victim.name))
        end
        local what = noting and ("%s's death by %s in %s"):format(tostring(kill.victim.name),
            ns.Diagnostics.Names(kill.killers), tostring(kill.zone or "?")) or "a death"
        local stored, new = ns.Merge.SubmitKill(kill)
        if not stored then return false, what .. ": dismissed earlier" end
        -- A death arriving live (not a catch-up answer or saved data) alerts once.
        local live = raw.live == true and channel ~= "SAVED"
        if new and live then Try(ns.Alerts and ns.Alerts.FriendKilled, stored) end
        return true, what .. (new and ": new" or ": already known") .. (live and ", live" or "")
    elseif raw.type == "wanted" or raw.type == "withdrawal" then
        local mark = CleanMark(raw, sourceId, now)
        if not mark then return false, "a mark that failed the checks" end
        if not OwnedBySender(mark.by.key, sender, channel) then
            return false, ("a mark by %s: not the sender's own"):format(tostring(mark.by.name))
        end
        local what = noting and ("%s Wanted by %s"):format(tostring(mark.target.name), tostring(mark.by.name)) or "a mark"
        if raw.type == "wanted" then
            local stored, new = ns.Merge.SubmitWanted(mark)
            if not stored then return false, what .. ": taken back earlier" end
            return true, what .. (new and ": new" or ": already known") .. (mark.expires and ", until it lapses" or "")
        end
        local removed = ns.Merge.SubmitWithdrawal(mark, raw.remember == false)
        return true, ("%s: ended, %s marks removed"):format(what, tostring(removed))
    end
    return false, "an unknown record type"
end

-- records: a list of raw records from one adapter. sourceId: e.g. "revengebook".
-- sender and channel: who sent them and how ("GUILD", "PARTY", "RAID",
-- "INSTANCE_CHAT", "WHISPER"), or channel "SAVED" for your own copy of the other
-- addon's saved data. Returns how many were accepted. Never errors.
function Foreign.Submit(records, sourceId, sender, channel)
    if not Enabled() or type(records) ~= "table" or not Text(sourceId) or not AdapterOn(sourceId) then return 0 end
    if channel ~= "SAVED" and not Foreign.Trusted(sender, channel) then
        ns.Log("others", "%s: refused a report from %s by %s: not a guildmate or friend", Foreign.Title(sourceId),
            sender, channel)
        return 0
    end
    local accepted, now, notes = 0, ns.Now(), {}
    local total = math.min(#records, MAX_RECORDS)
    -- Saved data comes in batches; the module writes one line for each whole read.
    local noting = channel ~= "SAVED" and ns.Diagnostics.On()
    ns.Batch(function()
        for i = 1, total do
            if acceptedThisSession >= MAX_PER_SESSION then
                notes[#notes + 1] = "this session's limit is reached"
                break
            end
            local ok, taken, note = pcall(SubmitOne, records[i], sourceId, sender, channel, now, noting)
            if ok and taken then
                accepted = accepted + 1
                acceptedThisSession = acceptedThisSession + 1
            elseif not ok then
                ns.Fail("other addons: %s record error: %s", sourceId, tostring(taken))
                note = "an error"
            end
            if #notes < 2 then notes[#notes + 1] = note end
        end
    end)
    if noting then
        ns.Log("others", "%s from %s by %s: %d of %d taken: %s", Foreign.Title(sourceId), sender, channel, accepted,
            total, table.concat(notes, "; "))
    end
    return accepted
end

-- An addon whose list is its saved data (Kill on Sight) read its whole list: Wanted
-- by you marks that only it gave, for players no longer on it, go. names: the
-- players on the list now. Returns how many marks went.
function Foreign.SyncMarks(sourceId, names)
    if not Enabled() or not Text(sourceId) or not AdapterOn(sourceId) or type(names) ~= "table" then return 0 end
    local listed = {}
    for i = 1, math.min(#names, 5000) do
        local key = Identity.Key(Text(names[i]))
        if key then listed[key] = true end
    end
    local gone = {}
    for id, mark in pairs(Store.AllWanted()) do
        local only = type(mark.sources) == "table" and mark.sources[sourceId] and next(mark.sources, nil) ~= nil
        if only then
            for source in pairs(mark.sources) do
                if source ~= sourceId then only = false end
            end
        end
        if only and not mark.own and Identity.IsSelf(mark.by) and not listed[mark.target.key] then
            gone[#gone + 1] = id
        end
    end
    for _, id in ipairs(gone) do Store.RemoveWanted(id) end
    if #gone > 0 then
        ns.Log("others", "%s: %d Wanted marks removed, those players are off its list", Foreign.Title(sourceId), #gone)
        ns.Changed()
    end
    return #gone
end

---------------------------------------------------------------------------
-- The module: loaded on demand, only while other addons' data is in use
---------------------------------------------------------------------------
-- "waiting" (not tried yet), "loaded", "off", "missing", "disabled" or "failed".
Foreign.moduleState = "waiting"

local function ModuleLoaded()
    return C_AddOns and C_AddOns.IsAddOnLoaded and Try(C_AddOns.IsAddOnLoaded, MODULE) and true or false
end

local REASONS = { MISSING = "missing", DISABLED = "disabled", DEP_DISABLED = "disabled" }

function Foreign.LoadModule()
    if not Enabled() then
        if not ModuleLoaded() then Foreign.moduleState = "off" end
        return
    end
    if ModuleLoaded() then
        Foreign.moduleState = "loaded"
        return
    end
    if Try(InCombatLockdown) then
        if not Foreign.waitingForCombat then ns.Log("others", "the module waits for combat to end") end
        Foreign.waitingForCombat = true
        return
    end
    if not (C_AddOns and C_AddOns.LoadAddOn) then
        Foreign.moduleState = "failed"
        ns.Log("others", "the module isn't loaded: the game can't load addons on demand")
        return
    end
    local loaded, reason = Try(C_AddOns.LoadAddOn, MODULE)
    if loaded then
        Foreign.moduleState = "loaded"
        ns.Log("others", "the module is loaded")
    else
        Foreign.moduleState = REASONS[AccessibleString(reason) or ""] or "failed"
        ns.Debug("other addons: the module didn't load (%s)", tostring(reason))
        ns.Log("others", "the module isn't loaded: %s (%s)", Foreign.moduleState, reason)
    end
end

-- The master switch, from the settings page or /revenge others on|off. Off hides
-- what only other addons reported at once; the module itself stays until /reload.
-- On loads the module now.
function Foreign.SetEnabled(on)
    if ns.Settings and ns.Settings.Set then
        ns.Settings.Set("otherAddons", on)
    else
        ns.db.settings.otherAddons = on
        Foreign.OnSwitch()
    end
end

function Foreign.OnSwitch()
    ns.Changed()
    if Enabled() then Foreign.LoadModule() end
end

---------------------------------------------------------------------------
-- Status, for the settings page and /revenge others
---------------------------------------------------------------------------
local STATES = { listening = "OTHERS_LISTENING", reading = "OTHERS_READING", paused = "OTHERS_PAUSED",
                 off = "OTHERS_ADAPTER_OFF", absent = "OTHERS_ABSENT", watching = "OTHERS_WATCHING" }

local function Describe(adapter, status)
    if Store.Setting(adapter.setting) == false then return L.OTHERS_ADAPTER_OFF:format(adapter.title) end
    local state = type(status) == "table" and STATES[status.state] or "OTHERS_LISTENING"
    local text = L[state]:format(adapter.title)
    local reports = type(status) == "table" and type(status.reports) == "number" and status.reports or 0
    if reports > 0 and state ~= "OTHERS_PAUSED" then text = text .. L.OTHERS_REPORTS:format(reports) end
    return text
end

-- One line per other addon, or one line saying why none is in use.
function Foreign.StatusLines()
    if not Enabled() then return { L.OTHERS_OFF } end
    if Foreign.moduleState ~= "loaded" then
        return { L["OTHERS_MODULE_" .. Foreign.moduleState:upper()] or L.OTHERS_MODULE_FAILED }
    end
    local status = Foreign.module and Try(Foreign.module.Status)
    local lines = {}
    for _, adapter in ipairs(Foreign.ADAPTERS) do
        lines[#lines + 1] = Describe(adapter, type(status) == "table" and status[adapter.id])
    end
    return lines
end

function Foreign:OnLogin()
    ns.On("PLAYER_REGEN_ENABLED", function()
        if Foreign.waitingForCombat then
            Foreign.waitingForCombat = false
            Foreign.LoadModule()
        end
    end)
    if Enabled() then
        ns.After(MODULE_DELAY, Foreign.LoadModule)
    else
        Foreign.moduleState = "off"
    end
end

---------------------------------------------------------------------------
-- The small public surface the module uses. Every call is safe to make with junk.
---------------------------------------------------------------------------
local function Safe(fn, fallback)
    return function(...)
        local ok, result = pcall(fn, ...)
        if ok then return result end
        return fallback
    end
end

RevengeTracker = {
    API = 1,
    SubmitForeign = Safe(Foreign.Submit, 0),
    -- Whether messages from this sender on this channel would be taken.
    Trusted = Safe(function(sender, channel) return Foreign.Trusted(sender, channel) end, false),
    -- Whether the game's name for a sender is you (guild messages come back to you).
    IsSelf = Safe(function(sender)
        local me = Identity.Self()
        return me ~= nil and me.key ~= nil and Identity.SenderIs(sender, me.key)
    end, false),
    -- Your own name, "First Last", for saved data that names you.
    SelfName = Safe(function()
        local me = Identity.Self()
        return me and me.name
    end),
    SyncMarks = Safe(Foreign.SyncMarks, 0),
    Enabled = Safe(Enabled, false),
    AdapterOn = Safe(function(id) return Enabled() and AdapterOn(id) end, false),
    -- The module hands over { Status = function() return { [id] = { state, reports } } end }.
    Attach = Safe(function(module)
        if type(module) == "table" then Foreign.module = module end
    end),
    Debug = Safe(function(fmt, ...) ns.Debug("other addons: " .. tostring(fmt), ...) end),
    -- A line in Revenge's diagnostic log (Diagnostics.lua), while it's on.
    Log = Safe(function(kind, fmt, ...) ns.Log(kind, fmt, ...) end),
}
