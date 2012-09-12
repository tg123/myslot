#!/bin/bash

TARGET=Myslot.zip
TOC=`ls *.toc`

rm -f $TARGET

grep '\.(lua)|(xml)$' $TOC -P | sed -e 's/\\/\//g' |xargs zip $TARGET $TOC

unzip -d Myslot $TARGET

rm -f $TARGET

zip -r $TARGET Myslot # fuck !

rm -rf Myslot

md5sum $TARGET
