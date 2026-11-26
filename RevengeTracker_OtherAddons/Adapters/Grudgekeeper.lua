-- Grudgekeeper (prefix "Grudgekeeper", guild only; REQ-027): guildmates' deaths and
-- kill orders. Read-only and listen-only. Format as read from Grudgekeeper's source at
-- ba6a723 (v1.13.1, 2026-11-26), described in our own words:
--
--   messages  type;1;fields...   (";" inside a field is never sent; new fields are
--             only ever added at the end, so missing or extra trailing fields are fine)
--   D         killer;class;race;level;zone;times;raceFile;sex;guild
--             the sender just died; no time, so it's stamped on arrival
--   G         D;killer;class;race;level;zone;t;guild;times;points
--             one of the sender's own earlier deaths, in a catch-up answer (t: their clock)
--   C         id;target;class;race;level;guid;reward;created;expires;state;doneBy;note;...
--             the sender's own kill order: state o (open) is "Wanted by" the sender
--             until it expires; d, p, x and e (fulfilled, paid, withdrawn, expired)
--             end it. Each C is the order as it stands, repeated in every catch-up
--             answer, so it's treated as state: ending one isn't remembered.
--   O, F, K and the rest are someone else's data or not deaths, and are ignored.
--
-- Long messages are split by AceComm: "\001" first part, "\002" middle, "\003" last,
-- per sender. "\004" escapes a message that starts with a control byte.
local _, mod = ...

local MAX_TEXT = 600            -- Grudgekeeper's own limit after joining parts
local SPOOL_FOR = 30            -- seconds an unfinished split message waits
local LIVE_FOR = 300

local spools = {}               -- sender -> { parts, at }

-- "Gorvak Ashmane"; an older client's "Gorvak-Realm" loses the realm.
local function PlayerName(text)
    if type(text) ~= "string" then return nil end
    if not text:find(" ", 1, true) then
        local first, tail = text:match("^(.-)%-([^%-]+)$")
        if first then
            local realm = GetRealmName and (GetRealmName() or ""):gsub("%s", "") or ""
            if tail:find("%d") or tail == "PvP" or tail == "PvE" or tail == realm then text = first end
        end
    end
    return mod.Name(text)
end

local function Class(text)
    return type(text) == "string" and text:match("^%u+$") and #text <= 12 and text or nil
end

local function Level(text)
    return mod.Int(text, 1, 100)
end

local function Kill(victim, killer, class, level, zone, at, precision, live)
    if not (victim and killer) then return nil end
    return {
        type = "kill",
        victim = { name = victim },
        killers = { { name = killer, class = Class(class), level = Level(level) } },
        at = at,
        precision = precision,
        zone = zone ~= "" and zone or nil,
        live = live,
    }
end

local handlers = {}

function handlers.D(f, sender, now)
    local record = Kill(PlayerName(sender), PlayerName(f[3]), f[4], f[6], f[7], now, "received", true)
    return record and { record } or nil
end

function handlers.G(f, sender, now)
    if f[3] ~= "D" then return {} end
    local at = mod.Int(f[9], 1000000000, 4000000000)
    if not at then return nil end
    local record = Kill(PlayerName(sender), PlayerName(f[4]), f[5], f[7], f[8], at, "client", now - at < LIVE_FOR)
    return record and { record } or nil
end

local STATES = { o = true, d = true, p = true, x = true, e = true }

function handlers.C(f, sender, now)
    local target = PlayerName(f[4])
    local created = mod.Int(f[10], 1000000000, 4000000000)
    local expires = mod.Int(f[11], 1000000000, 4000000000)
    local state = f[12]
    local by = PlayerName(sender)
    if not (target and created and expires and by and STATES[state]) then return nil end
    local guid = f[8] ~= "" and f[8]:match("^Player%-%d+%-%x+$") and f[8] or nil
    local open = state == "o" and expires > now
    -- Ending an order ends the mark from it (made at its creation), not later orders'.
    -- Every C is the order as it stands now, so nothing is remembered: the poster can
    -- post it again. An open order's mark lapses when the order would expire.
    return { {
        type = open and "wanted" or "withdrawal",
        target = { name = target, guid = guid, class = Class(f[5]), level = Level(f[7]) },
        by = { name = by },
        at = created,
        expires = open and expires or nil,
        remember = false,
    } }
end

-- Joins AceComm's parts. Returns the whole text, or nil while parts are missing.
local function Unsplit(text, sender, now)
    local lead = text:byte(1)
    if lead == 1 then
        spools[sender] = { parts = { text:sub(2) }, size = #text - 1, at = now }
        return nil
    elseif lead == 2 or lead == 3 then
        local spool = spools[sender]
        if not spool or now - spool.at > SPOOL_FOR then
            spools[sender] = nil
            return nil
        end
        spool.parts[#spool.parts + 1] = text:sub(2)
        spool.size = spool.size + #text - 1
        if spool.size > MAX_TEXT then
            spools[sender] = nil
            return nil
        end
        if lead == 2 then return nil end
        spools[sender] = nil
        return table.concat(spool.parts)
    elseif lead == 4 then
        return text:sub(2)
    elseif lead and lead <= 9 then
        return false
    end
    return text
end

local function Decode(_, text, _, sender)
    local now = GetServerTime()
    local whole = Unsplit(text, sender, now)
    if whole == nil or whole == false then return {} end
    if #whole > MAX_TEXT then return nil end
    local f = mod.Split(whole, ";", 40)
    if not f or #f < 2 or not f[1]:match("^%u$") then return nil end
    if f[2] ~= "1" then return nil end
    local handler = handlers[f[1]]
    if not handler then return {} end
    return handler(f, sender, now)
end

mod.Register({
    id = "grudgekeeper",
    prefixes = { "Grudgekeeper" },
    channels = { GUILD = true },
    addons = { "Grudgekeeper" },
    Decode = Decode,
})
