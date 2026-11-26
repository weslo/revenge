-- Host: the optional module that reads other addons' data for Revenge (REQ-024,
-- REQ-030, REQ-032; docs/plans/revenge/OTHER-ADDONS.md).
--
-- Revenge loads it on demand, only while "Use data from other addons" is on. It
-- reaches Revenge only through the RevengeTracker global's small API (the core's
-- Foreign.lua), which checks everything again. Ground rules:
--   - listen only: never send in another addon's format, answer its hellos or join
--     its channels;
--   - low priority and silent: every adapter call runs in pcall, work waits in a
--     bounded queue that runs a little each frame (Queue.lua), each adapter has a
--     circuit breaker (Breaker.lua), and nothing is ever printed.
--
-- An adapter (Adapters/*.lua) knows one other addon:
--   { id = "revengebook", prefixes = { "DeathNote" }, channels = { GUILD = true },
--     addons = { "DeathNote" },             -- its folder names, for saved data
--     Decode(prefix, text, channel, sender) -- a list of records (maybe empty: a type
--                                           -- we don't use), or nil if unparseable
--     Import(emit, pause)                   -- optional: reads its saved data }
local addonName, mod = ...

local Queue, Breaker = mod.Queue, mod.Breaker

mod.adapters = {}
local byPrefix = {}
local started = false

local MAX_MESSAGE = 255              -- what the game delivers; longer is junk
local RATE_WINDOW, PER_SENDER = 600, 120
local TRUST_FOR = 60                 -- seconds a sender's trust check is remembered
local IMPORT_FIRST, IMPORT_EVERY = 20, 600

---------------------------------------------------------------------------
-- Helpers for adapters
---------------------------------------------------------------------------
local canaccessvalue, issecretvalue = _G.canaccessvalue, _G.issecretvalue

-- The value, or nil if the game hides it from addons.
function mod.Accessible(value)
    if value == nil then return nil end
    if canaccessvalue and not canaccessvalue(value) then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

function mod.Core()
    local core = _G.RevengeTracker
    return type(core) == "table" and core.API == 1 and core or nil
end

function mod.Debug(fmt, ...)
    local core = mod.Core()
    if core then core.Debug(fmt, ...) end
end

-- Splits text on a plain separator, keeping empty fields. Nil past `max` fields.
function mod.Split(text, sep, max)
    local fields, start = {}, 1
    max = max or 64
    while true do
        local at = text:find(sep, start, true)
        if not at then
            fields[#fields + 1] = text:sub(start)
            return fields
        end
        fields[#fields + 1] = text:sub(start, at - 1)
        if #fields >= max then return nil end
        start = at + #sep
    end
end

-- "gorvak-ashmane" / "GORVAK  ashmane" -> "Gorvak Ashmane"; nil for anything that
-- isn't a plain name (letters in any language, spaces, apostrophes).
function mod.Name(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("[%s%-]+", " "):match("^%s*(.-)%s*$")
    if text == "" or #text > 48 or text:find("[^%a\128-\255 ']") then return nil end
    return (text:gsub("(%S)(%S*)", function(head, tail) return head:upper() .. tail end))
end

-- Whether two names, as the game or another addon writes them, are the same
-- character: "Mira Thornwood", "Mira-Realm", "mira": the first names match, and the
-- surnames too when both have one after a space.
function mod.SameName(a, b)
    local function Parts(name)
        if type(name) ~= "string" then return nil end
        local first, rest = name:match("^(%S+)%s+(.+)$")
        if first then return first:lower(), (rest:match("^([^%-]+)") or rest):lower() end
        return (name:match("^([^%-]+)") or name):lower(), nil
    end
    local af, as = Parts(a)
    local bf, bs = Parts(b)
    if not (af and bf) or af ~= bf then return false end
    return not (as and bs and as ~= bs)
end

-- A whole number in [low, high] from text, or nil.
function mod.Int(text, low, high, base)
    if type(text) ~= "string" or text == "" or #text > 12 then return nil end
    local value = tonumber(text, base or 10)
    if not value or value ~= math.floor(value) or value < low or value > high then return nil end
    return value
end

-- Whether one of these addon folders is loaded.
function mod.AddOnLoaded(names)
    if not (names and C_AddOns and C_AddOns.IsAddOnLoaded) then return false end
    for _, name in ipairs(names) do
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
        if ok and loaded then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Adapters
---------------------------------------------------------------------------
-- Whether an adapter may run now: Revenge uses other addons' data, its switch is on,
-- and its breaker hasn't tripped.
function mod.Usable(adapter)
    local core = mod.Core()
    return core ~= nil and not adapter.breaker.tripped and core.AdapterOn(adapter.id) == true
end

local trustCache = {}

function mod.Trusted(sender, channel)
    if channel == "SAVED" then return true end
    local key = tostring(channel) .. ":" .. tostring(sender)
    local now = GetTime()
    local cached = trustCache[key]
    if cached and now - cached.at < TRUST_FOR then return cached.trusted end
    local core = mod.Core()
    local trusted = core ~= nil and core.Trusted(sender, channel) == true
    trustCache[key] = { at = now, trusted = trusted }
    return trusted
end

local function RegisterPrefixes(adapter)
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
    for _, prefix in ipairs(adapter.prefixes) do pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix) end
end

function mod.Register(adapter)
    if type(adapter) ~= "table" or type(adapter.id) ~= "string" or type(adapter.Decode) ~= "function"
        and type(adapter.Import) ~= "function" then
        return nil
    end
    adapter.prefixes = adapter.prefixes or {}
    adapter.channels = adapter.channels or {}
    adapter.breaker = Breaker.New()
    adapter.reports = 0
    adapter.seen = {}
    adapter.senders = {}
    mod.adapters[#mod.adapters + 1] = adapter
    for _, prefix in ipairs(adapter.prefixes) do
        byPrefix[prefix] = byPrefix[prefix] or {}
        table.insert(byPrefix[prefix], adapter)
    end
    if started then RegisterPrefixes(adapter) end
    return adapter
end

-- Cheap rejection first: at most PER_SENDER messages per sender per adapter in 10 minutes.
local function RateOk(adapter, sender, now)
    local counts = adapter.senders[sender]
    if not counts or now - counts.start > RATE_WINDOW then
        counts = { start = now, n = 0 }
        adapter.senders[sender] = counts
    end
    if counts.n >= PER_SENDER then return false end
    counts.n = counts.n + 1
    return true
end

local function OnAddonMessage(prefix, text, channel, sender)
    prefix = mod.Accessible(prefix)
    local adapters = type(prefix) == "string" and byPrefix[prefix]
    if not adapters then return end
    text, channel, sender = mod.Accessible(text), mod.Accessible(channel), mod.Accessible(sender)
    if type(text) ~= "string" or type(channel) ~= "string" or type(sender) ~= "string" then return end
    if #text > MAX_MESSAGE or #sender > 80 then return end
    local core = mod.Core()
    if not (core and core.Enabled()) or core.IsSelf(sender) then return end
    local now = GetTime()
    for _, adapter in ipairs(adapters) do
        if adapter.channels[channel] and mod.Usable(adapter) and RateOk(adapter, sender, now) then
            Queue.Push({ adapter = adapter, prefix = prefix, text = text, channel = channel, sender = sender })
        end
    end
end

---------------------------------------------------------------------------
-- Saved data: after login, then at most every 10 minutes, one adapter at a time
---------------------------------------------------------------------------
local PUMP_EVERY = 2
local pumping = false

local function AnyDue()
    for _, adapter in ipairs(mod.adapters) do
        if adapter.importDue then return true end
    end
    return false
end

-- Starts the next due import once nothing else is waiting; checks again every few
-- seconds while any is due, and stops when none is.
local function Pump()
    pumping = false
    if not Queue.Busy() then
        for _, adapter in ipairs(mod.adapters) do
            if adapter.importDue then
                adapter.importDue = false
                if Queue.StartImport(adapter) then break end
            end
        end
    end
    if AnyDue() then
        pumping = true
        C_Timer.After(PUMP_EVERY, function()
            local ok, err = pcall(Pump)
            if not ok then mod.Debug("imports: %s", err) end
        end)
    end
end

local function ImportRound()
    local core = mod.Core()
    if not (core and core.Enabled()) then return end
    for _, adapter in ipairs(mod.adapters) do
        if adapter.Import and not adapter.importUnrecognised and mod.AddOnLoaded(adapter.addons) then
            adapter.importDue = true
        end
    end
    if not pumping then Pump() end
end

local function ScheduleImports()
    C_Timer.After(IMPORT_FIRST, function()
        pcall(ImportRound)
        local function Again()
            pcall(ImportRound)
            C_Timer.After(IMPORT_EVERY, Again)
        end
        C_Timer.After(IMPORT_EVERY, Again)
    end)
end

---------------------------------------------------------------------------
-- Status, for Revenge's settings page
---------------------------------------------------------------------------
function mod.Status()
    local core = mod.Core()
    local status = {}
    for _, adapter in ipairs(mod.adapters) do
        local state
        if adapter.breaker.tripped then
            state = "paused"
        elseif not (core and core.AdapterOn(adapter.id)) then
            state = "off"
        elseif adapter.importing then
            state = "reading"
        elseif #adapter.prefixes == 0 then
            state = mod.AddOnLoaded(adapter.addons) and "watching" or "absent"
        else
            state = "listening"
        end
        status[adapter.id] = { state = state, reports = adapter.reports }
    end
    return status
end

---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(function(...)
        if event == "CHAT_MSG_ADDON" then
            OnAddonMessage(...)
        elseif event == "ADDON_LOADED" and ... == addonName and not started then
            started = true
            for _, adapter in ipairs(mod.adapters) do RegisterPrefixes(adapter) end
            frame:RegisterEvent("CHAT_MSG_ADDON")
            local core = mod.Core()
            if core then core.Attach({ Status = mod.Status, Register = mod.Register, Import = ImportRound }) end
            ScheduleImports()
        end
    end, ...)
    if not ok then mod.Debug("host: %s", err) end
end)
