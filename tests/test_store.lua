-- Saved data: defaults, validation, pruning; settings registration and the slash command.

test("a first run gets every default", function()
    LoadAddon()
    local s = RevengeTrackerDB.settings
    eq(s.expiryDays, 7)
    eq(s.detailsModifier, "SHIFT")
    eq(s.nameplates, true)
    eq(s.otherAddons, true)
    eq(RevengeTrackerDB.version, 1)
end)

test("invalid saved settings are reset; a saved false is kept", function()
    LoadAddon({ settings = { expiryDays = 99, detailsModifier = "META", nameplates = false, alertSound = "yes" } })
    local s = RevengeTrackerDB.settings
    eq(s.expiryDays, 7)
    eq(s.detailsModifier, "SHIFT")
    eq(s.nameplates, false, "false kept")
    eq(s.alertSound, true, "wrong type reset")
end)

test("old kills, old tombstones and broken entries are pruned at load", function()
    local now = 1795600000
    LoadAddon({
        kills = {
            k1 = { id = "k1", at = now - 61 * 86400, victim = { key = "a" }, killers = { { key = "b" } }, sources = {} },
            k2 = { id = "k2", at = now - 10 * 86400, victim = { key = "a" }, killers = { { key = "b" } }, sources = {} },
            k3 = "broken",
        },
        tombstones = { k9 = { at = now - 91 * 86400, victim = "a", killers = {} } },
    })
    eq(count(RevengeTrackerDB.kills), 1)
    ok(RevengeTrackerDB.kills.k2, "recent kill kept")
    eq(count(RevengeTrackerDB.tombstones), 0)
end)

test("saved kills are found again after a reload", function()
    local ns = LoadAddon()
    ns.Merge.SubmitKill({ victim = { name = "Anna Bright", key = "anna bright" },
                          killers = { { name = "Gorvak Ashmane", key = "gorvak ashmane", guid = "Player-1-0000GORV" } },
                          at = Mock.now, precision = "exact", sources = { self = true }, own = true })
    local saved = RevengeTrackerDB
    ns = LoadAddon(saved)
    eq(#ns.Store.KillsByKiller("Player-1-0000GORV", nil), 1)
end)

test("the name cache is capped at 2000 players, keeping the most recent", function()
    local names = {}
    for i = 1, 2100 do names["Player-1-" .. i] = { n = "P " .. i, t = 1000 + i } end
    LoadAddon({ names = names })
    eq(count(RevengeTrackerDB.names), 2000)
    ok(RevengeTrackerDB.names["Player-1-2100"], "newest kept")
    eq(RevengeTrackerDB.names["Player-1-1"], nil, "oldest dropped")
end)

test("settings are registered in the game's panel, bound to saved data", function()
    LoadAddon()
    ok(Mock.registeredCategory, "category registered")
    eq(Mock.registeredCategory.name, "Revenge")
    local expiry = Mock.settings.RevengeTracker_expiryDays
    ok(expiry, "expiry setting")
    eq(expiry.tbl, RevengeTrackerDB.settings)
    eq(expiry.key, "expiryDays")
    ok(Mock.settings.RevengeTracker_detailsModifier, "modifier setting")
end)

test("/revenge opens the settings; unknown commands show help", function()
    LoadAddon()
    SlashCmdList.REVENGETRACKER("")
    eq(Mock.openedCategory, 42)
    SlashCmdList.REVENGETRACKER("nonsense")
    ok(Mock.chat[1]:find("Revenge commands", 1, true), "help shown")
end)

test("an error in one event handler doesn't stop the others", function()
    local ns = LoadAddon()
    local ran = false
    ns.On("TEST_EVENT", function() error("boom") end)
    ns.On("TEST_EVENT", function() ran = true end)
    Mock.Fire("TEST_EVENT")
    ok(ran, "second handler ran")
    eq(#Mock.chat, 0, "silent without debug")
end)
