local _, MySlot = ...
local T = MySlot.test
local base64 = MySlot.base64

T.describe("base64", function()
    T.it("round-trips empty input", function()
        local enc = base64.enc({})
        local dec = base64.dec(enc)
        T.assert.equal(0, #dec)
    end)

    T.it("round-trips a byte sequence", function()
        local src = { 0x4d, 0x79, 0x53, 0x6c, 0x6f, 0x74, 0x21 } -- "MySlot!"
        local enc = base64.enc(src)
        local dec = base64.dec(enc)
        T.assert.equal(#src, #dec)
        for i = 1, #src do
            T.assert.equal(src[i], dec[i], "byte " .. i)
        end
    end)

    T.it("round-trips 256 distinct bytes", function()
        local src = {}
        for i = 0, 255 do src[#src + 1] = i end
        local dec = base64.dec(base64.enc(src))
        T.assert.equal(256, #dec)
        for i = 1, 256 do
            T.assert.equal(src[i], dec[i], "byte " .. i)
        end
    end)
end)
