-- CI-only addon loader. Honors Myslot.toc: parses the TOC, recurses into
-- referenced XML (lua-pb), and loads each file with the same
-- (addon_name, shared_table) varargs WoW provides. Skips files that
-- require WoW UI APIs not worth stubbing for data-layer tests.

local ADDON_NAME = "Myslot"
local MySlot = {}

-- Files that need WoW UI/event/Lib APIs and contribute no data-layer
-- behaviour under test. Skipped at load time; if you add coverage for
-- any of these, remove from this set and extend ci/wow_stubs.lua.
local SKIP = {
    ["event.lua"]   = true,
    ["gui.lua"]     = true,
    ["options.lua"] = true,
    ["libs/LibStub/LibStub.lua"]                          = true,
    ["libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"]  = true,
    ["libs/LibDataBroker-1.1/LibDataBroker-1.1.lua"]      = true,
    ["libs/LibDBIcon-1.0/LibDBIcon-1.0.lua"]              = true,
}

-- Files that get loaded by ci/run.lua directly (the test harness itself);
-- skipped here so honoring the #@debug@ block in Myslot.toc remains a no-op
-- if someone removes #@debug@ markers.
local function is_test_file(p)
    return p:match("^tests/") ~= nil
end

local function normalize(p) return (p:gsub("\\", "/")) end

local function read_lines(path)
    local f, err = io.open(path, "r")
    if not f then error("cannot open " .. path .. ": " .. tostring(err), 0) end
    local lines = {}
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()
    return lines
end

local REPO_ROOT

local load_one  -- forward decl
local function load_xml(addon_xml)
    local xml_dir = addon_xml:match("(.+)/[^/]+$") or ""
    for _, line in ipairs(read_lines(REPO_ROOT .. "/" .. addon_xml)) do
        local f = line:match('<Script%s+file="([^"]+)"')
        if f then
            load_one((xml_dir == "" and "" or xml_dir .. "/") .. normalize(f))
        end
    end
end

function load_one(addon_path)
    addon_path = normalize(addon_path)
    if SKIP[addon_path] or is_test_file(addon_path) then return end
    if addon_path:match("%.xml$") then return load_xml(addon_path) end

    local full = REPO_ROOT .. "/" .. addon_path
    local chunk, err = loadfile(full)
    if not chunk then
        io.stderr:write("loadfile failed: " .. full .. ": " .. tostring(err) .. "\n")
        os.exit(2)
    end
    local ok, runerr = pcall(chunk, ADDON_NAME, MySlot)
    if not ok then
        io.stderr:write("execute failed: " .. full .. ": " .. tostring(runerr) .. "\n")
        os.exit(2)
    end
end

local function load_toc(toc_path)
    local in_debug = false
    for _, raw in ipairs(read_lines(REPO_ROOT .. "/" .. toc_path)) do
        local line = raw:gsub("\r$", ""):match("^%s*(.-)%s*$")
        if line == "" then
            -- blank
        elseif line:match("^#@debug@") then
            in_debug = true
        elseif line:match("^#@end%-debug@") then
            in_debug = false
        elseif line:sub(1, 1) == "#" then
            -- directive (## Foo) or BigWigs token (#@x@) or plain comment
        elseif not in_debug then
            load_one(line)
        end
    end
end

-- Repo root = directory containing this loader's parent.
local here = arg and arg[0] and arg[0]:match("(.-)[/\\][^/\\]+$") or "."
REPO_ROOT = here .. "/.."

load_toc("Myslot.toc")
return MySlot
