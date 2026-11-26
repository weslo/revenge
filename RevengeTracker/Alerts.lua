-- Alerts (REQ-008, REQ-009, REQ-019): two optional alerts, both on by default.
--   - Killer nearby: a recent killer or a Wanted player shows up on a nameplate, as your
--     target or under the mouse. At most once every 5 minutes per player, open world only.
--   - Friend or guildmate killed: their death was just shared (not a catch-up answer).
--     Once per death.
-- Each shows as the small popup (Popup.lua) and/or a chat line. The sound is for the
-- killer-nearby chat line and can be switched off.
local _, ns = ...

local Alerts = ns.RegisterModule("Alerts", {})
local L = ns.L
local Identity, Store = ns.Identity, ns.Store
local Try = ns.Try

local NEARBY_COOLDOWN = 300
local KILLED_DELAY = 1          -- lets the other parts of a death split over messages arrive
local MAX_KILLER_NAMES = 3
-- A short map ping (SoundKitConstants, loaded on Forever): quieter than a raid warning.
local NEARBY_SOUND = SOUNDKIT and SOUNDKIT.MAP_PING

local lastNearby = {}           -- player GUID or key -> time of their last alert

local function Setting(key) return Store.Setting(key) == true end

local function Show(title, detail, chat, sound)
    if Setting("alertPopup") and ns.Popup then ns.Try(ns.Popup.Show, title, detail) end
    if Setting("alertChat") then
        ns.Print(chat)
        if sound and NEARBY_SOUND and Setting("alertSound") then Try(PlaySound, NEARBY_SOUND, "SFX") end
    end
end

-- What a nearby player has against them: "(5) You, Mira, +1 more", "Wanted by Mira",
-- or both. Nil when nothing recent.
local function Summary(identity, now)
    local parts = {}
    local kills = ns.Tooltip.RecentKillsBy(identity, now)
    if #kills > 0 then parts[#parts + 1] = ns.Tooltip.SummaryText(kills) end
    local marks = ns.Tooltip.WantedMarksOn(identity)
    if #marks > 0 then parts[#parts + 1] = ns.Tooltip.WantedText(marks) end
    if #parts == 0 then return nil end
    return table.concat(parts, " · ")
end

-- A player came into view. Returns true if it alerted.
function Alerts.Seen(identity)
    if not (identity and Setting("alertNearby")) or Try(IsInInstance) then return false end
    if Identity.IsSelf(identity) then return false end
    local id = identity.guid or identity.key
    local now = ns.Now()
    if not id or (lastNearby[id] and now - lastNearby[id] < NEARBY_COOLDOWN) then return false end
    local summary = Summary(identity, now)
    if not summary then return false end
    lastNearby[id] = now
    local name = identity.name or "?"
    Show(L.ALERT_NEARBY:format(name), summary, L.ALERT_NEARBY_CHAT:format(name, summary), true)
    return true
end

local function KillerNames(kill)
    local names = {}
    for i = 1, math.min(#kill.killers, MAX_KILLER_NAMES) do names[i] = kill.killers[i].name or "?" end
    local text = table.concat(names, L.LIST_AND)
    if #kill.killers > MAX_KILLER_NAMES then
        text = text .. L.LIST_AND .. L.MORE:format(#kill.killers - MAX_KILLER_NAMES)
    end
    return text
end

-- A friend's or guildmate's death just arrived (Share.lua), as stored after the merge.
function Alerts.FriendKilled(kill)
    if not (kill and Setting("alertFriendKilled")) or Identity.IsSelf(kill.victim) then return end
    ns.After(KILLED_DELAY, function()
        local victim = Identity.LongName(kill.victim)
        local killers = KillerNames(kill)
        local zone = kill.zone
        local test = kill.test and L.ALERT_TEST or ""
        local title = L.ALERT_KILLED:format(victim, killers) .. test
        local chat
        if zone then
            chat = L.ALERT_KILLED_CHAT_ZONE:format(victim, killers, zone) .. test
        else
            chat = L.ALERT_KILLED_CHAT:format(victim, killers) .. test
        end
        Show(title, zone, chat, false)
    end)
end

local function Check(unit)
    if not Setting("alertNearby") then return end
    Alerts.Seen(Identity.FromUnit(unit))
end

function Alerts:OnLogin()
    ns.On("NAME_PLATE_UNIT_ADDED", Check)
    ns.On("PLAYER_TARGET_CHANGED", function() Check("target") end)
    ns.On("UPDATE_MOUSEOVER_UNIT", function() Check("mouseover") end)
end
