-- Tooltip: one line under a recorded enemy's tooltip, e.g.
--   [skull] (5) You, Mira, Tavish, +1 more
-- and, while the details key is held, one line per recent kill:
--   You · Hillsbrad Foothills · 2h ago
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

local MODIFIERS = {
    SHIFT = IsShiftKeyDown,
    CTRL = IsControlKeyDown,
    ALT = IsAltKeyDown,
}

local function DetailsWanted()
    local check = MODIFIERS[Store.Setting("detailsModifier")]
    return check and check() or false
end

local function Ago(seconds)
    if seconds < 3600 then return L.AGO_MINUTES:format(math.max(1, math.floor(seconds / 60))) end
    if seconds < 86400 then return L.AGO_HOURS:format(math.floor(seconds / 3600)) end
    return L.AGO_DAYS:format(math.floor(seconds / 86400))
end

-- Recent kills by this unit's player, newest first.
local function RecentKills(unit)
    local identity = Identity.FromUnit(unit)
    if not identity then return nil end
    local now, recent = ns.Now(), {}
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
    return recent, now
end

-- "(5) You, Mira, Tavish, +1 more": You first, then the others newest first.
local function SummaryText(kills)
    local names, seen, others = {}, {}, {}
    for _, kill in ipairs(kills) do
        local victim = kill.victim
        local key = victim.guid or victim.key
        if key and not seen[key] then
            seen[key] = true
            if Identity.IsSelf(victim) then
                table.insert(names, 1, L.YOU)
            else
                others[#others + 1] = Identity.ShortName(victim)
            end
        end
    end
    for _, name in ipairs(others) do names[#names + 1] = name end
    local shown = {}
    for i = 1, math.min(#names, MAX_NAMES) do shown[i] = names[i] end
    local text = ("(%d) %s"):format(#kills, table.concat(shown, L.LIST_AND))
    if #names > MAX_NAMES then text = text .. L.LIST_AND .. L.MORE:format(#names - MAX_NAMES) end
    return text
end

local function AddLines(tooltip, unit)
    local kills, now = RecentKills(unit)
    if not kills or #kills == 0 then return end
    tooltip:AddLine(SKULL .. SummaryText(kills), LINE_R, LINE_G, LINE_B)
    if DetailsWanted() then
        for i = 1, math.min(#kills, MAX_DETAILS) do
            local kill = kills[i]
            local text = ("%s · %s · %s"):format(Identity.LongName(kill.victim), kill.zone or L.UNKNOWN_ZONE, Ago(now - kill.at))
            tooltip:AddLine(text, DETAIL_R, DETAIL_G, DETAIL_B)
        end
        if #kills > MAX_DETAILS then
            tooltip:AddLine(L.MORE:format(#kills - MAX_DETAILS), DETAIL_R, DETAIL_G, DETAIL_B)
        end
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
