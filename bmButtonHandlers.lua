local mq                 = require('mq')
local btnUtils           = require('lib.buttonUtils')
local BMHotkeys          = require('bmHotkeys')

-- Icon Rendering
local animItems          = mq.FindTextureAnimation("A_DragItem")
local animSpellIcons     = mq.FindTextureAnimation('A_SpellIcons')

---@class BMButtonHandlers
local BMButtonHandlers   = {}
BMButtonHandlers.__index = BMButtonHandlers

function BMButtonHandlers.GetTimeMS()
    return mq.gettime() / 1000
end

-- A click that switches window focus between characters can be seen by this
-- client's ImGui as a mouse-down with no matching mouse-up, which Dear
-- ImGui's drag-and-drop then misreads as a long-press on whatever button it
-- landed on. Foreground state alone isn't enough to filter this out, since
-- that stray mouse-down can be the very thing still "down" on the first
-- frame this client regains foreground - so require a short settle period
-- of stable foreground before trusting click-and-hold interaction again.
-- See BMHotbarClass:RenderButtons.
local INTERACTION_SETTLE_FRAMES = 20 -- roughly a third of a second at 60fps
local wasForeground = false
local foregroundStableFrames = 0

---Call once per render frame, unconditionally (see init.lua's ButtonGUI) -
---has to run every frame regardless of what else is going on or it'll miss
---a focus transition and get out of sync.
function BMButtonHandlers.UpdateFocusTracking()
    local ok, isForeground = pcall(function() return mq.TLO.EverQuest.Foreground() end)
    if not ok then isForeground = true end -- fail open rather than permanently locking out interaction

    if isForeground and wasForeground then
        foregroundStableFrames = foregroundStableFrames + 1
    else
        foregroundStableFrames = 0
    end
    wasForeground = isForeground
end

---False right as this client's window regains foreground (or while it's in
---the background) - true once it's been stably foregrounded for a short
---settle window. Gate click-and-hold interaction (drag-and-drop) on this.
---@return boolean
function BMButtonHandlers.IsInteractionSafe()
    return foregroundStableFrames >= INTERACTION_SETTLE_FRAMES
end

---@param Button table # BMButtonConfig
function BMButtonHandlers.ExportButtonToClipBoard(Button)
    local sharableButton = { Type = "Button", Button = Button, }
    ImGui.SetClipboardText(btnUtils.encodeTable(sharableButton))
    btnUtils.Output("Button: '%s' has been copied to your clipboard!", Button.Label)
    local printableButton = btnUtils.dumpTable(sharableButton):gsub("\n/", "\\n/")
    btnUtils.Output('\n' .. printableButton)
end

function BMButtonHandlers:ExportSetToClipBoard(setKey)
    local sharableSet = { Type = "Set", Key = setKey, Set = {}, Buttons = {}, }
    for index, btnName in pairs(BMSettings:GetSettings().Sets[setKey]) do
        sharableSet.Set[index] = btnName
    end
    for _, buttonKey in pairs(BMSettings:GetSettings().Sets[setKey] or {}) do
        sharableSet.Buttons[buttonKey] = BMSettings:GetSettings().Buttons[buttonKey]
    end
    ImGui.SetClipboardText(btnUtils.encodeTable(sharableSet))
end

