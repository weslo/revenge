-- A small mock of the WoW: Forever API, enough to load Revenge and drive it from tests.
-- Mock.Reset() restores a clean world before each test.
Mock = {}

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
Mock.SECRET = SECRET

---------------------------------------------------------------------------
-- Lua 5.1 has no bit library; WoW provides one.
---------------------------------------------------------------------------
bit = {
    band = function(a, b)
        local result, place = 0, 1
        while a > 0 and b > 0 do
            local ra, rb = a % 2, b % 2
            if ra == 1 and rb == 1 then result = result + place end
            a, b, place = (a - ra) / 2, (b - rb) / 2, place * 2
        end
        return result
    end,
}

function wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

---------------------------------------------------------------------------
-- Secret values: Mock.SECRET stands for a value addons may not touch.
---------------------------------------------------------------------------
function canaccessvalue(v) return v ~= SECRET end
function issecretvalue(v) return v == SECRET end

---------------------------------------------------------------------------
-- Clock, timers, events
---------------------------------------------------------------------------
function GetServerTime() return Mock.now end
function GetTime() return Mock.clock end

C_Timer = {
    After = function(delay, fn)
        table.insert(Mock.timers, { at = Mock.clock + delay, fn = fn })
    end,
}

-- Advances the timer clock, running due timers in order.
function Mock.Advance(seconds)
    local target = Mock.clock + seconds
    while true do
        table.sort(Mock.timers, function(a, b) return a.at < b.at end)
        local nextTimer = Mock.timers[1]
        if not nextTimer or nextTimer.at > target then break end
        table.remove(Mock.timers, 1)
        Mock.clock = nextTimer.at
        nextTimer.fn()
    end
    Mock.clock = target
    Mock.now = Mock.now + math.floor(seconds)
end

---------------------------------------------------------------------------
-- Widgets: frames, font strings and textures share one forgiving stand-in.
-- Methods that matter to tests (text, scripts, shown state, scroll box rows)
-- are real; any other capitalized method is accepted and does nothing, so UI
-- code runs end to end. Addon fields must start lower-case to be stored.
---------------------------------------------------------------------------
local function NoOp() end
local W = {}
local WidgetMeta = {
    __index = function(_, key)
        local method = W[key]
        if method then return method end
        if type(key) == "string" and key:match("^%u") then return NoOp end
        return nil
    end,
}

local function NewWidget(kind, parent, template)
    local widget = setmetatable({ kind = kind, parent = parent, template = template, scripts = {},
                                  text = nil, shown = true }, WidgetMeta)
    if Mock.frames then table.insert(Mock.frames, widget) end
    if template == "InputBoxInstructionsTemplate" then
        widget.Instructions = NewWidget("FontString", widget)
    end
    return widget
end

function W:RegisterEvent(event)
    Mock.events[event] = Mock.events[event] or {}
    table.insert(Mock.events[event], self)
end
function W:SetScript(name, fn) self.scripts[name] = fn end
function W:GetScript(name) return self.scripts[name] end
function W:SetText(text) self.text = text end
function W:GetText() return self.text or "" end
function W:SetTextColor(r, g, b) self.color = { r, g, b } end
function W:SetVertexColor(r, g, b) self.color = { r, g, b } end
function W:SetAlpha(alpha) self.alpha = alpha end
function W:GetAlpha() return self.alpha or 1 end
function W:SetTexture(texture) self.texture = texture end
function W:SetParent(parent) self.parent = parent end
function W:SetPoint(...) self.points = self.points or {} table.insert(self.points, { ... }) end
function W:ClearAllPoints() self.points = {} end
function W:Show() self.shown = true end
function W:Hide() self.shown = false end
function W:SetShown(shown) self.shown = not not shown end
function W:IsShown() return self.shown end
function W:IsVisible() return self.shown end
function W:Click() if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end
function W:CreateFontString() return NewWidget("FontString", self) end
function W:CreateTexture() return NewWidget("Texture", self) end
-- Scroll boxes: SetDataProvider "renders" every item into pooled row frames.
function W:SetDataProvider(provider)
    self.pool = self.pool or {}
    self.rendered = {}
    local view = self.view
    for i, item in ipairs(provider.items) do
        local row = self.pool[i] or NewWidget("Frame", self, view.template)
        self.pool[i] = row
        view.initializer(row, item)
        self.rendered[i] = row
    end
