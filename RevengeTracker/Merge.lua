-- Merge: every kill report and Wanted mark, from any source, enters the store through here.
--
-- A kill report (and a stored kill) looks like:
--   { victim = identity, killers = { identity, ... },
--     at = server time, precision = "exact" | "client" | "received",
--     mapID = number?, x = 0..1?, y = 0..1?, zone = text?,
--     sources = { [sourceId] = true },   -- e.g. "self", "revenge", "revengebook"
--     own = true when Revenge itself (you or another Revenge user) reported it,
--     test = true for /revenge test kills,
--     origin = "victim key#their kill id" on a report shared by another Revenge user;
--              a stored kill keeps them all in origins = { [origin] = true } }
--
-- Two reports are the same kill when they share an origin, or when they share the
-- victim, at least one killer, a time within the window (2 min when both are exact,
-- 10 min otherwise) and the map when both give a map ID. The origin joins the parts
-- of a death sent in several messages, whose killers differ. Revenge's own data wins
-- any disagreement.
--
-- A Wanted mark looks like:
--   { target = identity, by = identity of whoever added it, at = time added,
--     sources = { [sourceId] = true }, own = true when added through Revenge,
--     hidden = true when you removed someone else's mark (it stays hidden for you) }
-- The same target and adder make one mark. Marks never expire; only their adder
-- withdraws them, and a withdrawal beats any copy of the mark from before it.
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

-- Only map IDs decide. Zone names can't: other addons send them in their user's
-- game language ("Dämmerwald" for "Duskwood"), which would split one death in two.
local function SameZone(a, b)
    if a.mapID and b.mapID then return a.mapID == b.mapID end
    return true
end

local function SameKill(a, b)
    return Identity.Same(a.victim, b.victim)
        and math.abs(a.at - b.at) <= Window(a, b)
        and SharesKiller(a, b)
        and SameZone(a, b)
end

-- Tombstones from before per-killer removal stored bare name keys.
local function StoneIdentity(entry)
    if type(entry) == "string" then return { key = entry } end
    return entry
end

-- Applies dismissals to a report about the same death: a dismissed kill is refused
-- outright, and a killer removed from it is dropped. Returns true when nothing is
-- left to record.
local function ApplyTombstones(report)
    for _, stone in pairs(ns.Store.Tombstones()) do
        if stone.victim == report.victim.key and math.abs(stone.at - report.at) <= LOOSE_WINDOW then
            for i = #report.killers, 1, -1 do
                for _, entry in ipairs(stone.killers) do
                    if Identity.Same(StoneIdentity(entry), report.killers[i]) then
                        if stone.all then return true end
                        table.remove(report.killers, i)
                        break
                    end
                end
            end
        end
    end
    return #report.killers == 0
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
    for source in pairs(report.sources or {}) do kill.sources[source] = true end
    if report.origin then
        kill.origins = kill.origins or {}
        kill.origins[report.origin] = true
    end
    kill.own = kill.own or report.own
    ns.Store.Reindex(kill)
end

local function SameOrigin(kill, report)
    return report.origin ~= nil and kill.origins ~= nil and kill.origins[report.origin] == true
end

-- Adds a kill report. Returns the stored kill, and true if it was new.
function Merge.SubmitKill(report)
    if not (report.victim and report.victim.key and type(report.at) == "number" and #report.killers > 0) then
        return nil
    end
    Identity.Resolve(report.victim)
    for _, killer in ipairs(report.killers) do Identity.Resolve(killer) end
    if ApplyTombstones(report) then return nil end
    for _, kill in ipairs(ns.Store.KillsByVictim(report.victim.key)) do
        if SameOrigin(kill, report) or SameKill(kill, report) then
            MergeInto(kill, report)
            ns.Changed()
            return kill, false
        end
    end
    report.id = ns.Store.NewId("k")
    report.sources = report.sources or {}
    if report.origin then report.origins = { [report.origin] = true } end
    report.origin = nil
    ns.Store.AddKill(report)
    ns.Changed()
    return report, true
end

---------------------------------------------------------------------------
-- Wanted marks
---------------------------------------------------------------------------
function Merge.PairKey(target, by)
    return target.key .. "|" .. by.key
end

local function ValidMarkReport(report)
    return type(report) == "table" and type(report.target) == "table" and type(report.target.key) == "string"
        and type(report.by) == "table" and type(report.by.key) == "string" and type(report.at) == "number"
end

local function FindMark(target, by)
    for _, mark in ipairs(ns.Store.WantedFor(target.guid, target.key)) do
        if Identity.Same(mark.target, target) and Identity.Same(mark.by, by) then return mark end
    end
end

-- Adds a Wanted mark. Returns the stored mark, and true if it was new.
function Merge.SubmitWanted(report)
    if not ValidMarkReport(report) then return nil end
    Identity.Resolve(report.target)
    local withdrawnAt = ns.Store.Withdrawal(Merge.PairKey(report.target, report.by))
    if withdrawnAt and report.at <= withdrawnAt then return nil end
    local mark = FindMark(report.target, report.by)
    if mark then
        local reportWins = report.own and not mark.own
        Fill(mark.target, report.target, reportWins)
        Fill(mark.by, report.by, reportWins)
        for source in pairs(report.sources or {}) do mark.sources[source] = true end
        mark.own = mark.own or report.own
        if report.at < mark.at then mark.at = report.at end
        ns.Store.ReindexWanted(mark)
        ns.Changed()
        return mark, false
    end
    report.id = ns.Store.NewId("w")
    report.sources = report.sources or {}
    report.hidden = nil
    ns.Store.AddWanted(report)
    ns.Changed()
    return report, true
end

-- The adder withdrew their mark at report.at: { target, by, at }. Removes it and
-- remembers the time, so an older copy arriving later is refused. Returns how many
-- marks were removed.
function Merge.SubmitWithdrawal(report)
    if not ValidMarkReport(report) then return 0 end
    ns.Store.SetWithdrawal(Merge.PairKey(report.target, report.by), report.at)
    local removed = 0
    for _, mark in ipairs(ns.Store.WantedFor(report.target.guid, report.target.key)) do
        if Identity.Same(mark.target, report.target) and Identity.Same(mark.by, report.by) and mark.at <= report.at then
            ns.Store.RemoveWanted(mark.id)
            removed = removed + 1
        end
    end
    if removed > 0 then ns.Changed() end
    return removed
end

---------------------------------------------------------------------------
-- The cache just learned a full name for this GUID (key: that name's key):
-- upgrade stored partial killers, and give Wanted marks added by name their GUID.
function Merge.UpgradeIdentity(guid, key)
    for _, kill in ipairs(ns.Store.KillsByKiller(guid, nil)) do
        for _, killer in ipairs(kill.killers) do
            if killer.guid == guid and killer.partial then Identity.Resolve(killer) end
        end
        ns.Store.Reindex(kill)
    end
    if not key then return end
    for _, mark in ipairs(ns.Store.WantedFor(nil, key)) do
        if not mark.target.guid then
            mark.target.guid = guid
            Identity.Resolve(mark.target)
            ns.Store.ReindexWanted(mark)
        end
    end
end
