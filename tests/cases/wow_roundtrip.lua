-- In-game end-to-end tests: seed real WoW state via Host APIs, run the full
-- Export -> Import -> RecoverData pipeline, then verify with raw WoW APIs.
-- These are skipped in CI (Host.in_wow is false) because the recovery path
-- calls PickupItem / PickupMacro / CreateMacro / SetBinding / PlaceAction /
-- SaveBindings etc.; faking all of them defeats the purpose of "verify
-- against the real game".
--
-- Safety: every test wraps its body in snapshot()/restore() inside a pcall
-- so a failure or assertion never leaves the character's bars, macros, or
-- bindings in a mutated state.

local _, MySlot = ...
local T = MySlot.test
local Host = MySlot.host

local function full_opt()
    return {
        ignoreActionBars = {},
        ignoreMacros = {},
        ignoreBinding = false,
        ignorePetActionBar = true,
        ignoreCooldownManager = true, -- dedicated test opts in explicitly
    }
end

local function recover_opt()
    return { actionOpt = full_opt() }
end

local MAX_MACROS = (MAX_ACCOUNT_MACROS or 120) + (MAX_CHARACTER_MACROS or 18)

local function find_macro_by_name(name)
    for i = 1, MAX_MACROS do
        local n, _, body = GetMacroInfo(i)
        if n == name then return i, body end
    end
    return nil
end

-- Every macro the suite creates uses one of these exact prefixes. We match only
-- these (not a broad "^Myslot") so running /myslottest never deletes a player's
-- real macros that happen to start with "Myslot".
local TEST_MACRO_PREFIXES = { "MyslotE2E", "MyslotBar", "MyslotT" }

