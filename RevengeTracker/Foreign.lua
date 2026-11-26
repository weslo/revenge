-- Foreign: the only door for data from other addons (the optional
-- RevengeTracker_OtherAddons module, built in a later slice).
--
-- Everything is checked here before it reaches the merge: known record types,
-- field types, string lengths, number ranges and sane times. Anything wrong is
-- dropped silently. Revenge's own data always wins over foreign data (Merge.lua).
local _, ns = ...

local Foreign = ns.RegisterModule("Foreign", {})

local MAX_TEXT = 64
local MAX_KILLERS = 5
local MAX_AGE = 30 * 86400
local MAX_FUTURE = 300

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
    local identity = ns.Identity.Make(name, guid)
    if not identity then return nil end
    identity.class = Text(raw.class)
    identity.level = Number(raw.level, 1, 100)
    identity.guild = Text(raw.guild)
    return identity
end

local function CleanKill(raw, sourceId, now)
    if type(raw) ~= "table" or raw.type ~= "kill" then return nil end
    local at = Number(raw.at, now - MAX_AGE, now + MAX_FUTURE)
    local victim = CleanIdentity(raw.victim)
    if not (at and victim and type(raw.killers) == "table") then return nil end
    local killers = {}
    for i = 1, math.min(#raw.killers, MAX_KILLERS) do
        local killer = CleanIdentity(raw.killers[i])
        if killer then killers[#killers + 1] = killer end
    end
    if #killers == 0 then return nil end
    local precision = raw.precision
    if precision ~= "exact" and precision ~= "client" then precision = "received" end
    return {
        victim = victim,
        killers = killers,
        at = at,
        precision = precision,
        mapID = Number(raw.mapID, 1, 100000),
        x = Number(raw.x, 0, 1),
        y = Number(raw.y, 0, 1),
        zone = Text(raw.zone),
        sources = { [sourceId] = true },
    }
end

-- records: a list of raw records from one adapter; sourceId: e.g. "revengebook".
-- Returns how many were accepted. Never errors.
function Foreign.Submit(records, sourceId)
    if not ns.db or not ns.Store.Setting("otherAddons") then return 0 end
    if type(records) ~= "table" or not Text(sourceId) then return 0 end
    local accepted, now = 0, ns.Now()
    for i = 1, math.min(#records, 50) do
        local ok, kill = pcall(CleanKill, records[i], sourceId, now)
        if ok and kill and ns.Try(ns.Merge.SubmitKill, kill) then accepted = accepted + 1 end
    end
    return accepted
end

-- The small public surface the optional module uses.
RevengeTracker = {
    SubmitForeign = function(records, sourceId)
        local ok, accepted = pcall(Foreign.Submit, records, sourceId)
        return ok and accepted or 0
    end,
}
