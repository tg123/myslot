local ADDONNAME, ADDONSELF = ...

if ADDONNAME == "lua-pb"

    local luapb = ADDONSELF.luapb
    local person = luapb.load_proto_ast(ADDONSELF.pbperson).Person

    SlashCmdList["LUAPBTEST"] = function(msg, editbox)

        local msg0 = person()

        msg0.name = "aa"
        msg0.id = 1

        print("serialize: name " .. msg0.name .. " id " .. msg0.id)

        local t = msg0:Serialize()

        assert(#t > 0, "size of t > 0")

        local msg1 = person()
        msg1:Parse(t)

        assert(msg1.name == msg0.name, "name not equal")
        assert(msg1.id == msg0.id, "id not equal")

        print("deserialize: name " .. msg1.name .. " id " .. msg1.id)

    end
    SLASH_LUAPBTEST1 = "/LUAPBTEST"

end
