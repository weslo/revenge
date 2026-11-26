-- Store: saved data (account-wide), its defaults and migrations, and lookup indexes.
--
-- RevengeTrackerDB = {
--   version  = schema version,
--   settings = { see DEFAULTS },
--   kills    = { [id] = kill },      -- see Merge.lua for a kill's fields
--   wanted   = { [id] = mark },      -- Wanted marks; see Merge.lua for a mark's fields
--   withdrawals = { ["target key|adder key"] = time },  -- when an adder withdrew a mark
--   names    = { [guid] = { n = "First Last", c = classFile, l = level, g = guild, f = faction, t = seen } },
--   tombstones = { [killId] = { victim = key, killers = { { key, guid, partial }... }, at = time,
--                               all = true when the whole kill was dismissed } },
--   nextId   = counter,
--   lastSeen = server time of the last logout (Share.lua: what catch-up asks for),
-- }
local _, ns = ...

local Store = {}
ns.Store = Store

local SCHEMA_VERSION = 1
local KEEP_KILLS_DAYS = 60          -- history kept beyond the display expiry
local MAX_NAMES = 2000              -- name cache size
local KEEP_TOMBSTONES_DAYS = 90
local KEEP_WITHDRAWALS_DAYS = 180
local MAX_FOREIGN_KILLS = 1000      -- kills known only from other addons; the oldest go first
local MAX_FOREIGN_MARKS = 500

Store.DEFAULTS = {
    expiryDays = 7,
    detailsModifier = "SHIFT",      -- SHIFT, CTRL, ALT or OFF
    nameplates = true,
    mapPins = true,
    alertNearby = true,
    alertFriendKilled = true,
    alertPopup = true,
    alertChat = true,
    alertSound = true,
    shareGuild = true,
    shareFriends = true,
    shareBattleNet = true,
    otherAddons = true,
    otherRevengeBook = true,
    otherGrudgekeeper = true,
    otherHeadHunter = true,
    otherKillOnSight = true,
}

local VALID = {
    expiryDays = function(v) return type(v) == "number" and v >= 1 and v <= 30 end,
    detailsModifier = function(v) return v == "SHIFT" or v == "CTRL" or v == "ALT" or v == "OFF" end,
}

local function ValidSetting(key, value)
    if VALID[key] then return VALID[key](value) end
    return type(value) == type(Store.DEFAULTS[key])
end

-- Indexes rebuilt from saved data; never saved.
local byKillerGuid, byKillerKey, byVictimKey = {}, {}, {}
local byTargetGuid, byTargetKey = {}, {}

