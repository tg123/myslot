# Myslot

**Copy your whole UI setup to any character — action bars, macros and keybinds — with one text string.**

[![CurseForge](https://img.shields.io/badge/CurseForge-Myslot-F16436?logo=curseforge&logoColor=white)](https://www.curseforge.com/wow/addons/myslot)
[![Wago](https://img.shields.io/badge/Wago-Myslot-7B3FE4)](https://addons.wago.io/addons/myslot)
[![Test](https://github.com/tg123/myslot/actions/workflows/test.yml/badge.svg)](https://github.com/tg123/myslot/actions/workflows/test.yml)

Setting up a new alt, moving to a new account, or rebuilding after a UI reset?
Myslot exports your setup as a short, copy‑paste friendly text.
Paste it on any character — even a different class — and click **Import**.

Browse and share profiles at **<https://myslot.net>**.

## Features

- **Action bars** — every bar, including the main action bar pages, stance bars and the Skyriding bar
- **Macros** — both account‑wide and character‑specific
- **Key bindings**
- **Click Cast Bindings** *(Retail)*
- **Cooldown Manager layouts** *(Retail)*
- **Talents** *(Retail)* — see the profile's talent loadout string, get warned when it differs from yours, and load it into the talent window with one click
- **Cross‑class & cross‑account** — spells, items, mounts and pets you don't have are skipped with a clear message; unowned mounts can fall back to a random mount
- **Saved profiles** — keep up to 100 exports in game, sort by name / date / class and filter to your class
- **Automatic backup** — your current setup is saved before every import, so you can always roll back
- **Share profiles via clickable chat links** — link a saved profile in guild, party, raid or whisper chat; other Myslot users click it to get a copy
- **Choose what to import or clear** — pick exactly which bars, macros and bindings to apply
- **Fast & safe** — asynchronous import with a progress bar, blocked during combat, CRC‑checked text
- **Minimap button** and `/myslot` slash command

### Supported game versions

Retail (The War Within / Midnight), Classic Era & Anniversary, Burning Crusade, Wrath, Cataclysm, Mists of Pandaria, Titan and WoW Forever.
Options that a game version doesn't support are hidden automatically.

## Usage

### Export

1. Type `/myslot` (or click the minimap button) to open Myslot
1. Click **Export**
1. Copy the text and save it anywhere — a text file, Discord, email, or [myslot.net](https://myslot.net)

### Import

1. Type `/myslot` to open Myslot
1. Paste the exported text into the text box (or pick a saved profile)
1. Choose what to import, then click **Import**

Importing a profile exported with talents other than the ones you are using asks for confirmation first —
a profile's action bars rarely fit another build.

### Talents *(Retail)*

Myslot doesn't import talents with the rest of a profile, but helps you switch to them:

- The profile's talent loadout string is shown in the **Talents** box under the text box —
  click it to select the string and copy it with Ctrl+C, e.g. for the talent window's **Import**.
- When the profile's talents differ from yours, click **Apply talents**: they are saved as the talent loadout
  `Myslot` (replacing the previous one) and the talent window opens with it selected.
  Review it there and click **Apply Changes** to switch to it.
- A profile saved before a talent tree change (a patch or hotfix) shows **Talents out of date**;
  it can still be loaded, but check it carefully since talents may have moved.
- The profile must be for your current specialization, and talents can't be changed in combat.

Talent loadout strings only exist since Dragonflight, so none of this is shown on Classic versions.

### Share in chat

1. Select a saved profile and click the chat bubble next to the profile list (save any changes first — only saved profiles can be shared)
1. Send the `[Myslot: Name - Profile]` tag in guild, party, raid, whisper, etc.
1. Other Myslot users click the link to receive the profile in their import box — they still have to click **Import**

Links are only served for the current session and cannot be fetched during encounters, Mythic+ or other chat-restricted content.

### Slash commands

| Command | Description |
|---------|-------------|
| `/myslot` | Toggle the Myslot window |
| `/myslot load <ProfileName>` | Import a saved profile by name — put it in a macro to swap setups with one click |
| `/myslot clear action` | Clear every action bar slot |
| `/myslot clear macro` | Delete all macros |
| `/myslot clear binding` | Clear all key bindings (Blizzard defaults included) |
| `/myslot clear talents` | Delete the `Myslot` talent loadouts made by **Apply talents**, in every specialization *(Retail; your talents in use are kept)* |
| `/myslot trim [N]` | Keep only the newest `N` saved profiles (default 100) and reload the UI |

## Get Myslot

- CurseForge — <https://www.curseforge.com/wow/addons/myslot>
- Wago — <https://addons.wago.io/addons/myslot>

## Contributing

Source code lives on GitHub: <https://github.com/tg123/myslot>. Bug reports and pull requests are welcome.

### Localization

Translations are welcome! Please submit them at
<https://www.wowace.com/projects/myslot/localization>.

### Build your own Myslot

- Clone the source code into `Interface\AddOns\Myslot`

```
$ git clone https://github.com/tg123/myslot.git Myslot
```

- Run the tests (Lua 5.1 + luabitop)

```
$ lua5.1 ci/run.lua
```

- Run the tests in game — a git checkout loads the test suite (it is stripped from CurseForge/Wago packages), then type:

```
/myslottest            -- run all tests
/myslottest <filter>   -- run only tests whose name matches <filter>
```

  The results are shown in a pop-up you can copy with Ctrl+A / Ctrl+C. Tests cannot run in combat.

#### Changing Protobuf

Myslot use a modified version of [lua-pb](https://github.com/tg123/lua-pb) to serialize/deserialize the data. 
You may want to change the data structure sometimes if you want add some new things to export.

Please check [lua-pb](https://github.com/tg123/lua-pb) about how to generate protobuf stub files.

## Copyright and License
1. Copyright (C) 2009-2026 by Boshi Lian <farmer1992@gmail.com>
1. Use of this software for profit purposes are NOT allowed except by prior arrangement and written consent of the author.
1. This software is licensed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.html)
1. All rights of **Exported text** are owned by end-users.
