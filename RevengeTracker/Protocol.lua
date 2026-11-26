-- Protocol: Revenge's own addon messages (prefix RVNG1), encoded and decoded.
-- Pure functions with no game calls; Share.lua sends and receives them.
-- docs/plans/revenge/PROTOCOL.md describes the messages and the rules around them.
--
-- One message per addon message (at most 255 bytes), fields separated by TAB. Every
-- message starts with: type, the sender's full name, the sender's GUID without "Player-".
--   H  since version                                  hello: "send me what's newer than since"
--   K  id at map x y flags {name guid class level}... a death of the sender, just now
--   R  (as K)                                         the same, in an answer to a hello
--   M  at target targetGuid class level               the sender marked target Wanted
--   X  at target                                      the sender withdrew that mark
-- Empty fields mean "unknown". A message with any malformed field is dropped whole.
local _, ns = ...

local Protocol = ns.RegisterModule("Protocol", {})

Protocol.PREFIX = "RVNG1"
Protocol.MAX_BYTES = 255
Protocol.MAX_KILLERS = 5      -- per message

local SEP = "\t"
local MAX_NAME = 48
local MAX_FIELDS = 40

---------------------------------------------------------------------------
-- Field checks: each returns the value, or nil when malformed.
---------------------------------------------------------------------------
-- Player names: letters in any language, spaces, apostrophes and hyphens.
local function Name(s)
    if s == "" or #s > MAX_NAME or s:find("[^%a\128-\255 '%-]") then return nil end
    return s
end

-- "6930-008E2109" (a player GUID without "Player-"): digits, a hyphen, letters and digits.
local function Guid(s)
    if #s > 24 or not s:match("^%d+%-%w+$") then return nil end
    return "Player-" .. s
end

local function Class(s)
    if #s > 12 or not s:match("^%u+$") then return nil end
    return s
end

local function Int(low, high)
    return function(s)
        if #s > 10 or not s:match("^%d+$") then return nil end
        local n = tonumber(s)
        if n < low or n > high then return nil end
        return n
    end
end

local Time = Int(1, 4e9)
local Level = Int(1, 100)
local Map = Int(1, 999999)
local Coord = Int(0, 1000)

local function KillId(s)
    if #s > 12 or not s:match("^k%d+$") then return nil end
    return s
end

local function Flags(s)
    if #s > 4 or s:find("[^a-z]") then return nil end
    return s
end

local function Version(s)
    if #s > 24 or s:find("[%c|]") then return nil end
    return s
end

-- Reads field i with check; empty fields are allowed when optional.
-- Returns ok, value.
local function Read(fields, i, check, optional)
    local s = fields[i]
    if s == nil then return false end
    if s == "" then return optional == true, nil end
    local value = check(s)
    return value ~= nil, value
end