local function AddToIndex(index, key, id)
    if not key then return end
    local list = index[key]
    if not list then
        list = {}
        index[key] = list
    end
    list[#list + 1] = id
end

local function IndexKill(kill)
    for _, killer in ipairs(kill.killers) do
        AddToIndex(byKillerGuid, killer.guid, kill.id)
        AddToIndex(byKillerKey, killer.key, kill.id)
    end
    AddToIndex(byVictimKey, kill.victim.key, kill.id)
end

local function IndexMark(mark)
    AddToIndex(byTargetGuid, mark.target.guid, mark.id)
    AddToIndex(byTargetKey, mark.target.key, mark.id)
end

function Store.RebuildIndexes()
    wipe(byKillerGuid)
    wipe(byKillerKey)
    wipe(byVictimKey)
    wipe(byTargetGuid)
    wipe(byTargetKey)
    for _, kill in pairs(ns.db.kills) do IndexKill(kill) end
    for _, mark in pairs(ns.db.wanted) do IndexMark(mark) end
end

local function ValidIdentity(identity)
    return type(identity) == "table" and (type(identity.key) == "string" or type(identity.guid) == "string")
end

local function ValidKill(kill)
    if type(kill) ~= "table" or type(kill.at) ~= "number" or not ValidIdentity(kill.victim)
        or type(kill.killers) ~= "table" or #kill.killers == 0 then
        return false
    end
    for _, killer in ipairs(kill.killers) do
        if not ValidIdentity(killer) then return false end
    end
    if type(kill.sources) ~= "table" then kill.sources = {} end
    if kill.origins ~= nil and type(kill.origins) ~= "table" then kill.origins = nil end
    return true
end

local function ValidMark(mark)
    if type(mark) ~= "table" or type(mark.at) ~= "number" or not ValidIdentity(mark.target)
        or type(mark.target.key) ~= "string" or not ValidIdentity(mark.by) or type(mark.by.key) ~= "string" then
        return false
    end
    if type(mark.sources) ~= "table" then mark.sources = {} end
    if mark.expires ~= nil and type(mark.expires) ~= "number" then mark.expires = nil end
    return true
end

local function Prune()
    local db, now = ns.db, ns.Now()
    for id, kill in pairs(db.kills) do
        if not ValidKill(kill) or now - kill.at > KEEP_KILLS_DAYS * 86400 then
            db.kills[id] = nil
        end
    end
    -- Revenge's own Wanted marks never expire; broken ones go, and other addons' lapsed ones.
    for id, mark in pairs(db.wanted) do
        if not ValidMark(mark) or (mark.expires and mark.expires <= now) then db.wanted[id] = nil end
    end
    for pair, at in pairs(db.withdrawals) do
        if type(at) ~= "number" or now - at > KEEP_WITHDRAWALS_DAYS * 86400 then db.withdrawals[pair] = nil end
    end
    for id, stone in pairs(db.tombstones) do
        if type(stone) ~= "table" or type(stone.at) ~= "number" or type(stone.killers) ~= "table"
            or now - stone.at > KEEP_TOMBSTONES_DAYS * 86400 then
            db.tombstones[id] = nil
        end
    end
    -- Data known only from other addons has its own cap, so it can't crowd out Revenge's.
    local foreignKills, foreignMarks = {}, {}
    for id, kill in pairs(db.kills) do
        if not kill.own then foreignKills[#foreignKills + 1] = { id = id, at = kill.at } end
    end
    for id, mark in pairs(db.wanted) do
        if not mark.own then foreignMarks[#foreignMarks + 1] = { id = id, at = mark.at } end
    end
    local function Newest(a, b) return a.at > b.at end
    if #foreignKills > MAX_FOREIGN_KILLS then
        table.sort(foreignKills, Newest)
        for i = MAX_FOREIGN_KILLS + 1, #foreignKills do db.kills[foreignKills[i].id] = nil end
    end
    if #foreignMarks > MAX_FOREIGN_MARKS then
        table.sort(foreignMarks, Newest)
        for i = MAX_FOREIGN_MARKS + 1, #foreignMarks do db.wanted[foreignMarks[i].id] = nil end
    end
    -- Name cache: keep the most recently seen.
    local entries = {}
    for guid, info in pairs(db.names) do
        if type(info) == "table" and type(info.t) == "number" then
            entries[#entries + 1] = { guid = guid, t = info.t }
        else
            db.names[guid] = nil
        end
    end
    if #entries > MAX_NAMES then
        table.sort(entries, function(a, b) return a.t > b.t end)
        for i = MAX_NAMES + 1, #entries do db.names[entries[i].guid] = nil end
    end
end

function Store.Init()
    if type(RevengeTrackerDB) ~= "table" then RevengeTrackerDB = {} end
    local db = RevengeTrackerDB
    ns.db = db
    db.version = db.version or SCHEMA_VERSION
    for _, key in ipairs({ "settings", "kills", "wanted", "withdrawals", "names", "tombstones" }) do
        if type(db[key]) ~= "table" then db[key] = {} end
    end
    db.nextId = type(db.nextId) == "number" and db.nextId or 1
    if type(db.lastSeen) ~= "number" then db.lastSeen = nil end
    -- Default only missing or invalid values; a saved false is intentional.
    for key, default in pairs(Store.DEFAULTS) do
        if db.settings[key] == nil or not ValidSetting(key, db.settings[key]) then
            db.settings[key] = default
        end
    end
    -- Future schema migrations go here, keyed on db.version.
    db.version = SCHEMA_VERSION
    Prune()
    Store.RebuildIndexes()
end

function Store.Setting(key)
    return ns.db.settings[key]
end

function Store.NewId(prefix)
    local id = prefix .. ns.db.nextId
    ns.db.nextId = ns.db.nextId + 1
    return id
end

function Store.AddKill(kill)
    ns.db.kills[kill.id] = kill
    IndexKill(kill)
end

-- Call after changing a stored kill's killers (merge, identity upgrade).
function Store.Reindex(kill)
    IndexKill(kill)  -- duplicates in the index are harmless; lookups dedupe by id
end

function Store.GetKill(id)
    return ns.db.kills[id]
end

local function Collect(ids, seen, out)
    if not ids then return end
    for _, id in ipairs(ids) do
        local kill = ns.db.kills[id]
        if kill and not seen[id] then
            seen[id] = true
            out[#out + 1] = kill
        end
    end
end

-- Kills whose killers include this GUID or name key, newest first.
function Store.KillsByKiller(guid, key)
    local seen, out = {}, {}
    if guid then Collect(byKillerGuid[guid], seen, out) end
    if key then Collect(byKillerKey[key], seen, out) end
    table.sort(out, function(a, b) return a.at > b.at end)
    return out
end

function Store.KillsByVictim(key)
    local seen, out = {}, {}
    Collect(byVictimKey[key], seen, out)
    return out
end

function Store.AllKills()
    return ns.db.kills
end

-- Records that these killers were dismissed from this kill (all: the whole kill).
local function Tombstone(kill, killers, all)
    local stone = ns.db.tombstones[kill.id]
    if not stone then
        stone = { victim = kill.victim.key, killers = {}, at = kill.at }
        ns.db.tombstones[kill.id] = stone
    end
    for _, killer in ipairs(killers) do
        table.insert(stone.killers, { key = killer.key, guid = killer.guid, partial = killer.partial })
    end
    if all then stone.all = true end
end

-- Dismisses a kill everywhere and keeps a tombstone so no source can bring it back.
function Store.Dismiss(id)
    local kill = ns.db.kills[id]
    if not kill then return end
    Tombstone(kill, kill.killers, true)
    ns.db.kills[id] = nil
    Store.RebuildIndexes()
end

-- Removes one player from a kill's killers, with a tombstone so no source adds them
-- back to this death. A kill left with no killers is deleted. Returns true if removed.
-- Call RebuildIndexes when done.
function Store.RemoveKiller(kill, identity)
    local removed = {}
    for i = #kill.killers, 1, -1 do
        if ns.Identity.Same(kill.killers[i], identity) then
            removed[#removed + 1] = table.remove(kill.killers, i)
        end
    end
    if #removed == 0 then return false end
    Tombstone(kill, removed, false)
    if #kill.killers == 0 then ns.db.kills[kill.id] = nil end
    return true
end

function Store.Tombstones()
    return ns.db.tombstones
end

function Store.RemoveTestKills()
    local removed = 0
    for id, kill in pairs(ns.db.kills) do
        if kill.test then
            ns.db.kills[id] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then Store.RebuildIndexes() end
    return removed
end

---------------------------------------------------------------------------
-- Wanted marks
---------------------------------------------------------------------------
function Store.AddWanted(mark)
    ns.db.wanted[mark.id] = mark
    IndexMark(mark)
end

function Store.ReindexWanted(mark)
    IndexMark(mark)
end

function Store.AllWanted()
    return ns.db.wanted
end

-- Marks on this GUID or name key (hidden ones included), newest first.
function Store.WantedFor(guid, key)
    local seen, out = {}, {}
    local function Add(ids)
        if not ids then return end
        for _, id in ipairs(ids) do
            local mark = ns.db.wanted[id]
            if mark and not seen[id] then
                seen[id] = true
                out[#out + 1] = mark
            end
        end
    end
    if guid then Add(byTargetGuid[guid]) end
    if key then Add(byTargetKey[key]) end
    table.sort(out, function(a, b) return a.at > b.at end)
    return out
end

function Store.RemoveWanted(id)
    if not ns.db.wanted[id] then return end
    ns.db.wanted[id] = nil
    Store.RebuildIndexes()
end

function Store.Withdrawal(pair)
    return ns.db.withdrawals[pair]
end

function Store.SetWithdrawal(pair, at)
    local previous = ns.db.withdrawals[pair]
    if not previous or at > previous then ns.db.withdrawals[pair] = at end
end

function Store.ClearWithdrawal(pair)
    ns.db.withdrawals[pair] = nil
end

-- Whether data known only from other addons shows: not while their use is switched off.
local function ForeignShown(record)
    return record.own or Store.Setting("otherAddons") == true
end

-- Whether a kill is recent enough to show (and, if only other addons reported it,
-- whether their data is in use).
function Store.IsRecent(kill, now)
    return (now or ns.Now()) - kill.at <= Store.Setting("expiryDays") * 86400 and ForeignShown(kill)
end

-- Whether a Wanted mark shows: not hidden by you, not lapsed, and not only from other
-- addons while those are switched off.
function Store.MarkShown(mark, now)
    if mark.hidden or (mark.expires and mark.expires <= (now or ns.Now())) then return false end
    return ForeignShown(mark) and true or false
end
