-- HeadHunter (prefix "HeadHunter"; REQ-028): deaths that guildmates and friends in
-- your group report, and HeadHunter's record of your own deaths while it's loaded.
-- Read-only and listen-only. Format as read from HeadHunter's source at 33130c0
-- (2026-11-26); its data format is described here in our own words:
--
--   message   "1" <A|H> <type> ":" record ("~" record)*        (one type per message)
--   D record  t;victim;level;class;race;mapID;x;y;confidence;layer;killer[;assist]*[;h<n>]
--             numbers in base 36 (0-9a-z); x and y in thousandths; confidence e, i or
--             s (a simulated test death, ignored); class and race as one-letter codes
--   enemy     name,incomplete,level,class,race,sex,guid
--             incomplete "1": first name only, with the full GUID; level "s": skull
--   E record  world;author;faction;server;hops;at;<type><record>  (gossip, by whisper)
--
-- Only the sender's own deaths count (DEC-021): a plain D by party or raid, or an E at
-- hop 1 whispered by its author. Relayed copies (hop 2 and up), catch-up data, bridged
-- envelopes on group channels and every other type are ignored.
local _, mod = ...

local CLASSES = { W = "WARRIOR", P = "PALADIN", H = "HUNTER", R = "ROGUE", I = "PRIEST", S = "SHAMAN",
                  M = "MAGE", L = "WARLOCK", D = "DRUID" }
local MAX_RECORDS = 12
local LIVE_FOR = 300            -- a death this recent alerts like a guildmate's own
local IMPORT_NEWEST = 200
local SLICE = 25

local function Base36(text, low, high)
    if type(text) ~= "string" or not text:match("^[0-9a-z]+$") or #text > 10 then return nil end
    return mod.Int(text, low, high, 36)
end

local function Enemy(text)
    local f = mod.Split(text, ",", 8)
    if not f or #f ~= 7 then return nil end
    local name = mod.Name(f[1])
    if not name then return nil end
    local guid = f[7] ~= "" and f[7]:match("^Player%-%d+%-%x+$") and f[7] or nil
    local incomplete = f[2] == "1"
    if incomplete and not guid then return nil end
    if incomplete then name = name:match("^(%S+)") end
    return {
        name = name,
        guid = guid,
        level = f[3] ~= "s" and Base36(f[3], 1, 100) or nil,
        class = CLASSES[f[4]],
    }
end

-- A D record as a kill, false for a simulated one, or nil if it doesn't parse.
local function Death(text, now)
    local f = mod.Split(text, ";", 20)
    if not f or #f < 11 then return nil end
    if #f > 11 and f[#f]:match("^h%w+$") then table.remove(f) end
    local at = Base36(f[1], 1000000000, 4000000000)
    local victim = mod.Name(f[2])
    if not (at and victim) then return nil end
    if f[9] == "s" then return false end
    local killers = { Enemy(f[11]) }
    if not killers[1] then return nil end
    for i = 12, math.min(#f, 15) do
        local assist = Enemy(f[i])
        if assist then killers[#killers + 1] = assist end
    end
    local x, y = Base36(f[7], 0, 999), Base36(f[8], 0, 999)
    return {
        type = "kill",
        victim = { name = victim, level = Base36(f[3], 1, 100), class = CLASSES[f[4]] },
        killers = killers,
        at = at,
        precision = "client",
        mapID = Base36(f[6], 1, 100000),
        x = x and y and x / 1000 or nil,
        y = x and y and y / 1000 or nil,
        live = now - at < LIVE_FOR,
    }
end

local ENVELOPE = "^([^;]*);([^;]*);([AH]);([^;]*);([^;]*);([^;]*);(%u)(.*)$"

local function Decode(_, text, channel, sender)
    local version, _, kind, body = text:match("^(%d)([AH])(%u):(.*)$")
    if not version then return nil end
    if version ~= "1" then return nil end
    if kind ~= "D" and kind ~= "E" then return {} end
    local parts = mod.Split(body, "~", MAX_RECORDS)
    if not parts then return nil end
    local now = GetServerTime()
    local records, bad = {}, 0
    for _, part in ipairs(parts) do
        local death
        if kind == "D" and channel ~= "WHISPER" then
            death = Death(part, now)
        elseif kind == "E" and channel == "WHISPER" then
            local _, author, _, _, hops, _, inner, record = part:match(ENVELOPE)
            if not author then
                death = nil
            elseif inner == "D" and hops == "1" and mod.SameName(author, sender) then
                death = Death(record, now)
            else
                death = false
            end
        else
            death = false
        end
        if death then
            records[#records + 1] = death
        elseif death == nil then
            bad = bad + 1
        end
    end
    if bad > 0 and #records == 0 then return nil end
    return records
end

-- Your own deaths, from HeadHunter's saved data for this home server: newest first.
local function Import(emit, pause)
    local db = _G.HeadHunter_DB
    if type(db) ~= "table" or type(db.meta) ~= "table" or type(db.homes) ~= "table" then return false end
    local home = db.homes[db.meta.home]
    if home == nil then return true end
    if type(home) ~= "table" or type(home.deaths) ~= "table" then return false end
    local deaths = home.deaths
    local newest = #deaths
    for i = newest, math.max(1, newest - IMPORT_NEWEST + 1), -1 do
        local d = deaths[i]
        if type(d) ~= "table" or type(d.victim) ~= "table" or type(d.killer) ~= "table" then return false end
        if d.origin == "local" and type(d.t) == "number" then
            local killers = {}
            for _, enemy in ipairs({ d.killer, unpack(type(d.assists) == "table" and d.assists or {}, 1, 4) }) do
                if type(enemy) == "table" then
                    local name = mod.Name(enemy.key or enemy.name)
                    if name and enemy.nameIncomplete then name = name:match("^(%S+)") end
                    if name then
                        killers[#killers + 1] = { name = name, guid = enemy.guid, class = enemy.class, level = enemy.level }
                    end
                end
            end
            if killers[1] then
                local more = emit({
                    type = "kill",
                    victim = { name = mod.Name(d.victim.key), class = d.victim.class, level = d.victim.level },
                    killers = killers,
                    at = d.t,
                    precision = "client",
                    mapID = d.mapID,
                    x = d.x,
                    y = d.y,
                    fp = "d:" .. tostring(d.id or d.t),
                })
                if not more then return true end
            end
        end
        if (newest - i + 1) % SLICE == 0 then pause() end
    end
    return true
end

mod.Register({
    id = "headhunter",
    prefixes = { "HeadHunter" },
    channels = { PARTY = true, RAID = true, WHISPER = true },
    addons = { "HeadHunter" },
    Decode = Decode,
    Import = Import,
})
