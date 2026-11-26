-- Deduplication across sources, tombstones and "own data wins".

local ME = { name = "Anna Bright", key = "anna bright", guid = "Player-1-AAAA0001" }

local function Id(name, guid)
    return { name = name, key = name and name:lower(), guid = guid, partial = (name and not name:find(" ")) or nil }
end

local function Own(ns, at, killers, extra)
    local report = { victim = Id(ME.name, ME.guid), killers = killers, at = at, precision = "exact",
                     mapID = 1431, zone = "Duskwood", sources = { self = true }, own = true }
    for k, v in pairs(extra or {}) do report[k] = v end
    return ns.Merge.SubmitKill(report)
end

local function Foreign(ns, at, killers, precision, extra)
    local report = { victim = Id(ME.name, ME.guid), killers = killers, at = at, precision = precision or "client",
                     sources = { revengebook = true } }
    for k, v in pairs(extra or {}) do report[k] = v end
    return ns.Merge.SubmitKill(report)
end

test("the same death from Revenge and another addon counts once", function()
    local ns = LoadAddon()
    local now = Mock.now
    local a, newA = Own(ns, now, { Id("Gorvak Ashmane", "Player-1-0000GORV") })
    local b, newB = Foreign(ns, now + 240, { Id("Gorvak Ashmane") }, "client", { zone = "Duskwood" })
    ok(newA, "first is new")
    eq(newB, false, "second merges")
    eq(a, b)
    eq(count(RevengeTrackerDB.kills), 1)
    ok(a.sources.self and a.sources.revengebook, "both sources kept")
end)

test("kills far apart in time stay separate", function()
    local ns = LoadAddon()
    local now = Mock.now
    Own(ns, now, { Id("Gorvak Ashmane", "Player-1-0000GORV") })
    Own(ns, now + 1800, { Id("Gorvak Ashmane", "Player-1-0000GORV") })
    eq(count(RevengeTrackerDB.kills), 2)
end)

test("two exact reports 3 minutes apart are two kills; a received-time report 9 minutes off merges", function()
    local ns = LoadAddon()
    local now = Mock.now
    Own(ns, now, { Id("Gorvak Ashmane", "Player-1-0000GORV") })
    Own(ns, now + 180, { Id("Gorvak Ashmane", "Player-1-0000GORV") })
    eq(count(RevengeTrackerDB.kills), 2, "exact window is 2 minutes")
    local _, isNew = Foreign(ns, now + 180 + 540, { Id("Gorvak Ashmane") }, "received")
    eq(isNew, false, "loose window is 10 minutes")
    eq(count(RevengeTrackerDB.kills), 2)
end)

test("zone names in another language don't split a kill", function()
    local ns = LoadAddon()
    local now = Mock.now
    Own(ns, now, { Id("Gorvak Ashmane", "Player-1-0000GORV") }, { zone = "Duskwood" })
    Foreign(ns, now + 30, { Id("Gorvak Ashmane") }, "client", { zone = "Dämmerwald" })
    eq(count(RevengeTrackerDB.kills), 1)
end)

test("different map IDs keep reports apart", function()
    local ns = LoadAddon()
    local now = Mock.now
    Own(ns, now, { Id("Gorvak Ashmane", "Player-1-0000GORV") })
    Foreign(ns, now + 30, { Id("Gorvak Ashmane") }, "client", { mapID = 1429 })
    eq(count(RevengeTrackerDB.kills), 2)
end)

test("a report with no killer in common is a different kill", function()
    local ns = LoadAddon()
    local now = Mock.now
    Own(ns, now, { Id("Gorvak Ashmane", "Player-1-0000GORV") })
    Foreign(ns, now + 30, { Id("Brakka Stonefist") })
    eq(count(RevengeTrackerDB.kills), 2)
end)

