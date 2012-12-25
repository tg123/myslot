local _, MySlot = ...

local L = setmetatable({}, {
	__index = function(table, key)
		if key then
			table[key] = tostring(key)
		end
		return tostring(key)
	end,
})


MySlot.L = L

--
-- Use http://www.wowace.com/addons/myslot/localization/ to translate thanks
-- 
local locale = GetLocale()

if locale == 'enUs' then
--@localization(locale="enUS", format="lua_additive_table", same-key-is-true=true)@
elseif locale == 'deDE' then
--@localization(locale="deDE", format="lua_additive_table", handle-unlocalized="comment")@
elseif locale == 'esES' then
--@localization(locale="esES", format="lua_additive_table", handle-unlocalized="comment")@
elseif locale == 'esMX' then
--@localization(locale="esMX", format="lua_additive_table", handle-unlocalized="comment")@
elseif locale == 'frFR' then
--@localization(locale="frFR", format="lua_additive_table", handle-unlocalized="comment")@
elseif locale == 'itIT' then
--@localization(locale="itIT", format="lua_additive_table", handle-unlocalized="comment")@
elseif locale == 'koKR' then
--@localization(locale="koKR", format="lua_additive_table", handle-unlocalized="comment")@
elseif locale == 'ptBR' then
--@localization(locale="ptBR", format="lua_additive_table", handle-unlocalized="comment")@
elseif locale == 'ruRU' then
--@localization(locale="ruRU", format="lua_additive_table", handle-unlocalized="comment")@
elseif locale == 'zhCN' then
--@localization(locale="zhCN", format="lua_additive_table", handle-unlocalized="comment")@
elseif locale == 'zhTW' then
--@localization(locale="zhTW", format="lua_additive_table", handle-unlocalized="comment")@
end


--[[
#!/bin/bash

#enUS
L="deDE
esES
esMX
frFR
itIT
koKR
ptBR
ruRU
zhCN
zhTW
"


for i in $L ;do 

echo "elseif locale == '$i' then"
echo "--@localization(locale=\"$i\", format=\"lua_additive_table\", handle-unlocalized=\"comment\")@"

done

# import to wowace
grep "L\[.*\]"  -Po MySlot.lua | sed -e s/$/=true/g
echo L[\"TOC_NOTES\"] = true

for i in $L ;do 
echo "## Notes-$i: @localization(locale=\"$i\", key=\"TOC_NOTES\")@"
done

]]
