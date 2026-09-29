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
