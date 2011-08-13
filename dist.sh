#!/bin/bash

git archive --prefix=MySlot/ --format=tar master | bzip2 > myslot.tar.bz2
