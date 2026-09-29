local _, MySlot = ...
local T = MySlot.test
local Host = MySlot.host
local Share = MySlot.share

T.describe("share: chat tags and links", function()
    T.it("sanitizes profile names for chat", function()
        T.assert.equal("Raid Main", Share.SanitizeName("  Raid]\n[Main|  "))
        T.assert.equal("a b", Share.SanitizeName("a\t\tb"))
        T.assert.equal("Profile", Share.SanitizeName("[]|"))
        T.assert.equal("Profile", Share.SanitizeName(nil))
        local long = Share.SanitizeName(("x"):rep(200))
        T.assert.equal(Share.MAX_NAME_BYTES, #long)
    end)

    T.it("truncates without splitting UTF-8 characters", function()
        local s = ("\228\184\173"):rep(20) -- 20 x U+4E2D, 3 bytes each
        T.assert.equal(("\228\184\173"):rep(3), Share.TruncateUTF8(s, 10))
        T.assert.equal(("\228\184\173"):rep(3), Share.TruncateUTF8(s, 9))
        T.assert.equal("", Share.TruncateUTF8(s, 2))
        T.assert.equal("abc", Share.TruncateUTF8("abc", 10))
    end)

    T.it("formats a tag that fits in one chat message", function()
        local tag = Share.FormatTag(Share.SanitizePlayer("Tester"), Share.SanitizeName(("y"):rep(500)))
        T.assert.is_true(#tag < 255, "tag too long: " .. #tag)
        T.assert.equal("[Myslot: Tester - Main]", Share.FormatTag("Tester", "Main"))
    end)

    T.it("rewrites a tag into a link bound to the real sender", function()
        local msg = "try [Myslot: Someone - Raid: ST - Boss] ok"
        local out, n = Share.RewriteMessage(msg, "Tester-Area52")
        T.assert.equal(1, n)
        T.assert.is_true(out:find("|Haddon:myslot:Tester-Area52:Raid: ST - Boss|h", 1, true) ~= nil, out)
        T.assert.is_true(out:find("[Myslot: Someone - Raid: ST - Boss]|h|r ok", 1, true) ~= nil, out)
        T.assert.equal("try ", out:sub(1, 4))
    end)

    T.it("rewrites several tags and handles realm names in the tag", function()
        local msg = "[Myslot: A-Realm - One] and [Myslot: B - Two]"
        local out, n = Share.RewriteMessage(msg, "Tester")
        T.assert.equal(2, n)
        T.assert.is_true(out:find("|Haddon:myslot:Tester:One|h[Myslot: A-Realm - One]|h", 1, true) ~= nil, out)
        T.assert.is_true(out:find("|Haddon:myslot:Tester:Two|h[Myslot: B - Two]|h", 1, true) ~= nil, out)
    end)

    T.it("leaves non-tag text alone", function()
        for _, msg in ipairs({
            "hello",
            "[Myslot: ]",
            "[Myslot: Name]",
            "[Myslot: Two Words - x]",
            "[Myslot: A - ]",
        }) do
            local out, n = Share.RewriteMessage(msg, "Tester")
            T.assert.equal(0, n, msg)
            T.assert.equal(msg, out)
        end
    end)

    T.it("parses the link payload back", function()
        local sender, profile = Share.ParseLink("addon:myslot:Tester-Area52:Raid: ST - Boss")
        T.assert.equal("Tester-Area52", sender)
        T.assert.equal("Raid: ST - Boss", profile)

        sender, profile = Share.ParseLink("addon:myslot:#42:Main")
        T.assert.equal("#42", sender)
        T.assert.equal("Main", profile)

        T.assert.equal(nil, (Share.ParseLink("addon:weakauras:Tester:Main")))
        T.assert.equal(nil, (Share.ParseLink("addon:myslot:Tester")))
    end)

    T.it("normalizes names for comparison", function()
        T.assert.equal("tester-area52", Share.NormalizeName("Tester", "Area52"))
        T.assert.equal("tester-other", Share.NormalizeName("Tester-Other", "Area52"))
        T.assert.equal(nil, Share.NormalizeName("", "Area52"))
    end)

    T.it("gives colliding profiles distinct link names", function()
        local linked = {}
        local a = Share.UniqueLinkName(linked, "A[ B", "one")
        linked[a] = "one"
        T.assert.equal("A B", a)
        -- Same export again reuses the name.
        T.assert.equal("A B", Share.UniqueLinkName(linked, "A B", "one"))
        -- A different export that sanitizes to the same name gets a suffix.
        local b = Share.UniqueLinkName(linked, "A] B", "two")
        T.assert.equal("A B (2)", b)
        linked[b] = "two"
        T.assert.equal("A B (3)", Share.UniqueLinkName(linked, "A B", "three"))
        T.assert.equal("A B (2)", Share.UniqueLinkName(linked, "A B", "two"))

        -- Suffixed names stay within the length limit.
        local long = ("x"):rep(200)
        linked = {}
        linked[Share.UniqueLinkName(linked, long, "one")] = "one"
        local c = Share.UniqueLinkName(linked, long, "two")
        T.assert.is_true(#c <= Share.MAX_NAME_BYTES, "too long: " .. #c)
        T.assert.equal(" (2)", c:sub(-4))
        -- The suffixed name still survives a chat round-trip.
        local _, n = Share.RewriteMessage(Share.FormatTag("Tester", c), "Tester")
        T.assert.equal(1, n)
    end)

    T.it("encodes Battle.net senders with the character GUID", function()
        local sender = Share.FormatBNSender(42, "Player-1234-0ABCDEF0")
        T.assert.equal("#42@Player-1234-0ABCDEF0", sender)
        local id, guid = Share.ParseBNSender(sender)
        T.assert.equal(42, id)
        T.assert.equal("Player-1234-0ABCDEF0", guid)

        T.assert.equal("#42", Share.FormatBNSender(42, nil))
        T.assert.equal("#42", Share.FormatBNSender(42, ""))
        id, guid = Share.ParseBNSender("#42")
        T.assert.equal(42, id)
        T.assert.equal(nil, guid)

        -- The encoded sender must survive the link round-trip.
        local out = Share.RewriteMessage("[Myslot: A - Main]", sender)
        local s, profile = Share.ParseLink(out:match("|H(.-)|h"))
        T.assert.equal(sender, s)
        T.assert.equal("Main", profile)
    end)

    T.it("picks the game account playing the linking character", function()
        local accounts = {
            { gameAccountID = 1, isOnline = true, clientProgram = "BSAp" },
            { gameAccountID = 2, isOnline = true, clientProgram = "WoW", playerGuid = "Player-1-AAA" },
            { gameAccountID = 3, isOnline = true, clientProgram = "WoW", playerGuid = "Player-1-BBB" },
            { gameAccountID = 4, isOnline = false, clientProgram = "WoW", playerGuid = "Player-1-CCC" },
        }
        T.assert.equal(3, Share.PickGameAccount(accounts, "Player-1-BBB").gameAccountID)
        -- Ambiguous without a GUID match: refuse rather than guess.
        T.assert.equal(nil, Share.PickGameAccount(accounts, nil))
        T.assert.equal(nil, Share.PickGameAccount(accounts, "Player-1-CCC"))
        -- A single online WoW account is used even without a GUID.
        T.assert.equal(2, Share.PickGameAccount({ accounts[1], accounts[2] }, nil).gameAccountID)
        T.assert.equal(nil, Share.PickGameAccount({ accounts[1] }, nil))
    end)
end)

T.describe("share: transfer protocol", function()
    T.it("round-trips request, chunk and error messages", function()
        T.assert.same({ "R", "123", "Raid: Main" },
            { Share.DecodeMessage(Share.EncodeRequest("123", "Raid: Main")) })

        local data = "# comment\tline\nABCD=="
        local kind, id, idx, total, got = Share.DecodeMessage(Share.EncodeChunk("9", 3, 10, data))
        T.assert.equal("D", kind)
        T.assert.equal("9", id)
        T.assert.equal(3, idx)
        T.assert.equal(10, total)
        T.assert.equal(data, got)

        T.assert.same({ "E", "9", "busy" }, { Share.DecodeMessage(Share.EncodeError("9", "busy")) })
        T.assert.equal(nil, (Share.DecodeMessage("X\tjunk")))
        T.assert.equal(nil, (Share.DecodeMessage("D\t1\tx\t2\tdata")))
        T.assert.equal(nil, (Share.DecodeMessage("")))
    end)

    T.it("keeps every chunk message within the addon message limit", function()
        local chunk = ("z"):rep(Share.CHUNK_SIZE)
        local msg = Share.EncodeChunk("99991000", Share.MAX_CHUNKS, Share.MAX_CHUNKS, chunk)
        T.assert.is_true(#msg <= 255, "chunk message too long: " .. #msg)
    end)

    T.it("splits and reassembles out of order with duplicates", function()
        local text = {}
        for i = 1, 1000 do text[#text + 1] = string.char(32 + i % 90) end
        text = table.concat(text)

        local chunks = Share.SplitChunks(text, 64)
        T.assert.equal(16, #chunks)

        local asm = Share.NewAssembly(#chunks)
        for i = #chunks, 1, -1 do
            T.assert.is_true(Share.AddChunk(asm, i, #chunks, chunks[i]))
            T.assert.is_true(Share.AddChunk(asm, i, #chunks, "dup"))
        end
        T.assert.is_true(Share.IsComplete(asm))
        T.assert.equal(text, Share.Assemble(asm))
    end)

    T.it("rejects inconsistent chunks", function()
        T.assert.equal(nil, Share.NewAssembly(0))
        T.assert.equal(nil, Share.NewAssembly(Share.MAX_CHUNKS + 1))

        local asm = Share.NewAssembly(2)
        T.assert.is_false(Share.AddChunk(asm, 3, 2, "x"))
        T.assert.is_false(Share.AddChunk(asm, 0, 2, "x"))
        T.assert.is_false(Share.AddChunk(asm, 1, 3, "x"))
        T.assert.is_true(Share.AddChunk(asm, 1, 2, "x"))
        T.assert.is_false(Share.IsComplete(asm))
    end)

    T.it("classifies send results", function()
        T.assert.equal("ok", Share.ClassifySendResult(nil))
        T.assert.equal("ok", Share.ClassifySendResult(true))
        T.assert.equal("ok", Share.ClassifySendResult(0))
        T.assert.equal("throttle", Share.ClassifySendResult(false))
        T.assert.equal("throttle", Share.ClassifySendResult(3))
        T.assert.equal("throttle", Share.ClassifySendResult(8))
        T.assert.equal("lockdown", Share.ClassifySendResult(11))
        T.assert.equal("offline", Share.ClassifySendResult(12))
        T.assert.equal("error", Share.ClassifySendResult(9))
    end)

    T.it("transfers a real export intact and validates it", function()
        if not Host.in_wow then
            Host.reset()
            Host.set_action(1, "spell", 100)
            Host.set_macro("hi", "INV_MISC_QUESTIONMARK", "/say hi")
            Host.set_binding("CTRL-A", "MOVEFORWARD")
        end

        local text = MySlot:Export({
            ignoreActionBars = {},
            ignoreMacros = {},
            ignoreBinding = false,
            ignorePetActionBar = true,
        })
        T.assert.not_nil(text)
        T.assert.is_true(MySlot:IsValidExportText(text))

        local chunks = Share.SplitChunks(text, Share.CHUNK_SIZE)
        local asm = Share.NewAssembly(#chunks)
        for i, c in ipairs(chunks) do
            local kind, _, idx, total, data = Share.DecodeMessage(Share.EncodeChunk("1", i, #chunks, c))
            T.assert.equal("D", kind)
            T.assert.is_true(Share.AddChunk(asm, idx, total, data))
        end
        local got = Share.Assemble(asm)
        T.assert.equal(text, got)
        T.assert.is_true(MySlot:IsValidExportText(got))

        -- Flip one base64 character in the payload: CRC32 must catch it.
        local pos = text:find("\n[A-Za-z0-9+/]", 1) + 10
        local ch = text:sub(pos, pos)
        local bad = text:sub(1, pos - 1) .. (ch == "A" and "B" or "A") .. text:sub(pos + 1)
        T.assert.is_false(MySlot:IsValidExportText(bad))
        T.assert.is_false(MySlot:IsValidExportText("not a profile"))
        T.assert.is_false(MySlot:IsValidExportText(""))
    end)
end)

T.describe("share: send queue", function()
    -- Deterministic harness: timers run only when step() is called, and
    -- results[i] decides what the i-th send returns (default "ok").
    local function harness(results)
        local h = { sent = {}, delays = {}, dropped = {}, lockdown = false }
        local timers = {}
        h.queue = Share.NewSendQueue({
            send = function(target, msg)
                local n = #h.sent + 1
                local _, id, idx, total, data = Share.DecodeMessage(msg)
                h.sent[n] = { to = target.name, id = id, idx = idx, total = total, data = data }
                return results and results[n] or "ok"
            end,
            after = function(delay, fn)
                timers[#timers + 1] = fn
                h.delays[#h.delays + 1] = delay
            end,
            inLockdown = function() return h.lockdown end,
            onDrop = function(job, result)
                h.dropped[#h.dropped + 1] = { id = job.id, result = result }
            end,
        })
        function h.step()
            local fn = table.remove(timers, 1)
            if fn then fn() end
            return fn ~= nil
        end
        function h.drain(limit)
            local n = 0
            while h.step() do
                n = n + 1
                assert(n < (limit or 1000), "queue did not settle")
            end
        end
        return h
    end

    local function job(id, name, ...)
        return { target = { name = name }, id = id, chunks = { ... } }
    end

    T.it("sends every chunk in order, paced, then goes idle", function()
        local h = harness()
        h.queue:Add(job("1", "Bob", "a", "b", "c"))
        T.assert.is_true(h.queue.running)
        h.drain()
        T.assert.equal(3, #h.sent)
        for i, s in ipairs(h.sent) do
            T.assert.equal("Bob", s.to)
            T.assert.equal(i, s.idx)
            T.assert.equal(3, s.total)
            T.assert.equal(("abc"):sub(i, i), s.data)
        end
        T.assert.same({ 0, Share.SEND_INTERVAL, Share.SEND_INTERVAL, Share.SEND_INTERVAL }, h.delays)
        T.assert.is_false(h.queue.running)
        T.assert.equal(0, #h.queue.jobs)
        T.assert.equal(0, #h.dropped)
    end)

    T.it("retries a throttled chunk after backing off", function()
        local h = harness({ "ok", "throttle", "throttle", "ok" })
        h.queue:Add(job("1", "Bob", "a", "b"))
        h.drain()
        T.assert.equal(4, #h.sent)
        T.assert.same({ 1, 2, 2, 2 }, { h.sent[1].idx, h.sent[2].idx, h.sent[3].idx, h.sent[4].idx })
        T.assert.same({ 0, Share.SEND_INTERVAL, Share.THROTTLE_BACKOFF, Share.THROTTLE_BACKOFF, Share.SEND_INTERVAL },
            h.delays)
        T.assert.equal(0, #h.dropped)
    end)

    T.it("drops a job that stays throttled", function()
        local results = {}
        for i = 1, Share.MAX_SEND_RETRIES + 1 do results[i] = "throttle" end
        local h = harness(results)
        h.queue:Add(job("1", "Bob", "a"))
        h.drain()
        T.assert.equal(Share.MAX_SEND_RETRIES + 1, #h.sent)
        T.assert.same({ { id = "1", result = "throttle" } }, h.dropped)
        T.assert.is_false(h.queue.running)
    end)

    T.it("drops the current job on lockdown, offline or error and moves on", function()
        for _, result in ipairs({ "offline", "error" }) do
            local h = harness({ "ok", result })
            h.queue:Add(job("1", "Bob", "a", "b", "c"))
            h.queue:Add(job("2", "Amy", "x"))
            h.drain()
            T.assert.same({ { id = "1", result = result } }, h.dropped, result)
            T.assert.equal("Amy", h.sent[#h.sent].to, result)
            T.assert.equal(3, #h.sent, result)
        end

        local h = harness()
        h.queue:Add(job("1", "Bob", "a", "b"))
        h.step() -- sends chunk 1
        h.lockdown = true
        h.step() -- lockdown: nothing sent, job dropped
        h.lockdown = false
        h.drain()
        T.assert.equal(1, #h.sent)
        T.assert.same({ { id = "1", result = "lockdown" } }, h.dropped)
    end)

    T.it("serves jobs first in, first out without interleaving", function()
        local h = harness()
        h.queue:Add(job("1", "Bob", "a", "b"))
        h.step()
        h.queue:Add(job("2", "Amy", "x", "y"))
        h.drain()
        local order = {}
        for _, s in ipairs(h.sent) do order[#order + 1] = s.id .. ":" .. s.idx end
        T.assert.same({ "1:1", "1:2", "2:1", "2:2" }, order)
        -- Adding while running must not start a second pump.
        local starts = 0
        for _, d in ipairs(h.delays) do
            if d == 0 then starts = starts + 1 end
        end
        T.assert.equal(1, starts)
    end)
end)