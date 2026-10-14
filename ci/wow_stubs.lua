-- Minimal WoW API stubs sufficient to load Myslot's serialization layer
-- (libs/base64, libs/crc32, lua-pb, protobuf/Myslot, locales, keys, Myslot.lua
-- and exercise Export/Import round-trip).
--
-- Anything not stubbed here is intentionally left nil; Myslot guards most
-- runtime APIs behind `C_X and C_X.Y or _G.Y` checks. APIs that are only
-- touched by RecoverData / Clear / GUI / event registration are NOT stubbed,
-- because the CI suite focuses on the data path (Export -> text -> Import).

-- bit library: LuaJIT provides bit natively. Plain Lua 5.1 needs luabitop.
if not bit then
    local ok, b = pcall(require, "bit")
    if ok then bit = b end
end
assert(bit, "bit library required (use LuaJIT or install luabitop)")

-- Mutable fake game state. Tests reseed via _G.WowStub.reset().
local Stub = {}
_G.WowStub = Stub

function Stub.reset()
    Stub.in_combat = false
    Stub.printed = {}
    Stub.locale = "enUS"
    Stub.is_windows = false
    Stub.player = {
        name = "Tester",
        class = "WARRIOR",
        level = 80,
    }
    Stub.action_bars = {}     -- [slotId] = { type, index, subType }
    Stub.macros = {}          -- [macroId] = { name, icon, body }
    Stub.bindings = {}        -- [i] = { action, header, key1, key2 }
    Stub.pet_active = false
    Stub.cooldown_layout = nil  -- opaque Cooldown Manager layout blob
    -- Base category membership returned by GetCooldownViewerCategorySet:
    --   Essential=0, Utility=1, TrackedBuff=2, TrackedBar=3
    Stub.cooldown_category_set = {
        [0] = { 101, 102 },
        [1] = { 201 },
        [2] = { 301 },
        [3] = { 401 },
    }
    Stub.cooldown_categories = {
        [101] = 0,
        [102] = 0,
        [201] = 1,
        [301] = 2,
        [401] = 3,
        [999] = 0, -- Custom active-layout entry absent from the default category set.
    }
    Stub.cooldown_moves = {}     -- [cooldownID] = category the cooldown was moved to
    Stub.cooldown_settings_shown = false  -- is Blizzard's Cooldown Manager panel open?
    Stub.cooldown_spec_tag = 11  -- classID * 10 + spec (Arms Warrior)
    Stub.cooldown_addon_loaded = true  -- Blizzard_CooldownViewer loaded? (retail=true)
    Stub.click_bindings = {}     -- vector of ClickBindingInfo {type, actionID, button, modifiers}
    Stub.interface_version = 110000  -- 4th GetBuildInfo() return (retail Mainline)
end

Stub.reset()

-- --- Client info -----------------------------------------------------------
function IsWindowsClient() return Stub.is_windows end
function IsWindowsServer() return Stub.is_windows end
function GetLocale() return Stub.locale end
function GetBuildInfo() return "11.0.0", "00000", "2024-01-01", Stub.interface_version end
function InCombatLockdown() return Stub.in_combat end

-- --- Chat / UI -------------------------------------------------------------
DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg)
        table.insert(Stub.printed, msg)
    end,
}

-- Globally referenced UI strings/constants ---------------------------------
LEVEL = "Level"
TALENTS = "Talents"
SPECIALIZATION = "Specialization"
NONE_CAPS = "NONE"
CLASS = "Class"
PLAYER = "Player"
Constants = {
    MacroConsts = {
        MAX_ACCOUNT_MACROS = 120,
        MAX_CHARACTER_MACROS = 30,
    },
}
NUM_PET_ACTION_SLOTS = 10

-- --- Player info -----------------------------------------------------------
function UnitName(unit)
    if unit == "player" then return Stub.player.name end
end
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6,
    SHAMAN = 7, MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13 }
function UnitClass(unit)
    if unit == "player" then return Stub.player.class, Stub.player.class, CLASS_IDS[Stub.player.class] end
end
function UnitLevel(unit)
    if unit == "player" then return Stub.player.level end
end

