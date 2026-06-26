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
    Stub.cooldown_moves = {}     -- [cooldownID] = category the cooldown was moved to
    Stub.cooldown_saved = false  -- set when SaveCurrentLayout runs
    Stub.click_bindings = {}     -- vector of ClickBindingInfo {type, actionID, button, modifiers}
end

Stub.reset()

-- --- Client info -----------------------------------------------------------
function IsWindowsClient() return Stub.is_windows end
function IsWindowsServer() return Stub.is_windows end
function GetLocale() return Stub.locale end
function GetBuildInfo() return "11.0.0", "00000", "2024-01-01", 110000 end
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
MAX_ACCOUNT_MACROS = 120
MAX_CHARACTER_MACROS = 18
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

-- Minimal settings frame so MySlot can drive drag-to-"Not Displayed" moves.
local cooldownDataProvider = {
    SetCooldownToCategory = function(_self, cooldownID, category)
        Stub.cooldown_moves[cooldownID] = category
    end,
}
CooldownViewerSettings = {
    GetDataProvider = function() return cooldownDataProvider end,
    SaveCurrentLayout = function() Stub.cooldown_saved = true end,
    RefreshLayout = function() end,
}

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
