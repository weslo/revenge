-- The SubmitForeign door: trust, validation, silence, hiding and the off switches.

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

local function Mark(kind, extra)
    local record = { type = kind, target = { name = "Gorvak Ashmane", class = "ROGUE" }, by = { name = "Mira Thornwood" },
                     at = Mock.now - 600 }
    for k, v in pairs(extra or {}) do record[k] = v end
    return record
end

local function Submit(records, sender, channel, source)
    return RevengeTracker.SubmitForeign(records, source or "revengebook", sender, channel)
end

local function OnlyKill()
    eq(count(RevengeTrackerDB.kills), 1, "one kill")
    local _, kill = next(RevengeTrackerDB.kills)
    return kill
end

local function HoverGorvak()
    Mock.units.mouseover = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 }
    local lines = Mock.Hover("mouseover")
    for i, line in ipairs(lines) do lines[i] = line:gsub("^|T[^|]*|t ", "") end
    return lines
end

test("a guildmate's own death from another addon is accepted and tagged with its source", function()
    LoadAddon()
    eq(Submit({ Raw() }, "Mira", "GUILD"), 1)
    local kill = OnlyKill()
    ok(kill.sources.revengebook, "source tag")
    eq(kill.own, nil, "not Revenge's own")
    eq(kill.victim.name, "Mira Thornwood")
    eq(kill.killers[1].level, 41)
end)

test("junk never errors and is never stored", function()
    LoadAddon()
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
        Raw({ killers = { { name = "Anna Bright" } } }),   -- you can't be your guildmate's killer
        Mark("wanted", { at = 5 }),
        Mark("wanted", { target = { name = "Anna Bright" } }),  -- a mark on you
        Mark("withdrawal", { by = "Mira" }),
    }
    eq(Submit(junk, "Mira", "GUILD"), 0)
    eq(RevengeTracker.SubmitForeign("not a list", "revengebook", "Mira", "GUILD"), 0)
    eq(RevengeTracker.SubmitForeign(nil, nil), 0)
    eq(RevengeTracker.SubmitForeign({ Raw() }, { "bad id" }, "Mira", "GUILD"), 0)
    eq(RevengeTracker.Trusted(nil, {}), false)
    eq(RevengeTracker.IsSelf(Mock.SECRET), false)
    eq(count(RevengeTrackerDB.kills), 0)
    eq(count(RevengeTrackerDB.wanted), 0)
    eq(#Mock.chat, 0, "nothing printed")
end)

test("a non-player GUID and a class that isn't a class token are dropped, the name kept", function()
    LoadAddon()
    Submit({ Raw({ killers = { { name = "Gorvak Ashmane", guid = "Creature-0-1-2-3", class = "Schurke" } } }) }, "Mira", "GUILD")
    local kill = OnlyKill()
    eq(kill.killers[1].guid, nil)
    eq(kill.killers[1].class, nil)
    eq(kill.killers[1].name, "Gorvak Ashmane")
end)

test("out-of-range numbers are dropped, not trusted", function()
    LoadAddon()
    Submit({ Raw({ x = 5, y = 0.5, mapID = "1431", killers = { { name = "Gorvak Ashmane", level = 900 } } }) }, "Mira", "GUILD")
    local kill = OnlyKill()
    eq(kill.x, nil)
    eq(kill.y, nil, "half a position is no position")
    eq(kill.mapID, nil)
    eq(kill.killers[1].level, nil)
end)

test("at most 50 records are taken per call", function()
    LoadAddon()
    local many = {}
    for i = 1, 80 do many[i] = Raw({ at = Mock.now - i * 1000, victim = { name = "Victim Number" } }) end
    eq(Submit(many, nil, "SAVED"), 50)
end)

test("only the sender's own data counts, and never a stranger's", function()
    LoadAddon()
    eq(Submit({ Raw() }, "Tavish", "GUILD"), 0, "Mira's death from someone else")
    eq(Submit({ Mark("wanted") }, "Tavish", "GUILD"), 0, "Mira's mark from someone else")
    eq(Submit({ Raw() }, "Mira", "WHISPER"), 0, "a whisper from a stranger")
    eq(Submit({ Raw() }, "Mira", "PARTY"), 0, "a party member who isn't a guildmate or friend")
    eq(Submit({ Raw() }, "Mira", "CHANNEL"), 0, "a public channel")
    eq(Submit({ Raw() }, "Mira", nil), 0, "no channel")
    Mock.inGuild = false
    eq(Submit({ Raw() }, "Mira", "GUILD"), 0, "not in a guild")
    eq(count(RevengeTrackerDB.kills), 0)
    eq(count(RevengeTrackerDB.wanted), 0)
end)