-- --- Macros ----------------------------------------------------------------
function GetMacroInfo(id)
    local m = Stub.macros[id]
    if not m then return nil end
    return m.name, m.icon, m.body
end
function GetNumMacros() return 0, 0 end

-- --- Action bars -----------------------------------------------------------
function GetActionInfo(slotId)
    local s = Stub.action_bars[slotId]
    if not s then return nil end
    return s.type, s.index, s.subType
end

-- --- Pet -------------------------------------------------------------------
function IsPetActive() return Stub.pet_active end
function GetPetActionInfo() return nil end

-- --- Secure hooks ----------------------------------------------------------
function hooksecurefunc(target, name, hook)
    if type(target) == "string" then
        target, name, hook = _G, target, name
    end
    local original = target[name]
    target[name] = function(...)
        local results = { original(...) }
        hook(...)
        return unpack(results)
    end
end

-- --- Cooldown Manager (Cooldown Viewer) ------------------------------------
-- Opaque layout blob passthrough: Export reads it, Import writes it back.
C_CooldownViewer = {
    GetLayoutData = function() return Stub.cooldown_layout end,
    SetLayoutData = function(data) Stub.cooldown_layout = data end,
    GetCooldownViewerCategorySet = function(category, _allowUnlearned)
        return Stub.cooldown_category_set[category] or {}
    end,
}

-- C_AddOns.IsAddOnLoaded gates Cooldown Manager support: Blizzard_CooldownViewer
-- only loads on retail ("## AllowLoadGameType: standard"), while the
-- C_CooldownViewer C-namespace is present on Classic too. Tests can flip
-- Stub.cooldown_addon_loaded = false to simulate a Classic client.
C_AddOns = C_AddOns or {}
C_AddOns.IsAddOnLoaded = C_AddOns.IsAddOnLoaded or function(name)
    if name == "Blizzard_CooldownViewer" then
        return Stub.cooldown_addon_loaded ~= false
    end
    return true
end

-- Pseudo-categories used by the settings UI to represent "Not Displayed".
Enum = Enum or {}
Enum.CooldownViewerCategory = {
    Essential = 0,
    Utility = 1,
    TrackedBuff = 2,
    TrackedBar = 3,
    HiddenSpell = -1,
    HiddenAura = -2,
}

CreateFromMixins = CreateFromMixins or function(...)
    local object = {}
    for i = 1, select("#", ...) do
        for k, v in pairs((select(i, ...))) do
            object[k] = v
        end
    end
    return object
end

