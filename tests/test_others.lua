-- The optional module RevengeTracker_OtherAddons (V-019): loading on demand, the
-- queue and its time budget, the circuit breakers, imports and status lines, tried
-- with deliberately broken fake adapters.

local MODULE = "RevengeTracker_OtherAddons"

-- Revenge after login, with the module loaded (it loads 5 seconds in).
local function Start(saved)
    local ns = LoadAddon(saved)
    Mock.Advance(5)
    return ns, Mock.module
end

-- A death report on `victim` (the sender) by Gorvak, as a fake adapter would return it.
local function Death(victim, ago)
    return { type = "kill", victim = { name = victim }, killers = { { name = "Gorvak Ashmane" } },
             at = Mock.now - (ago or 60), precision = "client" }
end

local function SenderName(sender)
    return ({ Mira = "Mira Thornwood", Tavish = "Tavish Brightforge" })[sender] or sender
end

-- A fake adapter on prefix "F_<id>": each message "ok" is a death of its sender.
local function Fake(id, decode, extra)
    local adapter = {
        id = id,
        prefixes = { "F_" .. id },
        channels = { GUILD = true },
        Decode = decode or function(_, text, _, sender)
            if text == "ok" then return { Death(SenderName(sender)) } end
            return nil
        end,
    }
    for k, v in pairs(extra or {}) do adapter[k] = v end
    return Mock.module.Register(adapter)
end

local function Send(id, text, sender, channel)
    Mock.Deliver(text, sender or "Mira", channel or "GUILD", "F_" .. id)
end

local function Status(ns)
    return table.concat(ns.Foreign.StatusLines(), " / ")
end

-- Revenge's own sharing still works: a guildmate's Revenge death arrives as before.
local function RevengeStillWorks()
    Mock.Deliver(table.concat({ "K", "Tavish Brightforge", "", "k1", tostring(Mock.now - 30), "1431", "420", "610", "",
                                "Shazra Vex", "", "", "" }, "\t"), "Tavish")
    for _, kill in pairs(RevengeTrackerDB.kills) do
        if kill.own and kill.victim.name == "Tavish Brightforge" then return true end
    end
    return false
end

