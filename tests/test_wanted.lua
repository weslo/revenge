-- Wanted marks: Add by name, the tooltip line, merging, withdrawals.

local GORVAK_GUID = "Player-1-0000GORV"
local MIRA = { name = "Mira Thornwood", key = "mira thornwood", guid = "Player-1-0000MIRA" }
local TAVISH = { name = "Tavish Brightforge", key = "tavish brightforge", guid = "Player-1-0000TAVI" }
local ORIN = { name = "Orin Hale", key = "orin hale", guid = "Player-1-0000ORIN" }

local function Copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local function Gorvak() return { name = "Gorvak Ashmane", key = "gorvak ashmane" } end

local function TargetGorvak()
    Mock.units.target = { name = "Gorvak", surname = "Ashmane", guid = GORVAK_GUID, class = "ROGUE", level = 41, faction = "Horde" }
end

local function StripSkull(text) return (text:gsub("^|T[^|]*|t ", "")) end

-- A mark from another Revenge user, as sharing will deliver it.
local function MarkBy(ns, by, ago)
    return ns.Merge.SubmitWanted({ target = Gorvak(), by = Copy(by), at = Mock.now - (ago or 0),
                                   sources = { revenge = true }, own = true })
end

test("Add by name marks the player Wanted by you", function()
    local ns = LoadAddon()
    local added, message = ns.List.AddByName("  gorvak   ASHMANE ")
    ok(added, message)
    eq(message, "Gorvak Ashmane is now wanted by you.")
    local _, mark = next(RevengeTrackerDB.wanted)
    eq(mark.target.name, "Gorvak Ashmane")
    eq(mark.by.guid, "Player-1-AAAA0001", "added by you")
    ok(mark.own, "own")
    TargetGorvak()
    local lines = Mock.Hover("target")
    eq(#lines, 1)
    ok(lines[1]:find("^|TInterface\\TargetingFrame\\UI%-RaidTargetingIcon_8"), "skull icon first")
    eq(StripSkull(lines[1]), "Wanted by you")
end)

test("the kills line comes first, then Wanted; Shift details sit between", function()
    local ns = LoadAddon()
    ns.Merge.SubmitKill({ victim = { name = "Anna Bright", key = "anna bright", guid = "Player-1-AAAA0001" },
                          killers = { { name = "Gorvak Ashmane", key = "gorvak ashmane", guid = GORVAK_GUID } },
                          at = Mock.now - 7200, precision = "exact", zone = "Duskwood", sources = { self = true }, own = true })
    ns.List.AddByName("Gorvak Ashmane")
    TargetGorvak()
    local lines = Mock.Hover("target")
    eq(#lines, 2)
    eq(StripSkull(lines[1]), "(1) You")
    eq(StripSkull(lines[2]), "Wanted by you")
    Mock.keys.shift = true
    lines = Mock.Hover("target")
    eq(#lines, 3)
    eq(lines[2], "You · Duskwood · 2h ago")
    eq(StripSkull(lines[3]), "Wanted by you")
end)

test("several adders: you first, then the others newest first, then +N more", function()
    local ns = LoadAddon()
    MarkBy(ns, MIRA, 3600)
    MarkBy(ns, TAVISH, 60)
    MarkBy(ns, ORIN, 7200)
    ns.List.AddByName("Gorvak Ashmane")
    TargetGorvak()
    eq(StripSkull(Mock.Hover("target")[1]), "Wanted by you, Tavish, Mira, +1 more")
end)

test("Add by name refuses junk, yourself and a first name alone", function()
    local ns = LoadAddon()
    local function Refused(text, expected)
        local added, message = ns.List.AddByName(text)
        eq(added, false, tostring(text))
        eq(message, expected, tostring(text))
    end
    local invalid = "That isn't a player name: use letters and spaces only."
    Refused("", "Type a player's name first.")
    Refused("   ", "Type a player's name first.")
    Refused(nil, "Type a player's name first.")
    Refused("Gorvak", "Type the player's first and last name.")
    Refused("Gorvak |cffff0000Ashmane", invalid)
    Refused("|Hplayer:Gorvak|h[Gorvak]|h", invalid)
    Refused("Gorvak Ashmane2", invalid)
    Refused(("Abcdefghij "):rep(5), invalid)
    Refused("anna BRIGHT", "That's you.")
    eq(count(RevengeTrackerDB.wanted), 0)
end)

test("hyphens, extra spaces and letters from other languages are fine", function()
    local ns = LoadAddon()
    ok(ns.List.AddByName("Gorvak-Ashmane"), "hyphen")
    ok(ns.List.AddByName("ærin høst"), "accented letters")
    ok(ns.List.AddByName("O'rin  Hale"), "apostrophe")
    eq(count(RevengeTrackerDB.wanted), 3)
end)

test("a first name alone is accepted where names have no surnames", function()
    local ns = LoadAddon()
    Mock.uniqueNames = false
    ok(ns.List.AddByName("gorvak"))
    local _, mark = next(RevengeTrackerDB.wanted)
    eq(mark.target.name, "Gorvak")
end)

test("a name seen before takes the game's spelling, GUID and class; your own faction is refused", function()
    local ns = LoadAddon({ names = {
        [GORVAK_GUID] = { n = "Gorvak Ashmane", c = "ROGUE", l = 41, f = "Horde", t = 1795600000 },
        ["Player-1-0000RUSK"] = { n = "Ruskar Redtusk", c = "WARRIOR", l = 44, f = "Alliance", t = 1795600000 },
    } })
    ok(ns.List.AddByName("GORVAK ashmane"))
    local _, mark = next(RevengeTrackerDB.wanted)
    eq(mark.target.guid, GORVAK_GUID)
    eq(mark.target.class, "ROGUE")
    eq(mark.target.level, 41)
    local added, message = ns.List.AddByName("ruskar redtusk")
    eq(added, false)
    eq(message, "Ruskar Redtusk is on your own faction.")
end)

test("adding the same player twice says so", function()
    local ns = LoadAddon()
    ns.List.AddByName("Gorvak Ashmane")
    local added, message = ns.List.AddByName("gorvak ashmane")
    eq(added, false)
    eq(message, "Gorvak Ashmane is already wanted by you.")
    eq(count(RevengeTrackerDB.wanted), 1)
end)

test("a Wanted player seen later gets their GUID and class", function()
    local ns = LoadAddon()
    ns.List.AddByName("Gorvak Ashmane")
    TargetGorvak()
    Mock.Fire("PLAYER_TARGET_CHANGED")
    local _, mark = next(RevengeTrackerDB.wanted)
    eq(mark.target.guid, GORVAK_GUID)
    eq(mark.target.class, "ROGUE")
    eq(#ns.Store.WantedFor(GORVAK_GUID, nil), 1, "found by GUID")
end)

test("the same mark from two sources counts once", function()
    local ns = LoadAddon()
    MarkBy(ns, MIRA, 60)
    local mark, new = ns.Merge.SubmitWanted({ target = Gorvak(), by = Copy(MIRA), at = Mock.now - 30,
                                              sources = { revengebook = true } })
    eq(new, false)
    eq(count(RevengeTrackerDB.wanted), 1)
    ok(mark.sources.revenge and mark.sources.revengebook, "both sources")
    eq(mark.at, Mock.now - 60, "earliest add time kept")
end)

test("the adder's withdrawal removes the mark; an older copy can't bring it back", function()
    local ns = LoadAddon()
    MarkBy(ns, MIRA, 600)
    eq(ns.Merge.SubmitWithdrawal({ target = Gorvak(), by = Copy(MIRA), at = Mock.now - 60 }), 1)
    eq(count(RevengeTrackerDB.wanted), 0)
    eq(MarkBy(ns, MIRA, 600), nil, "older copy refused")
    ok(MarkBy(ns, MIRA, 0), "a later mark is accepted")
end)

test("someone else's withdrawal doesn't touch your mark", function()
    local ns = LoadAddon()
    ns.List.AddByName("Gorvak Ashmane")
    eq(ns.Merge.SubmitWithdrawal({ target = Gorvak(), by = Copy(MIRA), at = Mock.now }), 0)
    eq(count(RevengeTrackerDB.wanted), 1)
end)

test("Wanted marks never expire and survive a reload", function()
    local ns = LoadAddon()
    ns.List.AddByName("Gorvak Ashmane")
    local saved = RevengeTrackerDB
    for _, mark in pairs(saved.wanted) do mark.at = mark.at - 40 * 86400 end
    ns = LoadAddon(saved)
    TargetGorvak()
    eq(StripSkull(Mock.Hover("target")[1]), "Wanted by you")
    ok(ns.List.Rows()[1], "still listed")
end)

test("broken saved marks are dropped at load", function()
    LoadAddon({ wanted = {
        w1 = "junk",
        w2 = { at = 1, target = { key = "x" } },
        w3 = { id = "w3", at = 1795600000, target = { name = "Gorvak Ashmane", key = "gorvak ashmane" },
               by = { name = "Anna Bright", key = "anna bright" } },
    } })
    eq(count(RevengeTrackerDB.wanted), 1)
    ok(RevengeTrackerDB.wanted.w3, "valid mark kept")
    ok(RevengeTrackerDB.wanted.w3.sources, "missing sources added")
end)
