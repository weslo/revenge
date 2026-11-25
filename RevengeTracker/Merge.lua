-- Merge: every kill report, from any source, enters the store through here.
--
-- A kill report (and a stored kill) looks like:
--   { victim = identity, killers = { identity, ... },
--     at = server time, precision = "exact" | "client" | "received",
--     mapID = number?, x = 0..1?, y = 0..1?, zone = text?,
--     sources = { [sourceId] = true },   -- e.g. "self", "revenge", "revengebook"
--     own = true when Revenge itself (you or another Revenge user) reported it,
--     test = true for /revenge test kills }
--
-- Two reports are the same kill when they share the victim, at least one killer,
-- a time within the window (2 min when both are exact, 10 min otherwise) and the
-- zone when both give one. Revenge's own data wins any disagreement.
local _, ns = ...

local Merge = ns.RegisterModule("Merge", {})
local Identity = ns.Identity

local EXACT_WINDOW = 120
local LOOSE_WINDOW = 600

local function Window(a, b)
    if a.precision == "exact" and b.precision == "exact" then return EXACT_WINDOW end
    return LOOSE_WINDOW
end

local function SharesKiller(a, b)
    for _, ka in ipairs(a.killers) do
        for _, kb in ipairs(b.killers) do
            if Identity.Same(ka, kb) then return true end
        end
    end
    return false
end

local function SameZone(a, b)
    if a.mapID and b.mapID then return a.mapID == b.mapID end
    if a.zone and b.zone then return a.zone == b.zone end
    return true
end

local function SameKill(a, b)
    return Identity.Same(a.victim, b.victim)
        and math.abs(a.at - b.at) <= Window(a, b)
        and SharesKiller(a, b)
        and SameZone(a, b)
end

local function Tombstoned(report)
    for _, stone in pairs(ns.Store.Tombstones()) do
        if stone.victim == report.victim.key and math.abs(stone.at - report.at) <= LOOSE_WINDOW then
            for _, key in ipairs(stone.killers) do
                for _, killer in ipairs(report.killers) do
                    if killer.key == key then return true end
                end
            end
        end
    end
    return false
end

-- Copies the fields of `from` into `into` where `into` has none, or where `from`
-- is Revenge's own and `into` isn't.
local function Fill(into, from, fromWins)
    for _, field in ipairs({ "name", "key", "guid", "class", "level", "guild", "faction" }) do
        if from[field] ~= nil and (into[field] == nil or fromWins) then into[field] = from[field] end
    end
    if into.partial and not from.partial and from.name then into.partial = nil end
end

local function MergeInto(kill, report)
    local reportWins = report.own and not kill.own
    -- Killers: union, combining the same player's details.
    for _, killer in ipairs(report.killers) do
        local match
        for _, existing in ipairs(kill.killers) do
            if Identity.Same(existing, killer) then match = existing break end
        end
        if match then Fill(match, killer, reportWins) else table.insert(kill.killers, killer) end
    end
    -- Time and place: the more precise, or Revenge's own.
    if report.precision == "exact" and (kill.precision ~= "exact" or reportWins) then
        kill.at, kill.precision = report.at, "exact"
    end
    if report.x and report.y and (not kill.x or reportWins) then
        kill.mapID, kill.x, kill.y = report.mapID, report.x, report.y
    end
    kill.zone = (reportWins and report.zone) or kill.zone or report.zone
    for source in pairs(report.sources) do kill.sources[source] = true end
    kill.own = kill.own or report.own
    ns.Store.Reindex(kill)
end

-- Adds a kill report. Returns the stored kill, and true if it was new.
function Merge.SubmitKill(report)
    if not (report.victim and report.victim.key and type(report.at) == "number" and #report.killers > 0) then
        return nil
    end
    Identity.Resolve(report.victim)
    for _, killer in ipairs(report.killers) do Identity.Resolve(killer) end
    if Tombstoned(report) then return nil end
    for _, kill in ipairs(ns.Store.KillsByVictim(report.victim.key)) do
        if SameKill(kill, report) then
            MergeInto(kill, report)
            return kill, false
        end
    end
    report.id = ns.Store.NewId("k")
    ns.Store.AddKill(report)
    return report, true
end

-- The cache just learned a full name for this GUID: upgrade stored partial identities.
function Merge.UpgradeIdentity(guid)
    for _, kill in ipairs(ns.Store.KillsByKiller(guid, nil)) do
        for _, killer in ipairs(kill.killers) do
            if killer.guid == guid and killer.partial then Identity.Resolve(killer) end
        end
        ns.Store.Reindex(kill)
    end
end
