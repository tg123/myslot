local _, MySlot = ...

local L = MySlot.L
local RegEvent = MySlot.regevent
local MAX_PROFILES_COUNT = 100
local IMPORT_BACKUP_COUNT = 1


local f = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
f:SetWidth(650)
f:SetHeight(600)
f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = {left = 8, right = 8, top = 10, bottom = 10}
})

f:SetBackdropColor(0, 0, 0)
f:SetPoint("CENTER", 0, 0)
f:SetToplevel(true)
f:EnableMouse(true)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetScript("OnKeyDown", function (_, key)
    if key == "ESCAPE" then
        f:Hide()
    end
end)
f:Hide()

MySlot.MainFrame = f

local menuFrame = CreateFrame("Frame", nil, UIParent, "UIDropDownMenuTemplate")

-- title
do
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface/DialogFrame/UI-DialogBox-Header")
    t:SetWidth(256)
    t:SetHeight(64)
    t:SetPoint("TOP", f, 0, 12)
    f.texture = t
end

do
    local t = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetText(L["Myslot"])
    t:SetPoint("TOP", f.texture, 0, -14)
end

local exportEditbox

-- options
do
    local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    b:SetWidth(100)
    b:SetHeight(25)
    b:SetPoint("BOTTOMRIGHT", -145, 15)
    b:SetText(OPTIONS)
    b:SetScript("OnClick", function()
        Settings.OpenToCategory(MySlot.settingcategory.ID)
    end)
end

-- close
do
    local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    b:SetWidth(100)
    b:SetHeight(25)
    b:SetPoint("BOTTOMRIGHT", -40, 15)
    b:SetText(CLOSE)
    b:SetScript("OnClick", function() f:Hide() end)
end

