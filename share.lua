-- Share saved profiles through clickable chat links.
--
-- A Myslot export is several KB but chat messages are capped at 255 chars and
-- the server strips |Haddon:...|h links from outgoing chat. So, like WeakAuras:
--   1. The sharer inserts a plain-text tag, "[Myslot: Player - Profile]", into
--      chat and remembers the profile for this session.
--   2. Every Myslot client rewrites that tag into a local |Haddon:myslot:...|h
--      link via a chat message event filter, using the real message sender.
--   3. Clicking the link whispers a request over the addon channel; the sharer
--      streams the profile back in small chunks.
--   4. The receiver reassembles it, checks the CRC32, and opens Myslot with the
--      text in the import box. It is never imported automatically: the user has
--      to review it and click Import (macros can contain /run code).

local _, MySlot = ...

local L = MySlot.L

local Share = {}
MySlot.share = Share

Share.PREFIX = "MyslotShare"
Share.LINK_TYPE = "myslot"
Share.LINK_COLOR = "ff71d5ff"
Share.MAX_NAME_BYTES = 48
-- Addon messages are capped at 255 bytes; leave room for the chunk header.
Share.CHUNK_SIZE = 220
Share.MAX_CHUNKS = 1000
Share.SEND_INTERVAL = 0.35
Share.THROTTLE_BACKOFF = 1.5
Share.MAX_SEND_RETRIES = 10
Share.RECEIVE_TIMEOUT = 30
Share.MAX_QUEUED = 5

-- Numeric Enum.SendAddonMessageResult values (12.x); older clients return a
-- boolean or nothing at all.
local RESULT_THROTTLE = { [3] = true, [8] = true }
local RESULT_LOCKDOWN = 11
local RESULT_OFFLINE = 12

local TAG_PATTERN = "%[Myslot: ([^%s%[%]|]+) %- ([^%[%]|]+)%]"

