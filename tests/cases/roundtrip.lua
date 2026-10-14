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

-- Empty protobuf repeated fields decode to nil (not an empty table), so a
-- character/state with e.g. no action slots yields msg.slot == nil. Treat that
-- as length 0 instead of erroring on #nil.
local function len(t) return t and #t or 0 end

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
        T.assert.equal(len(m1.slot),  len(m2.slot))
        T.assert.equal(len(m1.macro), len(m2.macro))
        T.assert.equal(len(m1.bind),  len(m2.bind))
        for i = 1, len(m1.slot) do
            T.assert.equal(m1.slot[i].id,    m2.slot[i].id,    "slot["..i.."].id")
            T.assert.equal(m1.slot[i].type,  m2.slot[i].type,  "slot["..i.."].type")
            T.assert.equal(m1.slot[i].index, m2.slot[i].index, "slot["..i.."].index")
        end
        for i = 1, len(m1.macro) do
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

    T.it("exports all five rows of character macros with Midnight constants", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()

        T.assert.equal(nil, _G.MAX_ACCOUNT_MACROS)
        T.assert.equal(nil, _G.MAX_CHARACTER_MACROS)
        for id = 121, 150 do
            _G.WowStub.macros[id] = {
                name = "Macro " .. id,
                icon = "INV_MISC_QUESTIONMARK",
                body = "/say " .. id,
            }
        end

        local msg = MySlot:Import(MySlot:Export(full_opt()), { force = true })
        T.assert.equal(30, len(msg.macro))
        T.assert.equal(121, msg.macro[1].id)
        T.assert.equal(150, msg.macro[30].id)
    end)

    T.it("exports on WoW Forever, which has the 11.0 spellbook but no talent grid", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()
        Host.set_action(1, "spell", 2098)

        -- The 12.1-engine spellbook/spec APIs exist, but MAX_TALENT_TIERS,
        -- NUM_TALENT_COLUMNS and C_SpecializationInfo stay nil.
        T.assert.equal(nil, _G.MAX_TALENT_TIERS)
        T.assert.equal(nil, _G.NUM_TALENT_COLUMNS)
        T.assert.equal(nil, _G.C_SpecializationInfo)
        local savedSpellBook, savedSpecGroups, savedTalentInfo =
            _G.C_SpellBook, _G.GetNumSpecGroups, _G.GetTalentInfo
        _G.C_SpellBook = { GetNumSpellBookSkillLines = function() return 0 end }
        _G.GetNumSpecGroups = function() return 1 end
        _G.GetTalentInfo = function() end

        local ok, text = pcall(MySlot.Export, MySlot, full_opt())
        _G.C_SpellBook, _G.GetNumSpecGroups, _G.GetTalentInfo =
            savedSpellBook, savedSpecGroups, savedTalentInfo
        T.assert.is_true(ok, tostring(text))

        local msg = MySlot:Import(text, { force = true })
        T.assert.equal(1, len(msg.slot))
        T.assert.equal(2098, msg.slot[1].index)
    end)

    T.it("reports cooldown manager support based on the loaded addon", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end

        -- Stub-backed CI env has Blizzard_CooldownViewer loaded -> supported.
        T.assert.equal(true, MySlot:IsCooldownManagerSupported())

        -- Classic clients ship the C_CooldownViewer namespace but never load the
        -- Blizzard_CooldownViewer addon, so support must be false there.
        _G.WowStub.cooldown_addon_loaded = false
        T.assert.equal(false, MySlot:IsCooldownManagerSupported())
        _G.WowStub.cooldown_addon_loaded = true
    end)

    T.it("reports click binding support based on C_ClickBindings", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end

        T.assert.equal(true, MySlot:IsClickBindingSupported())

        -- The C_ClickBindings namespace is genuinely absent on Classic.
        local saved = _G.C_ClickBindings
        _G.C_ClickBindings = nil
        T.assert.equal(false, MySlot:IsClickBindingSupported())
        _G.C_ClickBindings = saved
    end)

    T.it("reports pet action bar support based on the player's class", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end

        local saved = _G.WowStub.player.class

        _G.WowStub.player.class = "HUNTER"
        T.assert.equal(true, MySlot:IsPetActionBarSupported())

        -- A class that can never have a pet hides the pet action bar option.
        _G.WowStub.player.class = "ROGUE"
        T.assert.equal(false, MySlot:IsPetActionBarSupported())

        -- Mages only have a controllable pet bar on WotLK+ (interface >= 30000);
        -- on Vanilla/TBC-era clients the pet option stays hidden for them.
        local saved_iface = _G.WowStub.interface_version
        _G.WowStub.player.class = "MAGE"
        _G.WowStub.interface_version = 110000
        T.assert.equal(true, MySlot:IsPetActionBarSupported())
        _G.WowStub.interface_version = 11507
        T.assert.equal(false, MySlot:IsPetActionBarSupported())
        _G.WowStub.interface_version = saved_iface

        _G.WowStub.player.class = saved
    end)

    T.it("export captures the cooldown manager layout blob", function()
        -- Drives the C_CooldownViewer stub: Export should pull GetLayoutData()
        -- into msg.cooldownManager. The SetLayoutData import wiring is covered by
        -- the in-game suite (RecoverData isn't CI-safe).
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()
        local layout = "1|FAKECOOLDOWNLAYOUTBLOB=="
        _G.WowStub.cooldown_layout = layout

        local msg = MySlot:Import(MySlot:Export(full_opt()), { force = true })
        T.assert.equal(layout, msg.cooldownManager)

        -- And it's omitted when there's nothing to export.
        Host.reset()
        local msg2 = MySlot:Import(MySlot:Export(full_opt()), { force = true })
        T.assert.equal(nil, msg2.cooldownManager)
    end)

    T.it("Clear COOLDOWNMANAGER moves every cooldown to Not Displayed", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()
        local Cat = Enum.CooldownViewerCategory

        MySlot:Clear("COOLDOWNMANAGER")

        -- Spell categories (Essential/Utility) move to HiddenSpell,
        -- aura categories (TrackedBuff/TrackedBar) move to HiddenAura.
        T.assert.equal(Cat.HiddenSpell, _G.WowStub.cooldown_moves[101])
        T.assert.equal(Cat.HiddenSpell, _G.WowStub.cooldown_moves[102])
        T.assert.equal(Cat.HiddenSpell, _G.WowStub.cooldown_moves[999])
        T.assert.equal(Cat.HiddenSpell, _G.WowStub.cooldown_moves[201])
        T.assert.equal(Cat.HiddenAura, _G.WowStub.cooldown_moves[301])
        T.assert.equal(Cat.HiddenAura, _G.WowStub.cooldown_moves[401])

        -- Like Blizzard, editing the default layout creates an active layout for the
        -- spec; the re-serialized layouts are written straight to the datastore.
        local data = _G.WowStub.decode_cooldown_blob(_G.WowStub.cooldown_layout)
        T.assert.equal(1, data.active[11])
        T.assert.equal(Cat.HiddenSpell, data.layouts[1].overrides[101])
        T.assert.equal(Cat.HiddenAura, data.layouts[1].overrides[401])
        MySlot:AnnounceCooldownManagerPending()
    end)

    T.it("Clear COOLDOWNMANAGER never touches the live Cooldown Manager (#133)", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()

        -- CooldownViewerSettings and the viewer frames are stubbed to error on any
        -- access but IsShown: writing Blizzard's live state from addon code taints
        -- it until /reload, breaking UNIT_AURA handling, Edit Mode and Copy to
        -- Clipboard. A failed sandbox makes Clear print an error, so check for that.
        MySlot:Clear("COOLDOWNMANAGER")
        T.assert.not_nil(_G.WowStub.cooldown_layout)
        T.assert.equal(0, #_G.WowStub.printed)
        MySlot:AnnounceCooldownManagerPending()
    end)

    T.it("announces a saved cooldown layout once, with an Apply now link", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()

        MySlot:Clear("COOLDOWNMANAGER")
        MySlot:AnnounceCooldownManagerPending()
        T.assert.equal(1, #_G.WowStub.printed)
        local msg = _G.WowStub.printed[1]
        T.assert.is_true(msg:find("/reload", 1, true) ~= nil)
        T.assert.is_true(msg:find("|Haddon:myslot:cdm-apply|h[Apply now]|h", 1, true) ~= nil)

        -- Nothing new to announce.
        MySlot:AnnounceCooldownManagerPending()
        T.assert.equal(1, #_G.WowStub.printed)

        -- Clearing an already cleared layout writes nothing.
        MySlot:Clear("COOLDOWNMANAGER")
        MySlot:AnnounceCooldownManagerPending()
        T.assert.equal(1, #_G.WowStub.printed)
    end)

    T.it("builds a single-layout import string for Blizzard's Import Layout dialog", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()

        MySlot:Clear("COOLDOWNMANAGER")
        MySlot:AnnounceCooldownManagerPending()
        local single = _G.WowStub.decode_cooldown_blob(MySlot:GetCooldownLayoutImportString())
        T.assert.not_nil(single.layouts[1])
        T.assert.equal(nil, next(single.active))
    end)

    local function cooldown_layout(layoutID, name, specTag, overrides)
        return { layoutID = layoutID, layoutName = name, classAndSpecTag = specTag, overrides = overrides or {} }
    end

    T.it("imports a profile's cooldown layout as an active 'Myslot' layout", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()
        local Stub = _G.WowStub

        -- The player's own layout stays; the profile's becomes "Myslot" and active.
        Stub.cooldown_layout = Stub.encode_cooldown_blob({
            layouts = { [1] = cooldown_layout(1, "Mine", 11, { [101] = 1 }) },
            active = { [11] = 1 },
        })
        local profile = Stub.encode_cooldown_blob({
            layouts = {
                [7] = cooldown_layout(7, "Theirs", 11, { [201] = -1 }),
                [8] = cooldown_layout(8, "Prot", 13, { [301] = -2 }),
            },
            active = { [11] = 7, [13] = 8 },
        })

        T.assert.is_true(MySlot:ImportCooldownManagerLayout(profile))
        MySlot:AnnounceCooldownManagerPending()
        local data = Stub.decode_cooldown_blob(Stub.cooldown_layout)
        T.assert.equal("Mine", data.layouts[1].layoutName)
        local arms = data.layouts[data.active[11]]
        T.assert.equal("Myslot", arms.layoutName)
        T.assert.equal(-1, arms.overrides[201])
        local prot = data.layouts[data.active[13]]
        T.assert.equal("Myslot", prot.layoutName)
        T.assert.equal(13, prot.classAndSpecTag)

        -- Importing again replaces the earlier "Myslot" layouts instead of piling up.
        local before = 0
        for _ in pairs(data.layouts) do before = before + 1 end
        local profile2 = Stub.encode_cooldown_blob({
            layouts = { [3] = cooldown_layout(3, "Theirs", 11, { [102] = -1 }) },
            active = { [11] = 3 },
        })
        T.assert.is_true(MySlot:ImportCooldownManagerLayout(profile2))
        MySlot:AnnounceCooldownManagerPending()
        data = Stub.decode_cooldown_blob(Stub.cooldown_layout)
        local after = 0
        for _ in pairs(data.layouts) do after = after + 1 end
        T.assert.equal(before, after)
        T.assert.equal(-1, data.layouts[data.active[11]].overrides[102])
        T.assert.equal(nil, data.layouts[data.active[11]].overrides[201])
    end)

    T.it("skips cooldown layouts of other classes", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()
        local Stub = _G.WowStub

        local profile = Stub.encode_cooldown_blob({
            layouts = { [1] = cooldown_layout(1, "Rogue", 41) },
            active = { [41] = 1 },
        })
        T.assert.equal(false, MySlot:ImportCooldownManagerLayout(profile))
        T.assert.equal(nil, Stub.cooldown_layout)
        T.assert.equal(1, #Stub.printed)
    end)

    T.it("imports the current spec's cooldown layout first when layouts are full", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()
        local Stub = _G.WowStub

        local own = {}
        for i = 1, 4 do own[i] = cooldown_layout(i, "Mine" .. i, 12) end
        Stub.cooldown_layout = Stub.encode_cooldown_blob({ layouts = own, active = {} })
        local profile = Stub.encode_cooldown_blob({
            layouts = {
                [1] = cooldown_layout(1, "Fury", 12),
                [2] = cooldown_layout(2, "Arms", 11),
            },
            active = { [11] = 2, [12] = 1 },
        })

        T.assert.is_true(MySlot:ImportCooldownManagerLayout(profile))
        MySlot:AnnounceCooldownManagerPending()
        local data = Stub.decode_cooldown_blob(Stub.cooldown_layout)
        T.assert.equal("Myslot", data.layouts[data.active[11]].layoutName)
        T.assert.equal(nil, data.active[12])
        T.assert.is_true(Stub.printed[1]:find("Skipped 1", 1, true) ~= nil)
    end)

    T.it("switches a spec to the default cooldown layout when the profile did", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()
        local Stub = _G.WowStub

        Stub.cooldown_layout = Stub.encode_cooldown_blob({
            layouts = { [1] = cooldown_layout(1, "Mine", 11) },
            active = { [11] = 1 },
        })
        local profile = Stub.encode_cooldown_blob({ layouts = {}, active = { [11] = 0 } })

        T.assert.is_true(MySlot:ImportCooldownManagerLayout(profile))
        MySlot:AnnounceCooldownManagerPending()
        local data = Stub.decode_cooldown_blob(Stub.cooldown_layout)
        T.assert.equal(0, data.active[11])
        T.assert.equal("Mine", data.layouts[1].layoutName)
    end)

    T.it("keeps a pending cooldown layout when Blizzard auto-saves its stale copy", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()

        MySlot:Clear("COOLDOWNMANAGER")
        MySlot:AnnounceCooldownManagerPending()
        local pending = _G.WowStub.cooldown_layout

        -- e.g. a spec change makes Blizzard serialize its in-memory layouts.
        C_CooldownViewer.SetLayoutData("stale")
        T.assert.equal(pending, _G.WowStub.cooldown_layout)
    end)

    T.it("drops a pending cooldown layout when the user saves in Blizzard's panel", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()

        MySlot:Clear("COOLDOWNMANAGER")
        MySlot:AnnounceCooldownManagerPending()
        _G.WowStub.printed = {}

        _G.WowStub.cooldown_settings_shown = true
        C_CooldownViewer.SetLayoutData("edited")
        T.assert.equal("edited", _G.WowStub.cooldown_layout)
        T.assert.equal(1, #_G.WowStub.printed)

        -- No longer pending: later Blizzard saves are left alone.
        _G.WowStub.cooldown_settings_shown = false
        C_CooldownViewer.SetLayoutData("later")
        T.assert.equal("later", _G.WowStub.cooldown_layout)
        T.assert.equal(nil, MySlot:GetCooldownLayoutImportString())
    end)

    T.it("export captures the click cast binding profile", function()
        -- Drives the C_ClickBindings stub: Export should pull GetProfileInfo()
        -- into msg.clickBinding. The SetProfileByInfo import wiring is covered by
        -- the in-game suite (RecoverData isn't CI-safe).
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()
        _G.WowStub.click_bindings = {
            { type = 1, actionID = 17116, button = "Button1", modifiers = 1 },
            { type = 3, actionID = 1,     button = "Button2", modifiers = 0 },
        }

        local msg = MySlot:Import(MySlot:Export(full_opt()), { force = true })
        T.assert.equal(2, len(msg.clickBinding))
        T.assert.equal(1, msg.clickBinding[1].type)
        T.assert.equal(17116, msg.clickBinding[1].actionID)
        T.assert.equal("Button1", msg.clickBinding[1].button)
        T.assert.equal(1, msg.clickBinding[1].modifiers)
        T.assert.equal(3, msg.clickBinding[2].type)

        -- And it's omitted when there's nothing to export.
        Host.reset()
        local msg2 = MySlot:Import(MySlot:Export(full_opt()), { force = true })
        T.assert.equal(0, len(msg2.clickBinding))
    end)

    T.it("Clear CLICKBINDING resets the profile", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()
        _G.WowStub.click_bindings = {
            { type = 1, actionID = 100, button = "Button1", modifiers = 0 },
        }

        MySlot:Clear("CLICKBINDING")
        T.assert.equal(0, #_G.WowStub.click_bindings)
    end)
end)

T.describe("Loadout ordering (issue #102)", function()

    -- 4 saved loadouts; "gamma" is a legacy entry saved before class tagging.
    local function sample()
        return {
            { name = "Zeta",  class = "DRUID" },
            { name = "alpha", class = "HUNTER" },
            { name = "Beta",  class = "DRUID" },
            { name = "gamma" },
        }
    end

    local function indices(rows)
        local out = {}
        for _, r in ipairs(rows) do
            if r.index then out[#out + 1] = r.index end
        end
        return out
    end

    T.it("date sort lists newest (highest index) first", function()
        local rows = MySlot:OrderLoadouts(sample(), "date", false, "DRUID")
        T.assert.same({ 4, 3, 2, 1 }, indices(rows))
    end)

    T.it("name sort orders case-insensitively A-Z", function()
        local rows = MySlot:OrderLoadouts(sample(), "name", false, "DRUID")
        -- alpha(2), Beta(3), gamma(4), Zeta(1)
        T.assert.same({ 2, 3, 4, 1 }, indices(rows))
    end)

    T.it("class sort groups by class with headers, unknown last", function()
        local rows = MySlot:OrderLoadouts(sample(), "class", false, "DRUID")
        -- DRUID: Beta(3), Zeta(1); HUNTER: alpha(2); unknown: gamma(4)
        T.assert.same({ 3, 1, 2, 4 }, indices(rows))

        local headers = {}
        for _, r in ipairs(rows) do
            if r.index == nil then headers[#headers + 1] = r.header end
        end
        T.assert.same({ "DRUID", "HUNTER", false }, headers)
    end)

    T.it("only-my-class filter hides other classes but keeps legacy entries", function()
        local rows = MySlot:OrderLoadouts(sample(), "date", true, "DRUID")
        -- DRUID 1,3 kept; HUNTER 2 hidden; legacy gamma(4) always shown; newest first
        T.assert.same({ 4, 3, 1 }, indices(rows))
    end)
end)
