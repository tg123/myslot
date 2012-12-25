--[[
	parse MySlot.proto to ast
]]


local s = require("lua-pb.saveast")
local proto_parser = require("lua-pb.pb.proto.parser")


local f = assert(io.open('MySlot.proto'))
local text = f:read("*a")
f:close()


local ast = proto_parser.parse(text)
s.save(ast, 'PbMySlot.lua', [[
local _, MySlot = ...
]],[[
MySlot.ast = loadast()
]])