test("with other addons in use, the module loads after Revenge's own start-up", function()
    local ns = LoadAddon()
    eq(Mock.loaded[MODULE], nil, "not yet")
    eq(Mock.prefixes.DeathNote, nil)
    Mock.Advance(5)
    ok(Mock.loaded[MODULE], "loaded")
    for _, prefix in ipairs({ "DeathNote", "Grudgekeeper", "HeadHunter" }) do ok(Mock.prefixes[prefix], prefix) end
    eq(Status(ns), "Revenge Book: listening / Grudgekeeper: listening / HeadHunter: listening / Kill on Sight: not loaded")
    eq(#Mock.chat, 0, "silently")
end)

test("switched off, the module isn't loaded after /reload and no other prefixes are registered", function()
    local ns = LoadAddon()
    SlashCmdList.REVENGETRACKER("others off")
    ok(Mock.chat[#Mock.chat]:find("Not using data from other addons", 1, true))
    ns = LoadAddon(RevengeTrackerDB)
    Mock.Advance(60)
    eq(Mock.loaded[MODULE], nil, "not loaded")
    eq(Mock.prefixes.DeathNote, nil)
    eq(Mock.prefixes.Grudgekeeper, nil)
    eq(Status(ns), 'Not in use: "Use data from other addons" is off.')
    SlashCmdList.REVENGETRACKER("others on")
    ok(Mock.loaded[MODULE], "switching it on loads it at once")
    eq(Mock.loadCount[MODULE], 1)
    SlashCmdList.REVENGETRACKER("others")
    ok(Mock.chat[#Mock.chat]:find("Kill on Sight: not loaded", 1, true), "status in chat when asked")
end)

test("the switch on the settings page loads the module at once", function()
    LoadAddon()
    RevengeTrackerDB.settings.otherAddons = false
    Mock.Advance(5)
    eq(Mock.loaded[MODULE], nil)
    RevengeTrackerDB.settings.otherAddons = true
    Mock.valueCallbacks.RevengeTracker_otherAddons()
    ok(Mock.loaded[MODULE])
end)

test("a missing or disabled module just says so", function()
    local ns = LoadAddon()
    Mock.addonFiles[MODULE] = nil
    Mock.Advance(5)
    eq(Status(ns), "Not installed: the RevengeTracker_OtherAddons folder is missing. Reinstall Revenge to get it.")
    ns = LoadAddon()
    Mock.disabled[MODULE] = true
    Mock.Advance(5)
    eq(Status(ns), "Turned off in the game's AddOns list (Revenge: other addons).")
    eq(#Mock.chat, 0)
end)

test("the module waits out combat before loading", function()
    LoadAddon()
    Mock.inCombat = true
    Mock.Advance(5)
    eq(Mock.loaded[MODULE], nil)
    Mock.inCombat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    ok(Mock.loaded[MODULE])
end)

test("the settings page shows how each addon is doing", function()
    local ns = Start()
    RevengeTrackerDB.settings.otherHeadHunter = false
    Mock.ShowSettings()
    eq(ns.OthersPanel.Text(), "Revenge Book: listening\nGrudgekeeper: listening\nHeadHunter: switched off\nKill on Sight: not loaded")
end)

test("an adapter that throws trips only its own breaker, silently", function()
    local ns = Start()
    local calls = 0
    local thrower = Fake("thrower", function() calls = calls + 1 error("boom") end)
    local good = Fake("good")
    for _ = 1, 8 do Send("thrower", "ok") end
    Send("good", "ok")
    Mock.Frames(20)
    eq(calls, 5, "stopped after 5 errors")
    ok(thrower.breaker.tripped, "tripped")
    ok(not good.breaker.tripped, "the other adapter isn't")
    eq(good.reports, 1)
    eq(#Mock.chat, 0, "nothing printed")
    ok(RevengeStillWorks(), "Revenge's own sharing")
    Send("thrower", "ok")
    Mock.Frames(5)
    eq(calls, 5, "messages for a tripped adapter aren't even queued")
    ok(ns.Foreign.module.Status().thrower.state == "paused")
end)

test("a flood of malformed messages: the queue stays bounded, the parse breaker trips, the frame budget holds", function()
    local ns = Start()
    local seen = 0
    local adapter = Fake("junk", function() seen = seen + 1 return nil end)
    adapter.channels.WHISPER = nil
    for i = 1, 500 do Send("junk", "junk" .. i, "Sender" .. i) end
    local worst = 0
    for _ = 1, 40 do
        local before = Mock.profile
        Mock.Frames(1)
        worst = math.max(worst, Mock.profile - before)
    end
    ok(worst <= 0.5 + 0.05, "at most about 0.5 ms a frame, got " .. worst)
    ok(adapter.breaker.tripped, "tripped")
    eq(adapter.breaker.why, "unparseable")
    eq(seen, 26, "it took 26 failures out of the last 50")
    ok(seen <= 200, "the oldest dropped from a full queue")
    eq(#Mock.chat, 0)
    ok(RevengeStillWorks())
end)

test("the queue holds 200 messages; when it's full the oldest go", function()
    Start()
    local order = {}
    Fake("fine", function(_, text)
        order[#order + 1] = tonumber(text)
        return {}
    end)
    Mock.inCombat = true
    for i = 1, 250 do Send("fine", tostring(i), "Sender" .. i) end
    Mock.inCombat = false
    Mock.Frames(100)
    eq(#order, 200)
    eq(order[1], 51, "the first 50 were dropped")
    eq(order[200], 250)
end)

test("a slow adapter overruns its budget three times and stops; one slow call per frame at most", function()
    Start()
    local calls = 0
    local slow = Fake("slow", function(_, _, _, sender)
        calls = calls + 1
        Mock.profile = Mock.profile + 5
        return { Death(SenderName(sender)) }
    end)
    for _ = 1, 6 do Send("slow", "ok") end
    Mock.Frames(1)
    eq(calls, 1, "one 5 ms call uses up the frame")
    Mock.Frames(10)
    eq(calls, 3)
    ok(slow.breaker.tripped)
    eq(slow.breaker.why, "slow")
end)

test("nothing runs in combat; it waits", function()
    Start()
    local good = Fake("good")
    Mock.inCombat = true
    Send("good", "ok")
    Mock.Frames(10)
    eq(good.reports, 0)
    Mock.inCombat = false
    Mock.Frames(1)
    eq(good.reports, 1)
end)

test("at most 20 records a second go to the merge; the rest wait", function()
    Start()
    Fake("many")
    local handed = 0
    local original = RevengeTracker.SubmitForeign
    RevengeTracker.SubmitForeign = function(records, ...) handed = handed + #records return original(records, ...) end
    for _ = 1, 30 do Send("many", "ok") end
    Mock.Frames(10, 0.05)
    eq(handed, 20, "20 in the first half second")
    Mock.Frames(20, 0.05)
    eq(handed, 30, "the rest a second later")
    RevengeTracker.SubmitForeign = original
end)

test("your own messages coming back, strangers and floods are dropped before any decoding", function()
    Start()
    local decoded = 0
    local adapter = Fake("echo", function(_, _, _, sender)
        decoded = decoded + 1
        return { Death(SenderName(sender)) }
    end, { channels = { GUILD = true, WHISPER = true } })
    Send("echo", "ok", "Anna")
    Send("echo", "ok", "Anna-Realm")
    Mock.Frames(3)
    eq(decoded, 0, "your own echo")
    Send("echo", "ok", "Mira", "WHISPER")
    Send("echo", "ok", "Mira", "PARTY")
    Mock.Frames(3)
    eq(decoded, 0, "a stranger's whisper, and a channel the adapter doesn't listen on")
    for _ = 1, 130 do Send("echo", "ok", "Mira") end
    Mock.Frames(100, 0.1)
    eq(decoded, 119, "at most 120 per sender in 10 minutes, the whisper among them")
    ok(not adapter.breaker.tripped)
end)

test("other addons' data stops at once when the switch goes off, though the module stays loaded", function()
    Start()
    local good = Fake("good")
    SlashCmdList.REVENGETRACKER("others off")
    Send("good", "ok")
    Mock.Frames(3)
    eq(good.reports, 0)
end)

test("saved-data imports: sliced, paused in combat, new entries only on later runs, stopped by a bad structure", function()
    local ns = Start()
    Mock.loaded.OtherOne = true
    local total = 60
    local unrecognised = false
    local reader = Mock.module.Register({
        id = "reader",
        addons = { "OtherOne" },
        Import = function(emit, pause)
            if unrecognised then return false end
            for i = 1, total do
                emit({ type = "kill", victim = { name = "Victim Number" }, killers = { { name = "Gorvak Ashmane" } },
                       at = Mock.now - i * 1000, precision = "client", fp = "e" .. i })
                if i % 10 == 0 then pause() end
            end
            return true
        end,
    })
    eq(ns.Foreign.module.Status().reader.state, "watching")
    Mock.Advance(20)                 -- the first round is due 20 seconds after loading
    Mock.inCombat = true
    Mock.Frames(200, 0.05)
    eq(count(RevengeTrackerDB.kills), 0, "not in combat")
    Mock.inCombat = false
    Mock.Frames(20, 0.05)            -- 20 records a second
    ok(reader.reports > 0 and reader.reports < 60, "a slice at a time: " .. reader.reports)
    Mock.Frames(100, 0.05)
    eq(reader.reports, 60)
    total = 65
    Mock.Advance(600)
    Mock.Frames(100, 0.05)
    eq(reader.reports, 65, "only the 5 new ones")
    unrecognised = true
    Mock.Advance(600)
    Mock.Frames(100, 0.05)
    ok(reader.importUnrecognised, "a structure it didn't recognise stops it for the session")
    ok(not reader.breaker.tripped, "but that isn't an error")
    eq(#Mock.chat, 0)
end)

test("an import that throws or runs long counts against its breaker", function()
    Start()
    Mock.loaded.OtherOne = true
    local runs = 0
    local bad = Mock.module.Register({
        id = "bad",
        addons = { "OtherOne" },
        Import = function()
            runs = runs + 1
            error("their saved data changed")
        end,
    })
    for _ = 1, 6 do
        Mock.Advance(600)
        Mock.Frames(60, 0.05)
    end
    eq(runs, 5)
    ok(bad.breaker.tripped)
end)
