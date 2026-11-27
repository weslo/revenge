-- Breaker: one per adapter. An adapter switches itself off for the rest of the session
-- after any of (REQ-032, DEC-020):
--   - 5 errors;
--   - more than half of its last 50 messages failing to parse;
--   - 3 overruns of its time budget (one call taking longer than Queue.OVERRUN_MS).
-- Its status then reads "paused: the other addon may have changed". It tries again
-- next session.
local _, mod = ...

local Breaker = {}
mod.Breaker = Breaker

Breaker.ERRORS = 5
Breaker.WINDOW = 50
Breaker.OVERRUNS = 3

function Breaker.New()
    return { errors = 0, overruns = 0, results = {}, at = 0, fails = 0, tripped = false }
end

local function Trip(breaker, why)
    if breaker.tripped then return end
    breaker.tripped, breaker.why = true, why
end

function Breaker.Error(breaker)
    breaker.errors = breaker.errors + 1
    if breaker.errors >= Breaker.ERRORS then Trip(breaker, "errors") end
end

function Breaker.Overrun(breaker)
    breaker.overruns = breaker.overruns + 1
    if breaker.overruns >= Breaker.OVERRUNS then Trip(breaker, "slow") end
end

-- One message handled: parsed (true) or not (false). The last WINDOW are kept.
function Breaker.Parsed(breaker, parsed)
    breaker.at = breaker.at % Breaker.WINDOW + 1
    if breaker.results[breaker.at] == false then breaker.fails = breaker.fails - 1 end
    breaker.results[breaker.at] = parsed and true or false
    if not parsed then
        breaker.fails = breaker.fails + 1
        if breaker.fails * 2 > Breaker.WINDOW then Trip(breaker, "unparseable") end
    end
end
