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
function T.run(printer)
    printer = printer or function(line)
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage(line)
        else
            print(line)
        end
    end
    local passed, failed = 0, 0
    local failures = {}
    for _, suite in ipairs(T._suites) do
        printer("# " .. suite.name)
        for _, test in ipairs(suite.tests) do
            local ok, err = xpcall(test.fn, function(e)
                return tostring(e) .. "\n" .. (debug and debug.traceback("", 2) or "")
            end)
            if ok then
                passed = passed + 1
                printer("  ok   - " .. test.name)
            else
                failed = failed + 1
                table.insert(failures, { suite = suite.name, name = test.name, err = err })
                printer("  FAIL - " .. test.name)
                for line in tostring(err):gmatch("[^\n]+") do
                    printer("         " .. line)
                end
            end
        end
    end
    printer(string.format("# %d passed, %d failed", passed, failed))
    return passed, failed, failures
end

function T.reset()
    T._suites = {}
    T._current = nil
end

MySlot.test = T
