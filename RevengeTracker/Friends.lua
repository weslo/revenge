-- Friends: which in-game and Battle.net friends are online, which of them run Revenge,
-- and how to reach each one. Share.lua sends and receives; this module only keeps the
-- roster and says hello. (Recipe from OpenMap's and Revenge Book's Forever code.)
--
-- A route is how to reach one friend:
--   { key = "W:mira thornwood" | "B:<gameAccountID>", channel = "WHISPER" | "BN",
--     target = the name the friend list gives | the game account ID, name, guid, guildmate }
--   - In-game friends: C_FriendList; whispers go to the name exactly as the list gives it.
--   - Battle.net friends: only those playing WoW: Forever (WOW_PROJECT_ID) on your own
--     faction, so their killers are your enemies too (Q-005).
--   - Guildmates on your friend list are left to the guild channel.
-- A friend becomes a peer (known to run Revenge) once any valid message comes from them.
local _, ns = ...

local Friends = ns.RegisterModule("Friends", {})
local Identity = ns.Identity
local Try, Accessible, AccessibleString, AccessibleNumber = ns.Try, ns.Accessible, ns.AccessibleString, ns.AccessibleNumber

local SCAN_DELAY = 1
local FIRST_HELLO_DELAY, FIRST_HELLO_JITTER = 20, 10    -- after login, behind the guild hello
local ONLINE_HELLO_DELAY, ONLINE_HELLO_JITTER = 25, 15  -- a friend just came online: their addons load first
local HELLO_WINDOW, HELLOS_PER_WINDOW = 600, 30
local HELLO_RETRY = 60      -- a hello held back by the cap tries again this much later
local MAX_FRIENDS = 200

local online = {}          -- route key -> route, from the last scan
local peers = {}           -- route key -> true once they've sent us something valid
local helloed = {}         -- route key -> true once we've said hello while they're online
local hellosSent = {}      -- times of recent hellos
local scanScheduled, firstScanDone = false, false
local lastEagerScan = nil
local EAGER_SCAN_GAP = 5    -- an unknown whisperer triggers a fresh scan at most this often

-- "Mira Thornwood-Realm" -> "mira", "thornwood"; "Mira-Realm" / "Mira" -> "mira", nil
local function NameParts(name)
    if type(name) ~= "string" then return nil end
    local first, rest = name:match("^(%S+)%s+(.+)$")
    if first then return first:lower(), (rest:match("^([^%-]+)") or rest):lower() end
    return (name:match("^([^%-]+)") or name):lower(), nil
end

-- Whether two names, as the game writes them, are the same character: the first names
-- match, and the surnames too when both have one.
function Friends.SameName(a, b)
    local af, as = NameParts(a)
    local bf, bs = NameParts(b)
    if not (af and bf) or af ~= bf then return false end
    return not (as and bs and as ~= bs)
end

local function IsGuildmate(guid)
    return guid ~= nil and Try(IsGuildMember, guid) and true or false
end

-- A Battle.net friend's game account, if it's WoW: Forever on your own faction.
local function GameAccountRoute(g)
    if type(g) ~= "table" or not Accessible(g.isOnline) then return nil end
    if AccessibleString(g.clientProgram) ~= (BNET_CLIENT_WOW or "WoW") then return nil end
    local project = AccessibleNumber(g.wowProjectID)
    if WOW_PROJECT_ID and project ~= WOW_PROJECT_ID then return nil end
    local id, name = AccessibleNumber(g.gameAccountID), AccessibleString(g.characterName)
    if not (id and name) then return nil end
    local me = Identity.Self()
    local faction = AccessibleString(g.factionName)
    if not (me and me.faction and faction == me.faction) then return nil end
    local guid = AccessibleString(g.playerGuid)
    if guid and me.guid and guid == me.guid then return nil end
    return { key = "B:" .. id, channel = "BN", target = id, name = name, guid = guid, guildmate = IsGuildmate(guid) }
end

