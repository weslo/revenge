-- Tooltip: one line under a recorded enemy's tooltip, e.g.
--   [skull] (5) You, Mira, Tavish, +1 more
-- and, while the details key is held, one line per recent kill:
--   You · Hillsbrad Foothills · 2h ago
-- A player marked Wanted gets one more line after those:
--   [skull] Wanted by you, Mira
local _, ns = ...

local Tooltip = ns.RegisterModule("Tooltip", {})
local L = ns.L
local Try, AccessibleString = ns.Try, ns.AccessibleString
local Identity, Store = ns.Identity, ns.Store

local SKULL = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t "
local LINE_R, LINE_G, LINE_B = 1, 0.55, 0.43
local DETAIL_R, DETAIL_G, DETAIL_B = 0.79, 0.81, 0.84
local MAX_NAMES = 3
local MAX_DETAILS = 5

Tooltip.SKULL = SKULL

local MODIFIERS = {
    SHIFT = IsShiftKeyDown,
    CTRL = IsControlKeyDown,
    ALT = IsAltKeyDown,
}

local function DetailsWanted()
    local check = MODIFIERS[Store.Setting("detailsModifier")]
    return check and check() or false
end

-- Recent kills by this player, newest first.
function Tooltip.RecentKillsBy(identity, now)
    local recent = {}
    for _, kill in ipairs(Store.KillsByKiller(identity.guid, identity.key)) do
        if Store.IsRecent(kill, now) then
            for _, killer in ipairs(kill.killers) do
                if Identity.Same(killer, identity) then
                    recent[#recent + 1] = kill
                    break
                end
            end
        end
    end
    return recent
end

-- Wanted marks on this player that you haven't hidden, newest first.
function Tooltip.WantedMarksOn(identity)
    local marks = {}
    for _, mark in ipairs(Store.WantedFor(identity.guid, identity.key)) do
        if not mark.hidden and Identity.Same(mark.target, identity) then marks[#marks + 1] = mark end
    end
    return marks
end

-- "You, Mira, Tavish, +1 more": `first` (if any) leads, then the others in order.
local function NameList(first, others)
    local names = {}
    if first then names[1] = first end
    for _, name in ipairs(others) do names[#names + 1] = name end
    local shown = {}
    for i = 1, math.min(#names, MAX_NAMES) do shown[i] = names[i] end
    local text = table.concat(shown, L.LIST_AND)
    if #names > MAX_NAMES then text = text .. L.LIST_AND .. L.MORE:format(#names - MAX_NAMES) end
    return text
end

-- "(5) You, Mira, Tavish, +1 more": You first, then the others newest first.
function Tooltip.SummaryText(kills)
    local seen, others, you = {}, {}, nil
    for _, kill in ipairs(kills) do
        local victim = kill.victim
        local key = victim.guid or victim.key
        if key and not seen[key] then
            seen[key] = true
            if Identity.IsSelf(victim) then
                you = L.YOU
            else
                others[#others + 1] = Identity.ShortName(victim)
            end
        end
    end
    return ("(%d) %s"):format(#kills, NameList(you, others))
end

-- "Wanted by you, Mira": you first, then the other adders newest first.
function Tooltip.WantedText(marks)
    local seen, others, you = {}, {}, nil
    for _, mark in ipairs(marks) do
        local by = mark.by
        local key = by.guid or by.key
        if key and not seen[key] then
            seen[key] = true
            if Identity.IsSelf(by) then
                you = L.YOU_LOWER
            else
                others[#others + 1] = Identity.ShortName(by)
            end
        end
    end
    return L.WANTED_BY:format(NameList(you, others))
end

local function AddLines(tooltip, unit)
    local identity = Identity.FromUnit(unit)
    if not identity then return end
    local now = ns.Now()
    local kills = Tooltip.RecentKillsBy(identity, now)
    if #kills > 0 then
        tooltip:AddLine(SKULL .. Tooltip.SummaryText(kills), LINE_R, LINE_G, LINE_B)
        if DetailsWanted() then
            for i = 1, math.min(#kills, MAX_DETAILS) do
                local kill = kills[i]
                local text = ("%s · %s · %s"):format(Identity.LongName(kill.victim), kill.zone or L.UNKNOWN_ZONE, ns.Ago(now - kill.at))
                tooltip:AddLine(text, DETAIL_R, DETAIL_G, DETAIL_B)
            end
            if #kills > MAX_DETAILS then
                tooltip:AddLine(L.MORE:format(#kills - MAX_DETAILS), DETAIL_R, DETAIL_G, DETAIL_B)
            end
        end
    end
    local marks = Tooltip.WantedMarksOn(identity)
    if #marks > 0 then
        tooltip:AddLine(SKULL .. Tooltip.WantedText(marks), LINE_R, LINE_G, LINE_B)
    end
end

local function OnUnitTooltip(tooltip)
    if tooltip ~= GameTooltip or not ns.db then return end
    local _, unit = Try(tooltip.GetUnit, tooltip)
    unit = AccessibleString(unit)
    if not unit then return end
    AddLines(tooltip, unit)
end

-- Holding or releasing the details key redraws a shown unit tooltip.
local function OnModifierChanged()
    if Store.Setting("detailsModifier") == "OFF" then return end
    if not (GameTooltip and GameTooltip:IsShown()) then return end
    local _, unit = Try(GameTooltip.GetUnit, GameTooltip)
    if not AccessibleString(unit) then return end
    if GameTooltip.RefreshData then Try(GameTooltip.RefreshData, GameTooltip) end
end

function Tooltip:OnLogin()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            local ok, err = pcall(OnUnitTooltip, tooltip)
            if not ok then ns.Debug("tooltip error: %s", tostring(err)) end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip) pcall(OnUnitTooltip, tooltip) end)
    end
    ns.On("MODIFIER_STATE_CHANGED", OnModifierChanged)
end