end

function CreateFrame(kind, _, parent, template)
    return NewWidget(kind or "Frame", parent, template)
end
UIParent = NewWidget("Frame")
function PlaySound(sound, channel) table.insert(Mock.sounds, { sound = sound, channel = channel }) end

function CreateScrollBoxListLinearView()
    local view = {}
    function view:SetElementInitializer(template, fn) self.template, self.initializer = template, fn end
    function view:SetElementExtent(extent) self.extent = extent end
    return view
end
function CreateDataProvider(items) return { items = items or {} } end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, _, view) box.view = view end }
ScrollBoxConstants = { RetainScrollPosition = true }
LOCALIZED_CLASS_NAMES_MALE = { ROGUE = "Rogue", HUNTER = "Hunter", MAGE = "Mage", WARRIOR = "Warrior" }

function Mock.Fire(event, ...)
    for _, frame in ipairs(Mock.events[event] or {}) do
        local script = frame.scripts.OnEvent
        if script then script(frame, event, ...) end
    end
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------
DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, text) table.insert(Mock.chat, text) end,
}

-- Addon messages: what Revenge sends lands in Mock.sent. Mock.sendResults holds the
-- results the game gives the next sends (0, success, when empty).
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) Mock.prefixes[prefix] = true return 0 end,
    SendAddonMessage = function(prefix, text, channel, target)
        local result = table.remove(Mock.sendResults, 1) or 0
        if result == 0 then
            table.insert(Mock.sent, { prefix = prefix, text = text, channel = channel, target = target })
        end
        return result
    end,
    InChatMessagingLockdown = function() return Mock.chatLockdown end,
}

-- A message arriving as the game would deliver it (default: on the guild channel).
function Mock.Deliver(text, sender, channel, prefix)
    Mock.Fire("CHAT_MSG_ADDON", prefix or "RVNG1", text, channel or "GUILD", sender, "", 0, 0, "", 0)
end

-- Battle.net game data from a friend's game account.
function Mock.DeliverBN(text, gameAccountID, prefix)
    Mock.Fire("BN_CHAT_MSG_ADDON", prefix or "RVNG1", text, "WHISPER", gameAccountID)
end

---------------------------------------------------------------------------
-- The world map: data providers draw pins into Mock.pins.
---------------------------------------------------------------------------
function CreateFromMixins(...)
    local t = {}
    for _, mixin in ipairs({ ... }) do for k, v in pairs(mixin) do t[k] = v end end
    return t
end
function Mixin(object, ...)
    for _, mixin in ipairs({ ... }) do for k, v in pairs(mixin) do object[k] = v end end
    return object
end
MapCanvasDataProviderMixin = {
    OnAdded = function(self, map) self.owningMap = map end,
    GetMap = function(self) return self.owningMap end,
    RemoveAllData = function() end,
    RefreshAllData = function() end,
}
MapCanvasPinMixin = {
    SetScalingLimits = function() end,
    UseFrameLevelType = function() end,
    SetPosition = function(self, x, y) self.x, self.y = x, y end,
    ShouldMouseButtonBePassthrough = function(_, button) return button == "RightButton" end,
}
WorldMapFrame = NewWidget("Frame")
WorldMapFrame.AddDataProvider = function(self, provider)
    table.insert(Mock.mapProviders, provider)
    provider:OnAdded(self)
end
WorldMapFrame.GetMapID = function() return Mock.shownMap end
WorldMapFrame.AcquirePin = function(self, template, ...)
    local pin = NewWidget("Frame", self, template)
    Mixin(pin, RevengeTrackerKillPinMixin)
    pin.Icon = NewWidget("Texture", pin)
    pin.owningMap = self
    pin:OnLoad()
    pin:OnAcquired(...)
    table.insert(Mock.pins, pin)
    return pin
