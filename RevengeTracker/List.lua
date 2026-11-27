-- List: the model behind the "Recent killers" list in settings (ListPanel.lua draws it).
--
-- One row per player: their recent kills on you, friends and guildmates, and any
-- Wanted marks on them. Remove takes the player off the list:
--   - their kills: removed from every stored kill they're in (other killers stay),
--     with tombstones so no source brings them back for those deaths;
--   - your own Wanted mark: withdrawn, and the withdrawal shared;
--   - someone else's Wanted mark: hidden for you only.
-- Add by name marks a player "Wanted by you", and shares the mark.
local _, ns = ...

local List = ns.RegisterModule("List", {})
local L = ns.L
local Identity, Store, Merge = ns.Identity, ns.Store, ns.Merge

local MAX_NAME_BYTES = 48

local function ClassName(classFile)
    local names = LOCALIZED_CLASS_NAMES_MALE
    if type(names) == "table" and type(names[classFile]) == "string" then return names[classFile] end
    return classFile:sub(1, 1):upper() .. classFile:sub(2):lower()
end

-- "Level 41 Rogue", "Rogue", "Level 41" or "Not seen yet"
local function WhoText(identity)
    local level, class = identity.level, identity.class
    if level and class then return L.WHO_LEVEL_CLASS:format(level, ClassName(class)) end
    if class then return ClassName(class) end
    if level then return L.WHO_LEVEL:format(level) end
    return L.WHO_UNSEEN
end

List.WhoText = WhoText

-- Rows, newest activity first: { identity, kills = {...}, marks = {...}, latest = time }
function List.Rows(now)
    now = now or ns.Now()
    local rows, byId = {}, {}
    local function RowFor(identity)
        local id = identity.guid or identity.key
        local row = id and byId[id]
        if not row then
            for _, existing in ipairs(rows) do
                if Identity.Same(existing.identity, identity) then row = existing break end
            end
        end
        if not row then
            row = { identity = Identity.Copy(identity), kills = {}, marks = {}, latest = 0 }
            rows[#rows + 1] = row
        else
            -- Combine what each source knows about the player.
            local known = row.identity
            if known.partial and not identity.partial and identity.name then
                known.name, known.key, known.partial = identity.name, identity.key, nil
            end
            for _, field in ipairs({ "guid", "class", "level", "guild", "faction" }) do
                if known[field] == nil then known[field] = identity[field] end
            end
        end
        if id then byId[id] = row end
        return row
    end
    for _, kill in pairs(Store.AllKills()) do
        if Store.IsRecent(kill, now) then
            for _, killer in ipairs(kill.killers) do
                local row = RowFor(killer)
                row.kills[#row.kills + 1] = kill
                if kill.at > row.latest then row.latest = kill.at end
            end
        end
    end
    for _, mark in pairs(Store.AllWanted()) do
        if Store.MarkShown(mark) then
            Identity.Resolve(mark.target)
            local row = RowFor(mark.target)
            row.marks[#row.marks + 1] = mark
            if mark.at > row.latest then row.latest = mark.at end
        end
    end
    local function Newest(a, b) return a.at > b.at end
    for _, row in ipairs(rows) do
        table.sort(row.kills, Newest)
        table.sort(row.marks, Newest)
    end
    table.sort(rows, function(a, b)
        if a.latest ~= b.latest then return a.latest > b.latest end
        return (a.identity.key or "") < (b.identity.key or "")
    end)
    return rows
end

-- What a row shows: { name, who, what, when, row }
function List.Describe(row, now)
    local parts = {}
    if #row.kills > 0 then parts[#parts + 1] = ns.Tooltip.SummaryText(row.kills) end
    if #row.marks > 0 then parts[#parts + 1] = ns.Tooltip.WantedText(row.marks) end
    return {
        name = row.identity.name or "?",
        who = WhoText(row.identity),
        what = table.concat(parts, " · "),
        when = ns.Ago((now or ns.Now()) - row.latest),
        row = row,
    }
end

-- Takes a row's player off the list. Returns their name.
function List.Remove(row)
    local identity = row.identity
    local changed = false
    for _, kill in ipairs(Store.KillsByKiller(identity.guid, identity.key)) do
        if Store.RemoveKiller(kill, identity) then changed = true end
    end
    if changed then Store.RebuildIndexes() end
    local now = ns.Now()
    for _, mark in ipairs(row.marks) do
        if Identity.IsSelf(mark.by) then
            Merge.SubmitWithdrawal({ target = mark.target, by = mark.by, at = now })
            -- Only marks Revenge shared need taking back from others.
            if mark.own then ns.Try(ns.Share and ns.Share.OwnWithdrawal, mark.target, now) end
        else
            mark.hidden = true
        end
        changed = true
    end
    if changed then ns.Changed() end
    ns.Log("list", "took %s off the list", identity.name)
    return identity.name or "?"
end

---------------------------------------------------------------------------
-- Add by name
---------------------------------------------------------------------------
-- "  gorvak   ASHMANE " -> "Gorvak Ashmane", or nil and why not.
-- Only letters (any language), spaces and apostrophes: no escape codes or links.
local function CleanName(text)
    if type(text) ~= "string" then return nil, L.ADD_EMPTY end
    text = text:gsub("[%s%-]+", " "):match("^%s*(.-)%s*$")
    if text == "" then return nil, L.ADD_EMPTY end
    if #text > MAX_NAME_BYTES or text:find("[^%a\128-\255 ']") then return nil, L.ADD_INVALID end
    local words = 0
    text = text:gsub("%S+", function(word)
        words = words + 1
        return word:sub(1, 1):upper() .. word:sub(2):lower()
    end)
    -- Forever names are "First Last"; a first name alone could match many players.
    if words < 2 and ns.Try(RegionalUniqueNamesEnabled) then return nil, L.ADD_NEED_FULL end
    return text
end

-- Marks a player "Wanted by you". Returns ok, and a message to show.
function List.AddByName(text)
    local name, problem = CleanName(text)
    if not name then return false, problem end
    local me = Identity.Self()
    if not (me and me.key and ns.db) then return false, L.ADD_FAILED end
    local target = Identity.Make(name, nil)
    if target.key == me.key then return false, L.ADD_SELF end
    -- Seen before? Then use the game's spelling, GUID, class and level.
    local guid, cached = Identity.FindByName(target.key)
    if guid then
        target.guid = guid
        target.name, target.key, target.partial = cached.n, Identity.Key(cached.n), nil
        Identity.Resolve(target)
        if me.faction and target.faction == me.faction then
            return false, L.ADD_SAME_FACTION:format(target.name)
        end
    end
    for _, mark in ipairs(Store.WantedFor(target.guid, target.key)) do
        if Identity.Same(mark.target, target) and Identity.IsSelf(mark.by) then
            return false, L.ADD_ALREADY:format(mark.target.name or name)
        end
    end
    local by = Identity.Copy(me)
    Store.ClearWithdrawal(Merge.PairKey(target, by))
    local mark = Merge.SubmitWanted({ target = target, by = by, at = ns.Now(), sources = { self = true }, own = true })
    if not mark then return false, L.ADD_FAILED end
    ns.Log("list", "marked %s Wanted by you", mark.target.name or name)
    ns.Try(ns.Share and ns.Share.OwnWanted, mark)
    return true, L.ADD_DONE:format(mark.target.name or name)
end
