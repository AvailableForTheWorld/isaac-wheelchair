-- Run from the repository root with Lua 5.3+ (or lupa's Lua runtime).
-- Native rewind availability and physical device input still need an in-game check.
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, message .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end

local G, R, RT = 71, 82, 12
local UPDATE = 1
local MENU_RT = 27

local function loadMod(options)
    options = options or {}
    local keyboardIndex = options.keyboardIndex or -2
    local state = {
        keyboard = {},
        controllers = {},
        buttonValues = {},
        actions = {},
        players = options.players or { keyboardIndex },
        paused = false,
        commands = {},
        callbacks = {},
    }
    local game = {
        IsPaused = function() return state.paused end,
        GetNumPlayers = function() return #state.players end,
    }
    local mod = {
        AddCallback = function(_, callback, fn)
            assert(state.callbacks[callback] == nil, "callback registered twice")
            state.callbacks[callback] = fn
        end,
    }
    local mcm = {
        Config = { Wheelchair = options.config or {} },
        IsVisible = false,
        SetCategoryInfo = function() end,
        AddTitle = function() end,
        AddSpace = function() end,
        AddText = function() end,
    }
    local function addSetting(category, _, attribute, defaultValue)
        if mcm.Config[category][attribute] == nil then
            mcm.Config[category][attribute] = defaultValue
        end
    end
    mcm.AddKeyboardSetting = addSetting
    mcm.AddControllerSetting = addSetting

    local function buttonPressed(button, controllerIndex)
        if controllerIndex == keyboardIndex then
            if state.keyboard[button] then return true end
            -- Older input layouts could also report controller aliases at index 0.
            local buttons = state.controllers[controllerIndex]
            return buttons ~= nil and buttons[button % 32] == true
        end
        if controllerIndex == -2 then
            if options.rejectModernIndex then error("invalid controller index") end
            return false
        end
        if controllerIndex == -1 then
            if state.keyboard[button] then return true end
            for _, buttons in pairs(state.controllers) do
                if buttons[button % 32] then return true end
            end
            return false
        end
        local buttons = state.controllers[controllerIndex]
        -- The engine can alias keyboard scan codes to physical controller buttons.
        return buttons ~= nil and buttons[button % 32] == true
    end

    local input = { IsButtonPressed = buttonPressed }
    if not options.omitAnalogAPI then
        input.GetButtonValue = function(button, controllerIndex)
            local values = state.buttonValues[controllerIndex]
            return values and values[button] or 0
        end
    end
    if not options.omitActionAPI then
        input.IsActionPressed = function(action, controllerIndex)
            local actions = state.actions[controllerIndex]
            return actions ~= nil and actions[action] == true
        end
    end

    local env = setmetatable({
        REPENTANCE_PLUS = options.repentancePlus ~= false,
        Keyboard = { KEY_G = G },
        ButtonAction = { ACTION_MENURT = MENU_RT },
        ModCallbacks = { MC_POST_UPDATE = UPDATE },
        Options = { Language = "en" },
        RegisterMod = function() return mod end,
        Game = function() return game end,
        Input = input,
        Isaac = {
            GetPlayer = function(index)
                assert(state.players[index + 1] ~= nil, "missing player")
                return { ControllerIndex = state.players[index + 1] }
            end,
            ExecuteCommand = function(command)
                equal(command, "rewind", "only use native rewind")
                state.commands[#state.commands + 1] = command
            end,
        },
        require = function(name)
            assert(name == "scripts.modconfig", "unexpected module: " .. name)
            if not options.mcm then error("Mod Config Menu is not installed") end
            return mcm
        end,
    }, { __index = _G })
    assert(loadfile("mods/wheelchair/content/main.lua", "t", env))()
    equal(type(state.callbacks[UPDATE]), "function", "register update callback")
    function state:tick()
        self.callbacks[UPDATE](mod)
    end
    function state:controller(index, button, pressed)
        self.controllers[index] = self.controllers[index] or {}
        self.controllers[index][button] = pressed
    end
    function state:analog(index, button, value)
        self.buttonValues[index] = self.buttonValues[index] or {}
        self.buttonValues[index][button] = value
    end
    function state:action(index, action, pressed)
        self.actions[index] = self.actions[index] or {}
        self.actions[index][action] = pressed
    end
    state.mcm = mcm
    return state
end

-- Repentance+ 1.9.7.19 moved the keyboard from index 0 to -2.
local modern = loadMod()
modern:tick()
modern.keyboard[G] = true
modern:tick()
equal(#modern.commands, 1, "modern keyboard G works without MCM")
for _ = 1, 5 do modern:tick() end
equal(#modern.commands, 1, "holding G does not repeat rewind")
modern.keyboard[G] = false
modern:tick()
modern.keyboard[G] = true
modern:tick()
equal(#modern.commands, 2, "release and press G again")

local alias = loadMod({ players = { -2, 0 } })
alias:controller(0, G % 32, true)
alias:tick()
equal(#alias.commands, 0, "controller scan-code alias does not impersonate G")
alias.keyboard[G] = true
alias:tick()
equal(#alias.commands, 1, "controller alias does not suppress real keyboard G")

local keyboardOnly = loadMod()
keyboardOnly.keyboard[RT] = true
keyboardOnly:tick()
equal(#keyboardOnly.commands, 0, "keyboard player is not a physical controller")

local controllers = loadMod({ players = { 0, 0, 1 } })
controllers:controller(0, RT, true)
controllers:tick()
equal(#controllers.commands, 1, "first controller is now index zero")
controllers:tick()
equal(#controllers.commands, 1, "shared controller and held RT do not repeat")
controllers:controller(1, RT, true)
controllers:tick()
equal(#controllers.commands, 2, "another player's controller has its own edge")
controllers:controller(0, RT, false)
controllers:tick()
controllers:controller(0, RT, true)
controllers:tick()
equal(#controllers.commands, 3, "controller release rearms RT")

-- Newer Repentance+ builds can report RT as an analog value or menu action
-- while its raw IsButtonPressed value stays false.
local analog = loadMod({ players = { 0 } })
analog:analog(0, RT, 0.49)
analog:analog(1, RT, 1)
analog:tick()
equal(#analog.commands, 0, "ignore subthreshold RT and another controller's analog value")
analog:analog(0, RT, 0.5)
analog:tick()
equal(#analog.commands, 1, "analog RT activates at the threshold without raw input")
analog:analog(0, RT, 0.9)
analog:tick()
equal(#analog.commands, 1, "holding analog RT does not repeat")
analog:analog(0, RT, 0.49)
analog:tick()
analog:analog(0, RT, 0.51)
analog:tick()
equal(#analog.commands, 2, "releasing below threshold rearms analog RT")

local menuAction = loadMod({ players = { 1 } })
menuAction:action(0, MENU_RT, true)
menuAction:tick()
equal(#menuAction.commands, 0, "ignore another controller's RT action")
menuAction:action(1, MENU_RT, true)
menuAction:tick()
equal(#menuAction.commands, 1, "assigned controller RT action works without raw input")
menuAction:tick()
equal(#menuAction.commands, 1, "holding the RT action does not repeat")
menuAction:action(1, MENU_RT, false)
menuAction:tick()
menuAction:action(1, MENU_RT, true)
menuAction:tick()
equal(#menuAction.commands, 2, "release rearms the RT action")

local legacyKeyboardAction = loadMod({ keyboardIndex = 0, players = { 0 }, repentancePlus = false })
legacyKeyboardAction:action(0, MENU_RT, true)
legacyKeyboardAction:tick()
equal(#legacyKeyboardAction.commands, 0, "legacy keyboard MENU RT binding cannot impersonate a trigger")

local combinedRT = loadMod({ players = { 1 } })
combinedRT:controller(1, RT, true)
combinedRT:tick()
combinedRT:controller(1, RT, false)
combinedRT:analog(1, RT, 0.8)
combinedRT:tick()
combinedRT:analog(1, RT, 0)
combinedRT:action(1, MENU_RT, true)
combinedRT:tick()
equal(#combinedRT.commands, 1, "switching RT reporting channels does not create extra edges")
combinedRT:action(1, MENU_RT, false)
combinedRT:tick()
combinedRT:action(1, MENU_RT, true)
combinedRT:tick()
equal(#combinedRT.commands, 2, "RT rearms after every reporting channel is released")

local customController = loadMod({ mcm = true, players = { 1 }, config = {
    KeyboardShortcut = -1, ControllerShortcut = 4,
} })
customController:analog(1, RT, 1)
customController:analog(1, 4, 1)
customController:action(1, MENU_RT, true)
customController:tick()
equal(#customController.commands, 0, "custom button does not inherit RT action or analog fallbacks")
customController:controller(1, 4, true)
customController:tick()
equal(#customController.commands, 1, "custom controller button retains its raw binding")

local unboundRT = loadMod({ mcm = true, players = { 1 }, config = {
    KeyboardShortcut = -1, ControllerShortcut = -1,
} })
unboundRT:controller(1, RT, true)
unboundRT:analog(1, RT, 1)
unboundRT:action(1, MENU_RT, true)
unboundRT:tick()
equal(#unboundRT.commands, 0, "unbound controller ignores all RT reporting channels")

local olderInput = loadMod({ players = { 0 }, omitAnalogAPI = true, omitActionAPI = true })
olderInput:controller(0, RT, true)
olderInput:tick()
equal(#olderInput.commands, 1, "raw RT works when optional input APIs are unavailable")
local actionOnly = loadMod({ players = { 1 }, omitAnalogAPI = true })
actionOnly:action(1, MENU_RT, true)
actionOnly:tick()
equal(#actionOnly.commands, 1, "RT action remains usable without the analog API")
local analogOnly = loadMod({ players = { 0 }, omitActionAPI = true })
analogOnly:analog(0, RT, 1)
analogOnly:tick()
equal(#analogOnly.commands, 1, "analog RT remains usable without the action API")

local simultaneous = loadMod({ players = { -2, 0 } })
simultaneous.keyboard[G] = true
simultaneous:controller(0, RT, true)
simultaneous:tick()
equal(#simultaneous.commands, 1, "simultaneous shortcuts request one rewind")

local configured = loadMod({ mcm = true, players = { -2, 0 }, config = {
    KeyboardShortcut = R, ControllerShortcut = 4,
} })
configured.keyboard[G] = true
configured:controller(0, RT, true)
configured:tick()
equal(#configured.commands, 0, "configured bindings replace defaults")
configured.keyboard[R] = true
configured:tick()
equal(#configured.commands, 1, "custom keyboard shortcut")
configured:controller(0, 4, true)
configured:tick()
equal(#configured.commands, 2, "custom controller shortcut")
configured.mcm.Config.Wheelchair.KeyboardShortcut = -1
configured.mcm.Config.Wheelchair.ControllerShortcut = -1
configured.keyboard[R] = false
configured:controller(0, 4, false)
configured:tick()
configured.keyboard[R] = true
configured:controller(0, 4, true)
configured:tick()
equal(#configured.commands, 2, "unbound shortcuts cannot trigger rewind")

local paused = loadMod()
paused.paused = true
paused.keyboard[G] = true
paused:tick()
equal(#paused.commands, 0, "paused game ignores shortcut")
paused.paused = false
paused:tick()
equal(#paused.commands, 0, "held shortcut does not fire after unpausing")
paused.keyboard[G] = false
paused:tick()
paused.keyboard[G] = true
paused:tick()
equal(#paused.commands, 1, "new press after unpausing works")

local noPlayers = loadMod({ players = {} })
noPlayers.keyboard[G] = true
noPlayers:tick()
equal(#noPlayers.commands, 0, "cannot rewind outside a run")

local menu = loadMod({ mcm = true, players = { -2, 0 } })
menu.mcm.IsVisible = true
menu.keyboard[G] = true
menu:controller(0, RT, true)
menu:tick()
equal(#menu.commands, 0, "MCM captures shortcuts without rewind")
menu.keyboard[G] = false
menu:controller(0, RT, false)
menu:tick()
menu.mcm.IsVisible = false
menu:controller(0, RT, true)
menu:tick()
equal(#menu.commands, 0, "button closing MCM cannot rewind")
menu:tick()
equal(#menu.commands, 0, "holding menu close button cannot rewind")
menu:controller(0, RT, false)
menu:tick()
menu:controller(0, RT, true)
menu:tick()
equal(#menu.commands, 1, "fresh press after MCM closes works")

-- Preserve older Repentance/Repentance+ input layouts. Some builds reject -2;
-- others simply report no input there, so cover both forms of fallback.
for _, rejectsIndex in ipairs({ false, true }) do
    local legacy = loadMod({
        keyboardIndex = 0,
        rejectModernIndex = rejectsIndex,
        players = { 0, 1 },
        repentancePlus = false,
    })
    legacy.keyboard[G] = true
    legacy:tick()
    equal(#legacy.commands, 1, "legacy keyboard index zero works")
    legacy:tick()
    equal(#legacy.commands, 1, "legacy held key does not repeat")
    legacy.keyboard[G] = false
    legacy:tick()
    legacy:controller(0, G % 32, true)
    legacy:tick()
    equal(#legacy.commands, 1, "legacy scan-code alias guard remains active")
    legacy:controller(0, G % 32, false)
    legacy:controller(1, RT, true)
    legacy:tick()
    equal(#legacy.commands, 2, "legacy physical controller index one works")
end

print("wheelchair_spec: " .. checks .. " checks passed")
