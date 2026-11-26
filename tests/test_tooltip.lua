-- The tooltip line and the Shift details.

local GORVAK_GUID = "Player-1-0000GORV"

local function Victim(name, guid) return { name = name, key = name:lower(), guid = guid } end
local function Gorvak() return { name = "Gorvak Ashmane", key = "gorvak ashmane", guid = GORVAK_GUID } end

local function Kill(ns, victim, ago, zone)
    return ns.Merge.SubmitKill({ victim = victim, killers = { Gorvak() }, at = Mock.now - ago, precision = "exact",
                                 zone = zone or "Duskwood", sources = { self = true }, own = true })
end

-- Five recent kills by Gorvak: you twice, Mira, Tavish and Orin.
local function Setup()
    local ns = LoadAddon()
    Mock.units.target = { name = "Gorvak", surname = "Ashmane", guid = GORVAK_GUID, class = "ROGUE", level = 41 }
    Mock.friends["Player-1-0000MIRA"] = true
    Mock.guild["Player-1-0000TAVI"] = true
    Mock.guild["Player-1-0000ORIN"] = true
    local me = Victim("Anna Bright", "Player-1-AAAA0001")
    Kill(ns, me, 2 * 3600, "Hillsbrad Foothills")
    Kill(ns, Victim("Mira Thornwood", "Player-1-0000MIRA"), 86400)
    Kill(ns, Victim("Tavish Brightforge", "Player-1-0000TAVI"), 3 * 86400, "Stranglethorn Vale")
    Kill(ns, Victim("Orin Hale", "Player-1-0000ORIN"), 4 * 86400, "Arathi Highlands")
    Kill(ns, Victim("Anna Bright", "Player-1-AAAA0001"), 5 * 86400, "Arathi Highlands")
    return ns
end

local function StripSkull(text)
    return (text:gsub("^|T[^|]*|t ", ""))
end

test("one line: the count, then You first and up to 3 names", function()
    Setup()
    local lines = Mock.Hover("target")
    eq(#lines, 1)
    ok(lines[1]:find("^|TInterface\\TargetingFrame\\UI%-RaidTargetingIcon_8"), "skull icon first")
    eq(StripSkull(lines[1]), "(5) You, Mira, Tavish, +1 more")
end)

test("holding Shift lists each recent kill, newest first", function()
    Setup()
    Mock.keys.shift = true
    local lines = Mock.Hover("target")
    eq(#lines, 6)
    eq(lines[2], "You · Hillsbrad Foothills · 2h ago")
    eq(lines[3], "Mira Thornwood (friend) · Duskwood · 1d ago")
    eq(lines[4], "Tavish Brightforge (guild) · Stranglethorn Vale · 3d ago")
    eq(lines[6], "You · Arathi Highlands · 5d ago")
end)

test("the details key can be changed or turned off", function()
    Setup()
    Mock.keys.shift = true
    RevengeTrackerDB.settings.detailsModifier = "CTRL"
    eq(#Mock.Hover("target"), 1, "Shift no longer works")
    Mock.keys.ctrl = true
    eq(#Mock.Hover("target"), 6, "Ctrl does")
    RevengeTrackerDB.settings.detailsModifier = "OFF"
    eq(#Mock.Hover("target"), 1, "off")
end)

test("pressing the key redraws a shown tooltip", function()
    Setup()
    eq(#Mock.Hover("target"), 1)
    Mock.keys.shift = true
    Mock.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
    eq(#GameTooltip.lines, 6)
end)

test("kills older than the expiry don't count", function()
    Setup()
    RevengeTrackerDB.settings.expiryDays = 3
    eq(StripSkull(Mock.Hover("target")[1]), "(3) You, Mira, Tavish")
end)

test("more than 5 kills: details end with +N more", function()
    local ns = Setup()
    Kill(ns, Victim("Pell Oakes", "Player-1-0000PELL"), 6 * 3600)
    Mock.keys.shift = true
    local lines = Mock.Hover("target")
    eq(#lines, 7)
    eq(lines[7], "+1 more")
end)

test("players with no recent kills get no line", function()
    Setup()
    Mock.units.mouseover = { name = "Brakka", surname = "Stonefist", guid = "Player-1-0000BRAK" }
    eq(#Mock.Hover("mouseover"), 0)
    eq(#Mock.Hover("nonexistent"), 0)
end)

test("the line is found by name when the GUID is unknown", function()
    local ns = LoadAddon()
    ns.Merge.SubmitKill({ victim = Victim("Anna Bright", "Player-1-AAAA0001"),
                          killers = { { name = "Gorvak Ashmane", key = "gorvak ashmane" } },
                          at = Mock.now - 60, precision = "client", sources = { revengebook = true } })
    Mock.units.target = { name = "Gorvak", surname = "Ashmane", guid = GORVAK_GUID }
    eq(StripSkull(Mock.Hover("target")[1]), "(1) You")
end)

test("a hidden (secret) unit adds nothing and doesn't error", function()
    Setup()
    Mock.units.target.name, Mock.units.target.surname, Mock.units.target.guid = Mock.SECRET, Mock.SECRET, Mock.SECRET
    eq(#Mock.Hover("target"), 0)
end)
