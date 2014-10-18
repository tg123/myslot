#!/bin/bash

VER=`cat MySlot.ver`
LOCALE='locales.lua'
TOC='MySlot.toc'

TOCNOTE_KEY='TOC_NOTES'

WOWACE_EXPORT_URL='http://www.wowace.com/addons/myslot/localization/export.txt?'

REPLACING_SURFIX="wowace"

declare -A TOCNOTEMAP

echo "building $LOCALE ..."
true > "$LOCALE.$REPLACING_SURFIX"

while read -r r; do

	param=`echo $r |  sed -ne 's/.*(\([^$]*\)).*/\1/p' | sed 's/[" ]//g' | sed 's/,/\&/g' | sed 's/locale=/language=/' | sed 's/-/_/g'`

	if [ -n "$param" ]; then
		lang=`echo $param | sed -n 's/language=\(\w*\).*/\1/p'`
		if [ -n "$lang" ]; then
			:
			echo "Downloading $lang ..."
			curl -s "$WOWACE_EXPORT_URL$param" >> $LOCALE.$REPLACING_SURFIX
			note=`grep "L\[\"$TOCNOTE_KEY\"\]" $LOCALE.$REPLACING_SURFIX | tail -n 1 | cut -d = -f 2 | sed 's/"//g'`

			TOCNOTEMAP[$lang]="$note"

            continue
		fi
	fi	

    echo $r >> $LOCALE.$REPLACING_SURFIX

done< <(cat $LOCALE)

echo "$LOCALE.$REPLACING_SURFIX done"

echo "building $TOC ..."
true > "$TOC.$REPLACING_SURFIX"

while read -r r; do
	#@localization(locale="enUS", key="TOC_NOTES")@
	lang=`echo $r | sed -n 's/.*locale="\(\w*\)".*/\1/p'`
	if [ -n "$lang" ];then
		echo $r | sed "s/@localization.*@/${TOCNOTEMAP[$lang]}/" >> $TOC.$REPLACING_SURFIX
	else
		echo ${r/@project-version@/"$VER.DIST"} >> $TOC.$REPLACING_SURFIX
	fi
:

done< <(cat $TOC)

echo "$TOC.$REPLACING_SURFIX done"
