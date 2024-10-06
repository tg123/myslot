local _, MySlot = ...
local L = MySlot.L
local RegEvent = MySlot.regevent


local f = CreateFrame("Frame", nil, UIParent)
f.name = L["Myslot"]

local category = Settings.RegisterCanvasLayoutCategory(f, L["Myslot"])
MySlot.settingcategory = category
Settings.RegisterAddOnCategory(category)

RegEvent("ADDON_LOADED", function()
    do
        local t = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        t:SetText(L["Myslot"])
        t:SetPoint("TOPLEFT", f, 15, -15)
    end

    do
        local t = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        t:SetText(L["Feedback"] .. "  farmer1992@gmail.com")
        t:SetPoint("TOPLEFT", f, 15, -50)
    end


    do
        local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
        b:SetWidth(200)
        b:SetHeight(25)
        b:SetPoint("TOPLEFT", 15, -80)
        b:SetText(L["Open Myslot"])
        b:SetScript("OnClick", function()
            MySlot.MainFrame:Show()
        end)
    end

    MyslotSettings = MyslotSettings or {}

    do
        MyslotSettings.minimap = MyslotSettings.minimap or { hide = false }
        local config = MyslotSettings.minimap

        local b = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        b:SetPoint("TOPLEFT", f, 15, -110)

        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("LEFT", b, "RIGHT", 0, 1)
        b.text:SetText(L["Minimap Icon"])
        b:SetChecked(not config.hide)
        b:SetScript("OnClick", function()
            config.hide = not b:GetChecked()

            local icon = LibStub("LibDBIcon-1.0")
            if b:GetChecked() then
                icon:Show("Myslot")
            else
                icon:Hide("Myslot")
            end
        end)
    end

    local doffset = -160
    do
        local t = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        t:SetText(RED_FONT_COLOR:WrapTextInColorCode(L["DANGEROUS"]))
        t:SetPoint("TOPLEFT", f, 15, doffset)
    end

    do
        local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
        b:SetWidth(200)
        b:SetHeight(25)
        b:SetPoint("TOPLEFT", 15, doffset - 20)
        b:SetText(L["Remove everything in ActionBar"])
        b:SetScript("OnClick", function()
            StaticPopup_Show("MYSLOT_CONFIRM_CLEAR", "ACTION", nil, "ACTION")
        end)
    end

    do
        local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
        b:SetWidth(200)
        b:SetHeight(25)
        b:SetPoint("TOPLEFT", 15, doffset - 50)
        b:SetText(L["Remove all Key Bindings"])
        b:SetScript("OnClick", function()
            StaticPopup_Show("MYSLOT_CONFIRM_CLEAR", "BINDING", nil, "BINDING")
        end)
    end

    do
        local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
        b:SetWidth(200)
        b:SetHeight(25)
        b:SetPoint("TOPLEFT", 15, doffset - 80)
        b:SetText(L["Remove all Macros"])
        b:SetScript("OnClick", function()
            StaticPopup_Show("MYSLOT_CONFIRM_CLEAR", "MACRO", nil, "MACRO")
        end)
    end

    do
        local b = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        b:SetPoint("TOPLEFT", f, 15, doffset - 110)

        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("LEFT", b, "RIGHT", 0, 1)
        b.text:SetText(L["Allow"] .. " " .. "|cffff0000" .. L["CLEAR"] .. "|r" .. " " .. L[" before Import"])
        b:SetChecked(MyslotSettings.allowclearonimport)
        b:SetScript("OnClick", function()
            MyslotSettings.allowclearonimport = b:GetChecked()
        end)
    end
end)

StaticPopupDialogs["MYSLOT_CONFIRM_CLEAR"] = {
    text = L["Please type %s to confirm"],
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    multiple = 0,
    OnAccept = function(self, data)
        local tx = self.editBox:GetText()

        if tx == data then
            MySlot:Clear(data, {
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
            })
        else
            MySlot:Print(L["Please type %s to confirm"]:format(data))
        end

    end,
}