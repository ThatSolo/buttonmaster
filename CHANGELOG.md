# Changelog

All notable changes made in this fork of [DerpleDude/buttonmaster](https://github.com/DerpleDude/buttonmaster) are documented here.

## Keyboard Hotkeys

Buttons can now be triggered by a keyboard shortcut, assigned live from the button editor - no ini editing required.

- **Live capture** - click "Listen", press a key (optionally holding Ctrl/Alt/Shift), and it's bound. A short settle window is used while capturing so a modifier that lags the main key by a few frames still gets included in the chord.
- **Per-character bindings** - hotkeys are stored per-character, not on the shared button, so multiboxers won't have a hotkey bound on one character silently fire on every other character sharing that button.
- **Conflict warnings** - the editor flags when a chord is already bound to another button on the same character.
- **Risky-binding warnings** - binding an unmodified key that EQ/typing already relies on (WASD, Space, Enter, arrow keys) shows a warning, since it'll fire *while* you move/chat rather than instead of it.
- **Chat-input suppression** - hotkeys are automatically suppressed while you're typing in EQ's chat line, so a bound key doesn't fire mid-sentence or mid-tell. This is tracked two ways: an Enter opens a short grace window, continuously refreshed by further typing (or a key just being held down) and expiring a moment after you actually stop, with Escape clearing it immediately - and, on the default UI, a direct check of EQ's own chat input box (ChatWindow > CW_ChatInput) that doesn't depend on timing at all. Either one firing is enough to suppress. The direct check is on by default, with a Dev menu toggle to disable it if your UI uses different window names.
- **Debug logging** - the hotbar's right-click menu has a Dev "Enable Debug" toggle that logs every hotkey press and, if suppressed, exactly why.

## Fixes

- **Drag-and-drop misfiring on character-switch** - clicking to switch focus between characters could be misread by Dear ImGui as a long-press, making it look like you'd grabbed a button to move it. Fixed two ways: the existing per-hotbar "Locked" toggle now also blocks drag-and-drop (not just window move/resize), and unlocked hotbars require a brief period of stable window focus before a click-and-hold is trusted as a real drag.
- **Hotkeys permanently locking out after switching back to a character** - the same focus-switch quirk above could also leave a keyboard key stuck "down" in Dear ImGui with no release ever registering, which the chat-suppression tracking misread as continuous typing and used to refresh its grace window forever. Key state is now distrusted for a brief period right after a window regains focus, the same way drag-and-drop already was.
- **Crash when checking remaining chat-suppression time** - the debug-log message showing seconds left could crash on a fractional value (mq.gettime() is in milliseconds, so this was common, not an edge case). Rounded up to a whole second before formatting.
- **Hotkeys locking out after sending a chat message** - pressing your own bound hotkeys right after finishing typing (e.g. resuming a combat rotation after sending a tell) could keep re-arming the very suppression window blocking them, since mashing a key looks identical to typing it whether or not it's bound. A character's own bound hotkey keys no longer count as "still typing" for that purpose. The default grace period was also raised slightly (1s to 2s) since a normal pause between words was enough to lapse it mid-message.
- **Hotkeys firing during a longer pause mid-message** - the grace window above only covers a couple seconds of silence, so composing a longer message (or pausing to think) could let it lapse before you were actually done typing. Added a direct check of EQ's chat input box (confirmed via MacroQuest's Window Inspector that ChatWindow > CW_ChatInput is the real input line, not just the chat pane as a whole - checking the pane itself was tried first and false-positived) as a second signal that doesn't depend on timing.
- **Dev-menu toggles resetting on every script reload** - "Enable Debug" and "Enable Chat-Window Lookup" were both plain in-memory flags, so a `/lua stop` + `/lua run` silently reset them to their defaults - easy to mistake for a fix not working when it was actually just the toggle resetting. Both now persist per-character across reloads.
- **Crash when adding an item to a hotbar with Debug mode on** - the icon picker renders buttons without their label, but the debug-render path assumed a label position was always set. Fixed to match the same defensive pattern used elsewhere.

## Housekeeping

- Added this fork's README and changelog, crediting the original [DerpleDude/buttonmaster](https://github.com/DerpleDude/buttonmaster) project.
