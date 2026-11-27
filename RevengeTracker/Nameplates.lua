-- Nameplates (REQ-007): a small skull beside the nameplate of a recent killer or a
-- Wanted player. Revenge never touches the plate itself: the skull is its own frame,
-- parented to the base plate the game hands out (C_NamePlate.GetNamePlateForUnit), so
-- it sits beside the game's plate or a nameplate addon's alike and follows its scale
-- and fade. Open world only; a hidden identity, a forbidden plate or any error means
-- no skull, never an error. (Recipe from Revenge Book's Forever code.)
local _, ns = ...

local Nameplates = ns.RegisterModule("Nameplates", {})
local Identity, Store, Tooltip = ns.Identity, ns.Store, ns.Tooltip
local Try = ns.Try

local SIZE = 16
local GAP = 2

local marks = {}    -- unit token -> skull frame
local free = {}     -- skull frames not in use
local units = {}    -- unit tokens that have a nameplate now
Nameplates.marks = marks

local function Release(unit)
    local mark = marks[unit]
    if not mark then return end
    marks[unit] = nil
    mark:Hide()
    mark:ClearAllPoints()
    free[#free + 1] = mark
end

local function Acquire()
    local mark = table.remove(free)
    if mark then return mark end
    mark = CreateFrame("Frame")
    mark:SetSize(SIZE, SIZE)
    mark:EnableMouse(false)
    mark.icon = mark:CreateTexture(nil, "ARTWORK")
    mark.icon:SetAllPoints()
    mark.icon:SetTexture(ns.SKULL_TEXTURE)
    local color = ns.Colors.you
    mark.icon:SetVertexColor(color[1], color[2], color[3])
    return mark
end

-- Whether this player gets the skull: a recent kill, or a Wanted mark you can see.
function Nameplates.Marked(identity, now)
    if not identity or Identity.IsSelf(identity) then return false end
    return #Tooltip.RecentKillsBy(identity, now) > 0 or #Tooltip.WantedMarksOn(identity) > 0
end

local function Plate(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local plate = ns.Accessible(Try(C_NamePlate.GetNamePlateForUnit, unit))
    if type(plate) ~= "table" then return nil end
    if plate.IsForbidden and Try(plate.IsForbidden, plate) then return nil end
    return plate
end

-- The diagnostic log notes the first time each player got the skull this session.
local logged = {}

local function LogSkull(identity, now)
    local id = identity.guid or identity.key
    if not id or logged[id] or not ns.Diagnostics.On() then return end
    logged[id] = true
    ns.Log("skull", "%s: %s", identity.name, Tooltip.Summary(identity, now))
end

local function Update(unit)
    if Store.Setting("nameplates") ~= true or Try(IsInInstance) then return Release(unit) end
    local plate = Plate(unit)
    local identity, now = Identity.FromUnit(unit), ns.Now()
    if not (plate and Nameplates.Marked(identity, now)) then return Release(unit) end
    local mark = marks[unit] or Acquire()
    marks[unit] = mark
    mark:SetParent(plate)
    mark:ClearAllPoints()
    mark:SetPoint("RIGHT", plate, "LEFT", -GAP, 0)
    mark:Show()
    LogSkull(identity, now)
end

local function ReleaseAll()
    for unit in pairs(marks) do Release(unit) end
end

function Nameplates:OnLogin()
    ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
        unit = ns.AccessibleString(unit)
        if not unit then return end
        units[unit] = true
        Update(unit)
    end)
    ns.On("NAME_PLATE_UNIT_REMOVED", function(unit)
        unit = ns.AccessibleString(unit)
        if not unit then return end
        units[unit] = nil
        Release(unit)
    end)
    ns.On("PLAYER_ENTERING_WORLD", function()
        ReleaseAll()
        wipe(units)
    end)
    -- Kills, marks, expiry or the setting changed: look at every plate again.
    ns.OnChange(function()
        for unit in pairs(units) do Update(unit) end
    end)
end
