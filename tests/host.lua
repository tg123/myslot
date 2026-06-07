-- Host data plugin: uniform API for tests to seed/inspect "host" state.
-- Same calls work in CI (stubs) and in-game (real WoW APIs).
-- Loaded as a regular Myslot addon file via the packager #@debug@ block.

local _, MySlot = ...

local Host = {}

-- Detect environment: presence of _G.WowStub means CI loader is active.
local in_wow = _G.WowStub == nil
Host.in_wow = in_wow

if in_wow then
    -- ============================================================
    -- In-game backend. Mutates real bars/macros/bindings, so tests
    -- MUST pair snapshot()/restore() to leave the character intact.
    -- ============================================================

    function Host.snapshot()
        return MySlot:Export({
            ignoreActionBars = {},
            ignoreMacros = {},
            ignoreBinding = false,
            ignorePetActionBar = false,
        })
    end

    function Host.restore(snap)
        if not snap then return end
        local msg = MySlot:Import(snap, { force = true })
        if msg then
            MySlot:RecoverData(msg, {
                actionOpt = {
                    ignoreActionBars = {},
                    ignoreMacros = {},
                    ignoreBinding = false,
                    ignorePetActionBar = false,
                },
            })
        end
    end

    function Host.set_action(slot, kind, index)
        ClearCursor()
        if kind == "spell" then
            (C_Spell and C_Spell.PickupSpell or _G.PickupSpell)(index)
        elseif kind == "item" then
            (C_Item and C_Item.PickupItem or _G.PickupItem)(index)
        elseif kind == "macro" then
            PickupMacro(index)
        elseif kind == "empty" then
            PickupAction(slot)
            ClearCursor()
            return
        end
        PlaceAction(slot)
        ClearCursor()
    end

    function Host.get_action(slot) return GetActionInfo(slot) end

    function Host.clear_action(slot)
        PickupAction(slot)
        ClearCursor()
    end

    function Host.set_macro(name, icon, body)
        return CreateMacro(name, icon, body, nil)
    end

    function Host.delete_macro(id) DeleteMacro(id) end

    function Host.set_binding(key, command)
        SetBinding(key, command)
        SaveBindings(GetCurrentBindingSet())
    end

    function Host.player_name() return UnitName("player") end

else
    -- ============================================================
    -- CI backend: pokes _G.WowStub tables. Pure in-memory.
    -- ============================================================
    local S = _G.WowStub

    local function deep_copy(t)
        local r = {}
        for k, v in pairs(t) do
            if type(v) == "table" then
                local inner = {}
                for k2, v2 in pairs(v) do inner[k2] = v2 end
                r[k] = inner
            else
                r[k] = v
            end
        end
        return r
    end

    function Host.snapshot()
        return {
            action_bars = deep_copy(S.action_bars),
            macros      = deep_copy(S.macros),
            bindings    = deep_copy(S.bindings),
            player      = deep_copy(S.player),
        }
    end

    function Host.restore(snap)
        S.reset()
        if not snap then return end
        for k, v in pairs(snap.action_bars or {}) do S.action_bars[k] = v end
        for k, v in pairs(snap.macros      or {}) do S.macros[k]      = v end
        for k, v in pairs(snap.bindings    or {}) do S.bindings[k]    = v end
        for k, v in pairs(snap.player      or {}) do S.player[k]      = v end
    end

    function Host.set_action(slot, kind, index, subType)
        S.action_bars[slot] = { type = kind, index = index, subType = subType }
    end

    function Host.get_action(slot)
        local s = S.action_bars[slot]
        if not s then return nil end
        return s.type, s.index, s.subType
    end

    function Host.clear_action(slot) S.action_bars[slot] = nil end

    function Host.set_macro(name, icon, body)
        local id = #S.macros + 1
        S.macros[id] = { name = name, icon = icon, body = body }
        return id
    end

    function Host.delete_macro(id) S.macros[id] = nil end

    function Host.set_binding(key, command)
        table.insert(S.bindings, {
            action = command, header = nil, key1 = key, key2 = nil,
        })
    end

    function Host.set_player(name, class, level)
        if name  then S.player.name  = name  end
        if class then S.player.class = class end
        if level then S.player.level = level end
    end

    function Host.player_name() return S.player.name end
end

function Host.reset()
    if not in_wow then _G.WowStub.reset() end
    -- In-game callers use snapshot()/restore() instead.
end

MySlot.host = Host