local function Split(text)
    local fields, start = {}, 1
    while true do
        local i = text:find(SEP, start, true)
        if not i then
            fields[#fields + 1] = text:sub(start)
            return fields
        end
        fields[#fields + 1] = text:sub(start, i - 1)
        if #fields >= MAX_FIELDS then return nil end
        start = i + 1
    end
end

---------------------------------------------------------------------------
-- Decoding
---------------------------------------------------------------------------
local decoders = {}

-- Reads a run of checks into a table: spec = { { key, check, optional }, ... }.
local function ReadAll(fields, first, spec, into)
    for offset, field in ipairs(spec) do
        local ok, value = Read(fields, first + offset - 1, field[2], field[3])
        if not ok then return nil end
        into[field[1]] = value
    end
    return into
end

local PLAYER = { { "name", Name }, { "guid", Guid, true }, { "class", Class, true }, { "level", Level, true } }

function decoders.H(fields, msg)
    if #fields ~= 5 then return nil end
    return ReadAll(fields, 4, { { "since", Time }, { "version", Version, true } }, msg)
end

local function DecodeKill(fields, msg)
    local killerFields = #fields - 9
    if killerFields < 4 or killerFields % 4 ~= 0 or killerFields / 4 > Protocol.MAX_KILLERS then return nil end
    if not ReadAll(fields, 4, { { "id", KillId }, { "at", Time }, { "mapID", Map, true },
                                { "x", Coord, true }, { "y", Coord, true }, { "flags", Flags, true } }, msg) then
        return nil
    end
    if (msg.x == nil) ~= (msg.y == nil) then return nil end
    if msg.x then msg.x, msg.y = msg.x / 1000, msg.y / 1000 end
    msg.test = msg.flags and msg.flags:find("t", 1, true) and true or nil
    msg.flags = nil
    msg.killers = {}
    for first = 10, #fields, 4 do
        local killer = ReadAll(fields, first, PLAYER, {})
        if not killer then return nil end
        msg.killers[#msg.killers + 1] = killer
    end
    return msg
end
decoders.K = DecodeKill
decoders.R = DecodeKill

function decoders.M(fields, msg)
    if #fields ~= 8 then return nil end
    msg.target = {}
    if not ReadAll(fields, 4, { { "at", Time } }, msg) then return nil end
    if not ReadAll(fields, 5, PLAYER, msg.target) then return nil end
    return msg
end

function decoders.X(fields, msg)
    if #fields ~= 5 then return nil end
    msg.target = {}
    if not ReadAll(fields, 4, { { "at", Time } }, msg) then return nil end
    if not ReadAll(fields, 5, { PLAYER[1] }, msg.target) then return nil end
    return msg
end

-- A message as a table ({ type, name, guid, ... }), or nil if it isn't one of ours.
function Protocol.Decode(text)
    if type(text) ~= "string" or text == "" or #text > Protocol.MAX_BYTES or text:find("[%z\1-\8\10-\31|]") then
        return nil
    end
    local fields = Split(text)
    if not fields then return nil end
    local decode = decoders[fields[1]]
    if not decode then return nil end
    local msg = ReadAll(fields, 2, { { "name", Name }, { "guid", Guid, true } }, { type = fields[1] })
    if not msg then return nil end
    return decode(fields, msg)
end

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------
-- "Player-6930-008E2109" -> "6930-008E2109", or "" when it isn't a player GUID.
local function GuidTail(guid)
    return type(guid) == "string" and guid:match("^Player%-(%d+%-%w+)$") or ""
end

local function Clean(check, value)
    if value == nil then return "" end
    value = tostring(value)
    return check(value) and value or ""
end

local function NameField(name)
    return type(name) == "string" and Name(name) and name or nil
end

local function Join(fields)
    return table.concat(fields, SEP)
end

local function Header(kind, sender)
    local name = sender and NameField(sender.name)
    if not name then return nil end
    return { kind, name, GuidTail(sender.guid) }
end

local function Thousandths(v)
    if type(v) ~= "number" or v < 0 or v > 1 then return nil end
    return math.floor(v * 1000 + 0.5)
end

local function PlayerFields(identity)
    local name = NameField(identity.name)
    if not name then return nil end
    return { name, GuidTail(identity.guid), Clean(Class, identity.class), Clean(Level, identity.level) }
end

function Protocol.Hello(sender, since, version)
    local fields = Header("H", sender)
    if not fields then return nil end
    fields[#fields + 1] = tostring(math.floor(since))
    fields[#fields + 1] = Clean(Version, version)
    return Join(fields)
end

-- A kill as messages: kind "K" (live) or "R" (answer). More killers than fit in one
-- message go in further messages with the same id. Returns a list (empty if the kill
-- can't be sent: no usable sender name, or no killer with a full name).
function Protocol.Kill(kind, sender, kill)
    local out = {}
    local header = Header(kind, sender)
    if not (header and type(kill.id) == "string" and KillId(kill.id) and type(kill.at) == "number") then
        return out
    end
    local x, y = Thousandths(kill.x), Thousandths(kill.y)
    if not (x and y) then x, y = nil, nil end
    for _, field in ipairs({ kill.id, math.floor(kill.at), Clean(Map, kill.mapID), x or "", y or "",
                             kill.test and "t" or "" }) do
        header[#header + 1] = tostring(field)
    end
    local base = Join(header)
    local current, count = base, 0
    for _, killer in ipairs(kill.killers or {}) do
        local fields = PlayerFields(killer)
        if fields then
            local piece = SEP .. Join(fields)
            if count > 0 and (count >= Protocol.MAX_KILLERS or #current + #piece > Protocol.MAX_BYTES) then
                out[#out + 1] = current
                current, count = base, 0
            end
            if #current + #piece <= Protocol.MAX_BYTES then
                current, count = current .. piece, count + 1
            end
        end
    end
    if count > 0 then out[#out + 1] = current end
    return out
end

function Protocol.Wanted(sender, mark)
    local fields = Header("M", sender)
    local target = PlayerFields(mark.target)
    if not (fields and target) then return nil end
    fields[#fields + 1] = tostring(math.floor(mark.at))
    for _, field in ipairs(target) do fields[#fields + 1] = field end
    local text = Join(fields)
    return #text <= Protocol.MAX_BYTES and text or nil
end

-- targetName: the target's name, or their name key when that's all that's left.
function Protocol.Withdrawal(sender, targetName, at)
    local fields = Header("X", sender)
    if not (fields and NameField(targetName)) then return nil end
    fields[#fields + 1] = tostring(math.floor(at))
    fields[#fields + 1] = targetName
    return Join(fields)
end
