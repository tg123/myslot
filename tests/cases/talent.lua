local _, MySlot = ...
local T = MySlot.test
local Host = MySlot.host
-- The fakes below swap enum tables in and out; Enum is a read-only global to
-- luacheck, so go through a local alias of the same table.
local Enum = _G.Enum

local RETAIL_TALENT = "CEUAAAAAAAAAAAAAAAAAAAAAAMzMzMzsZmZmZGmxsNzMzMzsZmZmZGGAAAAAAAAzMzMzMbGmxsNzMzMzsZmZmZGA"

-- Header block of a real export, without the base64 payload.
local function header(talentline)
    local s = "# Myslot (https://myslot.net <- share your profile here)\n"
        .. "# Wow Version: 11.1.7 (61559)\n"
        .. "# Addon Version: 1.2.3\n"
        .. "# Time: Sat Sep 20 01:26:22 2025\n"
        .. "# Player: Bob\n"
        .. "# Class: Druid\n"
        .. "# Specialization: Balance\n"
    if talentline then
        s = s .. talentline .. "\n"
    end
    return s
        .. "# Level: 80\n"
        .. "# \n"
        .. "# Feedback  farmer1992@gmail.com\n"
        .. "# --------------------\n"
        .. "KgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n"
        .. "# --------------------\n"
        .. "# END OF MYSLOT"
end

T.describe("Talent string (issue #129)", function()

    T.it("reads the talent header of an export", function()
        local text = header("# " .. TALENTS .. ": " .. RETAIL_TALENT)
        T.assert.equal(RETAIL_TALENT, MySlot:ParseTalentString(text))
    end)

    T.it("ignores the classic per-tree point spread, nothing can import it", function()
        T.assert.equal(nil, MySlot:ParseTalentString(header("# " .. TALENTS .. ": 0/21/50")))
    end)

    T.it("returns nil when the profile carries no talents", function()
        T.assert.equal(nil, MySlot:ParseTalentString(header(nil)))
        T.assert.equal(nil, MySlot:ParseTalentString(""))
        T.assert.equal(nil, MySlot:ParseTalentString(nil))
    end)

    T.it("falls back to the loadout-like value of a foreign language export", function()
        -- Exported by a zhCN client, so the header label never matches ours.
        T.assert.equal(RETAIL_TALENT, MySlot:ParseTalentString(header("# \229\164\169\232\181\139: " .. RETAIL_TALENT)))
        T.assert.equal(nil, MySlot:ParseTalentString(header("# \229\164\169\232\181\139: 0/21/50")))
    end)

    T.it("never mistakes the payload or another header for a talent string", function()
        -- Payload lines are base64 and long enough to look like a loadout
        -- string, so parsing has to stop at the end of the header block.
        T.assert.equal(nil, MySlot:ParseTalentString(header(nil)))
        T.assert.equal(nil, MySlot:ParseTalentString("# Player: Bob\n# Level: 80\n"))
    end)

    T.it("only supports talent strings from Dragonflight retail onwards", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        local saved = _G.WowStub.interface_version

        for iface, expected in pairs({
            [100000] = true,   -- Dragonflight, loadout strings introduced
            [110000] = true,   -- The War Within
            [120100] = true,   -- Midnight
            [11508]  = false,  -- Classic Era
            [16001]  = false,  -- WoW Forever, modern engine but vanilla content
            [20505]  = false,  -- TBC
            [30405]  = false,  -- Wrath
            [40402]  = false,  -- Cata
            [50504]  = false,  -- Mists
            [90207]  = false,  -- Shadowlands, before the talent rework
        }) do
            _G.WowStub.interface_version = iface
            T.assert.equal(expected, MySlot:IsTalentStringSupported(), "interface " .. iface)
        end

        _G.WowStub.interface_version = saved
    end)

    T.it("reads back the talent string it exported", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()

        local talentsFrame = {
            GetConfigID = function() return 1 end,
            UpdateTreeInfo = function() end,
            GetLoadoutExportString = function() return RETAIL_TALENT end,
        }
        _G.PlayerSpellsFrame_LoadUI = function() end
        _G.PlayerSpellsFrame = { TalentsFrame = talentsFrame }

        T.assert.equal(RETAIL_TALENT, MySlot:GetTalentString())

        local text = MySlot:Export({
            ignoreActionBars = {},
            ignoreMacros = {},
            ignoreBinding = false,
            ignorePetActionBar = true,
        })
        T.assert.equal(RETAIL_TALENT, MySlot:ParseTalentString(text))

        _G.PlayerSpellsFrame_LoadUI = nil
        _G.PlayerSpellsFrame = nil
        T.assert.equal(nil, MySlot:GetTalentString())
    end)
end)