test("friends by whisper, guildmates and friends in your group, and your own saved data count", function()
    LoadAddon()
    Mock.friendList = { { name = "Mira Thornwood", connected = true, guid = "Player-1-0000MIRA" } }
    eq(Submit({ Raw() }, "Mira", "WHISPER"), 1, "an in-game friend")
    Mock.units.party2 = { name = "Tavish", surname = "Brightforge", guid = "Player-1-0000TAVI", class = "WARRIOR" }
    Mock.guild["Player-1-0000TAVI"] = true
    eq(Submit({ Raw({ victim = { name = "Tavish Brightforge" } }) }, "Tavish", "PARTY"), 1, "a guildmate in your party")
    Mock.inRaid, Mock.groupSize = true, 3
    Mock.units.raid3 = { name = "Orin", surname = "Hale", guid = "Player-1-0000ORIN" }
    Mock.friends["Player-1-0000ORIN"] = true
    eq(Submit({ Raw({ victim = { name = "Orin Hale" } }) }, "Orin", "RAID"), 1, "a friend in your raid")
    eq(Submit({ Raw({ victim = { name = "Somebody Else" }, at = Mock.now - 9000 }) }, nil, "SAVED"), 1,
       "your own copy of the other addon's data")
    eq(count(RevengeTrackerDB.kills), 4)
end)