-- Cut-down stand-ins for Blizzard's Cooldown Manager settings mixins. MySlot
-- instantiates private copies of these to read and rebuild the layout blob, so the
-- live CooldownViewerSettings objects are never written (that taints them, #133).
-- Layouts mirror Blizzard's fields (layoutID, layoutName, classAndSpecTag), with
-- `overrides` = { [cooldownID] = category } standing in for cooldownInfo. Blob
-- format: "stub|" .. Lua literal of { layouts = {...}, active = { [specTag] = id } },
-- where id 0 means "Blizzard's default layout". At most 5 layouts per character.
local COOLDOWN_DEFAULT_LAYOUT_ID = 0
local COOLDOWN_MAX_LAYOUTS = 5

local function SerializeValue(v)
    if type(v) == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = "[" .. SerializeValue(k) .. "]=" .. SerializeValue(v[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return type(v) == "string" and string.format("%q", v) or tostring(v)
end

function Stub.encode_cooldown_blob(data)
    return "stub|" .. SerializeValue(data)
end

function Stub.decode_cooldown_blob(blob)
    local payload = (blob or ""):match("^stub|(.*)$")
    if not payload then
        return { layouts = {}, active = {} }
    end
    local data = loadstring("return " .. payload)()
    data.layouts = data.layouts or {}
    data.active = data.active or {}
    return data
end

local function CopyDeep(t)
    local r = {}
    for k, v in pairs(t) do r[k] = type(v) == "table" and CopyDeep(v) or v end
    return r
end

function CooldownManagerLayout_GetID(layout) return layout.layoutID end
function CooldownManagerLayout_GetName(layout) return layout.layoutName or "" end
function CooldownManagerLayout_SetName(layout, name) layout.layoutName = name end
function CooldownManagerLayout_GetClassAndSpecTag(layout) return layout.classAndSpecTag end

CooldownViewerLayoutManagerMixin = {
    Init = function(self, dataProvider, serializer)
        self.dataProvider = dataProvider
        self.serializer = serializer
        self.layouts = {}
        self.lastActive = {}
    end,
    SetHasPendingChanges = function(self, hasPendingChanges)
        self.hasPendingChanges = hasPendingChanges
    end,
    SaveLayouts = function(self)
        local hadSomethingToSave = self.hasPendingChanges
        if hadSomethingToSave then
            self.serializer:WriteData()
        end
        self:SetHasPendingChanges(false)
        return hadSomethingToSave
    end,
    GetCurrentSpecTag = function() return Stub.cooldown_spec_tag end,
    GetActiveLayoutID = function(self) return self.activeLayoutID end,
    GetActiveLayout = function(self) return self.activeLayoutID and self.layouts[self.activeLayoutID] end,
    GetLayout = function(self, layoutID) return self.layouts[layoutID] end,
    EnumerateLayouts = function(self) return pairs(self.layouts) end,
    EnumeratePreviouslyActiveLayoutIDs = function(self) return pairs(self.lastActive) end,
    IsDefaultLayoutID = function(_, layoutID) return layoutID == COOLDOWN_DEFAULT_LAYOUT_ID end,
    SetPreviouslyActiveLayout = function(self, layout)
        self.lastActive[layout.classAndSpecTag] = layout.layoutID
    end,
    SetPreviouslyActiveLayoutForSpecToDefault = function(self, specTag)
        self.lastActive[specTag] = COOLDOWN_DEFAULT_LAYOUT_ID
    end,
    RemoveLayout = function(self, layoutID)
        local layout = self.layouts[layoutID]
        if not layout then return end
        if self.activeLayoutID == layoutID then self.activeLayoutID = nil end
        if self.lastActive[layout.classAndSpecTag] == layoutID then
            self.lastActive[layout.classAndSpecTag] = nil
        end
        self.layouts[layoutID] = nil
        self:SetHasPendingChanges(true)
    end,
    AreLayoutsFullyMaxed = function(self)
        local count = 0
        for _ in pairs(self.layouts) do count = count + 1 end
        return count >= COOLDOWN_MAX_LAYOUTS
    end,
    NextLayoutID = function(self)
        local largest = 0
        for layoutID in pairs(self.layouts) do largest = math.max(largest, layoutID) end
        return largest + 1
    end,
    CopyLayout = function(self, layout)
        local copy = CopyDeep(layout)
        copy.layoutID = self:NextLayoutID()
        return copy
    end,
    CheckAddFullLayout = function(self, layout)
        self.layouts[layout.layoutID] = layout
        self:SetHasPendingChanges(true)
        return layout
    end,
    SwitchToBestLayoutForSpec = function(self)
        local specTag = self:GetCurrentSpecTag()
        local layoutID = self.lastActive[specTag]
        if layoutID == COOLDOWN_DEFAULT_LAYOUT_ID then
            self.activeLayoutID = nil
            return
        end
        if not self.layouts[layoutID] then
            layoutID = nil
            for id, layout in pairs(self.layouts) do
                if layout.classAndSpecTag == specTag and (not layoutID or id < layoutID) then
                    layoutID = id
                end
            end
        end
        self.activeLayoutID = layoutID
        if layoutID then
            self.lastActive[specTag] = layoutID
        end
    end,
}

CooldownViewerDataStoreSerializationMixin = {
    Init = function(self, layoutManager, persistenceObject)
        self.layoutManager = layoutManager
        self.persistenceObject = persistenceObject
        local data = Stub.decode_cooldown_blob(persistenceObject:GetSerializedData())
        layoutManager.layouts = data.layouts
        layoutManager.lastActive = data.active
    end,
    WriteData = function(self)
        self.persistenceObject:SetSerializedData(self:SerializeLayouts())
    end,
    SerializeLayouts = function(self, singleLayoutID)
        local layoutManager = self.layoutManager
        if singleLayoutID then
            return Stub.encode_cooldown_blob({
                layouts = { [singleLayoutID] = layoutManager.layouts[singleLayoutID] },
                active = {},
            })
        end
        return Stub.encode_cooldown_blob({ layouts = layoutManager.layouts, active = layoutManager.lastActive })
    end,
}

CooldownViewerSettingsDataProviderMixin = {
    SetLayoutManager = function(self, layoutManager) self.layoutManager = layoutManager end,
    GetOrderedCooldownIDs = function() return {} end,
    SwitchToBestLayoutForSpec = function(self)
        self.layoutManager:SwitchToBestLayoutForSpec()
    end,
    GetOrderedCooldownIDsForCategory = function(self, category, _allowUnknown)
        local active = self.layoutManager:GetActiveLayout()
        local overrides = active and active.overrides or {}
        local cooldownIDs = {}
        for cooldownID, defaultCategory in pairs(Stub.cooldown_categories) do
            if (overrides[cooldownID] or defaultCategory) == category then
                cooldownIDs[#cooldownIDs + 1] = cooldownID
            end
        end
        return cooldownIDs
    end,
    -- Like Blizzard, editing while on the default layout creates a layout for it.
    SetCooldownToCategory = function(self, cooldownID, category)
        local layoutManager = self.layoutManager
        local active = layoutManager:GetActiveLayout()
        if not active then
            active = {
                layoutID = layoutManager:NextLayoutID(),
                classAndSpecTag = layoutManager:GetCurrentSpecTag(),
                overrides = {},
            }
            layoutManager:CheckAddFullLayout(active)
            layoutManager.activeLayoutID = active.layoutID
            layoutManager:SetPreviouslyActiveLayout(active)
        end
        Stub.cooldown_moves[cooldownID] = category
        active.overrides = active.overrides or {}
        active.overrides[cooldownID] = category
        layoutManager:SetHasPendingChanges(true)
    end,
}

-- The live Cooldown Manager objects. MySlot must never touch them: any write
-- from addon code taints Blizzard's state until /reload (#133). Only the listed
-- read-only methods are allowed.
local function Untouchable(name, allowed)
    return setmetatable({}, {
        __index = function(_, key)
            if allowed and allowed[key] then
                return allowed[key]
            end
            error(("MySlot touched live %s.%s"):format(name, tostring(key)), 2)
        end,
        __newindex = function(_, key)
            error(("MySlot wrote live %s.%s"):format(name, tostring(key)), 2)
        end,
    })
end

CooldownViewerSettings = Untouchable("CooldownViewerSettings", {
    IsShown = function() return Stub.cooldown_settings_shown end,
})

for _, frameName in ipairs({
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}) do
    _G[frameName] = Untouchable(frameName)
end

-- --- Click Cast Bindings ---------------------------------------------------
-- Profile passthrough: Export reads the vector, Import writes it back.
Enum.ClickBindingType = {
    None = 0,
    Spell = 1,
    Macro = 2,
    Interaction = 3,
    PetAction = 4,
}

C_ClickBindings = {
    GetProfileInfo = function() return Stub.click_bindings end,
    SetProfileByInfo = function(info) Stub.click_bindings = info end,
    ResetCurrentProfile = function() Stub.click_bindings = {} end,
}

-- --- Bindings --------------------------------------------------------------
function GetNumBindings() return #Stub.bindings end
function GetBinding(i)
    local b = Stub.bindings[i]
    if not b then return nil end
    return b.action, b.header, b.key1, b.key2
end
function GetCurrentBindingSet() return 1 end

-- --- Lua-side string helpers WoW exposes globally --------------------------
strtrim = strtrim or function(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
strsub = strsub or string.sub
strupper = strupper or string.upper
gsub = gsub or string.gsub

-- --- Frame stub (event.lua uses CreateFrame; we don't load event.lua in CI,
-- --- but provide a no-op anyway in case future tests load it). -------------
function CreateFrame()
    local f = {}
    function f:SetScript() end
    function f:RegisterEvent() end
    return f
end

-- Used by Myslot.lua top-level for the version banner; safe defaults.
function date() return "1970-01-01" end

return Stub