---@param Button table # BMButtonConfig
---@return integer, integer, boolean #CountDown, CooldownTimer, Toggle Locked
function BMButtonHandlers.GetButtonCooldown(Button, cacheUpdate)
    if not cacheUpdate and Button.CachedCountDown ~= nil and Button.CachedCoolDownTimer ~= nil and Button.CachedToggleLocked ~= nil then
        return Button.CachedCountDown, Button.CachedCoolDownTimer, Button.CachedToggleLocked
    end

    Button.CachedCountDown     = 0
    Button.CachedCoolDownTimer = 0
    Button.CachedToggleLocked  = false
    Button.CachedLastRan       = BMButtonHandlers.GetTimeMS()

    if Button.TimerType == "Custom Lua" then
        local success
        local result

        if Button.Timer and Button.Timer:len() > 0 then
            success, result = btnUtils.EvaluateLua(Button.Timer)
            if not success then
                btnUtils.Output("Failed to run Timer for Button(%s): %s", Button.Label, Button.Timer)
                btnUtils.Output("RunEnv was:\n%s", Button.Timer)
                Button.CachedCountDown = 0
            else
                Button.CachedCountDown = tonumber(result) or 0
            end
        end
        if Button.Cooldown and Button.Cooldown:len() > 0 then
            success, result = btnUtils.EvaluateLua(Button.Cooldown)
            if not success then
                btnUtils.Output("Failed to run Cooldown for Button(%s): %s", Button.Label, Button.Cooldown)
                btnUtils.Output("RunEnv was:\n%s", Button.Cooldown)
                Button.CachedCoolDownTimer = 0
            else
                Button.CachedCoolDownTimer = tonumber(result) or 0
            end
        end
        if Button.ToggleCheck and Button.ToggleCheck:len() > 0 then
            success, result = btnUtils.EvaluateLua(Button.ToggleCheck)
            if not success then
                btnUtils.Output("Failed to run ToggleCheck for Button(%s): %s", Button.Label, Button.ToggleCheck)
                btnUtils.Output("RunEnv was:\n%s", Button.ToggleCheck)
                Button.CachedToggleLocked = false
            else
                Button.CachedToggleLocked = type(result) == 'boolean' and result or false
            end
        end
    elseif Button.TimerType == "Seconds Timer" then
        if Button.CooldownTimer then
            Button.CachedCountDown = Button.CooldownTimer - BMButtonHandlers.GetTimeMS()
            if Button.CachedCountDown <= 0 or Button.CachedCountDown > Button.CooldownTimer then
                Button.CooldownTimer = nil
                return 0, 0, false
            end
            Button.CachedCoolDownTimer = Button.Cooldown
        end
    elseif Button.TimerType == "Item" then
        Button.CachedCountDown = mq.TLO.FindItem(Button.Cooldown).TimerReady() or 0
        Button.CachedCoolDownTimer = mq.TLO.FindItem(Button.Cooldown).Clicky.TimerID() or 0
    elseif Button.TimerType == "Spell Gem" then
        Button.CachedCountDown = (mq.TLO.Me.GemTimer(Button.Cooldown)() or 0) / 1000
        Button.CachedCoolDownTimer = (mq.TLO.Me.Gem(Button.Cooldown).RecastTime() or 0) / 1000
    elseif Button.TimerType == "AA" then
        Button.CachedCountDown = (mq.TLO.Me.AltAbilityTimer(Button.Cooldown)() or 0) / 1000
        Button.CachedCoolDownTimer = mq.TLO.Me.AltAbility(Button.Cooldown).MyReuseTime() or 0
    elseif Button.TimerType == "Disc" then
        Button.CachedCountDown = mq.TLO.Me.CombatAbilityTimer(Button.Cooldown).TotalSeconds() or 0
        Button.CachedCoolDownTimer = (mq.TLO.Spell(Button.Cooldown).RecastTime() or 0) / 1000
    elseif Button.TimerType == "Ability" then
        if mq.TLO.Me.AbilityTimer and mq.TLO.Me.AbilityTimerTotal then
            Button.CachedCountDown = (mq.TLO.Me.AbilityTimer(Button.Cooldown)() or 0) / 1000
            Button.CachedCoolDownTimer = (mq.TLO.Me.AbilityTimerTotal(Button.Cooldown)() or 0) / 1000
        end
    end

    return Button.CachedCountDown, Button.CachedCoolDownTimer, Button.CachedToggleLocked
end

