-- Sharing with in-game friends (whispers) and Battle.net friends (game data).

local HOSTILE_PLAYER = 0x0548
local MIRA_GUID = "Player-1-0000MIRA"

-- Anna, not in a guild, so only friends are in play.
local function LoadAnna(friendList, bnFriends)
    local ns = LoadAddon(nil, true)
    Mock.inGuild = false
    Mock.friendList = friendList or {}
    Mock.bnFriends = bnFriends or {}
    Mock.Fire("PLAYER_LOGIN")
    return ns
end

local function MiraFriend(connected)
    return { name = "Mira Thornwood", connected = connected ~= false, guid = MIRA_GUID }
end

local function BN(id, extra)
    local game = { gameAccountID = id, isOnline = true, clientProgram = "WoW", wowProjectID = 18,
                   characterName = "Mira", factionName = "Alliance", playerGuid = MIRA_GUID }
    for k, v in pairs(extra or {}) do game[k] = v end
    return game
end

local function Sent(seconds)
    Mock.Advance(seconds or 0)
    local out = Mock.sent
    Mock.sent = {}
    return out
end

local function Only(messages, kind)
    local out = {}
    for _, m in ipairs(messages) do
        if m.text:sub(1, 2) == kind .. "\t" then out[#out + 1] = m end
    end
    return out
end

local function MiraHello()
    return table.concat({ "H", "Mira Thornwood", "1-0000MIRA", tostring(Mock.now - 86400), "v" }, "\t")
end

local function MiraKill(id)
    return table.concat({ "K", "Mira Thornwood", "1-0000MIRA", id, tostring(Mock.now - 60), "1431", "", "", "",
                          "Gorvak Ashmane", "1-0000GORV", "ROGUE", "41" }, "\t")
end

local function AnnaDies()
    Mock.recap = { { sourceGUID = "Player-1-0000GORV", sourceName = "Gorvak", sourceFlags = HOSTILE_PLAYER,
                     timestamp = Mock.now - 1, overkill = 10 } }
    Mock.Fire("PLAYER_DEAD")
    Mock.recap = nil
end

---------------------------------------------------------------------------
test("an online friend gets a hello; once they answer, your deaths reach them by whisper", function()
    LoadAnna({ MiraFriend(), { name = "Orin Hale", connected = false, guid = "Player-1-0000ORIN" } })
    local hello = Only(Sent(40), "H")
    eq(#hello, 1, "one hello, to the friend who's online")
    eq(hello[1].channel, "WHISPER")
    eq(hello[1].target, "Mira Thornwood", "the name exactly as the friend list gives it")
    AnnaDies()
    eq(#Sent(), 0, "not a peer yet: nothing of yours goes to them")

    Mock.Deliver(MiraHello(), "Mira Thornwood", "WHISPER")
    local answer = Sent(10)
    eq(#Only(answer, "H"), 0, "already said hello")
    local deaths = Only(answer, "R")
    eq(#deaths, 1, "the answer, to Mira only")
    eq(deaths[1].channel, "WHISPER")
    eq(deaths[1].target, "Mira Thornwood")
    AnnaDies()  -- a second death, now that Mira is known to run Revenge
    local live = Sent()
    eq(#live, 0, "the recap's same death merges, so nothing new")
    Mock.Advance(300)
    Mock.recap = { { sourceGUID = "Player-1-0000SHAZ", sourceName = "Shazra", sourceFlags = HOSTILE_PLAYER,
                     timestamp = Mock.now - 1, overkill = 10 } }
    Mock.Fire("PLAYER_DEAD")
    live = Only(Sent(), "K")
    eq(#live, 1)
    eq(live[1].channel, "WHISPER")
end)

test("a friend's whispered death is taken; a stranger's whisper isn't", function()
    LoadAnna({ MiraFriend() })
    Mock.Deliver(MiraKill("k1"), "Tavish Brightforge", "WHISPER")   -- not a friend, and not Mira
    Mock.Deliver(MiraKill("k1"), "Mira Smith", "WHISPER")           -- a different Mira
    -- A stranger whispering their own death: the name fits, but they aren't a friend.
    Mock.Deliver(table.concat({ "K", "Tavish Brightforge", "1-0000TAVI", "k2", tostring(Mock.now - 60), "", "", "", "",
                                "Gorvak Ashmane", "1-0000GORV", "ROGUE", "41" }, "	"), "Tavish Brightforge", "WHISPER")
    eq(count(RevengeTrackerDB.kills), 0)
    Mock.Deliver(MiraKill("k1"), "Mira Thornwood", "WHISPER")
    eq(count(RevengeTrackerDB.kills), 1)
    local _, kill = next(RevengeTrackerDB.kills)
    eq(kill.victim.name, "Mira Thornwood")
end)

test("Battle.net friends on WoW: Forever and your faction get hellos; others don't", function()
    LoadAnna({}, {
        BN(7),
        BN(8, { wowProjectID = 1, characterName = "Zed" }),          -- retail
        BN(9, { factionName = "Horde", characterName = "Grom" }),     -- the other faction
        BN(10, { clientProgram = "App" }),                            -- the desktop app
        BN(11, { isOnline = false }),
    })
    local hellos = Only(Sent(40), "H")
    eq(#hellos, 1)
    eq(hellos[1].channel, "BN")
    eq(hellos[1].target, 7)
end)

test("a Battle.net friend's data is taken only from an account Revenge shares with", function()
    LoadAnna({}, { BN(7), BN(9, { factionName = "Horde", characterName = "Mira" }) })
    Mock.DeliverBN(MiraKill("k1"), 9)
    Mock.DeliverBN(MiraKill("k1"), 42)  -- not a friend at all
    eq(count(RevengeTrackerDB.kills), 0)
    Mock.DeliverBN(MiraKill("k1"), 7)
    eq(count(RevengeTrackerDB.kills), 1)
    -- Mira is now known to run Revenge: Anna's deaths go to her over Battle.net.
    Sent(40)
    AnnaDies()
    local live = Only(Sent(), "K")
    eq(#live, 1)
    eq(live[1].channel, "BN")
    eq(live[1].target, 7)
end)

test("a friend's hello gets a hello back, so they answer you too", function()
    LoadAnna({ MiraFriend() })
    Mock.Advance(2)  -- scanned, but Anna's own hello isn't due yet
    Mock.Deliver(MiraHello(), "Mira Thornwood", "WHISPER")
    local sent = Sent(10)
    eq(#Only(sent, "H"), 1, "hello back at once")
    eq(#Sent(60), 0, "and not again when Anna's own hello comes due")
end)

test("a friend who's also a guildmate is reached through the guild only", function()
    local ns = LoadAddon(nil, true)
    Mock.friendList = { MiraFriend() }
    Mock.guild[MIRA_GUID] = true
    Mock.Fire("PLAYER_LOGIN")
    local hellos = Only(Sent(40), "H")
    eq(#hellos, 1)
    eq(hellos[1].channel, "GUILD", "no whispered hello to a guildmate")
    Mock.Deliver(MiraHello(), "Mira Thornwood", "WHISPER")
    Sent(10)
    AnnaDies()
    local live = Only(Sent(), "K")
    eq(#live, 1, "one copy")
    eq(live[1].channel, "GUILD")
    ok(ns)
end)

test("each channel has its own switch; you still hear friends with yours off", function()
    LoadAnna({ MiraFriend() }, { BN(7, { characterName = "Tavish", playerGuid = "Player-1-0000TAVI" }) })
    Mock.Deliver(MiraHello(), "Mira Thornwood", "WHISPER")
    Mock.DeliverBN(table.concat({ "H", "Tavish Brightforge", "1-0000TAVI", tostring(Mock.now - 86400), "v" }, "\t"), 7)
    Sent(60)
    RevengeTrackerDB.settings.shareFriends = false
    AnnaDies()
    local live = Only(Sent(), "K")
    eq(#live, 1, "Battle.net only")
    eq(live[1].channel, "BN")
    RevengeTrackerDB.settings.shareBattleNet = false
    Mock.Advance(300)
    Mock.recap = { { sourceGUID = "Player-1-0000SHAZ", sourceName = "Shazra", sourceFlags = HOSTILE_PLAYER,
                     timestamp = Mock.now - 1, overkill = 10 } }
    Mock.Fire("PLAYER_DEAD")
    eq(#Sent(), 0, "both off: nothing")
    Mock.Deliver(MiraKill("k3"), "Mira Thornwood", "WHISPER")
    ok(next(RevengeTrackerDB.kills), "still received")
end)

test("a friend who goes offline stops getting your messages", function()
    LoadAnna({ MiraFriend() })
    Mock.Deliver(MiraHello(), "Mira Thornwood", "WHISPER")
    Sent(60)
    Mock.friendList = { MiraFriend(false) }
    Mock.Fire("FRIENDLIST_UPDATE")
    Mock.Advance(2)
    AnnaDies()
    eq(#Sent(), 0)
    Mock.Deliver(MiraKill("k4"), "Mira Thornwood", "WHISPER")
    eq(count(RevengeTrackerDB.kills), 1, "only Anna's own death: an offline friend's whisper isn't taken")
end)

test("hellos are capped, and a friend who comes online later gets one", function()
    local list = {}
    for i = 1, 40 do
        list[i] = { name = string.format("Friend%d Number", i), connected = true,
                    guid = string.format("Player-1-%08X", i) }
    end
    LoadAnna(list)
    eq(#Only(Sent(60), "H"), 30, "at most 30 hellos in 10 minutes")
    Mock.friendList = { MiraFriend() }
    Mock.Fire("FRIENDLIST_UPDATE")
    Mock.Advance(600)
    Mock.friendList = { MiraFriend(), { name = "Tavish Brightforge", connected = true, guid = "Player-1-0000TAVI" } }
    Mock.Fire("FRIENDLIST_UPDATE")
    local later = Only(Sent(60), "H")
    eq(#later, 2, "Mira, once the cap allowed, and Tavish")
end)
