-- The diagnostic log (V-020): off by default; while on, one line per event worth
-- reviewing later, bounded, never in chat, never able to break Revenge.

local HOSTILE_PLAYER = 0x0548
local HOSTILE_NPC = 0x0A48
local GORVAK_UNIT = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41, faction = "Horde" }
local MIRA = { name = "Mira", surname = "Thornwood", guid = "Player-1-0000MIRA", class = "MAGE", level = 40,
               guild = "Dawn Watch", faction = "Alliance" }
local ANNA = { name = "Anna", surname = "Bright", guid = "Player-1-AAAA0001", class = "PRIEST", level = 40,
               guild = "Dawn Watch", faction = "Alliance" }

local function Gorvak() return { name = "Gorvak Ashmane", key = "gorvak ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 } end

-- Revenge with the log on (as saved from an earlier session), logged in as `player`.
local function LogOn(player)
    local ns = LoadAddon({ settings = { diagnosticLog = true } }, true)
    if player then Mock.units.player = player end
    Mock.Fire("PLAYER_LOGIN")
    return ns
end

-- The log's lines as { at, kind, text }.
local function Lines()
    local out = {}
    for i, line in ipairs(RevengeTrackerDB.log or {}) do
        local at, kind, text = line:match("^(%d+) (%S+) (.*)$")
        out[i] = { at = tonumber(at), kind = kind, text = text, line = line }
    end
    return out
end

-- The texts of one kind's lines.
local function Texts(kind)
    local out = {}
    for _, line in ipairs(Lines()) do
        if line.kind == kind then out[#out + 1] = line.text end
    end
    return out
end

-- The one line of `kind` containing `part` (plain text); fails if there isn't exactly one.
local function One(kind, part)
    local found = {}
    for _, text in ipairs(Texts(kind)) do
        if text:find(part, 1, true) then found[#found + 1] = text end
    end
    eq(#found, 1, ("lines of %s with %q"):format(kind, part))
    return found[1]
end

local function SeeGorvak()
    Mock.units.target = GORVAK_UNIT
    Mock.Fire("PLAYER_TARGET_CHANGED")
    Mock.units.target = nil
end

local function Die(recap)
    Mock.recap = recap
    Mock.Fire("PLAYER_DEAD")
    Mock.recap = nil
end

local function KilledByGorvak()
    return { { sourceGUID = "Player-1-0000GORV", sourceName = "Gorvak", sourceFlags = HOSTILE_PLAYER,
               timestamp = Mock.now - 1, overkill = 50 } }
end

local function KillOnMe(ns, ago)
    return ns.Merge.SubmitKill({ victim = ns.Identity.Self(), killers = { Gorvak() }, at = Mock.now - (ago or 600),
                                 precision = "exact", mapID = 1431, x = 0.4, y = 0.6, zone = "Duskwood",
                                 sources = { self = true }, own = true })
end

---------------------------------------------------------------------------
test("the log is off by default: nothing is written or saved", function()
    local ns = LoadAddon()
    eq(RevengeTrackerDB.settings.diagnosticLog, false)
    SeeGorvak()
    Die(KilledByGorvak())
    ns.Log("death", "anything")
    Mock.Fire("PLAYER_LOGOUT")
    eq(RevengeTrackerDB.log, nil, "no log in saved data")
    eq(count(RevengeTrackerDB.kills), 1, "Revenge itself works as before")
end)

test("/revenge log on starts it with the session's setup; off keeps the lines; clear empties it", function()
    local ns = LoadAddon()
    SlashCmdList.REVENGETRACKER("log on")
    ok(Mock.chat[#Mock.chat]:find("Diagnostic log on", 1, true), "said so in chat")
    eq(RevengeTrackerDB.settings.diagnosticLog, true)
    local lines = Lines()
    eq(lines[1].kind, "log")
    eq(lines[1].text, "on (0 lines kept from before)")
    eq(lines[1].at, Mock.now, "server time")
    ok(One("session", "Revenge 0.1.0-test, client 1.60.1 (70938); Anna Bright, level 40, Alliance; in a guild: yes"))
    ok(One("session", "switches: sharing guild on, friends on, Battle.net on; alerts nearby on"))
    ok(One("session", "other addons on: Revenge Book on, Grudgekeeper on, HeadHunter on, Kill on Sight on"))
    local n = #RevengeTrackerDB.log
    SlashCmdList.REVENGETRACKER("log off")
    ok(Mock.chat[#Mock.chat]:find("Diagnostic log off", 1, true))
    ns.Log("death", "not written")
    eq(#RevengeTrackerDB.log, n, "nothing written while off; the lines stay")
    SlashCmdList.REVENGETRACKER("log")
    ok(Mock.chat[#Mock.chat]:find("Diagnostic log: off, " .. n .. " lines saved.", 1, true), Mock.chat[#Mock.chat])
    SlashCmdList.REVENGETRACKER("log clear")
    eq(#RevengeTrackerDB.log, 0)
    ok(Mock.chat[#Mock.chat]:find("cleared", 1, true))
end)

test("the settings page has the switch, last, under Troubleshooting", function()
    LoadAddon()
    local last = Mock.page[#Mock.page]
    eq(Mock.page[#Mock.page - 1].data.name, "Troubleshooting")
    eq(last.kind, "checkbox")
    eq(Mock.settings["RevengeTracker_diagnosticLog"].name, "Keep a diagnostic log")
    eq(Mock.settings["RevengeTracker_diagnosticLog"].default, false)
    RevengeTrackerDB.settings.diagnosticLog = true
    Mock.valueCallbacks["RevengeTracker_diagnosticLog"]()
    ok(One("log", "on"), "switching on from the page writes the setup too")
    ok(#Texts("session") == 3)
end)

test("with the log on, each login writes the setup, and logout says so", function()
    LogOn()
    eq(#Texts("session"), 3)
    Mock.Fire("PLAYER_LOGOUT")
    local lines = Lines()
    eq(lines[#lines].kind, "session")
    eq(lines[#lines].text, "logout")
end)

---------------------------------------------------------------------------
-- What gets a line
---------------------------------------------------------------------------
test("your deaths: recorded with killers, place and sharing, or not recorded and why", function()
    LogOn()
    SeeGorvak()
    Die(KilledByGorvak())
    eq(One("death", "recorded"), "recorded: killed by Gorvak Ashmane in Duskwood (map 1431, with position), new; 1 messages queued to share")
    eq(One("out", "your death"), "your death: 1 messages queued to guild")
    Mock.inInstance = true
    Die(KilledByGorvak())
    eq(One("death", "instance"), "not recorded: in an instance (party)")
    Mock.inInstance = false
    Die({ { sourceGUID = "Creature-0-1-2-3-4", sourceName = "Defias Bandit", sourceFlags = HOSTILE_NPC, timestamp = Mock.now } })
    eq(One("death", "no enemy"), "not recorded: no enemy player among the death recap's 1 hits, in Duskwood")
    Die(nil)
    Mock.Advance(5)
    eq(One("death", "no death recap"), "not recorded: no death recap in Duskwood")
    eq(#Mock.chat, 0, "nothing in chat")
end)

test("sharing: what goes out, what comes in by which route, and what's dropped and why", function()
    -- Mira's client records her death and says hello; Anna's receives both.
    local mira = LogOn(MIRA)
    Mock.units.target = GORVAK_UNIT
    Mock.Fire("PLAYER_TARGET_CHANGED")
    Mock.units.target = nil
    Die(KilledByGorvak())
    Mock.Advance(20)
    local sent = Mock.sent
    ok(One("out", "hello to the guild"), "Mira's hello")
    ok(mira)

    LogOn(ANNA)
    Mock.guild["Player-1-0000MIRA"] = true
    for _, m in ipairs(sent) do Mock.Deliver(m.text, "Mira", m.channel) end
    eq(One("in", "Mira Thornwood's death"),
        "Mira Thornwood's death by guild (live): killed by Gorvak Ashmane in Duskwood, new")
    ok(One("in", "hello from Mira Thornwood by guild, asking since"))
    Mock.Advance(1)
    eq(One("alert", "killed"), "killed: Mira Thornwood (guild) by Gorvak Ashmane in Duskwood (popup, chat)")
    Mock.Advance(10)
    ok(One("out", "answered the hello on guild"), "the answer")
    -- The same death again, a message about someone else, and junk.
    for _, m in ipairs(sent) do
        if m.text:sub(1, 1) == "K" then Mock.Deliver(m.text, "Mira", m.channel) end
    end
    ok(One("in", "already known"))
    for _, m in ipairs(sent) do
        if m.text:sub(1, 1) == "K" then Mock.Deliver(m.text, "Tavish", m.channel) end
    end
    eq(One("in", "not their own"), "dropped Tavish's message about Mira Thornwood by guild: not their own")
    Mock.Deliver("K\tjunk", "Mira", "GUILD")
    eq(One("in", "malformed"), "dropped a malformed message from Mira by guild")
    Mock.Deliver(sent[1].text, "Stranger", "WHISPER")
    eq(One("in", "whisper"), "dropped a whisper from Stranger, who isn't an online friend")
end)

test("alerts say how they showed; tooltips and skulls once per player; pins once per map and count", function()
    local ns = LogOn()
    KillOnMe(ns)
    SeeGorvak()
    eq(One("alert", "nearby"), "nearby: Gorvak Ashmane: (1) You (popup, chat, sound)")
    Mock.units.mouseover = GORVAK_UNIT
    Mock.Hover("mouseover")
    eq(One("tooltip", "Gorvak"), "Gorvak Ashmane: (1) You")
    Mock.Hover("mouseover")
    eq(#Texts("tooltip"), 1, "once per player per session")
    Mock.units.nameplate1 = GORVAK_UNIT
    Mock.plates.nameplate1 = CreateFrame("Frame")
    Mock.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    Mock.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    eq(One("skull", "Gorvak"), "Gorvak Ashmane: (1) You")
    Mock.ShowMap(1431)
    Mock.ShowMap(1431)
    eq(One("pins", "Duskwood"), "1 on Duskwood (map 1431)")
    Mock.ShowMap(1433)
    eq(#Texts("pins"), 1, "a map without pins isn't noted")
    RevengeTrackerDB.settings.alertPopup, RevengeTrackerDB.settings.alertChat = false, false
    Mock.Advance(301)
    SeeGorvak()
    ok(One("alert", "not shown: popup and chat are both off"))
end)

test("the list: marked Wanted, taken off, dismissed from the map", function()
    local ns = LogOn()
    ns.List.AddByName("Darrok Vane")
    eq(One("list", "marked"), "marked Darrok Vane Wanted by you")
    ok(One("out", "your Wanted mark on Darrok Vane: 1 messages queued to guild"))
    local kill = KillOnMe(ns)
    ns.MapPins.Dismiss(kill.id)
    eq(One("list", "dismissed"), "dismissed Anna Bright's death (killed by Gorvak Ashmane) from the map")
    local rows = ns.List.Rows()
    ns.List.Remove(rows[1])
    eq(One("list", "took"), "took Darrok Vane off the list")
    ok(One("out", "taking back your mark on Darrok Vane"))
end)

test("a friend found running Revenge gets one line", function()
    local ns = LogOn()
    local route = { key = "WHISPER:mira", name = "Mira Thornwood", channel = "WHISPER", target = "Mira" }
    ns.Friends.MarkPeer(route)
    ns.Friends.MarkPeer(route)
    eq(One("friends", "Mira"), "Mira Thornwood runs Revenge (in-game friend)")
end)

---------------------------------------------------------------------------
-- Other addons
---------------------------------------------------------------------------
local function RB(...) return table.concat({ "1", ... }, "\t") end

test("other addons: the module, each report, a summary of their messages, imports and breakers", function()
    local ns = LogOn()
    Mock.loaded.KillOnSight = true
    KillOnSightDB = { global = { data = { players = { ["darrok vane"] = { name = "Darrok Vane", addedAt = Mock.now - 60 } } } } }
    Mock.Advance(5)
    ok(One("others", "the module is loaded"))
    eq(One("others", "the module started"),
        "the module started; listening for revengebook, grudgekeeper, headhunter; other addons loaded here: killonsight")
    local t = tostring(Mock.now - 60)
    Mock.Deliver(RB("K", "Gorvak-Ashmane", "Gorvak Ashmane", "WARRIOR", "60", "Duskwood", t, "Mira Thornwood"), "Mira", "GUILD", "DeathNote")
    Mock.Deliver(RB("J", "anything"), "Mira", "GUILD", "DeathNote")
    Mock.Frames(3)
    eq(One("others", "Revenge Book from Mira"),
        "Revenge Book from Mira by GUILD: 1 of 1 taken: Mira Thornwood's death by Gorvak Ashmane in Duskwood: new, live")
    Mock.Advance(1)
    ok(One("alert", "killed: Mira Thornwood by Gorvak Ashmane"))
    -- Kill on Sight's list is read 20 seconds after the module starts.
    Mock.Advance(20)
    Mock.Frames(5)
    eq(One("others", "killonsight read"), "killonsight read its saved data: 1 new records handed over, 1 taken")
    Mock.Fire("PLAYER_LOGOUT")
    eq(One("others", "revengebook, last 10 minutes"),
        "revengebook, last 10 minutes or less: 2 messages, 1 of types Revenge doesn't use, 1 with reports; 1 records taken this session")
    ok(ns)
end)

test("other addons: a failing adapter's errors and its breaker get lines; repeats are counted", function()
    LogOn()
    Mock.Advance(5)
    local mod = Mock.module
    mod.Register({ id = "fake", prefixes = { "Fake" }, channels = { GUILD = true },
                   Decode = function() error("boom") end })
    for _ = 1, 6 do Mock.Deliver("x", "Mira", "GUILD", "Fake") end
    Mock.Frames(5)
    eq(One("others", "fake is paused"), "fake is paused for this session: errors")
    local errors = Texts("error")
    eq(#errors, 3, "the same error three times, then counted")
    ok(errors[1]:find("other addons: fake: ", 1, true) and errors[1]:find("boom", 1, true), errors[1])
    Mock.Fire("PLAYER_LOGOUT")
    ok(One("error", "(2 more times this session)"))
end)

---------------------------------------------------------------------------
-- Bounds and safety
---------------------------------------------------------------------------
test("errors Revenge catches get lines", function()
    local ns = LogOn()
    ns.On("SOME_EVENT", function() error("kaput") end)
    Mock.Fire("SOME_EVENT")
    local text = One("error", "kaput")
    ok(text:find("^SOME_EVENT handler error: "), text)
end)

test("the newest 2,000 lines are kept; junk in saved data goes at login", function()
    local ns = LogOn()
    RevengeTrackerDB.log = {}
    for i = 1, 2201 do ns.Log("x", "%d", i) end
    local log = RevengeTrackerDB.log
    eq(#log, 2000)
    ok(log[1]:find(" x 202$"), log[1])
    ok(log[2000]:find(" x 2201$"), log[2000])
    local saved = { settings = { diagnosticLog = true }, log = {} }
    for i = 1, 2500 do saved.log[i] = Mock.now .. " x " .. i end
    saved.log[2501] = 42
    LoadAddon(saved)
    log = RevengeTrackerDB.log
    eq(#log, 2003, "2,000 kept, then this session's three setup lines")
    ok(log[1]:find(" x 501$"), log[1])
    for _, line in ipairs(log) do eq(type(line), "string") end
    LoadAddon({ settings = { diagnosticLog = false }, log = "junk" })
    eq(RevengeTrackerDB.log, nil)
end)

test("lines never hold secrets, escape codes or line breaks, and long ones are cut", function()
    local ns = LogOn()
    RevengeTrackerDB.log = {}
    ns.Log("x", "%s and %s", Mock.SECRET, "a|cffff0000red\nline")
    ns.Log("x", "%s", string.rep("y", 500))
    ns.Log("x", "%d", "not a number")
    local texts = Texts("x")
    eq(texts[1], "- and a cffff0000red line")
    eq(#texts[2], 240)
    ok(texts[2]:find("%.%.%.$"))
    eq(texts[3], "%d", "a bad format writes the format itself")
end)

test("a broken log never breaks Revenge", function()
    local ns = LogOn()
    RevengeTrackerDB.log = setmetatable({}, { __newindex = function() error("no room") end })
    SeeGorvak()
    Die(KilledByGorvak())
    eq(count(RevengeTrackerDB.kills), 1, "the death is recorded")
    ns.Log("x", "still fine")
    RevengeTrackerDB.log = nil
    ns.Log("x", "a fresh log")
    eq(#RevengeTrackerDB.log, 1)
end)