end
WorldMapFrame.RemoveAllPinsByTemplate = function() Mock.pins = {} end

-- Shows the world map at mapID, as the game would: the providers redraw.
function Mock.ShowMap(mapID)
    Mock.shownMap = mapID
    WorldMapFrame.shown = true
    for _, provider in ipairs(Mock.mapProviders) do provider:RefreshAllData() end
    return Mock.pins
end

MenuUtil = {
    CreateContextMenu = function(owner, generator)
        local root = { items = {} }
        function root:CreateTitle(text) table.insert(self.items, { title = text }) end
        function root:CreateButton(text, fn) table.insert(self.items, { text = text, fn = fn }) end
        generator(owner, root)
        Mock.menu = root.items
    end,
}

---------------------------------------------------------------------------
-- Units: Mock.units[token] = { name, surname, guid, class, level, guild, faction }
---------------------------------------------------------------------------
local function U(unit) return Mock.units[unit] end

function UnitIsPlayer(unit) return U(unit) ~= nil end
function UnitGUID(unit) local u = U(unit) return u and u.guid end
function UnitFullName(unit)
    local u = U(unit)
    if u then return u.name, u.surname end
end
function GetUnitName(unit)
    local u = U(unit)
    if u then return u.surname and (u.name .. "-" .. u.surname) or u.name end
end
function UnitClass(unit)
    local u = U(unit)
    if u then return u.class, u.class, 1 end
end
function UnitLevel(unit) local u = U(unit) return u and u.level or 0 end
function UnitFactionGroup(unit) local u = U(unit) return u and u.faction, u and u.faction end
function GetGuildInfo(unit) local u = U(unit) return u and u.guild end
function RegionalUniqueNamesEnabled() return Mock.uniqueNames end

-- Mock.byGuid[guid] = { name, class, level } for GetPlayerInfoByGUID
function GetPlayerInfoByGUID(guid)
    local p = Mock.byGuid[guid]
    if p then return p.class, p.class, "Race", "RACE", 2, p.name, "Realm", p.level end
end
function IsGuildMember(guid) return Mock.guild[guid] == true end
function IsInGuild() return Mock.inGuild end
function Ambiguate(name) return name end
-- Friends: Mock.friendList = { { name, connected, guid } }; Mock.bnFriends = { gameAccountInfo tables }.
C_FriendList = {
    IsFriend = function(guid) return Mock.friends[guid] == true end,
    ShowFriends = function() end,
    GetNumFriends = function() return #Mock.friendList end,
    GetFriendInfoByIndex = function(i) return Mock.friendList[i] end,
}
BNET_CLIENT_WOW = "WoW"
WOW_PROJECT_ID = 18
function BNGetNumFriends() return #Mock.bnFriends end
C_BattleNet = {
    GetFriendAccountInfo = function(i)
        local game = Mock.bnFriends[i]
        if game then return { gameAccountInfo = game } end
    end,
    GetGameAccountInfoByID = function(id)
        for _, game in ipairs(Mock.bnFriends) do if game.gameAccountID == id then return game end end
    end,
    GetGameAccountInfoByGUID = function(guid)
        for _, game in ipairs(Mock.bnFriends) do if game.playerGuid == guid then return game end end
    end,
}
function BNSendGameData(id, prefix, text)
    local result = table.remove(Mock.sendResults, 1)
    if result == nil or result == 0 then
        table.insert(Mock.sent, { prefix = prefix, text = text, channel = "BN", target = id })
    end
    return result
end

-- Nameplates: Mock.plates[unit] is the base plate frame.
C_NamePlate = { GetNamePlateForUnit = function(unit) return Mock.plates[unit] end }
SOUNDKIT = { MAP_PING = 3175 }

