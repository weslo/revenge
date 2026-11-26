-- The nameplate skull and the world-map pins.

local function Gorvak() return { name = "Gorvak Ashmane", key = "gorvak ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 } end
local GORVAK_UNIT = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41, faction = "Horde" }

local function Victim(name, guid) return { name = name, key = name:lower(), guid = guid } end

local function Kill(ns, victim, ago, mapID, x, y, killers)
    return ns.Merge.SubmitKill({ victim = victim, killers = killers or { Gorvak() }, at = Mock.now - ago,
                                 precision = "exact", mapID = mapID, x = x, y = y, zone = "Duskwood",
                                 sources = { self = true }, own = true })
end

local function ShowPlate(unitData, token)
    token = token or "nameplate1"
    Mock.units[token] = unitData
    Mock.plates[token] = Mock.plates[token] or CreateFrame("Frame")
    Mock.Fire("NAME_PLATE_UNIT_ADDED", token)
    return Mock.plates[token]
end

local function Mark(ns, token)
    local mark = ns.Nameplates.marks[token or "nameplate1"]
    return mark and mark:IsShown() and mark or nil
end

---------------------------------------------------------------------------
-- Nameplates
---------------------------------------------------------------------------
test("a recent killer's nameplate gets the skull beside it, and the plate is left alone", function()
    local ns = LoadAddon()
    Kill(ns, ns.Identity.Self(), 600)
    local plate = ShowPlate(GORVAK_UNIT)
    local mark = Mark(ns)
    ok(mark, "skull shown")
    eq(mark.parent, plate, "parented to the base plate the game gave")
    eq(mark.icon.texture, "Interface\\AddOns\\RevengeTracker\\Media\\Skull", "Revenge's own skull, not a raid marker")
    local point = mark.points[1]
    eq(point[1], "RIGHT")
    eq(point[2], plate)
    eq(point[3], "LEFT", "beside the plate")
    eq(plate.points, nil, "the plate itself isn't moved")
    eq(plate.color, nil, "or recoloured")
end)

test("a Wanted player gets the skull; anyone else doesn't", function()
    local ns = LoadAddon()
    ns.List.AddByName("Darrok Vane")
    ShowPlate({ name = "Darrok", surname = "Vane", guid = "Player-1-0000DARR" }, "nameplate2")
    ok(Mark(ns, "nameplate2"), "Wanted")
    ShowPlate({ name = "Brakka", surname = "Stonefist", guid = "Player-1-0000BRAK" }, "nameplate3")
    eq(Mark(ns, "nameplate3"), nil)
end)

test("the skull goes when the kill is removed, expires, or the option is off", function()
    local ns = LoadAddon()
    Kill(ns, ns.Identity.Self(), 3 * 86400)
    ShowPlate(GORVAK_UNIT)
    ok(Mark(ns), "shown")
    RevengeTrackerDB.settings.nameplates = false
    ns.Changed()
    eq(Mark(ns), nil, "option off")
    RevengeTrackerDB.settings.nameplates = true
    ns.Changed()
    ok(Mark(ns), "back on")
    RevengeTrackerDB.settings.expiryDays = 2
    ns.Changed()
    eq(Mark(ns), nil, "expired")
    RevengeTrackerDB.settings.expiryDays = 7
    ns.Changed()
    ns.List.Remove(ns.List.Rows()[1])
    eq(Mark(ns), nil, "removed from the list")
end)

test("no skull in instances, for hidden players or forbidden plates; plates come and go", function()
    local ns = LoadAddon()
    Kill(ns, ns.Identity.Self(), 600)
    Mock.inInstance = true
    ShowPlate(GORVAK_UNIT)
    eq(Mark(ns), nil, "instance")
    Mock.inInstance = false
    ShowPlate({ name = Mock.SECRET, guid = Mock.SECRET }, "nameplate4")
    eq(Mark(ns, "nameplate4"), nil, "hidden identity")
    local forbidden = CreateFrame("Frame")
    forbidden.IsForbidden = function() return true end
    Mock.plates.nameplate5 = forbidden
    ShowPlate(GORVAK_UNIT, "nameplate5")
    eq(Mark(ns, "nameplate5"), nil, "forbidden plate")
    Mock.Fire("NAME_PLATE_UNIT_ADDED", Mock.SECRET)
    ShowPlate(GORVAK_UNIT, "nameplate6")
    local mark = Mark(ns, "nameplate6")
    ok(mark)
    Mock.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate6")
    eq(Mark(ns, "nameplate6"), nil, "released with its plate")
    ShowPlate(GORVAK_UNIT, "nameplate7")
    eq(Mark(ns, "nameplate7"), mark, "and reused")
end)

