-- MapPins (REQ-010, REQ-020): a skull on the world map where each recent death
-- happened, coloured by whose death it was (you, a friend, a guildmate). Hover for who
-- and when; right-click for "Dismiss kill", which removes that kill everywhere.
--
-- Built the way the game's own map pins are (Blizzard_MapCanvas): a data provider on
-- WorldMapFrame, and pins from the RevengeTrackerKillPinTemplate in Templates.xml.
-- Kills recorded on a zone also show on the maps that contain it. While you're in
-- combat, changes wait until it ends, so the map is never touched mid-fight.
local _, ns = ...

local MapPins = ns.RegisterModule("MapPins", {})
local L = ns.L
local Identity, Store = ns.Identity, ns.Store
local Try = ns.Try

local TEMPLATE = "RevengeTrackerKillPinTemplate"
local MAX_PINS = 100
local MAX_KILLER_NAMES = 3
local GREY = { 0.6, 0.6, 0.6 }

local provider
local refreshAfterCombat = false
local lastLogged                 -- "mapID:pins" last written to the diagnostic log

-- The pin template names this mixin (Templates.xml). It's filled in once the map's
-- own pin mixin exists, before any pin is made.
RevengeTrackerKillPinMixin = RevengeTrackerKillPinMixin or {}

-- Where a kill goes on the map being shown (0..1), or nil if it isn't on it.
function MapPins.Position(kill, mapID)
    if not (kill.mapID and kill.x and kill.y and mapID) then return nil end
    if kill.mapID == mapID then return kill.x, kill.y end
    if not (C_Map and C_Map.GetMapRectOnMap) then return nil end
    local minX, maxX, minY, maxY = Try(C_Map.GetMapRectOnMap, kill.mapID, mapID)
    minX, maxX, minY, maxY = ns.AccessibleNumber(minX), ns.AccessibleNumber(maxX),
        ns.AccessibleNumber(minY), ns.AccessibleNumber(maxY)
    if not (minX and maxX and minY and maxY) then return nil end
    local x, y = minX + (maxX - minX) * kill.x, minY + (maxY - minY) * kill.y
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

local function ColorOf(kill)
    return ns.Colors[Identity.Group(kill.victim) or "guild"]
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

-- The pin's tooltip lines: { text, r, g, b }.
function MapPins.TooltipLines(kill, now)
    local color = ColorOf(kill)
    local lines = {
        { Identity.LongName(kill.victim), color[1], color[2], color[3] },
        { L.PIN_KILLED_BY:format(KillerNames(kill)), 1, 1, 1 },
    }
    local ago = ns.Ago((now or ns.Now()) - kill.at)
    if #kill.killers == 1 then
        local killer = Identity.Resolve(kill.killers[1])
        lines[#lines + 1] = { ns.List.WhoText(killer) .. " · " .. ago, 1, 1, 1 }
    else
        lines[#lines + 1] = { ago, 1, 1, 1 }
    end
    lines[#lines + 1] = { L.PIN_DISMISS_HINT, GREY[1], GREY[2], GREY[3] }
    return lines
end

-- Removes a kill everywhere: tooltip count, nameplate skull, list and map.
function MapPins.Dismiss(id)
    if not Store.GetKill(id) then return end
    local kill = Store.GetKill(id)
    Store.Dismiss(id)
    ns.Log("list", "dismissed %s's death (killed by %s) from the map", kill.victim.name, ns.Diagnostics.Names(kill.killers))
    ns.Changed()
end

local function ShowMenu(pin)
    local kill = pin.kill
    if not (kill and MenuUtil and MenuUtil.CreateContextMenu) then return end
    local id, title = kill.id, Identity.LongName(kill.victim)
    MenuUtil.CreateContextMenu(pin, function(_, root)
        root:CreateTitle(title)
        root:CreateButton(L.PIN_DISMISS, function() ns.Try(MapPins.Dismiss, id) end)
        root:CreateButton(L.PIN_CANCEL, function() end)
    end)
end
MapPins.ShowMenu = ShowMenu

local function DefinePinMixin()
    local Pin = Mixin(RevengeTrackerKillPinMixin, MapCanvasPinMixin)

    function Pin:OnLoad()
        self:SetScalingLimits(1, 0.8, 0.8)   -- about the same size on screen at any zoom
        self:UseFrameLevelType("PIN_FRAME_LEVEL_CORPSE")
    end

    function Pin:OnAcquired(kill)
        self.kill = kill
        local color = ColorOf(kill)
        self.Icon:SetVertexColor(color[1], color[2], color[3])
    end

    function Pin:OnMouseEnter()
        if not self.kill then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, line in ipairs(MapPins.TooltipLines(self.kill)) do
            GameTooltip:AddLine(line[1], line[2], line[3], line[4])
        end
        GameTooltip:Show()
    end

    function Pin:OnMouseLeave()
        GameTooltip:Hide()
    end

    -- The map lets right-clicks through to zoom out; this pin keeps them for its menu.
    function Pin:ShouldMouseButtonBePassthrough()
        return false
    end

    function Pin:OnMouseClickAction(button)
        if button == "RightButton" then ShowMenu(self) end
    end
end

local function Refresh(self)
    self:RemoveAllData()
    if Store.Setting("mapPins") ~= true then return end
    local map = self:GetMap()
    local mapID = map and ns.AccessibleNumber(Try(map.GetMapID, map))
    if not mapID then return end
    local now = ns.Now()
    local kills = {}
    for _, kill in pairs(Store.AllKills()) do
        if Store.IsRecent(kill, now) then kills[#kills + 1] = kill end
    end
    table.sort(kills, function(a, b) return a.at > b.at end)
    local shown = 0
    for _, kill in ipairs(kills) do
        local x, y = MapPins.Position(kill, mapID)
        if x then
            local pin = map:AcquirePin(TEMPLATE, kill)
            pin:SetPosition(x, y)
            shown = shown + 1
            if shown >= MAX_PINS then break end
        end
    end
    -- Noted when a map shows pins, once per map and number of pins.
    local key = mapID .. ":" .. shown
    if shown > 0 and key ~= lastLogged and ns.Diagnostics.On() then
        lastLogged = key
        local info = C_Map and Try(C_Map.GetMapInfo, mapID)
        ns.Log("pins", "%d on %s (map %d)", shown, type(info) == "table" and info.name or "?", mapID)
    end
end

local function Attach()
    if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and CreateFromMixins and Mixin
        and MapCanvasDataProviderMixin and MapCanvasPinMixin) then
        return
    end
    DefinePinMixin()
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
    end
    function provider:RefreshAllData()
        local ok, err = pcall(Refresh, self)
        if not ok then ns.Fail("map pins error: %s", tostring(err)) end
    end
    WorldMapFrame:AddDataProvider(provider)
    MapPins.provider = provider
end

local function RefreshIfShown()
    if not (provider and WorldMapFrame and WorldMapFrame:IsShown()) then return end
    if Try(InCombatLockdown) then
        refreshAfterCombat = true
        return
    end
    provider:RefreshAllData()
end

function MapPins:OnLogin()
    Attach()
    ns.On("ADDON_LOADED", function(name)
        if name == "Blizzard_WorldMap" then Attach() end
    end)
    ns.On("PLAYER_REGEN_ENABLED", function()
        if refreshAfterCombat then
            refreshAfterCombat = false
            RefreshIfShown()
        end
    end)
    ns.OnChange(RefreshIfShown)
end
