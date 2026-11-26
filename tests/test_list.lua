-- The settings list: rows, Remove, Add by name, and the page itself.

local function Gorvak() return { name = "Gorvak Ashmane", key = "gorvak ashmane", guid = "Player-1-0000GORV", class = "ROGUE", level = 41 } end
local function Shazra() return { name = "Shazra Vex", key = "shazra vex", guid = "Player-1-0000SHAZ", class = "HUNTER", level = 39 } end
local function Me() return { name = "Anna Bright", key = "anna bright", guid = "Player-1-AAAA0001" } end
local function Mira() return { name = "Mira Thornwood", key = "mira thornwood", guid = "Player-1-0000MIRA" } end

local function Kill(ns, victim, killers, ago, source)
    return ns.Merge.SubmitKill({ victim = victim, killers = killers, at = Mock.now - ago, precision = "exact",
                                 zone = "Duskwood", mapID = 1431, sources = { [source or "self"] = true }, own = true })
end

local function Describe(ns)
    local out, now = {}, ns.Now()
    for i, row in ipairs(ns.List.Rows(now)) do out[i] = ns.List.Describe(row, now) end
    return out
end

local function RowFor(ns, key)
    for _, row in ipairs(ns.List.Rows()) do
        if row.identity.key == key then return row end
    end
end

local function Hover(name, surname, guid)
    Mock.units.target = { name = name, surname = surname, guid = guid }
    return Mock.Hover("target")
end