---------------------------------------------------------------------------
-- Map pins
---------------------------------------------------------------------------
local MIRA_GUID, TAVISH_GUID = "Player-1-0000MIRA", "Player-1-0000TAVI"

local function Setup()
    local ns = LoadAddon()
    Mock.friends[MIRA_GUID] = true
    Mock.guild[TAVISH_GUID] = true
    Kill(ns, ns.Identity.Self(), 2 * 3600, 1431, 0.42, 0.61)
    Kill(ns, Victim("Mira Thornwood", MIRA_GUID), 86400, 1431, 0.5, 0.5)
    Kill(ns, Victim("Tavish Brightforge", TAVISH_GUID), 3 * 86400, 1433, 0.3, 0.3)
    Kill(ns, ns.Identity.Self(), 8 * 86400, 1431, 0.1, 0.1)   -- expired
    Kill(ns, Victim("Orin Hale", "Player-1-0000ORIN"), 3600, nil, nil, nil)  -- no position
    return ns
end

local function ByVictim(pins)
    local out = {}
    for _, pin in ipairs(pins) do out[pin.kill.victim.key] = pin end
    return out
end

test("skulls where recent deaths happened, coloured by whose they were", function()
    Setup()
    local pins = ByVictim(Mock.ShowMap(1431))
    eq(count(pins), 2, "two recent deaths with a position on Duskwood")
    eq(pins["anna bright"].x, 0.42)
    eq(pins["anna bright"].y, 0.61)
    eq(pins["anna bright"].Icon.color[1], 1, "you: coral")
    eq(pins["mira thornwood"].Icon.color[3], 0.851, "a friend: blue")
    pins = Mock.ShowMap(1433)
    eq(#pins, 1)
    eq(pins[1].Icon.color[1], 0.910, "a guildmate: yellow")
end)

test("a zone's kills show on the maps that contain it", function()
    Setup()
    Mock.mapRects["1431>1415"] = { 0.4, 0.5, 0.6, 0.7 }
    local pins = ByVictim(Mock.ShowMap(1415))
    eq(count(pins), 2)
    ok(math.abs(pins["anna bright"].x - (0.4 + 0.1 * 0.42)) < 1e-9, "x on the parent map")
    ok(math.abs(pins["anna bright"].y - (0.6 + 0.1 * 0.61)) < 1e-9, "y on the parent map")
end)

test("hover says who, by whom and when; right-click dismisses the kill everywhere", function()
    local ns = Setup()
    local pin = ByVictim(Mock.ShowMap(1431))["mira thornwood"]
    pin:OnMouseEnter()
    eq(table.concat(GameTooltip.lines, " / "),
       "Mira Thornwood (friend) / Killed by Gorvak Ashmane / Level 41 Rogue · 1d ago / Right-click to dismiss")
    eq(pin:ShouldMouseButtonBePassthrough("RightButton"), false, "right-click stays with the pin")
    pin:OnMouseClickAction("RightButton")
    eq(Mock.menu[1].title, "Mira Thornwood (friend)")
    eq(Mock.menu[2].text, "Dismiss kill")
    eq(Mock.menu[3].text, "Cancel")
    Mock.units.target = GORVAK_UNIT
    ok(Mock.Hover("target")[1]:find("(4)", 1, true), "four recent kills before")
    eq(#ns.List.Rows()[1].kills, 4)
    Mock.menu[2].fn()
    ok(Mock.Hover("target")[1]:find("(3)", 1, true), "three after: the tooltip count dropped")
    eq(count(ByVictim(Mock.pins)), 1, "the map redrew without it")
    eq(#ns.List.Rows()[1].kills, 3, "and the list")
end)

test("pins can be switched off, and wait out combat", function()
    local ns = Setup()
    eq(#Mock.ShowMap(1431), 2)
    RevengeTrackerDB.settings.mapPins = false
    ns.Changed()
    eq(#Mock.pins, 0, "off")
    RevengeTrackerDB.settings.mapPins = true
    Mock.inCombat = true
    ns.Changed()
    eq(#Mock.pins, 0, "not redrawn in combat")
    Mock.inCombat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(#Mock.pins, 2, "redrawn after")
end)