local function CreateSettingMenu(opt)

    local tableref = function (name)
        if name == "action" then
            return opt.ignoreActionBars
        end

        -- if name == "binding" then
        --     return opt.ignoreBindings
        -- end

        if name == "macro" then
            return opt.ignoreMacros
        end
    end

    local childchecked = function (self)
        return tableref(self.arg1)[self.arg2]
    end

    local childclicked = function (self)
        local t = tableref(self.arg1)
        t[self.arg2] = not t[self.arg2]
        UIDropDownMenu_RefreshAll(menuFrame)
    end

    local parentchecked = function (self)
        local t = tableref(self.arg1)
        for _, v in pairs(t) do
            if v then
                return true
            end
        end

        return false
    end

    local parentclicked  = function (self)
        local checkedany = parentchecked(self)
        local t = tableref(self.arg1)

        for i in pairs(t) do
            t[i] = not checkedany
        end

        UIDropDownMenu_RefreshAll(menuFrame)
    end

    opt.ignoreActionBars = opt.ignoreActionBars or {
        [1] = false,
        [2] = false,
        [3] = false,
        [4] = false,
        [5] = false,
        [6] = false,
        [7] = false,
        [8] = false,
        [9] = false,
        [10] = false,
        [11] = false,
        [12] = false,
        [13] = false,
        [14] = false,
        [15] = false,
    }

    opt.ignoreBinding = false
    -- opt.ignoreBindings = opt.ignoreBindings or {}

    opt.ignoreMacros = opt.ignoreMacros or {
        ["ACCOUNT"] = false,
        ["CHARACTOR"] = false,
    }

    opt.ignorePetActionBar = false

    -- https://warcraft.wiki.gg/wiki/Action_slot
    local actionbarlist = {
        {
            text = L["Main Action Bar Page"] .. " 1",
            isNotRadio = true,
            keepShownOnClick = true,
            arg1 = "action",
            arg2 = 1,
            checked = childchecked,
            func = childclicked,
        },
        {
            text = L["Main Action Bar Page"] .. " 2",
            isNotRadio = true,
            keepShownOnClick = true,
            arg1 = "action",
            arg2 = 2,
            checked = childchecked,
            func = childclicked,
        },
        {
            text = OPTION_SHOW_ACTION_BAR:format(2), -- MultiBarBottomLeft
            isNotRadio = true,
            keepShownOnClick = true,
            arg1 = "action",
            arg2 = BOTTOMLEFT_ACTIONBAR_PAGE,
            checked = childchecked,
            func = childclicked,
        },
        {
            text = OPTION_SHOW_ACTION_BAR:format(3), -- MultiBarBottomRight
            isNotRadio = true,
            keepShownOnClick = true,
            arg1 = "action",
            arg2 = BOTTOMRIGHT_ACTIONBAR_PAGE,
            checked = childchecked,
            func = childclicked,
        },
        {
            text = OPTION_SHOW_ACTION_BAR:format(4), -- MultiBarRight
            isNotRadio = true,
            keepShownOnClick = true,
            arg1 = "action",
            arg2 = RIGHT_ACTIONBAR_PAGE,
            checked = childchecked,
            func = childclicked,
        },
        {
            text = OPTION_SHOW_ACTION_BAR:format(5), -- MultiBarLeft
            isNotRadio = true,
            keepShownOnClick = true,
            arg1 = "action",
            arg2 = LEFT_ACTIONBAR_PAGE,
            checked = childchecked,
            func = childclicked,
        },
    }

    if MULTIBAR_5_ACTIONBAR_PAGE then

        table.insert(actionbarlist, {
            text = OPTION_SHOW_ACTION_BAR:format(6),
            isNotRadio = true,
            keepShownOnClick = true,
            arg1 = "action",
            arg2 = MULTIBAR_5_ACTIONBAR_PAGE,
            checked = childchecked,
            func = childclicked,
        })
    end

    if MULTIBAR_6_ACTIONBAR_PAGE then
        table.insert(actionbarlist, {
            text = OPTION_SHOW_ACTION_BAR:format(7),
            isNotRadio = true,
            keepShownOnClick = true,
            arg1 = "action",
            arg2 = MULTIBAR_6_ACTIONBAR_PAGE,
            checked = childchecked,
            func = childclicked,
        })
    end

    if  MULTIBAR_7_ACTIONBAR_PAGE then
        table.insert(actionbarlist, {
            text = OPTION_SHOW_ACTION_BAR:format(8),
            isNotRadio = true,
            keepShownOnClick = true,
            arg1 = "action",
            arg2 = MULTIBAR_7_ACTIONBAR_PAGE,
            checked = childchecked,
            func = childclicked,
        })
    end

    -- 10.0
    if select(4, GetBuildInfo()) > 100000 then
        table.insert(actionbarlist, {
            text = L["Skyriding Bar"],
            isNotRadio = true,
            keepShownOnClick = true,
            arg1 = "action",
            arg2 = 11,
            checked = childchecked,
            func = childclicked,
        })        
    end

    for i = 1, 4 do

        -- local _, _, _, spell = GetShapeshiftFormInfo(i)
        -- TODO better name

        -- if spell then
        table.insert(actionbarlist, {
            text = L["Stance Action Bar"] .. " " .. i,
            isNotRadio = true,
            keepShownOnClick = true,
            arg1 = "action",
            arg2 = 6 + i,
            checked = childchecked,
            func = childclicked,
        })
        -- end
    end

    return {
        {
            text = ACTIONBARS_LABEL,
            hasArrow = true,
            notCheckable = false,
            isNotRadio = true,
            keepShownOnClick = true,
            menuList = actionbarlist,
            func = parentclicked,
            checked = parentchecked,
            arg1 = "action",
        }, -- 1
        {
            text = L["Key Binding"],
            notCheckable = false,
            isNotRadio = true,
            keepShownOnClick = true,
            func = function ()
                opt.ignoreBinding = not opt.ignoreBinding
            end,
            checked = function ()
                return opt.ignoreBinding
            end,
        }, -- 2
        {
            text = MACRO,
            hasArrow = true,
            notCheckable = false,
            isNotRadio = true,
            keepShownOnClick = true,
            func = parentclicked,
            checked = parentchecked,
            arg1 = "macro",
            menuList = {
                {
                    text = GENERAL_MACROS,
                    isNotRadio = true,
                    keepShownOnClick = true,
                    arg1 = "macro",
                    arg2 = "ACCOUNT",
                    checked = childchecked,
                    func = childclicked,
                },
                {
                    text = CHARACTER_SPECIFIC_MACROS:format(""),
                    isNotRadio = true,
                    keepShownOnClick = true,
                    arg1 = "macro",
                    arg2 = "CHARACTOR",
                    checked = childchecked,
                    func = childclicked,
                },
            }
        }, -- 3
        {
            text = PET .. " " .. ACTIONBARS_LABEL,
            notCheckable = false,
            isNotRadio = true,
            keepShownOnClick = true,
            func = function ()
                opt.ignorePetActionBar = not opt.ignorePetActionBar
            end,
            checked = function ()
                return opt.ignorePetActionBar
            end,
        }, -- 4
    }
