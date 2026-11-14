-- Pet action bar restore must not erase slots (issue #71).
--
-- The client's PickupPetAction lifts an occupied slot onto an empty cursor and
-- swaps when the cursor already holds an action; ClearCursor then drops it.
-- These CI-only cases emulate that on top of the WoW stubs.

local _, MySlot = ...
local T = MySlot.test
local Host = MySlot.host

if Host.in_wow then return end

-- bar[i] = { token = "PET_ACTION_ATTACK" } or { spell = id } or nil
local function with_pet_api(bar, known, fn)
    local names = { "IsPetActive", "GetPetActionInfo", "PickupPetAction",
        "PickupPetSpell", "GetCursorInfo", "ClearCursor" }
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
end)