test("one row per player, newest first, with kills and Wanted marks", function()
    local ns = LoadAddon()
    Kill(ns, Me(), { Gorvak() }, 7200)
    Kill(ns, Mira(), { Gorvak() }, 86400)
    Kill(ns, Me(), { Shazra() }, 3 * 86400)
    ns.Merge.SubmitWanted({ target = { name = "Darrok Vane", key = "darrok vane" }, by = Mira(),
                            at = Mock.now - 600, sources = { revenge = true }, own = true })
    local rows = Describe(ns)
    eq(#rows, 3)
    eq(rows[1].name, "Darrok Vane")
    eq(rows[1].who, "Not seen yet")
    eq(rows[1].what, "Wanted by Mira")
    eq(rows[1].when, "10m ago")
    eq(rows[2].name, "Gorvak Ashmane")
    eq(rows[2].who, "Level 41 Rogue")
    eq(rows[2].what, "(2) You, Mira")
    eq(rows[2].when, "2h ago")
    eq(rows[3].name, "Shazra Vex")
    eq(rows[3].what, "(1) You")
    eq(rows[3].when, "3d ago")
end)

test("a player with kills and your Wanted mark is one row", function()
    local ns = LoadAddon()
    Kill(ns, Me(), { Gorvak() }, 7200)
    ns.List.AddByName("Gorvak Ashmane")
    local rows = Describe(ns)
    eq(#rows, 1)
    eq(rows[1].what, "(1) You · Wanted by you")
    eq(rows[1].who, "Level 41 Rogue")
end)

test("expired kills make no row; the empty list says when kills drop off", function()
    local ns = LoadAddon()
    Kill(ns, Me(), { Gorvak() }, 8 * 86400)
    eq(#Describe(ns), 0)
    local frame = Mock.ShowSettings()[1]
    eq(frame.titleText.text, "Recent killers (0)")
    ok(frame.emptyText.shown, "empty text shown")
    eq(frame.emptyText.text, "No recent killers. Kills older than 7 days drop off by themselves.")
end)

test("Remove takes the player out of every kill and keeps the other killers", function()
    local ns = LoadAddon()
    Kill(ns, Me(), { Gorvak(), Shazra() }, 7200)
    Kill(ns, Mira(), { Gorvak() }, 86400)
    eq(ns.List.Remove(RowFor(ns, "gorvak ashmane")), "Gorvak Ashmane")
    eq(count(RevengeTrackerDB.kills), 1, "Mira's kill had only Gorvak, so it's gone")
    local _, kill = next(RevengeTrackerDB.kills)
    eq(#kill.killers, 1)
    eq(kill.killers[1].key, "shazra vex")
    eq(#ns.Store.KillsByKiller("Player-1-0000GORV", "gorvak ashmane"), 0, "index rebuilt")
    eq(#Hover("Gorvak", "Ashmane", "Player-1-0000GORV"), 0, "no tooltip line")
    eq(#Hover("Shazra", "Vex", "Player-1-0000SHAZ"), 1, "the other killer keeps theirs")
    eq(Kill(ns, Mira(), { Gorvak() }, 86400, "revenge"), nil, "Mira's death stays dismissed")
end)

test("a removed killer stays removed when the same death is reported again", function()
    local ns = LoadAddon()
    Kill(ns, Me(), { Gorvak(), Shazra() }, 7200)
    ns.List.Remove(RowFor(ns, "gorvak ashmane"))
    -- The same death from another source, a minute off: merged, without Gorvak.
    local kill, new = Kill(ns, Me(), { Gorvak(), Shazra() }, 7200 - 60, "revenge")
    ok(kill, "merged into the kept kill")
    eq(new, false)
    eq(count(RevengeTrackerDB.kills), 1)
    eq(#kill.killers, 1)
    eq(kill.killers[1].key, "shazra vex")
    -- Gorvak alone, by first name only, for that death: nothing to record.
    eq(ns.Merge.SubmitKill({ victim = Me(), killers = { { name = "Gorvak", key = "gorvak", partial = true } },
                             at = Mock.now - 7200, precision = "received", sources = { revenge = true } }), nil)
    -- A new death to Gorvak later still counts.
    ok(Kill(ns, Me(), { Gorvak() }, 60), "new death recorded")
    eq(#Hover("Gorvak", "Ashmane", "Player-1-0000GORV"), 1)
end)

test("removing your Wanted mark withdraws it; someone else's is hidden for you only", function()
    local ns = LoadAddon()
    ns.List.AddByName("Gorvak Ashmane")
    local function MiraMark()
        return ns.Merge.SubmitWanted({ target = { name = "Darrok Vane", key = "darrok vane" }, by = Mira(),
                                       at = Mock.now - 600, sources = { revenge = true }, own = true })
    end
    MiraMark()
    local rows = ns.List.Rows()
    eq(#rows, 2)
    for _, row in ipairs(rows) do ns.List.Remove(row) end
    eq(#ns.List.Rows(), 0)
    local marks = {}
    for _, mark in pairs(RevengeTrackerDB.wanted) do marks[#marks + 1] = mark end
    eq(#marks, 1, "yours is gone")
    eq(marks[1].target.key, "darrok vane")
    ok(marks[1].hidden, "Mira's is kept, hidden")
    ok(RevengeTrackerDB.withdrawals["gorvak ashmane|anna bright"], "withdrawal recorded")
    eq(#Hover("Darrok", "Vane", "Player-1-0000DARR"), 0, "no tooltip line for a hidden mark")
    ok(MiraMark().hidden, "Mira's mark arriving again stays hidden")
    ok(ns.List.AddByName("Gorvak Ashmane"), "you can add Gorvak again at once")
end)

test("the settings page follows the mock-up: Kills, Sharing, Alerts, then the list", function()
    LoadAddon()
    local kinds = {}
    for i, item in ipairs(Mock.page) do
        kinds[i] = item.kind == "header" and ("# " .. item.data.name) or item.kind or item.template
    end
    eq(table.concat(kinds, ", "), table.concat({
        "# Kills", "slider", "dropdown", "checkbox", "checkbox",
        "# Sharing", "checkbox", "checkbox", "checkbox",
        "# Alerts", "checkbox", "checkbox", "checkbox", "checkbox", "checkbox",
        "RevengeTrackerListTemplate" }, ", "))
    eq(Mock.page[#Mock.page]:GetExtent(), 328, "matches the template height")
    local labels = {}
    for _, setting in pairs(Mock.settings) do labels[setting.key] = setting.name end
    eq(labels.nameplates, "Skull beside recent killers' nameplates")
    eq(labels.shareFriends, "…with in-game friends")
    eq(labels.alertPopup, "Show alerts as a small popup (silent, fades quickly)")
end)

test("the list draws one row per player and Remove works from the page", function()
    local ns = LoadAddon()
    Kill(ns, Me(), { Gorvak() }, 7200)
    Kill(ns, Me(), { Shazra() }, 86400)
    local frame = Mock.ShowSettings()[1]
    eq(frame.titleText.text, "Recent killers (2)")
    eq(frame.emptyText.shown, false)
    eq(#frame.scrollBox.rendered, 2)
    local row = frame.scrollBox.rendered[1]
    eq(row.nameText.text, "Gorvak Ashmane")
    eq(row.whoText.text, "Level 41 Rogue")
    eq(row.whatText.text, "(1) You")
    eq(row.whenText.text, "2h ago")
    eq(row.removeButton.text, "Remove")
    row.removeButton:Click()
    eq(frame.statusText.text, "Removed Gorvak Ashmane.")
    eq(frame.titleText.text, "Recent killers (1)")
    eq(#frame.scrollBox.rendered, 1)
    eq(frame.scrollBox.rendered[1].nameText.text, "Shazra Vex")
end)

test("Add by name works from the page; a mistake keeps the text to fix", function()
    LoadAddon()
    local frame = Mock.ShowSettings()[1]
    eq(frame.editBox.Instructions.text, "First Last")
    frame.editBox:SetText("gorvak")
    frame.addButton:Click()
    eq(frame.statusText.text, "Type the player's first and last name.")
    eq(frame.editBox:GetText(), "gorvak", "text kept")
    frame.editBox:SetText("gorvak ashmane")
    frame.editBox.scripts.OnEnterPressed(frame.editBox)
    eq(frame.statusText.text, "Gorvak Ashmane is now wanted by you.")
    eq(frame.editBox:GetText(), "", "cleared")
    eq(frame.scrollBox.rendered[1].whatText.text, "Wanted by you")
    eq(frame.scrollBox.rendered[1].whoText.text, "Not seen yet")
end)

test("the list updates while shown, and catches up when shown again", function()
    local ns = LoadAddon()
    local frame = Mock.ShowSettings()[1]
    eq(#frame.scrollBox.rendered, 0)
    Kill(ns, Me(), { Gorvak() }, 60)
    eq(#frame.scrollBox.rendered, 1, "redrawn on a new kill")
    frame.shown = false
    Kill(ns, Me(), { Shazra() }, 60)
    eq(#frame.scrollBox.rendered, 1, "not redrawn while hidden")
    eq(#Mock.ShowSettings()[1].scrollBox.rendered, 2, "redrawn when shown again")
end)

test("changing the expiry redraws the list at once", function()
    local ns = LoadAddon()
    Kill(ns, Me(), { Gorvak() }, 3 * 86400)
    local frame = Mock.ShowSettings()[1]
    eq(#frame.scrollBox.rendered, 1)
    RevengeTrackerDB.settings.expiryDays = 2
    Mock.valueCallbacks.RevengeTracker_expiryDays()
    eq(#frame.scrollBox.rendered, 0, "the 3-day-old kill dropped off")
    eq(frame.emptyText.text, "No recent killers. Kills older than 2 days drop off by themselves.")
end)

test("/revenge add marks a player from chat", function()
    LoadAddon()
    SlashCmdList.REVENGETRACKER("add Gorvak Ashmane")
    ok(Mock.chat[#Mock.chat]:find("Gorvak Ashmane is now wanted by you.", 1, true), "confirmation in chat")
    eq(count(RevengeTrackerDB.wanted), 1)
end)

test("if the list can't be built, the rest of the settings page still is", function()
    local original = Settings.CreateElementInitializer
    Settings.CreateElementInitializer = function() error("boom") end
    local loaded, err = pcall(LoadAddon)
    Settings.CreateElementInitializer = original
    ok(loaded, tostring(err))
    ok(Mock.registeredCategory, "category registered")
    eq(#Mock.page, 15)
end)
