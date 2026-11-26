-- Recording your own deaths from the death recap.

local HOSTILE_PLAYER = 0x0548   -- player type, hostile, player-controlled, outsider
local HOSTILE_NPC = 0x0A48

local function Hit(guid, name, flags, stamp, overkill)
    return { sourceGUID = guid, sourceName = name, sourceFlags = flags, timestamp = stamp, overkill = overkill or -1 }
end

local function Die()
    Mock.Fire("PLAYER_DEAD")
end

test("an open-world death records each hostile player, with full names from the cache", function()
    local ns = LoadAddon()
    -- Seen before the fight, so the cache knows Gorvak's surname.
    Mock.units.target = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE",
                          level = 41, faction = "Horde" }
    Mock.Fire("PLAYER_TARGET_CHANGED")
    Mock.units.target = nil
    Mock.byGuid["Player-1-0000SHAZ"] = { name = "Shazra", class = "HUNTER", level = 39 }
    Mock.recap = {
        Hit("Creature-0-1-2-3-4", "Defias Bandit", HOSTILE_NPC, Mock.now - 9),
        Hit("Player-1-0000SHAZ", "Shazra", HOSTILE_PLAYER, Mock.now - 5),
        Hit("Player-1-0000GORV", "Gorvak", HOSTILE_PLAYER, Mock.now - 1, 120),
    }
    Die()
    eq(count(RevengeTrackerDB.kills), 1)
    local _, kill = next(RevengeTrackerDB.kills)
    eq(#kill.killers, 2, "two players, the NPC ignored")
    local names = { kill.killers[1].name, kill.killers[2].name }
    table.sort(names)
    eq(names[1], "Gorvak Ashmane", "surname from the cache")
    eq(names[2], "Shazra", "first name only until seen")
    eq(kill.victim.name, "Anna Bright")
    eq(kill.at, Mock.now - 1)
    eq(kill.precision, "exact")
    eq(kill.mapID, 1431)
    eq(kill.x, 0.42)
    eq(kill.zone, "Duskwood")
    ok(kill.own, "own")
end)

test("a recap that's late is read on a retry, once", function()
    local ns = LoadAddon()
    Die()
    eq(count(RevengeTrackerDB.kills), 0, "nothing yet")
    Mock.Advance(0.5)
    Mock.recap = { Hit("Player-1-0000GORV", "Gorvak", HOSTILE_PLAYER, Mock.now) }
    Mock.Advance(1)
    eq(count(RevengeTrackerDB.kills), 1, "read on the 1 s retry")
    Mock.Advance(5)
    eq(count(RevengeTrackerDB.kills), 1, "later retries don't add more")
end)

test("deaths inside instances are ignored", function()
    local ns = LoadAddon()
    Mock.inInstance = true
    Mock.recap = { Hit("Player-1-0000GORV", "Gorvak", HOSTILE_PLAYER, Mock.now) }
    Die()
    Mock.Advance(5)
    eq(count(RevengeTrackerDB.kills), 0)
end)

test("deaths to NPCs only record nothing", function()
    local ns = LoadAddon()
    Mock.recap = { Hit("Creature-0-1-2-3-4", "Defias Bandit", HOSTILE_NPC, Mock.now) }
    Die()
    Mock.Advance(5)
    eq(count(RevengeTrackerDB.kills), 0)
end)

test("same-faction players (free-for-all) are skipped", function()
    local ns = LoadAddon()
    Mock.units.target = { name = "Pell", surname = "Oakes", guid = "Player-1-0000PELL", class = "WARRIOR",
                          level = 40, faction = "Alliance" }
    Mock.Fire("PLAYER_TARGET_CHANGED")
    Mock.recap = { Hit("Player-1-0000PELL", "Pell", HOSTILE_PLAYER, Mock.now) }
    Die()
    eq(count(RevengeTrackerDB.kills), 0)
end)

test("an old recap from an earlier death is ignored", function()
    local ns = LoadAddon()
    Mock.recap = { Hit("Player-1-0000GORV", "Gorvak", HOSTILE_PLAYER, Mock.now - 600) }
    Die()
    Mock.Advance(5)
    eq(count(RevengeTrackerDB.kills), 0)
end)

test("a recap with an unexpected time unit still records the death at the death time", function()
    local ns = LoadAddon()
    Mock.recap = { Hit("Player-1-0000GORV", "Gorvak", HOSTILE_PLAYER, 12345.6) }
    Die()
    local _, kill = next(RevengeTrackerDB.kills)
    ok(kill, "recorded")
    eq(kill.at, Mock.now)
end)

test("hidden recap values are skipped without errors", function()
    local ns = LoadAddon()
    Mock.recap = {
        Hit(Mock.SECRET, Mock.SECRET, Mock.SECRET, Mock.SECRET),
        Hit("Player-1-0000GORV", "Gorvak", HOSTILE_PLAYER, Mock.now),
    }
    Die()
    eq(count(RevengeTrackerDB.kills), 1)
end)

test("/revenge test records a test kill, and test clear removes it", function()
    local ns = LoadAddon()
    Mock.units.target = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 }
    SlashCmdList.REVENGETRACKER("test")
    local _, kill = next(RevengeTrackerDB.kills)
    ok(kill and kill.test, "test kill")
    eq(kill.killers[1].name, "Gorvak Ashmane")
    SlashCmdList.REVENGETRACKER("test clear")
    eq(count(RevengeTrackerDB.kills), 0)
end)

test("/revenge test without a player target says so", function()
    local ns = LoadAddon()
    SlashCmdList.REVENGETRACKER("test")
    eq(count(RevengeTrackerDB.kills), 0)
    ok(Mock.chat[#Mock.chat]:find("Target a player first", 1, true), "message")
end)
