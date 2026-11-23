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

local function clearItem(ui, title, label)
    local seen = false
    for _, child in ipairs(ui.menu.children) do
        if child.text == title then seen = true end
        if seen and child.text == label then return child end
    end
end

T.describe("GUI", function()
    T.it("seeds the CLEAR before Import menu from saved defaults", ci(function(ui)
        ui.MyslotSettings.defaultIgnore = { clear = { ignoreMacros = { ACCOUNT = true } } }
        ui.addon:ApplyIgnoreDefaults("clear")
        ui.importArrow.scripts.OnClick(ui.importArrow)
        T.assert.is_true(clearItem(ui, CLEAR_TITLE, _G.MACRO or "MACRO").checked())
        T.assert.is_false(clearItem(ui, CLEAR_TITLE, MySlot.L["Key Binding"]).checked())
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

    T.it("clears before import only while CLEAR before Import is allowed", ci(function(ui)
        local cleared = {}
        ui.addon.Import = function() return {} end
        ui.addon.IsTalentStringSupported = function() return false end
        ui.addon.Export = function() return "backup" end
        ui.addon.Clear = function(_, what) cleared[#cleared + 1] = what end
        ui.addon.RecoverData = function() end
        ui.MyslotSettings.defaultIgnore = { clear = { ignoreMacros = { ACCOUNT = true } } }
        ui.addon:ApplyIgnoreDefaults("clear")

        ui.MyslotSettings.allowclearonimport = false
        ui.importButton.scripts.OnClick()
        ui.StaticPopupDialogs.MYSLOT_MSGBOX.OnAccept()
        T.assert.equal(0, #cleared)

        ui.MyslotSettings.allowclearonimport = true
        ui.importButton.scripts.OnClick()
        ui.StaticPopupDialogs.MYSLOT_MSGBOX.OnAccept()
        T.assert.is_true(#cleared > 0)
    end))

    T.it("backs up categories selected for CLEAR even when the import ignores them", ci(function(ui)
        local exported, recovered
        ui.addon.Import = function() return {} end
        ui.addon.IsTalentStringSupported = function() return false end
        ui.addon.Export = function(_, opt) exported = opt; return "backup" end
        ui.addon.Clear = function() end
        ui.addon.RecoverData = function(_, _, opt) recovered = opt end
        ui.MyslotSettings.defaultIgnore = {
            import = { ignoreMacros = { ACCOUNT = true } },
            clear = { ignoreMacros = { ACCOUNT = true } },
        }
        ui.addon:ApplyIgnoreDefaults("import")
        ui.addon:ApplyIgnoreDefaults("clear")
        ui.importButton.scripts.OnClick()
        ui.StaticPopupDialogs.MYSLOT_MSGBOX.OnAccept()
        T.assert.is_false(exported.ignoreMacros.ACCOUNT)
        T.assert.is_true(recovered.actionOpt.ignoreMacros.ACCOUNT)
    end))

    T.it("backs up macros referenced by click bindings selected for CLEAR", ci(function(ui)
        local exported, recovered
        ui.addon.Import = function() return {} end
        ui.addon.IsTalentStringSupported = function() return false end
        ui.addon.Export = function(_, opt) exported = opt; return "backup" end
        ui.addon.Clear = function() end
        ui.addon.RecoverData = function(_, _, opt) recovered = opt end
        ui.MyslotSettings.defaultIgnore = {
            import = { ignoreMacros = { ACCOUNT = true, CHARACTOR = true } },
            clear = { ignoreClickBindings = true },
        }
        ui.addon:ApplyIgnoreDefaults("import")
        ui.addon:ApplyIgnoreDefaults("clear")
        ui.importButton.scripts.OnClick()
        ui.StaticPopupDialogs.MYSLOT_MSGBOX.OnAccept()
        T.assert.is_false(exported.ignoreMacros.ACCOUNT)
        T.assert.is_false(exported.ignoreMacros.CHARACTOR)
        T.assert.is_true(recovered.actionOpt.ignoreMacros.ACCOUNT)
        T.assert.is_true(recovered.actionOpt.ignoreMacros.CHARACTOR)
    end))

    T.it("keeps one-off CLEAR selections when an unrelated CLEAR default changes", ci(function(ui)
        local macro = _G.MACRO or "MACRO"
        local account = _G.GENERAL_MACROS or "GENERAL_MACROS"
        ui.MyslotSettings.defaultIgnore = { clear = { ignoreMacros = { ACCOUNT = true } } }
        ui.addon:ApplyIgnoreDefaults("clear")
        ui.importArrow.scripts.OnClick(ui.importArrow)
        clearItem(ui, CLEAR_TITLE, macro):Find(account):Click()
        ui.addon:ShowIgnoreDefaultsMenu("import")
        clearItem(ui, (_G.DEFAULT or "DEFAULT") .. ": " .. CLEAR_TITLE, MySlot.L["Key Binding"])
            :Find(MySlot.L["Keyboard"]):Click()
        ui.importArrow.scripts.OnClick(ui.importArrow)
        T.assert.is_false(clearItem(ui, CLEAR_TITLE, macro):Find(account).checked())
        T.assert.is_true(clearItem(ui, CLEAR_TITLE, MySlot.L["Key Binding"]):Find(MySlot.L["Keyboard"]).checked())
    end))

    T.it("offers the Cooldown Manager CLEAR entry once it becomes supported", function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        Host.reset()
        local supported = false
        local original = MySlot.IsCooldownManagerSupported
        MySlot.IsCooldownManagerSupported = function() return supported end
        local ok, err = pcall(function()
            local ui = MySlot.guiHarness(MySlot)
            ui.importArrow.scripts.OnClick(ui.importArrow)
            T.assert.equal(nil, clearItem(ui, CLEAR_TITLE, MySlot.L["Cooldown Manager"]))
            supported = true
            ui.importArrow.scripts.OnClick(ui.importArrow)
            T.assert.not_nil(clearItem(ui, CLEAR_TITLE, MySlot.L["Cooldown Manager"]))
        end)
        MySlot.IsCooldownManagerSupported = original
        assert(ok, err)
    end)
end)
