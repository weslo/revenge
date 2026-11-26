-- Test runner: loads Revenge into the mock world fresh for every test.
-- Run with:  .venv\Scripts\python.exe -I tests\run.py [filter]
local ROOT, FILTER = ...

dofile(ROOT .. "/tests/wow_mock.lua")

local function TocFiles()
    local files = {}
    for line in io.lines(ROOT .. "/RevengeTracker/RevengeTracker.toc") do
        line = line:match("^%s*(.-)%s*$")
        -- XML files hold frame templates, which the mock doesn't need.
        if line ~= "" and not line:match("^#") and not line:lower():match("%.xml$") then
            files[#files + 1] = ROOT .. "/RevengeTracker/" .. line:gsub("\\", "/")
        end
    end
    return files
end

-- Loads the addon as the game would: each file gets (addonName, ns).
-- savedDB is what RevengeTrackerDB held on disk, or nil for a first run.
function LoadAddon(savedDB, skipLogin)
    Mock.Reset()
    RevengeTrackerDB = savedDB
    RevengeTracker = nil
    local ns = {}
    for _, path in ipairs(TocFiles()) do
        local chunk = assert(loadfile(path))
        chunk("RevengeTracker", ns)
    end
    Mock.Fire("ADDON_LOADED", "RevengeTracker")
    if not skipLogin then Mock.Fire("PLAYER_LOGIN") end
    return ns
end

---------------------------------------------------------------------------
-- A tiny test framework
---------------------------------------------------------------------------
local tests = {}
function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function Show(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function eq(actual, expected, label)
    if actual ~= expected then
        error((label and (label .. ": ") or "") .. "expected " .. Show(expected) .. ", got " .. Show(actual), 2)
    end
end

function ok(value, label)
    if not value then error((label or "expected a true value") .. ", got " .. Show(value), 2) end
end

function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

for _, file in ipairs({ "test_identity", "test_merge", "test_foreign", "test_deaths", "test_tooltip", "test_store", "test_wanted", "test_list", "test_share" }) do
    dofile(ROOT .. "/tests/" .. file .. ".lua")
end

local passed, failed = 0, 0
for _, t in ipairs(tests) do
    if not FILTER or FILTER == "" or t.name:find(FILTER, 1, true) then
        local success, err = pcall(t.fn)
        if success then
            passed = passed + 1
        else
            failed = failed + 1
            print("FAIL " .. t.name .. "\n     " .. tostring(err))
        end
    end
end
print(string.format("%d passed, %d failed", passed, failed))
return failed