-- {{{ Apply talents
-- Fakes the retail talent APIs and Blizzard's loadout codec, captures the
-- event frame ApplyTalentString creates, and fires the events by hand.
local LOADOUT_ERRORS = {
    LOADOUT_ERROR_BAD_STRING = "bad string",
    LOADOUT_ERROR_IMPORT_FAILED = "import failed",
    LOADOUT_ERROR_SERIALIZATION_VERSION_MISMATCH = "version mismatch",
    LOADOUT_ERROR_TREE_CHANGED = "tree changed",
    LOADOUT_ERROR_WRONG_SPEC = "wrong spec",
}

local FAKED_GLOBALS = {
    "C_ClassTalents", "C_Traits", "C_Timer", "ExportUtil", "ClassTalentImportExportMixin",
    "CreateFromMixins", "CreateFrame", "GetSpecialization", "GetSpecializationInfo",
    "GetSpecializationInfoByID", "PlayerSpellsFrame", "PlayerSpellsFrame_LoadUI", "HideUIPanel",
    "ShowUIPanel", "PlayerSpellsUtil", "GetNumSpecializations",
}
for name in pairs(LOADOUT_ERRORS) do FAKED_GLOBALS[#FAKED_GLOBALS + 1] = name end

local fake
-- The event frame is created once and reused, so keep what it was given.
local eventFrame, eventHandler

local function fire(event, ...)
    eventHandler(eventFrame, event, ...)
end

local function install()
    local zeroHash = {}
    for i = 1, 16 do zeroHash[i] = 0 end

    fake = {
        -- The class's specs; the player is in the first.
        specs = { 102, 103 },
        header = { ok = true, version = 2, spec = 102, hash = zeroHash },
        treeHash = zeroHash,
        -- 11 is the loadout a previous apply left behind.
        configs = { [11] = { name = "Myslot" }, [12] = { name = "Raid" } },
        entries = { { nodeID = 1, ranksGranted = 0, ranksPurchased = 1, selectionEntryID = 9 } },
        active = 5,
        canEdit = true,
        canCreate = true,
        populated = true,
        importOk = true,
        deleted = {},
        loads = {},
        hidden = {},
        -- The talent window: its loadout dropdown has "Raid" selected.
        window = { shown = false, opened = 0, selection = 12, selections = {} },
    }

    local saved = {}
    for _, name in ipairs(FAKED_GLOBALS) do saved[name] = _G[name] end
    saved.Enum_TraitConfigType = Enum.TraitConfigType

    for name, text in pairs(LOADOUT_ERRORS) do _G[name] = text end
    Enum.TraitConfigType = { Invalid = 0, Combat = 1, Profession = 2, Generic = 3 }

    -- No timers unless a test adds them: the timeout would fire right away.
    _G.C_Timer = nil
    _G.PlayerSpellsFrame_LoadUI = nil
    _G.ShowUIPanel = nil
    _G.HideUIPanel = function(frame)
        fake.hidden[#fake.hidden + 1] = frame
        fake.window.shown = false
    end
    _G.PlayerSpellsFrame = {
        IsShown = function() return fake.window.shown end,
        TalentsFrame = {
            LoadSystem = {
                GetSelectionID = function() return fake.window.selection end,
            },
            SetSelectedSavedConfigID = function(_, configID, autoApply)
                fake.window.selection = configID
                table.insert(fake.window.selections, { id = configID, autoApply = autoApply })
            end,
        },
    }
    _G.PlayerSpellsUtil = {
        OpenToClassTalentsTab = function()
            fake.window.opened = fake.window.opened + 1
            fake.window.shown = true
        end,
    }

    _G.GetSpecialization = function() return 1 end
    _G.GetNumSpecializations = function() return #fake.specs end
    _G.GetSpecializationInfo = function(index) return fake.specs[index] end
    _G.GetSpecializationInfoByID = function(id) return id, "Spec" .. id end

    _G.C_ClassTalents = {
        CanEditTalents = function() return fake.canEdit, fake.editError or "" end,
        GetActiveConfigID = function() return fake.active end,
        GetTraitTreeForSpec = function() return 700 end,
        GetConfigIDsBySpecID = function(specID)
            local ids = {}
            for id, info in pairs(fake.configs) do
                if (info.spec or 102) == specID then ids[#ids + 1] = id end
            end
            table.sort(ids)
            return ids
        end,
        DeleteConfig = function(id)
            fake.configs[id] = nil
            fake.deleted[#fake.deleted + 1] = id
            return true
        end,
        CanCreateNewConfig = function() return fake.canCreate end,
        ImportLoadout = function(configID, entries, name, importString)
            fake.imported = { configID = configID, entries = entries, name = name, importString = importString }
            return fake.importOk, fake.importError or ""
        end,
        IsConfigPopulated = function() return fake.populated end,
        LoadConfig = function(id, autoApply)
            fake.loads[#fake.loads + 1] = { id = id, autoApply = autoApply }
        end,
        UpdateLastSelectedSavedConfigID = function(specID, configID)
            fake.lastSelected = { specID, configID }
        end,
    }
    _G.C_Traits = {
        GetLoadoutSerializationVersion = function() return 2 end,
        GetTreeHash = function(treeID)
            fake.hashedTree = treeID
            return fake.treeHash
        end,
        GetConfigInfo = function(id) return fake.configs[id] end,
    }
    _G.ExportUtil = { MakeImportDataStream = function(s) return { s = s } end }
    _G.ClassTalentImportExportMixin = {
        ReadLoadoutHeader = function()
            local h = fake.header
            return h.ok, h.version, h.spec, h.hash
        end,
        IsHashEmpty = function(_, hash)
            for _, v in ipairs(hash) do
                if v ~= 0 then return false end
            end
            return true
        end,
        HashEquals = function(_, a, b)
            for i = 1, 16 do
                if a[i] ~= b[i] then return false end
            end
            return true
        end,
        ReadLoadoutContent = function()
            if fake.readError then error(fake.readError) end
            return {}
        end,
        ConvertToImportLoadoutEntryInfo = function() return fake.entries end,
    }
    _G.CreateFromMixins = function(mixin)
        local t = {}
        for k, v in pairs(mixin) do t[k] = v end
        return t
    end
    _G.CreateFrame = function()
        local fr = { events = {} }
        function fr:SetScript(_, fn)
            eventFrame, eventHandler = self, fn
        end
        function fr:RegisterEvent(e) self.events[e] = true end
        function fr:UnregisterEvent(e) self.events[e] = nil end
        function fr:UnregisterAllEvents() self.events = {} end
        return fr
    end

    return function()
        for _, name in ipairs(FAKED_GLOBALS) do _G[name] = saved[name] end
        Enum.TraitConfigType = saved.Enum_TraitConfigType
        _G.WowStub.in_combat = false
    end
end

-- Runs fn with the fakes installed, restoring the globals even if it fails.
local function with_fakes(fn)
    if Host.in_wow then T.skip("CI-only (stub-backed)") end
    local restore = install()
    local ok, err = pcall(fn)
    restore()
    if not ok then error(err, 0) end
end

local function start(onDone)
    return MySlot:ApplyTalentString(RETAIL_TALENT, onDone)
end

T.describe("Apply talents (issue #129)", function()

    T.it("replaces the Myslot loadout and opens it in the talent window, unapplied", function()
        with_fakes(function()
            local done
            T.assert.equal(true, (start(function(ok, err) done = { ok = ok, err = err } end)))

            -- Only the previous "Myslot" loadout is dropped.
            T.assert.same({ 11 }, fake.deleted)
            T.assert.not_nil(fake.configs[12])

            T.assert.equal(5, fake.imported.configID)
            T.assert.equal("Myslot", fake.imported.name)
            T.assert.equal(RETAIL_TALENT, fake.imported.importString)
            T.assert.same(fake.entries, fake.imported.entries)
            T.assert.equal(true, eventFrame.events.TRAIT_CONFIG_CREATED)

            -- Someone else's new loadout is not ours to open.
            fire("TRAIT_CONFIG_CREATED", { ID = 30, name = "Raid", type = Enum.TraitConfigType.Combat })
            T.assert.equal(0, fake.window.opened)

            fire("TRAIT_CONFIG_CREATED", { ID = 21, name = "Myslot", type = Enum.TraitConfigType.Combat })
            T.assert.same({ 102, 21 }, fake.lastSelected)
            T.assert.equal(1, fake.window.opened)

            -- "Raid" was selected, so "Myslot" is selected in its place, the way
            -- the dropdown does it; nothing is committed, that's the player's
            -- "Apply Changes" click.
            T.assert.same({ { id = 21, autoApply = false } }, fake.window.selections)
            T.assert.same({}, fake.loads)

            T.assert.same({ ok = true }, done)
            T.assert.equal(nil, eventFrame.events.TRAIT_CONFIG_CREATED, "events released")
        end)
    end)

    T.it("leaves the selection to the talent window when it already picked the loadout", function()
        with_fakes(function()
            -- Blizzard's OnShow selects the last selected loadout when nothing
            -- valid is selected yet.
            _G.PlayerSpellsUtil.OpenToClassTalentsTab = function()
                fake.window.opened = fake.window.opened + 1
                fake.window.selection = fake.lastSelected[2]
            end
            start()
            fire("TRAIT_CONFIG_CREATED", { ID = 21, name = "Myslot", type = Enum.TraitConfigType.Combat })
            T.assert.equal(1, fake.window.opened)
            T.assert.same({}, fake.window.selections)
        end)
    end)

    T.it("waits until a new loadout is populated before opening it", function()
        with_fakes(function()
            fake.populated = false
            local done
            start(function(ok) done = ok end)

            fire("TRAIT_CONFIG_CREATED", { ID = 21, name = "Myslot", type = Enum.TraitConfigType.Combat })
            fire("TRAIT_CONFIG_UPDATED", 99)
            T.assert.equal(0, fake.window.opened)

            fire("TRAIT_CONFIG_UPDATED", 21)
            T.assert.equal(1, fake.window.opened)
            T.assert.equal(true, done)

            -- A later update of the same loadout doesn't reopen anything.
            fire("TRAIT_CONFIG_UPDATED", 21)
            T.assert.equal(1, fake.window.opened)
        end)
    end)

    T.it("opens the talent window on the next frame and times out without a loadout", function()
        with_fakes(function()
            local timers = {}
            _G.C_Timer = { After = function(delay, fn) timers[delay] = fn end }

            local done
            start(function(ok, err) done = { ok = ok, err = err } end)
            -- The old "Myslot" loadout goes first, and nothing is imported
            -- until it reports back.
            T.assert.same({ 11 }, fake.deleted)
            T.assert.equal(nil, fake.imported)
            fire("TRAIT_CONFIG_DELETED", 11)
            T.assert.not_nil(fake.imported)

            fire("TRAIT_CONFIG_CREATED", { ID = 21, name = "Myslot", type = Enum.TraitConfigType.Combat })
            -- Not while TRAIT_CONFIG_CREATED is still being dispatched: the
            -- window would hear it too and auto-apply the loadout.
            T.assert.equal(0, fake.window.opened)

            timers[0]()
            T.assert.equal(1, fake.window.opened)
            T.assert.same({ ok = true }, done)

            -- The timeout of a finished apply is a no-op.
            timers[30]()
            T.assert.same({ ok = true }, done)

            -- One whose loadout never shows up is reported.
            timers = {}
            start(function(ok, err) done = { ok = ok, err = err } end)
            timers[30]()
            T.assert.same({ ok = false, err = "Timed out applying talents" }, done)
            T.assert.equal(1, fake.window.opened)
        end)
    end)

    T.it("closes an open talent window first so it doesn't apply the loadout itself", function()
        with_fakes(function()
            fake.window.shown = true
            start()
            T.assert.same({ _G.PlayerSpellsFrame }, fake.hidden)
            fire("TRAIT_CONFIG_CREATED", { ID = 21, name = "Myslot", type = Enum.TraitConfigType.Combat })
            T.assert.equal(1, fake.window.opened)
        end)
    end)

    T.it("refuses loadouts for another spec, naming the spec", function()
        with_fakes(function()
            fake.header.spec = 105
            local ok, err = start()
            T.assert.equal(false, ok)
            T.assert.is_true(err:find("Spec105", 1, true) ~= nil, err)
            T.assert.same({}, fake.deleted)
            T.assert.equal(nil, fake.imported)
        end)
    end)

    T.it("refuses strings of another serialization format", function()
        with_fakes(function()
            fake.header.version = 1
            T.assert.same({ false, "version mismatch" }, { start() })

            fake.header.ok = false
            T.assert.same({ false, "bad string" }, { start() })
            T.assert.equal(nil, fake.imported)
        end)
    end)

    T.it("still loads a string saved from an older talent tree, without its string", function()
        with_fakes(function()
            local changed = {}
            for i = 1, 16 do changed[i] = i end
            fake.header.hash = changed

            local done
            T.assert.equal(true, (start(function(ok) done = ok end)))
            T.assert.equal("Myslot", fake.imported.name)
            T.assert.same(fake.entries, fake.imported.entries)
            T.assert.equal(nil, fake.imported.importString)

            fire("TRAIT_CONFIG_CREATED", { ID = 21, name = "Myslot", type = Enum.TraitConfigType.Combat })
            T.assert.equal(true, done)
            T.assert.same({}, fake.loads)
        end)
    end)

    T.it("refuses an older string that no longer decodes against the tree", function()
        with_fakes(function()
            local changed = {}
            for i = 1, 16 do changed[i] = i end
            fake.header.hash = changed
            fake.readError = "attempt to read past the end of the stream"
            T.assert.same({ false, "tree changed", "invalid" }, { MySlot:CheckTalentString(RETAIL_TALENT) })
        end)
    end)

    T.it("checks the hash against the tree of the active config, like the talent window", function()
        with_fakes(function()
            local changed = {}
            for i = 1, 16 do changed[i] = i end
            fake.header.hash = changed

            -- Falls back to the spec's tree without an active config tree.
            MySlot:CheckTalentString(RETAIL_TALENT)
            T.assert.equal(700, fake.hashedTree)

            fake.configs[fake.active] = { name = "Default", treeIDs = { 800 } }
            MySlot:CheckTalentString(RETAIL_TALENT)
            T.assert.equal(800, fake.hashedTree)
        end)
    end)

    T.it("pre-checks a string without touching any loadout", function()
        with_fakes(function()
            T.assert.same({ true }, { MySlot:CheckTalentString(RETAIL_TALENT) })

            local changed = {}
            for i = 1, 16 do changed[i] = i end
            fake.header.hash = changed
            T.assert.same({ true, "tree changed", "outdated" }, { MySlot:CheckTalentString(RETAIL_TALENT) })

            fake.header.hash = fake.treeHash
            fake.header.version = 1
            T.assert.same({ false, "version mismatch", "format" }, { MySlot:CheckTalentString(RETAIL_TALENT) })

            fake.header.version = 2
            fake.header.spec = 105
            local ok, err, reason = MySlot:CheckTalentString(RETAIL_TALENT)
            T.assert.equal(false, ok)
            T.assert.is_true(err:find("Spec105", 1, true) ~= nil, err)
            T.assert.equal("spec", reason)

            T.assert.same({}, fake.deleted)
            T.assert.equal(nil, fake.imported)
            T.assert.same({ false, "bad string", "invalid" }, { MySlot:CheckTalentString("") })
        end)
    end)

    T.it("refuses while talents can't change", function()
        with_fakes(function()
            _G.WowStub.in_combat = true
            T.assert.equal(false, (start()))
            _G.WowStub.in_combat = false

            fake.canEdit = false
            fake.editError = "in a mythic keystone"
            T.assert.same({ false, "in a mythic keystone" }, { start() })
            T.assert.equal(nil, fake.imported)
        end)
    end)

    T.it("frees itself when the import is refused", function()
        with_fakes(function()
            fake.importOk = false
            fake.importError = "too many loadouts"
            local done
            T.assert.equal(true, (start(function(ok, err) done = { ok = ok, err = err } end)))
            T.assert.same({ ok = false, err = "too many loadouts" }, done)

            -- Nothing is left pending, so the next attempt can go ahead.
            fake.importOk = true
            T.assert.equal(true, (start()))
            fire("TRAIT_CONFIG_CREATED", { ID = 21, name = "Myslot", type = Enum.TraitConfigType.Combat })
        end)
    end)

    T.it("reports when no loadout can be added", function()
        with_fakes(function()
            fake.canCreate = false
            local done
            start(function(ok, err) done = { ok = ok, err = err } end)
            T.assert.same({ ok = false, err = "Too many saved talent loadouts, delete one first" }, done)
            T.assert.equal(nil, fake.imported)
        end)
    end)

    T.it("is not offered on classic", function()
        with_fakes(function()
            local saved = _G.WowStub.interface_version
            _G.WowStub.interface_version = 30405
            local ok = start()
            _G.WowStub.interface_version = saved
            T.assert.equal(false, ok)
            T.assert.equal(nil, fake.imported)
        end)
    end)
end)

T.describe("/myslot clear talents", function()

    -- Filled in by the (possibly later) completion callback.
    local result
    local function clear()
        result = nil
        return MySlot:DeleteTalentLoadouts(function(deleted, failed)
            result = { deleted = deleted, failed = failed }
        end)
    end

    T.it("deletes the Myslot loadouts of every spec and nothing else", function()
        with_fakes(function()
            fake.configs = {
                [fake.active] = { name = "Myslot", spec = 102 }, -- in use
                [11] = { name = "Myslot", spec = 102 },
                [12] = { name = "Raid", spec = 102 },
                [13] = { name = "Myslot", spec = 103 },
                [14] = { name = "Myslot", spec = 103 },
                [15] = { name = "Myslot", spec = 999 }, -- another class
            }
            local found = clear()
            T.assert.equal(3, found)
            T.assert.same({ deleted = 3, failed = 0 }, result)
            T.assert.same({ 11, 13, 14 }, fake.deleted)
            T.assert.not_nil(fake.configs[12])
            T.assert.not_nil(fake.configs[15])
            T.assert.not_nil(fake.configs[fake.active])

            found = clear()
            T.assert.equal(0, found)
            T.assert.same({ deleted = 0, failed = 0 }, result)
        end)
    end)

    T.it("deletes one at a time, counting TRAIT_CONFIG_DELETED, not the reply", function()
        with_fakes(function()
            local timers = {}
            _G.C_Timer = { After = function(delay, fn) table.insert(timers, { delay = delay, fn = fn }) end }
            fake.configs = {
                [11] = { name = "Myslot", spec = 102 },
                [13] = { name = "Myslot", spec = 103 },
                [14] = { name = "Myslot", spec = 103 },
            }
            -- The reply says no, but the loadout goes anyway.
            local delete = _G.C_ClassTalents.DeleteConfig
            _G.C_ClassTalents.DeleteConfig = function(id)
                delete(id)
                return false
            end

            clear()
            T.assert.same({ 11 }, fake.deleted, "one request at a time")

            fire("TRAIT_CONFIG_DELETED", 99) -- someone else's
            T.assert.same({ 11 }, fake.deleted)

            fire("TRAIT_CONFIG_DELETED", 11)
            T.assert.same({ 11, 13 }, fake.deleted)

            -- 13 never reports back: its timeout moves on to 14.
            timers[2].fn()
            T.assert.equal(2, timers[2].delay)
            T.assert.same({ 11, 13, 14 }, fake.deleted)

            -- A stale timeout (11's) changes nothing.
            timers[1].fn()
            T.assert.equal(nil, result)

            fire("TRAIT_CONFIG_DELETED", 14)
            T.assert.same({ deleted = 2, failed = 1 }, result)
            T.assert.equal(nil, eventFrame.events.TRAIT_CONFIG_DELETED, "events released")
        end)
    end)

    T.it("is what Clear TALENTLOADOUT (the options button) runs", function()
        with_fakes(function()
            local printed = _G.WowStub.printed
            local before = #printed
            MySlot:Clear("TALENTLOADOUT")
            T.assert.same({ 11 }, fake.deleted)
            T.assert.equal(before + 1, #printed)
            T.assert.is_true(printed[#printed]:find("Deleted 1 'Myslot' talent loadout(s)", 1, true) ~= nil,
                printed[#printed])
        end)
    end)

    T.it("reports the Myslot loadouts it could not delete", function()
        with_fakes(function()
            fake.configs = {
                [11] = { name = "Myslot", spec = 102 },
                [13] = { name = "Myslot", spec = 103 },
            }
            _G.C_ClassTalents.DeleteConfig = function(id) return id ~= 13 end
            clear()
            T.assert.same({ deleted = 1, failed = 1 }, result)

            local printed = _G.WowStub.printed
            MySlot:Clear("TALENTLOADOUT")
            T.assert.is_true(printed[#printed]:find("Could not delete 1 'Myslot' talent loadout(s)", 1, true) ~= nil,
                printed[#printed])
        end)
    end)

    T.it("refuses in combat, while applying or deleting, and on classic", function()
        with_fakes(function()
            _G.WowStub.in_combat = true
            T.assert.equal(false, (clear()))
            _G.WowStub.in_combat = false

            start()
            T.assert.same({ false, "Talents are already being applied" }, { MySlot:DeleteTalentLoadouts() })
            fire("TRAIT_CONFIG_CREATED", { ID = 21, name = "Myslot", type = Enum.TraitConfigType.Combat })

            -- A delete waiting on TRAIT_CONFIG_DELETED blocks both.
            _G.C_Timer = { After = function() end }
            fake.configs[13] = { name = "Myslot", spec = 103 }
            clear()
            T.assert.same({ false, "Talents are already being applied" }, { MySlot:DeleteTalentLoadouts() })
            T.assert.same({ false, "Talents are already being applied" }, { start() })
            fire("TRAIT_CONFIG_DELETED", 13)
            _G.C_Timer = nil

            local saved = _G.WowStub.interface_version
            _G.WowStub.interface_version = 30405
            local ok = clear()
            _G.WowStub.interface_version = saved
            T.assert.equal(false, ok)
            T.assert.same({ 11, 13 }, fake.deleted)
        end)
    end)
end)
-- }}}
