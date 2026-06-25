-- Lua 5.1+ base64 v3.0 (c) 2009 by Alex Kloss <alexthkloss@web.de>
-- Licensed under the terms of the LGPL2
-- modified to support byte seq table and World of Warcraft by Boshi Lian <farmer1992@gmail.com> 2010 Oct 24

local _, ADDONSELF = ...
ADDONSELF.base64 = {}

local base64 = ADDONSELF.base64 

local CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function enc(data)
    local t = {}

    local n = 0
    for _, x in pairs(data) do
        local r, b = '', x
        for i = 8, 1, -1 do
            r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0')
        end
        t[#t + 1] = r
        n = n + 1
        -- Encoding a large payload is a long, tight loop that can trip WoW's
        -- "script ran too long" watchdog. When inside a coroutine (async
        -- import/export or the test harness), yield periodically so the watchdog
        -- resets. No-op on the main thread. NB: we can only yield here, not in
        -- the gsub callbacks below, since Lua 5.1 can't yield across a C call.
        if n % 1024 == 0 then
            local co, isMain = coroutine.running()
            if co and not isMain then coroutine.yield() end
        end
    end

    t[#t + 1] = '0000'

    local r = {}
    table.concat(t):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return nil end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
        r[#r + 1] = CHARS:sub(c + 1, c + 1)
    end)

    r[#r + 1] = ({'', '==', '='})[#data % 3 + 1]
    return table.concat(r)
end

-- decoding
local function dec(data)
    data = string.gsub(data, '[^' .. CHARS .. '=]', '')
    local t = {}
    data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r, f = '', (CHARS:find(x) - 1)
        for i = 6, 1, -1 do
            r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0')
        end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return nil end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0) end
        t[#t + 1] = c
    end)
    return t
end

base64.enc = enc
base64.dec = dec
