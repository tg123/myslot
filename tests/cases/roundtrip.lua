local _, MySlot = ...
local T = MySlot.test
local Host = MySlot.host

local function full_opt()
    return {
        ignoreActionBars = {},
        ignoreMacros = {},
        ignoreBinding = false,
        ignorePetActionBar = true, -- avoid pet APIs we don't stub
    }
end

T.describe("Export/Import round-trip", function()

    T.it("Export+Import produces a parseable message", function()
        local snap
        if Host.in_wow then
            snap = Host.snapshot()
        else
            Host.reset()
            Host.set_action(1,  "spell", 100)
            Host.set_action(2,  "spell", 200)
            Host.set_action(13, "item",  6948)
            local mid = Host.set_macro("hi", "INV_MISC_QUESTIONMARK", "/say hi")
            Host.set_action(25, "macro", mid)
            Host.set_binding("CTRL-A", "MOVEFORWARD")
        end

        local opt = full_opt()
        local text = MySlot:Export(opt)
        T.assert.not_nil(text)
        T.assert.is_true(#text > 0)

        local msg = MySlot:Import(text, { force = true })
        T.assert.not_nil(msg)
        T.assert.equal(42, msg.ver)
        T.assert.not_nil(msg.name)

        if Host.in_wow then
            Host.restore(snap)
        end
    end)

    T.it("Export output, re-exported, parses to identical structure", function()
        local snap
        if Host.in_wow then
            snap = Host.snapshot()
        else
            Host.reset()
            Host.set_action(1, "spell", 1234)
            Host.set_action(7, "item",  6948)
            Host.set_macro("m1", "INV_MISC_QUESTIONMARK", "/say m1")
            Host.set_binding("CTRL-B", "JUMP")
        end

        local opt = full_opt()
        local m1 = MySlot:Import(MySlot:Export(opt), { force = true })
        local m2 = MySlot:Import(MySlot:Export(opt), { force = true })
        T.assert.not_nil(m1)
        T.assert.not_nil(m2)
        T.assert.equal(m1.ver, m2.ver)
        T.assert.equal(#m1.slot,  #m2.slot)
        T.assert.equal(#m1.macro, #m2.macro)
        T.assert.equal(#m1.bind,  #m2.bind)
        for i = 1, #m1.slot do
            T.assert.equal(m1.slot[i].id,    m2.slot[i].id,    "slot["..i.."].id")
            T.assert.equal(m1.slot[i].type,  m2.slot[i].type,  "slot["..i.."].type")
            T.assert.equal(m1.slot[i].index, m2.slot[i].index, "slot["..i.."].index")
        end
        for i = 1, #m1.macro do
            T.assert.equal(m1.macro[i].name, m2.macro[i].name)
            T.assert.equal(m1.macro[i].body, m2.macro[i].body)
            T.assert.equal(m1.macro[i].icon, m2.macro[i].icon)
        end

        if Host.in_wow then
            Host.restore(snap)
        end
    end)

    T.it("ignores comment lines in import text", function()
        local snap
        if Host.in_wow then
            snap = Host.snapshot()
        else
            Host.reset()
            Host.set_action(1, "spell", 999)
        end
        local text = MySlot:Export(full_opt())
        -- Inject extra # comments; Import must strip them.
        local with_comments = "# extra\n# another\n" .. text .. "\n# trailing"
        local msg = MySlot:Import(with_comments, { force = true })
        T.assert.not_nil(msg)
        if Host.in_wow then Host.restore(snap) end
    end)

    T.it("rejects garbage input without force", function()
        local msg = MySlot:Import("not a real export", {})
        T.assert.equal(nil, msg)
    end)

    T.it("rejects too-short input", function()
        local msg = MySlot:Import("# only a comment\n", { force = true })
        T.assert.equal(nil, msg)
    end)
end)
