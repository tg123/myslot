-- Macro restore must survive macro index shifts (issue #142).
--
-- WoW keeps account macros (1..MAX_ACCOUNT_MACROS) and character macros
-- (MAX_ACCOUNT_MACROS+1..) sorted by name, so CreateMacro can move existing
-- macros to new indices. Action slots follow the macro, but any index cached
-- before the create now points at a different macro. These CI-only cases
-- emulate that behaviour on top of the WoW stubs and drive RecoverData.

local _, MySlot = ...
local T = MySlot.test
local Host = MySlot.host

if Host.in_wow then return end

local S = _G.WowStub
local MAX_ACCOUNT = Constants.MacroConsts.MAX_ACCOUNT_MACROS
local MAX_CHARACTER = Constants.MacroConsts.MAX_CHARACTER_MACROS

-- Re-sort one macro range by name, keeping action slots attached to the same
-- macro (as the real client does) and returning the new index of `track`.
local function resort(first, last, track)
    local list = {}
    for i = first, last do
        if S.macros[i] then
            list[#list + 1] = { m = S.macros[i], old = i }
            S.macros[i] = nil
        end
    end
    table.sort(list, function(a, b)
        local na, nb = a.m.name:lower(), b.m.name:lower()
        if na == nb then return a.old < b.old end
        return na < nb
    end)

    local remap, tracked = {}, nil
    for n, e in ipairs(list) do
        local id = first + n - 1
        S.macros[id] = e.m
        remap[e.old] = id
        if e.m == track then tracked = id end
    end
    for _, a in pairs(S.action_bars) do
        if a.type == "macro" and remap[a.index] then
            a.index = remap[a.index]
        end
    end
    return tracked
end

local function create_macro(name, icon, body, perCharacter)
    local first = perCharacter and MAX_ACCOUNT + 1 or 1
    local last = perCharacter and MAX_ACCOUNT + MAX_CHARACTER or MAX_ACCOUNT
    local m = { name = name, icon = icon, body = body }
    -- Park it in a free slot, then let resort() move it into name order.
    for i = first, last do
        if not S.macros[i] then
            S.macros[i] = m
            return resort(first, last, m)
        end
    end
end

local function count_macros()
    local g, c = 0, 0
    for i in pairs(S.macros) do
        if i <= MAX_ACCOUNT then g = g + 1 else c = c + 1 end
    end
    return g, c
end

local function with_macro_api(fn)
    local names = { "CreateMacro", "GetNumMacros", "PickupMacro", "PickupAction",
        "PlaceAction", "GetCursorInfo", "ClearCursor", "C_Timer" }
    local saved = {}
    for _, k in ipairs(names) do saved[k] = _G[k] end

    local cursor = nil
    _G.CreateMacro = create_macro
    _G.GetNumMacros = count_macros
    _G.PickupMacro = function(id)
        cursor = S.macros[id] and { type = "macro", index = id } or nil
    end
    _G.PickupAction = function(slot)
        local a = S.action_bars[slot]
        S.action_bars[slot] = nil
        cursor = a and { type = a.type, index = a.index } or nil
    end
    _G.PlaceAction = function(slot)
        if cursor then
            S.action_bars[slot] = { type = cursor.type, index = cursor.index }
            cursor = nil
        end
    end
    _G.GetCursorInfo = function()
        if cursor then return cursor.type, cursor.index end
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
        ignorePetActionBar = true,
        ignoreCooldownManager = true,
    }
end

local function recover_opt()
    local o = export_opt()
    o.ignoreClickBindings = true
    return { actionOpt = o }
end

-- Export from a "source" character whose bars hold the given macros (slot n
-- holds macro n), then wipe state so the caller can seed the target.
local function export_bars(macros)
    for i, m in ipairs(macros) do
        S.macros[i] = { name = m, icon = "INV_MISC_QUESTIONMARK", body = "/say " .. m }
        S.action_bars[i] = { type = "macro", index = i }
    end
    local msg = MySlot:Import(MySlot:Export(export_opt()), { force = true })
    T.assert.not_nil(msg)
    Host.reset()
    return msg
end

local function seed_macro(name)
    return create_macro(name, "INV_MISC_QUESTIONMARK", "/say " .. name)
end

local function macro_on_slot(slot)
    local a = S.action_bars[slot]
    T.assert.not_nil(a, "slot " .. slot .. " is empty")
    T.assert.equal("macro", a.type)
    return S.macros[a.index] and S.macros[a.index].name
end

T.describe("Macro restore across index shifts (issue #142)", function()

    T.it("places existing macros correctly after creating one that sorts before them", function()
        with_macro_api(function()
            local msg = export_bars({ "Alpha", "Zeta" })

            -- Target already has Zeta at index 1; Alpha is missing, so the
            -- import creates it at index 1 and pushes Zeta to index 2.
            seed_macro("Zeta")
            MySlot:RecoverData(msg, recover_opt())

            T.assert.equal("Alpha", macro_on_slot(1))
            T.assert.equal("Zeta", macro_on_slot(2))
        end)
    end)

    T.it("places macros correctly when another addon creates a macro mid-import", function()
        with_macro_api(function()
            local msg = export_bars({ "Alpha", "Zeta" })
            seed_macro("Alpha")
            seed_macro("Zeta")

            -- RecoverData runs across frames; once the first macro is on the
            -- bar, an "other addon" (e.g. Naowh) creates Beta between frames,
            -- shifting Zeta from index 2 to 3.
            local injected = false
            _G.C_Timer = {
                After = function(_, cb)
                    if not injected and S.action_bars[1] then
                        injected = true
                        seed_macro("Beta")
                    end
                    cb()
                end,
            }

            local done
            MySlot:RunAsync(function()
                MySlot:RecoverData(msg, recover_opt())
            end, nil, function(ok) done = ok end)

            T.assert.is_true(injected, "external macro was never injected")
            T.assert.equal(true, done)
            T.assert.equal("Alpha", macro_on_slot(1))
            T.assert.equal("Zeta", macro_on_slot(2))
        end)
    end)
end)
