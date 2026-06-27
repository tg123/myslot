local _, MySlot = ...

local L = MySlot.L
local RegEvent = MySlot.regevent
local MAX_PROFILES_COUNT = 100
local IMPORT_BACKUP_COUNT = 3


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

-- {{{ Import progress bar
-- Shown while a large profile is restored. RecoverData now runs across frames
-- (MySlot:RunAsync) so it can't trip the "script ran too long" watchdog on big
-- profiles (notably WoW Classic Era 1.15, which has a stricter script budget).
local progressFrame = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
progressFrame:SetSize(360, 70)
progressFrame:SetPoint("CENTER", 0, 0)
progressFrame:SetFrameStrata("FULLSCREEN_DIALOG")
progressFrame:SetToplevel(true)
progressFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = {left = 8, right = 8, top = 8, bottom = 8}
})
progressFrame:SetBackdropColor(0, 0, 0)
progressFrame:Hide()

local progressText = progressFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
progressText:SetPoint("TOP", 0, -14)

local progressBar = CreateFrame("StatusBar", nil, progressFrame)
progressBar:SetSize(320, 18)
progressBar:SetPoint("BOTTOM", 0, 16)
progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
progressBar:SetStatusBarColor(0.2, 0.6, 1.0)
progressBar:SetMinMaxValues(0, 1)
progressBar:SetValue(0)

local progressBg = progressBar:CreateTexture(nil, "BACKGROUND")
progressBg:SetAllPoints(progressBar)
progressBg:SetColorTexture(0, 0, 0, 0.6)

local function ShowImportProgress()
    progressBar:SetValue(0)
    progressText:SetText(L["Importing..."])
    progressFrame:Show()
end

local function SetImportProgress(frac)
    frac = frac or 0
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    progressBar:SetValue(frac)
    progressText:SetText(("%s %d%%"):format(L["Importing..."], math.floor(frac * 100 + 0.5)))
end

local function HideImportProgress(ok)
    progressFrame:Hide()
    if ok == false then
        MySlot:Print(L["Import failed"])
    end
end
-- }}}

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

local function CreateSettingMenu(opt, onChanged)

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

        if onChanged then
            onChanged()
        end
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

        if onChanged then
            onChanged()
        end
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

    opt.ignoreCooldownManager = false

    opt.ignoreClickBindings = false

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

    local menu = {
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

                if onChanged then
                    onChanged()
                end
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

                if onChanged then
                    onChanged()
                end
            end,
            checked = function ()
                return opt.ignorePetActionBar
            end,
        }, -- 4
        {
            text = L["Cooldown Manager"],
            notCheckable = false,
            isNotRadio = true,
            keepShownOnClick = true,
            func = function ()
                opt.ignoreCooldownManager = not opt.ignoreCooldownManager

                if onChanged then
                    onChanged()
                end
            end,
            checked = function ()
                return opt.ignoreCooldownManager
            end,
        }, -- 5
        {
            text = L["Click Cast Bindings"],
            notCheckable = false,
            isNotRadio = true,
            keepShownOnClick = true,
            func = function ()
                opt.ignoreClickBindings = not opt.ignoreClickBindings

                if onChanged then
                    onChanged()
                end
            end,
            checked = function ()
                return opt.ignoreClickBindings
            end,
        }, -- 6
    }

    -- Some categories are retail-only; drop their entries where the client
    -- doesn't support them (e.g. Classic) so we never offer an option that
    -- can't apply.
    local unsupported = {}
    if not MySlot:IsCooldownManagerSupported() then
        unsupported[L["Cooldown Manager"]] = true
    end
    if not MySlot:IsClickBindingSupported() then
        unsupported[L["Click Cast Bindings"]] = true
    end
    if not MySlot:IsPetActionBarSupported() then
        unsupported[PET .. " " .. ACTIONBARS_LABEL] = true
    end
    for i = #menu, 1, -1 do
        if menu[i].text and unsupported[menu[i].text] then
            table.remove(menu, i)
        end
    end

    return menu
end

local function AllSettingMenuIgnored(opt)
    if not opt then
        return false
    end

    if not opt.ignoreActionBars then
        return false
    end
    for _, v in pairs(opt.ignoreActionBars) do
        if not v then
            return false
        end
    end

    if not opt.ignoreBinding then
        return false
    end

    if not opt.ignoreMacros then
        return false
    end
    for _, v in pairs(opt.ignoreMacros) do
        if not v then
            return false
        end
    end

    if MySlot:IsPetActionBarSupported() and not opt.ignorePetActionBar then
        return false
    end

    if MySlot:IsCooldownManagerSupported() and not opt.ignoreCooldownManager then
        return false
    end

    if MySlot:IsClickBindingSupported() and not opt.ignoreClickBindings then
        return false
    end

    return true
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