---@param Button table # BMButtonConfig
---@param cursorScreenPos table # cursor position on screen
---@param size number # button size
function BMButtonHandlers.RenderButtonCooldown(Button, cursorScreenPos, size)
    local currentTimer = BMButtonHandlers.GetTimeMS()
    local updateRate = Button.UpdateRate or 0

    local updateCache = (Button.CachedLastRan == nil or ((currentTimer - Button.CachedLastRan) > updateRate) or ((currentTimer - Button.CachedLastRan) < 0))
    local countDown, coolDowntimer, toggleLocked = BMButtonHandlers.GetButtonCooldown(Button, updateCache)

    if coolDowntimer == 0 and not toggleLocked then return end

    local ratio = 1 - (countDown / (coolDowntimer))

    if toggleLocked then
        ratio = 100
    end

    local start_angle = (1.5 * math.pi)
    local end_angle = math.pi * ((2 * ratio) - 0.5)
    local center = ImVec2(cursorScreenPos.x + (size / 2), cursorScreenPos.y + (size / 2))

    local draw_list = ImGui.GetWindowDrawList()
    draw_list:PushClipRect(cursorScreenPos, ImVec2(cursorScreenPos.x + size, cursorScreenPos.y + size), true)
    draw_list:PathLineTo(center)
    draw_list:PathArcTo(center, size, start_angle, end_angle, 0)
    draw_list:PathFillConvex(ImGui.GetColorU32(0.8, 0.02, 0.02, 0.75))
    draw_list:PopClipRect()
end

---@param Button table # BMButtonConfig
---@param cursorScreenPos ImVec2 # cursor position on screen
---@param size number # button size
function BMButtonHandlers.RenderButtonIcon(Button, cursorScreenPos, size)
    if not Button.Icon and (not Button.IconLua or Button.IconLua:len() == 0) then
        return BMButtonHandlers.RenderButtonRect(Button, cursorScreenPos, size, 255)
    end

    local draw_list = ImGui.GetWindowDrawList()

    local iconId = Button.Icon
    local iconType = Button.IconType

    if Button.IconLua and Button.IconLua:len() > 0 then
        local success
        success, iconId, iconType = btnUtils.EvaluateLua(Button.IconLua)
        if not success then
            btnUtils.Debug("Failed to evaluate IconLua: %s\nError:\n%s", Button.IconLua, iconId)
            iconId = Button.Icon
            iconType = Button.IconType
        end
    end

    local renderIconAnim = animItems
    if iconType == nil or iconType == "Spell" then
        animSpellIcons:SetTextureCell(tonumber(iconId) or 0)
        renderIconAnim = animSpellIcons
    else
        animItems:SetTextureCell(tonumber(iconId) or 0)
    end

    draw_list:AddTextureAnimation(renderIconAnim, cursorScreenPos, ImVec2(size, size))
end

