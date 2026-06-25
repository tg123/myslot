-- CI entry point.
--   1. Load WoW API stubs (defines IsWindowsClient, GetActionInfo, ...).
--   2. Load Myslot addon files via the loader (simulates WoW addon load).
--   3. Load the test framework + host plugin + every test case file.
--   4. Run the suite. Exit nonzero if anything failed.
--
-- Run from repo root:    lua5.1 ci/run.lua   (luabitop required)
--                     or luajit ci/run.lua

dofile((arg[0]:match("(.-)[/\\][^/\\]+$") or ".") .. "/wow_stubs.lua")

local MySlot = dofile((arg[0]:match("(.-)[/\\][^/\\]+$") or ".") .. "/loader.lua")

-- Same calling convention as addon files.
local function load_test(rel)
    local path = "tests/" .. rel
    local chunk, err = loadfile(path)
    if not chunk then
        io.stderr:write("loadfile failed: " .. path .. ": " .. tostring(err) .. "\n")
        os.exit(2)
    end
    local ok, runerr = pcall(chunk, "Myslot", MySlot)
    if not ok then
        io.stderr:write("execute failed: " .. path .. ": " .. tostring(runerr) .. "\n")
        os.exit(2)
    end
end

load_test("framework.lua")
load_test("host.lua")
load_test("cases/base64.lua")
load_test("cases/crc32.lua")
load_test("cases/protobuf.lua")
load_test("cases/roundtrip.lua")
load_test("cases/runasync.lua")
load_test("cases/wow_roundtrip.lua")

local _, failed = MySlot.test.run(print)
os.exit(failed == 0 and 0 or 1)