local function is_test_macro(name)
    if not name then return false end
    for _, prefix in ipairs(TEST_MACRO_PREFIXES) do
        if name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- RecoverData never deletes macros (removing a user's macros would be
-- destructive), so snapshot/restore can't reclaim what a test created. Without
-- this purge those macros pile up across runs until the 120-macro account cap
-- fills and CreateMacro starts failing. Collect matches in one pass, then delete
-- highest-index first so the lower indices we still need stay valid.
local function purge_test_macros()
    if not Host.in_wow then return end
    local hits = {}
    for i = 1, MAX_MACROS do
        local n = GetMacroInfo(i)
        if is_test_macro(n) then hits[#hits + 1] = i end
    end
    for j = #hits, 1, -1 do
        DeleteMacro(hits[j])
    end
end

local function in_game(fn)
    return function()
        if not Host.in_wow then T.skip("in-game only") end
        -- Drop any leftover test macros first so they never get baked into the
        -- snapshot (and thus re-created by restore).
        purge_test_macros()
        local snap = Host.snapshot()
        -- T.safe_run is a yield-aware pcall (Lua 5.1 can't yield across a
        -- real pcall). Guarantees restore() runs even on assert failure.
        local ok, err = T.safe_run(fn)
        -- Clean up whatever this test created, then restore the pristine state.
        purge_test_macros()
        Host.restore(snap)
        if not ok then error(err, 0) end
    end
end

-- ---------------------------------------------------------------------------
T.describe("in-game: action bar round-trip (via WoW API)", function()

    T.it("restores an item action slot after Import+RecoverData", in_game(function()
        local SLOT = 1
        local HEARTHSTONE = 6948

        Host.clear_action(SLOT)
        Host.set_action(SLOT, "item", HEARTHSTONE)
        local t, idx = GetActionInfo(SLOT)
        T.assert.equal("item", t)
        T.assert.equal(HEARTHSTONE, idx)

        local text = MySlot:Export(full_opt())
        T.assert.not_nil(text)

        Host.clear_action(SLOT)
        T.assert.equal(nil, GetActionInfo(SLOT))

        local msg = MySlot:Import(text, { force = true })
        T.assert.not_nil(msg)
        MySlot:RecoverData(msg, recover_opt())

        local t2, idx2 = GetActionInfo(SLOT)
        T.assert.equal("item", t2)
        T.assert.equal(HEARTHSTONE, idx2)
    end))

    T.it("clears extra slots not present in the import payload", in_game(function()
        local SLOT_KEEP = 1
        local SLOT_EXTRA = 2
        local HEARTHSTONE = 6948

        Host.clear_action(SLOT_KEEP)
        Host.clear_action(SLOT_EXTRA)
        Host.set_action(SLOT_KEEP, "item", HEARTHSTONE)

        local text = MySlot:Export(full_opt())
        Host.set_action(SLOT_EXTRA, "item", HEARTHSTONE)
        T.assert.not_nil(GetActionInfo(SLOT_EXTRA))

        local msg = MySlot:Import(text, { force = true })
        MySlot:RecoverData(msg, recover_opt())

        T.assert.not_nil(GetActionInfo(SLOT_KEEP))
        T.assert.equal(nil, GetActionInfo(SLOT_EXTRA))
    end))
end)

-- Create a test macro, reclaiming the slot if a previous run left one with
-- the same name behind. Tests should fail (not skip) if the account truly
-- has no macro slots free, otherwise we'd silently green-light a bug.
local function create_test_macro(name, icon, body)
    local existing = find_macro_by_name(name)
    if existing then Host.delete_macro(existing) end
    local id = Host.set_macro(name, icon, body)
    T.assert.not_nil(id, "CreateMacro returned nil for '" .. name ..
        "' (no free macro slots?)")
    -- Classic Era commits a new macro to GetMacroInfo only on the next frame, so
    -- yield once to let it become queryable by name/body before we (or
    -- RecoverData's macro index) look it up. No-op in CI (sync mode).
    T.yield()
    return id
end

-- ---------------------------------------------------------------------------
T.describe("in-game: macro round-trip (via WoW API)", function()

    T.it("re-creates a deleted macro after Import+RecoverData", in_game(function()
        -- WoW caps macro names at 16 chars; "MyslotE2E" + 4 digits = 13.
        local NAME = "MyslotE2E" .. math.random(1000, 9999)
        local BODY = "/say myslot-e2e-" .. tostring(math.random(1, 1e9))
        local ICON = "INV_MISC_QUESTIONMARK"

        local id = create_test_macro(NAME, ICON, BODY)
        T.assert.not_nil(find_macro_by_name(NAME))

        local text = MySlot:Export(full_opt())

        Host.delete_macro(id)
        T.assert.equal(nil, find_macro_by_name(NAME))

        local msg = MySlot:Import(text, { force = true })
        T.assert.not_nil(msg)
        MySlot:RecoverData(msg, recover_opt())

        -- Let the macro RecoverData just created commit before querying it.
        T.yield()

        local found_id, found_body = find_macro_by_name(NAME)
        T.assert.not_nil(found_id)
        T.assert.equal(BODY, found_body)
    end))

    T.it("restores a macro placed on an action slot", in_game(function()
        local SLOT = 1
        -- "MyslotBar" + 4 digits = 13 chars, within WoW's 16-char limit.
        local NAME = "MyslotBar" .. math.random(1000, 9999)
        local BODY = "/say bar-" .. tostring(math.random(1, 1e9))

        local mid = create_test_macro(NAME, "INV_MISC_QUESTIONMARK", BODY)
        Host.clear_action(SLOT)
        Host.set_action(SLOT, "macro", mid)
        local t = GetActionInfo(SLOT)
        T.assert.equal("macro", t)

        local text = MySlot:Export(full_opt())

        Host.clear_action(SLOT)
        Host.delete_macro(mid)
        T.assert.equal(nil, find_macro_by_name(NAME))

        local msg = MySlot:Import(text, { force = true })
        MySlot:RecoverData(msg, recover_opt())

        -- Let the macro RecoverData just created commit before querying it.
        T.yield()

        local new_mid, new_body = find_macro_by_name(NAME)
        T.assert.not_nil(new_mid)
        T.assert.equal(BODY, new_body)

        local at, ai = GetActionInfo(SLOT)
        T.assert.equal("macro", at)
        T.assert.equal(new_mid, ai)
    end))
end)

-- ---------------------------------------------------------------------------
-- All-slots round-trip: fill every slot the game accepts an item on, export,
-- wipe, import, verify each slot came back identical. Uses T.yield() between
-- phases so WoW's per-script watchdog ("script ran too long") doesn't fire
-- on Export's full-payload CRC32 or RecoverData's 180 PlaceAction calls.
T.describe("in-game: all action slots round-trip", function()

    T.it("restores every populated slot 1..180", in_game(function()
        local HEARTHSTONE = 6948
        local MAX = 180

        for slot = 1, MAX do
            Host.clear_action(slot)
            if slot % 30 == 0 then T.yield() end
        end

        local expected = {}
        for slot = 1, MAX do
            Host.set_action(slot, "item", HEARTHSTONE)
            local t, idx = GetActionInfo(slot)
            if t == "item" and idx == HEARTHSTONE then
                expected[slot] = true
            end
            if slot % 30 == 0 then T.yield() end
        end
        T.assert.is_true(next(expected) ~= nil,
            "no slots accepted the test item (cannot validate)")

        T.yield()
        local text = MySlot:Export(full_opt())
        T.assert.not_nil(text)

        T.yield()
        for slot in pairs(expected) do Host.clear_action(slot) end
        T.yield()
        for slot in pairs(expected) do
            T.assert.equal(nil, GetActionInfo(slot),
                "slot " .. slot .. " should be cleared before import")
        end

        T.yield()
        local msg = MySlot:Import(text, { force = true })
        T.assert.not_nil(msg)
        T.yield()
        MySlot:RecoverData(msg, recover_opt())
        T.yield()

        local missing = {}
        for slot in pairs(expected) do
            local t, idx = GetActionInfo(slot)
            if t ~= "item" or idx ~= HEARTHSTONE then
                missing[#missing + 1] = ("%d=%s/%s"):format(
                    slot, tostring(t), tostring(idx))
            end
        end
        T.assert.equal(0, #missing,
            "slots failed to round-trip: " .. table.concat(missing, ","))
    end))
end)

-- ---------------------------------------------------------------------------
-- One test per supported slot type. Verifies via raw GetActionInfo that the
-- (type, id) tuple round-trips through Export -> Import -> RecoverData.
-- Skips cleanly when the character lacks a source (e.g. no collected mounts).
T.describe("in-game: slot type round-trip (per type)", function()

    local SLOT = 1

    local function roundtrip(place_fn)
        Host.clear_action(SLOT)
        place_fn(SLOT)
        local before_t, before_i = GetActionInfo(SLOT)
        if not before_t then T.skip("could not place test action on slot") end

        local text = MySlot:Export(full_opt())
        T.assert.not_nil(text)

        Host.clear_action(SLOT)
        T.assert.equal(nil, GetActionInfo(SLOT))

        local msg = MySlot:Import(text, { force = true })
        T.assert.not_nil(msg)
        MySlot:RecoverData(msg, recover_opt())

        local after_t, after_i = GetActionInfo(SLOT)
        T.assert.equal(before_t, after_t)
        T.assert.equal(before_i, after_i)
    end

    -- Find the first action slot already holding `wantType` ("spell", "flyout",
    -- "summonmount", ...). The classic GetSpellBookItemInfo/BOOKTYPE_SPELL scan was
    -- removed in 12.0, and journal "pick the first collected entry" placement is
    -- flaky (some entries can't be placed), so for these types we reuse whatever the
    -- player already has on their bars.
    local function find_action_of_type(wantType)
        for i = 1, 180 do
            local t, id = GetActionInfo(i)
            if t == wantType then return i, id end
        end
        return nil
    end

    -- Round-trip a type by clearing an existing slot of that type and letting
    -- RecoverData restore it from the export. This exercises MySlot's real restore
    -- path for the type instead of re-implementing per-type pickup in the test.
    local function roundtrip_existing(wantType, label)
        local slot = find_action_of_type(wantType)
        if not slot then T.skip("no " .. (label or wantType) .. " on action bars") end
        local before_t, before_i = GetActionInfo(slot)

        local text = MySlot:Export(full_opt())
        T.assert.not_nil(text)

        Host.clear_action(slot)
        T.assert.equal(nil, GetActionInfo(slot))

        local msg = MySlot:Import(text, { force = true })
        T.assert.not_nil(msg)
        MySlot:RecoverData(msg, recover_opt())

        local after_t, after_i = GetActionInfo(slot)
        T.assert.equal(before_t, after_t)
        T.assert.equal(before_i, after_i)
    end

    T.it("type=spell", in_game(function()
        roundtrip_existing("spell")
    end))

    T.it("type=item", in_game(function()
        roundtrip(function(s) Host.set_action(s, "item", 6948) end)
    end))

    T.it("type=macro", in_game(function()
        -- "MyslotT" + 4 digits = 11 chars, within WoW's 16-char macro name limit.
        local name = "MyslotT" .. math.random(1000, 9999)
        local mid = create_test_macro(name, "INV_MISC_QUESTIONMARK", "/say type-test")
        roundtrip(function(s) Host.set_action(s, "macro", mid) end)
    end))

    T.it("type=mount", in_game(function()
        roundtrip_existing("summonmount", "mount")
    end))

    T.it("type=battle pet", in_game(function()
        if not (C_PetJournal and C_PetJournal.GetNumPets) then
            T.skip("no pet journal API")
        end
        local petGUID
        local total = C_PetJournal.GetNumPets()
        for i = 1, total do
            local guid, _, owned = C_PetJournal.GetPetInfoByIndex(i)
            if owned and guid then petGUID = guid; break end
        end
        if not petGUID then T.skip("no collected battle pets") end
        roundtrip(function(s)
            ClearCursor()
            C_PetJournal.PickupPet(petGUID)
            PlaceAction(s)
            ClearCursor()
        end)
    end))

    T.it("type=equipment set", in_game(function()
        if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs) then
            T.skip("no equipment set API")
        end
        local ids = C_EquipmentSet.GetEquipmentSetIDs()
        if not ids or #ids == 0 then T.skip("no equipment sets") end
        local setID = ids[1]
        roundtrip(function(s)
            ClearCursor()
            C_EquipmentSet.PickupEquipmentSet(setID)
            PlaceAction(s)
            ClearCursor()
        end)
    end))

    T.it("type=outfit", in_game(function()
        if not (C_TransmogOutfitInfo and C_TransmogOutfitInfo.GetOutfitsInfo and C_TransmogOutfitInfo.PickupOutfit) then
            T.skip("no transmog outfit API")
        end
        local outfits = C_TransmogOutfitInfo.GetOutfitsInfo()
        if not outfits or #outfits == 0 then T.skip("no saved outfits") end
        local outfitID = outfits[1].outfitID
        roundtrip(function(s)
            ClearCursor()
            C_TransmogOutfitInfo.PickupOutfit(outfitID)
            PlaceAction(s)
            ClearCursor()
        end)
    end))

    T.it("type=flyout", in_game(function()
        roundtrip_existing("flyout")
    end))
end)

-- ---------------------------------------------------------------------------
-- MySlot:GetBindingInfo only captures key1/key2 (Myslot.lua:283), so if we
-- pick a command with existing default keys (e.g. MOVEFORWARD->W) our test
-- key becomes key3 and is silently dropped from Export. Using commands with
-- no defaults ensures our test key lands in key1 and is exercised.
local function find_unbound_commands(n)
    local out = {}
    for i = 1, GetNumBindings() do
        local cmd, _, k1, k2 = GetBinding(i)
        if cmd and not k1 and not k2
           and not cmd:match("^HEADER_")
           and not cmd:match("^TYPE_") then
            out[#out + 1] = cmd
            if #out >= n then return out end
        end
    end
    return out
end

T.describe("in-game: key binding round-trip (via WoW API)", function()

    T.it("restores a binding after clearing it", in_game(function()
        local cmds = find_unbound_commands(1)
        if #cmds < 1 then T.skip("no unbound commands available") end
        local CMD = cmds[1]
        local KEY = "CTRL-SHIFT-F12"

        Host.set_binding(KEY, CMD)
        T.assert.equal(CMD, GetBindingAction(KEY))

        local text = MySlot:Export(full_opt())

        Host.set_binding(KEY, nil)
        local cleared = GetBindingAction(KEY)
        T.assert.is_true(cleared == "" or cleared == nil,
            "binding should be cleared before import (got " .. tostring(cleared) .. ")")

        local msg = MySlot:Import(text, { force = true })
        T.assert.not_nil(msg)
        MySlot:RecoverData(msg, recover_opt())

        T.assert.equal(CMD, GetBindingAction(KEY))
    end))

    T.it("restores a binding swapped to a different key", in_game(function()
        local cmds = find_unbound_commands(2)
        if #cmds < 2 then T.skip("need 2 unbound commands, found " .. #cmds) end
        local CMD, OTHER = cmds[1], cmds[2]
        local KEY = "CTRL-SHIFT-F11"

        Host.set_binding(KEY, CMD)
        T.assert.equal(CMD, GetBindingAction(KEY))

        local text = MySlot:Export(full_opt())

        Host.set_binding(KEY, OTHER)
        T.assert.equal(OTHER, GetBindingAction(KEY))

        local msg = MySlot:Import(text, { force = true })
        MySlot:RecoverData(msg, recover_opt())

        T.assert.equal(CMD, GetBindingAction(KEY))
    end))
end)

T.describe("in-game: cooldown manager round-trip (via WoW API)", function()

    T.it("restores the cooldown manager layout and refreshes the live state", in_game(function()
        if not (C_CooldownViewer and C_CooldownViewer.GetLayoutData and C_CooldownViewer.SetLayoutData) then
            T.skip("no cooldown viewer API")
        end
        local original = C_CooldownViewer.GetLayoutData()
        if not original or original == "" then T.skip("no cooldown layout configured") end

        -- Export with cooldown capture enabled; the message must carry the blob.
        local opt = full_opt()
        opt.ignoreCooldownManager = false
        local text = MySlot:Export(opt)
        local msg = MySlot:Import(text, { force = true })
        T.assert.not_nil(msg)
        T.assert.equal(original, msg.cooldownManager)

        -- Reproduce the real scenario: the live Cooldown Manager keeps an in-memory
        -- copy of the layouts in CooldownViewerSettings. Wipe THROUGH that system so
        -- both the datastore and the in-memory layouts/serializer cache become empty.
        local settings = CooldownViewerSettings
        local serializer = settings and settings.GetSerializer and settings:GetSerializer()
        local layoutManager = settings and settings.GetLayoutManager and settings:GetLayoutManager()
        local canInspectLive = serializer and layoutManager
            and serializer.SetSerializedData and serializer.GetSerializedData and serializer.ReadData
            and layoutManager.InitMemberVariables and layoutManager.ClearActiveLayout

        if canInspectLive then
            serializer:SetSerializedData("")
            layoutManager:InitMemberVariables()
            layoutManager:ClearActiveLayout()
            serializer:ReadData()
            T.assert.equal("", C_CooldownViewer.GetLayoutData())
            T.assert.equal("", serializer:GetSerializedData())
        else
            C_CooldownViewer.SetLayoutData("")
        end

        -- RecoverData must restore the datastore AND refresh the live in-memory copy.
        MySlot:RecoverData(msg, { actionOpt = opt })
        T.assert.equal(original, C_CooldownViewer.GetLayoutData())

        if canInspectLive then
            -- A stale serializer cache here would mean ApplyCooldownLayout didn't
            -- reload the live state, so the visible bars would never update and the
            -- next save would clobber the import. The cache must match the datastore.
            T.assert.equal(original, serializer:GetSerializedData())
        end
    end))

    T.it("moves every cooldown to Not Displayed on clear", in_game(function()
        if not (CooldownViewerSettings and CooldownViewerSettings.GetDataProvider and Enum and Enum.CooldownViewerCategory) then
            T.skip("no cooldown viewer settings")
        end
        local dataProvider = CooldownViewerSettings:GetDataProvider()
        if not (dataProvider and dataProvider.GetOrderedCooldownIDsForCategory) then
            T.skip("no cooldown data provider")
        end
        local Cat = Enum.CooldownViewerCategory

        -- Sanity: there is something to hide. If the player has nothing in the
        -- visible categories there's nothing meaningful to assert.
        local before = 0
        for _, c in ipairs({ Cat.Essential, Cat.Utility, Cat.TrackedBuff, Cat.TrackedBar }) do
            before = before + #dataProvider:GetOrderedCooldownIDsForCategory(c, true)
        end
        if before == 0 then T.skip("no visible cooldowns to move") end

        -- The in_game wrapper's snapshot/restore puts the real layout back afterwards.
        MySlot:Clear("COOLDOWNMANAGER")

        -- Every visible category must now be empty (everything is "Not Displayed").
        for _, c in ipairs({ Cat.Essential, Cat.Utility, Cat.TrackedBuff, Cat.TrackedBar }) do
            T.assert.equal(0, #dataProvider:GetOrderedCooldownIDsForCategory(c, true))
        end
    end))
end)

T.describe("in-game: click cast binding round-trip (via WoW API)", function()

    T.it("restores the click cast binding profile after clearing it", in_game(function()
        if not (C_ClickBindings and C_ClickBindings.GetProfileInfo
            and C_ClickBindings.SetProfileByInfo) then
            T.skip("no click bindings API")
        end
        if InCombatLockdown() then T.skip("click bindings are protected in combat") end

        -- The in_game wrapper's snapshot/restore already captures the player's real
        -- click-binding profile (Export/RecoverData round-trip it), so it is put back
        -- afterwards regardless of what this test does.

        local Spell = (Enum and Enum.ClickBindingType and Enum.ClickBindingType.Spell) or 1
        local Interaction = (Enum and Enum.ClickBindingType and Enum.ClickBindingType.Interaction) or 3
        local Target = (Enum and Enum.ClickBindingInteraction and Enum.ClickBindingInteraction.Target) or 1
        local OpenMenu = (Enum and Enum.ClickBindingInteraction and Enum.ClickBindingInteraction.OpenContextMenu) or 2

        -- Find a real click-bindable spell from the player's action bars so we exercise
        -- the spellID path. Fall back to a second distinct interaction if none exists
        -- (distinct actions so neither binding gets collapsed by the profile).
        local second
        if C_ClickBindings.CanSpellBeClickBound then
            for i = 1, 180 do
                local t, id = GetActionInfo(i)
                if t == "spell" and id and C_ClickBindings.CanSpellBeClickBound(id) then
                    second = { type = Spell, actionID = id, button = "Button5", modifiers = 1 }
                    break
                end
            end
        end
        if not second then
            second = { type = Interaction, actionID = OpenMenu, button = "Button5", modifiers = 1 }
        end
        T.log("seed: Button4 interaction/Target +",
            "Button5 type=" .. tostring(second.type) .. " actionID=" .. tostring(second.actionID))

        C_ClickBindings.SetProfileByInfo({
            { type = Interaction, actionID = Target, button = "Button4", modifiers = 0 },
            second,
        })

        local opt = full_opt()
        opt.ignoreClickBindings = false
        local msg = MySlot:Import(MySlot:Export(opt), { force = true })
        T.assert.not_nil(msg)
        for i, c in ipairs(msg.clickBinding) do
            T.log(("exported[%d]: button=%s type=%s actionID=%s modifiers=%s")
                :format(i, tostring(c.button), tostring(c.type), tostring(c.actionID), tostring(c.modifiers)))
        end
        T.assert.equal(2, #msg.clickBinding)

        -- Wipe to an empty profile, then restore from the exported message.
        C_ClickBindings.SetProfileByInfo({})
        T.log("after wipe: profile has " .. #C_ClickBindings.GetProfileInfo() .. " binding(s)")
        T.assert.equal(0, #C_ClickBindings.GetProfileInfo())

        MySlot:RecoverData(msg, { actionOpt = opt })

        local now = C_ClickBindings.GetProfileInfo()
        for i, c in ipairs(now) do
            T.log(("restored[%d]: button=%s type=%s actionID=%s modifiers=%s")
                :format(i, tostring(c.button), tostring(c.type), tostring(c.actionID), tostring(c.modifiers)))
        end
        T.assert.equal(2, #now)
        local byButton = {}
        for _, c in ipairs(now) do byButton[c.button] = c end
        T.assert.not_nil(byButton["Button4"])
        T.assert.not_nil(byButton["Button5"])
        T.assert.equal(Interaction, byButton["Button4"].type)
        T.assert.equal(Target, byButton["Button4"].actionID)
        T.assert.equal(second.type, byButton["Button5"].type)
        T.assert.equal(second.actionID, byButton["Button5"].actionID)
        T.assert.equal(1, byButton["Button5"].modifiers)
    end))
end)
