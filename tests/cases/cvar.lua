local _, MySlot = ...
local T = MySlot.test
local Host = MySlot.host
local Proto = MySlot.luapb.load_proto_ast(MySlot.ast)

local function options(selected)
    local opt = {
        ignoreActionBars = {},
        ignoreMacros = { ACCOUNT = true, CHARACTOR = true },
        ignoreBinding = true,
        ignorePetActionBar = true,
        ignoreCooldownManager = true,
        ignoreClickBindings = true,
        ignoreCVars = selected,
    }
    for i = 1, 15 do opt.ignoreActionBars[i] = true end
    return opt
end

local function ci(fn)
    return function()
        if Host.in_wow then T.skip("CI-only (stub-backed)") end
        local api, info, setter = C_CVar, _G.GetCVarInfo, _G.SetCVar
        Host.reset()
        local ok, err = pcall(fn, _G.WowStub)
        _G.C_CVar, _G.GetCVarInfo, _G.SetCVar = api, info, setter
        if not ok then error(err, 0) end
    end
end

local function seed(stub, name, value, flags)
    flags = flags or {}
    flags.value = value
    stub.cvars[name] = flags
end

local function notices(stub, text)
    for _, msg in ipairs(stub.printed) do
        if msg:find(text, 1, true) then return true end
    end
    return false
end

