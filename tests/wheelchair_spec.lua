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

local function loadMod(options)
    options = options or {}
    local keyboardIndex = options.keyboardIndex or -2
    local state = {
        keyboard = {},
        controllers = {},
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

    local env = setmetatable({
        REPENTANCE_PLUS = options.repentancePlus ~= false,
        Keyboard = { KEY_G = G },
        ModCallbacks = { MC_POST_UPDATE = UPDATE },
        Options = { Language = "en" },
        RegisterMod = function() return mod end,
        Game = function() return game end,
        Input = { IsButtonPressed = buttonPressed },
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
