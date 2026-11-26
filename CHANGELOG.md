# Changelog

All notable changes made in this fork of [DerpleDude/buttonmaster](https://github.com/DerpleDude/buttonmaster) are documented here.

## Keyboard Hotkeys

Buttons can now be triggered by a keyboard shortcut, assigned live from the button editor - no ini editing required.

- **Live capture** - click "Listen", press a key (optionally holding Ctrl/Alt/Shift), and it's bound. A short settle window is used while capturing so a modifier that lags the main key by a few frames still gets included in the chord.
- **Per-character bindings** - hotkeys are stored per-character, not on the shared button, so multiboxers won't have a hotkey bound on one character silently fire on every other character sharing that button.
- **Conflict warnings** - the editor flags when a chord is already bound to another button on the same character.
- **Risky-binding warnings** - binding an unmodified key that EQ/typing already relies on (WASD, Space, Enter, arrow keys) shows a warning, since it'll fire *while* you move/chat rather than instead of it.
- **Chat-input suppression** - hotkeys are automatically suppressed while you're typing in EQ's chat line, so a bound key doesn't fire mid-sentence or mid-tell. This is tracked without depending on EverQuest's internal window names: an Enter opens a short grace window, which is continuously refreshed by further typing (or a key just being held down) and expires a moment after you actually stop, with Escape clearing it immediately. An optional, off-by-default window-lookup can supplement this on UI layouts where the default window names are reliable.
- **Debug logging** - the hotbar's right-click menu has a Dev "Enable Debug" toggle that logs every hotkey press and, if suppressed, exactly why.

## Fixes

- **Drag-and-drop misfiring on character-switch** - clicking to switch focus between characters could be misread by Dear ImGui as a long-press, making it look like you'd grabbed a button to move it. Fixed two ways: the existing per-hotbar "Locked" toggle now also blocks drag-and-drop (not just window move/resize), and unlocked hotbars require a brief period of stable window focus before a click-and-hold is trusted as a real drag.
- **Hotkeys permanently locking out after switching back to a character** - the same focus-switch quirk above could also leave a keyboard key stuck "down" in Dear ImGui with no release ever registering, which the chat-suppression tracking misread as continuous typing and used to refresh its grace window forever. Key state is now distrusted for a brief period right after a window regains focus, the same way drag-and-drop already was.
- **Crash when checking remaining chat-suppression time** - the debug-log message showing seconds left could crash on a fractional value (mq.gettime() is in milliseconds, so this was common, not an edge case). Rounded up to a whole second before formatting.
- **Hotkeys locking out after sending a chat message** - pressing your own bound hotkeys right after finishing typing (e.g. resuming a combat rotation after sending a tell) could keep re-arming the very suppression window blocking them, since mashing a key looks identical to typing it whether or not it's bound. A character's own bound hotkey keys no longer count as "still typing" for that purpose. The default grace period was also raised slightly (1s to 2s) since a normal pause between words was enough to lapse it mid-message.

## Housekeeping

- Added this fork's README and changelog, crediting the original [DerpleDude/buttonmaster](https://github.com/DerpleDude/buttonmaster) project.
