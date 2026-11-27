-- Deaths: records your own open-world deaths to enemy players.
--
-- Forever has no combat log for addons. C_DeathRecap lists the last death's hits:
-- sourceGUID, sourceName (first name only), sourceFlags, overkill and timestamp
-- (server time). It may not be ready on the PLAYER_DEAD frame, so it's read again
-- after short delays. Every hostile player in it counts as a killer.
local _, ns = ...

local Deaths = ns.RegisterModule("Deaths", {})
local Try, Accessible, AccessibleString, AccessibleNumber = ns.Try, ns.Accessible, ns.AccessibleString, ns.AccessibleNumber
local Identity = ns.Identity

local TYPE_PLAYER = 0x00000400
local REACTION_HOSTILE = 0x00000040
local RETRY_DELAYS = { 0.3, 1, 2.5 }
local RECAP_MAX_AGE = 90  -- seconds between the newest recap hit and the death

local deathSerial = 0

local function IsOpenWorld()
    local inInstance = Try(IsInInstance)
    return not inInstance
end

local function Copy(identity)
    local copy = {}
    for key, value in pairs(identity) do copy[key] = value end
    return copy
end

local function WherePlayerIs()
    local mapID = AccessibleNumber(Try(C_Map.GetBestMapForUnit, "player"))
    local x, y
    if mapID then
        local position = Accessible(Try(C_Map.GetPlayerMapPosition, mapID, "player"))
        if position then
            if position.GetXY then
                x, y = Try(position.GetXY, position)
            else
                x, y = position.x, position.y
            end
            x, y = AccessibleNumber(x), AccessibleNumber(y)
        end
    end
    return mapID, x, y, AccessibleString(Try(GetRealZoneText))
end

-- Hostile players in the recap, as identities; and the newest hit's time.
local function KillersFromRecap(events)
    local killers, seen, newest = {}, {}, nil
    local myFaction = Identity.Self() and Identity.Self().faction
    for _, entry in ipairs(events) do
        local flags = AccessibleNumber(Accessible(entry.sourceFlags))
        local guid = AccessibleString(entry.sourceGUID)
        local stamp = AccessibleNumber(Accessible(entry.timestamp))
        if stamp and (not newest or stamp > newest) then newest = stamp end
        if flags and guid and guid:match("^Player%-")
            and bit.band(flags, TYPE_PLAYER) ~= 0 and bit.band(flags, REACTION_HOSTILE) ~= 0
            and not seen[guid] then
            seen[guid] = true
            local killer = Identity.Resolve(Identity.Make(AccessibleString(entry.sourceName), guid))
            -- Same-faction players (free-for-all areas) aren't grudges.
            if killer and not (myFaction and killer.faction == myFaction) then
                killers[#killers + 1] = killer
            end
        end
    end
    return killers, newest
end

local function NotRecorded(why, ...)
    ns.Log("death", "not recorded: " .. why, ...)
end

local function TryRecord(serial, attempt, diedAt, where)
    if serial ~= deathSerial then return end
    local events = C_DeathRecap and Try(C_DeathRecap.HasRecapEvents) and Try(C_DeathRecap.GetRecapEvents)
    if type(events) ~= "table" or #events == 0 then
        local delay = RETRY_DELAYS[attempt + 1]
        if delay then
            ns.After(delay, function() TryRecord(serial, attempt + 1, diedAt, where) end)
        else
            NotRecorded("no death recap in %s", where.zone)
        end
        return
    end
    deathSerial = deathSerial + 1  -- handled: ignore later retries for this death
    local killers, newest = KillersFromRecap(events)
    if #killers == 0 then return NotRecorded("no enemy player among the death recap's %d hits, in %s", #events, where.zone) end
    -- Timestamps are expected to be server time; anything else is ignored rather
    -- than trusted, so an unexpected unit can't discard real deaths.
    if newest and newest < 1e9 then newest = nil end
    if newest and math.abs(diedAt - newest) > RECAP_MAX_AGE then  -- an old recap
        return NotRecorded("the death recap was %d seconds old", math.floor(math.abs(diedAt - newest)))
    end
    local me = Identity.Self()
    if not me then return NotRecorded("your own name wasn't readable") end
    local kill, new = ns.Merge.SubmitKill({
        victim = Copy(me),
        killers = killers,
        at = newest and math.floor(newest) or diedAt,
        precision = "exact",
        mapID = where.mapID, x = where.x, y = where.y, zone = where.zone,
        sources = { self = true },
        own = true,
    })
    if not kill then return NotRecorded("killed by %s, a death dismissed earlier", ns.Diagnostics.Names(killers)) end
    ns.Debug("recorded death to %d killer(s)", #killers)
    local sent = new and ns.Try(ns.Share and ns.Share.OwnKill, kill) or 0
    ns.Log("death", "recorded: killed by %s in %s (map %s, %s), %s; %d messages queued to share",
        ns.Diagnostics.Names(killers), where.zone, where.mapID, where.x and "with position" or "no position",
        new and "new" or "merged with one already known", sent)
end

local function OnPlayerDead()
    if not IsOpenWorld() then
        local _, kind = Try(IsInInstance)
        return NotRecorded("in an instance (%s)", kind)
    end
    deathSerial = deathSerial + 1
    local mapID, x, y, zone = WherePlayerIs()
    TryRecord(deathSerial, 0, ns.Now(), { mapID = mapID, x = x, y = y, zone = zone })
end

-- /revenge test: a kill on you by `killer`, marked as a test. With share, it's also
-- sent to guildmates (/revenge test share); returns how many messages were queued.
function Deaths.RecordTestKill(killer, share)
    local me = Identity.Self()
    if not me then return 0 end
    local mapID, x, y, zone = WherePlayerIs()
    local kill = ns.Merge.SubmitKill({
        victim = Copy(me),
        killers = { Copy(killer) },
        at = ns.Now(),
        precision = "exact",
        mapID = mapID, x = x, y = y, zone = zone,
        sources = { self = true },
        own = true,
        test = true,
    })
    if not (share and kill) then return 0 end
    return ns.Try(ns.Share and ns.Share.OwnKill, kill) or 0
end

function Deaths:OnLogin()
    ns.On("PLAYER_DEAD", OnPlayerDead)
end
