MySlot = LibStub:NewLibrary("MySlot-4.0", 4)

local crc32 = LibStub:GetLibrary('CRC32-1.0')
local base64 = LibStub:GetLibrary('BASE64-1.0')

local MYSLOT_AUTHOR = "T.G. <farmer1992@gmail.com>"

local MYSLOT_VER = 10
local MYSLOT_ALLOW_VER = {6,10}

-- 不能大于 7 不含
local MYSLOT_SPELL = 1
local MYSLOT_ITEM = 4
local MYSLOT_MACRO = 3
local MYSLOT_FLYOUT = 5
local MYSLOT_EQUIPMENTSET = 6
local MYSLOT_EMPTY = 0
local MYSLOT_NOTFOUND = "notfound"

MySlot.SLOT_TYPE = {
	["spell"] = MYSLOT_SPELL,
	["companion"] = MYSLOT_SPELL,
	["macro"]= MYSLOT_MACRO,
	["item"]= MYSLOT_ITEM,
	["flyout"] = MYSLOT_FLYOUT,	
	["petaction"] = MYSLOT_EMPTY,
	["futurespell"] = MYSLOT_EMPTY,
	["equipmentset"] = MYSLOT_EQUIPMENTSET,
	[MYSLOT_NOTFOUND] = MYSLOT_EMPTY,
}

local function GetMacroIconTable()
	local t = {}
	for i =1,GetNumMacroIcons() do
		t[GetMacroIconInfo(i)] = i
	end
	return t
end
MySlot.MACRO_ICON_TABLE = GetMacroIconTable()


