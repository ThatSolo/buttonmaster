--[[
    BMHotkeys - lets a Button be triggered by a keyboard shortcut ("hotkey"),
    assigned live in-game from the button editor (no ini editing required).

    A Hotkey is { Key = <ImGuiKey number>, Ctrl = bool, Shift = bool, Alt = bool },
    stored per-character (see BMSettings:GetCharHotkeys) rather than on the
    Button itself, since Buttons are shared/synced across characters.

    Key is the raw ImGuiKey enum value (stable, numeric) so it round-trips
    through mq.pickle without needing a name<->enum lookup table.
]]

local mq       = require('mq')
local btnUtils = require('lib.buttonUtils')

---@class BMHotkeys
local BMHotkeys        = {}
BMHotkeys.__index      = BMHotkeys

-- true while the popup is waiting for the next keypress to bind.
BMHotkeys.Listening        = false
-- the button table (usually the edit popup's tmpButton) receiving the capture.
BMHotkeys.ListenTargetButton = nil

---Only allow binding "real" keys - not the bare modifier keys themselves
---(those are captured separately as Ctrl/Shift/Alt), not the gamepad/mouse
---pseudo-keys ImGui reports through the same enum range, and not ImGui's
---internal ModCtrl/ModShift/ModAlt/ModSuper alias keys (these mirror
---whichever real modifier is held, and aren't exposed as named ImGuiKey.*
---fields, so they're filtered by name instead of by value).
---@param key integer
---@return boolean
local function isAssignableKey(key)
    if key < ImGuiKey.NamedKey_BEGIN or key >= ImGuiKey.NamedKey_END then return false end
    if key >= ImGuiKey.LeftCtrl and key <= ImGuiKey.RightSuper then return false end
    if key >= ImGuiKey.GamepadStart and key <= ImGuiKey.MouseWheelY then return false end

    local ok, name = pcall(ImGui.GetKeyName, key)
    if ok and name and name:match("^Mod%u") then return false end

    return true
end

-- Keys EQ (or basic typing/movement) already relies on constantly - warn if
-- someone binds one of these with no modifier since it'll fire *while* they
-- move/chat/close windows, not instead of it.
-- Built lazily (not at module load) since ImGuiKey isn't defined as a global
-- yet this early in the require chain (well before mq.imgui.init() runs).
local riskyUnmoddedKeys = nil
local function getRiskyUnmoddedKeys()
    if not riskyUnmoddedKeys then
        riskyUnmoddedKeys = {
            [ImGuiKey.W] = true,
            [ImGuiKey.A] = true,
            [ImGuiKey.S] = true,
            [ImGuiKey.D] = true,
            [ImGuiKey.Space] = true,
            [ImGuiKey.Enter] = true,
            [ImGuiKey.UpArrow] = true,
            [ImGuiKey.DownArrow] = true,
            [ImGuiKey.LeftArrow] = true,
            [ImGuiKey.RightArrow] = true,
        }
    end
    return riskyUnmoddedKeys
end

-- Multi-key chords aren't pressed in one perfectly simultaneous instant by
-- hand - a modifier can lag the main key by a few frames or vice versa. So
-- once the first assignable key is seen, capture holds off finalizing for a
-- short settle window and OR's in whatever modifiers are down across it (one
-- released partway through the window still counts). Measured in polled
-- frames rather than wall-clock time since PollCapture already runs every
-- render frame from the edit popup.
BMHotkeys.CaptureSettleFrames = 20 -- roughly a third of a second at 60fps
local pendingKey = nil
local pendingFramesLeft = 0
local pendingCtrl, pendingShift, pendingAlt = false, false, false

local function resetPendingCapture()
    pendingKey = nil
    pendingFramesLeft = 0
    pendingCtrl, pendingShift, pendingAlt = false, false, false
end

---Begin listening for the next keypress and bind it (plus any held mods) to `button.Hotkey`.
---@param button table # BMButtonConfig, typically the edit popup's tmpButton
function BMHotkeys.BeginCapture(button)
    resetPendingCapture()
    BMHotkeys.Listening = true
    BMHotkeys.ListenTargetButton = button
end

---Stop listening without assigning anything.
---@param button table? # if given, only cancels when this is the button currently being listened for
function BMHotkeys.CancelCapture(button)
    if button ~= nil and BMHotkeys.ListenTargetButton ~= button then return end
    resetPendingCapture()
    BMHotkeys.Listening = false
    BMHotkeys.ListenTargetButton = nil
end

---While a capture is in progress (a key has registered but the settle
---window hasn't finished), returns a live preview of what's been seen so
---far ("Ctrl+F1") and how many settle-frames remain.
---@return string? preview
---@return integer? framesLeft
function BMHotkeys.CaptureProgress()
    if not pendingKey then return nil, nil end
    return BMHotkeys.FormatHotkey({ Key = pendingKey, Ctrl = pendingCtrl, Shift = pendingShift, Alt = pendingAlt }),
        pendingFramesLeft
end

---Call every frame while the button editor is open. Returns true the frame a
---key gets captured and assigned (Escape cancels instead of assigning).
---@return boolean
function BMHotkeys.PollCapture()
    if not BMHotkeys.Listening then return false end

    if ImGui.IsKeyPressed(ImGuiKey.Escape, false) then
        resetPendingCapture()
        BMHotkeys.CancelCapture()
        return false
    end

    if not pendingKey then
        for key = ImGuiKey.NamedKey_BEGIN, ImGuiKey.NamedKey_END - 1 do
            if isAssignableKey(key) and ImGui.IsKeyPressed(key, false) then
                pendingKey = key
                pendingFramesLeft = BMHotkeys.CaptureSettleFrames
                break
            end
        end
        if not pendingKey then return false end
    end

    -- OR'd, not overwritten - a modifier down on ANY polled frame during the
    -- settle window counts, even if it's released again before the window ends.
    pendingCtrl = pendingCtrl or ImGui.IsKeyDown(ImGuiMod.Ctrl)
    pendingShift = pendingShift or ImGui.IsKeyDown(ImGuiMod.Shift)
    pendingAlt = pendingAlt or ImGui.IsKeyDown(ImGuiMod.Alt)

    pendingFramesLeft = pendingFramesLeft - 1
    if pendingFramesLeft > 0 then
        return false -- still settling
    end

    local button = BMHotkeys.ListenTargetButton
    if button then
        button.Hotkey = { Key = pendingKey, Ctrl = pendingCtrl, Shift = pendingShift, Alt = pendingAlt }
    end
    resetPendingCapture()
    BMHotkeys.CancelCapture()
    return true
end

---Human readable form, e.g. "Ctrl+Shift+F1". Empty string if unassigned.
---@param Hotkey table? # {Key=number, Ctrl=bool, Shift=bool, Alt=bool}
---@return string
function BMHotkeys.FormatHotkey(Hotkey)
    if not Hotkey or not Hotkey.Key then return "" end

    local ok, name = pcall(ImGui.GetKeyName, Hotkey.Key)
    if not ok or not name or name:len() == 0 then
        name = "Key#" .. tostring(Hotkey.Key)
    end

    local parts = {}
    if Hotkey.Ctrl then table.insert(parts, "Ctrl") end
    if Hotkey.Alt then table.insert(parts, "Alt") end
    if Hotkey.Shift then table.insert(parts, "Shift") end
    table.insert(parts, name)
    return table.concat(parts, "+")
end

---True if this Hotkey is an unmodified key EQ/typing already depends on.
---@param Hotkey table?
---@return boolean
function BMHotkeys.IsRisky(Hotkey)
    if not Hotkey or not Hotkey.Key then return false end
    if Hotkey.Ctrl or Hotkey.Shift or Hotkey.Alt then return false end
    return getRiskyUnmoddedKeys()[Hotkey.Key] == true
end

---Build an ImGuiKeyChord (key OR-ed with any held modifiers) for IsKeyChordPressed.
---@param Hotkey table?
---@return integer?
function BMHotkeys.BuildChord(Hotkey)
    if not Hotkey or not Hotkey.Key then return nil end

    local chord = Hotkey.Key
    if Hotkey.Ctrl then chord = bit32.bor(chord, ImGuiMod.Ctrl) end
    if Hotkey.Shift then chord = bit32.bor(chord, ImGuiMod.Shift) end
    if Hotkey.Alt then chord = bit32.bor(chord, ImGuiMod.Alt) end
    return chord
end

---True if two Hotkey tables represent the same chord.
---@param a table?
---@param b table?
---@return boolean
local function sameHotkey(a, b)
    if not a or not b or not a.Key or not b.Key then return false end
    return a.Key == b.Key
        and (a.Ctrl or false) == (b.Ctrl or false)
        and (a.Shift or false) == (b.Shift or false)
        and (a.Alt or false) == (b.Alt or false)
end

---Find another button on this character already bound to the same chord
---(for an "already used by..." warning). Hotkeys are per-character (see
---BMSettings:GetCharHotkeys), so only this character's bindings are checked.
---@param Hotkey table?
---@param charHotkeys table # BMSettings:GetCharHotkeys() - { [ButtonKey] = Hotkey }
---@param excludeKey string? # the button key currently being edited, so it doesn't flag itself
---@return string? conflictButtonKey
function BMHotkeys.FindConflict(Hotkey, charHotkeys, excludeKey)
    if not Hotkey or not Hotkey.Key then return nil end
    for buttonKey, otherHotkey in pairs(charHotkeys or {}) do
        if buttonKey ~= excludeKey and sameHotkey(Hotkey, otherHotkey) then
            return buttonKey
        end
    end
    return nil
end

---True if EQ's own chat input line currently has keyboard focus, checked by
---asking the game's UI directly. Best-effort: custom chat window setups can
---use different window names than the default UI and just silently never
---match. See BMHotkeys.IsChatInputActive for the self-tracked fallback that
---doesn't depend on this.
---@return string? matchedCandidate # e.g. "ChatWindow > CW_ChatInput", or nil if none matched
local function isKnownChatWindowFocused()
    -- (topLevelWindow, childWindow-or-nil) pairs worth trying. Add more here
    -- if your UI uses a different window name (check via "/windows open" or
    -- MacroQuest's Window Inspector in /mqconsole).
    local candidates = {
        { "ChatWindow", "CW_ChatInput" },
        { "ChatWindow", nil },
        { "ChatInputWnd", nil },
    }

    for _, candidate in ipairs(candidates) do
        local topName, childName = candidate[1], candidate[2]
        local ok, active = pcall(function()
            local w = mq.TLO.Window(topName)
            if childName then w = w.Child(childName) end
            return w() ~= nil and w.Highlighted()
        end)
        if ok and active == true then
            return childName and (topName .. " > " .. childName) or topName
        end
    end

    return nil
end

-- Self-tracked chat-input suppression that doesn't depend on knowing EQ's
-- internal window names. Enter (re)starts a grace window rather than
-- toggling on/off, since a "closing" Enter isn't guaranteed to reach this
-- overlay; ordinary typing (or a held key) keeps extending it too, so the
-- window really means "no keyboard activity for this long" - it expires
-- quickly once you're done, but never lapses mid-message. 1s cuts it close
-- for a normal typing cadence (a brief pause between words is enough to
-- lapse it mid-message); 2s gives more headroom while still resuming fast
-- once you're actually done. Uses mq.gettime() rather than os.time() as the
-- clock.
BMHotkeys.ChatGraceSeconds = 2
local chatAssumedOpenAt = nil
local wasEnterDown = false
local wasEscapeDown = false

local function nowSeconds()
    return mq.gettime() / 1000
end

-- Switching focus between character windows (clicking a different client,
-- same as the drag-and-drop focus bug - see BMButtonHandlers.IsInteractionSafe)
-- can leave Dear ImGui thinking some key is still held down from before the
-- switch, with no release ever registering. Key state is distrusted for a
-- short settle period right after regaining foreground so a stuck key can't
-- be mistaken for real activity.
local FOCUS_SETTLE_FRAMES = 20
local wasForeground = false
local foregroundStableFrames = 0

local function isKeyStateTrustworthy()
    local ok, isForeground = pcall(function() return mq.TLO.EverQuest.Foreground() end)
    if not ok then isForeground = true end -- fail open

    if isForeground and wasForeground then
        foregroundStableFrames = foregroundStableFrames + 1
    else
        foregroundStableFrames = 0
    end
    wasForeground = isForeground

    return foregroundStableFrames >= FOCUS_SETTLE_FRAMES
end

---Keys currently bound as a hotkey on this character, as a {[Key]=true} set.
---Best-effort: BMSettings is a global set up by init.lua, not required here
---(requiring it back would be circular - BMSettings requires
---BMButtonHandlers, which requires this module), so it's read defensively.
---@return table<integer, boolean>
local function currentlyBoundKeys()
    local excluded = {}
    local ok, charHotkeys = pcall(function() return BMSettings and BMSettings:GetCharHotkeys() end)
    if ok and charHotkeys then
        for _, hotkey in pairs(charHotkeys) do
            if hotkey and hotkey.Key then excluded[hotkey.Key] = true end
        end
    end
    return excluded
end

---True if any assignable (plain typing) key - other than Enter/Escape or one
---of this character's own bound hotkeys - is currently held down. Uses
---IsKeyDown rather than a press-edge check, since a held/auto-repeating key
---only generates one press edge but must keep refreshing the window for as
---long as it's held. Enter/Escape are excluded since they're already tracked
---as their own edges above (see isKeyStateTrustworthy for why counting them
---here too is dangerous). Bound hotkeys are excluded because otherwise,
---after the window is armed, simply mashing your own hotkeys in gameplay
---(not typing at all) would keep re-arming the very suppression blocking
---them, locking them out indefinitely instead of letting the window expire.
---Only scanned while the window is already open, so this adds no per-frame
---cost the rest of the time.
---@return boolean
local function anyTypingKeyDown()
    local boundKeys = currentlyBoundKeys()
    for key = ImGuiKey.NamedKey_BEGIN, ImGuiKey.NamedKey_END - 1 do
        if key ~= ImGuiKey.Enter and key ~= ImGuiKey.KeypadEnter and key ~= ImGuiKey.Escape
            and not boundKeys[key] and isAssignableKey(key) and ImGui.IsKeyDown(key) then
            return true
        end
    end
    return false
end

---True if the grace window is genuinely still open (not just set, but not
---yet past ChatGraceSeconds). Self-heals - nils chatAssumedOpenAt once
---expired - so a keypress arriving after expiry can't resurrect a dead
---window; only activity seen while still open extends it further.
---@return boolean
local function isChatAssumedOpen()
    if not chatAssumedOpenAt then return false end
    if nowSeconds() - chatAssumedOpenAt > BMHotkeys.ChatGraceSeconds then
        chatAssumedOpenAt = nil -- grace period expired with no Enter/Escape/typing seen - self heal
        return false
    end
    return true
end

local function updateChatTrackingFromKeys()
    local enterDown = ImGui.IsKeyDown(ImGuiKey.Enter) or ImGui.IsKeyDown(ImGuiKey.KeypadEnter)
    local escapeDown = ImGui.IsKeyDown(ImGuiKey.Escape)

    if not isKeyStateTrustworthy() then
        -- Absorb the current (possibly stale) key state without acting on it,
        -- so a key that's actually stuck down doesn't register as a fresh
        -- edge once the settle window ends.
        wasEnterDown = enterDown
        wasEscapeDown = escapeDown
        return
    end

    local enterEdge = enterDown and not wasEnterDown
    local escapeEdge = escapeDown and not wasEscapeDown

    wasEnterDown = enterDown
    wasEscapeDown = escapeDown

    if enterEdge then
        chatAssumedOpenAt = nowSeconds() -- (re)start/extend the window; every Enter counts the same, open or send
    elseif escapeEdge then
        chatAssumedOpenAt = nil -- explicit early-out when this DOES make it through
    elseif isChatAssumedOpen() and anyTypingKeyDown() then
        chatAssumedOpenAt = nowSeconds() -- still actively typing (or holding a key) - keep the window alive
    end
end

---Call once per render frame, UNCONDITIONALLY - this has to run every frame
---no matter what else is going on (hotkeys disabled, mid-capture, etc.) or
---it'll miss an Enter/Escape edge and get out of sync. See CheckHotkeys.
function BMHotkeys.UpdateChatTracking()
    local ok, err = pcall(updateChatTrackingFromKeys)
    if not ok then
        btnUtils.Debug("BMHotkeys.UpdateChatTracking failed: %s", tostring(err))
    end
end

-- Off switch for the best-effort window lookup, independent of the
-- self-tracked Enter/Escape timer. Defaults off: on some UI setups
-- "ChatWindow" reports Highlighted=true even while not typing, a false
-- positive that blocks hotkeys permanently. Dev menu toggle to re-enable.
BMHotkeys.EnableWindowLookup = false

---True if EQ's chat input currently has focus (the player is typing a
---message/command) by either signal: the best-effort window lookup above,
---or the self-tracked Enter/Escape heuristic. Either firing is enough - a
---false "still typing" for a few seconds costs nothing, a missed one lets a
---hotkey leak into someone's tell. Also returns which signal fired, for
---debug logging (see CheckHotkeys).
---@return boolean active
---@return string? reason
function BMHotkeys.IsChatInputActive()
    if isChatAssumedOpen() then
        local secondsLeft = BMHotkeys.ChatGraceSeconds - (nowSeconds() - chatAssumedOpenAt)
        -- rounded up to a whole second for display - %d errors on a non-integer
        -- float, which secondsLeft almost always is (mq.gettime() is milliseconds)
        return true, string.format("Enter-tracked grace window, %ds left", math.max(math.ceil(secondsLeft), 0))
    end

    if BMHotkeys.EnableWindowLookup then
        local matched = isKnownChatWindowFocused()
        if matched then
            return true, "window lookup matched " .. matched
        end
    end

    return false, nil
end

return BMHotkeys
