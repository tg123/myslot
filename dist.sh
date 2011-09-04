#!/bin/bash

git archive --prefix=MySlot/ --format=tar master | bzip2 > myslot.tar.bz2
git archive --prefix=MySlot/ --format=zip master > myslot.zip

md5sum myslot.tar.bz2 myslot.zip
