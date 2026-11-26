-- Share: your own deaths and Wanted marks go to guildmates running Revenge, and
-- theirs come in through the same merge as your own. Protocol.lua encodes the
-- messages; docs/plans/revenge/PROTOCOL.md has the rules. In short:
--   - everyone sends only their own data, so nothing travels second-hand;
--   - the guild channel only, for now (friends and Battle.net come later);
--   - after login you say hello, and guildmates answer with what you missed;
--   - with "Share my deaths and wanted players with my guild" off, nothing of yours
--     is sent and hellos aren't answered. You still receive.
-- Anything malformed, or not the sender's own, is dropped without a word.
local _, ns = ...

local Share = ns.RegisterModule("Share", {})
local Protocol, Identity, Store = ns.Protocol, ns.Identity, ns.Store
local Try = ns.Try

local PREFIX = Protocol.PREFIX
local CHANNEL = "GUILD"

-- Catch-up
local HELLO_DELAY, HELLO_JITTER = 10, 5
local LOOKBACK = 86400              -- a hello asks for at least the last day
local SINCE_OVERLAP = 600
local ANSWER_DELAY_MIN, ANSWER_DELAY_MAX = 2, 8
local ANSWER_GAP = 10               -- seconds between two answers
local HELLO_REPEAT = 300            -- a guildmate's hello is answered at most this often
local ANSWER_KILLS, ANSWER_MARKS, ANSWER_WITHDRAWALS = 20, 20, 10
local WITHDRAWAL_AGE = 30 * 86400

-- Receiving
local MAX_AGE, MAX_FUTURE = 30 * 86400, 300
local RATE_WINDOW, PER_SENDER, IN_ALL = 600, 80, 400
local MARKS_PER_ADDER = 50
local MAX_SENDER = 80               -- bytes in a sender's name as the game gives it

-- Sending
local BURST, PER_SECOND = 8, 1
local BACKOFF, TRIES = 2, 5
local QUEUE_MAX, QUEUE_TTL = 120, 600
local HOLD_RETRY = 30

local function Me()
    local me = Identity.Self()
    if me and me.name then return me end
end

local function CanShare()
    return ns.db ~= nil and Store.Setting("shareGuild") == true and Try(IsInGuild) and Me() ~= nil
end

---------------------------------------------------------------------------
-- The send queue: up to BURST at once, then PER_SECOND; waits out combat,
-- instances and the game's chat lockdown; backs off when throttled.
---------------------------------------------------------------------------
local queue, pumpScheduled = {}, false
local tokens, refilledAt = BURST, nil
local RESULT = (Enum and Enum.SendAddonMessageResult) or {}

local function Held()
    if Try(InCombatLockdown) then return true end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and Try(C_ChatInfo.InChatMessagingLockdown) then return true end
    if Try(IsInInstance) then return true end
    return false
end

-- "ok", "throttle", "retry" or "drop", from pcall(SendAddonMessage, ...).
local function Outcome(ok, result)
    if not ok then return "retry" end
    if result == nil or result == true or result == (RESULT.Success or 0) then return "ok" end
    if result == false then return "retry" end
    if result == (RESULT.AddonMessageThrottle or 3) or result == (RESULT.ChannelThrottle or 8) then return "throttle" end
    if result == (RESULT.AddOnMessageLockdown or 11) or result == (RESULT.GeneralError or 9) then return "retry" end
    return "drop"  -- not in a guild, an invalid channel or message: waiting won't help
end

local Pump

local function Schedule(delay)
    if pumpScheduled then return end
    pumpScheduled = true
    ns.After(delay, Pump)
end

Pump = function()
    pumpScheduled = false
    local clock = GetTime()
    tokens = math.min(BURST, tokens + (clock - (refilledAt or clock)) * PER_SECOND)
    refilledAt = clock
    while queue[1] do
        local item = queue[1]
        if ns.Now() - item.queued > QUEUE_TTL then
            table.remove(queue, 1)
        elseif Held() then
            return Schedule(HOLD_RETRY)
        elseif tokens < 1 then
            return Schedule((1 - tokens) / PER_SECOND)
        else
            local outcome = Outcome(pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.text, item.channel, item.target))
            if outcome == "ok" then
                table.remove(queue, 1)
                tokens = tokens - 1
            elseif outcome == "drop" then
                table.remove(queue, 1)
                ns.Debug("share: the game refused a message")
            else
                item.tries = item.tries + 1
                if item.tries >= TRIES then
                    table.remove(queue, 1)
                else
                    if outcome == "throttle" then tokens = 0 end
                    return Schedule(BACKOFF * 2 ^ (item.tries - 1))
                end
            end
        end
    end
end

