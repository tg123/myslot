local _, MySlot = ...
local T = MySlot.test
local Host = MySlot.host

local function ci(fn)
    return function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()
        fn(MySlot.guiHarness(MySlot))
    end
end

local CLEAR_TITLE = "|cffff0000" .. MySlot.L["CLEAR"] .. "|r" .. MySlot.L[" before Import"]

T.describe("GUI", function()
    T.it("seeds the CLEAR before Import menu from saved defaults", ci(function(ui)
        local function clearItem(label)
            local seen = false
            for _, child in ipairs(ui.menu.children) do
                if child.text == CLEAR_TITLE then seen = true end
                if seen and child.text == label then return child end
            end
        end
        ui.MyslotSettings.defaultIgnore = { clear = { ignoreMacros = { ACCOUNT = true } } }
        ui.addon:ApplyIgnoreDefaults("clear")
        ui.importArrow.scripts.OnClick(ui.importArrow)
        T.assert.is_true(clearItem(_G.MACRO or "MACRO").checked())
        T.assert.is_false(clearItem(MySlot.L["Key Binding"]).checked())
    end))

    T.it("offers default CLEAR options only when CLEAR before Import is allowed", ci(function(ui)
        local title = (_G.DEFAULT or "DEFAULT") .. ": " .. CLEAR_TITLE
        ui.addon:ShowIgnoreDefaultsMenu("import")
        T.assert.not_nil(ui.menu:Find(title))
        ui.addon:ShowIgnoreDefaultsMenu("export")
        T.assert.equal(nil, ui.menu:Find(title))
        ui.MyslotSettings.allowclearonimport = false
        ui.addon:ShowIgnoreDefaultsMenu("import")
        T.assert.equal(nil, ui.menu:Find(title))
    end))
end)
