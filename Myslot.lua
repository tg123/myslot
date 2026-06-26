local _, MySlot = ...

local L = MySlot.L

local crc32 = MySlot.crc32
local base64 = MySlot.base64

local pblua = MySlot.luapb
local _MySlot = pblua.load_proto_ast(MySlot.ast)


local MYSLOT_AUTHOR = "Boshi Lian <farmer1992@gmail.com>"

local MYSLOT_VER = 42

-- TWW Beta Compat code (fix and cleanup below later)
local PickupSpell = C_Spell and C_Spell.PickupSpell or _G.PickupSpell
local PickupItem = C_Item and C_Item.PickupItem or _G.PickupItem
local GetSpellInfo = C_Spell and C_Spell.GetSpellName or _G.GetSpellInfo
local GetSpellLink = C_Spell and C_Spell.GetSpellLink or _G.GetSpellLink
local PickupSpellBookItem = C_SpellBook and C_SpellBook.PickupSpellBookItem or _G.PickupSpellBookItem
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
-- TWW Beta Compat End
-- Polyfill for deprecated Blizzard Macro Globals in Midnight 12.1
local MAX_ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120
local MAX_CHARACTER_MACROS = MAX_CHARACTER_MACROS or 18
-- Polyfill for deprecated Blizzard Macro Globals in Midnight 12.1 END
-- local MYSLOT_IS_DEBUG = true
local MYSLOT_LINE_SEP = IsWindowsClient() and "\r\n" or "\n"
local MYSLOT_MAX_ACTIONBAR = 180

-- {{{ SLOT TYPE
local MYSLOT_SPELL = _MySlot.Slot.SlotType.SPELL
local MYSLOT_COMPANION = _MySlot.Slot.SlotType.COMPANION
local MYSLOT_ITEM = _MySlot.Slot.SlotType.ITEM
local MYSLOT_MACRO = _MySlot.Slot.SlotType.MACRO
local MYSLOT_FLYOUT = _MySlot.Slot.SlotType.FLYOUT
local MYSLOT_EQUIPMENTSET = _MySlot.Slot.SlotType.EQUIPMENTSET
local MYSLOT_EMPTY = _MySlot.Slot.SlotType.EMPTY
local MYSLOT_SUMMONPET = _MySlot.Slot.SlotType.SUMMONPET
local MYSLOT_SUMMONMOUNT = _MySlot.Slot.SlotType.SUMMONMOUNT
local MYSLOT_OUTFIT = _MySlot.Slot.SlotType.OUTFIT
local MYSLOT_NOTFOUND = "notfound"

MySlot.SLOT_TYPE = {
    ["spell"] = MYSLOT_SPELL,
    ["companion"] = MYSLOT_COMPANION,
    ["macro"] = MYSLOT_MACRO,
    ["item"] = MYSLOT_ITEM,
    ["flyout"] = MYSLOT_FLYOUT,
    ["petaction"] = MYSLOT_EMPTY,
    ["futurespell"] = MYSLOT_EMPTY,
    ["equipmentset"] = MYSLOT_EQUIPMENTSET,
    ["summonpet"] = MYSLOT_SUMMONPET,
    ["summonmount"] = MYSLOT_SUMMONMOUNT,
    ["outfit"] = MYSLOT_OUTFIT,
    [MYSLOT_NOTFOUND] = MYSLOT_EMPTY,
}
-- }}}

local MYSLOT_BIND_CUSTOM_FLAG = 0xFFFF

-- WoW provides geterrorhandler(); plain Lua (CI / standalone harness) does not.
-- Resolve it once with a print-based fallback so RunAsync's error paths never
-- raise "attempt to call a nil value" and mask the original error.
local geterrorhandler = _G.geterrorhandler or function() return print end

-- Yield back to the WoW runtime when running inside a coroutine (e.g. the test
-- harness, or any future async import/export driver). This lets the per-script
-- watchdog ("script ran too long") reset between heavy phases. It is a no-op on
-- the main thread, so synchronous callers (the GUI import path) are unaffected.
local function MaybeYield(progress)
    -- coroutine.running() returns nil on the main thread in Lua 5.1, but
    -- (thread, true) on the main thread in LuaJIT. The second return value tells
    -- the two apart so this stays a true no-op when not actually in a coroutine.
    -- The optional `progress` (0..1) is forwarded to the async runner so callers
    -- like RecoverData can drive a progress bar; synchronous callers ignore it.
    local co, isMain = coroutine.running()
    if co and not isMain then
        coroutine.yield(progress)
    end
end

-- Run fn() inside a coroutine, pumping it one step per frame with C_Timer so
-- heavy work (e.g. importing a large profile) yields back to the WoW runtime and
-- never trips the "script ran too long" watchdog. Values yielded by fn (a 0..1
-- progress fraction, via MaybeYield) are forwarded to onProgress; onDone(ok) is
-- called when the coroutine finishes or errors. Falls back to a synchronous call
-- when no frame scheduler is available (CI / very old clients).
function MySlot:RunAsync(fn, onProgress, onDone)
    if not (C_Timer and C_Timer.After) then
        local ok, err = pcall(fn)
        if not ok then
            geterrorhandler()(err)
        end
        if onProgress then onProgress(1) end
        if onDone then onDone(ok) end
        return
    end

    local co = coroutine.create(fn)
    local function step()
        local ok, progress = coroutine.resume(co)
        if not ok then
            geterrorhandler()(progress)
            if onDone then onDone(false) end
            return
        end
        if coroutine.status(co) == "dead" then
            if onProgress then onProgress(1) end
            if onDone then onDone(true) end
            return
        end
        if onProgress and type(progress) == "number" then
            onProgress(progress)
        end
        C_Timer.After(0, step)
    end
    step()