---------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------
function IsInInstance() return Mock.inInstance, Mock.inInstance and "party" or "none" end
function GetRealZoneText() return Mock.zone end
function InCombatLockdown() return Mock.inCombat end
C_Map = {
    GetBestMapForUnit = function() return Mock.mapID end,
    GetMapRectOnMap = function(from, to)
        local rect = Mock.mapRects[from .. ">" .. to]
        if rect then return rect[1], rect[2], rect[3], rect[4] end
    end,
    GetMapInfo = function(mapID)
        local name = Mock.maps[mapID]
        if name then return { mapID = mapID, name = name } end
    end,
    GetPlayerMapPosition = function()
        if not Mock.position then return nil end
        local p = { x = Mock.position[1], y = Mock.position[2] }
        function p:GetXY() return self.x, self.y end
        return p
    end,
}
C_DeathRecap = {
    HasRecapEvents = function() return Mock.recap ~= nil and #Mock.recap > 0 end,
    GetRecapEvents = function() return Mock.recap end,
}
-- Addons: Mock.loaded[name] is true once loaded. Mock.addonFiles[name] loads a
-- load-on-demand addon's files (tests/run.lua); Mock.disabled[name] makes it refuse.
C_AddOns = {
    GetAddOnMetadata = function() return "0.1.0-test" end,
    IsAddOnLoaded = function(name) return Mock.loaded[name] == true end,
    LoadAddOn = function(name)
        if Mock.loaded[name] then return true end
        local load = Mock.addonFiles[name]
        if not load then return false, "MISSING" end
        if Mock.disabled[name] then return false, "DISABLED" end
        Mock.loaded[name] = true
        Mock.loadCount[name] = (Mock.loadCount[name] or 0) + 1
        load()
        Mock.Fire("ADDON_LOADED", name)
        return true
    end,
}
Mock.addonFiles = {}

-- A high-resolution clock in milliseconds. Each read moves it on by Mock.profileStep;
-- tests make work "slow" by adding to Mock.profile.
function debugprofilestop()
    Mock.profile = Mock.profile + Mock.profileStep
    return Mock.profile
end

-- Runs n frames of `elapsed` seconds each: timers first, then every OnUpdate script.
function Mock.Frames(n, elapsed)
    elapsed = elapsed or 0.02
    for _ = 1, n or 1 do
        Mock.Advance(elapsed)
        local frames = {}
        for i, frame in ipairs(Mock.frames) do frames[i] = frame end
        for _, frame in ipairs(frames) do
            local script = frame.scripts.OnUpdate
            if script then script(frame, elapsed) end
        end
    end
end

function IsInRaid() return Mock.inRaid end
function GetNumGroupMembers() return Mock.groupSize end
function GetRealmName() return "Realm" end

---------------------------------------------------------------------------
-- Keys, tooltip, settings
---------------------------------------------------------------------------
function IsShiftKeyDown() return Mock.keys.shift end
function IsControlKeyDown() return Mock.keys.ctrl end
function IsAltKeyDown() return Mock.keys.alt end

Enum = {
    TooltipDataType = { Unit = 2 },
    SendAddonMessageResult = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3,
        InvalidChatType = 4, NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8,
        GeneralError = 9, NotInGuild = 10, AddOnMessageLockdown = 11, TargetOffline = 12 },
}
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn)
        Mock.tooltipCalls[kind] = Mock.tooltipCalls[kind] or {}
        table.insert(Mock.tooltipCalls[kind], fn)
    end,
}

GameTooltip = {
    lines = {},
    unit = nil,
    shown = false,
    AddLine = function(self, text) table.insert(self.lines, text) end,
    GetUnit = function(self) return "name", self.unit end,
    SetOwner = function(self, owner) self.owner = owner end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end,
    RefreshData = function(self) Mock.Hover(self.unit) end,
}

-- Shows the unit tooltip for `unit` and returns the lines addons added.
function Mock.Hover(unit)
    GameTooltip.lines, GameTooltip.unit, GameTooltip.shown = {}, unit, true
    for _, fn in ipairs(Mock.tooltipCalls[Enum.TooltipDataType.Unit] or {}) do fn(GameTooltip) end
    return GameTooltip.lines
end

MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }

-- The settings list: initializers in page order. Mock.ShowSettings() displays the
-- page, calling each custom element's InitFrame with a frame from its template.
local function Initializer(template, data)
    return { template = template, data = data or {}, AddSearchTags = NoOp }
