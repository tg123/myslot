-- Tiny shared test framework. Loaded as a regular Myslot addon file via the
-- packager #@debug@ block, so it has direct access to the MySlot upvalue.
-- In CI, the loader feeds the same (addon_name, MySlot) varargs.

local _, MySlot = ...

local T = {}
T._suites = {}
T._current = nil

function T.describe(name, fn)
    local suite = { name = name, tests = {} }
    table.insert(T._suites, suite)
    T._current = suite
    fn()
    T._current = nil
end

function T.it(name, fn)
    assert(T._current, "it() must be called inside describe()")
    table.insert(T._current.tests, { name = name, fn = fn })
end

local SKIP_MARKER = {}
function T.skip(reason)
    error({ _skip = SKIP_MARKER, reason = reason or "skipped" })
end

local function fmt(v)
    local tv = type(v)
    if tv == "string" then return string.format("%q", v) end
    if tv == "table" then
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = tostring(k) .. "=" .. fmt(x)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end
T._fmt = fmt

local function deep_eq(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not deep_eq(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
T.deep_eq = deep_eq

T.assert = {}
function T.assert.is_true(v, msg)
    if not v then error((msg or "expected true") .. " (got " .. fmt(v) .. ")", 2) end
end
function T.assert.is_false(v, msg)
    if v then error((msg or "expected false") .. " (got " .. fmt(v) .. ")", 2) end
end
function T.assert.equal(expected, actual, msg)
    if expected ~= actual then
        error((msg or "values differ") .. ": expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end
function T.assert.same(expected, actual, msg)
    if not deep_eq(expected, actual) then
        error((msg or "tables differ") .. ": expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end
function T.assert.not_nil(v, msg)
    if v == nil then error(msg or "expected non-nil", 2) end
end

-- printer(line) defaults to print outside WoW, DEFAULT_CHAT_FRAME inside.
-- T.run(printer, on_done):
--   * If on_done is provided, runs async: each test runs in a coroutine and
--     can call T.yield() to break across frames, letting WoW's per-script
--     watchdog reset between heavy phases. on_done(passed, failed, failures)
--     fires when all tests finish.
--   * If on_done is omitted, runs fully synchronously (CI path) and returns
--     (passed, failed, failures) directly.
--
-- T.yield() is a no-op when called outside a coroutine, so tests can use it
-- freely without breaking the CI sync path.

local function schedule(fn)
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, fn)
    else
        fn()
    end
end

function T.yield()
    -- coroutine.running() returns (nil) on the main thread in Lua 5.1, but
    -- (thread, true) on the main thread in LuaJIT. Use the second return
    -- value to detect "is main thread" so this is a true no-op in sync mode.
    local co, is_main = coroutine.running()
    if co and not is_main then coroutine.yield() end
end

-- Yield-safe pcall replacement. Lua 5.1 (and therefore WoW) cannot yield
-- across a pcall boundary, but tests need both: cleanup-on-failure AND the
-- ability to yield mid-test to dodge the script-runtime watchdog. We run
-- the body in a child coroutine, bubbling its yields up to the framework's
-- driver coroutine and capturing any error when the child dies.
function T.safe_run(fn, ...)
    local co = coroutine.create(fn)
    local args = { ... }
    while true do
        local results = { coroutine.resume(co, unpack(args)) }
        local ok = results[1]
        if not ok then
            return false, results[2]
        end
        if coroutine.status(co) == "dead" then
            return true
        end
        -- Child yielded; propagate up so the framework's driver schedules
        -- a frame, then resume the child with whatever value comes back.
        args = { coroutine.yield(unpack(results, 2)) }
    end
end

local function err_handler(e)
    if type(e) == "table" and e._skip == SKIP_MARKER then return e end
    return tostring(e) .. "\n" .. (debug and debug.traceback("", 2) or "")
end

local function record(state, suite, test, ok, err)
    if ok then
        state.passed = state.passed + 1
        state.printer("  ok   - " .. test.name)
    elseif type(err) == "table" and err._skip == SKIP_MARKER then
        state.skipped = state.skipped + 1
        state.printer("  skip - " .. test.name .. " (" .. tostring(err.reason) .. ")")
    else
        state.failed = state.failed + 1
        table.insert(state.failures,
            { suite = suite.name, name = test.name, err = err })
        state.printer("  FAIL - " .. test.name)
        for line in tostring(err):gmatch("[^\n]+") do
            state.printer("         " .. line)
        end
    end
end

function T.run(printer, on_done)
    printer = printer or function(line)
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage(line)
        else
            print(line)
        end
    end

    local state = {
        printer = printer, passed = 0, failed = 0, skipped = 0, failures = {},
    }

    -- Sync mode: run inline, return counts. Used by CI; safe because the
    -- watchdog is a WoW-only constraint.
    if not on_done then
        for _, suite in ipairs(T._suites) do
            printer("# " .. suite.name)
            for _, test in ipairs(suite.tests) do
                local ok, err = xpcall(test.fn, err_handler)
                record(state, suite, test, ok, err)
            end
        end
        printer(string.format("# %d passed, %d failed, %d skipped",
            state.passed, state.failed, state.skipped))
        return state.passed, state.failed, state.failures
    end

    -- Async mode: walk the suite/test indices via C_Timer ticks so each
    -- coroutine yield gives the WoW runtime a frame to breathe.
    local si, ti = 1, 0
    local function step()
        local suite = T._suites[si]
        if not suite then
            printer(string.format("# %d passed, %d failed, %d skipped",
                state.passed, state.failed, state.skipped))
            on_done(state.passed, state.failed, state.failures)
            return
        end
        if ti == 0 then printer("# " .. suite.name) end
        ti = ti + 1
        local test = suite.tests[ti]
        if not test then
            si, ti = si + 1, 0
            return schedule(step)
        end

        local co = coroutine.create(test.fn)
        local function pump()
            local ok, err = coroutine.resume(co)
            if coroutine.status(co) == "suspended" then
                -- Test yielded; give the engine a frame, then resume.
                return schedule(pump)
            end
            -- coroutine.resume swallows the error into (false, err);
            -- mimic xpcall's err_handler shape for skip/trace formatting.
            if not ok then err = err_handler(err) end
            record(state, suite, test, ok, err)
            schedule(step)
        end
        pump()
    end
    step()
end

function T.reset()
    T._suites = {}
    T._current = nil
end

MySlot.test = T
