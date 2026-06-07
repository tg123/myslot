-- In-game test runner. Registers /myslottest. Loaded only via the packager
-- #@debug@ block in Myslot.toc, so users on Curse/Wago never see this.

local _, MySlot = ...

SLASH_MYSLOTTEST1 = "/myslottest"
SlashCmdList["MYSLOTTEST"] = function()
    if InCombatLockdown() then
        MySlot:Print("|cFFFF6060Myslot tests cannot run in combat|r")
        return
    end
    MySlot:Print("|cFFFFD100Running Myslot tests...|r")
    local _, failed = MySlot.test.run(function(line)
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end)
    if failed == 0 then
        MySlot:Print("|cFF60FF60All tests passed|r")
    else
        MySlot:Print(("|cFFFF6060%d test(s) failed|r"):format(failed))
    end
end
