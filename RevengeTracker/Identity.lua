-- Identity: who a player is, as a stable key, and a cache that learns full names.
--
-- An identity is { name = "First Last", key = "first last", guid = "Player-...",
--   class = "ROGUE", level = 41, guild = "Bloodfang Raiders", faction = "Horde",
--   partial = true when only the first name is known }.
--
-- Forever's death recap gives only an enemy's first name, so full names come from
-- the cache, filled from nameplates, the target and the mouseover.
local _, ns = ...

local Identity = ns.RegisterModule("Identity", {})
local Try, AccessibleString, AccessibleNumber = ns.Try, ns.AccessibleString, ns.AccessibleNumber

-- "  Gorvak-Ashmane " / "gorvak  ashmane" -> "gorvak ashmane"
function Identity.Key(name)
    if type(name) ~= "string" then return nil end
    local key = name:gsub("%-", " "):gsub("%s+", " "):match("^%s*(.-)%s*$"):lower()
    if key == "" then return nil end
    return key
end

local function FirstWord(key)
    return key and key:match("^(%S+)")
end

local function IsFullName(name)
    return type(name) == "string" and name:find("%s") ~= nil
end

-- Full name of a unit ("First Last" on Forever), or nil.
local function UnitFullNameText(unit)
    local first, second = Try(UnitFullName, unit)
    first, second = AccessibleString(first), AccessibleString(second)
    if first and second and Try(RegionalUniqueNamesEnabled) then
        return first .. " " .. second
    end
    local full = AccessibleString(Try(GetUnitName, unit, true))
    if full then return (full:gsub("%-", " ")) end
    return first
end

function Identity.Make(name, guid)
    local key = Identity.Key(name)
    if not key and not guid then return nil end
    return { name = name, key = key, guid = guid, partial = not IsFullName(name) or nil }
end

-- Identity of a player unit right now, or nil (not a player, or hidden).
function Identity.FromUnit(unit)
    if not Try(UnitIsPlayer, unit) then return nil end
    local name = UnitFullNameText(unit)
    local guid = AccessibleString(Try(UnitGUID, unit))
    local identity = Identity.Make(name, guid)
    if not identity then return nil end
    local _, classFile = Try(UnitClass, unit)
    identity.class = AccessibleString(classFile)
    local level = AccessibleNumber(Try(UnitLevel, unit))
    identity.level = level and level > 0 and level or nil
    identity.guild = AccessibleString(Try(GetGuildInfo, unit))
    identity.faction = AccessibleString(Try(UnitFactionGroup, unit))
    return identity
end

function Identity.Self()
    if not Identity.self then Identity.self = Identity.FromUnit("player") end
    return Identity.self
end

function Identity.IsSelf(identity)
    local me = Identity.Self()
    if not (me and identity) then return false end
    if me.guid and identity.guid then return me.guid == identity.guid end
    return me.key ~= nil and me.key == identity.key
end

---------------------------------------------------------------------------
-- Name cache
---------------------------------------------------------------------------
-- Remembers what a seen player looks like; upgrades stored partial identities.
-- Nameplates appear often in busy places, so a player seen in the last 30 seconds
-- is skipped, and entries are updated in place.
local OBSERVE_INTERVAL = 30

local function Observe(unit)
    if not Try(UnitIsPlayer, unit) then return end
    local guid = AccessibleString(Try(UnitGUID, unit))
    if not guid then return end
    local names, now = ns.db.names, ns.Now()
    local entry = names[guid]
    if entry and now - entry.t < OBSERVE_INTERVAL and IsFullName(entry.n) then return end
    local identity = Identity.FromUnit(unit)
    if not (identity and identity.name) then return end
    local learnedFullName = IsFullName(identity.name) and not (entry and IsFullName(entry.n))
    if not entry then
        entry = {}
        names[guid] = entry
    end
    entry.n = identity.name
    entry.c = identity.class or entry.c
    entry.l = identity.level or entry.l
    entry.g = identity.guild or entry.g
    entry.f = identity.faction or entry.f
    entry.t = now
    if learnedFullName then ns.Merge.UpgradeIdentity(guid, Identity.Key(identity.name)) end
end

