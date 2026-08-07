local Wheelchair = RegisterMod("Wheelchair Emergency Rewind", 1)
local game = Game()

local DEFAULT_KEYBOARD_SHORTCUT = Keyboard.KEY_G
local DEFAULT_CONTROLLER_SHORTCUT = 12 -- Controller.TRIGGER_RIGHT in MCM
local MCM_CATEGORY = "Wheelchair"
local MCM_SUBCATEGORY = "Controls"

local TRANSLATIONS = {
    en = {
        categoryInfo = "Configure the keyboard and controller shortcuts for the native one-step rewind.",
        title = "Emergency Rewind",
        keyboardShortcut = "Keyboard shortcut",
        keyboardHelp = "Press a keyboard key to use for rewind. Go back without choosing a key to unbind it.",
        controllerShortcut = "Controller shortcut",
        controllerHelp = "Press a controller button to use for rewind. Go back without choosing a button to unbind it.",
        defaults = "Defaults: G / Right Trigger",
    },
    zh = {
        categoryInfo = "配置原生单步房间回溯的键盘和手柄快捷键。",
        title = "紧急回溯",
        keyboardShortcut = "键盘快捷键",
        keyboardHelp = "按下一个键盘按键，将其设为回溯快捷键。不选择按键并返回即可解除绑定。",
        controllerShortcut = "手柄快捷键",
        controllerHelp = "按下一个手柄按键，将其设为回溯快捷键。不选择按键并返回即可解除绑定。",
        defaults = "默认：G / 右扳机",
    },
}

local function getTranslation()
    if Options and Options.Language == "zh" then
        return TRANSLATIONS.zh
    end
    return TRANSLATIONS.en
end

local mcmLoaded, MCM = pcall(require, "scripts.modconfig")
local mcmWasVisible = false
local keyboardPressed = false
local trackedKeyboardShortcut = nil
local controllerPressedByIndex = {}
local trackedControllerShortcut = nil

if mcmLoaded then
    local text = getTranslation()

    MCM.SetCategoryInfo(
        MCM_CATEGORY,
        text.categoryInfo
    )
    MCM.AddTitle(MCM_CATEGORY, MCM_SUBCATEGORY, text.title)
    MCM.AddKeyboardSetting(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        "KeyboardShortcut",
        DEFAULT_KEYBOARD_SHORTCUT,
        text.keyboardShortcut,
        true,
        text.keyboardHelp
    )
    MCM.AddControllerSetting(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        "ControllerShortcut",
        DEFAULT_CONTROLLER_SHORTCUT,
        text.controllerShortcut,
        true,
        text.controllerHelp
    )
    MCM.AddSpace(MCM_CATEGORY, MCM_SUBCATEGORY)
    MCM.AddText(MCM_CATEGORY, MCM_SUBCATEGORY, text.defaults)
end

local function getConfiguredShortcut(attribute, defaultValue)
    if mcmLoaded
        and MCM.Config[MCM_CATEGORY] ~= nil
        and type(MCM.Config[MCM_CATEGORY][attribute]) == "number" then
        return MCM.Config[MCM_CATEGORY][attribute]
    end
    return defaultValue
end

local function rewind()
    if not game:IsPaused() and game:GetNumPlayers() > 0 then
        Isaac.ExecuteCommand("rewind")
    end
end

local function keyboardShortcutTriggered()
    local shortcut = getConfiguredShortcut("KeyboardShortcut", DEFAULT_KEYBOARD_SHORTCUT)
    if shortcut ~= trackedKeyboardShortcut then
        keyboardPressed = false
        trackedKeyboardShortcut = shortcut
    end
    if shortcut < 0 then return false end

    -- Isaac can report a controller button whose number overlaps a keyboard
    -- key. This is the same guard used by Mod Config Menu's input helper.
    local pressed = Input.IsButtonPressed(shortcut, 0)
        and not Input.IsButtonPressed(shortcut % 32, 0)
    local triggered = pressed and not keyboardPressed
    keyboardPressed = pressed
    return triggered
end

local function controllerShortcutTriggered()
    local shortcut = getConfiguredShortcut("ControllerShortcut", DEFAULT_CONTROLLER_SHORTCUT)
    if shortcut ~= trackedControllerShortcut then
        controllerPressedByIndex = {}
        trackedControllerShortcut = shortcut
    end
    if shortcut < 0 then return false end

    local activeControllerIndexes = {}
    local triggered = false
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        local controllerIndex = player.ControllerIndex

        if not activeControllerIndexes[controllerIndex] then
            local pressed = Input.IsButtonPressed(shortcut, controllerIndex)
            if pressed and not controllerPressedByIndex[controllerIndex] then
                triggered = true
            end

            controllerPressedByIndex[controllerIndex] = pressed
            activeControllerIndexes[controllerIndex] = true
        end
    end

    return triggered
end

function Wheelchair:OnUpdate()
    -- Track held states even while MCM is visible or the game is paused.
    -- Unlike Isaac's one-update IsButtonTriggered event, these checks cannot
    -- miss a normal multi-frame press. The rising edges still ensure that
    -- each physical press requests at most one rewind.
    local keyboardTriggered = keyboardShortcutTriggered()
    local controllerTriggered = controllerShortcutTriggered()

    -- Do not activate rewind while the same buttons are being captured or
    -- used to navigate Mod Config Menu.
    if mcmLoaded and MCM.IsVisible then
        mcmWasVisible = true
        return
    end
    if mcmWasVisible then
        -- Swallow the button press that closed MCM, especially when that same
        -- controller button has just been selected as the rewind shortcut.
        mcmWasVisible = false
        return
    end

    if keyboardTriggered or controllerTriggered then
        rewind()
    end
end

Wheelchair:AddCallback(ModCallbacks.MC_POST_UPDATE, Wheelchair.OnUpdate)