end

local function DrawMenu(root, menuData)
    for _, m in ipairs(menuData) do
        if m.isTitle then
            root:CreateTitle(m.text)
        else
            local c = root:CreateCheckbox(m.text, m.checked, function ()

            end, {
                arg1 = m.arg1,
                arg2 = m.arg2,
            })
            c:SetResponder(function(data, menuInputData, menu)
                m.func({
                    arg1 = m.arg1,
                    arg2 = m.arg2,
                })
                -- Your handler here...
                return MenuResponse.Refresh;
            end)

            if m.menuList then
                DrawMenu(c, m.menuList)
            end
        end
    end

end

local EasyMenu = _G.EasyMenu or function (settings)
    MenuUtil.CreateContextMenu(UIParent, function(ownerRegion, rootDescription)
        DrawMenu(rootDescription, settings)
    end)
end

-- import
do

    local actionOpt = {}
    local clearOpt  = {}
    local forceImport = false

    local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    b:SetWidth(125)
    b:SetHeight(25)
    b:SetPoint("BOTTOMLEFT", 200, 15)
    b:SetText(L["Import"])
    b:SetScript("OnClick", function()
        local msg = MySlot:Import(exportEditbox:GetText(), {
            force = forceImport,
        })

        if not msg then
            return
        end

        StaticPopupDialogs["MYSLOT_MSGBOX"].OnAccept = function()
            StaticPopup_Hide("MYSLOT_MSGBOX")

            MySlot:Print(L["Starting backup..."])
            local backup = MySlot:Export(actionOpt)

            if not backup then
                MySlot:Print(L["Backup failed"])

                if not forceImport then
                    return
                end
            end

            table.insert(MyslotExports["backups"], backup)
            while #MyslotExports["backups"] > IMPORT_BACKUP_COUNT do
                table.remove(MyslotExports["backups"], 1)
            end

            MySlot:Clear("MACRO", clearOpt.ignoreMacros)
            MySlot:Clear("ACTION", clearOpt.ignoreActionBars)
            if clearOpt.ignoreBinding then
                MySlot:Clear("BINDING")
            end

            MySlot:RecoverData(msg, {
                actionOpt = actionOpt,
                clearOpt = clearOpt,
            })
        end
        StaticPopup_Show("MYSLOT_MSGBOX")
    end)

    local ba = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    ba:SetWidth(25)
    ba:SetHeight(25)
    ba:SetPoint("LEFT", b, "RIGHT", 0, 0)
    ba:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    do
        local icon = ba:CreateTexture(nil, 'ARTWORK')
        icon:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        icon:SetPoint('CENTER', 1, 0)
        icon:SetSize(16, 16)
    end

    local settings = {
        {
            isTitle = true,
            text = "|cffff0000" .. L["IGNORE"] .. "|r" .. L[" during Import"],
            notCheckable = true,
        }
    }

    tAppendAll(settings, CreateSettingMenu(actionOpt))

    local clearbegin = #settings + 1
    tAppendAll(settings, {
        {
            isTitle = true,
            text = "|cffff0000" .. L["CLEAR"] .. "|r" .. L[" before Import"],
            notCheckable = true,
        }
    })
    tAppendAll(settings, CreateSettingMenu(clearOpt))

    table.remove(settings) -- remove pet action bar clearOpt, will support it later
    local clearend = #settings

    tAppendAll(settings, {
        {
            isTitle = true,
            text = OTHER,
            notCheckable = true,
        },
        {
            text = L["Force Import"],
            isNotRadio = true,
            keepShownOnClick = true,
            checked = function()
                return forceImport
            end,
            func = function()
                forceImport = not forceImport
            end
        }
    })

    local settingswithoutclear = {}
    tAppendAll(settingswithoutclear, settings)
    for i = clearend, clearbegin, -1 do
        table.remove(settingswithoutclear, i)
    end


    ba:SetScript("OnClick", function(self, button)
        EasyMenu(MyslotSettings.allowclearonimport and settings or settingswithoutclear, menuFrame, "cursor", 0 , 0, "MENU");
    end)
