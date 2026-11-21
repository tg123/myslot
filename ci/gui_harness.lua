-- CI-only GUI harness shared by test cases (exposed as MySlot.guiHarness).
-- Loads the real menu/button code from gui.lua without the unrelated
-- ADDON_LOADED UI panels, backed by minimal frame and Menu API fakes.

return function(MySlot)
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

    local file = assert(io.open("gui.lua", "r"))
    local source = file:read("*a")
    file:close()
    local prefix = assert(source:match('^(.-)\nRegEvent%("ADDON_LOADED", function%(%)'))

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