local function Scan()
    local found = {}
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, math.min(AccessibleNumber(Try(C_FriendList.GetNumFriends)) or 0, MAX_FRIENDS) do
            local info = Accessible(Try(C_FriendList.GetFriendInfoByIndex, i))
            local name = type(info) == "table" and AccessibleString(info.name)
            if name and not name:find("[%c|]") and Accessible(info.connected) == true then
                local guid = AccessibleString(info.guid)
                local key = "W:" .. Identity.Key(name)
                found[key] = { key = key, channel = "WHISPER", target = name, name = name, guid = guid,
                               guildmate = IsGuildmate(guid) }
            end
        end
    end
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for i = 1, math.min(AccessibleNumber(Try(BNGetNumFriends)) or 0, MAX_FRIENDS) do
            local account = Accessible(Try(C_BattleNet.GetFriendAccountInfo, i))
            local route = type(account) == "table" and GameAccountRoute(Accessible(account.gameAccountInfo))
            if route then found[route.key] = route end
        end
    end
    return found
end

local function MayHello(now)
    for i = #hellosSent, 1, -1 do
        if now - hellosSent[i] > HELLO_WINDOW then table.remove(hellosSent, i) end
    end
    return #hellosSent < HELLOS_PER_WINDOW
end

local function Hello(key)
    local route = online[key]
    if not route or helloed[key] or route.guildmate then return end
    local now = ns.Now()
    if not MayHello(now) then
        -- Too many hellos lately: try again while they're still online.
        ns.After(HELLO_RETRY, function() Hello(key) end)
        return
    end
    if ns.Share and ns.Share.HelloTo(route) then
        helloed[key] = true
        hellosSent[#hellosSent + 1] = now
    end
end

local function Rescan()
    scanScheduled = false
    local found = Scan()
    local first = not firstScanDone
    firstScanDone = true
    for key, route in pairs(found) do
        if not online[key] then
            -- Newly online (or the first scan): say hello once their addons have loaded.
            local delay = first and (FIRST_HELLO_DELAY + math.random() * FIRST_HELLO_JITTER)
                or (ONLINE_HELLO_DELAY + math.random() * ONLINE_HELLO_JITTER)
            ns.After(delay, function() Hello(key) end)
        end
        local known = online[key]
        if known then
            -- Keep what we learned about them; take the fresh details.
            known.target, known.name, known.guid, known.guildmate = route.target, route.name, route.guid, route.guildmate
            found[key] = known
        end
    end
    for key in pairs(online) do
        if not found[key] then peers[key], helloed[key] = nil, nil end
    end
    online = found
end

local function ScheduleScan()
    if scanScheduled then return end
    scanScheduled = true
    ns.After(SCAN_DELAY, Rescan)
end

---------------------------------------------------------------------------
-- What Share.lua asks
---------------------------------------------------------------------------
local function FindWhisperer(sender)
    for _, route in pairs(online) do
        if route.channel == "WHISPER" and Friends.SameName(route.name, sender) then return route end
    end
    return nil
end

-- The route of an in-game friend who whispered, or nil if they aren't one. A friend
-- the last scan hadn't seen online (just logged in, or before the first scan) is
-- found by scanning again, at most every few seconds.
function Friends.FromWhisper(sender)
    local route = FindWhisperer(sender)
    if route then return route end
    local clock = GetTime()
    if lastEagerScan and clock - lastEagerScan < EAGER_SCAN_GAP then return nil end
    lastEagerScan = clock
    Rescan()
    return FindWhisperer(sender)
end

-- The route of a Battle.net friend's game account, or nil if it isn't one we take.
function Friends.FromBattleNet(gameAccountID)
    if not (C_BattleNet and C_BattleNet.GetGameAccountInfoByID) then return nil end
    local route = GameAccountRoute(Accessible(Try(C_BattleNet.GetGameAccountInfoByID, gameAccountID)))
    if not route then return nil end
    if online[route.key] then return online[route.key] end
    online[route.key] = route  -- the last scan hadn't seen them yet
    return route
end

-- Someone sent us a valid message, so they run Revenge.
function Friends.MarkPeer(route)
    peers[route.key] = true
end

-- Whether we've already said hello to them (Share.lua answers a hello with one of ours).
function Friends.Helloed(route)
    return helloed[route.key] == true
end

function Friends.SetHelloed(route)
    helloed[route.key] = true
end

-- Online friends who run Revenge, as routes.
function Friends.Peers()
    local list = {}
    for key, route in pairs(online) do
        if peers[key] then list[#list + 1] = route end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

function Friends:OnLogin()
    if C_FriendList and C_FriendList.ShowFriends then Try(C_FriendList.ShowFriends) end
    for _, event in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
                             "BN_FRIEND_ACCOUNT_OFFLINE" }) do
        ns.On(event, ScheduleScan)
    end
    ScheduleScan()
end