---@param Button table # BMButtonConfig
---@param cursorScreenPos ImVec2 # cursor position on screen
---@param size number # button size
---@param alpha number # button alpha color
function BMButtonHandlers.RenderButtonRect(Button, cursorScreenPos, size, alpha)
    local draw_list = ImGui.GetWindowDrawList()
    local buttonStyle = ImGui.GetStyleColorVec4(ImGuiCol.Button)
    local Colors = btnUtils.split(Button.ButtonColorRGB, ",")
    local buttonBGCol = IM_COL32(tonumber(Colors[1]) or math.floor(buttonStyle.x * 255),
        tonumber(Colors[2]) or math.floor(buttonStyle.y * 255),
        tonumber(Colors[3]) or math.floor(buttonStyle.z * 255),
        #Colors == 0 and math.floor(buttonStyle.w * 255) or alpha)

    draw_list:AddRectFilled(cursorScreenPos, ImVec2(cursorScreenPos.x + size, cursorScreenPos.y + size), buttonBGCol)
end

---@param Button table # BMButtonConfig
---@param label string
---@param subText string?
function BMButtonHandlers.RenderButtonTooltip(Button, label, subText, Hotkey)
    -- hover tooltip
    if Button.Unassigned == nil and ImGui.IsItemHovered() then
        local tooltipText = label

        -- check label instead of tooltipText because if there is no text we dont care about the timer.
        if label:len() > 0 then
            local countDown, _ = BMButtonHandlers.GetButtonCooldown(Button)
            if countDown ~= 0 then
                tooltipText = tooltipText .. "\n\n" .. btnUtils.FormatTime(math.ceil(countDown))
            end

            if Hotkey then
                tooltipText = tooltipText .. "\nHotkey: " .. BMHotkeys.FormatHotkey(Hotkey)
            end

            ImGui.BeginTooltip()
            ImGui.Text(tooltipText)
            if subText then
                ImGui.Separator()
                ImGui.Text(subText)
            end
            ImGui.EndTooltip()
        end
    end
end

---@param Button table # BMButtonConfig
---@param cursorScreenPos ImVec2 # cursor position on screen
---@param size number # button size
---@param Hotkey table? # this character's Hotkey for this button, if any (see BMSettings:GetButtonHotkey)
function BMButtonHandlers.RenderButtonHotkeyBadge(Button, cursorScreenPos, size, Hotkey)
    if not Hotkey or not Hotkey.Key then return end

    local ok, keyName = pcall(ImGui.GetKeyName, Hotkey.Key)
    if not ok or not keyName or keyName:len() == 0 then return end

    local draw_list = ImGui.GetWindowDrawList()
    ImGui.SetWindowFontScale(0.7)
    local textW, textH = ImGui.CalcTextSize(keyName)
    ImGui.SetWindowFontScale(1)

    local pos = ImVec2(cursorScreenPos.x + size - textW - 2, cursorScreenPos.y + 1)
    draw_list:AddRectFilled(pos, ImVec2(pos.x + textW + 2, pos.y + textH), IM_COL32(0, 0, 0, 140))

    ImGui.SetWindowFontScale(0.7)
    draw_list:AddText(pos, IM_COL32(255, 255, 0, 255), keyName)
    ImGui.SetWindowFontScale(1)
end

---@param Button table # BMButtonConfig
---@param cursorScreenPos ImVec2 # cursor position on screen
---@param size number # button size
---@param label string
function BMButtonHandlers.RenderButtonLabel(Button, cursorScreenPos, size, label)
    local Colors = btnUtils.split(Button.TextColorRGB, ",")
    local buttonLabelCol = IM_COL32(tonumber(Colors[1]) or 255, tonumber(Colors[2]) or 255, tonumber(Colors[3]) or 255, 255)
    local draw_list = ImGui.GetWindowDrawList()

    BMButtonHandlers.CalcButtonTextPos(Button, size)

    draw_list:PushClipRect(cursorScreenPos, ImVec2(cursorScreenPos.x + size, cursorScreenPos.y + size), true)
    draw_list:AddText(ImVec2(cursorScreenPos.x + (Button.labelMidX or 0), cursorScreenPos.y + (Button.labelMidY or 0)), buttonLabelCol, label)
    draw_list:PopClipRect()
end

---@param cursorScreenPos ImVec2 # cursor position on screen
---@param text string
function BMButtonHandlers.RenderButtonDebugText(cursorScreenPos, text)
    local buttonLabelCol = IM_COL32(255, 0, 0, 255)
    local draw_list = ImGui.GetWindowDrawList()

    draw_list:AddText(ImVec2(cursorScreenPos.x, cursorScreenPos.y), buttonLabelCol, text)
end

---@param Button table # BMButtonConfig
---@param leaveSpaces boolean? # leave spaces or replace with new line.
function BMButtonHandlers.ResolveButtonLabel(Button, leaveSpaces, cacheUpdate)
    if not cacheUpdate and Button.CachedLabel ~= nil then
        return leaveSpaces and Button.CachedLabel or Button.CachedLabel:gsub(" ", "\n")
    end
    local success = true
    local evaluatedLabel = Button.Label

    if Button.EvaluateLabel then
        success, evaluatedLabel = btnUtils.EvaluateLua(Button.Label)
        if not success then
            btnUtils.Debug("Failed to evaluate Button Label:\n%s\nError:\n%s", Button.Label, evaluatedLabel)
        end
    end
    evaluatedLabel = tostring(evaluatedLabel)

    Button.CachedLabel = evaluatedLabel

    return leaveSpaces and Button.CachedLabel or Button.CachedLabel:gsub(" ", "\n")
end

function BMButtonHandlers.CalcButtonTextPos(Button, size)
    local label_x, label_y = ImGui.CalcTextSize(BMButtonHandlers.ResolveButtonLabel(Button, false))
    local midX, midY = math.max(math.floor((size - label_x) / 2), 0), math.floor((size - label_y) / 2)
    if midX ~= Button.labelMidX or midY ~= Button.labelMidY then
        Button.labelMidX, Button.labelMidY = midX, midY
    end
end

---@param Button table # BMButtonConfig
---@param size number # size to render the button as
---@param renderLabel boolean # render the label on top or not
---@param fontScale number # Font scale for text
---@param advTooltips boolean # enable advanced tooltips6
---@param ButtonKey string? # this button's key in BMSettings Buttons, so its per-character Hotkey (if any) can be looked up and shown
---@return boolean # clicked
function BMButtonHandlers.Render(Button, size, renderLabel, fontScale, advTooltips, ButtonKey)
    local evaluatedLabel = BMButtonHandlers.ResolveButtonLabel(Button) or ""
    local clicked = false
    local startTimeMS = os.clock() * 1000
    local cursorScreenPos = ImGui.GetCursorScreenPosVec()
    local hotkey = ButtonKey and BMSettings:GetButtonHotkey(ButtonKey) or nil

    BMButtonHandlers.RenderButtonIcon(Button, cursorScreenPos, size)
    clicked = ImGui.Selectable('', false, ImGuiSelectableFlags.DontClosePopups, size, size)
    if ImGui.IsItemHovered() then
        BMButtonHandlers.RenderButtonRect(Button, cursorScreenPos, size, 200)
    end

    BMButtonHandlers.RenderButtonCooldown(Button, cursorScreenPos, size)
    BMButtonHandlers.RenderButtonHotkeyBadge(Button, cursorScreenPos, size, hotkey)

    -- label and tooltip
    ImGui.SetWindowFontScale(fontScale)
    if renderLabel then
        BMButtonHandlers.RenderButtonLabel(Button, cursorScreenPos, size, evaluatedLabel)
    end
    BMButtonHandlers.RenderButtonTooltip(Button, evaluatedLabel, advTooltips and (Button.Cmd or nil) or nil, hotkey)
    ImGui.SetWindowFontScale(1)


    local endTimeMS = os.clock() * 1000

    local renderTimeMS = math.ceil(endTimeMS - startTimeMS)

    if btnUtils.enableDebug then
        if Button.highestRenderTime == nil or renderTimeMS > Button.highestRenderTime then Button.highestRenderTime = renderTimeMS end
        ImGui.SetWindowFontScale(0.8)
        BMButtonHandlers.RenderButtonDebugText(cursorScreenPos, tostring(Button.highestRenderTime))
        BMButtonHandlers.RenderButtonDebugText(ImVec2(cursorScreenPos.x, cursorScreenPos.y + 10), string.format("%d,%d", Button.labelMidX, Button.labelMidY))
        ImGui.SetWindowFontScale(1)
    end

    return clicked
end

function BMButtonHandlers.FireTimer(Button)
    if Button.TimerType == "Seconds Timer" then
        Button.CooldownTimer = BMButtonHandlers.GetTimeMS() + Button.Cooldown
    end
end

function BMButtonHandlers.EvaluateAndCache(Button)
    BMButtonHandlers.ResolveButtonLabel(Button, false, true)
end

---@param Button table # BMButtonConfig
function BMButtonHandlers.Exec(Button)
    if Button.Cmd then
        if Button.Cmd:find("^--[ ]?lua") == nil then
            local cmds = btnUtils.split(Button.Cmd, "\n")
            for i, c in ipairs(cmds) do
                if c:len() > 0 and c:find('^#') == nil and c:find('^[-]+') == nil and c:find('^|') == nil then
                    if c:find('^/') then
                        -- don't use cmdf here because users might have %'s in their commands.
                        mq.cmd(c)
                    else
                        btnUtils.Output('\arInvalid command on Line %d : \ax%s', i, c)
                    end
                else
                    btnUtils.Debug("Ignored: %s", c)
                end
            end
        else
            btnUtils.EvaluateLua(Button.Cmd)
        end
        BMButtonHandlers.FireTimer(Button)
    end
end

--- Scans every configured Button and Exec's any whose assigned Hotkey chord
--- was just pressed this frame. Call once per render frame (see init.lua).
--- Skipped while the button editor is capturing a new hotkey, while an ImGui
--- text field has keyboard focus, while EQ's own chat input line is focused
--- (typing a message/command), or while the current character has disabled
--- hotkeys (Windows Display Settings -> Enable/Disable Hotkeys).
function BMButtonHandlers.CheckHotkeys()
    -- Must run every frame no matter what else below short-circuits, or the
    -- Enter/Escape chat tracking it does can miss an edge and get out of sync.
    BMHotkeys.UpdateChatTracking()

    local settings = BMSettings and BMSettings:GetSettings()
    if not settings or not settings.Buttons then return end

    -- Hotkeys are per-character (BMSettings:GetCharHotkeys), not on the
    -- shared Button, so this only fires buttons *this* character bound.
    local charHotkeys = BMSettings:GetCharHotkeys()

    -- Find whatever chord(s) were actually pressed THIS frame before
    -- applying any gating below, so the debug logging only ever fires the
    -- instant you press a bound key - not every single frame - and tells
    -- you exactly which of the gates (if any) ate it. Enable this with the
    -- hotbar's right-click menu -> Dev -> Enable Debug.
    local pressed = {}
    for buttonKey, hotkey in pairs(charHotkeys) do
        local button = settings.Buttons[buttonKey]
        if button then
            local chord = BMHotkeys.BuildChord(hotkey)
            if chord and ImGui.IsKeyChordPressed(chord) then
                table.insert(pressed, { Button = button, Hotkey = hotkey })
            end
        end
    end
    if #pressed == 0 then return end

    local function label()
        return BMButtonHandlers.ResolveButtonLabel(pressed[1].Button, true)
    end

    if BMHotkeys.Listening then
        btnUtils.Debug("CheckHotkeys: '%s' pressed but skipped - currently capturing a new hotkey assignment", label())
        return
    end

    local charConfig = BMSettings:GetCharConfig()
    if charConfig and charConfig.HotkeysEnabled == false then
        btnUtils.Debug("CheckHotkeys: '%s' pressed but skipped - hotkeys are disabled for this character", label())
        return
    end

    local io = ImGui.GetIO()
    if io and io.WantTextInput then
        btnUtils.Debug("CheckHotkeys: '%s' pressed but skipped - an ImGui text field has keyboard focus", label())
        return
    end

    local chatActive, chatReason = BMHotkeys.IsChatInputActive()
    if chatActive then
        btnUtils.Debug("CheckHotkeys: '%s' pressed but skipped - chat input is presumed active (%s)", label(),
            chatReason or "?")
        return
    end

    for _, entry in ipairs(pressed) do
        btnUtils.Debug("CheckHotkeys: firing '%s' (%s)", BMButtonHandlers.ResolveButtonLabel(entry.Button, true),
            BMHotkeys.FormatHotkey(entry.Hotkey))
        BMButtonHandlers.Exec(entry.Button)
    end
end

return BMButtonHandlers