end

local infolabel


-- export
do
    local actionOpt = {}

    local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    b:SetWidth(125)
    b:SetHeight(25)
    b:SetPoint("BOTTOMLEFT", 40, 15)
    b:SetText(L["Export"])
    b:SetScript("OnClick", function()
        local s = MySlot:Export(actionOpt)
        exportEditbox:SetText(s)
        infolabel.ShowUnsaved()
    end)

    local ba = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    ba:SetWidth(25)
    ba:SetHeight(25)
    ba:SetPoint("LEFT", b, "RIGHT", 0, 0)
    ba:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    do
        local icon = ba:CreateTexture(nil, 'ARTWORK')
        icon:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        icon:SetPoint('CENTER', 1, 0)
        icon:SetSize(16, 16)
    end

    local settings = {
        {
            isTitle = true,
            text = "|cffff0000" .. L["IGNORE"] .. "|r" .. L[" during Export"],
            notCheckable = true,
        }
    }

    tAppendAll(settings, CreateSettingMenu(actionOpt))

    ba:SetScript("OnClick", function(self, button)
        EasyMenu(settings, menuFrame, "cursor", 0 , 0, "MENU");
    end)
end

RegEvent("ADDON_LOADED", function()
    do
        local t = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
        t:SetWidth(600)
        t:SetHeight(455)
        t:SetPoint("TOPLEFT", f, 25, -75)
        t:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileEdge = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = -2, right = -2, top = -2, bottom = -2 },
        })
        t:SetBackdropColor(0, 0, 0, 0)

        local s = CreateFrame("ScrollFrame", nil, t, "UIPanelScrollFrameTemplate")
        s:SetWidth(560)
        s:SetHeight(440)
        s:SetPoint("TOPLEFT", 10, -10)


        local edit = CreateFrame("EditBox", nil, s)
        s.cursorOffset = 0
        edit:SetWidth(550)
        s:SetScrollChild(edit)
        edit:SetAutoFocus(false)
        edit:EnableMouse(true)
        edit:SetMaxLetters(99999999)
        edit:SetMultiLine(true)
        edit:SetFontObject(GameTooltipText)
        edit:SetScript("OnEscapePressed", edit.ClearFocus)
        edit:SetScript("OnMouseUp", function()
            edit:HighlightText(0, -1)
        end)

        -- edit:SetScript("OnTextChanged", function()
        --     infolabel:SetText(L["Unsaved"])
        -- end)
        edit:SetScript("OnTextSet", function()
            edit.savedtxt = edit:GetText()
            infolabel:SetText("")
        end)
        edit:SetScript("OnChar", function(self, c)
            infolabel.ShowUnsaved()
        end)

        t:SetScript("OnMouseDown", function()
            edit:SetFocus()
        end)

        exportEditbox = edit
    end


    do
        local t = CreateFrame("Frame", nil, f, "UIDropDownMenuTemplate")
        t:SetPoint("TOPLEFT", f, 5, -45)
        UIDropDownMenu_SetWidth(t, 200)
        do
            local tt = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            tt:SetPoint("BOTTOMLEFT", t, "TOPLEFT", 20, 0)

            tt.ShowUnsaved = function()
                tt:SetText(YELLOW_FONT_COLOR:WrapTextInColorCode(L["Unsaved"]))
            end

            infolabel = tt
        end

        if not MyslotExports then
            MyslotExports = {}
        end
        if not MyslotExports["exports"] then
            MyslotExports["exports"] = {}
        end
        if not MyslotExports["backups"] then
            MyslotExports["backups"] = {}
        end
        local exports = MyslotExports["exports"]
        local backups = MyslotExports["backups"]

        local onclick = function(self)
            local idx = self.value
            UIDropDownMenu_SetSelectedValue(t, idx)

            local n = exports[idx] and exports[idx].name or ""
            UIDropDownMenu_SetText(t, n)

            local v = exports[idx] and exports[idx].value or ""
            exportEditbox:SetText(v)
        end

        local create = function(name)
            if #exports > MAX_PROFILES_COUNT then
                MySlot:Print(L["Too many profiles, please delete before create new one."])
                return
            end

            local txt = {
                name = name
            }
            table.insert(exports, txt)

            local info = UIDropDownMenu_CreateInfo()
            info.text = txt.name
            info.value = #exports
            info.func = onclick
            UIDropDownMenu_AddButton(info)

            return true
        end

        local save = function(force)
            local c = UIDropDownMenu_GetSelectedValue(t)
            local v = exportEditbox:GetText()
            if not force and v == "" then
                return
            end
            if (not c) or (not exports[c]) then
                local n = date()
                if not create(n) then
                    return
                end
                UIDropDownMenu_SetSelectedValue(t, #exports)
                UIDropDownMenu_SetText(t, n)
                c = #exports
            end

            exports[c].value = v
            infolabel:SetText("")
        end
        -- exportEditbox:SetScript("OnTextChanged", function() save(false) end)

        UIDropDownMenu_Initialize(t, function()
            local info = UIDropDownMenu_CreateInfo()
            info.text = L["Before Last Import"]
            info.customCheckIconTexture = "Interface\\Icons\\inv_scroll_04"
            info.func = function()
                local b = backups[1] -- only 1 backup now, will support more later
                if b then
                    exportEditbox:SetText(b)
                    infolabel:SetText("")
                    UIDropDownMenu_SetText(t, "")
                end
            end
            UIDropDownMenu_AddButton(info)

            for i, txt in pairs(exports) do
                -- print(txt.name)
                local info = UIDropDownMenu_CreateInfo()
                info.text = txt.name
                info.value = i
                info.func = onclick
                info.customCheckIconTexture = "Interface\\Icons\\inv_scroll_03"
                UIDropDownMenu_AddButton(info)
            end
        end)

        local popctx = {}

        StaticPopupDialogs["MYSLOT_EXPORT_TITLE"].OnShow = function(self)
            local c = popctx.current

            if c and exports[c] then
                self.editBox:SetText(exports[c].name or "")
            end
            self.editBox:SetFocus()
        end


        StaticPopupDialogs["MYSLOT_EXPORT_TITLE"].OnAccept = function(self)
            local c = popctx.current

            -- if c then rename
            if c and exports[c] then
                local n = self.editBox:GetText()
                if n ~= "" then
                    exports[c].name = n
                    UIDropDownMenu_SetText(t, n)
                end
                return
            end

            if create(self.editBox:GetText()) then
                onclick({value = #exports})
            end
        end

        do
            local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
            b:SetWidth(70)
            b:SetHeight(25)
            b:SetPoint("TOPLEFT", t, 240, 0)
            b:SetText(NEW)
            b:SetScript("OnClick", function()
                popctx.current = nil
                StaticPopup_Show("MYSLOT_EXPORT_TITLE")
            end)
        end

        do
            local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
            b:SetWidth(70)
            b:SetHeight(25)
            b:SetPoint("TOPLEFT", t, 315, 0)
            b:SetText(SAVE)
            b:SetScript("OnClick", function() save(true) end)
        end

        do
            local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
            b:SetWidth(70)
            b:SetHeight(25)
            b:SetPoint("TOPLEFT", t, 390, 0)
            b:SetText(DELETE)
            b:SetScript("OnClick", function()
                local c = UIDropDownMenu_GetSelectedValue(t)

                if c then
                    StaticPopupDialogs["MYSLOT_CONFIRM_DELETE"].OnAccept = function()
                        StaticPopup_Hide("MYSLOT_CONFIRM_DELETE")
                        table.remove(exports, c)

                        if #exports == 0 then
                            UIDropDownMenu_SetSelectedValue(t, nil)
                            UIDropDownMenu_SetText(t, "")
                            exportEditbox:SetText("")
                        else
                            onclick({value = #exports})
                        end
                    end
                    StaticPopup_Show("MYSLOT_CONFIRM_DELETE", exports[c].name)
                end
            end)
        end

        do
            local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
            b:SetWidth(70)
            b:SetHeight(25)
            b:SetPoint("TOPLEFT", t, 465, 0)
            b:SetText(L["Rename"])
            b:SetScript("OnClick", function()
                local c = UIDropDownMenu_GetSelectedValue(t)

                if c and exports[c] then
                    popctx.current = c
                    StaticPopup_Show("MYSLOT_EXPORT_TITLE")
                end
            end)
        end

    end

end)

RegEvent("ADDON_LOADED", function()
    local ldb = LibStub("LibDataBroker-1.1")
    local icon = LibStub("LibDBIcon-1.0")

    MyslotSettings = MyslotSettings or {}
    MyslotSettings.minimap = MyslotSettings.minimap or { hide = false }
    local config = MyslotSettings.minimap

    icon:Register("Myslot", ldb:NewDataObject("Myslot", {
            icon = "Interface\\MacroFrame\\MacroFrame-Icon",
            OnClick = function()
                f:SetShown(not f:IsShown())
            end,
            OnTooltipShow = function(tooltip)
                tooltip:AddLine(L["Myslot"])
            end,
        }), config)


    local lib = LibStub:NewLibrary("Myslot-5.0", 1)

    if lib then
        lib.MainFrame = MySlot.MainFrame
    end

end)

SlashCmdList["MYSLOT"] = function(msg, editbox)
    local cmd, what = msg:match("^(%S*)%s*(%S*)%s*$")

    if cmd == "load" then

        if not MyslotExports then
            MyslotExports = {}
        end
        if not MyslotExports["exports"] then
            MyslotExports["exports"] = {}
        end
        local exports = MyslotExports["exports"]
        local profileString = ""

        for i, profile in ipairs(exports) do

            if profile.name == what then
                MySlot:Print(L["Profile to load found : " .. profile.name])
                profileString = profile.value
            end
        end

        if profileString == "" then
            MySlot:Print(L["No profile found with name " .. what])
        else
            local msg = MySlot:Import(profileString, { force = false })

            if not msg then
                return
            end

            local opt = {}
            CreateSettingMenu(opt)

            MySlot:RecoverData(msg, {
                actionOpt = opt,
                clearOpt = opt,
            })
        end

    elseif cmd == "clear" then
        Settings.OpenToCategory(MySlot.settingcategory.ID)
    elseif cmd == "trim" then
        if not MyslotExports then
            MyslotExports = {}
        end
        if not MyslotExports["exports"] then
            MyslotExports["exports"] = {}
        end
        local exports = MyslotExports["exports"]
        local n = tonumber(what) or MAX_PROFILES_COUNT
        n = math.max(n, 0)
        while #exports > n do
            table.remove(exports, 1)
        end
        C_UI.Reload()
    else
        f:Show()
    end
end
SLASH_MYSLOT1 = "/MYSLOT"

StaticPopupDialogs["MYSLOT_MSGBOX"] = {
    text = L["Are you SURE to import ?"],
    button1 = ACCEPT,
    button2 = CANCEL,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    multiple = 0,
}

StaticPopupDialogs["MYSLOT_EXPORT_TITLE"] = {
    text = L["Name of exported text"],
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    multiple = 0,
    OnAccept = function()
    end,
    OnShow = function()
    end,
}

StaticPopupDialogs["MYSLOT_CONFIRM_DELETE"] = {
    text = L["Are you SURE to delete '%s'?"],
    button1 = ACCEPT,
    button2 = CANCEL,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    multiple = 0,
}
