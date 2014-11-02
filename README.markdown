#MySlot


##Introduction
Myslot is a [World of Warcraft](http://www.battle.net/wow) Addon for transferring settings between accounts.

Myslot can export your ActionBar Layout, Marcos and Key Bindings as a transfer-friendly text. 
Any character, even different class, can use Myslot to import those settings from the 'Exported text'

##Usage


### Export

  1. Use command /myslot to toggle Myslot main UI
  1. Click the 'Export' button
  1. Save the `exported text` anywhere you want (e.g. nodepat as a txt)

### Import
  
  1. Use command /myslot to toggle Myslot main UI
  1. Paste `exported text` into textbox
  1. Click the 'Import' button
 
### Clean up tools
  

  1. Clear all action slot on your action bar
     
    /myslot clear action

  1. Clear all key bindings (blizzard default included)
     
    /myslot clear binding


## Get Myslot

 * Curse (Lastest stable) http://www.curse.com/addons/wow/myslot
 * Wowace (stable and test) http://www.wowace.com/addons/myslot/

## Contrubuting

 Source on Github <https://github.com/tg123/myslot>

### Localization

Localization is welcomed, Please visit 
<http://www.wowace.com/addons/myslot/localization/>
and submit your localization


### Build your own Myslot

My game envirment is Ubuntu + wine

 * fetch the source code

```
$ git clone https://github.com/tg123/myslot.git

$ cd myslot

$ git submodule init

$ git submodule update 
```
 
 * pull the localizations from wowace

```
./update_locale.sh
```
 
 * build your own dist `.zip`

```
./dist.sh
```

#### Changing Protobuf def

Myslot use a modified version of [lua-pb](https://github.com/tg123/lua-pb) to serialize/deserialize the data. 
You may want to change the data structure sometimes if you want add some new things to export.

* Dependencies

Your need install `lpeg` to build `.proto`

```
luarocks install lpeg
```

 * Generate

Editing `protobuf/MySlot.proto`

run

```
lua buildast.lua
```

to generate `PbMySlot.lua` for game use

## Copyright and License
1. Copyright (C) 2009-2014 by tgic <farmer1992@gmail.com>
1. Use of this software for profit purposes are NOT allowed except by prior arrangement and written consent of the author.
1. This software is licensed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.html)
1. All rights of **Exported text** are owned by end-users.
