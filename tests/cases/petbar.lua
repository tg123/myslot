-- Pet action bar restore must not erase slots (issue #71).
--
-- The client's PickupPetAction lifts an occupied slot onto an empty cursor and
-- swaps when the cursor already holds an action; ClearCursor then drops it.
-- Picking from the pet spellbook (PickupPetSpell / PickupSpellBookItem) puts a
-- copy on the cursor without touching the bar. These CI-only cases emulate
-- that on top of the WoW stubs.

local _, MySlot = ...
local T = MySlot.test
local Host = MySlot.host

if Host.in_wow then return end

-- bar[i] = { token = "PET_ACTION_ATTACK" } or { spell = id } or nil
-- known[spellID] / known[token] = true when the pet spellbook offers it.
local function with_pet_api(bar, known, fn)
    local names = { "IsPetActive", "GetPetActionInfo", "PickupPetAction",
        "PickupPetSpell", "GetCursorInfo", "ClearCursor", "C_SpellBook", "Enum" }
    local book = {}
    for k in pairs(known) do
        if type(k) == "string" then
            book[#book + 1] = k
            names[#names + 1] = k
        end
    end
    local saved = {}
    for _, k in ipairs(names) do saved[k] = _G[k] end

    local cursor = nil
    _G.IsPetActive = function() return true end
    _G.GetPetActionInfo = function(i)
        local a = bar[i]
        if not a then return nil end
        if a.token then return a.token, nil, true end
        return "spell" .. a.spell, nil, false, nil, nil, nil, a.spell
    end
    _G.PickupPetAction = function(i)
        local a = bar[i]
        bar[i] = cursor
        cursor = a
    end
    _G.PickupPetSpell = function(id)
        cursor = known[id] and { spell = id } or nil
    end
    _G.GetCursorInfo = function()
        if cursor then return "petaction", 1 end
    end
    _G.ClearCursor = function() cursor = nil end
    _G.Enum = setmetatable({
        SpellBookSpellBank = { Player = 0, Pet = 1 },
        SpellBookItemType = { Spell = 1, PetAction = 3 },
    }, { __index = saved.Enum })
    for _, token in ipairs(book) do _G[token] = "Label " .. token end
    _G.C_SpellBook = {
        HasPetSpells = function() return #book, "PET" end,
        GetSpellBookItemInfo = function(i, bank)
            if bank ~= 1 or not book[i] then return nil end
            return { itemType = 3, name = _G[book[i]], actionID = i }
        end,
        PickupSpellBookItem = function(i, bank)
            if bank == 1 and book[i] then cursor = { token = book[i] } end
        end,
    }

    Host.reset()
    local ok, err = pcall(fn)
    for _, k in ipairs(names) do _G[k] = saved[k] end
    if not ok then error(err, 0) end
end

local function export_opt()
    return {
        ignoreActionBars = {},
        ignoreMacros = {},
        ignoreBinding = true,
        ignorePetActionBar = false,
        ignoreCooldownManager = true,
    }
end

local function recover_opt()
    local o = export_opt()
    o.ignoreClickBindings = true
    return { actionOpt = o }
end

local function export_pet(bar)
    local msg
    with_pet_api(bar, {}, function()
        msg = MySlot:Import(MySlot:Export(export_opt()), { force = true })
    end)
    T.assert.not_nil(msg)
    return msg
end

T.describe("Pet action bar restore (issue #71)", function()

    T.it("imports a pet-bar-only export without force", function()
        local all = {}
        for i = 1, 15 do all[i] = true end
        local opt = export_opt()
        opt.ignoreActionBars = all
        opt.ignoreMacros = { ACCOUNT = true, CHARACTOR = true }
        local msg
        with_pet_api({ [1] = { token = "PET_ACTION_ATTACK" } }, {}, function()
            msg = MySlot:Import(MySlot:Export(opt), {})
        end)
        T.assert.not_nil(msg, "pet-only export rejected as empty")
    end)

    T.it("keeps slots whose exported spell the current pet does not know", function()
        local msg = export_pet({
            [1] = { token = "PET_ACTION_ATTACK" },
            [4] = { spell = 111 },
            [5] = { spell = 222 },
        })

        local bar = {
            [1] = { token = "PET_ACTION_ATTACK" },
            [4] = { spell = 333 },
            [5] = { spell = 444 },
        }
        with_pet_api(bar, { [222] = true }, function()
            MySlot:RecoverData(msg, recover_opt())
        end)

        T.assert.equal(333, bar[4] and bar[4].spell, "unknown spell erased slot 4")
        T.assert.equal(222, bar[5] and bar[5].spell)
        T.assert.equal("PET_ACTION_ATTACK", bar[1] and bar[1].token)
    end)

    T.it("swaps tokens into place without destroying the displaced action", function()
        local msg = export_pet({
            [1] = { token = "PET_ACTION_FOLLOW" },
            [2] = { token = "PET_ACTION_ATTACK" },
        })

        local bar = {
            [1] = { token = "PET_ACTION_ATTACK" },
            [2] = { token = "PET_ACTION_FOLLOW" },
            [3] = { token = "PET_MODE_ASSIST" },
        }
        with_pet_api(bar, {}, function()
            MySlot:RecoverData(msg, recover_opt())
        end)

        T.assert.equal("PET_ACTION_FOLLOW", bar[1] and bar[1].token)
        T.assert.equal("PET_ACTION_ATTACK", bar[2] and bar[2].token)
        T.assert.equal("PET_MODE_ASSIST", bar[3] and bar[3].token, "empty slot cleared a token")
    end)

    T.it("clears spells under exported empty slots but keeps tokens", function()
        local msg = export_pet({
            [1] = { token = "PET_ACTION_ATTACK" },
        })

        local bar = {
            [1] = { token = "PET_ACTION_ATTACK" },
            [2] = { token = "PET_MODE_ASSIST" },
            [4] = { spell = 333 },
        }
        with_pet_api(bar, {}, function()
            MySlot:RecoverData(msg, recover_opt())
        end)

        T.assert.equal(nil, bar[4], "exported empty slot left a spell in place")
        T.assert.equal("PET_MODE_ASSIST", bar[2] and bar[2].token, "empty slot cleared a token")
        T.assert.equal("PET_ACTION_ATTACK", bar[1] and bar[1].token)
    end)

    -- In-game state from the issue #71 repro: duplicated spells, missing
    -- commands. Import must move rather than copy, and refill commands from
    -- the pet spellbook.
    T.it("moves duplicates into place and restores missing pet commands", function()
        local msg = export_pet({
            [1] = { token = "PET_ACTION_ATTACK" }, [2] = { token = "PET_ACTION_FOLLOW" },
            [3] = { token = "PET_ACTION_MOVE_TO" }, [4] = { spell = 49966 },
            [5] = { spell = 16827 }, [6] = { spell = 2649 }, [7] = { spell = 61684 },
            [8] = { token = "PET_MODE_ASSIST" }, [9] = { token = "PET_MODE_DEFENSIVEASSIST" },
            [10] = { token = "PET_MODE_PASSIVE" },
        })

        local bar = {
            [1] = { token = "PET_ACTION_ATTACK" }, [3] = { spell = 61684 },
            [4] = { spell = 2649 }, [5] = { spell = 61684 }, [6] = { spell = 2649 },
            [10] = { token = "PET_MODE_ASSIST" },
        }
        local known = { [2649] = true, [61684] = true, [17253] = true,
            PET_ACTION_ATTACK = true, PET_ACTION_FOLLOW = true, PET_ACTION_MOVE_TO = true,
            PET_MODE_ASSIST = true, PET_MODE_DEFENSIVEASSIST = true, PET_MODE_PASSIVE = true }
        with_pet_api(bar, known, function()
            MySlot:RecoverData(msg, recover_opt())
        end)

        local function at(i) return bar[i] and (bar[i].token or bar[i].spell) end
        T.assert.equal("PET_ACTION_ATTACK", at(1))
        T.assert.equal("PET_ACTION_FOLLOW", at(2))
        T.assert.equal("PET_ACTION_MOVE_TO", at(3))
        T.assert.equal(2649, at(6))
        T.assert.equal(61684, at(7))
        T.assert.equal("PET_MODE_ASSIST", at(8))
        T.assert.equal("PET_MODE_DEFENSIVEASSIST", at(9))
        T.assert.equal("PET_MODE_PASSIVE", at(10))
        local assists = 0
        for i = 1, 10 do if at(i) == "PET_MODE_ASSIST" then assists = assists + 1 end end
        T.assert.equal(1, assists, "pet command duplicated")
    end)

    local function at(bar, i) return bar[i] and (bar[i].token or bar[i].spell) end

    T.it("moves a spell already on the bar instead of copying it", function()
        local msg = export_pet({ [4] = { spell = 2649 }, [6] = { spell = 49966 } })
        local bar = { [4] = { spell = 61684 }, [6] = { spell = 2649 } }
        with_pet_api(bar, { [2649] = true, [61684] = true }, function()
            MySlot:RecoverData(msg, recover_opt())
        end)
        T.assert.equal(2649, at(bar, 4))
        T.assert.equal(61684, at(bar, 6), "displaced spell should swap into the source slot")
    end)

    T.it("restores a missing pet command from the pet spellbook", function()
        local msg = export_pet({ [2] = { token = "PET_ACTION_FOLLOW" } })
        local bar = {}
        with_pet_api(bar, { PET_ACTION_FOLLOW = true }, function()
            MySlot:RecoverData(msg, recover_opt())
        end)
        T.assert.equal("PET_ACTION_FOLLOW", at(bar, 2))
    end)

    T.it("leaves the slot untouched when a missing command is not in the spellbook", function()
        local msg = export_pet({ [2] = { token = "PET_ACTION_FOLLOW" } })
        local bar = { [2] = { spell = 2649 } }
        with_pet_api(bar, { [2649] = true }, function()
            MySlot:RecoverData(msg, recover_opt())
        end)
        T.assert.equal(2649, at(bar, 2))
    end)

    T.it("parks an action displaced by a spellbook pick into a free slot", function()
        local msg = export_pet({ [1] = { spell = 2649 } })
        local bar = { [1] = { token = "PET_MODE_PASSIVE" } }
        with_pet_api(bar, { [2649] = true }, function()
            MySlot:RecoverData(msg, recover_opt())
        end)
        T.assert.equal(2649, at(bar, 1))
        local found = false
        for i = 2, 10 do
            if at(bar, i) == "PET_MODE_PASSIVE" then found = true end
        end
        T.assert.is_true(found, "displaced pet command was dropped")
    end)

    T.it("keeps a pet command when a full bar leaves nowhere to park it", function()
        local msg = export_pet({ [1] = { spell = 2649 } })
        local bar = { [1] = { token = "PET_MODE_PASSIVE" } }
        for i = 2, 10 do bar[i] = { spell = 1000 + i } end
        with_pet_api(bar, { [2649] = true }, function()
            MySlot:RecoverData(msg, recover_opt())
        end)
        T.assert.equal("PET_MODE_PASSIVE", at(bar, 1), "pet command dropped on a full bar")
    end)

    T.it("clears duplicate spells left in slots exported as empty", function()
        local msg = export_pet({ [4] = { spell = 2649 } })
        local bar = { [4] = { spell = 2649 }, [6] = { spell = 2649 } }
        with_pet_api(bar, { [2649] = true }, function()
            MySlot:RecoverData(msg, recover_opt())
        end)
        T.assert.equal(2649, at(bar, 4))
        T.assert.equal(nil, at(bar, 6))
    end)
end)
