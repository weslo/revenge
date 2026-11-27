-- Share: your own deaths and Wanted marks go to guildmates and friends running Revenge,
-- and theirs come in through the same merge as your own. Protocol.lua encodes the
-- messages, Friends.lua knows which friends to reach and how, and
-- docs/plans/revenge/PROTOCOL.md has the rules. In short:
--   - everyone sends only their own data, so nothing travels second-hand;
--   - the guild channel; whispers to in-game friends; Battle.net game data to
--     Battle.net friends on WoW: Forever and your faction. Each has its own switch;
--   - after login you say hello, and they answer with what you missed;
--   - with a channel's sharing off, nothing of yours goes there and hellos from there
--     aren't answered. You still receive.
-- Anything malformed, or not the sender's own, is dropped without a word.
local _, ns = ...

local Share = ns.RegisterModule("Share", {})
local Protocol, Identity, Store = ns.Protocol, ns.Identity, ns.Store
local Try = ns.Try

local PREFIX = Protocol.PREFIX
local GUILD = { key = "GUILD", channel = "GUILD" }

-- Catch-up
local HELLO_DELAY, HELLO_JITTER = 10, 5
local LOOKBACK = 86400              -- a hello asks for at least the last day
local SINCE_OVERLAP = 600
local ANSWER_DELAY_MIN, ANSWER_DELAY_MAX = 2, 8
local ANSWER_GAP = 10               -- seconds between two answers on one route
local HELLO_REPEAT = 300            -- a sender's hello is answered at most this often
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

local SETTING = { GUILD = "shareGuild", WHISPER = "shareFriends", BN = "shareBattleNet" }

-- Whether your own data may go out on this route.
local function MayShare(route)
    if not (ns.db and Me() and Store.Setting(SETTING[route.channel]) == true) then return false end
    if route.channel == "GUILD" then return Try(IsInGuild) and true or false end
    return true
end

local function Friends() return ns.Friends end

-- "guild", "Mira Thornwood (whisper)", "Tavish Reed (Battle.net)": for the diagnostic log.
local HOW = { WHISPER = "whisper", BN = "Battle.net" }
local function RouteText(route)
    if not route then return "-" end
    if route.channel == "GUILD" then return "guild" end
    return ("%s (%s)"):format(tostring(route.name or route.target or "?"), HOW[route.channel] or tostring(route.channel))
end
Share.RouteText = RouteText

local function Names(identities) return ns.Diagnostics.Names(identities) end

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

-- "ok", "throttle", "retry" or "drop", from pcall(send, ...).
local function Outcome(ok, result)
    if not ok then return "retry" end
    if result == nil or result == true or result == (RESULT.Success or 0) then return "ok" end
    if result == false then return "retry" end
    if result == (RESULT.AddonMessageThrottle or 3) or result == (RESULT.ChannelThrottle or 8) then return "throttle" end
    if result == (RESULT.AddOnMessageLockdown or 11) or result == (RESULT.GeneralError or 9) then return "retry" end
    return "drop"  -- not in a guild, the friend went offline, an invalid message: waiting won't help
end

local function BattleNetSend()
    return BNSendGameData or (C_BattleNet and C_BattleNet.SendGameData)
end

local function SendNow(item)
    if item.channel == "BN" then
        local send = BattleNetSend()
        if not send then return "drop" end
        return Outcome(pcall(send, item.target, PREFIX, item.text))
    end
    return Outcome(pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.text, item.channel, item.target))
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
            ns.Log("out", "a message to %s waited over %d minutes and was dropped", RouteText(item), QUEUE_TTL / 60)
        elseif Held() then
            return Schedule(HOLD_RETRY)
        elseif tokens < 1 then
            return Schedule((1 - tokens) / PER_SECOND)
        else
            local outcome = SendNow(item)
            if outcome == "ok" then
                table.remove(queue, 1)
                tokens = tokens - 1
            elseif outcome == "drop" then
                table.remove(queue, 1)
                ns.Debug("share: the game refused a message")
                ns.Log("out", "the game refused a message to %s", RouteText(item))
            else
                item.tries = item.tries + 1
                if item.tries >= TRIES then
                    table.remove(queue, 1)
                    ns.Log("out", "a message to %s failed %d times and was dropped", RouteText(item), TRIES)
                else
                    if outcome == "throttle" then tokens = 0 end
                    return Schedule(BACKOFF * 2 ^ (item.tries - 1))
                end
            end
        end
    end
end

local function Enqueue(text, route)
    if not (text and route) or #queue >= QUEUE_MAX then return false end
    if route.channel == "BN" then
        if not BattleNetSend() then return false end
    elseif not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        return false
    end
    queue[#queue + 1] = { text = text, channel = route.channel, target = route.target, name = route.name,
                          queued = ns.Now(), tries = 0 }
    Schedule(0)
    return true
