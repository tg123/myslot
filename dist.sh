#!/bin/bash



TARGET=`grep package-as .pkgmeta | cut -d ' ' -f 2`
TOC=`ls *.toc`

rm -f $TARGET.zip
rm -rf $TARGET

grep '\.(lua)|(xml)$' $TOC -P | sed -e 's/\\/\//g' |xargs zip $TARGET $TOC

unzip -d $TARGET $TARGET.zip

rm -f $TARGET.zip

if [ ! -e locales.lua.wowace ] || [ ! -e MySlot.toc.wowace ];then
	./update_locale.sh
fi 

/bin/cp locales.lua.wowace $TARGET/locales.lua
/bin/cp MySlot.toc.wowace $TARGET/MySlot.toc

zip -r $TARGET.zip $TARGET
rm -rf $TARGET

md5sum $TARGET.zip