local function Enqueue(text)
    if not (text and C_ChatInfo and C_ChatInfo.SendAddonMessage) or #queue >= QUEUE_MAX then return false end
    queue[#queue + 1] = { text = text, channel = CHANNEL, queued = ns.Now(), tries = 0 }
    Schedule(0)
    return true
end

function Share.QueueLength()
    return #queue
end

---------------------------------------------------------------------------
-- Your own data, as it happens
---------------------------------------------------------------------------
-- A death of yours (Deaths.lua). Returns how many messages were queued.
function Share.OwnKill(kill)
    if not (kill and CanShare() and Identity.IsSelf(kill.victim)) then return 0 end
    local queued = 0
    for _, text in ipairs(Protocol.Kill("K", Me(), kill)) do
        if Enqueue(text) then queued = queued + 1 end
    end
    return queued
end

-- A player you marked Wanted (List.lua).
function Share.OwnWanted(mark)
    if not (mark and CanShare() and Identity.IsSelf(mark.by)) then return false end
    return Enqueue(Protocol.Wanted(Me(), mark))
end

-- You withdrew your mark on target at `at` (List.lua).
function Share.OwnWithdrawal(target, at)
    if not (target and CanShare()) then return false end
    return Enqueue(Protocol.Withdrawal(Me(), target.name or target.key, at))
end

---------------------------------------------------------------------------
-- Catch-up: hello after login, answers to guildmates' hellos
---------------------------------------------------------------------------
local helloSent, helloScheduled = false, false
local pendingSince, answerScheduled, lastAnswerAt = nil, false, nil
local helloAnswered = {}

-- What a hello asks for: since you were last online (less an overlap), at least a
-- day back, and no further back than your expiry.
function Share.HelloSince(now)
    now = now or ns.Now()
    local floor = now - Store.Setting("expiryDays") * 86400
    local since = floor
    if ns.db.lastSeen then since = math.max(floor, math.min(ns.db.lastSeen - SINCE_OVERLAP, now - LOOKBACK)) end
    return math.floor(since)
end

local function SendHello()
    helloScheduled = false
    if helloSent or not Try(IsInGuild) or not Me() then return end
    local text = Protocol.Hello(Me(), Share.HelloSince(), ns.VERSION)
    if text and Enqueue(text) then helloSent = true end
end

local function ScheduleHello()
    if helloSent or helloScheduled then return end
    helloScheduled = true
    ns.After(HELLO_DELAY + math.random() * HELLO_JITTER, SendHello)
end

local function Newest(a, b) return a.at > b.at end

local function Take(list, limit)
    table.sort(list, Newest)
    for i = #list, limit + 1, -1 do list[i] = nil end
    return list
end

local function OwnKillsSince(since, now)
    local kills = {}
    for _, kill in pairs(Store.AllKills()) do
        if not kill.test and kill.at >= since and now - kill.at <= MAX_AGE and Identity.IsSelf(kill.victim) then
            kills[#kills + 1] = kill
        end
    end
    return Take(kills, ANSWER_KILLS)
end

local function OwnMarks()
    local marks = {}
    for _, mark in pairs(Store.AllWanted()) do
        if Identity.IsSelf(mark.by) then marks[#marks + 1] = mark end
    end
    return Take(marks, ANSWER_MARKS)
end

-- Withdrawals are stored as "target key|adder key" = time.
local function OwnWithdrawals(me, now)
    local list = {}
    for pair, at in pairs(ns.db.withdrawals) do
        local targetKey, adderKey = pair:match("^(.*)|(.*)$")
        if adderKey == me.key and now - at <= WITHDRAWAL_AGE then
            list[#list + 1] = { key = targetKey, at = at }
        end
    end
    return Take(list, ANSWER_WITHDRAWALS)
end

local function SendAnswer()
    answerScheduled = false
    lastAnswerAt = GetTime()
    local since = pendingSince
    pendingSince = nil
    local me = Me()
    if not (since and me and CanShare()) then return end
    local now = ns.Now()
    for _, kill in ipairs(OwnKillsSince(since, now)) do
        for _, text in ipairs(Protocol.Kill("R", me, kill)) do Enqueue(text) end
    end
    for _, mark in ipairs(OwnMarks()) do Enqueue(Protocol.Wanted(me, mark)) end
    for _, withdrawal in ipairs(OwnWithdrawals(me, now)) do
        Enqueue(Protocol.Withdrawal(me, withdrawal.key, withdrawal.at))
    end
end

local function OnHello(msg, senderKey, now)
    if not CanShare() then return end
    if helloAnswered[senderKey] and now - helloAnswered[senderKey] < HELLO_REPEAT then return end
    helloAnswered[senderKey] = now
    pendingSince = math.min(pendingSince or msg.since, msg.since)
    if answerScheduled then return end
    answerScheduled = true
    local wait = ANSWER_DELAY_MIN + math.random() * (ANSWER_DELAY_MAX - ANSWER_DELAY_MIN)
    if lastAnswerAt then wait = math.max(wait, lastAnswerAt + ANSWER_GAP - GetTime()) end
    ns.After(wait, SendAnswer)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local senderCounts, inAll = {}, { start = 0, n = 0 }

local function Allow(senderKey, now)
    if now - inAll.start > RATE_WINDOW then inAll.start, inAll.n = now, 0 end
    local counts = senderCounts[senderKey]
    if not counts or now - counts.start > RATE_WINDOW then
        counts = { start = now, n = 0 }
        senderCounts[senderKey] = counts
    end
    if counts.n >= PER_SENDER or inAll.n >= IN_ALL then return false end
    counts.n, inAll.n = counts.n + 1, inAll.n + 1
    return true
end

-- Whether the game's sender name fits the name in the message. The game gives
-- "Name", "Name-Realm", "Name-Surname" or "Name Surname": the first name must match,
-- and a surname too when the game gives one after a space.
local function SenderMatches(sender, claimedKey)
    local name = ns.AccessibleString(Try(Ambiguate, sender, "none")) or sender
    local first, rest = name:match("^(%S+)%s+(.+)$")
    if first then
        return Identity.Key(first .. " " .. (rest:match("^([^%-]+)") or rest)) == claimedKey
    end
    return Identity.Key(name:match("^([^%-]+)") or name) == claimedKey:match("^(%S+)")
end

local function MapName(mapID)
    if not (mapID and C_Map and C_Map.GetMapInfo) then return nil end
    local info = Try(C_Map.GetMapInfo, mapID)
    return type(info) == "table" and ns.AccessibleString(info.name) or nil
end

local function Player(fields)
    local identity = Identity.Make(fields.name, fields.guid)
    identity.class, identity.level = fields.class, fields.level
    return identity
end

-- A shared full name fills a gap in the name cache (never overwrites what you saw).
local function Learn(identity, now)
    local names = ns.db.names
    if not (identity.guid and identity.name) or identity.partial or names[identity.guid] then return end
    names[identity.guid] = { n = identity.name, c = identity.class, l = identity.level, t = now }
    ns.Merge.UpgradeIdentity(identity.guid, identity.key)
end

local function OnKill(msg, now)
    if msg.at > now + MAX_FUTURE or now - msg.at > MAX_AGE then return end
    local victim = Player(msg)
    local killers = {}
    for _, fields in ipairs(msg.killers) do
        local killer = Player(fields)
        if not Identity.IsSelf(killer) then
            killers[#killers + 1] = killer
            Learn(killer, now)
        end
    end
    if #killers == 0 then return end
    ns.Merge.SubmitKill({
        victim = victim, killers = killers, at = msg.at, precision = "exact",
        mapID = msg.mapID, x = msg.x, y = msg.y, zone = MapName(msg.mapID),
        sources = { revenge = true }, own = true, test = msg.test,
        origin = victim.key .. "#" .. msg.id,
    })
end

local function MarksBy(by)
    local n = 0
    for _, mark in pairs(Store.AllWanted()) do
        if Identity.Same(mark.by, by) then n = n + 1 end
    end
    return n
end

local function HasMark(target, by)
    for _, mark in ipairs(Store.WantedFor(target.guid, target.key)) do
        if Identity.Same(mark.target, target) and Identity.Same(mark.by, by) then return true end
    end
    return false
end

local function OnWanted(msg, now)
    if msg.at > now + MAX_FUTURE then return end
    local target, by = Player(msg.target), Player(msg)
    if Identity.IsSelf(target) then return end
    if not HasMark(target, by) and MarksBy(by) >= MARKS_PER_ADDER then return end
    Learn(target, now)
    ns.Merge.SubmitWanted({ target = target, by = by, at = msg.at, sources = { revenge = true }, own = true })
end

local function OnWithdrawal(msg, now)
    if msg.at > now + MAX_FUTURE then return end
    ns.Merge.SubmitWithdrawal({ target = Identity.Make(msg.target.name, nil), by = Player(msg), at = msg.at })
end

local handlers = { K = OnKill, R = OnKill, M = OnWanted, X = OnWithdrawal }

local function OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    text, channel, sender = ns.AccessibleString(text), ns.AccessibleString(channel), ns.AccessibleString(sender)
    -- Guild only for now: whispers wait for friends sharing, with their own checks.
    if not (text and sender) or channel ~= CHANNEL or #sender > MAX_SENDER then return end
    local msg = Protocol.Decode(text)
    if not msg then return ns.Debug("share: dropped a malformed message from %s", sender) end
    local claimedKey = Identity.Key(msg.name)
    if Identity.IsSelf({ key = claimedKey, guid = msg.guid }) then return end  -- our own, echoed
    if not SenderMatches(sender, claimedKey) then
        return ns.Debug("share: dropped %s's message about %s", sender, msg.name)
    end
    local now = ns.Now()
    if not Allow(claimedKey, now) then return ns.Debug("share: %s is sending too much", sender) end
    if msg.type == "H" then
        OnHello(msg, claimedKey, now)
    else
        handlers[msg.type](msg, now)
    end
end

function Share:OnLogin()
    ns.On("PLAYER_LOGOUT", function() ns.db.lastSeen = ns.Now() end)
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage) then return end
    Try(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    ns.On("CHAT_MSG_ADDON", OnAddonMessage)
    ns.On("PLAYER_GUILD_UPDATE", function(unit)
        if unit == nil or unit == "player" then ScheduleHello() end
    end)
    ScheduleHello()
end