local function MergeTable(target, source)
	if type target == 'Table' then
		if source then
			for _,b in ipairs(source) do
				target[#target+1] = b
			end
		end
	end
end

function MySlot:Debug()
	
--[[	for i= 1,54 do
	local name, iconTexture, body, isLocal = MySlot:GetMacroInfo(i)
	
		if name then
			--self:Print(i)
			--self:Print(iconTexture)
		end
	end]]

			--self:Print(GetNumMacroIcons())

			s = '我'
			--for i=1, string.len(s) do
			
			t = {}	
			--for _,v in pairs({string.byte(s,1,string.len(s))}) do
			--self:Print(v)
			--t[#t + 1] = v
			--end 
			self:Print(string.char(unpack(t)))
		--	for _,b in ipairs(string.byte(s,2,string.len(s))) do
		--	end
end

function MySlot:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|CFFFF0000<|r|CFFFFD100My Slot 4 beta|r|CFFFF0000>|r"..(msg or "nil"))
end

function MySlot:GetMacroInfo(i)
	-- { icon high 8, icon low 8 , namelen, ..., bodylen, ...}

	local t = {}	
	local name, iconTexture, body, isLocal = GetMacroInfo(i)
	iconTexture = MySlot.MACRO_ICON_TABLE[iconTexture]

	-- icon
	t[#t+1] = bit.rshift(iconTexture,8)
	t[#t+1] = bit.band(iconTexture, 255)

	-- name
	local namelen = string.len(name)
	t[#t + 1] = namelen
	for _,b in pairs({string.byte(name ,1 ,namelen)}) do
		t[#t + 1] = b
	end 

	-- body
	local bodylen = string.len(body)
	t[#t + 1] = bodylen 
	for _,b in pairs({string.byte(body , 1 , bodylen)}) do
		t[#t + 1] = b
	end 
	
	return t
end

function MySlot:GetActionInfo(slotId)
	-- { slotId, slotType and high 16 ,high 8 , low 8, }
	local slotType, index = GetActionInfo(slotId)
	if MySlot.SLOT_TYPE[slotType] == MYSLOT_EQUIPMENTSET then
		_, index = GetEquipmentSetInfoByName(index)
		index = index + 1
	elseif not MySlot.SLOT_TYPE[slotType] then
		if slotType then 
			self:Print("忽略不支持的按键类型[" .. slotType .."] 请通知作者" .. MYSLOT_AUTHOR)
		end
		return nil
	end
	return { slotId, MySlot.SLOT_TYPE[slotType] * 32 + bit.rshift(index ,16) , bit.rshift(index,8) , bit.band(index, 255) }
end


local function KeyToByte(key , command)
	-- {mod , key , command high 8, command low 8}
	if not key then
		return nil
	end

	local mod,key = nil, key
	local t = {}
	local _,_,_mod,_key = string.find(key ,"(.+)-(.+)") 
	if _mod and _key then
		mod, key = _mod, _key
	end

	if not MySlot.KEYS[key] then
		MySlot:Print("[WARN]忽略不支持的绑定 K = [" .. key .."]")
		return nil
	end
	mod = mod or "NONE"

	if not MySlot.MOD_KEYS[mod] then
		MySlot:Print("[WARN]忽略不支持的绑定 MK = [" .. key .."]")
		return nil
	end

	t[#t+1] = MySlot.MOD_KEYS[mod]
	t[#t+1] = MySlot.KEYS[key]

	t[#t+1] = bit.rshift(command,8)
	t[#t+1] = bit.band(command, 255)

	return t
end

function MySlot:GetBindingInfo(index)
	-- might more than 1
	local t = {}
	local _command, key1, key2 = GetBinding(index)
	local command = MySlot.BINDS[_command]

	if not command then
		MySlot:Print("[WARN]忽略不支持的绑定 C = " .. _command)
		return nil
	end

	local s  = KeyToByte(key1, command)
	if s then
		for _,b in ipairs(s) do
			t[#t+1] = b
		end
	end

	local s  = KeyToByte(key2, command)
	if s then
		for _,b in ipairs(s) do
			t[#t+1] = b
		end
	end

	return #t > 0 and t or nil
end

function MySlot:Export()
	-- ver nop nop nop crc32 crc32 crc32 crc32
	local t = {MYSLOT_VER,0,0,0,0,0,0,0}
	
	local head = 8
	-- macro
	local c = 0

	-- move head
	head = head + c*4 + 1

	-- spell
	t[head] = 0
	local c = 0
	for i = 1,120 do
		local s = self:GetActionInfo(i)
		if s then
			for _,b in ipairs(s) do
				t[#t+1] = b
			end
			c = c + 1
		end
	end
	t[head] = c

	-- move head
	head = head + c*4 + 1

	-- keys
	t[head] = 0
	t[head + 1] = 0
	local c = 0
	for i = 1,GetNumBindings() do
		local s = self:GetBindingInfo(i)
		if s then
			for _,b in ipairs(s) do
				t[#t+1] = b
			end
			c = c + #s/4
		end
	end
	t[head] = bit.rshift(c,8)
	t[head + 1] = bit.band(c, 255)

	-- crc

	local crc = crc32.enc(t)
	t[5] = bit.rshift(crc , 24)
	t[6] = bit.band(bit.rshift(crc , 16), 255)
	t[7] = bit.band(bit.rshift(crc , 8) , 255)
	t[8] = bit.band(crc , 255)
	
	local s=""
	s = "@ --------------------\n"..s
	s = "@ 问题/建议请联系 farmer1992@gmail.com\n"..s
	s = "@ \n"..s
	s = "@ 等级："..UnitLevel("player").."\n"..s
	s = "@ 职业："..UnitClass("player").."\n"..s
	s = "@ 人物："..UnitName("player").."\n"..s
	-- s = "@ 天赋："..select(3,GetTalentTabInfo(1)).."/"..select(3,GetTalentTabInfo(2)).."/"..select(3,GetTalentTabInfo(3)).."\n"..s
	s = "@ Myslot 导出数据"..date().."\n"..s

	s = s..base64.enc(t)
	MYSLOT_ReportFrame_EditBox:SetText(s)
	MYSLOT_ReportFrame_EditBox:HighlightText()
end

function MySlot:Import()
	if InCombatLockdown() then
		MySlot:Print("请在非战斗时候使用导入功能")
	end

	local s = MYSLOT_ReportFrame_EditBox:GetText() or ""
	s = string.gsub(s,"(@.[^\n]*\n)","")
	s = string.gsub(s,"\n","")
	s = string.gsub(s,"\r","")
	s = base64.dec(s)
	
	if #s < 8  then
		MySlot:Print("导入字符不合法 [TEXT]")
		return
	end

	StaticPopupDialogs["MYSLOT_MSGBOX"].OnAccept=function()
		MySlot:RecoverData(s)
	end
	StaticPopup_Show("MYSLOT_MSGBOX")
end

function MySlot:RecoverData(s)

	local ver = s[1]
	local crc = s[5] * 2^24 + s[6] * 2^16 + s[7] * 2^8 + s[8]
	s[5], s[6], s[7] ,s[8] = 0, 0 ,0 ,0
	
	if ( crc ~= crc32.enc(s)) then
		MySlot:Print("导入字符码校验不合法 [CRC32]")
		return 
	end

	if ver ~= MYSLOT_VER then
		MySlot:Print("导出串版本不兼容")
		return 
	end
	
	local spells = {}
	local head = 1
	local tail

	--cache spells
	local i = 1
	while true do
		local spellType, spellId = GetSpellBookItemInfo(i, BOOKTYPE_SPELL)
		if not spellType then
			break 
		end
		
		spells[MySlot.SLOT_TYPE[string.lower(spellType)] .. "_" .. spellId] = i
		i = i + 1
	end 

	-- cache macro
	local macro

	local spellCount = s[2]
	head = head + 8
	tail = spellCount * 4 + head

	for i = head, tail - 1 ,4 do
		local slotId = s[i]
		local slotType = bit.rshift(s[i+1], 5)
		local index = bit.band(s[i+1],31) * 65536  + (s[i+2] * 256 + s[i+3])
		
		local curType, curIndex = GetActionInfo(slotId)
		curType = MySlot.SLOT_TYPE[curType or MYSLOT_NOTFOUND]
		if curIndex ~= index or curType ~= slotType then
			if slotType == MYSLOT_SPELL or slotType == MYSLOT_FLYOUT then
				local newId = spells[slotType .."_" ..index]
				if newId then
					PickupSpellBookItem(newId, BOOKTYPE_SPELL)
				else
					MySlot:Print("忽略未掌握技能：" .. GetSpellLink(index))	
				end
			elseif slotType == MYSLOT_ITEM then
				PickupItem(index)
			elseif slotType == MYSLOT_MACRO then
				PickupMacro(index)
			elseif slotType == MYSLOT_EMPTY then
				PickupAction(slotId)
			elseif slotType == MYSLOT_EQUIPMENTSET then
				PickupEquipmentSet(slotId)
			end
			PlaceAction(slotId)	
			ClearCursor()
		end
	end

	local bindCount = s[3] * 256 + s[4]
	head = tail
	tail = bindCount * 4 + head
	
	local mode = GetCurrentBindingSet()
	for i = head, tail - 1 ,4 do
		local mod,key,command = MySlot.R_MOD_KEYS[s[i]] , MySlot.R_KEYS[s[i+1]] , MySlot.R_BINDS[s[i+2]*256 + s[i+3]]
		local key = ( mod ~= "NONE" and (mod .. "-") or "" ) .. key
		SetBinding(key ,command, mode)
	end
	SaveBindings(mode)


	MySlot:Print("所有按钮及按键邦定位置恢复完毕")
end

SlashCmdList["Myslot"] = function()
	MYSLOT_ReportFrame:Show()
end
SLASH_Myslot1 = "/Myslot"

StaticPopupDialogs["MYSLOT_MSGBOX"] = {
	text = "你 确定 要导入么？？？",
	button1 = "确定",
	button2 = "取消",
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	multiple = 1,
}
