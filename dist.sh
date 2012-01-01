#!/bin/bash

git archive --prefix=MySlot/ --format=tar master | bzip2 > Myslot.tar.bz2
git archive --prefix=MySlot/ --format=zip master > Myslot.zip

md5sum Myslot.tar.bz2 Myslot.zip
