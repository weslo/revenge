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
C_FriendList = { IsFriend = function(guid) return Mock.friends[guid] == true end }

---------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------
function IsInInstance() return Mock.inInstance, Mock.inInstance and "party" or "none" end
function GetRealZoneText() return Mock.zone end
function InCombatLockdown() return false end
C_Map = {
    GetBestMapForUnit = function() return Mock.mapID end,
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
C_AddOns = { GetAddOnMetadata = function() return "0.1.0-test" end }

---------------------------------------------------------------------------
-- Keys, tooltip, settings
---------------------------------------------------------------------------
function IsShiftKeyDown() return Mock.keys.shift end
function IsControlKeyDown() return Mock.keys.ctrl end
function IsAltKeyDown() return Mock.keys.alt end

Enum = { TooltipDataType = { Unit = 2 } }
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
    GameTooltip.lines, GameTooltip.unit, GameTooltip.shown = {}, nil, false
end
