local _, MySlot = ...
local T = MySlot.test
local Host = MySlot.host

-- RunAsync is pure control flow (coroutine stepping + callback semantics), so we
-- exercise it in CI / standalone only. Running it in-game would route the
-- deliberate error-path test through WoW's real geterrorhandler() and pop a red
-- error frame mid-suite; CI's print-based fallback keeps it noise-free here.
if Host.in_wow then return end

-- Drive RunAsync deterministically by injecting a C_Timer whose After() runs the
-- next step immediately, so the coroutine path completes within the test. Saved
-- and restored around the body so we never leak the stub into other cases.
local function with_immediate_timer(fn)
    local saved = _G.C_Timer
    _G.C_Timer = { After = function(_, cb) cb() end }
    local ok, err = pcall(fn)
    _G.C_Timer = saved
    if not ok then error(err) end
end

T.describe("RunAsync (async runner)", function()

    T.it("runs fn to completion and reports onDone(true)", function()
        with_immediate_timer(function()
            local ran, doneOk = false, nil
            MySlot:RunAsync(function() ran = true end, nil, function(ok) doneOk = ok end)
            T.assert.is_true(ran)
            T.assert.equal(true, doneOk)
        end)
    end)

    T.it("forwards progress fractions yielded via MaybeYield/coroutine.yield", function()
        with_immediate_timer(function()
            local seen = {}
            MySlot:RunAsync(function()
                coroutine.yield(0.25)
                coroutine.yield(0.5)
                coroutine.yield(0.75)
            end, function(p) seen[#seen + 1] = p end, nil)
            -- The three yielded fractions, then a final 1 emitted on completion.
            T.assert.equal(0.25, seen[1])
            T.assert.equal(0.5,  seen[2])
            T.assert.equal(0.75, seen[3])
            T.assert.equal(1,    seen[#seen])
        end)
    end)

    T.it("reports onDone(false) and does not rethrow when fn errors", function()
        with_immediate_timer(function()
            -- geterrorhandler resolves to print() in CI; swallow it so the error
            -- message doesn't pollute test output. The framework keeps its own
            -- printer reference, so this swap doesn't affect result reporting.
            local savedPrint = _G.print
            _G.print = function() end
            local doneOk
            local ok, err = pcall(function()
                MySlot:RunAsync(function() error("boom") end, nil, function(o) doneOk = o end)
            end)
            _G.print = savedPrint
            if not ok then error(err) end
            T.assert.equal(false, doneOk)
        end)
    end)

    T.it("falls back to synchronous execution when no C_Timer is available", function()
        local saved = _G.C_Timer
        _G.C_Timer = nil
        local ran, doneOk = false, nil
        MySlot:RunAsync(function() ran = true end, nil, function(ok) doneOk = ok end)
        _G.C_Timer = saved
        T.assert.is_true(ran)
        T.assert.equal(true, doneOk)
    end)

end)

T.describe("test name filtering", function()

    local function with_test_suites(fn)
        local savedSuites = T._suites
        T._suites = {
            {
                name = "Mount suite",
                tests = {
                    { name = "restores mount", fn = function() end },
                    { name = "unrelated case", fn = function() end },
                },
            },
            {
                name = "Other suite",
                tests = {
                    { name = "ignored case", fn = function() error("must not run") end },
                },
            },
        }
        local ok, err = pcall(fn)
        T._suites = savedSuites
        if not ok then error(err) end
    end

    T.it("filters synchronous runs by suite and test name", function()
        with_test_suites(function()
            local passed, failed, _, selected = T.run(function() end, nil, "RESTORES MOUNT")
            T.assert.equal(1, passed)
            T.assert.equal(0, failed)
            T.assert.equal(1, selected)
        end)
    end)

    T.it("filters asynchronous runs by suite and test name", function()
        with_test_suites(function()
            with_immediate_timer(function()
                local result
                T.run(function() end, function(passed, failed, _, selected)
                    result = { passed, failed, selected }
                end, "mount suite")
                T.assert.same({ 2, 0, 2 }, result)
            end)
        end)
    end)

end)
