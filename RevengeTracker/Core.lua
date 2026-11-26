-- Core: shared helpers, the event dispatcher, start-up order and the slash command.
local addonName, ns = ...
local L = ns.L

ns.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"

---------------------------------------------------------------------------
-- Restricted ("secret") values. Forever can hide some unit values from addons.
-- These return nil instead of a value we may not touch, so callers never
-- compare, format or store a secret by accident.
---------------------------------------------------------------------------
local canaccessvalue, issecretvalue = _G.canaccessvalue, _G.issecretvalue

function ns.Accessible(value)
    if value == nil then return nil end
    if canaccessvalue and not canaccessvalue(value) then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

function ns.AccessibleString(value)
    value = ns.Accessible(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

function ns.AccessibleNumber(value)
    value = ns.Accessible(value)
    if type(value) ~= "number" then return nil end
    return value
end

-- Calls fn(...) and returns its results, or nothing if it errored.
function ns.Try(fn, ...)
    if type(fn) ~= "function" then return end
    local results = { pcall(fn, ...) }
    if not results[1] then
        ns.Debug("error: %s", tostring(results[2]))
        return
    end
    return unpack(results, 2, table.maxn(results))
end

function ns.Now()
    return GetServerTime()
end

-- "5m ago", "2h ago", "3d ago"
function ns.Ago(seconds)
    seconds = math.max(0, seconds)
    if seconds < 3600 then return L.AGO_MINUTES:format(math.max(1, math.floor(seconds / 60))) end
    if seconds < 86400 then return L.AGO_HOURS:format(math.floor(seconds / 3600)) end
    return L.AGO_DAYS:format(math.floor(seconds / 86400))
end

-- "1 day", "7 days"
function ns.DaysText(value)
    value = math.floor(value + 0.5)
    return value == 1 and L.DAYS_ONE or L.DAYS_MANY:format(value)
end

---------------------------------------------------------------------------
-- Chat output
---------------------------------------------------------------------------
function ns.Print(fmt, ...)
    local text = select("#", ...) > 0 and fmt:format(...) or fmt
    DEFAULT_CHAT_FRAME:AddMessage(L.PREFIX .. ": " .. text)
end

function ns.Debug(fmt, ...)
    local db = ns.db
    if not (db and db.debug) then return end
    local ok, text = pcall(string.format, fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888Revenge debug:|r " .. (ok and text or tostring(fmt)))
end

---------------------------------------------------------------------------
-- Events: modules subscribe with ns.On(event, handler). Every handler is
-- isolated, so one module's error can't stop the others.
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, handler)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], handler)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then ns.Debug("%s handler error: %s", event, tostring(err)) end
    end
end)

-- Data changes: anything showing kills or Wanted marks (the settings list now;
-- nameplates and map pins later) subscribes with ns.OnChange(fn). Merge and the
-- list call ns.Changed() after changing stored data.
local changeListeners = {}

function ns.OnChange(fn)
    changeListeners[#changeListeners + 1] = fn
end

function ns.Changed()
    for i = 1, #changeListeners do
        local ok, err = pcall(changeListeners[i])
        if not ok then ns.Debug("change listener error: %s", tostring(err)) end
    end
end

-- Runs fn after delay seconds, isolated like an event handler.
function ns.After(delay, fn)
    C_Timer.After(delay, function()
        local ok, err = pcall(fn)
        if not ok then ns.Debug("timer error: %s", tostring(err)) end
    end)
end

---------------------------------------------------------------------------
-- Start-up: saved data first, then each module in order.
---------------------------------------------------------------------------
ns.modules = {}

function ns.RegisterModule(name, module)
    module.name = name
    table.insert(ns.modules, module)
    ns[name] = module
    return module
end

ns.On("ADDON_LOADED", function(loaded)
    if loaded ~= addonName then return end
    ns.Store.Init()
    for _, module in ipairs(ns.modules) do
        if module.Init then
            local ok, err = pcall(module.Init, module)
            if not ok then ns.Debug("%s init error: %s", module.name, tostring(err)) end
        end
    end
end)

ns.On("PLAYER_LOGIN", function()
    for _, module in ipairs(ns.modules) do
        if module.OnLogin then
            local ok, err = pcall(module.OnLogin, module)
            if not ok then ns.Debug("%s login error: %s", module.name, tostring(err)) end
        end
    end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
local function ShowHelp()
    ns.Print(L.HELP_HEADER)
    for _, line in ipairs({ L.HELP_OPEN, L.HELP_ADD, L.HELP_TEST, L.HELP_TEST_CLEAR, L.HELP_DEBUG }) do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
    end
end

local commands = {}

function commands.test(rest)
    if rest == "clear" then
        ns.Print(L.TEST_CLEARED, ns.Store.RemoveTestKills())
        return
    end
    local killer = ns.Identity.FromUnit("target")
    if not killer or not ns.Try(UnitIsPlayer, "target") then
        ns.Print(L.TEST_NEED_PLAYER)
        return
    end
    ns.Deaths.RecordTestKill(killer)
    ns.Print(L.TEST_ADDED, killer.name)
end

function commands.add(rest)
    local _, message = ns.List.AddByName(rest)
    ns.Print(message)
end

function commands.debug()
    ns.db.debug = not ns.db.debug or nil
    ns.Print(ns.db.debug and L.DEBUG_ON or L.DEBUG_OFF)
end

function commands.help()
    ShowHelp()
end

SLASH_REVENGETRACKER1 = "/revenge"
SlashCmdList.REVENGETRACKER = function(input)
    local command, rest = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "" then
        ns.Settings.Open()
    elseif commands[command] then
        commands[command](rest)
    else
        ShowHelp()
    end
end
