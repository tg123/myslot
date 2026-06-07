-- In-game test runner. Registers /myslottest. Loaded only via the packager
-- #@debug@ block in Myslot.toc, so users on Curse/Wago never see this.

local _, MySlot = ...

-- Pop-up with a single multi-line editbox so the full log can be
-- Ctrl+A / Ctrl+C'd out of the client, no chat-scrollback hunting.
local function show_log(text)
    local f = MySlot._testLogFrame
    if not f then
        f = CreateFrame("Frame", "MyslotTestLogFrame", UIParent,
            BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(720, 520)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true); f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop",  f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
            f:SetBackdropColor(0, 0, 0, 0.92)
        end

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -14)
        title:SetText("Myslot test log  (Ctrl+A then Ctrl+C to copy)")

        local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        close:SetSize(80, 22)
        close:SetPoint("BOTTOMRIGHT", -16, 14)
        close:SetText(CLOSE)
        close:SetScript("OnClick", function() f:Hide() end)

        local scroll = CreateFrame("ScrollFrame", "MyslotTestLogScroll", f,
            "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -36)
        scroll:SetPoint("BOTTOMRIGHT", -36, 46)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal or GameFontHighlight)
        edit:SetWidth(640)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit

        MySlot._testLogFrame = f
    end
    f.edit:SetText(text)
    f.edit:HighlightText()
    f.edit:SetFocus()
    f:Show()
end

SLASH_MYSLOTTEST1 = "/myslottest"
SlashCmdList["MYSLOTTEST"] = function()
    if InCombatLockdown() then
        MySlot:Print("|cFFFF6060Myslot tests cannot run in combat|r")
        return
    end

    local lines = {}
    local function append(line)
        DEFAULT_CHAT_FRAME:AddMessage(line)
        -- Strip WoW color escapes so the copied text is plain.
        lines[#lines + 1] = (line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end

    MySlot:Print("|cFFFFD100Running Myslot tests...|r")
    append("Running Myslot tests...")
    -- Async run: tests can T.yield() to keep WoW's per-script watchdog
    -- happy. The dialog opens after all tests have finished.
    MySlot.test.run(append, function(_, failed)
        local summary = failed == 0
            and "All tests passed"
            or ("%d test(s) failed"):format(failed)
        if failed == 0 then
            MySlot:Print("|cFF60FF60" .. summary .. "|r")
        else
            MySlot:Print("|cFFFF6060" .. summary .. "|r")
        end
        append(summary)
        show_log(table.concat(lines, "\n"))
    end)
end
