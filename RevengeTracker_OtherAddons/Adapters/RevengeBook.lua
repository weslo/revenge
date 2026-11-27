-- Revenge Book (folder DeathNote, prefix "DeathNote"; REQ-026): guildmates' deaths and
-- Wanted players from its guild messages, and the books in your own Revenge Book when
-- you run it too. Read-only and listen-only. Format as read from Revenge Book's source
-- at 01ef1c1 (v1.7.1, 2026-11-26), described in our own words:
--
--   messages  1 <TAB> type <TAB> fields...   (each type has an exact field count)
--             control bytes, "%" and "|" are escaped as %XX; numbers are decimal;
--             times are the sender's clock (time())
--   K, R      key display class level zone t victim   (K live, R in a catch-up answer)
--             key "First-Surname" is the killer; when their surname is unknown the
--             second part is a realm and display is the first name alone; the
--             victim is always the sender
--   L         key t victim mapID x y      (where that death was; x, y in tenths of a percent)
--   M         key display class level t by   (the sender marked a player Wanted by hand)
--   X         key by                      (the sender took that mark back)
-- Everything else (hit lists, bounties, sightings, hellos, ...) is ignored. Friends'
-- whispers and Battle.net data need Revenge Book's own hello, so they're never seen
-- here; they reach you through your own Revenge Book's saved data instead.
local _, mod = ...

local FIELDS = { K = 9, R = 9, L = 8, M = 8, X = 4 }
local LIVE_FOR = 300
local MAX_AGE = 30 * 86400
local SLICE = 20
local MAX_KEYS = 1500

local function Unescape(field)
    local _, percents = field:gsub("%%", "")
    local decoded, escapes = field:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    if escapes ~= percents then return nil end
    if #decoded > 64 or decoded:find("[%c|]") then return nil end
    return decoded
end

-- The killer from key and display: "Gorvak Ashmane", or "Gorvak" alone when the
-- key's second part is only a realm.
local function Killer(key, display, class, level)
    if not key:match("^[^%-]+%-[^%-]+$") or #key < 3 or #key > 64 then return nil end
    local name
    local first, second = key:match("^([^%-]+)%-(.+)$")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if second == "?" or (realm and second == realm) then
        name = mod.Name(first)    -- the surname is unknown: the key ends in a realm
    elseif display ~= "" and not display:find(" ", 1, true) then
        name = mod.Name(display)
        if not (name and mod.SameName(name, key:match("^([^%-]+)"))) then return nil end
    else
        name = mod.Name(key)
    end
    if not name then return nil end
    return {
        name = name,
        class = class ~= "" and class:match("^%u+$") or nil,
        level = mod.Int(level, 1, 100),
    }
end

local function Time(text)
    return mod.Int(text, 1000000000, 4000000000)
end

local handlers = {}

local function KillMessage(f, live, now)
    local killer = Killer(f[3], f[4], f[5], f[6])
    local at, victim = Time(f[8]), mod.Name(f[9])
    if not (killer and at and victim) then return nil end
    return { {
        type = "kill",
        victim = { name = victim },
        killers = { killer },
        at = at,
        precision = "client",
        zone = f[7] ~= "" and f[7] or nil,
        live = live and now - at < LIVE_FOR,
    } }
end

function handlers.K(f, now) return KillMessage(f, true, now) end
function handlers.R(f, now) return KillMessage(f, false, now) end

-- Where a death happened: the same death as its K or R (same victim, killer and
-- time), so it merges into that kill.
function handlers.L(f)
    local killer = Killer(f[3], "", "", "")
    local at, victim = Time(f[4]), mod.Name(f[5])
    local mapID, x, y = mod.Int(f[6], 1, 100000), mod.Int(f[7], 0, 1000), mod.Int(f[8], 0, 1000)
    if not (killer and at and victim and mapID and x and y) then return nil end
    return { {
        type = "kill",
        victim = { name = victim },
        killers = { killer },
        at = at,
        precision = "client",
        mapID = mapID,
        x = x / 1000,
        y = y / 1000,
    } }
end

function handlers.M(f)
    local target = Killer(f[3], f[4], f[5], f[6])
    local at, by = Time(f[7]), mod.Name(f[8])
    if not (target and at and by) then return nil end
    return { { type = "wanted", target = target, by = { name = by }, at = at } }
end

function handlers.X(f, now)
    local target, by = Killer(f[3], "", "", ""), mod.Name(f[4])
    if not (target and by) then return nil end
    -- No time is sent: it's taken back as of now, which beats every earlier copy.
    return { { type = "withdrawal", target = target, by = { name = by }, at = now } }
end