test("killers from both reports are combined", function()
    local ns = LoadAddon()
    local now = Mock.now
    local kill = Own(ns, now, { Id("Gorvak Ashmane", "Player-1-0000GORV") })
    Foreign(ns, now + 20, { Id("Gorvak Ashmane"), Id("Shazra Vex") })
    eq(#kill.killers, 2)
    eq(kill.killers[2].name, "Shazra Vex")
end)

test("a dismissed kill can't come back from another source", function()
    local ns = LoadAddon()
    local now = Mock.now
    local kill = Own(ns, now, { Id("Gorvak Ashmane", "Player-1-0000GORV") })
    ns.Store.Dismiss(kill.id)
    eq(count(RevengeTrackerDB.kills), 0)
    local again = Foreign(ns, now + 60, { Id("Gorvak Ashmane") })
    eq(again, nil)
    eq(count(RevengeTrackerDB.kills), 0)
    ok(#ns.Store.KillsByKiller("Player-1-0000GORV", "gorvak ashmane") == 0, "index cleared")
end)

test("Revenge's own data wins over another addon's", function()
    local ns = LoadAddon()
    local now = Mock.now
    -- Same map, but the other addon's zone name is in another language.
    local kill = Foreign(ns, now, { { name = "Gorvak Ashmane", key = "gorvak ashmane", class = "WARRIOR" } },
                         "client", { mapID = 1431, zone = "Bosque del Ocaso" })
    eq(kill.own, nil)
    Own(ns, now + 30, { { name = "Gorvak Ashmane", key = "gorvak ashmane", guid = "Player-1-0000GORV", class = "ROGUE" } },
        { zone = "Duskwood" })
    eq(count(RevengeTrackerDB.kills), 1)
    eq(kill.zone, "Duskwood", "own zone wins")
    eq(kill.killers[1].class, "ROGUE", "own class wins")
    eq(kill.killers[1].guid, "Player-1-0000GORV", "own GUID added")
    eq(kill.own, true)
    eq(kill.precision, "exact")
end)

test("another addon only fills gaps in Revenge's own kill", function()
    local ns = LoadAddon()
    local now = Mock.now
    local kill = Own(ns, now, { { name = "Gorvak Ashmane", key = "gorvak ashmane", guid = "Player-1-0000GORV", class = "ROGUE" } },
                     { zone = "Duskwood" })
    Foreign(ns, now + 30, { { name = "Gorvak Ashmane", key = "gorvak ashmane", class = "WARRIOR", guild = "Bloodfang Raiders" } },
            "client", { zone = "Elsewhere" })
    eq(kill.zone, "Duskwood")
    eq(kill.killers[1].class, "ROGUE")
    eq(kill.killers[1].guild, "Bloodfang Raiders", "gap filled")
end)

test("reports missing a victim, time or killers are dropped", function()
    local ns = LoadAddon()
    eq(ns.Merge.SubmitKill({ victim = {}, killers = { Id("Gorvak Ashmane") }, at = Mock.now, sources = {} }), nil)
    eq(ns.Merge.SubmitKill({ victim = Id(ME.name), killers = {}, at = Mock.now, sources = {} }), nil)
    eq(ns.Merge.SubmitKill({ victim = Id(ME.name), killers = { Id("Gorvak Ashmane") }, sources = {} }), nil)
    eq(count(RevengeTrackerDB.kills), 0)
end)

test("a cached full name upgrades a first-name-only killer", function()
    local ns = LoadAddon()
    local kill = Own(ns, Mock.now, { { name = "Gorvak", key = "gorvak", guid = "Player-1-0000GORV", partial = true } })
    eq(kill.killers[1].name, "Gorvak")
    Mock.units.target = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 }
    Mock.Fire("PLAYER_TARGET_CHANGED")
    eq(kill.killers[1].name, "Gorvak Ashmane")
    eq(kill.killers[1].partial, nil)
    eq(#ns.Store.KillsByKiller(nil, "gorvak ashmane"), 1, "findable by full name")
end)
