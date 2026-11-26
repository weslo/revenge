-- Store: saved data (account-wide), its defaults and migrations, and lookup indexes.
--
-- RevengeTrackerDB = {
--   version  = schema version,
--   settings = { see DEFAULTS },
--   kills    = { [id] = kill },      -- see Merge.lua for a kill's fields
--   wanted   = { [id] = mark },      -- Wanted marks (added in a later slice)
--   names    = { [guid] = { n = "First Last", c = classFile, l = level, g = guild, f = faction, t = seen } },
--   tombstones = { [id] = { victim = key, killers = { key... }, at = time } },  -- dismissed kills
--   nextId   = counter,
-- }
local _, ns = ...

local Store = {}
ns.Store = Store

local SCHEMA_VERSION = 1
local KEEP_KILLS_DAYS = 60          -- history kept beyond the display expiry
local MAX_NAMES = 2000              -- name cache size
local KEEP_TOMBSTONES_DAYS = 90

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

function Store.RebuildIndexes()
    wipe(byKillerGuid)
    wipe(byKillerKey)
    wipe(byVictimKey)
    for _, kill in pairs(ns.db.kills) do IndexKill(kill) end
end

local function Prune()
    local db, now = ns.db, ns.Now()
    for id, kill in pairs(db.kills) do
        if type(kill) ~= "table" or type(kill.at) ~= "number" or now - kill.at > KEEP_KILLS_DAYS * 86400 then
            db.kills[id] = nil
        end
    end
    for id, stone in pairs(db.tombstones) do
        if type(stone) ~= "table" or type(stone.at) ~= "number" or now - stone.at > KEEP_TOMBSTONES_DAYS * 86400 then
            db.tombstones[id] = nil
        end
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
    for _, key in ipairs({ "settings", "kills", "wanted", "names", "tombstones" }) do
        if type(db[key]) ~= "table" then db[key] = {} end
    end
    db.nextId = type(db.nextId) == "number" and db.nextId or 1
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

-- Dismisses a kill everywhere and keeps a tombstone so no source can bring it back.
function Store.Dismiss(id)
    local kill = ns.db.kills[id]
    if not kill then return end
    local keys = {}
    for i, killer in ipairs(kill.killers) do keys[i] = killer.key end
    ns.db.tombstones[id] = { victim = kill.victim.key, killers = keys, at = kill.at }
    ns.db.kills[id] = nil
    Store.RebuildIndexes()
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

-- Whether a kill is recent enough to show.
function Store.IsRecent(kill, now)
    return (now or ns.Now()) - kill.at <= Store.Setting("expiryDays") * 86400
end