end
local function AddToPage(kind)
    return function() table.insert(Mock.page, { kind = kind }) end
end
function CreateSettingsListSectionHeaderInitializer(name)
    local initializer = Initializer("SettingsListSectionHeaderTemplate", { name = name })
    initializer.kind = "header"
    return initializer
end

function Mock.ShowSettings()
    local frames = {}
    for _, initializer in ipairs(Mock.page) do
        if initializer.InitFrame then
            local frame = Mock.pageFrames[initializer] or CreateFrame("Frame", nil, nil, initializer.template)
            Mock.pageFrames[initializer] = frame
            frame.shown = true
            initializer:InitFrame(frame)
            frames[#frames + 1] = frame
        end
    end
    return frames
end

Settings = {
    VarType = { Boolean = "boolean", String = "string", Number = "number" },
    RegisterVerticalLayoutCategory = function(name)
        Mock.settingsCategory = { name = name, GetID = function() return 42 end }
        local layout = { AddInitializer = function(_, initializer) table.insert(Mock.page, initializer) end }
        return Mock.settingsCategory, layout
    end,
    CreateElementInitializer = Initializer,
    SetOnValueChangedCallback = function(variable, fn) Mock.valueCallbacks[variable] = fn end,
    RegisterAddOnSetting = function(_, variable, key, tbl, varType, name, default)
        Mock.settings[variable] = { key = key, tbl = tbl, varType = varType, name = name, default = default }
        return Mock.settings[variable]
    end,
    CreateCheckbox = AddToPage("checkbox"),
    CreateSliderOptions = function() return { SetLabelFormatter = NoOp } end,
    CreateSlider = AddToPage("slider"),
    CreateControlTextContainer = function()
        local data = {}
        return { Add = function(_, value, label) table.insert(data, { value = value, label = label }) end,
                 GetData = function() return data end }
    end,
    CreateDropdown = AddToPage("dropdown"),
    RegisterAddOnCategory = function(category) Mock.registeredCategory = category end,
    OpenToCategory = function(id) Mock.openedCategory = id end,
}

SlashCmdList = {}

---------------------------------------------------------------------------
function Mock.Reset()
    Mock.now = 1795600000
    Mock.clock = 0
    Mock.timers = {}
    Mock.events = {}
    Mock.chat = {}
    Mock.units = {
        player = { name = "Anna", surname = "Bright", guid = "Player-1-AAAA0001", class = "PRIEST",
                   level = 40, guild = "Dawn Watch", faction = "Alliance" },
    }
    Mock.byGuid = {}
    Mock.guild = {}
    Mock.friends = {}
    Mock.inInstance = false
    Mock.zone = "Duskwood"
    Mock.mapID = 1431
    Mock.position = { 0.42, 0.61 }
    Mock.recap = nil
    Mock.keys = { shift = false, ctrl = false, alt = false }
    Mock.tooltipCalls = {}
    Mock.settings = {}
    Mock.settingsCategory, Mock.registeredCategory, Mock.openedCategory = nil, nil, nil
    Mock.page, Mock.pageFrames = {}, {}
    Mock.valueCallbacks = {}
    Mock.uniqueNames = true
    Mock.sent, Mock.sendResults, Mock.prefixes = {}, {}, {}
    Mock.sounds = {}
    Mock.friendList, Mock.bnFriends, Mock.plates = {}, {}, {}
    Mock.pins, Mock.mapProviders, Mock.shownMap, Mock.menu, Mock.mapRects = {}, {}, nil, nil, {}
    WorldMapFrame.shown = false
    Mock.inGuild, Mock.inCombat, Mock.chatLockdown = true, false, false
    Mock.maps = { [1431] = "Duskwood", [1433] = "Redridge Mountains" }
    GameTooltip.lines, GameTooltip.unit, GameTooltip.shown = {}, nil, false
    Mock.frames = {}
    Mock.loaded, Mock.disabled, Mock.loadCount = { RevengeTracker = true }, {}, {}
    Mock.profile, Mock.profileStep = 0, 0.001
    Mock.inRaid, Mock.groupSize = false, 0
end
