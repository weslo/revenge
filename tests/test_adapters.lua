-- The adapters (V-015 to V-018), offline: sample messages and saved data in each other
-- addon's format, as read from their source (docs/plans/revenge/OTHER-ADDONS.md),
-- through the module and the core's door into Revenge's tooltip and list.

local function Start()
    local ns = LoadAddon()
    Mock.Advance(5)
    ok(Mock.module, "the module loaded")
    return ns
end

local function Adapter(id)
    for _, adapter in ipairs(Mock.module.adapters) do
        if adapter.id == id then return adapter end
    end
end

local function Deliver(prefix, text, sender, channel)
    Mock.Deliver(text, sender or "Mira", channel or "GUILD", prefix)
    Mock.Frames(3)
end

local function Kills()
    local list = {}
    for _, kill in pairs(RevengeTrackerDB.kills) do list[#list + 1] = kill end
    table.sort(list, function(a, b) return a.at > b.at end)
    return list
end

local function Marks()
    local list = {}
    for _, mark in pairs(RevengeTrackerDB.wanted) do list[#list + 1] = mark.target.name .. " < " .. mark.by.name end
    table.sort(list)
    return table.concat(list, ", ")
end

local function HoverGorvak()
    Mock.units.mouseover = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 }
    local lines = Mock.Hover("mouseover")
    for i, line in ipairs(lines) do lines[i] = line:gsub("^|T[^|]*|t ", "") end
    return table.concat(lines, " / ")
end

local function Base36(n)
    local digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    repeat
        local d = n % 36
        out = digits:sub(d + 1, d + 1) .. out
        n = (n - d) / 36
    until n == 0
    return out
end

---------------------------------------------------------------------------
-- Revenge Book
---------------------------------------------------------------------------
local function RB(...) return table.concat({ "1", ... }, "\t") end

test("Revenge Book: a guildmate's death, its place, and a catch-up copy make one kill", function()
    Start()
    local t = tostring(Mock.now - 60)
    Deliver("DeathNote", RB("K", "Gorvak-Ashmane", "Gorvak Ashmane", "WARRIOR", "60", "Duskwood", t, "Mira Thornwood"))
    Deliver("DeathNote", RB("L", "Gorvak-Ashmane", t, "Mira Thornwood", "1431", "453", "618"))
    Deliver("DeathNote", RB("R", "Gorvak-Ashmane", "Gorvak Ashmane", "WARRIOR", "60", "Duskwood", t, "Mira Thornwood"))
    local kills = Kills()
    eq(#kills, 1)
    local kill = kills[1]
    eq(kill.victim.name, "Mira Thornwood")
    eq(kill.killers[1].name, "Gorvak Ashmane")
    eq(kill.killers[1].class, "WARRIOR")
    eq(kill.killers[1].level, 60)
    eq(kill.zone, "Duskwood")
    eq(kill.mapID, 1431)
    ok(math.abs(kill.x - 0.453) < 1e-9 and math.abs(kill.y - 0.618) < 1e-9, "x, y in tenths of a percent")
    eq(kill.precision, "client")
    ok(kill.sources.revengebook)
    eq(HoverGorvak(), "(1) Mira")
    Mock.Advance(1)
    eq(#Mock.chat, 1, "the live K alerted once")
    eq(Adapter("revengebook").reports, 3)
end)

test("Revenge Book: escapes, unknown class and level, another language, a surname it didn't know", function()
    Start()
    Deliver("DeathNote", RB("R", "Gorvak-Ashmane", "Gorvak Ashmane", "", "0", "D\195\164mmerwald", tostring(Mock.now - 9000), "Mira Thornwood"))
    Deliver("DeathNote", RB("R", "Gorvak-Ashmane", "", "WARRIOR", "59", "100%25 Duskwood", tostring(Mock.now - 5000), "Mira Thornwood"))
    Deliver("DeathNote", RB("R", "Selka-?", "Selka", "MAGE", "40", "Duskwood", tostring(Mock.now - 3000), "Mira Thornwood"))
    local kills = Kills()
    eq(#kills, 3)
    eq(kills[1].killers[1].name, "Selka", "first name only")
    ok(kills[1].killers[1].partial)
    eq(kills[2].zone, "100% Duskwood")
    eq(kills[2].killers[1].name, "Gorvak Ashmane", "an empty display means the key's own name")
    eq(kills[3].zone, "D\195\164mmerwald")
    eq(kills[3].killers[1].class, nil)
    eq(kills[3].killers[1].level, nil)
    Mock.Advance(1)
    eq(#Mock.chat, 0, "catch-up copies don't alert")
end)

test("Revenge Book: Wanted by hand, then taken back; an older copy stays taken back", function()
    Start()
    local listed = tostring(Mock.now - 3600)
    Deliver("DeathNote", RB("M", "Gorvak-Ashmane", "Gorvak Ashmane", "WARRIOR", "60", listed, "Mira Thornwood"))
    eq(Marks(), "Gorvak Ashmane < Mira Thornwood")
    eq(HoverGorvak(), "Wanted by Mira")
    Deliver("DeathNote", RB("X", "Gorvak-Ashmane", "Mira Thornwood"))
    eq(Marks(), "")
    Deliver("DeathNote", RB("M", "Gorvak-Ashmane", "Gorvak Ashmane", "WARRIOR", "60", listed, "Mira Thornwood"))
    eq(Marks(), "", "a catch-up answer repeating the old mark")
end)

test("Revenge Book: someone else's data, junk and other message types", function()
    Start()
    local t = tostring(Mock.now - 60)
    Deliver("DeathNote", RB("K", "Gorvak-Ashmane", "Gorvak Ashmane", "WARRIOR", "60", "Duskwood", t, "Mira Thornwood"), "Tavish")
    Deliver("DeathNote", RB("M", "Gorvak-Ashmane", "Gorvak Ashmane", "", "0", t, "Mira Thornwood"), "Tavish")
    Deliver("DeathNote", RB("K", "Gorvak-Ashmane", "Gorvak Ashmane", "WARRIOR", "60", "Duskwood", t, "Mira Thornwood", "extra"))
    Deliver("DeathNote", RB("K", "gorvak ashmane", "Gorvak Ashmane", "WARRIOR", "60", "Duskwood", t, "Mira Thornwood"))
    Deliver("DeathNote", RB("K", "Gorvak-Ashmane", "Gorvak Ashmane", "WARRIOR", "60", "Dusk%2wood", t, "Mira Thornwood"))
    Deliver("DeathNote", RB("K", "Gorvak-Ashmane", "Gorvak Ashmane", "WARRIOR", "60", "Duskwood", "soon", "Mira Thornwood"))
    Deliver("DeathNote", "2\tK\tGorvak-Ashmane")
    Deliver("DeathNote", RB("J", "Gorvak-Ashmane", "camped the flight master"))
    Deliver("DeathNote", RB("H", "whatever"))
    eq(#Kills(), 0)
    eq(Marks(), "")
    ok(not Adapter("revengebook").breaker.tripped)
    eq(#Mock.chat, 0)
end)

test("Revenge Book: the books in your own Revenge Book, once, and your own death counted once", function()
    local ns = Start()
    local t = Mock.now - 7200
    -- Revenge recorded your death itself...
    ns.Merge.SubmitKill({ victim = ns.Identity.Self(), killers = { { name = "Gorvak Ashmane", key = "gorvak ashmane" } },
                          at = t, precision = "exact", zone = "Duskwood", sources = { self = true }, own = true })
    -- ...and so did Revenge Book, on your own clock.
    Mock.loaded.DeathNote = true
    DeathNoteDB = {
        enemies = {
            ["Gorvak-Ashmane"] = { display = "Gorvak Ashmane", class = "WARRIOR", level = 60, status = "wanted",
                deaths = {
                    { t = t + 4, zone = "Duskwood", mapID = 1431, x = 45.3, y = 61.8, me = "Anna Bright", role = "kill", sure = true },
                    { t = t - 9000, me = "Anna Bright", role = "assist", sure = true },
                    { t = t - 9900, me = "Anna Bright", role = "kill", sure = false },
                } },
            ["Selka-Duskmantle"] = { display = "Selka Duskmantle", manual = true, by = "Anna Bright",
                                     listedAt = Mock.now - 86400, status = "wanted", deaths = {} },
            ["Old-Grudge"] = { display = "Old Grudge", deaths = { { t = Mock.now - 40 * 86400, me = "Anna Bright", role = "kill", sure = true } } },
        },
        guild = { lists = {
            ["Dawn Watch"] = { enemies = {
                ["Gorvak-Ashmane"] = { display = "Gorvak Ashmane", class = "WARRIOR",
                    deeds = { { t = t - 600, zone = "Duskwood", victim = "Doran Vell" } },
                    listedBy = { ["Doran Vell"] = Mock.now - 4000 } },
            } },
            ["Another Guild"] = { enemies = {
                ["Shazra-Vex"] = { display = "Shazra Vex", deeds = { { t = t, victim = "Someone Else" } } },
            } },
        } },
        friends = { enemies = {
            ["Gorvak-Ashmane"] = { display = "Gorvak Ashmane", deeds = { { t = t - 1200, victim = "Orin Hale", imported = true },
                                                                          { t = t - 1800, victim = "Tavish Brightforge" } } },
        } },
    }
    Mock.Advance(20)
    Mock.Frames(100, 0.05)
    eq(HoverGorvak(), "(3) You, Doran, Tavish / Wanted by Doran", "your own death once, then Doran's and Tavish's")
    local yours
    for _, kill in ipairs(Kills()) do if kill.own then yours = kill end end
    eq(yours.precision, "exact", "Revenge's own time wins")
    eq(yours.mapID, 1431, "Revenge Book filled in the place")
    eq(Marks(), "Gorvak Ashmane < Doran Vell, Selka Duskmantle < Anna Bright")
    local reports = Adapter("revengebook").reports
    Mock.Advance(600)
    Mock.Frames(100, 0.05)
    eq(Adapter("revengebook").reports, reports, "nothing new the second time")
    eq(#Mock.chat, 0)
end)

---------------------------------------------------------------------------
-- Grudgekeeper
---------------------------------------------------------------------------
local function GK(...) return table.concat({ ... }, ";") end

-- AceComm's split: "\001" + 254 bytes, "\002" + 254 bytes..., "\003" + the rest.
local function Split(text)
    if #text <= 255 then return { text } end
    local parts, at = { "\1" .. text:sub(1, 254) }, 255
    while #text - at + 1 > 254 do
        parts[#parts + 1] = "\2" .. text:sub(at, at + 253)
        at = at + 254
    end
    parts[#parts + 1] = "\3" .. text:sub(at)
    return parts
end

test("Grudgekeeper: a guildmate's death now, and an earlier one in a catch-up answer", function()
    Start()
    Deliver("Grudgekeeper", GK("D", "1", "Gorvak Ashmane", "ROGUE", "Orc", "58", "Duskwood", "3", "Orc", "2", "Bloodfang Raiders"))
    Deliver("Grudgekeeper", GK("G", "1", "D", "Gorvak Ashmane", "ROGUE", "Orc", "58", "Duskwood", tostring(Mock.now - 9000),
                               "Bloodfang Raiders", "3", ""))
    Deliver("Grudgekeeper", GK("D", "1", "Shazra Vex", "", "Orc", "-1", "", "1", "Orc", "2", ""))
    local kills = Kills()
    eq(#kills, 3)
    eq(kills[1].at, Mock.now, "no time sent: stamped on arrival")
    eq(kills[1].precision, "received")
    eq(kills[2].killers[1].name, "Shazra Vex")
    eq(kills[2].killers[1].level, nil, "level -1 is ??")
    eq(kills[2].zone, nil, "streamer mode sends no zone")
    eq(kills[3].at, Mock.now - 9000)
    eq(kills[3].killers[1].class, "ROGUE")
    eq(kills[3].killers[1].level, 58)
    Mock.Advance(1)
    eq(#Mock.chat, 2, "the two deaths just now alerted; the catch-up copy didn't")
end)

test("Grudgekeeper: an open kill order is Wanted by its poster until it ends or expires", function()
    Start()
    local created, expires = tostring(Mock.now - 3600), tostring(Mock.now + 6 * 86400)
    local function Order(state, expiry, target, guid)
        return GK("C", "1", created, target or "Gorvak Ashmane", "ROGUE", "Orc", "58", guid or "", "500000", created,
                  expiry or expires, state, "", "Camped me at Raven Hill.", "", "Orc", "2")
    end
    Deliver("Grudgekeeper", Order("o"))
    eq(HoverGorvak(), "Wanted by Mira")
    local _, mark = next(RevengeTrackerDB.wanted)
    eq(mark.at, Mock.now - 3600)
    eq(mark.expires, Mock.now + 6 * 86400)
    eq(mark.by.name, "Mira", "the poster is the sender, named as the game names them")
    Deliver("Grudgekeeper", Order("o", nil, "Darrok Vane", "Player-5826-0A3F9C21"))
    for _, m in pairs(RevengeTrackerDB.wanted) do
        if m.target.name == "Darrok Vane" then eq(m.target.guid, "Player-5826-0A3F9C21") end
    end
    Deliver("Grudgekeeper", Order("x", nil, "Darrok Vane"))
    Deliver("Grudgekeeper", Order("o"))
    eq(count(RevengeTrackerDB.wanted), 1, "repeats are the same mark")
    Deliver("Grudgekeeper", Order("d"))
    eq(Marks(), "", "fulfilled")
    Deliver("Grudgekeeper", Order("d"))
    eq(Marks(), "", "and repeated in a catch-up answer")
    Deliver("Grudgekeeper", Order("o", tostring(Mock.now - 1)))
    eq(Marks(), "", "an open order that already expired")
    Deliver("Grudgekeeper", Order("o"))
    eq(Marks(), "Gorvak Ashmane < Mira", "posted again")
    eq(count(RevengeTrackerDB.withdrawals), 0, "nothing remembered")
end)

test("Grudgekeeper: split messages are joined; relays, others' data and junk are ignored", function()
    Start()
    local note = string.rep("Camped me at Raven Hill. ", 8)
    local order = GK("C", "1", tostring(Mock.now - 60), "Gorvak Ashmane", "ROGUE", "Orc", "58", "", "0",
                     tostring(Mock.now - 60), tostring(Mock.now + 86400), "o", "", note, "c", "Orc", "2")
    local parts = Split(order)
    eq(#parts, 2)
    Deliver("Grudgekeeper", parts[1])
    eq(Marks(), "", "waits for the rest")
    Deliver("Grudgekeeper", parts[2])
    eq(Marks(), "Gorvak Ashmane < Mira")
    Deliver("Grudgekeeper", "\3stray last part")
    Deliver("Grudgekeeper", "\4" .. GK("D", "1", "Shazra Vex", "MAGE", "Orc", "40", "Duskwood", "1", "Orc", "2", ""))
    eq(#Kills(), 1, "an escaped message")
    Deliver("Grudgekeeper", GK("O", "1", "Tavish Brightforge", "1795599000", "Darrok Vane", "MAGE", "Orc", "30", "", "0",
                               "1795599000", tostring(Mock.now + 86400), "o", "", "", "", "Orc", "2"))
    Deliver("Grudgekeeper", GK("D", "1", "Darrok Vane", "MAGE", "Orc", "30", "Duskwood", "1", "Orc", "2", ""), "Tavish", "WHISPER")
    Deliver("Grudgekeeper", GK("K", "1", "Darrok Vane"))
    Deliver("Grudgekeeper", GK("D", "2", "Darrok Vane"))
    Deliver("Grudgekeeper", "D")
    eq(Marks(), "Gorvak Ashmane < Mira", "the relayed order isn't Tavish's own")
    eq(#Kills(), 1)
    ok(not Adapter("grudgekeeper").breaker.tripped)
end)

---------------------------------------------------------------------------
-- HeadHunter
---------------------------------------------------------------------------
local function Grouped()
    Mock.units.party1 = { name = "Mira", surname = "Thornwood", guid = "Player-1-0000MIRA", class = "PALADIN" }
    Mock.guild["Player-1-0000MIRA"] = true
end

local function HHDeath(extra)
    local t = Base36(Mock.now - 60)
    return t .. ";Mira Thornwood;12;P;H;13r;bo;gy;" .. (extra or "e") .. ";42v;Gorvak Ashmane,,15,R,O,2,"
end

test("HeadHunter: a grouped guildmate's death by party", function()
    Start()
    Grouped()
    Deliver("HeadHunter", "1AD:" .. HHDeath(), "Mira", "PARTY")
    local kills = Kills()
    eq(#kills, 1)
    local kill = kills[1]
    eq(kill.at, Mock.now - 60)
    eq(kill.victim.name, "Mira Thornwood")
    eq(kill.victim.level, 38)
    eq(kill.killers[1].name, "Gorvak Ashmane")
    eq(kill.killers[1].level, 41)
    eq(kill.killers[1].class, "ROGUE")
    eq(kill.mapID, 1431)
    ok(math.abs(kill.x - 0.42) < 1e-9 and math.abs(kill.y - 0.61) < 1e-9, "thousandths")
    Mock.Advance(1)
    eq(#Mock.chat, 1, "alerted")
end)

test("HeadHunter: a stealthy killer known by first name and GUID, assists and helpers", function()
    Start()
    Grouped()
    local t = Base36(Mock.now - 60)
    Deliver("HeadHunter", "1AD:" .. t .. ";Mira Thornwood;12;P;H;13r;bo;gy;e;42v;Gorvak,1,,R,O,2,Player-4620-0B3F12A7;"
                          .. "Thessa Duskmantle,,14,L,U,3,;h1", "Mira", "RAID")
    local kill = Kills()[1]
    eq(#kill.killers, 2)
    eq(kill.killers[1].name, "Gorvak")
    ok(kill.killers[1].partial)
    eq(kill.killers[1].guid, "Player-4620-0B3F12A7")
    eq(kill.killers[2].name, "Thessa Duskmantle")
    eq(kill.killers[2].class, "WARLOCK")
end)

test("HeadHunter: a friend's own whispered envelope counts; relays, strangers and tests don't", function()
    Start()
    Mock.friendList = { { name = "Mira Thornwood", connected = true, guid = "Player-1-0000MIRA" } }
    local at = Base36(Mock.now - 59)
    Deliver("HeadHunter", "1AE:eu-pvp;Mira Thornwood;A;3kc;2;" .. at .. ";D" .. HHDeath(), "Mira", "WHISPER")
    eq(#Kills(), 0, "hop 2: relayed")
    Deliver("HeadHunter", "1AE:eu-pvp;Tavish Brightforge;A;3kc;1;" .. at .. ";D" .. HHDeath(), "Mira", "WHISPER")
    eq(#Kills(), 0, "an envelope someone else wrote")
    Deliver("HeadHunter", "1AD:" .. HHDeath(), "Mira", "WHISPER")
    eq(#Kills(), 0, "a plain D is never whispered")
    Deliver("HeadHunter", "1AE:eu-pvp;Orin Hale;A;3kc;1;" .. at .. ";D" .. HHDeath():gsub("Mira Thornwood", "Orin Hale"),
            "Orin", "WHISPER")
    eq(#Kills(), 0, "a stranger")
    Deliver("HeadHunter", "1AD:" .. HHDeath():gsub("Mira Thornwood", "Orin Hale"), "Orin", "PARTY")
    eq(#Kills(), 0, "not a friend, nor a guildmate in your group")
    Deliver("HeadHunter", "1AD:" .. HHDeath("s"), "Mira", "PARTY")
    eq(#Kills(), 0, "a simulated test death")
    Deliver("HeadHunter", "1AE:eu-pvp;Mira Thornwood;A;3kc;1;" .. at .. ";D" .. HHDeath(), "Mira", "WHISPER")
    eq(#Kills(), 1, "Mira's own envelope at hop 1")
    Deliver("HeadHunter", "2AD:" .. HHDeath(), "Mira", "PARTY")
    Deliver("HeadHunter", "1AK:outlaw;whatever", "Mira", "PARTY")
    Deliver("HeadHunter", "1AD:not;a;death", "Mira", "PARTY")
    eq(#Kills(), 1)
    ok(not Adapter("headhunter").breaker.tripped)
end)

test("HeadHunter: your own deaths from its saved data while it's loaded", function()
    Start()
    Mock.loaded.HeadHunter = true
    HeadHunter_DB = { meta = { home = "forever|4620" }, homes = { ["forever|4620"] = { deaths = {
        { id = "Anna Bright:1", t = Mock.now - 5000, origin = "local", victim = { key = "Anna Bright", class = "PRIEST" },
          killer = { key = "Gorvak Ashmane", class = "ROGUE", level = 41 }, assists = {}, mapID = 1431, x = 0.42, y = 0.61 },
        { id = "Anna Bright:2", t = Mock.now - 4000, origin = "sim", victim = { key = "Anna Bright" },
          killer = { key = "Gorvak Ashmane" } },
        { id = "Anna Bright:3", t = Mock.now - 3000, origin = "local", victim = { key = "Anna Bright" },
          killer = { key = "Gorvak", nameIncomplete = true, guid = "Player-4620-0B3F12A7" } },
    } } } }
    Mock.Advance(20)
    Mock.Frames(50, 0.05)
    local kills = Kills()
    eq(#kills, 2, "not the simulated one")
    eq(kills[1].killers[1].name, "Gorvak")
    ok(kills[1].killers[1].partial)
    eq(kills[2].mapID, 1431)
end)

---------------------------------------------------------------------------
-- Kill on Sight
---------------------------------------------------------------------------
test("Kill on Sight: your list is Wanted by you, and players taken off it go", function()
    local ns = Start()
    Mock.loaded.KillOnSight = true
    KillOnSightDB = { global = { data = {
        players = {
            ["gorvak ashmane"] = { name = "Gorvak Ashmane", class = "ROGUE", type = "KoS", addedBy = "Anna Bright",
                                   addedAt = Mock.now - 86400 },
            ["darrok vane"] = { name = "darrok vane", type = "KoS", addedBy = "Anna", addedAt = Mock.now - 5000 },
            ["shazra vex"] = { name = "Shazra Vex", type = "KoS", addedBy = "Mira Thornwood", addedAt = Mock.now - 4000 },
            ["grimm"] = { name = "Grimm", type = "KoS", addedBy = "Anna", addedAt = Mock.now - 3000 },
        },
        honorPlayers = { ["kind soul"] = { name = "Kind Soul", class = "PRIEST" } },
    } } }
    eq(ns.Foreign.module.Status().killonsight.state, "watching")
    Mock.Advance(20)
    Mock.Frames(50, 0.05)
    eq(Marks(), "Darrok Vane < Anna Bright, Gorvak Ashmane < Anna Bright, Shazra Vex < Mira Thornwood")
    eq(HoverGorvak(), "Wanted by you")
    KillOnSightDB.global.data.players["gorvak ashmane"] = nil
    Mock.Advance(600)
    Mock.Frames(50, 0.05)
    eq(Marks(), "Darrok Vane < Anna Bright, Shazra Vex < Mira Thornwood")
    eq(HoverGorvak(), "")
end)

test("Kill on Sight isn't read while it isn't loaded, or when its data isn't what Revenge knows", function()
    local ns = Start()
    KillOnSightDB = { global = { data = { players = { ["gorvak ashmane"] = { name = "Gorvak Ashmane" } } } } }
    Mock.Advance(20)
    Mock.Frames(50, 0.05)
    eq(Marks(), "")
    eq(ns.Foreign.module.Status().killonsight.state, "absent")
    Mock.loaded.KillOnSight = true
    KillOnSightDB = { global = { data = { players = "changed" } } }
    Mock.Advance(600)
    Mock.Frames(50, 0.05)
    eq(Marks(), "")
    ok(Adapter("killonsight").importUnrecognised)
    eq(#Mock.chat, 0)
end)
