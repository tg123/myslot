local _, MySlot = ...
local T = MySlot.test
local pblua = MySlot.luapb
local _MySlot = pblua.load_proto_ast(MySlot.ast)

T.describe("protobuf Charactor message", function()
    T.it("round-trips a non-trivial payload", function()
        local msg = _MySlot.Charactor()
        msg.ver = 42
        msg.name = "Tester"

        msg.macro = {}
        local m = _MySlot.Macro()
        m.id = 1
        m.icon = "INV_MISC_QUESTIONMARK"
        m.name = "hi"
        m.body = "/say hi"
        msg.macro[1] = m

        msg.slot = {}
        local s = _MySlot.Slot()
        s.id = 1
        s.type = _MySlot.Slot.SlotType.SPELL
        s.index = 12345
        msg.slot[1] = s

        local bytes = msg:Serialize()
        T.assert.is_true(#bytes > 0)

        local out = _MySlot.Charactor():Parse(bytes)
        T.assert.equal(42, out.ver)
        T.assert.equal("Tester", out.name)
        T.assert.equal(1, #out.macro)
        T.assert.equal("hi", out.macro[1].name)
        T.assert.equal("/say hi", out.macro[1].body)
        T.assert.equal(1, #out.slot)
        T.assert.equal(12345, out.slot[1].index)
        T.assert.equal(_MySlot.Slot.SlotType.SPELL, _MySlot.Slot.SlotType[out.slot[1].type])
    end)

    T.it("round-trips string-indexed slot", function()
        local s = _MySlot.Slot()
        s.id = 7
        s.type = _MySlot.Slot.SlotType.SPELL
        s.index = 0
        s.strindex = "ASSISTEDCOMBAT"
        local out = _MySlot.Slot():Parse(s:Serialize())
        T.assert.equal(7, out.id)
        T.assert.equal("ASSISTEDCOMBAT", out.strindex)
    end)

    T.it("round-trips an outfit slot (id + name)", function()
        local s = _MySlot.Slot()
        s.id = 42
        s.type = _MySlot.Slot.SlotType.OUTFIT
        s.index = 1234
        s.strindex = "My Cool Outfit"
        local out = _MySlot.Slot():Parse(s:Serialize())
        T.assert.equal(42, out.id)
        T.assert.equal(1234, out.index)
        T.assert.equal("My Cool Outfit", out.strindex)
        T.assert.equal(_MySlot.Slot.SlotType.OUTFIT, _MySlot.Slot.SlotType[out.type])
    end)

    T.it("round-trips the cooldown manager layout blob", function()
        local msg = _MySlot.Charactor()
        msg.cooldownManager = "1|deadbeefBASE64BLOB=="
        local out = _MySlot.Charactor():Parse(msg:Serialize())
        T.assert.equal("1|deadbeefBASE64BLOB==", out.cooldownManager)
    end)

    T.it("round-trips click cast bindings", function()
        local msg = _MySlot.Charactor()
        msg.clickBinding = {}

        local c1 = _MySlot.ClickBinding()
        c1.type = 1
        c1.actionID = 17116
        c1.button = "BUTTON1"
        c1.modifiers = 1
        msg.clickBinding[1] = c1

        local c2 = _MySlot.ClickBinding()
        c2.type = 2
        c2.actionID = 5
        c2.button = "BUTTON2"
        c2.modifiers = 0
        msg.clickBinding[2] = c2

        local out = _MySlot.Charactor():Parse(msg:Serialize())
        T.assert.equal(2, #out.clickBinding)
        T.assert.equal(1, out.clickBinding[1].type)
        T.assert.equal(17116, out.clickBinding[1].actionID)
        T.assert.equal("BUTTON1", out.clickBinding[1].button)
        T.assert.equal(1, out.clickBinding[1].modifiers)
        T.assert.equal(2, out.clickBinding[2].type)
        T.assert.equal(5, out.clickBinding[2].actionID)
        T.assert.equal("BUTTON2", out.clickBinding[2].button)
    end)
end)
