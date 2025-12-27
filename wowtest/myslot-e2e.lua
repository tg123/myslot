local ADDONNAME, MySlot = ...

if (ADDONNAME or ""):lower() ~= "myslot" then
    return
end

local function click(button)
    if button and button.Click then
        button:Click()
        return
    end

    if not button or not button.GetScript then
        return
    end

    local handler = button:GetScript("OnClick")
    if handler then
        handler(button)
    end
end

local function run_e2e()
    if not MySlot.MainFrame or not MySlot.TestHooks then
        print("Myslot e2e: UI not ready")
        return
    end

    local exportButton = MySlot.TestHooks.exportButton
    local importButton = MySlot.TestHooks.importButton
    local edit = MySlot.TestHooks.exportEditbox

    if not exportButton or not importButton or not edit then
        print("Myslot e2e: missing UI handles")
        return
    end

    MySlot.MainFrame:Show()

    edit:SetText("")
    click(exportButton)

    local exportText = edit:GetText() or ""
    if exportText == "" then
        print("Myslot e2e: export produced empty payload")
        return
    end

    edit:SetText(exportText)
    click(importButton)

    local dialogName = (MySlot.TestHooks and MySlot.TestHooks.importDialog) or "MYSLOT_MSGBOX"
    local msgbox = StaticPopupDialogs and StaticPopupDialogs[dialogName]
    if msgbox and msgbox.OnAccept then
        msgbox.OnAccept()
    end

    print("Myslot e2e: import/export flow executed (length " .. #exportText .. ")")
end

MySlot.TestHooks.e2eRun = run_e2e