end

function Share.QueueLength()
    return #queue
end

-- Where your own data goes: the guild, and each friend running Revenge who isn't
-- reached through the guild already.
local function Routes()
    local routes = {}
    local toGuild = MayShare(GUILD)
    if toGuild then routes[#routes + 1] = GUILD end
    local friends = Friends()
    for _, route in ipairs(friends and friends.Peers() or {}) do
        if MayShare(route) and not (toGuild and route.guildmate) then routes[#routes + 1] = route end
    end
    return routes
end

-- Sends texts to every route. Returns how many messages were queued. what: what they
-- are, for the diagnostic log.
local function Broadcast(texts, what)
    local queued, reached = 0, {}
    for _, route in ipairs(Routes()) do
        reached[#reached + 1] = RouteText(route)
        for _, text in ipairs(texts) do
            if Enqueue(text, route) then queued = queued + 1 end
        end
    end
    if #reached == 0 then
        ns.Log("out", "%s: not shared, nowhere to send (sharing off, or no guild and no friends running Revenge online)", what)
    else
        ns.Log("out", "%s: %d messages queued to %s", what, queued, table.concat(reached, ", "))
    end
    return queued
end

---------------------------------------------------------------------------
-- Your own data, as it happens
---------------------------------------------------------------------------
-- A death of yours (Deaths.lua). Returns how many messages were queued.
function Share.OwnKill(kill)
    if not (kill and Me() and Identity.IsSelf(kill.victim)) then return 0 end
    return Broadcast(Protocol.Kill("K", Me(), kill), "your death")
end

-- A player you marked Wanted (List.lua).
function Share.OwnWanted(mark)
    if not (mark and Me() and Identity.IsSelf(mark.by)) then return 0 end
    return Broadcast({ Protocol.Wanted(Me(), mark) }, ("your Wanted mark on %s"):format(tostring(mark.target.name)))
end

-- You withdrew your mark on target at `at` (List.lua).
function Share.OwnWithdrawal(target, at)
    if not (target and Me()) then return 0 end
    return Broadcast({ Protocol.Withdrawal(Me(), target.name or target.key, at) },
        ("taking back your mark on %s"):format(tostring(target.name or target.key)))
end

---------------------------------------------------------------------------
-- Catch-up: hellos, and answers to them
---------------------------------------------------------------------------
local guildHelloSent, guildHelloScheduled = false, false
local answers = {}           -- route key -> { route, since, scheduled, lastAt }
local helloAnswered = {}     -- sender key -> time we last answered their hello

-- What a hello asks for: since you were last online (less an overlap), at least a
-- day back, and no further back than your expiry.
function Share.HelloSince(now)
    now = now or ns.Now()
    local floor = now - Store.Setting("expiryDays") * 86400
    local since = floor
    if ns.db.lastSeen then since = math.max(floor, math.min(ns.db.lastSeen - SINCE_OVERLAP, now - LOOKBACK)) end
    return math.floor(since)
end

local function HelloText()
    local me = Me()
    return me and Protocol.Hello(me, Share.HelloSince(), ns.VERSION)
end

local function SendGuildHello()
    guildHelloScheduled = false
    if guildHelloSent or not Try(IsInGuild) then return end
    if Enqueue(HelloText(), GUILD) then
        guildHelloSent = true
        ns.Log("out", "hello to the guild, asking for what's new since %s", ns.Ago(ns.Now() - Share.HelloSince()))
    end
end

local function ScheduleGuildHello()
    if guildHelloSent or guildHelloScheduled then return end
    guildHelloScheduled = true
    ns.After(HELLO_DELAY + math.random() * HELLO_JITTER, SendGuildHello)
end

-- Says hello to one friend (Friends.lua). Returns true if it was queued.
function Share.HelloTo(route)
    local queued = Enqueue(HelloText(), route)
    if queued then ns.Log("out", "hello to %s", RouteText(route)) end
    return queued
end

local function Newest(a, b) return a.at > b.at end

local function Take(list, limit)
    table.sort(list, Newest)
    for i = #list, limit + 1, -1 do list[i] = nil end
    return list
end

-- Your answer to a hello asking for what's newer than `since`, as texts.
local function AnswerTexts(since, me, now)
    local texts = {}
    local kills = {}
    for _, kill in pairs(Store.AllKills()) do
        -- Only what Revenge itself recorded: other addons' copies aren't ours to pass on.
        if kill.own and not kill.test and kill.at >= since and now - kill.at <= MAX_AGE
            and Identity.IsSelf(kill.victim) then
            kills[#kills + 1] = kill
        end
    end
    for _, kill in ipairs(Take(kills, ANSWER_KILLS)) do
        for _, text in ipairs(Protocol.Kill("R", me, kill)) do texts[#texts + 1] = text end
    end
    local marks = {}
    for _, mark in pairs(Store.AllWanted()) do
        if mark.own and Identity.IsSelf(mark.by) then marks[#marks + 1] = mark end
    end
    for _, mark in ipairs(Take(marks, ANSWER_MARKS)) do texts[#texts + 1] = Protocol.Wanted(me, mark) end
    -- Withdrawals are stored as "target key|adder key" = time.
    local withdrawals = {}
    for pair, at in pairs(ns.db.withdrawals) do
        local targetKey, adderKey = pair:match("^(.*)|(.*)$")
        if adderKey == me.key and now - at <= WITHDRAWAL_AGE then
            withdrawals[#withdrawals + 1] = { key = targetKey, at = at }
        end
    end
    for _, w in ipairs(Take(withdrawals, ANSWER_WITHDRAWALS)) do
        texts[#texts + 1] = Protocol.Withdrawal(me, w.key, w.at)
    end
    return texts
end

local function SendAnswer(key)
    local answer = answers[key]
    if not answer then return end
    answer.scheduled, answer.lastAt = false, GetTime()
    local since = answer.since
    answer.since = nil
    local me = Me()
    if not (since and me and MayShare(answer.route)) then return end
    local texts, queued = AnswerTexts(since, me, ns.Now()), 0
    for _, text in ipairs(texts) do
        if Enqueue(text, answer.route) then queued = queued + 1 end
    end
    ns.Log("out", "answered the hello on %s: %d of %d messages queued", RouteText(answer.route), queued, #texts)
end

-- Answers a hello on its route (the guild, or that one friend), merging hellos that
-- arrive while an answer waits.
local function OnHello(msg, senderKey, now, route)
    local friends = Friends()
    if route ~= GUILD and friends and not friends.Helloed(route) then
        -- They don't know about us yet: say hello back, so they answer us too.
        if Share.HelloTo(route) then friends.SetHelloed(route) end
    end
    if not MayShare(route) then
        return ns.Log("in", "hello from %s by %s; not answered: your sharing there is off", msg.name, RouteText(route))
    end
    if helloAnswered[senderKey] and now - helloAnswered[senderKey] < HELLO_REPEAT then
        return ns.Log("in", "hello from %s by %s; not answered: answered them in the last 5 minutes", msg.name, RouteText(route))
    end
    helloAnswered[senderKey] = now
    ns.Log("in", "hello from %s by %s, asking since %s", msg.name, RouteText(route), ns.Ago(now - msg.since))
    local answer = answers[route.key]
    if not answer then
        answer = { route = route, scheduled = false }
        answers[route.key] = answer
    end
    answer.route = route
    answer.since = math.min(answer.since or msg.since, msg.since)
    if answer.scheduled then return end
    answer.scheduled = true
    local wait = ANSWER_DELAY_MIN + math.random() * (ANSWER_DELAY_MAX - ANSWER_DELAY_MIN)
    if answer.lastAt then wait = math.max(wait, answer.lastAt + ANSWER_GAP - GetTime()) end
    ns.After(wait, function() SendAnswer(route.key) end)
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

local SenderMatches = Identity.SenderIs

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

local function OnKill(msg, now, route)
    local live = msg.type == "K" and "live" or "catch-up"
    if msg.at > now + MAX_FUTURE or now - msg.at > MAX_AGE then
        return ns.Log("in", "%s's death by %s (%s): dropped, its time is out of range", msg.name, RouteText(route), live)
    end
    local victim = Player(msg)
    local killers = {}
    for _, fields in ipairs(msg.killers) do
        local killer = Player(fields)
        if not Identity.IsSelf(killer) then
            killers[#killers + 1] = killer
            Learn(killer, now)
        end
    end
    if #killers == 0 then return ns.Log("in", "%s's death by %s (%s): dropped, no killers", msg.name, RouteText(route), live) end
    local kill, new = ns.Merge.SubmitKill({
        victim = victim, killers = killers, at = msg.at, precision = "exact",
        mapID = msg.mapID, x = msg.x, y = msg.y, zone = MapName(msg.mapID),
        sources = { revenge = true }, own = true, test = msg.test,
        origin = victim.key .. "#" .. msg.id,
    })
    if not kill then
        return ns.Log("in", "%s's death by %s (%s): not taken, dismissed earlier", msg.name, RouteText(route), live)
    end
    ns.Log("in", "%s's death by %s (%s): killed by %s in %s%s, %s", msg.name, RouteText(route), live, Names(killers),
        tostring(kill.zone or "?"), msg.test and " (a test)" or "", new and "new" or "already known")
    -- A death just now (not a catch-up answer) alerts once.
    if new and msg.type == "K" then ns.Try(ns.Alerts and ns.Alerts.FriendKilled, kill) end
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

local function OnWanted(msg, now, route)
    local what = ("%s's Wanted mark on %s, by %s"):format(tostring(msg.name), tostring(msg.target.name), RouteText(route))
    if msg.at > now + MAX_FUTURE then return ns.Log("in", "%s: dropped, its time is in the future", what) end
    local target, by = Player(msg.target), Player(msg)
    if Identity.IsSelf(target) then return ns.Log("in", "%s: it's you, so not shown", what) end
    if not HasMark(target, by) and MarksBy(by) >= MARKS_PER_ADDER then
        return ns.Log("in", "%s: dropped, they have %d marks already", what, MARKS_PER_ADDER)
    end
    Learn(target, now)
    local mark, new = ns.Merge.SubmitWanted({ target = target, by = by, at = msg.at, sources = { revenge = true }, own = true })
    ns.Log("in", "%s: %s", what, not mark and "not taken, they took it back later" or new and "new" or "already known")
end

local function OnWithdrawal(msg, now, route)
    local what = ("%s took back their mark on %s, by %s"):format(tostring(msg.name), tostring(msg.target.name), RouteText(route))
    if msg.at > now + MAX_FUTURE then return ns.Log("in", "%s: dropped, its time is in the future", what) end
    local removed = ns.Merge.SubmitWithdrawal({ target = Identity.Make(msg.target.name, nil), by = Player(msg), at = msg.at })
    ns.Log("in", "%s: %s marks removed", what, removed)
end

local handlers = { K = OnKill, R = OnKill, M = OnWanted, X = OnWithdrawal }

-- A message from `sender` (the name the game gave) that came by `route`.
local rateLogged = {}         -- sender key -> when "sending too much" was last logged

local function Receive(text, sender, route)
    if not (text and sender) or #sender > MAX_SENDER then return end
    local msg = Protocol.Decode(text)
    if not msg then
        ns.Log("in", "dropped a malformed message from %s by %s", sender, RouteText(route))
        return ns.Debug("share: dropped a malformed message from %s", sender)
    end
    local claimedKey = Identity.Key(msg.name)
    if Identity.IsSelf({ key = claimedKey, guid = msg.guid }) then return end  -- our own, echoed
    if not SenderMatches(sender, claimedKey) then
        ns.Log("in", "dropped %s's message about %s by %s: not their own", sender, msg.name, RouteText(route))
        return ns.Debug("share: dropped %s's message about %s", sender, msg.name)
    end
    local now = ns.Now()
    if not Allow(claimedKey, now) then
        if not rateLogged[claimedKey] or now - rateLogged[claimedKey] > RATE_WINDOW then
            rateLogged[claimedKey] = now
            ns.Log("in", "dropping messages from %s for a while: over %d in 10 minutes", sender, PER_SENDER)
        end
        return ns.Debug("share: %s is sending too much", sender)
    end
    if route ~= GUILD and Friends() then Friends().MarkPeer(route) end
    if msg.type == "H" then
        OnHello(msg, claimedKey, now, route)
    else
        handlers[msg.type](msg, now, route)
    end
end

local function OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    text, channel, sender = ns.AccessibleString(text), ns.AccessibleString(channel), ns.AccessibleString(sender)
    if not (text and sender) then return end
    if channel == "GUILD" then return Receive(text, sender, GUILD) end
    if channel == "WHISPER" then
        -- Whispers count only from your in-game friends.
        local route = Friends() and Friends().FromWhisper(sender)
        if not route then
            ns.Log("in", "dropped a whisper from %s, who isn't an online friend", sender)
            return ns.Debug("share: dropped a whisper from %s, who isn't a friend", sender)
        end
        return Receive(text, sender, route)
    end
end

local function OnBattleNetMessage(prefix, text, _, senderID)
    if prefix ~= PREFIX then return end
    text, senderID = ns.AccessibleString(text), ns.AccessibleNumber(senderID)
    if not (text and senderID and Friends()) then return end
    local route = Friends().FromBattleNet(senderID)
    if not route then
        ns.Log("in", "dropped Battle.net data from an account Revenge doesn't share with")
        return ns.Debug("share: dropped Battle.net data from an account Revenge doesn't share with")
    end
    Receive(text, route.name, route)
end

function Share:OnLogin()
    ns.On("PLAYER_LOGOUT", function() ns.db.lastSeen = ns.Now() end)
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage) then return end
    Try(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    ns.On("CHAT_MSG_ADDON", OnAddonMessage)
    ns.On("BN_CHAT_MSG_ADDON", OnBattleNetMessage)
    ns.On("PLAYER_GUILD_UPDATE", function(unit)
        if unit == nil or unit == "player" then ScheduleGuildHello() end
    end)
    ScheduleGuildHello()
end
