#!/bin/bash

TARGET=Myslot.zip
TOC=`ls *.toc`

rm -f $TARGET

grep '\.(lua)|(xml)$' $TOC -P | sed -e 's/\\/\//g' |xargs zip -p Myslot $TARGET $TOC

md5sum $TARGET
