-- Identity keys, matching and the name cache.

GORVAK = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE",
           level = 41, guild = "Bloodfang Raiders", faction = "Horde" }

function Unit(def)
    local copy = {}
    for k, v in pairs(def) do copy[k] = v end
    return copy
end

test("Key normalizes case, hyphens and spaces", function()
    local ns = LoadAddon()
    eq(ns.Identity.Key("  Gorvak-Ashmane "), "gorvak ashmane")
    eq(ns.Identity.Key("gorvak   ASHMANE"), "gorvak ashmane")
    eq(ns.Identity.Key(""), nil)
    eq(ns.Identity.Key("   "), nil)
    eq(ns.Identity.Key(nil), nil)
end)

test("Same: GUIDs decide when both have one", function()
    local ns = LoadAddon()
    local I = ns.Identity
    ok(I.Same({ guid = "Player-1-A", key = "x y" }, { guid = "Player-1-A", key = "other name" }))
    ok(not I.Same({ guid = "Player-1-A", key = "x y" }, { guid = "Player-1-B", key = "x y" }), "different GUIDs")
end)

test("Same: full names, and a first name alone matches only its own full name", function()
    local ns = LoadAddon()
    local I = ns.Identity
    ok(I.Same(I.Make("Gorvak Ashmane"), I.Make("gorvak-ashmane")), "same full name")
    ok(I.Same(I.Make("Gorvak"), I.Make("Gorvak Ashmane")), "first name vs full name")
    ok(not I.Same(I.Make("Gorvak"), I.Make("Brakka Stonefist")), "different first name")
    ok(not I.Same(I.Make("Gorvak Ashmane"), I.Make("Gorvak Stonefist")), "different surname")
end)

test("FromUnit builds the Forever full name and details", function()
    local ns = LoadAddon()
    Mock.units.target = Unit(GORVAK)
    local id = ns.Identity.FromUnit("target")
    eq(id.name, "Gorvak Ashmane")
    eq(id.key, "gorvak ashmane")
    eq(id.guid, GORVAK.guid)
    eq(id.class, "ROGUE")
    eq(id.level, 41)
    eq(id.guild, "Bloodfang Raiders")
    eq(id.partial, nil)
end)

test("FromUnit returns nothing for hidden (secret) identities", function()
    local ns = LoadAddon()
    local hidden = Unit(GORVAK)
    hidden.name, hidden.surname, hidden.guid = Mock.SECRET, Mock.SECRET, Mock.SECRET
    Mock.units.target = hidden
    eq(ns.Identity.FromUnit("target"), nil)
end)

test("the name cache learns players from target, mouseover and nameplates", function()
    local ns = LoadAddon()
    Mock.units.target = Unit(GORVAK)
    Mock.Fire("PLAYER_TARGET_CHANGED")
    local entry = RevengeTrackerDB.names[GORVAK.guid]
    ok(entry, "cached")
    eq(entry.n, "Gorvak Ashmane")
    eq(entry.f, "Horde")
    Mock.units["nameplate3"] = Unit(GORVAK)
    Mock.units["nameplate3"].guid = "Player-1-0000BRAK"
    Mock.units["nameplate3"].name, Mock.units["nameplate3"].surname = "Brakka", "Stonefist"
    Mock.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    eq(RevengeTrackerDB.names["Player-1-0000BRAK"].n, "Brakka Stonefist")
end)

test("the name cache skips a player seen in the last 30 seconds", function()
    local ns = LoadAddon()
    Mock.units.target = Unit(GORVAK)
    Mock.Fire("PLAYER_TARGET_CHANGED")
    local first = RevengeTrackerDB.names[GORVAK.guid].t
    Mock.Advance(10)
    Mock.units.target.level = 42
    Mock.Fire("PLAYER_TARGET_CHANGED")
    eq(RevengeTrackerDB.names[GORVAK.guid].t, first, "not updated yet")
    eq(RevengeTrackerDB.names[GORVAK.guid].l, 41)
    Mock.Advance(30)
    Mock.Fire("PLAYER_TARGET_CHANGED")
    eq(RevengeTrackerDB.names[GORVAK.guid].l, 42, "updated after 30 s")
end)

test("Resolve fills a first-name-only identity from the cache", function()
    local ns = LoadAddon()
    Mock.units.target = Unit(GORVAK)
    Mock.Fire("PLAYER_TARGET_CHANGED")
    local id = ns.Identity.Resolve(ns.Identity.Make("Gorvak", GORVAK.guid))
    eq(id.name, "Gorvak Ashmane")
    eq(id.key, "gorvak ashmane")
    eq(id.partial, nil)
    eq(id.class, "ROGUE")
end)

test("Resolve falls back to GetPlayerInfoByGUID for class and level", function()
    local ns = LoadAddon()
    Mock.byGuid["Player-1-0000NEW1"] = { name = "Velka", class = "MAGE", level = 40 }
    local id = ns.Identity.Resolve(ns.Identity.Make(nil, "Player-1-0000NEW1"))
    eq(id.name, "Velka")
    eq(id.partial, true)
    eq(id.class, "MAGE")
    eq(id.level, 40)
end)

test("LongName labels friends and guildmates", function()
    local ns = LoadAddon()
    Mock.friends["Player-1-0000MIRA"] = true
    Mock.guild["Player-1-0000TAVI"] = true
    eq(ns.Identity.LongName({ name = "Mira Thornwood", guid = "Player-1-0000MIRA" }), "Mira Thornwood (friend)")
    eq(ns.Identity.LongName({ name = "Tavish Brightforge", guid = "Player-1-0000TAVI" }), "Tavish Brightforge (guild)")
    eq(ns.Identity.LongName({ name = "Anna Bright", guid = "Player-1-AAAA0001" }), "You")
end)
