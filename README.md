# ButtonMaster

A [MacroQuest](https://www.macroquest.org/) Lua addon for EverQuest: fully configurable, ImGui-based hotbars ("Buttons") for firing commands, spells, abilities, disciplines, AAs, items, and custom Lua — built with multiboxing in mind (shared button Sets across characters, `/bc`-style broadcast commands, per-character display settings).

> This is a fork/continuation of an existing ButtonMaster project. See "Origin" below.

## Requirements

- [MacroQuest](https://www.macroquest.org/) with Lua scripting support
- EverQuest

## Installation

Copy the `buttonmaster` folder into your MacroQuest `lua` directory, e.g.:

```
<MacroQuest root>/lua/buttonmaster/
```

Then in-game:

```
/lua run buttonmaster
```

## Features

- Configurable hotbars ("Sets") of Buttons, each running one or more `/`-commands, an item click, a spell/AA/disc/ability, or custom Lua
- Cooldown/timer overlays per button (manual timer, item, spell gem, AA, disc, ability, or custom Lua)
- Drag-and-drop button reassignment between hotbars, with a per-hotbar Lock toggle to disable it
- Icon picker, custom colors, custom themes
- Import/export buttons and sets via clipboard, for sharing configs
- **Keyboard hotkeys** - assign a real keyboard shortcut (with Ctrl/Alt/Shift) to any button, captured live from the button editor:
  - Bound per-character, not shared across your other characters/boxes even when they use the same button
  - Automatically suppressed while typing in EverQuest's chat input, so hotkeys don't fire mid-sentence (WIP)
  - Conflict and risky-binding warnings in the editor UI

## Configuration

Settings (including your hotkey bindings, button layouts, and windows) are stored outside this folder, in MacroQuest's own config directory - typically `<MacroQuest root>/config/ButtonMaster.lua`, with periodic backups under `config/Buttonmaster-Backups/`. Nothing personal lives inside the `buttonmaster` addon folder itself, so it's safe to share or version-control as-is.

## Origin
https://github.com/DerpleDude/buttonmaster

## License