local function Decode(_, text)
    local raw = mod.Split(text, "\t", 10)
    if not raw or raw[1] ~= "1" then return nil end
    local kind = raw[2]
    local count = FIELDS[kind]
    if not count then return {} end
    if #raw ~= count then return nil end
    local f = {}
    for i, field in ipairs(raw) do
        f[i] = Unescape(field)
        if not f[i] then return nil end
    end
    return handlers[kind](f, GetServerTime())
end

---------------------------------------------------------------------------
-- Saved data: your own book, your guild's book and your friends' book
---------------------------------------------------------------------------
local function Percent(value)
    return type(value) == "number" and value >= 0 and value <= 100 and value / 100 or nil
end

local function EntryKiller(key, entry)
    local name = mod.Name(entry.display) or mod.Name(key)
    if not name then return nil end
    return { name = name, guid = entry.guid, class = entry.class, level = entry.level }
end

local function Keys(book)
    if type(book) ~= "table" then return nil end
    local keys = {}
    for key in pairs(book) do
        if type(key) ~= "string" then return nil end
        keys[#keys + 1] = key
        if #keys >= MAX_KEYS then break end
    end
    return keys
end

local function Death(killer, victim, deed, fp)
    return {
        type = "kill",
        victim = { name = victim },
        killers = { killer },
        at = deed.t,
        precision = "client",
        zone = type(deed.zone) == "string" and deed.zone ~= "" and deed.zone or nil,
        mapID = deed.mapID,
        x = Percent(deed.x),
        y = Percent(deed.y),
        fp = fp,
    }
end

-- One book: { [key] = entry }, where an entry's deaths are in `deedsField` and the
-- victim's name in each deed's `victimField`. Own hand entries become Wanted marks by
-- you, and guildmates' and friends' marks (listedBy) Wanted marks by them.
local function ReadBook(book, deedsField, victimField, emit, pause, since, me)
    local keys = Keys(book)
    if not keys then return false end
    for i, key in ipairs(keys) do
        local entry = book[key]
        if entry ~= nil then
            if type(entry) ~= "table" then return false end
            local killer = EntryKiller(key, entry)
            local deeds = entry[deedsField]
            if killer and type(deeds) == "table" then
                for _, deed in ipairs(deeds) do
                    if type(deed) ~= "table" then return false end
                    local victim = mod.Name(deed[victimField])
                    local counts = deedsField ~= "deaths" or (deed.role == "kill" and deed.sure == true)
                    if victim and counts and not deed.imported and type(deed.t) == "number" and deed.t >= since then
                        if not emit(Death(killer, victim, deed, "k:" .. key .. "|" .. deed.t .. "|" .. victim)) then
                            return true
                        end
                    end
                end
            end
            if killer and entry.manual and entry.status == "wanted" and type(entry.listedAt) == "number"
                and mod.Name(entry.by) == me then
                if not emit({ type = "wanted", target = killer, by = { name = me }, at = entry.listedAt,
                              fp = "m:" .. key .. "|" .. entry.listedAt }) then
                    return true
                end
            end
            if killer and type(entry.listedBy) == "table" then
                for by, at in pairs(entry.listedBy) do
                    local adder = mod.Name(by)
                    if adder and type(at) == "number" then
                        if not emit({ type = "wanted", target = killer, by = { name = adder }, at = at,
                                      fp = "l:" .. key .. "|" .. adder .. "|" .. at }) then
                            return true
                        end
                    end
                end
            end
        end
        if i % SLICE == 0 then pause() end
    end
    return true
end

local function Import(emit, pause)
    local db = _G.DeathNoteDB
    if type(db) ~= "table" then return false end
    local core = mod.Core()
    local me = core and mod.Name(core.SelfName())
    if not me then return true end
    local since = GetServerTime() - MAX_AGE
    if db.enemies ~= nil and not ReadBook(db.enemies, "deaths", "me", emit, pause, since, me) then return false end
    local guild = GetGuildInfo and GetGuildInfo("player")
    local lists = type(db.guild) == "table" and db.guild.lists
    if type(guild) == "string" and type(lists) == "table" and type(lists[guild]) == "table" then
        if not ReadBook(lists[guild].enemies, "deeds", "victim", emit, pause, since, me) then return false end
    end
    if type(db.friends) == "table" and db.friends.enemies ~= nil then
        if not ReadBook(db.friends.enemies, "deeds", "victim", emit, pause, since, me) then return false end
    end
    return true
end

mod.Register({
    id = "revengebook",
    prefixes = { "DeathNote" },
    channels = { GUILD = true },
    addons = { "DeathNote" },
    Decode = Decode,
    Import = Import,
})