-- Load the real menu/button code without the unrelated ADDON_LOADED UI panels.
local function gui()
    local file = assert(io.open("gui.lua", "r"))
    local source = file:read("*a")
    file:close()
    local prefix = assert(source:match('^(.-)\nRegEvent%("ADDON_LOADED", function%(%)'))
    local frames = {}
    local function frame()
        local widget = { scripts = {}, enabled = true }
        function widget:SetText(text) self.text = text end
        function widget:GetText() return self.text or "" end
        function widget:SetScript(event, fn) self.scripts[event] = fn end
        function widget:SetPoint(point, relative) self.relative = relative end
        function widget:Enable() self.enabled = true end
        function widget:Disable() self.enabled = false end
        widget.CreateTexture, widget.CreateFontString = frame, frame
        return setmetatable(widget, { __index = function() return function() end end })
    end
    local function description(text, checked, data)
        local node = { text = text, data = data, children = {} }
        if checked then node.checked = function() return checked(data) end end
        function node:CreateCheckbox(label, check, _, args)
            local child = description(label, check, args)
            self.children[#self.children + 1] = child
            return child
        end
        function node:CreateTitle(label)
            self.children[#self.children + 1] = description(label)
        end
        function node:SetResponder(fn) self.respond = fn end
        function node:Find(label)
            for _, child in ipairs(self.children) do
                if child.text == label then return child end
            end
        end
        function node:Click() self.respond(self.data) end
        return node
    end
    local addon = setmetatable({}, { __index = MySlot })
    function addon:RunAsync(fn, progress, done)
        fn()
        done(true)
    end
    local env = {
        StaticPopupDialogs = { MYSLOT_MSGBOX = {} },
        StaticPopup_Show = function() end,
        StaticPopup_Hide = function() end,
        UIDropDownMenu_RefreshAll = function() end,
        time = os.time,
        MyslotExports = { backups = {} },
        MyslotSettings = { allowclearonimport = true },
        CHARACTER_SPECIFIC_MACROS = "Character %s",
        MenuResponse = { Refresh = 1 },
        MenuUtil = {},
        harnessEdit = frame(),
        harnessInfo = { ShowUnsaved = function() end },
        CreateFrame = function()
            local widget = frame()
            frames[#frames + 1] = widget
            return widget
        end,
        tAppendAll = function(dest, src)
            for _, entry in ipairs(src) do dest[#dest + 1] = entry end
        end,
    }
    setmetatable(env, { __index = function(_, key)
        if _G[key] ~= nil then return _G[key] end
        if key:match("^[A-Z_0-9]+$") then return key end
    end })
    function env.MenuUtil.CreateContextMenu(owner, draw)
        env.menu = description()
        draw(owner, env.menu)
    end
    local chunk = assert(loadstring(prefix .. [[
        exportEditbox = harnessEdit
        infolabel = harnessInfo
        return CreateSettingMenu, AllSettingMenuIgnored
    ]], "@gui.lua"))
    setfenv(chunk, env)
    env.addon = addon
    env.createMenu, env.allIgnored = chunk("Myslot", addon)
    for _, widget in ipairs(frames) do
        if widget.text == MySlot.L["Export"] then env.exportButton = widget end
        if widget.text == MySlot.L["Import"] then env.importButton = widget end
    end
    for _, widget in ipairs(frames) do
        if widget.relative == env.exportButton then env.exportArrow = widget end
        if widget.relative == env.importButton then env.importArrow = widget end
    end
    return env
end

T.describe("CVars", function()
    T.it("round-trips names and exact string values", function()
        local msg = Proto.Charactor()
        local entry = Proto.CVar()
        entry.name, entry.value = "statusTextDisplay", "BOTH"
        msg.cvar = { entry }
        local out = Proto.Charactor():Parse(msg:Serialize())
        T.assert.equal("statusTextDisplay", out.cvar[1].name)
        T.assert.equal("BOTH", out.cvar[1].value)
        entry.value = ""
        out = Proto.Charactor():Parse(msg:Serialize())
        T.assert.equal("", out.cvar[1].value)
    end)

    T.it("parses entries missing a name or value without rejecting the profile", function()
        local msg = Proto.Charactor()
        msg.ver, msg.name = 42, "Partial"
        local nameOnly, valueOnly = Proto.CVar(), Proto.CVar()
        nameOnly.name = "autoLootDefault"
        valueOnly.value = "1"
        msg.cvar = { nameOnly, valueOnly }
        local out = Proto.Charactor():Parse(msg:Serialize())
        T.assert.not_nil(out)
        T.assert.equal(42, out.ver)
        T.assert.equal(2, #out.cvar)
        T.assert.equal("autoLootDefault", out.cvar[1].name)
        T.assert.equal(nil, out.cvar[1].value)
        T.assert.equal(nil, out.cvar[2].name)
        T.assert.equal("1", out.cvar[2].value)
    end)

    T.it("keeps legacy protobuf fields and profiles compatible", ci(function(stub)
        seed(stub, "autoLootDefault", "1")
        local legacy = MySlot:Import(MySlot:Export(options(nil)), { force = true })
        T.assert.equal(42, legacy.ver)
        T.assert.equal(nil, legacy.cvar)
        MySlot:RecoverData(legacy, { actionOpt = options(false) })
        T.assert.equal(0, #stub.cvar_writes)
        -- A reader with the pre-CVar schema must ignore the new field.
        local ast = { types = {} }
        for _, node in ipairs(MySlot.ast.types) do
            if node.name ~= "CVar" then
                local copy = {}
                for k, value in pairs(node) do copy[k] = value end
                if node.name == "Charactor" then
                    copy.fields = {}
                    for _, field in ipairs(node.fields) do
                        if field.name ~= "cvar" then
                            copy.fields[#copy.fields + 1] = field
                            copy.fields[field.name] = field
                        end
                    end
                end
                ast.types[#ast.types + 1] = copy
                ast.types[copy.name] = copy
            end
        end
        local old = MySlot.luapb.load_proto_ast(ast)
        local msg = Proto.Charactor()
        msg.ver, msg.name = 42, "Legacy"
        local entry = Proto.CVar()
        entry.name, entry.value = "autoLootDefault", "1"
        msg.cvar = { entry }
        local out = old.Charactor():Parse(msg:Serialize())
        T.assert.equal(42, out.ver)
        T.assert.equal("Legacy", out.name)
        T.assert.equal(nil, rawget(out, ".data").cvar)
    end))

    T.it("exports only explicitly selected CVars, including defaults", ci(function(stub)
        seed(stub, "autoLootDefault", "0", { default = "0" })
        seed(stub, "statusTextDisplay", "BOTH")
        seed(stub, "spellActivationOverlayOpacity", "0.500000")
        for _, opt in ipairs({ options(nil), options(true) }) do
            local msg = MySlot:Import(MySlot:Export(opt), { force = true })
            T.assert.equal(nil, msg.cvar)
        end
        local text = MySlot:Export(options(false))
        local msg = MySlot:Import(text, { force = false })
        T.assert.not_nil(msg, "CVar-only profiles must not be treated as empty")
        T.assert.equal(3, #msg.cvar)
        T.assert.equal("autoLootDefault", msg.cvar[1].name)
        T.assert.equal("0", msg.cvar[1].value)
        T.assert.equal("0.500000", msg.cvar[2].value)
        T.assert.equal("BOTH", msg.cvar[3].value)
        T.assert.same(msg.cvar, MySlot:Import(MySlot:Export(options(false)), {}).cvar)
    end))

    T.it("omits disallowed, absent, and protected CVars on export", ci(function(stub)
        seed(stub, "gxResolution", "1920x1080")
        seed(stub, "Sound_MasterVolume", "0.5")
        seed(stub, "accountName", "not-exported")
        seed(stub, "nameplateUnlistedSetting", "1")
        seed(stub, "autoLootDefault", "1", { locked = true })
        seed(stub, "autoSelfCast", "1", { secure = true })
        seed(stub, "lockActionBars", "1", { readOnly = true })
        seed(stub, "statusTextDisplay", "NUMERIC")
        local entries = MySlot:GetCVars()
        T.assert.equal(1, #entries)
        T.assert.equal("statusTextDisplay", entries[1].name)
    end))

    T.it("ignores missing or explicitly disabled recovery options", ci(function(stub)
        seed(stub, "autoLootDefault", "1")
        local msg = MySlot:Import(MySlot:Export(options(false)), {})
        stub.cvars.autoLootDefault.value = "0"
        MySlot:RecoverData(msg, { actionOpt = options(nil) })
        MySlot:RecoverData(msg, { actionOpt = options(true) })
        T.assert.equal("0", stub.cvars.autoLootDefault.value)
        T.assert.equal(0, #stub.cvar_writes)
        MySlot:RecoverData(msg, { actionOpt = options(false) })
        T.assert.equal("1", stub.cvars.autoLootDefault.value)
        T.assert.equal(1, #stub.cvar_writes)
    end))

    T.it("rechecks destination permissions and reports each skipped entry", ci(function(stub)
        local names = { "autoLootDefault", "autoSelfCast", "lockActionBars", "statusText" }
        local entries = {}
        for _, name in ipairs(names) do
            seed(stub, name, "0")
            entries[#entries + 1] = { name = name, value = "1" }
        end
        stub.cvars.autoLootDefault.locked = true
        stub.cvars.autoSelfCast.secure = true
        stub.cvars.lockActionBars.readOnly = true
        stub.cvars.statusText = nil
        local applied, skipped, failed = MySlot:ApplyCVars(entries)
        T.assert.equal(0, applied)
        T.assert.equal(4, skipped)
        T.assert.equal(0, failed)
        T.assert.equal(0, #stub.cvar_writes)
        for _, name in ipairs(names) do T.assert.is_true(notices(stub, "Skipped CVar " .. name)) end
    end))

    T.it("rejects untrusted names and malformed values and keeps the first duplicate", ci(function(stub)
        seed(stub, "autoLootDefault", "0")
        seed(stub, "autoSelfCast", "0")
        local applied, skipped = MySlot:ApplyCVars({
            { name = "AUTOLOOTDEFAULT", value = "1" },
            { name = "autoLootDefault", value = "0" },
            { name = "autoSelfCast", value = 1 },
            { name = "autoSelfCast", value = "1\0junk" },
            { name = "Sound_MasterVolume", value = "0" },
            { name = "gxResolution", value = "1x1" },
            { name = "accountName", value = "other" },
            { name = "nameplateUnlistedSetting", value = "1" },
            { value = "1" },
            "not an entry",
        })
        T.assert.equal(1, applied)
        T.assert.equal(9, skipped)
        T.assert.equal("1", stub.cvars.autoLootDefault.value)
        T.assert.equal("0", stub.cvars.autoSelfCast.value)
        T.assert.equal(1, #stub.cvar_writes)
        T.assert.is_true(notices(stub, "Duplicate CVar entry"))
    end))

    T.it("imports profiles with incomplete CVar entries and skips only those entries", ci(function(stub)
        Host.set_action(1, "spell", 100)
        seed(stub, "autoLootDefault", "1")
        seed(stub, "autoSelfCast", "1")
        seed(stub, "statusTextDisplay", "BOTH")
        local getCVars = MySlot.GetCVars
        MySlot.GetCVars = function(self)
            local entries = getCVars(self)
            for _, entry in ipairs(entries) do
                if entry.name == "autoSelfCast" then
                    entry.value = nil
                elseif entry.name == "statusTextDisplay" then
                    entry.name = nil
                end
            end
            return entries
        end
        local opt = options(false)
        opt.ignoreActionBars = {}
        local ok, text = pcall(MySlot.Export, MySlot, opt)
        MySlot.GetCVars = getCVars
        if not ok then error(text, 0) end

        local msg = MySlot:Import(text, {})
        T.assert.not_nil(msg, "incomplete CVar entries must not reject the profile")
        T.assert.equal(1, #msg.slot)
        T.assert.equal(1, msg.slot[1].id)
        T.assert.equal(100, msg.slot[1].index)
        T.assert.equal(3, #msg.cvar)

        stub.cvars.autoLootDefault.value = "0"
        stub.cvars.autoSelfCast.value = "0"
        stub.cvars.statusTextDisplay.value = "NONE"
        MySlot:RecoverData(msg, { actionOpt = options(nil) })
        MySlot:RecoverData(msg, { actionOpt = options(true) })
        T.assert.equal(0, #stub.cvar_writes)

        stub.printed = {}
        MySlot:RecoverData(msg, { actionOpt = options(false) })
        T.assert.equal("1", stub.cvars.autoLootDefault.value)
        T.assert.equal("0", stub.cvars.autoSelfCast.value)
        T.assert.equal("NONE", stub.cvars.statusTextDisplay.value)
        T.assert.equal(1, #stub.cvar_writes)
        T.assert.is_true(notices(stub, "Skipped CVar autoSelfCast"))
        T.assert.is_true(notices(stub, "Skipped CVar ?"))
        T.assert.is_true(notices(stub, "CVars: 1 applied, 2 skipped, 0 failed."))
    end))

    T.it("applies coupled presentation CVars in canonical order", ci(function(stub)
        seed(stub, "statusText", "0")
        seed(stub, "statusTextDisplay", "NONE")
        seed(stub, "displaySpellActivationOverlays", "0")
        seed(stub, "spellActivationOverlayOpacity", "0")
        MySlot:ApplyCVars({
            { name = "statusText", value = "1" },
            { name = "displaySpellActivationOverlays", value = "1" },
            { name = "statusTextDisplay", value = "BOTH" },
            { name = "spellActivationOverlayOpacity", value = "0.500000" },
        })
        T.assert.equal("spellActivationOverlayOpacity", stub.cvar_writes[1].name)
        T.assert.equal("displaySpellActivationOverlays", stub.cvar_writes[2].name)
        T.assert.equal("statusTextDisplay", stub.cvar_writes[3].name)
        T.assert.equal("statusText", stub.cvar_writes[4].name)
    end))

    T.it("reports setter errors, false returns, and ineffective writes without stopping", ci(function(stub)
        seed(stub, "autoLootDefault", "0", { write_error = "setter failure" })
        seed(stub, "autoSelfCast", "0", { reject = true })
        seed(stub, "lockActionBars", "0", { ignore_write = true })
        seed(stub, "statusText", "0")
        local applied, skipped, failed = MySlot:ApplyCVars({
            { name = "autoLootDefault", value = "1" },
            { name = "autoSelfCast", value = "1" },
            { name = "lockActionBars", value = "1" },
            { name = "statusText", value = "1" },
        })
        T.assert.equal(1, applied)
        T.assert.equal(0, skipped)
        T.assert.equal(3, failed)
        T.assert.equal("1", stub.cvars.statusText.value)
        T.assert.is_true(notices(stub, "setter failure"))
        T.assert.is_true(notices(stub, "Could not apply CVar autoSelfCast"))
        T.assert.is_true(notices(stub, "Could not apply CVar lockActionBars"))
        T.assert.is_true(notices(stub, "CVars: 1 applied, 0 skipped, 3 failed."))
    end))

    T.it("blocks CVar writes in combat, including combat starting mid-import", ci(function(stub)
        seed(stub, "autoLootDefault", "0")
        seed(stub, "statusText", "0")
        local entries = {
            { name = "autoLootDefault", value = "1" },
            { name = "statusText", value = "1" },
        }
        stub.in_combat = true
        local applied, skipped = MySlot:ApplyCVars(entries)
        T.assert.equal(0, applied)
        T.assert.equal(2, skipped)
        T.assert.equal(0, #stub.cvar_writes)
        T.assert.is_true(notices(stub, "combat"))
        stub.in_combat = false
        local set = C_CVar.SetCVar
        _G.C_CVar = {
            GetCVarInfo = C_CVar.GetCVarInfo,
            SetCVar = function(name, value)
                local result = set(name, value)
                stub.in_combat = true
                return result
            end,
        }
        applied, skipped = MySlot:ApplyCVars(entries)
        T.assert.equal(1, applied)
        T.assert.equal(1, skipped)
        T.assert.equal(1, #stub.cvar_writes)
    end))

    T.it("disables unsupported APIs, accepts absent read-only metadata, and skips missing locked/secure", ci(function(stub)
        seed(stub, "autoLootDefault", "0")
        local entries = { { name = "autoLootDefault", value = "1" } }
        _G.C_CVar = nil
        _G.GetCVarInfo, _G.SetCVar = nil, nil
        T.assert.is_false(MySlot:IsCVarSupported())
        T.assert.equal(nil, MySlot:Export(options(false)))
        local applied, skipped = MySlot:ApplyCVars(entries)
        T.assert.equal(0, applied)
        T.assert.equal(1, skipped)

        local current = "0"
        _G.GetCVarInfo = function() return current, "0", false, false, false, false end
        _G.SetCVar = function(_, value) current = value end
        T.assert.is_true(MySlot:IsCVarSupported())
        local exported = false
        for _, entry in ipairs(MySlot:GetCVars()) do
            if entry.name == "autoLootDefault" and entry.value == "0" then exported = true end
        end
        T.assert.is_true(exported)
        applied, skipped = MySlot:ApplyCVars(entries)
        T.assert.equal(1, applied)
        T.assert.equal(0, skipped)
        T.assert.equal("1", current)

        local cases = {
            function() return "0", "0", false, false, false end,
            function() return "0", "0", false, false, false, true end,
            function() return "0", "0", false, false, false, false, nil end,
        }
        for _, getter in ipairs(cases) do
            local before = #stub.printed
            _G.GetCVarInfo = getter
            _G.SetCVar = function() error("must not set without complete permission metadata") end
            T.assert.equal(0, #MySlot:GetCVars())
            applied, skipped = MySlot:ApplyCVars(entries)
            T.assert.equal(0, applied)
            T.assert.equal(1, skipped)
            local found = false
            for i = before + 1, #stub.printed do
                if stub.printed[i]:find("permissions are unavailable", 1, true) then found = true end
            end
            T.assert.is_true(found)
        end
    end))

    T.it("supports legacy APIs with complete metadata and nil setter returns", ci(function(stub)
        seed(stub, "autoLootDefault", "0")
        local api = C_CVar
        _G.C_CVar = nil
        _G.GetCVarInfo = api.GetCVarInfo
        _G.SetCVar = function(name, value) api.SetCVar(name, value) end
        T.assert.is_true(MySlot:IsCVarSupported())
        local applied = MySlot:ApplyCVars({ { name = "autoLootDefault", value = "1" } })
        T.assert.equal(1, applied)
        T.assert.equal("1", stub.cvars.autoLootDefault.value)
    end))

    T.it("fails selected-category export on read errors and reports import read errors", ci(function(stub)
        seed(stub, "autoLootDefault", "0", { read_error = "read failure" })
        T.assert.equal(nil, MySlot:Export(options(false)))
        T.assert.is_true(notices(stub, "Could not read CVar autoLootDefault"))
        seed(stub, "statusText", "0")
        local applied, skipped = MySlot:ApplyCVars({
            { name = "autoLootDefault", value = "1" },
            { name = "statusText", value = "1" },
        })
        T.assert.equal(1, applied)
        T.assert.equal(1, skipped)
        T.assert.is_true(notices(stub, "read failure"))
    end))

    T.it("restores selected CVars from a pre-import backup", ci(function(stub)
        seed(stub, "autoLootDefault", "1")
        seed(stub, "statusTextDisplay", "BOTH")
        local opt = options(false)
        local profile = MySlot:Import(MySlot:Export(opt), {})
        stub.cvars.autoLootDefault.value = "0"
        stub.cvars.statusTextDisplay.value = "NONE"
        local backup = MySlot:Export(opt)
        MySlot:RecoverData(profile, { actionOpt = opt })
        T.assert.equal("1", stub.cvars.autoLootDefault.value)
        T.assert.equal("BOTH", stub.cvars.statusTextDisplay.value)
        MySlot:RecoverData(MySlot:Import(backup, {}), { actionOpt = opt })
        T.assert.equal("0", stub.cvars.autoLootDefault.value)
        T.assert.equal("NONE", stub.cvars.statusTextDisplay.value)
    end))

    T.it("defaults GUI and slash-load menu options to opt-out", ci(function()
        local ui = gui()
        local opt = options(nil)
        local menu = ui.createMenu(opt)
        T.assert.equal(true, opt.ignoreCVars)
        opt.ignorePetActionBar, opt.ignoreCooldownManager, opt.ignoreClickBindings = true, true, true
        opt.ignoreBindings.KEYBOARD, opt.ignoreBindings.GAMEPAD = true, true
        T.assert.is_true(ui.allIgnored(opt))
        local cvar
        for _, item in ipairs(menu) do
            if item.text == MySlot.L["CVars"] then cvar = item end
        end
        T.assert.not_nil(cvar)
        T.assert.is_true(cvar.checked())
        cvar.func()
        T.assert.equal(false, opt.ignoreCVars)
        T.assert.is_false(ui.allIgnored(opt))
        _G.C_CVar, _G.GetCVarInfo, _G.SetCVar = nil, nil, nil
        for _, item in ipairs(ui.createMenu(options(nil))) do
            T.assert.is_false(item.text == MySlot.L["CVars"])
        end
    end))

    T.it("seeds the import and export menus from saved default IGNORE options", ci(function()
        local ui = gui()
        ui.MyslotSettings.defaultIgnore = {
            import = { ignoreCVars = false, ignoreMacros = { ACCOUNT = true } },
            export = { ignoreCVars = true },
        }
        ui.addon:ApplyIgnoreDefaults("import")
        ui.addon:ApplyIgnoreDefaults("export")

        ui.importArrow.scripts.OnClick(ui.importArrow)
        T.assert.is_false(ui.menu:Find(MySlot.L["CVars"]).checked())
        T.assert.is_true(ui.menu:Find(_G.MACRO or "MACRO").checked())
        ui.exportArrow.scripts.OnClick(ui.exportArrow)
        T.assert.is_true(ui.menu:Find(MySlot.L["CVars"]).checked())
    end))

    T.it("enables CVar-only export through the real export menu and button", ci(function(stub)
        seed(stub, "autoLootDefault", "1")
        local ui = gui()
        ui.exportArrow.scripts.OnClick(ui.exportArrow)
        for _, item in ipairs(ui.menu.children) do
            if item.checked and not item.checked() then item:Click() end
        end
        T.assert.is_false(ui.exportButton.enabled)
        ui.menu:Find(MySlot.L["CVars"]):Click()
        T.assert.is_true(ui.exportButton.enabled)
        ui.exportButton.scripts.OnClick()
        local msg = MySlot:Import(ui.harnessEdit:GetText(), {})
        T.assert.not_nil(msg)
        T.assert.equal(1, #msg.cvar)
        T.assert.equal("autoLootDefault", msg.cvar[1].name)
        T.assert.equal(nil, msg.slot)
        T.assert.equal(nil, msg.bind)
        T.assert.equal(nil, msg.macro)
    end))

    T.it("backs up selected CVars through the real GUI import callback", ci(function(stub)
        seed(stub, "autoLootDefault", "1")
        local text = MySlot:Export(options(false))
        seed(stub, "autoLootDefault", "0")
        local ui = gui()
        ui.harnessEdit:SetText(text)
        ui.importArrow.scripts.OnClick(ui.importArrow)
        local cvar = ui.menu:Find(MySlot.L["CVars"])
        T.assert.is_true(cvar.checked())
        for _, item in ipairs(ui.menu.children) do
            if item == cvar then item:Click(); break end
            if item.checked and not item.checked() then item:Click() end
        end
        local clearHeaders = 0
        for _, item in ipairs(ui.menu.children) do
            if item.text == MySlot.L["CVars"] then clearHeaders = clearHeaders + 1 end
        end
        T.assert.equal(1, clearHeaders, "CVars must not appear in the clear menu")
        ui.importButton.scripts.OnClick()
        ui.StaticPopupDialogs.MYSLOT_MSGBOX.OnAccept()
        T.assert.equal("1", stub.cvars.autoLootDefault.value)
        T.assert.equal(1, #ui.MyslotExports.backups)
        local backup = MySlot:Import(ui.MyslotExports.backups[1].value, {})
        T.assert.equal("0", backup.cvar[1].value)
        MySlot:RecoverData(backup, { actionOpt = options(false) })
        T.assert.equal("0", stub.cvars.autoLootDefault.value)
    end))

    T.it("does not force past a failed selected CVar backup or erase export text", ci(function(stub)
        seed(stub, "autoLootDefault", "1")
        local text = MySlot:Export(options(false))
        seed(stub, "autoLootDefault", "0", { read_error = "backup read failure" })
        local ui = gui()
        ui.harnessEdit:SetText(text)
        ui.importArrow.scripts.OnClick(ui.importArrow)
        ui.menu:Find(MySlot.L["CVars"]):Click()
        ui.menu:Find(MySlot.L["Force Import"]):Click()
        ui.importButton.scripts.OnClick()
        ui.StaticPopupDialogs.MYSLOT_MSGBOX.OnAccept()
        T.assert.equal(0, #stub.cvar_writes)
        T.assert.equal(0, #ui.MyslotExports.backups)
        T.assert.is_true(notices(stub, "Backup failed"))
        ui.exportArrow.scripts.OnClick(ui.exportArrow)
        ui.menu:Find(MySlot.L["CVars"]):Click()
        ui.exportButton.scripts.OnClick()
        T.assert.equal(text, ui.harnessEdit:GetText())
    end))

    T.it("round-trips a real CVar and always restores its original value", function()
        if not Host.in_wow then T.skip("in-game only") end
        if not MySlot:IsCVarSupported() then T.skip("CVar API unavailable") end
        local original
        for _, entry in ipairs(MySlot:GetCVars() or {}) do
            if entry.name == "autoLootDefault" then original = entry.value end
        end
        if original == nil then T.skip("autoLootDefault is not safely writable on this client") end
        local ok, err = T.safe_run(function()
            local opt = options(false)
            local profile = MySlot:Import(MySlot:Export(opt), {})
            T.assert.not_nil(profile)
            local other = original == "1" and "0" or "1"
            T.assert.equal(1, MySlot:ApplyCVars({ { name = "autoLootDefault", value = other } }))
            MySlot:RecoverData(profile, { actionOpt = opt })
            local value = C_CVar and C_CVar.GetCVarInfo or _G.GetCVarInfo
            T.assert.equal(original, value("autoLootDefault"))
        end)
        local restored = MySlot:ApplyCVars({ { name = "autoLootDefault", value = original } })
        T.assert.equal(1, restored, "failed to restore original autoLootDefault")
        if not ok then error(err, 0) end
    end)
end)