test("Wanted marks and withdrawals from other addons", function()
    LoadAddon()
    eq(Submit({ Mark("wanted") }, "Mira", "GUILD"), 1)
    local lines = HoverGorvak()
    eq(lines[#lines], "Wanted by Mira")
    eq(Submit({ Mark("withdrawal", { at = Mock.now }) }, "Mira", "GUILD"), 1)
    eq(count(RevengeTrackerDB.wanted), 0, "taken back")
    eq(Submit({ Mark("wanted") }, "Mira", "GUILD"), 0, "an older copy arriving later stays taken back")
    eq(Submit({ Mark("wanted", { at = Mock.now + 10 }) }, "Mira", "GUILD"), 1, "marked again later")
end)

test("marks from another addon lapse when it says they do; Revenge's own don't", function()
    local ns = LoadAddon()
    Submit({ Mark("wanted", { expires = Mock.now + 3600 }) }, "Mira", "GUILD")
    eq(#HoverGorvak(), 1)
    Mock.now = Mock.now + 3601
    eq(#HoverGorvak(), 0, "lapsed")
    ns.List.AddByName("Gorvak Ashmane")
    Submit({ Mark("wanted", { by = { name = "Anna Bright" }, expires = Mock.now + 60 }) }, nil, "SAVED")
    Mock.now = Mock.now + 120
    eq(#HoverGorvak(), 1, "your own mark keeps it")
end)

test("switched off: nothing is accepted, and what only other addons gave is hidden at once", function()
    local ns = LoadAddon()
    Submit({ Raw() }, "Mira", "GUILD")
    Submit({ Mark("wanted") }, "Mira", "GUILD")
    ns.Merge.SubmitKill({ victim = ns.Identity.Self(), killers = { { name = "Gorvak Ashmane", key = "gorvak ashmane" } },
                          at = Mock.now - 7200, precision = "exact", sources = { self = true }, own = true })
    eq(HoverGorvak()[1], "(2) You, Mira")
    local redraws = 0
    ns.OnChange(function() redraws = redraws + 1 end)
    SlashCmdList.REVENGETRACKER("others off")
    ok(redraws > 0, "redrawn at once")
    eq(table.concat(HoverGorvak(), " / "), "(1) You", "only your own kill shows")
    eq(Submit({ Raw({ victim = { name = "Tavish Brightforge" } }) }, "Tavish", "GUILD"), 0, "nothing more comes in")
    eq(#ns.List.Rows(), 1)
    SlashCmdList.REVENGETRACKER("others on")
    eq(HoverGorvak()[1], "(2) You, Mira", "back again")
end)

test("an addon switched off stops its data arriving, and only its own", function()
    LoadAddon()
    RevengeTrackerDB.settings.otherGrudgekeeper = false
    eq(Submit({ Raw() }, "Mira", "GUILD", "grudgekeeper"), 0)
    eq(Submit({ Raw() }, "Mira", "GUILD", "revengebook"), 1)
end)

test("Shift details say which other addon a kill came from, unless Revenge reported it too", function()
    local ns = LoadAddon()
    Submit({ Raw() }, "Mira", "GUILD")
    Mock.keys.shift = true
    local lines = HoverGorvak()
    eq(lines[2], "Mira Thornwood · Duskwood · 1m ago  |cff888888via Revenge Book|r")
    -- Mira's own Revenge reports the same death: it's Revenge's now, and Revenge's details win.
    ns.Merge.SubmitKill({ victim = { name = "Mira Thornwood", key = "mira thornwood" },
                          killers = { { name = "Gorvak Ashmane", key = "gorvak ashmane" } },
                          at = Mock.now - 50, precision = "exact", zone = "Duskwood", sources = { revenge = true }, own = true })
    lines = HoverGorvak()
    eq(lines[1], "(1) Mira", "one death, counted once")
    eq(lines[2], "Mira Thornwood · Duskwood · 1m ago")
    eq(OnlyKill().precision, "exact")
end)

test("a death arriving live alerts once; a catch-up copy and saved data don't", function()
    LoadAddon()
    Submit({ Raw({ live = true }) }, "Mira", "GUILD")
    Mock.Advance(1)
    eq(#Mock.chat, 1)
    ok(Mock.chat[1]:find("Mira Thornwood was killed by Gorvak Ashmane in Duskwood.", 1, true), Mock.chat[1])
    Mock.chat = {}
    Submit({ Raw({ live = true, zone = "Elsewhere" }) }, "Mira", "GUILD")
    Submit({ Raw({ victim = { name = "Tavish Brightforge" } }) }, "Tavish", "GUILD")
    Submit({ Raw({ live = true, victim = { name = "Orin Hale" } }) }, nil, "SAVED")
    Mock.Advance(1)
    eq(#Mock.chat, 0)
end)

test("many records together redraw once", function()
    local ns = LoadAddon()
    local redraws = 0
    ns.OnChange(function() redraws = redraws + 1 end)
    local many = {}
    for i = 1, 20 do many[i] = Raw({ victim = { name = "Victim Number" }, at = Mock.now - i * 1000 }) end
    eq(Submit(many, nil, "SAVED"), 20)
    eq(redraws, 1)
end)

test("Revenge never passes on what other addons gave it", function()
    local ns = LoadAddon()
    Submit({ Raw({ victim = { name = "Anna Bright" } }) }, nil, "SAVED")       -- your death, from another addon
    Submit({ Mark("wanted", { by = { name = "Anna Bright" } }) }, nil, "SAVED")  -- your mark, from another addon
    Mock.sent = {}
    Mock.Deliver(table.concat({ "H", "Mira Thornwood", "1-0000MIRA", tostring(Mock.now - 86400), "v0.1.0" }, "\t"), "Mira")
    Mock.Advance(15)
    for _, m in ipairs(Mock.sent) do ok(m.text:sub(1, 2) == "H\t", "only a hello went out: " .. m.text) end
    local lines = HoverGorvak()
    eq(lines[1], "(1) You", "but you see it")
    eq(lines[2], "Wanted by you")
    ns.List.Remove(ns.List.Rows()[1])
    for _, m in ipairs(Mock.sent) do ok(m.text:sub(1, 2) ~= "X\t", "no withdrawal shared for a mark Revenge never shared") end
end)

test("a list read whole drops the marks that only it gave, for players no longer on it", function()
    local ns = LoadAddon()
    local function Mine(name) return Mark("wanted", { target = { name = name }, by = { name = "Anna Bright" } }) end
    ns.List.AddByName("Darrok Vane")
    Submit({ Mine("Gorvak Ashmane"), Mine("Darrok Vane"), Mine("Shazra Vex") }, nil, "SAVED", "killonsight")
    Submit({ Mark("wanted", { target = { name = "Shazra Vex" } }) }, "Mira", "GUILD", "revengebook")
    eq(RevengeTracker.SyncMarks("killonsight", { "Gorvak Ashmane" }), 1,
       "your Kill on Sight mark on Shazra went; Darrok's is Revenge's own too, and Mira's isn't yours")
    local left = {}
    for _, mark in pairs(RevengeTrackerDB.wanted) do left[#left + 1] = mark.target.name .. "<" .. mark.by.name end
    table.sort(left)
    eq(table.concat(left, ", "), "Darrok Vane<Anna Bright, Gorvak Ashmane<Anna Bright, Shazra Vex<Mira Thornwood")
end)

test("data known only from other addons has its own cap", function()
    LoadAddon()
    local saved = RevengeTrackerDB
    for i = 1, 1005 do
        saved.kills["f" .. i] = { id = "f" .. i, at = Mock.now - i, precision = "client", victim = { key = "v", name = "V" },
                                  killers = { { key = "k", name = "K" } }, sources = { revengebook = true } }
    end
    saved.kills.own = { id = "own", at = Mock.now - 99999, victim = { key = "v" }, killers = { { key = "k" } },
                        sources = { self = true }, own = true }
    LoadAddon(saved)
    eq(count(RevengeTrackerDB.kills), 1001, "the oldest 5 foreign kills went; Revenge's own stayed")
    ok(RevengeTrackerDB.kills.own and RevengeTrackerDB.kills.f1000 and not RevengeTrackerDB.kills.f1001)
end)
