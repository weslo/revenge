-- Alerts and the popup: killer nearby, friend or guildmate killed.

local function Gorvak() return { name = "Gorvak Ashmane", key = "gorvak ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 } end
local GORVAK_UNIT = { name = "Gorvak", surname = "Ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41, faction = "Horde" }

local function KillOnMe(ns, ago)
    return ns.Merge.SubmitKill({ victim = ns.Identity.Self(), killers = { Gorvak() }, at = Mock.now - (ago or 600),
                                 precision = "exact", zone = "Duskwood", sources = { self = true }, own = true })
end

local function Target(unit)
    Mock.units.target = unit
    Mock.Fire("PLAYER_TARGET_CHANGED")
    Mock.units.target = nil
end

local function Lines()
    local out = {}
    for i, line in ipairs(Mock.chat) do out[i] = line:gsub("^.-: ", "", 1) end
    Mock.chat = {}
    return out
end

local function ShownPopups(ns)
    local out = {}
    for _, frame in ipairs(ns.Popup.frames) do
        if frame:IsShown() then out[#out + 1] = frame end
    end
    return out
end

test("a recent killer coming into view alerts once, then not again for 5 minutes", function()
    local ns = LoadAddon()
    KillOnMe(ns)
    Target(GORVAK_UNIT)
    eq(table.concat(Lines(), " / "), "Gorvak Ashmane is nearby: (1) You.")
    local popups = ShownPopups(ns)
    eq(#popups, 1)
    eq(popups[1].title.text, "Gorvak Ashmane is nearby")
    eq(popups[1].detail.text, "(1) You")
    Target(GORVAK_UNIT)
    Mock.units.mouseover = GORVAK_UNIT
    Mock.Fire("UPDATE_MOUSEOVER_UNIT")
    Mock.Fire("NAME_PLATE_UNIT_ADDED", "mouseover")
    eq(#Lines(), 0, "not again within 5 minutes")
    Mock.Advance(301)
    Mock.Fire("NAME_PLATE_UNIT_ADDED", "mouseover")
    eq(#Lines(), 1, "again later, from a nameplate")
end)

test("a Wanted player alerts too, with who wants them; anyone else doesn't", function()
    local ns = LoadAddon()
    ns.List.AddByName("Darrok Vane")
    Mock.chat = {}
    Target({ name = "Darrok", surname = "Vane", guid = "Player-1-0000DARR", class = "MAGE", level = 30 })
    eq(table.concat(Lines(), " / "), "Darrok Vane is nearby: Wanted by you.")
    Target({ name = "Brakka", surname = "Stonefist", guid = "Player-1-0000BRAK" })
    eq(#Lines(), 0)
end)

test("no nearby alerts in instances, for hidden players, or when switched off", function()
    local ns = LoadAddon()
    KillOnMe(ns)
    Mock.inInstance = true
    Target(GORVAK_UNIT)
    eq(#Lines(), 0, "instance")
    Mock.inInstance = false
    Target({ name = Mock.SECRET, guid = Mock.SECRET })
    eq(#Lines(), 0, "identity hidden by the game")
    RevengeTrackerDB.settings.alertNearby = false
    Target(GORVAK_UNIT)
    eq(#Lines(), 0, "switched off")
    eq(#ShownPopups(ns), 0)
end)

test("popup only, chat only, and the sound only with the chat line", function()
    local ns = LoadAddon()
    KillOnMe(ns)
    RevengeTrackerDB.settings.alertChat = false
    Target(GORVAK_UNIT)
    eq(#Lines(), 0, "no chat line")
    eq(#ShownPopups(ns), 1, "the popup still")
    eq(#Mock.sounds, 0, "no sound without the chat line")
    RevengeTrackerDB.settings.alertChat = true
    RevengeTrackerDB.settings.alertPopup = false
    Mock.Advance(301)
    ns.Popup.frames[1]:Hide()
    Target(GORVAK_UNIT)
    eq(#Lines(), 1)
    eq(#ShownPopups(ns), 0, "no popup")
end)

test("the popup fades after about 4 seconds, and at once when clicked", function()
    local ns = LoadAddon()
    local frame = ns.Popup.Show("Gorvak Ashmane is nearby", "(1) You")
    local OnUpdate = frame.scripts.OnUpdate
    OnUpdate(frame, 3.9)
    ok(frame:IsShown() and frame:GetAlpha() == 1, "full strength for 4 seconds")
    OnUpdate(frame, 0.5)
    ok(frame:IsShown() and frame:GetAlpha() < 1 and frame:GetAlpha() > 0, "fading")
    OnUpdate(frame, 1)
    eq(frame:IsShown(), false, "gone")
    eq(frame.icon.texture, "Interface\\AddOns\\RevengeTracker\\Media\\Skull", "Revenge's own skull")

    frame = ns.Popup.Show("Mira Thornwood was killed by Gorvak Ashmane", "Duskwood")
    OnUpdate(frame, 1)
    frame:Click()
    OnUpdate(frame, 0.2)
    eq(frame:IsShown(), false, "a click fades it at once")
end)

test("popups stack, three at most", function()
    local ns = LoadAddon()
    for i = 1, 3 do ns.Popup.Show("Alert " .. i) end
    eq(#ShownPopups(ns), 3)
    ns.Popup.frames[1].scripts.OnUpdate(ns.Popup.frames[1], 2)
    ns.Popup.Show("Alert 4")
    eq(#ShownPopups(ns), 3)
    eq(ns.Popup.frames[1].title.text, "Alert 4", "the oldest was reused")
end)

---------------------------------------------------------------------------
local function GuildKill(id, killers, kind, extra)
    local fields = { kind or "K", "Anna Bright", "1-AAAA0001", id, tostring(Mock.now - 30), "1431", "420", "610",
                     extra or "" }
    for _, k in ipairs(killers) do
        for _, f in ipairs({ k, "", "", "" }) do fields[#fields + 1] = f end
    end
    return table.concat(fields, "\t")
end

test("a guildmate's death just now alerts once; answers and repeats don't", function()
    local ns = LoadAddon(nil, true)
    Mock.units.player = { name = "Mira", surname = "Thornwood", guid = "Player-1-0000MIRA", faction = "Alliance" }
    Mock.Fire("PLAYER_LOGIN")
    Mock.guild["Player-1-AAAA0001"] = true
    Mock.Deliver(GuildKill("k1", { "Gorvak Ashmane" }), "Anna")
    eq(#Lines(), 0, "waits a moment for the rest of the death")
    Mock.Advance(1)
    eq(table.concat(Lines(), " / "), "Anna Bright (guild) was killed by Gorvak Ashmane in Duskwood.")
    eq(ShownPopups(ns)[1].title.text, "Anna Bright (guild) was killed by Gorvak Ashmane")
    eq(ShownPopups(ns)[1].detail.text, "Duskwood")
    Mock.Deliver(GuildKill("k1", { "Gorvak Ashmane" }), "Anna")
    Mock.Deliver(GuildKill("k2", { "Shazra Vex" }, "R"), "Anna")
    Mock.Advance(2)
    eq(#Lines(), 0, "a repeat and a catch-up answer don't alert")
    eq(count(RevengeTrackerDB.kills), 2)
end)

test("a death in several messages alerts once, naming its killers", function()
    LoadAddon(nil, true)
    Mock.units.player = { name = "Mira", surname = "Thornwood", guid = "Player-1-0000MIRA", faction = "Alliance" }
    Mock.Fire("PLAYER_LOGIN")
    Mock.Deliver(GuildKill("k5", { "Gorvak Ashmane", "Shazra Vex" }), "Anna")
    Mock.Deliver(GuildKill("k5", { "Velka Duskmantle", "Ruskar Redtusk" }), "Anna")
    Mock.Advance(1)
    eq(table.concat(Lines(), " / "),
       "Anna Bright was killed by Gorvak Ashmane, Shazra Vex, Velka Duskmantle, +1 more in Duskwood.")
end)

test("a shared test kill alerts as a test; the alert can be switched off", function()
    LoadAddon(nil, true)
    Mock.units.player = { name = "Mira", surname = "Thornwood", guid = "Player-1-0000MIRA", faction = "Alliance" }
    Mock.Fire("PLAYER_LOGIN")
    Mock.Deliver(GuildKill("k9", { "Gorvak Ashmane" }, "K", "t"), "Anna")
    Mock.Advance(1)
    eq(table.concat(Lines(), " / "), "Anna Bright was killed by Gorvak Ashmane in Duskwood. (test)")
    RevengeTrackerDB.settings.alertFriendKilled = false
    Mock.Deliver(GuildKill("k10", { "Shazra Vex" }), "Anna")
    Mock.Advance(1)
    eq(#Lines(), 0)
end)
