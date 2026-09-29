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
function UnitClass(unit)
    if unit == "player" then return Stub.player.class, Stub.player.class end
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
-- instantiates private copies of these to rebuild the layout blob, so the live
-- CooldownViewerSettings objects are never written (that taints them, #133).
-- Stub blob format: "stub|<cooldownID>=<category>,..." holding category overrides
-- on top of Stub.cooldown_categories.
local function ParseCooldownBlob(blob)
    local overrides = {}
    for cooldownID, category in (blob or ""):gmatch("(%-?%d+)=(%-?%d+)") do
        overrides[tonumber(cooldownID)] = tonumber(category)
    end
    return overrides
end

local function SerializeCooldownOverrides(overrides)
    local ids = {}
    for cooldownID in pairs(overrides) do ids[#ids + 1] = cooldownID end
    table.sort(ids)
    local parts = {}
    for _, cooldownID in ipairs(ids) do
        parts[#parts + 1] = cooldownID .. "=" .. overrides[cooldownID]
    end
    return "stub|" .. table.concat(parts, ",")
end

CooldownViewerLayoutManagerMixin = {
    Init = function(self, dataProvider, serializer)
        self.dataProvider = dataProvider
        self.serializer = serializer
        self.overrides = {}
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
}

CooldownViewerDataStoreSerializationMixin = {
    Init = function(self, layoutManager, persistenceObject)
        self.layoutManager = layoutManager
        self.persistenceObject = persistenceObject
        layoutManager.overrides = ParseCooldownBlob(persistenceObject:GetSerializedData())
    end,
    WriteData = function(self)
        self.persistenceObject:SetSerializedData(SerializeCooldownOverrides(self.layoutManager.overrides))
    end,
}

CooldownViewerSettingsDataProviderMixin = {
    SetLayoutManager = function(self, layoutManager) self.layoutManager = layoutManager end,
    GetOrderedCooldownIDs = function() return {} end,
    SwitchToBestLayoutForSpec = function() end,
    GetOrderedCooldownIDsForCategory = function(self, category, _allowUnknown)
        local cooldownIDs = {}
        for cooldownID, defaultCategory in pairs(Stub.cooldown_categories) do
            local currentCategory = self.layoutManager.overrides[cooldownID] or defaultCategory
            if currentCategory == category then
                cooldownIDs[#cooldownIDs + 1] = cooldownID
            end
        end
        return cooldownIDs
    end,
    SetCooldownToCategory = function(self, cooldownID, category)
        Stub.cooldown_moves[cooldownID] = category
        self.layoutManager.overrides[cooldownID] = category
        self.layoutManager:SetHasPendingChanges(true)
    end,
}

-- The live Cooldown Manager objects. MySlot must never touch them: any write
-- from addon code taints Blizzard's state until /reload (#133).
local function Untouchable(name)
    return setmetatable({}, {
        __index = function(_, key)
            error(("MySlot touched live %s.%s"):format(name, tostring(key)), 2)
        end,
        __newindex = function(_, key)
            error(("MySlot wrote live %s.%s"):format(name, tostring(key)), 2)
        end,
    })
end

for _, frameName in ipairs({
    "CooldownViewerSettings",
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
