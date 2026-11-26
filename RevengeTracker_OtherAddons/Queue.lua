-- Queue: other addons' work waits here and runs later, a little each frame, behind
-- everything else (REQ-032, DEC-020):
--   - messages wait in a bounded queue (200; the oldest drop when it's full);
--   - each frame spends at most 0.5 ms on them, then on saved-data imports;
--   - nothing runs in combat;
--   - at most 20 records a second go to Revenge's merge;
--   - one adapter call longer than 2 ms counts as an overrun (Breaker.lua).
-- With nothing waiting, no frame script runs at all.
local _, mod = ...

local Queue = {}
mod.Queue = Queue

Queue.MAX = 200
Queue.BUDGET_MS = 0.5
Queue.OVERRUN_MS = 2
Queue.PER_SECOND = 20
Queue.IMPORT_MAX = 500          -- records one import run may hand over
Queue.SUBMIT_CHUNK = 50         -- records per call to Revenge

local Breaker = mod.Breaker
local items, first, last = {}, 1, 0
local job                       -- the saved-data import running now, if any
local window = { start = -1, n = 0 }
local frame

local function Size() return last - first + 1 end

local function Pop()
    if first > last then return nil end
    local item = items[first]
    items[first] = nil
    first = first + 1
    return item
end

local function Clock() return debugprofilestop() end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() and true or false
end

-- Hands records to Revenge, which checks them all again. Returns how many it took.
local function Submit(adapter, records, sender, channel)
    window.n = window.n + #records
    local core = mod.Core()
    if not core then return 0 end
    local taken = core.SubmitForeign(records, adapter.id, sender, channel)
    if type(taken) ~= "number" then taken = 0 end
    adapter.reports = adapter.reports + taken
    return taken
end

local function RunMessage(item)
    local adapter = item.adapter
    if not mod.Usable(adapter) or not mod.Trusted(item.sender, item.channel) then return end
    local started = Clock()
    local ok, records = pcall(adapter.Decode, item.prefix, item.text, item.channel, item.sender)
    if Clock() - started > Queue.OVERRUN_MS then Breaker.Overrun(adapter.breaker) end
    if not ok then
        Breaker.Error(adapter.breaker)
        mod.Debug("%s: %s", adapter.id, records)
        return
    end
    if type(records) ~= "table" then
        Breaker.Parsed(adapter.breaker, false)
        return
    end
    Breaker.Parsed(adapter.breaker, true)
    if #records > 0 then Submit(adapter, records, item.sender, item.channel) end
end

local function EndJob(result)
    local adapter = job.adapter
    adapter.importing = false
    if result == false then adapter.importUnrecognised = true end
    job = nil
end

local function FlushJob()
    local batch = job.batch
    job.batch = {}
    for i = 1, #batch, Queue.SUBMIT_CHUNK do
        local chunk = {}
        for j = i, math.min(i + Queue.SUBMIT_CHUNK - 1, #batch) do chunk[#chunk + 1] = batch[j] end
        Submit(job.adapter, chunk, nil, "SAVED")
    end
end

-- One slice of the running import.
local function RunJob()
    local adapter = job.adapter
    if not mod.Usable(adapter) then return EndJob() end
    local started = Clock()
    local ok, result = coroutine.resume(job.co)
    if Clock() - started > Queue.OVERRUN_MS then Breaker.Overrun(adapter.breaker) end
    if not ok then
        Breaker.Error(adapter.breaker)
        mod.Debug("%s import: %s", adapter.id, result)
        job.batch = {}
        return EndJob()
    end
    FlushJob()
    if coroutine.status(job.co) == "dead" or job.emitted >= Queue.IMPORT_MAX then EndJob(result) end
end

local function Step()
    if InCombat() then return end
    local now = GetTime()
    if now - window.start >= 1 then window.start, window.n = now, 0 end
    local deadline = Clock() + Queue.BUDGET_MS
    while Clock() < deadline and window.n < Queue.PER_SECOND do
        local item = Pop()
        if item then
            RunMessage(item)
        elseif job then
            RunJob()
        else
            break
        end
    end
    if first > last and not job then frame:SetScript("OnUpdate", nil) end
end

local function Wake()
    if not frame then frame = CreateFrame("Frame") end
    frame:SetScript("OnUpdate", function()
        local ok, err = pcall(Step)
        if not ok then mod.Debug("queue: %s", err) end
    end)
end

-- A message for an adapter: { adapter, prefix, text, channel, sender }.
function Queue.Push(item)
    if Size() >= Queue.MAX then Pop() end
    last = last + 1
    items[last] = item
    Wake()
end

-- Starts reading an adapter's saved data, unless an import is already running.
-- adapter.Import(emit, pause) reads a slice, calls pause() between slices and returns
-- false at a structure it doesn't recognise. emit(record) returns false once the run
-- has handed over enough. A record with an `fp` (fingerprint) seen earlier this
-- session is skipped, so later runs hand over only what's new.
function Queue.StartImport(adapter)
    if job or not adapter.Import or not mod.Usable(adapter) then return false end
    local run = { adapter = adapter, batch = {}, emitted = 0 }
    local function Emit(record)
        if run.emitted >= Queue.IMPORT_MAX then return false end
        if type(record) ~= "table" then return true end
        local fp = record.fp
        if fp ~= nil then
            if adapter.seen[fp] then return true end
            adapter.seen[fp] = true
            record.fp = nil
        end
        run.batch[#run.batch + 1] = record
        run.emitted = run.emitted + 1
        return run.emitted < Queue.IMPORT_MAX
    end
    run.co = coroutine.create(function() return adapter.Import(Emit, coroutine.yield) end)
    job = run
    adapter.importing = true
    Wake()
    return true
end

function Queue.Busy()
    return first <= last or job ~= nil
end