-- A cached player by name key: their GUID and cache entry, or nil. Scans the whole
-- cache, so it's for user actions like Add by name, not for every frame.
function Identity.FindByName(key)
    if not key then return nil end
    for guid, entry in pairs(ns.db.names) do
        if type(entry) == "table" and Identity.Key(entry.n) == key then return guid, entry end
    end
end

function Identity.Copy(identity)
    local copy = {}
    for field, value in pairs(identity) do copy[field] = value end
    return copy
end

-- Fills in an identity from the cache and GetPlayerInfoByGUID.
function Identity.Resolve(identity)
    if not identity then return nil end
    local guid = identity.guid
    if guid then
        local cached = ns.db.names[guid]
        if cached then
            if identity.partial and IsFullName(cached.n) then
                identity.name, identity.key, identity.partial = cached.n, Identity.Key(cached.n), nil
            end
            identity.class = identity.class or cached.c
            identity.level = identity.level or cached.l
            identity.guild = identity.guild or cached.g
            identity.faction = identity.faction or cached.f
        end
        if not identity.class or not identity.level then
            local _, classFile, _, _, _, name, _, level = Try(GetPlayerInfoByGUID, guid)
            identity.class = identity.class or AccessibleString(classFile)
            level = AccessibleNumber(level)
            identity.level = identity.level or (level and level > 0 and level) or nil
            if not identity.name then
                identity.name = AccessibleString(name)
                identity.key = Identity.Key(identity.name)
                identity.partial = not IsFullName(identity.name) or nil
            end
        end
    end
    return identity
end

-- Whether two identities are the same player. A first name alone matches a full
-- name only when they share it and no GUIDs disagree.
function Identity.Same(a, b)
    if not (a and b) then return false end
    if a.guid and b.guid then return a.guid == b.guid end
    if not (a.key and b.key) then return false end
    if a.key == b.key then return true end
    if a.partial or b.partial then return FirstWord(a.key) == FirstWord(b.key) end
    return false
end

-- Whether the name the game gives a message's sender fits a player's name key. The game
-- gives "Name", "Name-Realm", "Name-Surname" or "Name Surname": the first name must
-- match, and a surname too when the game gives one after a space.
function Identity.SenderIs(sender, key)
    if type(sender) ~= "string" or type(key) ~= "string" then return false end
    local name = AccessibleString(Try(Ambiguate, sender, "none")) or sender
    local first, rest = name:match("^(%S+)%s+(.+)$")
    if first then
        return Identity.Key(first .. " " .. (rest:match("^([^%-]+)") or rest)) == key
    end
    return Identity.Key(name:match("^([^%-]+)") or name) == key:match("^(%S+)")
end

-- Short display name: the first name, or "You".
function Identity.ShortName(identity)
    if Identity.IsSelf(identity) then return ns.L.YOU end
    local name = identity.name or "?"
    return name:match("^(%S+)") or name
end

-- Whose this is: "you", "guild", "friend" (in-game or Battle.net), or nil.
function Identity.Group(identity)
    if not identity then return nil end
    if Identity.IsSelf(identity) then return "you" end
    local guid = identity.guid
    if not guid then return nil end
    if Try(IsGuildMember, guid) then return "guild" end
    if C_FriendList and Try(C_FriendList.IsFriend, guid) then return "friend" end
    if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID
        and type(ns.Accessible(Try(C_BattleNet.GetGameAccountInfoByGUID, guid))) == "table" then
        return "friend"
    end
    return nil
end

-- Full display name with "(friend)" or "(guild)", or "You".
function Identity.LongName(identity)
    local group = Identity.Group(identity)
    if group == "you" then return ns.L.YOU end
    local name = identity.name or "?"
    if group == "guild" then return ns.L.AS_GUILD:format(name) end
    if group == "friend" then return ns.L.AS_FRIEND:format(name) end
    return name
end

function Identity:OnLogin()
    Identity.self = nil
    Identity.Self()
    ns.On("PLAYER_TARGET_CHANGED", function() Observe("target") end)
    ns.On("UPDATE_MOUSEOVER_UNIT", function() Observe("mouseover") end)
    ns.On("NAME_PLATE_UNIT_ADDED", function(unit) Observe(unit) end)
end
