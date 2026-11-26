-- The SubmitForeign door: validation, silence and the off switch.

local function Raw(extra)
    local record = {
        type = "kill",
        at = Mock.now - 60,
        precision = "client",
        victim = { name = "Mira Thornwood" },
        killers = { { name = "Gorvak Ashmane", class = "ROGUE", level = 41 } },
        zone = "Duskwood",
    }
    for k, v in pairs(extra or {}) do record[k] = v end
    return record
end

test("a valid foreign kill is accepted and tagged with its source", function()
    local ns = LoadAddon()
    eq(RevengeTracker.SubmitForeign({ Raw() }, "revengebook"), 1)
    local _, kill = next(RevengeTrackerDB.kills)
    ok(kill.sources.revengebook, "source tag")
    eq(kill.own, nil, "not Revenge's own")
    eq(kill.victim.name, "Mira Thornwood")
    eq(kill.killers[1].level, 41)
end)

test("junk never errors and is never stored", function()
    local ns = LoadAddon()
    local junk = {
        "text", 42, true, {}, { type = "other" },
        Raw({ at = "yesterday" }),
        Raw({ at = Mock.now + 3600 }),                    -- from the future
        Raw({ at = Mock.now - 40 * 86400 }),              -- too old
        Raw({ victim = "Mira" }),
        Raw({ victim = { name = string.rep("x", 200) } }), -- too long
        Raw({ victim = { name = "Mi|cffff0000ra" } }),     -- escape codes
        Raw({ killers = "Gorvak" }),
        Raw({ killers = { "Gorvak" } }),
        Raw({ killers = {} }),
    }
    eq(RevengeTracker.SubmitForeign(junk, "revengebook"), 0)
    eq(RevengeTracker.SubmitForeign("not a list", "revengebook"), 0)
    eq(RevengeTracker.SubmitForeign(nil, nil), 0)
    eq(RevengeTracker.SubmitForeign({ Raw() }, { "bad id" }), 0)
    eq(count(RevengeTrackerDB.kills), 0)
    eq(#Mock.chat, 0, "nothing printed")
end)

test("a non-player GUID is dropped but the name kept", function()
    local ns = LoadAddon()
    RevengeTracker.SubmitForeign({ Raw({ killers = { { name = "Gorvak Ashmane", guid = "Creature-0-1-2-3" } } }) }, "x")
    local _, kill = next(RevengeTrackerDB.kills)
    eq(kill.killers[1].guid, nil)
    eq(kill.killers[1].name, "Gorvak Ashmane")
end)

test("out-of-range numbers are dropped, not trusted", function()
    local ns = LoadAddon()
    RevengeTracker.SubmitForeign({ Raw({ x = 5, y = -1, mapID = "1431",
        killers = { { name = "Gorvak Ashmane", level = 900 } } }) }, "x")
    local _, kill = next(RevengeTrackerDB.kills)
    eq(kill.x, nil)
    eq(kill.y, nil)
    eq(kill.mapID, nil)
    eq(kill.killers[1].level, nil)
end)

test("with other addons switched off, nothing is accepted", function()
    local ns = LoadAddon()
    RevengeTrackerDB.settings.otherAddons = false
    eq(RevengeTracker.SubmitForeign({ Raw() }, "revengebook"), 0)
    eq(count(RevengeTrackerDB.kills), 0)
end)

test("at most 50 records are taken per call", function()
    local ns = LoadAddon()
    local many = {}
    for i = 1, 80 do
        many[i] = Raw({ at = Mock.now - i * 1000, victim = { name = "Victim Number" .. i } })
    end
    eq(RevengeTracker.SubmitForeign(many, "x"), 50)
end)
