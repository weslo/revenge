-- Guild sharing and catch-up: one client's real messages, delivered to another's.

local HOSTILE_PLAYER = 0x0548

local function Player(name, surname, guid, class)
    return { name = name, surname = surname, guid = guid, class = class or "MAGE", level = 40,
             guild = "Dawn Watch", faction = "Alliance" }
end
local ANNA = Player("Anna", "Bright", "Player-1-AAAA0001", "PRIEST")
local MIRA = Player("Mira", "Thornwood", "Player-1-0000MIRA")
local TAVISH = Player("Tavish", "Brightforge", "Player-1-0000TAVI", "WARRIOR")

local function Gorvak() return { name = "Gorvak Ashmane", key = "gorvak ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 } end

-- Loads Revenge as `player`, with saved data.
local function LoadAs(player, saved)
    local ns = LoadAddon(saved, true)
    Mock.units.player = player
    Mock.Fire("PLAYER_LOGIN")
    return ns
end

-- What Revenge sent within `seconds` (default 0: what goes out at once), then forgets it.
local function Sent(seconds)
    Mock.Advance(seconds or 0)
    local out = Mock.sent
    Mock.sent = {}
    return out
end

local function OfType(messages, kind)
    local out = {}
    for _, m in ipairs(messages) do
        if m.text:sub(1, 2) == kind .. "\t" then out[#out + 1] = m end
    end
    return out
end

-- Messages other than hellos.
local function NotHellos(messages)
    local out = {}
    for _, m in ipairs(messages) do
        if m.text:sub(1, 2) ~= "H	" then out[#out + 1] = m end
    end
    return out
end

local function Deliver(messages, sender)
    for _, m in ipairs(messages) do Mock.Deliver(m.text, sender, m.channel) end
end

local function Strip(line) return line and (line:gsub("^|T[^|]*|t ", "")) end

local function HoverGorvak()
    Mock.units.target = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 }
    local lines = Mock.Hover("target")
    Mock.units.target = nil
    return lines
end

-- Anna dies to Gorvak (and anyone else in `extra`), recorded from the death recap.
-- She saw Gorvak beforehand, so her cache knows his full name.
local function AnnaDies(extra)
    Mock.units.target = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE",
                          level = 41, faction = "Horde" }
    Mock.Fire("PLAYER_TARGET_CHANGED")
    Mock.units.target = nil
    Mock.recap = { { sourceGUID = "Player-1-0000GORV", sourceName = "Gorvak", sourceFlags = HOSTILE_PLAYER,
                     timestamp = Mock.now - 1, overkill = 50 } }
    for _, hit in ipairs(extra or {}) do table.insert(Mock.recap, hit) end
    Mock.Fire("PLAYER_DEAD")
    Mock.recap = nil
end

local function OnlyKill()
    local id, kill = next(RevengeTrackerDB.kills)
    ok(id and not next(RevengeTrackerDB.kills, id), "exactly one kill")
    return kill
end

---------------------------------------------------------------------------
test("your death goes to the guild at once, and shows on the killer's tooltip for a guildmate", function()
    LoadAs(ANNA)
    AnnaDies()
    local sent = Sent()
    eq(#sent, 1)
    eq(sent[1].prefix, "RVNG1")
    eq(sent[1].channel, "GUILD")
    ok(sent[1].text:find("^K\tAnna Bright\t1%-AAAA0001\tk%d+\t"), sent[1].text)

    LoadAs(MIRA)
    Mock.guild["Player-1-AAAA0001"] = true
    Deliver(sent, "Anna")
    local kill = OnlyKill()
    eq(kill.victim.name, "Anna Bright")
    eq(kill.killers[1].name, "Gorvak Ashmane")
    eq(kill.killers[1].class, "ROGUE")
    ok(kill.sources.revenge, "source")
    eq(kill.zone, "Duskwood", "zone named from the map ID")
    eq(kill.x, 0.42)
    local lines = HoverGorvak()
    eq(Strip(lines[1]), "(1) Anna")
    Mock.keys.shift = true
    lines = HoverGorvak()
    eq(lines[2], "Anna Bright (guild) · Duskwood · 1m ago")
end)

test("a repeated death changes nothing, live or in an answer", function()
    LoadAs(ANNA)
    AnnaDies()
    local sent = Sent()
    LoadAs(MIRA)
    Deliver(sent, "Anna")
    Deliver(sent, "Anna-Realm")
    local answer = { { text = sent[1].text:gsub("^K", "R"), channel = "GUILD" } }
    Deliver(answer, "Anna Bright")
    eq(#OnlyKill().killers, 1)
    eq(Strip(HoverGorvak()[1]), "(1) Anna")
end)

test("a death with killers that don't fit in one message arrives as one kill", function()
    LoadAs(ANNA)
    local extra = {}
    for i = 1, 6 do
        local guid = string.format("Player-1-0000%04X", i)
        RevengeTrackerDB.names[guid] = { n = "Longername" .. string.char(96 + i) .. " Ofthehordeclan", c = "WARRIOR",
                                         l = 60, t = Mock.now }
        extra[#extra + 1] = { sourceGUID = guid, sourceName = "Longername", sourceFlags = HOSTILE_PLAYER,
                              timestamp = Mock.now - 2 }
    end
    AnnaDies(extra)
    local sent = Sent()
    ok(#sent >= 2, "split across messages: " .. #sent)
    for _, m in ipairs(sent) do ok(#m.text <= 255, "fits: " .. #m.text) end
    LoadAs(MIRA)
    Deliver(sent, "Anna")
    eq(#OnlyKill().killers, 7)
end)

test("only the sender's own data is taken, from the guild channel", function()
    LoadAs(ANNA)
    AnnaDies()
    local sent = Sent()
    LoadAs(MIRA)
    Deliver(sent, "Tavish")                                  -- Tavish passing on Anna's death
    Deliver(sent, "Anna Smith")                              -- a different Anna
    Mock.Deliver(sent[1].text, "Anna", "WHISPER")            -- whispers wait for friends sharing
    Mock.Deliver(sent[1].text, "Anna", "GUILD", "OtherAddon")
    eq(count(RevengeTrackerDB.kills), 0)
    Deliver(sent, "Anna Bright-Realm")
    eq(count(RevengeTrackerDB.kills), 1, "the real sender")
end)

test("your own messages coming back are ignored, so you never answer yourself", function()
    LoadAs(ANNA)
    AnnaDies()
    local sent = Sent()
    local hello = OfType(Sent(20), "H")
    eq(#hello, 1)
    -- The game hands you your own guild messages too.
    Deliver(sent, "Anna")
    Deliver(hello, "Anna")
    eq(count(RevengeTrackerDB.kills), 1, "still just the one you recorded")
    eq(#Sent(60), 0, "no answer to your own hello")
end)

test("junk never errors and is never stored", function()
    local ns = LoadAs(MIRA)
    local now = tostring(Mock.now)
    local junk = {
        "", "\t\t\t", "K", "Z\tAnna Bright\t\t1", "K\tAnna Bright",
        "K\tAnna Bright\t1-AAAA0001\tk1\t" .. now .. "\t1431\t420\t610\t\tGorvak Ashmane\t1-0000GORV\tROGUE",
        "K\tAnna Bright\t1-AAAA0001\tk1\tsoon\t1431\t420\t610\t\tGorvak Ashmane\t1-0000GORV\tROGUE\t41",
        "K\tAnna Bright\t1-AAAA0001\tk1\t" .. now .. "\t1431\t420\t\t\tGorvak Ashmane\t1-0000GORV\tROGUE\t41",
        "K\tAnna Bright\t1-AAAA0001\tk1\t" .. now .. "\t1431\t420\t610\t\tGor|cffvak\t1-0000GORV\tROGUE\t41",
        "K\tAnna Bright\tCreature-0\tk1\t" .. now .. "\t1431\t420\t610\t\tGorvak Ashmane\t1-0000GORV\tROGUE\t41",
        "K\tAnna Bright\t1-AAAA0001\tk1\t" .. tostring(Mock.now + 3600) .. "\t\t\t\t\tGorvak Ashmane\t\t\t",
        "K\tAnna Bright\t1-AAAA0001\tk1\t" .. tostring(Mock.now - 40 * 86400) .. "\t\t\t\t\tGorvak Ashmane\t\t\t",
        "K\tAnna Bright\t1-AAAA0001\tx1\t" .. now .. "\t\t\t\t\tGorvak Ashmane\t\t\t",
        "M\tAnna Bright\t1-AAAA0001\t" .. now .. "\tGorvak Ashmane\t\tROGUE",
        "M\tAnna Bright\t1-AAAA0001\t" .. now .. "\tGorvak\nAshmane\t\t\t",
        "X\tAnna Bright\t1-AAAA0001\t" .. now,
        "H\tAnna Bright\t1-AAAA0001\tlater\tv1",
        string.rep("K\t", 200),
        "K\tAnna Bright\t1-AAAA0001\tk1\t" .. now .. "\t\t\t\t\t" .. string.rep("Gorvak Ashmane\t\t\t\t", 6) .. "x",
    }
    for _, text in ipairs(junk) do
        eq(ns.Protocol.Decode(text) ~= nil and text:find(tostring(Mock.now + 3600), 1, true) == nil
            and text:find(tostring(Mock.now - 40 * 86400), 1, true) == nil, false, "decodes: " .. text:sub(1, 40))
        Mock.Deliver(text, "Anna")
    end
    Mock.Deliver(nil, "Anna")
    Mock.Deliver(Mock.SECRET, "Anna")
    Mock.Deliver("H\tAnna Bright\t\t1\t", Mock.SECRET)
    eq(count(RevengeTrackerDB.kills), 0)
    eq(count(RevengeTrackerDB.wanted), 0)
    eq(#Mock.chat, 0, "nothing printed")
    eq(#Sent(30), 1, "only Mira's own hello")
end)

test("a flood from one guildmate is capped", function()
    LoadAs(MIRA)
    for i = 1, 200 do
        Mock.Deliver(table.concat({ "K", "Anna Bright", "", "k" .. i, tostring(Mock.now - i * 300), "", "", "", "",
                                    "Gorvak Ashmane", "1-0000GORV", "ROGUE", "41" }, "\t"), "Anna")
    end
    eq(count(RevengeTrackerDB.kills), 80, "per guildmate, per 10 minutes")
    Mock.Advance(601)
    Mock.Deliver(table.concat({ "K", "Anna Bright", "", "k999", tostring(Mock.now - 30), "", "", "", "",
                                "Gorvak Ashmane", "1-0000GORV", "ROGUE", "41" }, "\t"), "Anna")
    eq(count(RevengeTrackerDB.kills), 81, "and again after the window")
end)

test("Wanted marks and withdrawals are shared, and a withdrawal beats older copies", function()
    local nsA = LoadAs(ANNA)
    ok(nsA.List.AddByName("Gorvak Ashmane"))
    local added = Sent()
    eq(#added, 1)
    ok(added[1].text:find("^M\tAnna Bright\t1%-AAAA0001\t%d+\tGorvak Ashmane\t"), added[1].text)
    Sent(60)  -- Anna's hello goes out meanwhile
    nsA.List.Remove(nsA.List.Rows()[1])
    local withdrawn = Sent()
    eq(#withdrawn, 1)
    ok(withdrawn[1].text:find("^X\tAnna Bright\t"), withdrawn[1].text)

    local nsM = LoadAs(MIRA)
    Deliver(added, "Anna")
    local lines = HoverGorvak()
    eq(Strip(lines[1]), "Wanted by Anna")
    Deliver(withdrawn, "Anna")
    eq(#HoverGorvak(), 0, "withdrawn")
    Deliver(added, "Anna")
    eq(#HoverGorvak(), 0, "the older copy is refused")
    eq(count(RevengeTrackerDB.wanted), 0)
    ok(nsM)
end)

test("with guild sharing off, nothing of yours is sent, but you still hear guildmates", function()
    local ns = LoadAs(ANNA)
    RevengeTrackerDB.settings.shareGuild = false
    AnnaDies()
    ns.List.AddByName("Shazra Vex")
    Mock.Deliver(table.concat({ "H", "Mira Thornwood", "1-0000MIRA", tostring(Mock.now - 86400), "v" }, "\t"), "Mira")
    local sent = Sent(60)
    eq(#sent, 1, "only the hello")
    ok(sent[1].text:find("^H\tAnna Bright\t"), sent[1].text)
    Mock.Deliver(table.concat({ "M", "Mira Thornwood", "1-0000MIRA", tostring(Mock.now), "Gorvak Ashmane",
                                "1-0000GORV", "ROGUE", "41" }, "\t"), "Mira")
    eq(Strip(HoverGorvak()[2]), "Wanted by Mira", "received while sharing is off")
end)

test("test kills stay with you unless you share them on purpose", function()
    LoadAs(ANNA)
    Mock.units.target = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 }
    SlashCmdList.REVENGETRACKER("test")
    eq(#Sent(), 0, "a plain test kill isn't sent")
    SlashCmdList.REVENGETRACKER("test share")
    local sent = Sent()
    eq(#sent, 1)
    ok(Mock.chat[#Mock.chat]:find("sent it to guildmates", 1, true), Mock.chat[#Mock.chat])
    ok(sent[1].text:find("\tt\tGorvak Ashmane\t", 1, true), "flagged as a test: " .. sent[1].text)

    LoadAs(MIRA)
    Deliver(sent, "Anna")
    local kill = OnlyKill()
    eq(kill.test, true)
    SlashCmdList.REVENGETRACKER("test clear")
    eq(count(RevengeTrackerDB.kills), 0, "cleared like your own test kills")
end)

test("/revenge test share says so when it can't send", function()
    LoadAs(ANNA)
    Mock.inGuild = false
    Mock.units.target = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 }
    SlashCmdList.REVENGETRACKER("test share")
    ok(Mock.chat[#Mock.chat]:find("didn't send it", 1, true), Mock.chat[#Mock.chat])
    eq(#Sent(), 0)
end)

---------------------------------------------------------------------------
-- Catch-up
---------------------------------------------------------------------------
-- Anna's saved data: deaths 2 hours and 3 days ago, an old test kill, a Wanted
-- mark, and a withdrawal from last week.
local function AnnaWithHistory()
    local ns = LoadAs(ANNA)
    local me = { name = "Anna Bright", key = "anna bright", guid = "Player-1-AAAA0001" }
    for _, ago in ipairs({ 2 * 3600, 3 * 86400 }) do
        ns.Merge.SubmitKill({ victim = me, killers = { Gorvak() }, at = Mock.now - ago, precision = "exact",
                              mapID = 1433, sources = { self = true }, own = true })
    end
    ns.Merge.SubmitKill({ victim = me, killers = { Gorvak() }, at = Mock.now - 3600, precision = "exact",
                          sources = { self = true }, own = true, test = true })
    ns.List.AddByName("Shazra Vex")
    RevengeTrackerDB.withdrawals["darrok vane|anna bright"] = Mock.now - 7 * 86400
    RevengeTrackerDB.withdrawals["orin hale|mira thornwood"] = Mock.now - 86400  -- not Anna's
    Sent()
    return ns
end

local function Hello(name, guid, since)
    return table.concat({ "H", name, guid, tostring(math.floor(since)), "v0.1.0" }, "\t")
end

test("a guildmate's hello is answered with your own deaths since then, your marks and withdrawals", function()
    AnnaWithHistory()
    Mock.Deliver(Hello("Mira Thornwood", "1-0000MIRA", Mock.now - 86400), "Mira")
    eq(#Sent(1), 0, "answers wait a moment")
    local answer = Sent(10)
    eq(#OfType(answer, "R"), 1, "only the death since then, and not the test kill")
    eq(#OfType(answer, "M"), 1)
    eq(#OfType(answer, "X"), 1, "only Anna's own withdrawal")
    eq(#OfType(answer, "K"), 0)
    for _, m in ipairs(answer) do eq(m.channel, "GUILD") end

    LoadAs(MIRA)
    RevengeTrackerDB.wanted = RevengeTrackerDB.wanted or {}
    Deliver(answer, "Anna")
    local kill = OnlyKill()
    eq(kill.at, Mock.now - 2 * 3600, "the 2-hour-old death, as it happened")
    eq(kill.zone, "Redridge Mountains")
    eq(count(RevengeTrackerDB.wanted), 1)
    ok(RevengeTrackerDB.withdrawals["darrok vane|anna bright"], "the withdrawal is remembered")
end)

test("answers to several hellos are merged, and a repeated hello waits 5 minutes", function()
    AnnaWithHistory()
    Mock.Deliver(Hello("Mira Thornwood", "1-0000MIRA", Mock.now - 86400), "Mira")
    Mock.Deliver(Hello("Tavish Brightforge", "1-0000TAVI", Mock.now - 4 * 86400), "Tavish")
    local answer = Sent(10)
    eq(#OfType(answer, "R"), 2, "one answer, back to the earlier since")
    Mock.Deliver(Hello("Mira Thornwood", "1-0000MIRA", Mock.now - 86400), "Mira")
    eq(#NotHellos(Sent(30)), 0, "Mira just got an answer")
    Mock.Advance(300)
    Mock.Deliver(Hello("Mira Thornwood", "1-0000MIRA", Mock.now - 86400), "Mira")
    eq(#OfType(Sent(30), "R"), 1, "answered again later")
end)

test("after login, your hello asks for what's new since you were last online", function()
    LoadAs(MIRA)
    local hello = Sent(20)
    eq(#hello, 1)
    local since = tonumber(hello[1].text:match("^H\tMira Thornwood\t1%-0000MIRA\t(%d+)\t"))
    eq(since, Mock.now - 20 - 7 * 86400, "first time: your whole expiry")
    eq(#Sent(600), 0, "one hello per session")
    Mock.Fire("PLAYER_LOGOUT")
    local lastSeen = RevengeTrackerDB.lastSeen
    eq(lastSeen, Mock.now)

    local saved = RevengeTrackerDB
    LoadAs(MIRA, saved)
    Mock.now = lastSeen + 3 * 86400
    since = tonumber(Sent(20)[1].text:match("^H\t[^\t]+\t[^\t]*\t(%d+)\t"))
    eq(since, lastSeen - 600, "since you were last online, less 10 minutes")
end)

test("a hello waits for the guild; without one, nothing is sent", function()
    LoadAs(MIRA)
    Mock.inGuild = false
    eq(#Sent(30), 0)
    Mock.inGuild = true
    Mock.Fire("PLAYER_GUILD_UPDATE", "player")
    eq(#OfType(Sent(30), "H"), 1, "sent once you're in a guild")
end)

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
test("sending waits out combat and the game's lockdown, and backs off when throttled", function()
    local ns = LoadAs(ANNA)
    Mock.inCombat = true
    AnnaDies()
    eq(#Sent(10), 0, "nothing in combat")
    Mock.inCombat = false
    Mock.chatLockdown = true
    eq(#Sent(30), 0, "nothing while addon chat is locked")
    Mock.chatLockdown = false
    eq(#OfType(Sent(30), "K"), 1, "sent once it's clear")

    Mock.sendResults = { 3, 3 }   -- throttled twice
    ns.List.AddByName("Gorvak Ashmane")
    eq(#Sent(1), 0)
    eq(#Sent(10), 1, "then sent")
    Mock.sendResults = { 7 }      -- an invalid channel: waiting won't help
    ns.List.AddByName("Shazra Vex")
    eq(#Sent(60), 0, "dropped")
    eq(ns.Share.QueueLength(), 0)
end)

test("a burst goes out at once, then one message a second", function()
    local ns = LoadAs(ANNA)
    for i = 1, 12 do
        ns.Share.OwnWanted({ target = { name = "Enemy Number" .. string.char(96 + i), key = "x" .. i },
                             by = ns.Identity.Self(), at = Mock.now })
    end
    eq(#Sent(0), 8)
    eq(#Sent(2), 2)
    eq(#Sent(5), 2)
end)

---------------------------------------------------------------------------
test("a guildmate's full names fill gaps in your name cache", function()
    local ns = LoadAs(MIRA)
    -- Mira's own death: the recap gave only "Gorvak".
    ns.Merge.SubmitKill({ victim = ns.Identity.Self(), killers = { { name = "Gorvak", key = "gorvak", guid = "Player-1-0000GORV", partial = true } },
                          at = Mock.now - 600, precision = "exact", sources = { self = true }, own = true })
    Mock.Deliver(table.concat({ "K", "Anna Bright", "1-AAAA0001", "k7", tostring(Mock.now - 60), "1431", "", "", "",
                                "Gorvak Ashmane", "1-0000GORV", "ROGUE", "41" }, "\t"), "Anna")
    eq(RevengeTrackerDB.names["Player-1-0000GORV"].n, "Gorvak Ashmane")
    for _, kill in pairs(RevengeTrackerDB.kills) do
        eq(kill.killers[1].name, "Gorvak Ashmane", "Mira's own kill upgraded too")
    end
end)

test("Protocol round trip: what one side encodes, the other decodes", function()
    local ns = LoadAs(ANNA)
    local P = ns.Protocol
    local me = { name = "Anna Bright", guid = "Player-1-AAAA0001" }
    local kill = { id = "k12", at = 1795600000, mapID = 1431, x = 0.4237, y = 0.6, test = true,
                   killers = { { name = "Gorvak Ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 },
                               { name = "Zoë Ñandú", class = "HUNTER" } } }
    local texts = P.Kill("K", me, kill)
    eq(#texts, 1)
    local msg = P.Decode(texts[1])
    eq(msg.type, "K")
    eq(msg.name, "Anna Bright")
    eq(msg.guid, "Player-1-AAAA0001")
    eq(msg.id, "k12")
    eq(msg.at, 1795600000)
    eq(msg.mapID, 1431)
    eq(msg.x, 0.424)
    eq(msg.y, 0.6)
    eq(msg.test, true)
    eq(#msg.killers, 2)
    eq(msg.killers[1].guid, "Player-1-0000GORV")
    eq(msg.killers[1].level, 41)
    eq(msg.killers[2].name, "Zoë Ñandú")
    eq(msg.killers[2].guid, nil)
    eq(msg.killers[2].level, nil)

    msg = P.Decode(P.Wanted(me, { at = 1795600000, target = { name = "Shazra Vex", class = "HUNTER", level = 39 } }))
    eq(msg.type, "M")
    eq(msg.target.name, "Shazra Vex")
    eq(msg.target.level, 39)
    msg = P.Decode(P.Withdrawal(me, "shazra vex", 1795600001))
    eq(msg.type, "X")
    eq(msg.target.name, "shazra vex")
    msg = P.Decode(P.Hello(me, 1795500000, "@project-version@"))
    eq(msg.since, 1795500000)
    eq(P.Kill("K", { name = "Bad|Name" }, kill)[1], nil, "no sender name, no message")
end)
