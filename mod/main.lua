local Wheelchair = RegisterMod("Wheelchair Emergency Rewind", 1)
local game = Game()

local DEFAULT_KEYBOARD_SHORTCUT = Keyboard.KEY_G
local DEFAULT_CONTROLLER_SHORTCUT = 12 -- Controller.TRIGGER_RIGHT in MCM
local MCM_CATEGORY = "Wheelchair"
local MCM_SUBCATEGORY = "Controls"

local mcmLoaded, MCM = pcall(require, "scripts.modconfig")
local mcmWasVisible = false

if mcmLoaded then
    MCM.SetCategoryInfo(
        MCM_CATEGORY,
        "Configure the keyboard and controller shortcuts for the native one-step rewind."
    )
    MCM.AddTitle(MCM_CATEGORY, MCM_SUBCATEGORY, "Emergency Rewind")
    MCM.AddKeyboardSetting(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        "KeyboardShortcut",
        DEFAULT_KEYBOARD_SHORTCUT,
        "Keyboard shortcut",
        true,
        "Press a keyboard key to use for rewind. Go back without choosing a key to unbind it."
    )
    MCM.AddControllerSetting(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        "ControllerShortcut",
        DEFAULT_CONTROLLER_SHORTCUT,
        "Controller shortcut",
        true,
        "Press a controller button to use for rewind. Go back without choosing a button to unbind it."
    )
    MCM.AddSpace(MCM_CATEGORY, MCM_SUBCATEGORY)
    MCM.AddText(MCM_CATEGORY, MCM_SUBCATEGORY, "Defaults: G / Right Trigger")
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
    if shortcut < 0 then return false end

    -- Isaac can report a controller button whose number overlaps a keyboard
    -- key. This is the same guard used by Mod Config Menu's input helper.
    return Input.IsButtonTriggered(shortcut, 0)
        and not Input.IsButtonTriggered(shortcut % 32, 0)
end

local function controllerShortcutTriggered()
    local shortcut = getConfiguredShortcut("ControllerShortcut", DEFAULT_CONTROLLER_SHORTCUT)
    if shortcut < 0 then return false end

    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if Input.IsButtonTriggered(shortcut, player.ControllerIndex) then
            return true
        end
    end
    return false
end

function Wheelchair:OnUpdate()
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

    if keyboardShortcutTriggered() or controllerShortcutTriggered() then
        rewind()
    end
end

Wheelchair:AddCallback(ModCallbacks.MC_POST_UPDATE, Wheelchair.OnUpdate)
