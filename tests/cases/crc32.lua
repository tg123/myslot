local _, MySlot = ...
local T = MySlot.test
local crc32 = MySlot.crc32

local function bytes(s)
    local r = {}
    for i = 1, #s do r[i] = string.byte(s, i) end
    return r
end

-- crc32.enc returns a signed 32-bit int in luabitop/LuaJIT/WoW bit lib.
-- Normalize to unsigned for comparison with canonical vectors.
local function u32(v)
    if v < 0 then v = v + 2 ^ 32 end
    return v
end

T.describe("crc32", function()
    T.it("matches the canonical IEEE vector for '123456789'", function()
        T.assert.equal(0xCBF43926, u32(crc32.enc(bytes("123456789"))))
    end)

    T.it("produces 0 for empty input", function()
        T.assert.equal(0, u32(crc32.enc({})))
    end)

    T.it("is deterministic", function()
        local a = crc32.enc(bytes("Myslot test payload"))
        local b = crc32.enc(bytes("Myslot test payload"))
        T.assert.equal(a, b)
    end)

    T.it("changes when input changes", function()
        local a = crc32.enc(bytes("Myslot"))
        local b = crc32.enc(bytes("Myslot!"))
        T.assert.is_true(a ~= b)
    end)
end)
