-- Kill on Sight (REQ-029): the players on your Kill on Sight list, as "Wanted by" you.
-- Its Forever build sends no messages, so this reads its saved data, read-only, while
-- it's loaded. Format as read from its source at 8ec0efb (v4.0.3 Forever, 2026-11-25):
--
--   KillOnSightDB.global.data.players["first last"] =
--     { name = "First Last", class = "ROGUE", reason, addedBy = "First Last",
--       addedAt = time(), lastSeenAt, ... }
--
-- Everything in `players` is kill on sight; its "Honoured" list is a separate table
-- and isn't read, nor are backups or old per-realm copies. Removing a player from
-- Kill on Sight deletes the entry, so after reading the whole list, Revenge drops the
-- marks that only Kill on Sight gave for players no longer on it.
local _, mod = ...

local MAX_ENTRIES = 1000
local SLICE = 25

local function Import(emit, pause)
    local db = _G.KillOnSightDB
    local global = type(db) == "table" and db.global
    local data = type(global) == "table" and global.data
    local players = type(data) == "table" and data.players
    if type(players) ~= "table" then return false end
    local core = mod.Core()
    local me = core and core.SelfName()
    if not me then return true end
    -- Take the keys first: the list can change between slices.
    local keys = {}
    for key in pairs(players) do
        if type(key) ~= "string" then return false end
        keys[#keys + 1] = key
        if #keys >= MAX_ENTRIES then return true end
    end
    local listed = {}
    for i, key in ipairs(keys) do
        local entry = players[key]
        if entry ~= nil then
            if type(entry) ~= "table" then return false end
            local name = mod.Name(type(entry.name) == "string" and entry.name or key)
            -- Old entries with a first name only could match anyone with that name;
            -- Kill on Sight itself never alerts on them, so neither does Revenge.
            if name and name:find(" ", 1, true) then
                listed[#listed + 1] = name
                -- Your list: marked by you, unless an old sync put a guildmate's name here.
                local by = mod.Name(entry.addedBy)
                if not by or not by:find(" ", 1, true) or core.IsSelf(by) then by = me end
                local class = type(entry.class) == "string" and entry.class:match("^%u+$") and entry.class or nil
                local at = type(entry.addedAt) == "number" and entry.addedAt or 1000000000
                if not emit({ type = "wanted", target = { name = name, class = class }, by = { name = by }, at = at,
                              fp = key .. "|" .. at }) then
                    return true
                end
            end
        end
        if i % SLICE == 0 then pause() end
    end
    core.SyncMarks("killonsight", listed)
    return true
end

mod.Register({
    id = "killonsight",
    addons = { "KillOnSight", "KillOnSight-forever" },
    Import = Import,
})