-- {{{ Pure helpers (unit tested in tests/cases/share.lua)

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Truncate s to at most n bytes without splitting a UTF-8 sequence.
function Share.TruncateUTF8(s, n)
    if #s <= n then
        return s
    end
    local cut = n
    while cut > 0 do
        local b = s:byte(cut + 1)
        -- stop once the next byte starts a new character (not 10xxxxxx)
        if b < 0x80 or b >= 0xC0 then
            break
        end
        cut = cut - 1
    end
    return s:sub(1, cut)
end

-- Make a profile name safe to embed in a chat tag and a hyperlink: no
-- brackets, pipes or control characters, single spaces, bounded length.
function Share.SanitizeName(name)
    local s = tostring(name or "")
    s = s:gsub("[%c%[%]|]", " ")
    s = trim(s:gsub("%s+", " "))
    s = trim(Share.TruncateUTF8(s, Share.MAX_NAME_BYTES))
    if s == "" then
        s = "Profile"
    end
    return s
end

function Share.SanitizePlayer(name)
    local s = tostring(name or ""):gsub("[%s%[%]|]", "")
    if s == "" then
        s = "?"
    end
    return s
end

function Share.FormatTag(player, profile)
    return "[Myslot: " .. player .. " - " .. profile .. "]"
end

function Share.FormatLink(sender, player, profile)
    return "|c" .. Share.LINK_COLOR .. "|Haddon:" .. Share.LINK_TYPE .. ":" .. sender .. ":" .. profile .. "|h"
        .. Share.FormatTag(player, profile) .. "|h|r"
end

-- Rewrite every plain-text tag in msg into a clickable link that requests the
-- profile from `sender` (the authoritative chat sender, not the tag text).
-- Returns the new message and the number of tags rewritten.
function Share.RewriteMessage(msg, sender)
    return msg:gsub(TAG_PATTERN, function(player, profile)
        return Share.FormatLink(sender, player, profile)
    end)
end

-- Parse the link payload handed to SetItemRef ("addon:myslot:<sender>:<profile>").
function Share.ParseLink(link)
    local sender, profile = link:match("^addon:" .. Share.LINK_TYPE .. ":([^:]+):(.+)$")
    return sender, profile
end

-- Wire format (tab separated, single message each):
--   R <id> <profile>                 request a linked profile
--   D <id> <index> <total> <data>    one chunk of the profile text
--   E <id> <code>                    error: "notfound" or "busy"
function Share.EncodeRequest(id, profile)
    return "R\t" .. id .. "\t" .. profile
end

function Share.EncodeChunk(id, index, total, data)
    return "D\t" .. id .. "\t" .. index .. "\t" .. total .. "\t" .. data
end

function Share.EncodeError(id, code)
    return "E\t" .. id .. "\t" .. code
end

function Share.DecodeMessage(msg)
    local kind = msg:sub(1, 1)
    if kind == "R" then
        local id, profile = msg:match("^R\t([^\t]+)\t(.+)$")
        if id then
            return "R", id, profile
        end
    elseif kind == "D" then
        local id, index, total, data = msg:match("^D\t([^\t]+)\t(%d+)\t(%d+)\t(.*)$")
        if id then
            return "D", id, tonumber(index), tonumber(total), data
        end
    elseif kind == "E" then
        local id, code = msg:match("^E\t([^\t]+)\t(.+)$")
        if id then
            return "E", id, code
        end
    end
end

function Share.SplitChunks(text, size)
    local chunks = {}
    for i = 1, #text, size do
        chunks[#chunks + 1] = text:sub(i, i + size - 1)
    end
    if #chunks == 0 then
        chunks[1] = ""
    end
    return chunks
end

function Share.NewAssembly(total)
    if type(total) ~= "number" or total < 1 or total > Share.MAX_CHUNKS then
        return nil
    end
    return { total = total, parts = {}, received = 0 }
end

-- Store one chunk. Duplicates are ignored; out-of-range or inconsistent
-- chunks are rejected (returns false).
function Share.AddChunk(asm, index, total, data)
    if total ~= asm.total or type(index) ~= "number" or index < 1 or index > asm.total then
        return false
    end
    if not asm.parts[index] then
        asm.parts[index] = data
        asm.received = asm.received + 1
    end
    return true
end

function Share.IsComplete(asm)
    return asm.received == asm.total
end

function Share.Assemble(asm)
    return table.concat(asm.parts, "", 1, asm.total)
end

-- Map a SendAddonMessage / SendGameData result to
-- "ok" | "throttle" | "lockdown" | "offline" | "error".
function Share.ClassifySendResult(result)
    if result == nil or result == true or result == 0 then
        return "ok"
    end
    if result == false or RESULT_THROTTLE[result] then
        return "throttle"
    end
    if result == RESULT_LOCKDOWN then
        return "lockdown"
    end
    if result == RESULT_OFFLINE then
        return "offline"
    end
    return "error"
end

-- "Name" -> "Name-Realm" so names from chat and addon events compare equal.
function Share.NormalizeName(name, realm)
    if not name or name == "" then
        return nil
    end
    if not name:find("-", 1, true) and realm and realm ~= "" then
        name = name .. "-" .. realm
    end
    return name:lower()
end

-- }}}

-- {{{ In-game wiring

local linked = {}   -- [sanitized profile name] = export text, this session only
local pending = {}  -- [request id] = incoming transfer we asked for
local outgoing = {} -- FIFO of transfers we are serving
local sending = false
local requestCounter = 0

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) and true or false
end

local function InLockdown()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        return C_ChatInfo.InChatMessagingLockdown() and true or false
    end
    return false
end

local function PrintLockdown()
    MySlot:Print(L["Addon messages are restricted right now (combat, encounter, Mythic+ or PvP). Try again later."])
end

local function After(delay, fn)
    C_Timer.After(delay, fn)
end

local function MyRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = GetRealmName and (GetRealmName() or ""):gsub("[%s%-]", "") or ""
    end
    return realm
end

local function IsSelf(name)
    local realm = MyRealm()
    return Share.NormalizeName(name, realm) == Share.NormalizeName(UnitName("player"), realm)
end

local function ShortName(name)
    if Ambiguate then
        return Ambiguate(name, "none")
    end
    return name
end

local function NewRequestId()
    requestCounter = requestCounter + 1
    return ("%d%d"):format(math.random(1000, 9999), requestCounter)
end

-- A target is { name = "Name-Realm" } for character whispers or
-- { bnID = gameAccountID } for Battle.net friends.
local function SendRaw(target, msg)
    local result
    if target.bnID then
        local send = (C_BattleNet and C_BattleNet.SendGameData) or BNSendGameData
        if not send then
            return "error"
        end
        result = send(target.bnID, Share.PREFIX, msg)
    else
        local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
        if not send then
            return "error"
        end
        result = send(Share.PREFIX, msg, "WHISPER", target.name)
    end
    return Share.ClassifySendResult(result)
end

local function TargetKey(target)
    if target.bnID then
        return "#bn:" .. target.bnID
    end
    return Share.NormalizeName(target.name, MyRealm())
end

-- {{{ Sharer side
local function PumpQueue()
    local job = outgoing[1]
    if not job then
        sending = false
        return
    end

    local delay = Share.SEND_INTERVAL
    local result = InLockdown() and "lockdown"
        or SendRaw(job.target, Share.EncodeChunk(job.id, job.next, #job.chunks, job.chunks[job.next]))

    if result == "ok" then
        job.next = job.next + 1
        job.retries = 0
        if job.next > #job.chunks then
            table.remove(outgoing, 1)
        end
    elseif result == "throttle" and job.retries < Share.MAX_SEND_RETRIES then
        job.retries = job.retries + 1
        delay = Share.THROTTLE_BACKOFF
    else
        table.remove(outgoing, 1)
        if result == "lockdown" then
            MySlot:Print(L["Stopped sending a shared profile."])
            PrintLockdown()
        else
            MySlot:Print((L["Failed to send profile '%s' to %s."]):format(job.profile, job.label))
        end
    end

    After(delay, PumpQueue)
end

local function HandleRequest(target, label, id, profile)
    local value = linked[profile]
    if not value then
        SendRaw(target, Share.EncodeError(id, "notfound"))
        return
    end

    local key = TargetKey(target)
    for _, job in ipairs(outgoing) do
        if job.id == id and job.key == key then
            return
        end
    end
    for _, job in ipairs(outgoing) do
        if job.key == key and job.profile == profile then
            SendRaw(target, Share.EncodeError(id, "busy"))
            return
        end
    end
    if #outgoing >= Share.MAX_QUEUED then
        SendRaw(target, Share.EncodeError(id, "busy"))
        return
    end

    table.insert(outgoing, {
        target = target,
        key = key,
        label = label,
        id = id,
        profile = profile,
        chunks = Share.SplitChunks(value, Share.CHUNK_SIZE),
        next = 1,
        retries = 0,
    })
    MySlot:Print((L["Sending profile '%s' to %s..."]):format(profile, label))

    if not sending then
        sending = true
        After(0, PumpQueue)
    end
end

function Share.LinkProfile(name, value)
    if type(value) ~= "string" or value == "" then
        MySlot:Print(L["Nothing to share, save the profile first"])
        return
    end

    local profile = Share.SanitizeName(name)
    linked[profile] = value

    local tag = Share.FormatTag(Share.SanitizePlayer(UnitName("player")), profile)
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if insert and insert(tag) then
        return
    end
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    if open then
        open(tag)
    end
end
-- }}}

-- {{{ Requester side
local function OpenReceived(text, profile, from)
    if MySlot.ShowImportText then
        MySlot:ShowImportText(text, ("%s - %s"):format(from, profile))
    end
    MySlot:Print((L["Received profile '%s' from %s. Review it, then click Import to apply."]):format(profile, from))
end

local function CheckTimeout(id)
    local p = pending[id]
    if not p then
        return
    end
    local idle = GetTime() - p.last
    if idle >= Share.RECEIVE_TIMEOUT then
        pending[id] = nil
        MySlot:Print((L["No response from %s. They may be offline, busy, or not running Myslot."]):format(p.label))
    else
        After(Share.RECEIVE_TIMEOUT - idle, function() CheckTimeout(id) end)
    end
end

local function ResolveBNTarget(bnAccountID)
    if not (C_BattleNet and C_BattleNet.GetAccountInfoByID) then
        return
    end
    local info = C_BattleNet.GetAccountInfoByID(bnAccountID)
    local game = info and info.gameAccountInfo
    if not (game and game.isOnline and game.gameAccountID) then
        return
    end
    return { bnID = game.gameAccountID }, game.characterName or info.accountName or L["Battle.net friend"]
end

function Share.RequestProfile(sender, profile)
    if IsSelf(sender) then
        local value = linked[profile]
        if value then
            OpenReceived(value, profile, ShortName(UnitName("player")))
        else
            MySlot:Print(L["This profile is no longer shared, link it again."])
        end
        return
    end

    if InLockdown() then
        PrintLockdown()
        return
    end

    local target, label
    local bnAccountID = sender:match("^#(%d+)$")
    if bnAccountID then
        target, label = ResolveBNTarget(tonumber(bnAccountID))
        if not target then
            MySlot:Print(L["That Battle.net friend is not online in World of Warcraft."])
            return
        end
    else
        target, label = { name = sender }, ShortName(sender)
    end

    local key = TargetKey(target)
    for _, p in pairs(pending) do
        if p.key == key and p.profile == profile then
            MySlot:Print((L["Already requesting '%s' from %s..."]):format(profile, label))
            return
        end
    end

    local id = NewRequestId()
    pending[id] = { key = key, label = label, profile = profile, last = GetTime() }
    MySlot:Print((L["Requesting profile '%s' from %s..."]):format(profile, label))
    local result = SendRaw(target, Share.EncodeRequest(id, profile))
    if result == "ok" then
        After(Share.RECEIVE_TIMEOUT, function() CheckTimeout(id) end)
        return
    end

    pending[id] = nil
    if result == "lockdown" then
        PrintLockdown()
    elseif result == "offline" then
        MySlot:Print((L["%s is offline."]):format(label))
    else
        MySlot:Print(L["Could not send the request, try again later."])
    end
end

local function HandleChunk(key, id, index, total, data)
    local p = pending[id]
    if not p or p.key ~= key then
        return
    end

    p.asm = p.asm or Share.NewAssembly(total)
    if not p.asm or not Share.AddChunk(p.asm, index, total, data) then
        pending[id] = nil
        MySlot:Print((L["Received a damaged profile from %s."]):format(p.label))
        return
    end
    p.last = GetTime()

    if Share.IsComplete(p.asm) then
        pending[id] = nil
        local text = Share.Assemble(p.asm)
        if MySlot:IsValidExportText(text) then
            OpenReceived(text, p.profile, p.label)
        else
            MySlot:Print((L["Received a damaged profile from %s."]):format(p.label))
        end
    end
end

local function HandleError(key, id, code)
    local p = pending[id]
    if not p or p.key ~= key then
        return
    end
    pending[id] = nil
    if code == "busy" then
        MySlot:Print((L["%s is busy sharing other profiles, try again later."]):format(p.label))
    else
        MySlot:Print((L["%s is no longer sharing '%s'."]):format(p.label, p.profile))
    end
end
-- }}}

local function OnAddonMessage(target, label, text)
    if type(text) ~= "string" then
        return
    end
    local kind, id, a, b, c = Share.DecodeMessage(text)
    if kind == "R" then
        HandleRequest(target, label, id, a)
    elseif kind == "D" then
        HandleChunk(TargetKey(target), id, a, b, c)
    elseif kind == "E" then
        HandleError(TargetKey(target), id, a)
    end
end

-- Whisper-like events whose author is the other party even though we wrote
-- the message; links in them must point back to us.
local SELF_AUTHORED = {
    CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
}

local CHAT_EVENTS = {
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
}

local function ChatFilter(_, event, msg, author, ...)
    -- 12.x can hand out secret values that must not be inspected.
    if IsSecret(msg) or IsSecret(author) or type(msg) ~= "string" then
        return false
    end
    if not msg:find("[Myslot: ", 1, true) then
        return false
    end

    local sender
    if SELF_AUTHORED[event] then
        sender = UnitName("player")
    elseif event == "CHAT_MSG_BN_WHISPER" then
        local bnSenderID = select(11, ...)
        if IsSecret(bnSenderID) or type(bnSenderID) ~= "number" then
            return false
        end
        sender = "#" .. bnSenderID
    elseif type(author) == "string" and author ~= "" then
        sender = author
    else
        return false
    end

    local newMsg, n = Share.RewriteMessage(msg, sender)
    if n == 0 then
        return false
    end
    return false, newMsg, author, ...
end

local function OnLinkClicked(link)
    if type(link) ~= "string" or IsSecret(link) then
        return
    end
    local sender, profile = Share.ParseLink(link)
    if sender then
        Share.RequestProfile(sender, profile)
    end
end

function Share.Init()
    local RegEvent = MySlot.regevent

    local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if register then
        register(Share.PREFIX)
    end

    local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if addFilter then
        for _, event in ipairs(CHAT_EVENTS) do
            addFilter(event, ChatFilter)
        end
    end

    if EventRegistry and EventRegistry.RegisterCallback and LinkTypes and LinkTypes.AddOn then
        EventRegistry:RegisterCallback("SetItemRef", function(_, link)
            OnLinkClicked(link)
        end, Share)
    elseif hooksecurefunc then
        hooksecurefunc("SetItemRef", OnLinkClicked)
    end

    RegEvent("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
        if prefix ~= Share.PREFIX or channel ~= "WHISPER" or IsSecret(text) or IsSecret(sender) then
            return
        end
        if type(sender) ~= "string" or sender == "" then
            return
        end
        OnAddonMessage({ name = sender }, ShortName(sender), text)
    end)

    RegEvent("BN_CHAT_MSG_ADDON", function(prefix, text, channel, senderID)
        if prefix ~= Share.PREFIX or IsSecret(text) or IsSecret(senderID) or type(senderID) ~= "number" then
            return
        end
        local label = L["Battle.net friend"]
        if C_BattleNet and C_BattleNet.GetGameAccountInfoByID then
            local info = C_BattleNet.GetGameAccountInfoByID(senderID)
            label = info and info.characterName or label
        end
        OnAddonMessage({ bnID = senderID }, label, text)
    end)
end

-- The CI loader runs this file without event.lua or the chat APIs; only the
-- pure helpers above are exercised there.
if MySlot.regevent then
    Share.Init()
end

-- }}}