end

-- {{{ MergeTable
-- return item count merge into target
local function MergeTable(target, source)
    if source then
        assert(type(target) == 'table' and type(source) == 'table')
        local n = 0
        for _, b in ipairs(source) do
            assert(b < 256)
            target[#target + 1] = b
            n = n + 1
            if n % 1024 == 0 then
                MaybeYield()
            end
        end
        return #source
    else
        return 0
    end
end
-- }}}

-- fix unpack stackoverflow
local function StringToTable(s)
    if type(s) ~= 'string' then
        return {}
    end
    local r = {}
    for i = 1, string.len(s) do
        r[#r + 1] = string.byte(s, i)
        if i % 1024 == 0 then
            MaybeYield()
        end
    end
    return r
end

local function TableToString(s)
    if type(s) ~= 'table' then
        return ''
    end
    local t = {}
    local n = 0
    for _, c in pairs(s) do
        t[#t + 1] = string.char(c)
        n = n + 1
        if n % 1024 == 0 then
            MaybeYield()
        end
    end
    return table.concat(t)
end

local function CreateSpellOverrideMap()
    local spellOverride = {}

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        -- 11.0 only
        for skillLineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
            for i = 1, skillLineInfo.numSpellBookItems do
                local spellIndex = skillLineInfo.itemIndexOffset + i
                local spellType, id, spellId = C_SpellBook.GetSpellBookItemType(spellIndex, Enum.SpellBookSpellBank.Player)
                if spellId then
                    local newid = C_Spell.GetOverrideSpell(spellId)
                    if newid ~= spellId then
                        spellOverride[newid] = spellId
                    end
                elseif spellType == Enum.SpellBookItemType.Flyout then
                    local _, _, numSlots, isKnown = GetFlyoutInfo(id);
                    if isKnown and (numSlots > 0) then
                        for k = 1, numSlots do
                            local spellID, overrideSpellID = GetFlyoutSlotInfo(id, k)
                            spellOverride[overrideSpellID] = spellID
                        end
                    end
                end
            end
        end

        local isInspect = false
        for specIndex = 1, GetNumSpecGroups(isInspect) do
            for tier = 1, MAX_TALENT_TIERS do
                for column = 1, NUM_TALENT_COLUMNS do
                    local spellId = select(6, GetTalentInfo(tier, column, specIndex))
                    if spellId then
                        local newid = C_Spell.GetOverrideSpell(spellId)
                        if newid ~= spellId then
                            spellOverride[newid] = spellId
                        end
                    end
                end
            end
        end

        for pvpTalentSlot = 1, 3 do
            local slotInfo = C_SpecializationInfo.GetPvpTalentSlotInfo(pvpTalentSlot)
            if slotInfo ~= nil then
                for i, pvpTalentID in ipairs(slotInfo.availableTalentIDs) do
                    local spellId = select(6, GetPvpTalentInfoByID(pvpTalentID))
                    if spellId then
                        local newid = C_Spell.GetOverrideSpell(spellId)
                        if newid ~= spellId then
                            spellOverride[newid] = spellId
                        end
                    end
                end
            end
        end
    end

    return spellOverride
end

function MySlot:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|CFFFF0000<|r|CFFFFD100Myslot|r|CFFFF0000>|r" .. (msg or "nil"))
end

-- {{{ GetMacroInfo
function MySlot:GetMacroInfo(macroId)
    -- {macroId ,icon high 8, icon low 8 , namelen, ..., bodylen, ...}

    local name, iconTexture, body  = GetMacroInfo(macroId)

    if not name then
        return nil
    end

    iconTexture = gsub(strupper(iconTexture or "INV_Misc_QuestionMark"), "INTERFACE\\ICONS\\", "")

    local msg = _MySlot.Macro()
    msg.id = macroId
    msg.icon = iconTexture
    msg.name = name
    msg.body = body

    return msg
end

-- }}}

-- {{{ GetActionInfo
function MySlot:GetActionInfo(slotId)
    local slotType, index, subType = GetActionInfo(slotId)
    local strindexOverride = nil
    if MySlot.SLOT_TYPE[slotType] == MYSLOT_EQUIPMENTSET then
        -- i starts from 0 https://github.com/tg123/myslot/issues/10 weird blz
        for i = 0, C_EquipmentSet.GetNumEquipmentSets() do
            if C_EquipmentSet.GetEquipmentSetInfo(i) == index then
                index = i
                break
            end
        end
    elseif MySlot.SLOT_TYPE[slotType] == MYSLOT_OUTFIT then
        -- `index` is the account-wide outfitID. Also record the outfit name so
        -- Import can fall back to matching by name when the id doesn't exist
        -- (e.g. importing someone else's export). https://github.com/tg123/myslot/issues/110
        if C_TransmogOutfitInfo and C_TransmogOutfitInfo.GetOutfitInfo then
            local outfitInfo = C_TransmogOutfitInfo.GetOutfitInfo(index)
            if outfitInfo then
                strindexOverride = outfitInfo.name
            end
        end
    elseif not MySlot.SLOT_TYPE[slotType] then
        if slotType then
            self:Print(L["[WARN] Ignore unsupported Slot Type [ %s ] , contact %s please"]:format(slotType, MYSLOT_AUTHOR))
        end
        return nil
    elseif slotType == "macro" and subType then
        PickupAction(slotId)
        _, index = GetCursorInfo()
        PlaceAction(slotId)
    elseif slotType == "spell" and subType == "assistedcombat" then
        index = C_AssistedCombat.GetActionSpell()
    elseif not index then
        return nil
    end

    local msg = _MySlot.Slot()
    msg.id = slotId
    msg.type = MySlot.SLOT_TYPE[slotType]
    if type(index) == 'string' then
        msg.strindex = index
        msg.index = 0
    else
        msg.index = index
    end
    if strindexOverride then
        msg.strindex = strindexOverride
    end
    return msg
end

-- }}}

function MySlot:GetPetActionInfo(slotId)
    local name, _, isToken, _, _, _, spellID = GetPetActionInfo(slotId)

    local msg = _MySlot.Slot()
    msg.id = slotId
    msg.type = MYSLOT_SPELL

    if isToken then
        msg.strindex = name
        msg.index = 0
    elseif spellID then
        msg.index = spellID
    elseif not name then
        msg.index = 0
        msg.type = MYSLOT_EMPTY
    else
        return nil
    end

    return msg
end

-- {{{ GetBindingInfo
-- {{{ Serialzie Key
local function KeyToByte(key, command)
    -- {mod , key , command high 8, command low 8}
    if not key then
        return nil
    end

    local mod = nil
    local _, _, _mod, _key = string.find(key, "(.+)-(.+)")
    if _mod and _key then
        mod, key = _mod, _key
    end

    mod = mod or "NONE"

    if not MySlot.MOD_KEYS[mod] then
        MySlot:Print(L["[WARN] Ignore unsupported Key Binding [ %s ] , contact %s please"]:format(mod, MYSLOT_AUTHOR))
        return nil
    end

    local msg = _MySlot.Key()
    if MySlot.KEYS[key] then
        msg.key = MySlot.KEYS[key]
    else
        msg.key = MySlot.KEYS["KEYCODE"]
        msg.keycode = key
    end
    msg.mod = MySlot.MOD_KEYS[mod]

    return msg
end
-- }}}

function MySlot:GetBindingInfo(index)
    -- might more than 1
    local _command, _, key1, key2 = GetBinding(index)

    if not _command then
        return
    end

    local command = MySlot.BINDS[_command]

    local msg = _MySlot.Bind()

    if not command then
        msg.command = _command
        command = MYSLOT_BIND_CUSTOM_FLAG
    end

    msg.id = command

    msg.key1 = KeyToByte(key1)
    msg.key2 = KeyToByte(key2)

    if msg.key1 or msg.key2 then
        return msg
    else
        return nil
    end
end

-- }}}

local function GetTalentTreeString()
    -- maybe classic
    if GetTalentTabInfo then

        -- wlk
        if tonumber(select(3, GetTalentTabInfo(1)), 10) then
            return select(3, GetTalentTabInfo(1)) ..  "/" .. select(3, GetTalentTabInfo(2)) .. "/" .. select(3, GetTalentTabInfo(3))
        end

        -- other
        if tonumber(select(5, GetTalentTabInfo(1)), 10) then
            return select(5, GetTalentTabInfo(1)) ..  "/" .. select(5, GetTalentTabInfo(2)) .. "/" .. select(5, GetTalentTabInfo(3))
        end
    end

    -- 11.0
    if PlayerSpellsFrame_LoadUI then
        PlayerSpellsFrame_LoadUI()

        -- no talent yet
        if not PlayerSpellsFrame.TalentsFrame:GetConfigID() then
            return nil
        end

        PlayerSpellsFrame.TalentsFrame:UpdateTreeInfo()
        if PlayerSpellsFrame.TalentsFrame:GetLoadoutExportString() then
            return PlayerSpellsFrame.TalentsFrame:GetLoadoutExportString()
        end
    end

    return nil
end

function MySlot:Export(opt)
    -- ver nop nop nop crc32 crc32 crc32 crc32

    local msg = _MySlot.Charactor()

    msg.ver = MYSLOT_VER
    msg.name = UnitName("player")

    msg.macro = {}

    if not opt.ignoreMacros["ACCOUNT"] then
        for i = 1, MAX_ACCOUNT_MACROS  do
            local m = self:GetMacroInfo(i)
            if m then
                msg.macro[#msg.macro + 1] = m
            end
        end
    end

    if not opt.ignoreMacros["CHARACTOR"] then
        for i = MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
            local m = self:GetMacroInfo(i)
            if m then
                msg.macro[#msg.macro + 1] = m
            end
        end
    end

    msg.slot = {}
    -- TODO move to GetActionInfo
    local spellOverride = CreateSpellOverrideMap()

    for i = 1, MYSLOT_MAX_ACTIONBAR do
        if not opt.ignoreActionBars[math.ceil(i / 12)] then
            local m = self:GetActionInfo(i)
            if m then
                if m.type == 'SPELL' then
                    if spellOverride[m.index] then
                        m.index = spellOverride[m.index]
                    end
                end
                msg.slot[#msg.slot + 1] = m
            end
        end

        -- Yield once per action bar (12 slots) so scanning all 180 slots can't
        -- trip the "script ran too long" watchdog. No-op outside a coroutine.
        if i % 12 == 0 then
            MaybeYield()
        end
    end

    msg.bind = {}
    if not opt.ignoreBinding then
        for i = 1, GetNumBindings() do
            local m = self:GetBindingInfo(i)
            if m then
                msg.bind[#msg.bind + 1] = m
            end
            if i % 32 == 0 then
                MaybeYield()
            end
        end
    end

    msg.petslot = {}
    if not opt.ignorePetActionBar and IsPetActive() then
        for i = 1, NUM_PET_ACTION_SLOTS, 1 do
            local m = self:GetPetActionInfo(i)
            if m then
                msg.petslot[#msg.petslot + 1] = m
            end
        end
    end

    if not opt.ignoreCooldownManager and C_CooldownViewer and C_CooldownViewer.GetLayoutData then
        local layout = C_CooldownViewer.GetLayoutData()
        if layout and layout ~= "" then
            msg.cooldownManager = layout
        end
    end

    msg.clickBinding = {}
    if not opt.ignoreClickBindings and C_ClickBindings and C_ClickBindings.GetProfileInfo then
        for _, info in ipairs(C_ClickBindings.GetProfileInfo()) do
            local c = _MySlot.ClickBinding()
            c.type = info.type
            c.actionID = info.actionID or 0
            c.button = info.button
            c.modifiers = info.modifiers or 0
            msg.clickBinding[#msg.clickBinding + 1] = c
        end
    end

    local ct = msg:Serialize()
    local t = { MYSLOT_VER, 86, 04, 22, 0, 0, 0, 0 }
    MergeTable(t, StringToTable(ct))

    -- {{{ CRC32
    -- crc
    local crc = crc32.enc(t)
    t[5] = bit.rshift(crc, 24)
    t[6] = bit.band(bit.rshift(crc, 16), 255)
    t[7] = bit.band(bit.rshift(crc, 8), 255)
    t[8] = bit.band(crc, 255)
    -- }}}

    -- {{{ OUTPUT
    local talent = GetTalentTreeString()

    local s = ""
    s = "# --------------------" .. MYSLOT_LINE_SEP .. s
    s = "# " .. L["Feedback"] .. "  farmer1992@gmail.com" .. MYSLOT_LINE_SEP .. s
    s = "# " .. MYSLOT_LINE_SEP .. s
    s = "# " .. LEVEL .. ": " .. UnitLevel("player") .. MYSLOT_LINE_SEP .. s
    if talent then
        s = "# " .. TALENTS .. ": " .. talent .. MYSLOT_LINE_SEP .. s
    end
    if GetSpecialization then
        s = "# " ..
        SPECIALIZATION ..
        ": " ..
        (GetSpecialization() and select(2, GetSpecializationInfo(GetSpecialization())) or NONE_CAPS) ..
        MYSLOT_LINE_SEP .. s
    end
    s = "# " .. CLASS .. ": " .. UnitClass("player") .. MYSLOT_LINE_SEP .. s
    s = "# " .. PLAYER .. ": " .. UnitName("player") .. MYSLOT_LINE_SEP .. s
    s = "# " .. L["Time"] .. ": " .. date() .. MYSLOT_LINE_SEP .. s

    if GetAddOnMetadata then
        s = "# Addon Version: " .. GetAddOnMetadata("Myslot", "Version") .. MYSLOT_LINE_SEP .. s
    end

    s = "# Wow Version: " .. GetBuildInfo() .. MYSLOT_LINE_SEP .. s
    s = "# Myslot (https://myslot.net " .. L["<- share your profile here"]  ..")" .. MYSLOT_LINE_SEP .. s

    local d = base64.enc(t)
    local LINE_LEN = 60
    for i = 1, d:len(), LINE_LEN do
        s = s .. d:sub(i, i + LINE_LEN - 1) .. MYSLOT_LINE_SEP
    end
    s = strtrim(s)
    s = s .. MYSLOT_LINE_SEP .. "# --------------------"
    s = s .. MYSLOT_LINE_SEP .. "# END OF MYSLOT"

    return s
    -- }}}
end

local function IsEmptyTable(t)
    return (t == nil) or (next(t) == nil)
end

function MySlot:Import(text, opt)
    if InCombatLockdown() then
        MySlot:Print(L["Import is not allowed when you are in combat"])
        return
    end

    local s = text or ""
    s = string.gsub(s, "(@.[^\n]*\n*)", "")
    s = string.gsub(s, "(#.[^\n]*\n*)", "")
    s = string.gsub(s, "\n", "")
    s = string.gsub(s, "\r", "")
    s = base64.dec(s)

    if #s < 8 then
        MySlot:Print(L["Bad importing text [TEXT]"])
        return
    end

    local force = opt.force

    local crc = s[5] * 2 ^ 24 + s[6] * 2 ^ 16 + s[7] * 2 ^ 8 + s[8]
    s[5], s[6], s[7], s[8] = 0, 0, 0, 0

    if (crc ~= bit.band(crc32.enc(s), 2 ^ 32 - 1)) then
        MySlot:Print(L["Bad importing text [CRC32]"])
        if force then
            MySlot:Print(L["Skip bad CRC32"] .. " " .. L["Try force importing"])
        else
            return
        end
    end

    local ct = {}
    for i = 9, #s do
        ct[#ct + 1] = s[i]
    end
    ct = TableToString(ct)

    local msg = _MySlot.Charactor():Parse(ct)

    if IsEmptyTable(msg.slot) and IsEmptyTable(msg.bind) and IsEmptyTable(msg.macro)
        and IsEmptyTable(msg.clickBinding)
        and (msg.cooldownManager == nil or msg.cooldownManager == "") and not force then
        MySlot:Print(L["Nothing to import"])
        return
    end

    return msg
end

local function UnifyCRLF(text)
    text = string.gsub(text, "\r", "")
    return strtrim(text)
end

-- Build a lookup of the character's current macros keyed by both "name_body"
-- and "body". Scanning all 138 macro slots is expensive, so callers that do
-- many lookups (RecoverData) should build this once and reuse it instead of
-- rebuilding per lookup.
function MySlot:BuildMacroIndex()
    local localMacro = {}
    for i = 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
        local name, _, body = GetMacroInfo(i)
        if name then
            body = UnifyCRLF(body)
            localMacro[name .. "_" .. body] = i
            localMacro[body] = i
        end
        if i % 30 == 0 then
            MaybeYield()
        end
    end
    return localMacro
end

-- Find macro by index/name/body. Pass a prebuilt localMacro index (see
-- BuildMacroIndex) to avoid rescanning every macro slot on each call.
function MySlot:FindMacro(macroInfo, localMacro)
    if not macroInfo then
        return
    end

    localMacro = localMacro or MySlot:BuildMacroIndex()

    local name = macroInfo["name"]
    local body = macroInfo["body"]
    body = UnifyCRLF(body)

    -- Return index if found or nil
    return localMacro[name .. "_" .. body] or localMacro[body]
end

-- {{{ FindOrCreateMacro
function MySlot:FindOrCreateMacro(macroInfo, localMacro)
    if not macroInfo then
        return
    end

    localMacro = localMacro or MySlot:BuildMacroIndex()

    local localIndex = MySlot:FindMacro(macroInfo, localMacro)
    if localIndex then
        return localIndex
    else
        local id = macroInfo["oldid"]
        local name = macroInfo["name"]
        local icon = macroInfo["icon"]
        local body = macroInfo["body"]
        body = UnifyCRLF(body)

        local numglobal, numperchar = GetNumMacros()
        local perchar = id > MAX_ACCOUNT_MACROS and 2 or 1

        --[[
            perchar    G = 01 P = 10
            testallow  allow 01 | allow 10 = 00 , 01 , 10 , 11
            perchar & testallow = 01 , 10 , 00
            perchar = testallow when not allow
        ]]
        local testallow = bit.bor(numglobal < MAX_ACCOUNT_MACROS and 1 or 0, numperchar < MAX_CHARACTER_MACROS and 2 or 0)
        perchar = bit.band(perchar, testallow)
        perchar = perchar == 0 and testallow or perchar

        if perchar ~= 0 then
            -- fix icon using #showtooltip

            if strsub(body, 0, 12) == '#showtooltip' then
                icon = 'INV_Misc_QuestionMark'
            end
            local newid = CreateMacro(name, icon, body, perchar >= 2)
            if newid then
                -- Keep the shared index in sync so later lookups in the same
                -- recovery pass find this macro instead of creating a duplicate.
                localMacro[name .. "_" .. body] = newid
                localMacro[body] = newid
                return newid
            end
        end

        self:Print(L["Macro %s was ignored, check if there is enough space to create"]:format(name))
        return nil
    end
end
-- }}}


local function CreateFlyoutSpellbookMap()
    local flyouts = {}

    if SPELLS_PER_PAGE then
        for i = 1, GetNumSpellTabs() do
            local _, _, offset, numSpells, _, offSpecID = GetSpellTabInfo(i)
            offSpecID = (offSpecID ~= 0)
            if not offSpecID then
                offset = offset + 1
                local tabEnd = offset + numSpells
                for j = offset, tabEnd - 1 do
                    local spellType, spellId = GetSpellBookItemInfo(j, BOOKTYPE_SPELL)
                    if spellType == "FLYOUT" then
                        local slot = j + (SPELLS_PER_PAGE * (SPELLBOOK_PAGENUMBERS[i] - 1))
                        flyouts[spellId] = { slot, BOOKTYPE_SPELL }
                    end
                end
            end
        end
    end

    if BOOKTYPE_PROFESSION then
        if GetProfessions then
            for _, p in pairs({ GetProfessions() }) do
                local _, _, _, _, numSpells, spelloffset = GetProfessionInfo(p)
                for i = 1, numSpells do
                    local slot = i + spelloffset
                    local spellType, spellId = GetSpellBookItemInfo(slot, BOOKTYPE_PROFESSION)
                    if spellType == "FLYOUT" then
                        flyouts[spellId] = { slot, BOOKTYPE_PROFESSION }
                    end
                end
            end
        end
    end

    -- 11.0 only
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        for skillLineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
            for i = 1, skillLineInfo.numSpellBookItems do
                local spellIndex = skillLineInfo.itemIndexOffset + i
                local spellTypeEnum, spellId = C_SpellBook.GetSpellBookItemType(spellIndex, Enum.SpellBookSpellBank.Player);
                if spellId and spellTypeEnum == Enum.SpellBookItemType.Flyout then
                    flyouts[spellId] = { spellIndex, Enum.SpellBookSpellBank.Player }
                end
            end
        end
    end

    return flyouts
end

-- The live Cooldown Manager keeps an in-memory copy of the layouts in
-- CooldownViewerSettings. Writing the datastore with C_CooldownViewer.SetLayoutData
-- alone does NOT update that copy, so the visible bars never refresh and the stale
-- copy overwrites our blob on the next save. To actually apply an imported layout we
-- push it through the settings serializer, reload the in-memory layouts from the
-- datastore, activate the layout for the current spec, and notify listeners (the
-- live viewer and settings panel both refresh on "CooldownViewerSettings.OnDataChanged").
local function ApplyCooldownLayout(blob)
    if not (C_CooldownViewer and C_CooldownViewer.SetLayoutData) then
        return false
    end

    local settings = CooldownViewerSettings
    local layoutManager = settings and settings.GetLayoutManager and settings:GetLayoutManager()
    local serializer = settings and settings.GetSerializer and settings:GetSerializer()
    local dataProvider = settings and settings.GetDataProvider and settings:GetDataProvider()

    if layoutManager and serializer and dataProvider
        and serializer.SetSerializedData and serializer.ReadData
        and layoutManager.InitMemberVariables and layoutManager.ClearActiveLayout
        and dataProvider.SwitchToBestLayoutForSpec then
        serializer:SetSerializedData(blob)        -- write datastore + clear serializer cache
        layoutManager:InitMemberVariables()       -- drop stale in-memory layouts
        layoutManager:ClearActiveLayout()
        serializer:ReadData()                     -- re-read layouts from the datastore
        dataProvider:SwitchToBestLayoutForSpec()  -- activate the layout for the current spec

        if dataProvider.MarkDirty then
            dataProvider:MarkDirty()
        end

        if layoutManager.SetHasPendingChanges then
            layoutManager:SetHasPendingChanges(false)
        end

        if layoutManager.NotifyListeners then
            layoutManager:NotifyListeners()       -- refresh the live bars + settings panel
        end
    else
        -- Settings UI unavailable; fall back to a plain datastore write.
        C_CooldownViewer.SetLayoutData(blob)
    end

    return true
end

-- Simulate dragging every cooldown into the "Not Displayed" section of the
-- Cooldown Manager, mirroring CooldownViewerSettings drag-to-category behavior.
-- SetLayoutData("") only resets to the Blizzard default layout (which still shows
-- the default cooldowns), so to actually empty the bars we move each cooldown into
-- the hidden pseudo-categories (HiddenSpell / HiddenAura) via the settings data
-- provider and persist the result.
local function MoveAllCooldownsToNotDisplayed()
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then
        return false
    end

    if not (CooldownViewerSettings and CooldownViewerSettings.GetDataProvider) then
        return false
    end

    local category = Enum and Enum.CooldownViewerCategory
    if not category then
        return false
    end

    local hiddenByCategory = {
        [category.Essential] = category.HiddenSpell,
        [category.Utility] = category.HiddenSpell,
        [category.TrackedBuff] = category.HiddenAura,
        [category.TrackedBar] = category.HiddenAura,
    }

    local dataProvider = CooldownViewerSettings:GetDataProvider()
    if not (dataProvider and dataProvider.SetCooldownToCategory) then
        return false
    end

    for cooldownCategory, hiddenCategory in pairs(hiddenByCategory) do
        if hiddenCategory ~= nil then
            local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cooldownCategory, true)
            if cooldownIDs then
                for _, cooldownID in ipairs(cooldownIDs) do
                    dataProvider:SetCooldownToCategory(cooldownID, hiddenCategory)
                end
            end
        end
    end

    if CooldownViewerSettings.SaveCurrentLayout then
        CooldownViewerSettings:SaveCurrentLayout()
    end

    if CooldownViewerSettings.RefreshLayout then
        CooldownViewerSettings:RefreshLayout()
    end

    local layoutManager = CooldownViewerSettings.GetLayoutManager and CooldownViewerSettings:GetLayoutManager()
    if layoutManager and layoutManager.NotifyListeners then
        layoutManager:NotifyListeners()
    end

    return true
end

function MySlot:RecoverData(msg, opt)
    -- {{{ Cache Spells
    --cache spells
    local spellOverride = CreateSpellOverrideMap()
    local flyouts = CreateFlyoutSpellbookMap()
    -- }}}


    -- {{{ cache mounts
    local mounts = {}
    if C_MountJournal then
        for i = 1, C_MountJournal.GetNumMounts() do
            local _, _, _, _, _, _, _, _, _, _, isCollected, mountId = C_MountJournal.GetDisplayedMountInfo(i)
            if isCollected then
                mounts[mountId] = i
            end
        end
    end
    -- }}}

    local slotBucket = {}

    -- Progress accounting for the async runner / progress bar. Total work is the
    -- number of macros + action slots to restore + the clear-unused sweep. Each
    -- yield below reports the running fraction; nil-safe when fields are empty.
    local numMacro = msg.macro and #msg.macro or 0
    local numSlot  = msg.slot and #msg.slot or 0
    local totalWork = numMacro + numSlot + MYSLOT_MAX_ACTIONBAR
    local function pct(done)
        if totalWork <= 0 then return nil end
        return done / totalWork
    end

    -- {{{ Macro
    local macro = {}

    -- Maps an exported macro id (source character slot index) to the macro id
    -- it resolved to on this character. Click bindings of type Macro reference a
    -- macro by index, so they need this remap to survive import.
    local macroIdMap = {}

    -- Build the local macro index once and reuse it for every lookup below.
    -- Rebuilding it per FindMacro/FindOrCreateMacro call scans all 138 macro
    -- slots each time, which on large payloads trips WoW's "script ran too long"
    -- watchdog and can leave duplicate macros behind.
    local localMacro = MySlot:BuildMacroIndex()

    for _, s in pairs(msg.slot or {}) do
        local slotId = s.id
        local slotType = _MySlot.Slot.SlotType[s.type]
        local index = s.index

        if slotType == MYSLOT_MACRO then
            if macro[index] then
                table.insert(macro[index], slotId)
            else
                macro[index] = {slotId}
            end
        end
    end

    local macroProcessed = 0
    for _, m in pairs(msg.macro or {}) do
        local macroId = m.id
        local icon = m.icon
        local name = m.name
        local body = m.body

        local info = {
            ["oldid"] = macroId,
            ["name"] = name,
            ["icon"] = icon,
            ["body"] = body,
        }

        local newid = nil

        if (not opt.actionOpt.ignoreMacros["ACCOUNT"] and macroId <= MAX_ACCOUNT_MACROS)
        or (not opt.actionOpt.ignoreMacros["CHARACTOR"] and macroId > MAX_ACCOUNT_MACROS)
        then
            newid = self:FindOrCreateMacro(info, localMacro)
        end

        if not newid then
            newid = self:FindMacro(info, localMacro)
        end

        if newid then
            macroIdMap[macroId] = newid
            for _, slotId in pairs(macro[macroId] or {}) do
                if not opt.actionOpt.ignoreActionBars[math.ceil(slotId / 12)] then
                    PickupMacro(newid)
                    PlaceAction(slotId)
                end
            end
        else
            MySlot:Print(L["Ignore unknown macro [id=%s]"]:format(macroId))
        end

        macroProcessed = macroProcessed + 1
        MaybeYield(pct(macroProcessed))
    end
    -- }}} Macro


    local slotProcessed = 0
    for _, s in pairs(msg.slot or {}) do
        local slotId = s.id
        local slotType = _MySlot.Slot.SlotType[s.type]
        local index = s.index
        local strindex = s.strindex

        local curType, curIndex = GetActionInfo(slotId)
        curType = MySlot.SLOT_TYPE[curType or MYSLOT_NOTFOUND]
        slotBucket[slotId] = true

        if not pcall(function()

                if opt.actionOpt.ignoreActionBars[math.ceil(slotId / 12)] then
                    return
                end

                if curIndex ~= index or curType ~= slotType then
                    if slotType == MYSLOT_SPELL then
                        PickupSpell(index)

                        -- try if override
                        if not GetCursorInfo() then
                            if spellOverride[index] then
                                PickupSpell(spellOverride[index])
                            end
                        end

                        -- this fallback should not happen, only to workaround some old export
                        if not GetCursorInfo() then
                            local spellName = GetSpellInfo(index)
                            if spellName then
                                PickupSpell(spellName)
                            end
                        end

                        -- another fallback option - try to get base spell
                        if not GetCursorInfo() and FindBaseSpellByID then
                            local baseSpellId = FindBaseSpellByID(index)
                            if baseSpellId then
                                PickupSpell(baseSpellId)
                            end
                        end

                        if not GetCursorInfo() then
                            MySlot:Print(L["Ignore unlearned skill [id=%s], %s"]:format(index, GetSpellLink(index) or ""))
                        end
                    elseif slotType == MYSLOT_FLYOUT then
                        local flyout = flyouts[index]
                        if flyout then
                            PickupSpellBookItem(flyout[1], flyout[2])
                        end

                        if not GetCursorInfo() then
                            MySlot:Print(L["Ignore unlearned skill [flyoutid=%s], %s"]:format(index, GetFlyoutInfo(index) or ""))
                        end

                    elseif slotType == MYSLOT_COMPANION then
                        PickupSpell(index)

                        if not GetCursorInfo() then
                            MySlot:Print(L["Ignore unattained companion [id=%s], %s"]:format(index, GetSpellLink(index) or ""))
                        end
                    elseif slotType == MYSLOT_ITEM then
                        PickupItem(index)

                        if not GetCursorInfo() then
                            MySlot:Print(L["Ignore missing item [id=%s]"]:format(index)) -- TODO add item link
                        end
                    elseif slotType == MYSLOT_SUMMONPET and strindex and strindex ~= curIndex then
                        C_PetJournal.PickupPet(strindex, false)
                        if not GetCursorInfo() then
                            C_PetJournal.PickupPet(strindex, true)
                        end
                        if not GetCursorInfo() then
                            MySlot:Print(L["Ignore unattained pet [id=%s]"]:format(strindex))
                        end
                    elseif slotType == MYSLOT_SUMMONMOUNT then
                        index = mounts[index]
                        if index then
                            C_MountJournal.Pickup(index)
                        else
                            C_MountJournal.Pickup(0)
                            MySlot:Print(L["Use random mount instead of an unattained mount"])
                        end
                    elseif slotType == MYSLOT_EMPTY then
                        PickupAction(slotId)
                    elseif slotType == MYSLOT_EQUIPMENTSET then
                        C_EquipmentSet.PickupEquipmentSet(index)
                    elseif slotType == MYSLOT_OUTFIT then
                        if C_TransmogOutfitInfo and C_TransmogOutfitInfo.PickupOutfit then
                            C_TransmogOutfitInfo.PickupOutfit(index)

                            -- id may not exist on this character/account; fall
                            -- back to matching the saved outfit by name.
                            if not GetCursorInfo() and strindex and strindex ~= ""
                                and C_TransmogOutfitInfo.GetOutfitInfoByName then
                                local outfitInfo = C_TransmogOutfitInfo.GetOutfitInfoByName(strindex)
                                if outfitInfo then
                                    C_TransmogOutfitInfo.PickupOutfit(outfitInfo.outfitID)
                                end
                            end

                            if not GetCursorInfo() then
                                MySlot:Print(L["Ignore unknown outfit [id=%s, name=%s]"]:format(index, strindex or ""))
                            end
                        end
                    end

                    if GetCursorInfo() then
                        PlaceAction(slotId)
                    end
                    ClearCursor()
                end
            end) then
            MySlot:Print(L["[WARN] Ignore slot due to an unknown error DEBUG INFO = [S=%s T=%s I=%s] Please send Importing Text and DEBUG INFO to %s"]:format(slotId, slotType, index, MYSLOT_AUTHOR))
        end

        slotProcessed = slotProcessed + 1
        if slotProcessed % 12 == 0 then
            MaybeYield(pct(numMacro + slotProcessed))
        end
    end

    local clearProcessed = 0
    for i = 1, MYSLOT_MAX_ACTIONBAR do
        if not opt.actionOpt.ignoreActionBars[math.ceil(i / 12)] and not slotBucket[i] then
            if GetActionInfo(i) then
                PickupAction(i)
                ClearCursor()
            end
        end

        clearProcessed = clearProcessed + 1
        if clearProcessed % 12 == 0 then
            MaybeYield(pct(numMacro + numSlot + clearProcessed))
        end
    end

    if not opt.actionOpt.ignoreBinding then

        local bindProcessed = 0
        for _, b in pairs(msg.bind or {}) do
            local command = b.command
            if b.id ~= MYSLOT_BIND_CUSTOM_FLAG then
                command = MySlot.R_BINDS[b.id]
            end

            if b.key1 then
                local mod, key = MySlot.R_MOD_KEYS[b.key1.mod], MySlot.R_KEYS[b.key1.key]
                if key == "KEYCODE" then
                    key = b.key1.keycode
                end
                key = (mod ~= "NONE" and (mod .. "-") or "") .. key
                local bindingContext = 1

                if C_KeyBindings and C_KeyBindings.GetBindingContextForAction then
                     bindingContext = C_KeyBindings.GetBindingContextForAction(command)
                end

                SetBinding(key, command, bindingContext)
            end

            if b.key2 then
                local mod, key = MySlot.R_MOD_KEYS[b.key2.mod], MySlot.R_KEYS[b.key2.key]
                if key == "KEYCODE" then
                    key = b.key2.keycode
                end
                key = (mod ~= "NONE" and (mod .. "-") or "") .. key
                local bindingContext = 1

                if C_KeyBindings and C_KeyBindings.GetBindingContextForAction then
                     bindingContext = C_KeyBindings.GetBindingContextForAction(command)
                end
                SetBinding(key, command, bindingContext)
            end

            bindProcessed = bindProcessed + 1
            if bindProcessed % 32 == 0 then
                MaybeYield()
            end
        end
        SaveBindings(GetCurrentBindingSet())
    end


    if not opt.actionOpt.ignorePetActionBar and IsPetActive() then
        local pettoken = {}
        for i = 1, NUM_PET_ACTION_SLOTS, 1 do
            local name, _, isToken = GetPetActionInfo(i)
            if isToken then
                pettoken[name] = i
            end
        end

        for _, p in pairs(msg.petslot or {}) do
            if p.strindex then
                local slot = pettoken[p.strindex]
                if slot then
                    PickupPetAction(slot)
                    PickupPetAction(p.id)
                end
            elseif p.index then
                PickupPetSpell(p.index)
                PickupPetAction(p.id)
            elseif p.type == MYSLOT_EMPTY then
                PickupPetAction(p.id)
            end
            ClearCursor()
        end
    end


    if not opt.actionOpt.ignoreCooldownManager and msg.cooldownManager and msg.cooldownManager ~= ""
        and C_CooldownViewer and C_CooldownViewer.SetLayoutData then
        ApplyCooldownLayout(msg.cooldownManager)
    end


    if not opt.actionOpt.ignoreClickBindings and not IsEmptyTable(msg.clickBinding)
        and C_ClickBindings and C_ClickBindings.SetProfileByInfo then
        -- Enum.ClickBindingType.Macro; macros are referenced by index, which the
        -- macro restore above may have relocated, so remap through macroIdMap.
        local MACRO_TYPE = (Enum and Enum.ClickBindingType and Enum.ClickBindingType.Macro) or 2
        local profile = {}
        for _, c in pairs(msg.clickBinding) do
            local actionID = c.actionID
            local keep = true
            if c.type == MACRO_TYPE then
                actionID = macroIdMap[c.actionID]
                keep = actionID ~= nil
            end
            if keep then
                profile[#profile + 1] = {
                    type = c.type,
                    actionID = actionID,
                    button = c.button,
                    modifiers = c.modifiers or 0,
                }
            end
        end
        C_ClickBindings.SetProfileByInfo(profile)
    end


    MySlot:Print(L["All slots were restored"])
end

function MySlot:Clear(what, opt)
    if what == "ACTION" then
        for i = 1, MYSLOT_MAX_ACTIONBAR do
            if opt[math.ceil(i / 12)] then
                PickupAction(i)
                ClearCursor()
            end
        end
    elseif what == "MACRO" then
        if opt["ACCOUNT"] then
            for i = MAX_ACCOUNT_MACROS, 1, -1   do
                DeleteMacro(i)
            end
        end

        if opt["CHARACTOR"] then
            for i = MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS,  MAX_ACCOUNT_MACROS + 1, -1 do
                DeleteMacro(i)
            end
        end
    elseif what == "BINDING" then
        for i = 1, GetNumBindings() do
            local action, _, key1, key2 = GetBinding(i)

            for _, key in pairs({ key1, key2 }) do
                if key then
                    local bindingContext = 1

                    if C_KeyBindings and C_KeyBindings.GetBindingContextForAction then
                        bindingContext = C_KeyBindings.GetBindingContextForAction(action)
                    end
                    SetBinding(key, nil, bindingContext)
                end
            end
        end
        SaveBindings(GetCurrentBindingSet())
    elseif what == "COOLDOWNMANAGER" then
        MoveAllCooldownsToNotDisplayed()
    elseif what == "CLICKBINDING" then
        -- Remove all click bindings by committing an empty profile.
        -- (ResetCurrentProfile reverts to the Blizzard default, which isn't "remove
        -- all"; SetProfileByInfo is the real save/commit API.)
        if C_ClickBindings and C_ClickBindings.SetProfileByInfo then
            C_ClickBindings.SetProfileByInfo({})
        end
    end
end