-- Always use the modern Menu API (Blizzard_Menu ships on every flavor, 1.x ->
-- retail), so the import/export popups match the loadout dropdown's look.
local EasyMenu = function (settings, owner)
    MenuUtil.CreateContextMenu(owner or UIParent, function(ownerRegion, rootDescription)
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

            table.insert(MyslotExports["backups"], { value = backup, time = time() })
            while #MyslotExports["backups"] > IMPORT_BACKUP_COUNT do
                table.remove(MyslotExports["backups"], 1)
            end

            MySlot:Clear("MACRO", clearOpt.ignoreMacros)
            MySlot:Clear("ACTION", clearOpt.ignoreActionBars)
            if clearOpt.ignoreBinding then
                MySlot:Clear("BINDING")
            end
            if clearOpt.removeCooldownManager then
                MySlot:Clear("COOLDOWNMANAGER")
            end
            if clearOpt.ignoreClickBindings then
                MySlot:Clear("CLICKBINDING")
            end

            ShowImportProgress()
            MySlot:RunAsync(function()
                MySlot:RecoverData(msg, {
                    actionOpt = actionOpt,
                    clearOpt = clearOpt,
                })
            end, SetImportProgress, HideImportProgress)
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
    -- Pet Action Bar and Cooldown Manager have no per-category clear here (pet
    -- isn't supported yet; cooldown is offered as an explicit "Remove all" below),
    -- so drop them by identity rather than by position to stay robust against any
    -- future change to CreateSettingMenu's entry order.
    local clearMenu = CreateSettingMenu(clearOpt)
    local clearExcludedText = {
        [PET .. " " .. ACTIONBARS_LABEL] = true,
        [L["Cooldown Manager"]] = true,
    }
    for i = #clearMenu, 1, -1 do
        if clearMenu[i].text and clearExcludedText[clearMenu[i].text] then
            table.remove(clearMenu, i)
        end
    end
    tAppendAll(settings, clearMenu)

    -- Cooldown Manager "remove all" only makes sense on clients that have it.
    if MySlot:IsCooldownManagerSupported() then
        tAppendAll(settings, {
            {
                text = L["Cooldown Manager"],
                notCheckable = false,
                isNotRadio = true,
                keepShownOnClick = true,
                func = function ()
                    clearOpt.removeCooldownManager = not clearOpt.removeCooldownManager
                end,
                checked = function ()
                    return clearOpt.removeCooldownManager
                end,
            },
        })
    end

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
        EasyMenu(MyslotSettings.allowclearonimport and settings or settingswithoutclear, self);
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

    local function UpdateExportButtonState()
        if AllSettingMenuIgnored(actionOpt) then
            b:Disable()
        else
            b:Enable()
        end
    end

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

    tAppendAll(settings, CreateSettingMenu(actionOpt, UpdateExportButtonState))

    UpdateExportButtonState()

    ba:SetScript("OnClick", function(self, button)
        EasyMenu(settings, self);
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
        -- Gold "binding button" look (UIMenuButtonStretchTemplate, the same family
        -- as the keybinding selector). The menu itself is opened via
        -- MenuUtil.CreateContextMenu on click, so its border matches the
        -- import/export popups exactly.
        local t = CreateFrame("Button", nil, f, "UIMenuButtonStretchTemplate")
        t:SetPoint("TOPLEFT", f, 25, -45)
        t:SetSize(240, 26)

        -- Scroll icon on the left, downward dropdown arrow on the right.
        do
            local icon = t:CreateTexture(nil, "OVERLAY")
            icon:SetTexture("Interface\\Icons\\inv_scroll_03")
            icon:SetSize(18, 18)
            icon:SetPoint("LEFT", t, "LEFT", 6, 0)

            local arrow = t:CreateTexture(nil, "OVERLAY")
            arrow:SetPoint("RIGHT", t, "RIGHT", -6, 0)
            local atlas
            for _, name in ipairs({ "common-dropdown-classic-a-buttonDown", "common-dropdown-a-buttonDown" }) do
                if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) then
                    atlas = name
                    break
                end
            end
            if atlas then
                arrow:SetAtlas(atlas)
                arrow:SetSize(16, 16)
            else
                -- Rotate the right-pointing expand arrow to point down.
                arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
                arrow:SetSize(16, 16)
                arrow:SetRotation(-math.pi / 2)
            end
        end

        -- This template ships no text region, so add a left-aligned label of our
        -- own, sitting between the scroll icon and the arrow.
        local label = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", t, "LEFT", 28, 0)
        label:SetPoint("RIGHT", t, "RIGHT", -22, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)

        -- Drives the gold button's label (selected loadout name). When nothing is
        -- selected, show a greyed placeholder instead of an empty bar.
        local function setButtonText(s)
            if s and s ~= "" then
                label:SetText(s)
                label:SetTextColor(1, 0.82, 0)
            else
                label:SetText(L["Select a profile"])
                label:SetTextColor(0.5, 0.5, 0.5)
            end
        end
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

        -- Currently selected loadout, identified by its storage index in
        -- `exports`. The modern dropdown has no built-in selection model for our
        -- index-as-identity scheme, so we track it ourselves and drive the text.
        local selectedIdx

        local function setSelected(idx)
            selectedIdx = idx
            setButtonText(idx and exports[idx] and exports[idx].name or "")
        end

        local function selectLoadout(idx)
            setSelected(idx)
            local v = exports[idx] and exports[idx].value or ""
            exportEditbox:SetText(v)
        end

        -- Nothing is selected on load, so show the greyed placeholder immediately.
        setSelected(nil)

        local create = function(name)
            if #exports > MAX_PROFILES_COUNT then
                MySlot:Print(L["Too many profiles, please delete before create new one."])
                return
            end

            local txt = {
                name = name,
                class = select(2, UnitClass("player")),
            }
            table.insert(exports, txt)

            return true
        end

        local save = function(force)
            local c = selectedIdx
            local v = exportEditbox:GetText()
            if not force and v == "" then
                return
            end
            if (not c) or (not exports[c]) then
                local n = date()
                if not create(n) then
                    return
                end
                c = #exports
                setSelected(c)
            end

            exports[c].value = v
            infolabel:SetText("")
        end

        -- Localized, class-colored label for a class group header. token may be
        -- false/nil for the legacy/unknown group.
        local function classHeaderText(token)
            if not token then
                return OTHER
            end
            local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
            if color then
                if color.WrapTextInColorCode then
                    return color:WrapTextInColorCode(name)
                elseif color.colorStr then
                    return "|c" .. color.colorStr .. name .. "|r"
                end
            end
            return name
        end

        local SORT_MODES = {
            { value = "date", text = L["By date"] },
            { value = "name", text = L["By name"] },
            { value = "class", text = L["By class"] },
        }

        -- Inline icon prefix so menu items carry the scroll icons the original
        -- UIDropDownMenu put in the check slot (inv_scroll_03 for loadouts,
        -- inv_scroll_04 for the pre-import backup).
        local function withIcon(texture, text)
            return ("|T%s:16:16|t %s"):format(texture, text)
        end

        -- Rebuilt every time the dropdown opens. Checkboxes/radios default to
        -- MenuResponse.Refresh, so flipping the filter or a sort mode regenerates
        -- the list in place -- no manual reopen needed.
        local function generator(_, root)
            root:CreateCheckbox(L["Only my class"], function()
                return MyslotSettings and MyslotSettings.loadoutFilterClass and true or false
            end, function()
                MyslotSettings.loadoutFilterClass = not (MyslotSettings.loadoutFilterClass and true or false)
            end)

            local sortSub = root:CreateButton(L["Sort by"])
            for _, mode in ipairs(SORT_MODES) do
                local value = mode.value
                sortSub:CreateRadio(mode.text, function()
                    return ((MyslotSettings and MyslotSettings.loadoutSort) or "date") == value
                end, function()
                    MyslotSettings.loadoutSort = value
                end)
            end

            root:CreateDivider()

            local backupIcon = "Interface\\Icons\\inv_scroll_04"
            local function restoreBackup(val)
                if val then
                    exportEditbox:SetText(val)
                    infolabel:SetText("")
                    setSelected(nil)
                    setButtonText(L["Before Last Import"])
                end
            end

            if #backups == 0 then
                -- Nothing backed up yet: show the entry greyed/disabled.
                local none = root:CreateButton(withIcon(backupIcon, L["Before Last Import"]))
                none:SetEnabled(false)
            else
                -- Clicking "Before Last Import" restores the newest backup by
                -- default; the submenu arrow lists all recent backups (newest
                -- first) so an older snapshot can be picked instead.
                local newest = backups[#backups]
                local newestVal = type(newest) == "table" and newest.value or newest
                local backupSub = root:CreateButton(
                    withIcon(backupIcon, L["Before Last Import"]),
                    function()
                        restoreBackup(newestVal)
                    end)
                backupSub:SetShouldRespondIfSubmenu(true)
                for i = #backups, 1, -1 do
                    local b = backups[i]
                    local val = type(b) == "table" and b.value or b
                    local when = type(b) == "table" and b.time
                    local lbl = when and date("%Y-%m-%d %H:%M", when)
                        or (L["Backup"] .. " " .. tostring(#backups - i + 1))
                    backupSub:CreateButton(lbl, function()
                        restoreBackup(val)
                    end)
                end
            end

            local sort = (MyslotSettings and MyslotSettings.loadoutSort) or "date"
            local filterClass = MyslotSettings and MyslotSettings.loadoutFilterClass or false
            local myClass = select(2, UnitClass("player"))
            local rows = MySlot:OrderLoadouts(exports, sort, filterClass, myClass)

            for _, dispRow in ipairs(rows) do
                if dispRow.header ~= nil then
                    root:CreateTitle(classHeaderText(dispRow.header))
                else
                    local idx = dispRow.index
                    root:CreateButton(withIcon("Interface\\Icons\\inv_scroll_03", exports[idx].name), function()
                        selectLoadout(idx)
                    end)
                end
            end
        end

        t:SetScript("OnClick", function(self)
            -- Pin the menu directly below the button (left-aligned), like the
            -- keybinding dropdown, instead of cursor-anchoring it.
            local description = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultMenuMixin())
            description:SetMinimumWidth(self:GetWidth())
            Menu.PopulateDescription(generator, self, description)
            -- Match Blizzard's DropdownButton default anchor (TOPLEFT -> BOTTOMLEFT,
            -- flush, left-aligned), as used by the system/settings menu dropdowns.
            local anchor = AnchorUtil.CreateAnchor("TOPLEFT", self, "BOTTOMLEFT", 0, 0)
            Menu.GetManager():OpenMenu(self, description, anchor)
        end)

        local popctx = {}

        StaticPopupDialogs["MYSLOT_EXPORT_TITLE"].OnShow = function(self)
            local c = popctx.current
            local editBox = self.GetEditBox and self:GetEditBox() or self.editBox
            if c and exports[c] then
                editBox:SetText(exports[c].name or "")
            end
            editBox:SetFocus()
        end


        StaticPopupDialogs["MYSLOT_EXPORT_TITLE"].OnAccept = function(self)
            local c = popctx.current
            local editBox = self.GetEditBox and self:GetEditBox() or self.editBox
            -- if c then rename
            if c and exports[c] then
                local n = editBox:GetText()
                if n ~= "" then
                    exports[c].name = n
                    if selectedIdx == c then
                        setButtonText(n)
                    end
                end
                return
            end

            if create(editBox:GetText()) then
                selectLoadout(#exports)
            end
        end

        do
            local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
            b:SetWidth(70)
            b:SetHeight(25)
            b:SetPoint("TOPLEFT", t, 280, 0)
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
            b:SetPoint("TOPLEFT", t, 355, 0)
            b:SetText(SAVE)
            b:SetScript("OnClick", function() save(true) end)
        end

        do
            local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
            b:SetWidth(70)
            b:SetHeight(25)
            b:SetPoint("TOPLEFT", t, 430, 0)
            b:SetText(DELETE)
            b:SetScript("OnClick", function()
                local c = selectedIdx

                if c then
                    StaticPopupDialogs["MYSLOT_CONFIRM_DELETE"].OnAccept = function()
                        StaticPopup_Hide("MYSLOT_CONFIRM_DELETE")
                        table.remove(exports, c)

                        if #exports == 0 then
                            setSelected(nil)
                            exportEditbox:SetText("")
                        else
                            selectLoadout(#exports)
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
            b:SetPoint("TOPLEFT", t, 505, 0)
            b:SetText(L["Rename"])
            b:SetScript("OnClick", function()
                local c = selectedIdx

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
            type = "launcher",
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
            local importMsg = MySlot:Import(profileString, { force = false })

            if not importMsg then
                return
            end

            local opt = {}
            CreateSettingMenu(opt)

            MySlot:RecoverData(importMsg, {
                actionOpt = opt,
                clearOpt = opt,
            })
        end

    elseif cmd == "clear" then
        opt = {
            [1] = true,
            [2] = true,
            [3] = true,
            [4] = true,
            [5] = true,
            [6] = true,
            [7] = true,
            [8] = true,
            [9] = true,
            [10] = true,
            [11] = true,
            [12] = true,
            [13] = true,
            [14] = true,
            [15] = true,
            ["ACCOUNT"] = true,
            ["CHARACTOR"] = true,
        }
        if what == "action" then
            MySlot:Clear("ACTION", opt)
        elseif what == "macro" then
            MySlot:Clear("MACRO", opt)
        elseif what == "binding" then
            MySlot:Clear("BINDING", opt)
        else
            Settings.OpenToCategory(MySlot.settingcategory.ID)
        end
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
