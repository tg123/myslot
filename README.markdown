# Myslot

## Introduction
Myslot is a [World of Warcraft](http://www.battle.net/wow) Addon for transferring settings between accounts.

Myslot can export your ActionBar Layout, Marcos and Key Bindings as a transfer-friendly text, 
which can be copy/paste into notepad, sent via email, etc.
Any character, even different class, can use Myslot to import those settings from the 'Exported text'

## Usage


### Export

  1. Use command /myslot to toggle Myslot main UI
  1. Click the 'Export' button
  1. Save the `exported text` anywhere you want (e.g. nodepad as a txt)

### Import
  
  1. Use command /myslot to toggle Myslot main UI
  1. Paste `exported text` into textbox
  1. Click the 'Import' button
 
### Clean up tools
  

  1. Clear all action slot on your action bar
     
    /myslot clear action

  1. Clear all key bindings (blizzard default included)
     
    /myslot clear binding
 
### Import profile from command
  

You can use the command 'load' to import a profile by name
     
    /myslot load ProfileName

You can add this line in a macro and safe it in your profile and swap from one profile to another by using the macro.


## Get Myslot

 * Curse https://www.curseforge.com/wow/addons/myslot
 * Wowace http://www.wowace.com/addons/myslot

## Contrubuting

 Source on Github <https://github.com/tg123/myslot>

### Localization

Localization is welcomed, Please visit 
<http://www.wowace.com/addons/myslot/localization/>
and submit your localization


### Build your own Myslot

 * clone the source code into `Interface\Addons\Myslot`

```
$ git clone https://github.com/tg123/myslot.git Myslot
```
 
 * pull the localizations from wowace (optional)

```
./update_locale.sh
```
 
#### Changing Protobuf

Myslot use a modified version of [lua-pb](https://github.com/tg123/lua-pb) to serialize/deserialize the data. 
You may want to change the data structure sometimes if you want add some new things to export.

Please check [lua-pb](https://github.com/tg123/lua-pb) about how to generate protobuf stub files.


## Copyright and License
1. Copyright (C) 2009-2019 by Boshi Lian <farmer1992@gmail.com>
1. Use of this software for profit purposes are NOT allowed except by prior arrangement and written consent of the author.
1. This software is licensed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.html)
1. All rights of **Exported text** are owned by end-users.
