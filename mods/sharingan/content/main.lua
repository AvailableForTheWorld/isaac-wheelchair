local BeginnerLedger = RegisterMod("Sharingan", 1)
local game = Game()
local json = require("json")
local I18N = include("i18n")

local UI_FONTS = { en = { body = Font(), small = Font() } }

UI_FONTS.en.bodyLoaded = UI_FONTS.en.body:Load("font/teammeatex/teammeatex12.fnt")
UI_FONTS.en.smallLoaded = UI_FONTS.en.small:Load("font/teammeatex/teammeatex10.fnt")

local ROOM_FILL_SPRITE = Sprite()
ROOM_FILL_SPRITE:Load("gfx/ui/sharingan_room_fill.anm2", true)
ROOM_FILL_SPRITE:SetFrame("Fill", 0)

local function currentFonts()
    return UI_FONTS[I18N.GetLanguage()] or UI_FONTS.en
end

local function tr(key)
    return I18N.Get(key)
end

local SAVE_SCHEMA = 3
local MAP_COLUMNS = 13
local MAP_ROWS = 13
local MAP_GRID_SIZE = MAP_COLUMNS * MAP_ROWS
local MAP_CELL_SIZE = 13
local LEGEND_ROWS_PER_COLUMN = 10
local LEGEND_COLUMN_WIDTH = 86
local LEGEND_ROW_HEIGHT = 13
local VISITED_SPECIAL_ROOM_COLOR = { 0.48, 0.50, 0.52 }
local UNVISITED_ROOM_FILL_COLOR = { 0.82, 0.84, 0.86, 1.00 }
local VISITED_ROOM_FILL_COLOR = { 0.26, 0.28, 0.30, 1.00 }
local ZERO_VECTOR = Vector(0, 0)
local DEFAULT_SPRITE_COLOR = Color(1, 1, 1, 1, 0, 0, 0)
local ROOM_FILL_UNVISITED_SPRITE_COLOR = Color(0.82, 0.84, 0.86, 1, 0, 0, 0)
local ROOM_FILL_VISITED_SPRITE_COLOR = Color(0.26, 0.28, 0.30, 1, 0, 0, 0)

local DEFAULT_KEYBOARD_SHORTCUT = Keyboard.KEY_F6
local DEFAULT_CONTROLLER_SHORTCUT = 10 -- Controller.STICK_LEFT in MCM
local MCM_CATEGORY = "Sharingan"
local LEGACY_MCM_CATEGORY = "Beginner Ledger"
local MCM_SUBCATEGORY = "Controls"

local MCM_TRANSLATIONS = {
    en = {
        categoryInfo = "Configure how the generated floor map is opened.",
        title = "Map controls",
        keyboardShortcut = "Keyboard shortcut",
        keyboardHelp = "Press a keyboard key to open or close the floor map. Go back without choosing a key to unbind it.",
        controllerShortcut = "Controller shortcut",
        controllerHelp = "Press a controller button to open or close the floor map. Go back without choosing a button to unbind it.",
        defaults = "Defaults: F6 / Left Stick click",
    },
    zh = {
        categoryInfo = "配置生成楼层地图的打开方式。",
        title = "地图控制",
        keyboardShortcut = "键盘快捷键",
        keyboardHelp = "按下一个键盘按键，将其设为楼层地图开关。不选择按键并返回即可解除绑定。",
        controllerShortcut = "手柄快捷键",
        controllerHelp = "按下一个手柄按键，将其设为楼层地图开关。不选择按键并返回即可解除绑定。",
        defaults = "默认：F6 / 按下左摇杆",
    },
}

local function getMcmTranslation()
    if Options and Options.Language == "zh" then return MCM_TRANSLATIONS.zh end
    return MCM_TRANSLATIONS.en
end

local mcmLoaded, MCM = pcall(require, "scripts.modconfig")
local mcmWasVisible = false
local keyboardShortcutPressed = false
local trackedKeyboardShortcut = nil
local controllerShortcutPressedByIndex = {}
local trackedControllerShortcut = nil

if mcmLoaded and type(MCM.Config) == "table"
    and type(MCM.Config[LEGACY_MCM_CATEGORY]) == "table" then
    MCM.Config[MCM_CATEGORY] = MCM.Config[MCM_CATEGORY] or {}
    for _, attribute in ipairs({ "KeyboardShortcut", "ControllerShortcut" }) do
        if MCM.Config[MCM_CATEGORY][attribute] == nil
            and type(MCM.Config[LEGACY_MCM_CATEGORY][attribute]) == "number" then
            MCM.Config[MCM_CATEGORY][attribute] = MCM.Config[LEGACY_MCM_CATEGORY][attribute]
        end
    end
end

if mcmLoaded then
    local text = getMcmTranslation()
    MCM.SetCategoryInfo(MCM_CATEGORY, text.categoryInfo)
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

local SPECIAL_ROOMS = {
    { key = "secret", roomType = RoomType.ROOM_SECRET, labelKey = "room.secret",
        code = "1", color = { 0.10, 1.00, 0.88 } },
    { key = "superSecret", roomType = RoomType.ROOM_SUPERSECRET, labelKey = "room.superSecret",
        code = "2", color = { 0.12, 0.58, 1.00 } },
    { key = "treasure", roomType = RoomType.ROOM_TREASURE, labelKey = "room.treasure",
        code = "3", color = { 1.00, 0.82, 0.05 } },
    { key = "shop", roomType = RoomType.ROOM_SHOP, labelKey = "room.shop",
        code = "4", color = { 0.62, 1.00, 0.08 } },
    { key = "devil", roomType = RoomType.ROOM_DEVIL, labelKey = "room.devil",
        code = "5", color = { 1.00, 0.08, 0.15 } },
    { key = "angel", roomType = RoomType.ROOM_ANGEL, labelKey = "room.angel",
        code = "6", color = { 1.00, 0.96, 0.10 } },
    { key = "planetarium", roomType = RoomType.ROOM_PLANETARIUM, labelKey = "room.planetarium",
        code = "7", color = { 0.42, 0.18, 1.00 } },
    { key = "ultraSecret", roomType = RoomType.ROOM_ULTRASECRET, labelKey = "room.ultraSecret",
        code = "8", color = { 1.00, 0.08, 0.72 } },
    { key = "sacrifice", roomType = RoomType.ROOM_SACRIFICE, labelKey = "room.sacrifice",
        code = "9", color = { 1.00, 0.26, 0.42 } },
    { key = "curse", roomType = RoomType.ROOM_CURSE, labelKey = "room.curse",
        code = "10", color = { 0.78, 0.08, 1.00 } },
    { key = "challenge", roomType = RoomType.ROOM_CHALLENGE, labelKey = "room.challenge",
        code = "11", color = { 1.00, 0.38, 0.04 } },
    { key = "dice", roomType = RoomType.ROOM_DICE, labelKey = "room.dice",
        code = "12", color = { 0.08, 1.00, 0.28 } },
    { key = "library", roomType = RoomType.ROOM_LIBRARY, labelKey = "room.library",
        code = "13", color = { 0.95, 0.48, 0.08 } },
    { key = "vault", roomType = RoomType.ROOM_CHEST, labelKey = "room.vault",
        code = "14", color = { 0.05, 0.78, 1.00 } },
    { key = "arcade", roomType = RoomType.ROOM_ARCADE, labelKey = "room.arcade",
        code = "15", color = { 1.00, 0.18, 0.48 } },
    { key = "bossRush", roomType = RoomType.ROOM_BOSSRUSH, labelKey = "room.bossRush",
        code = "16", color = { 1.00, 0.22, 0.02 } },
    { key = "blackMarket", roomType = RoomType.ROOM_BLACK_MARKET, labelKey = "room.blackMarket",
        code = "17", color = { 0.52, 0.08, 1.00 } },
    { key = "crawlSpace", roomType = RoomType.ROOM_DUNGEON, labelKey = "room.crawlSpace",
        code = "18", color = { 0.04, 0.90, 0.62 } },
    { key = "cleanBedroom", roomType = RoomType.ROOM_ISAACS, labelKey = "room.cleanBedroom",
        code = "19", color = { 0.18, 0.86, 1.00 } },
    { key = "dirtyBedroom", roomType = RoomType.ROOM_BARREN, labelKey = "room.dirtyBedroom",
        code = "20", color = { 0.92, 0.58, 0.06 } },
}

local SPECIAL_ROOM_BY_TYPE = {}
for _, special in ipairs(SPECIAL_ROOMS) do
    SPECIAL_ROOM_BY_TYPE[special.roomType] = special
end

-- Boss Rooms are useful on the map but deliberately stay outside SPECIAL_ROOMS,
-- so they do not consume a ranked digit or appear in the right-side legend.
local BOSS_ROOM_MAP_MARKER = {
    code = "B",
    color = { 0.00, 0.00, 0.00 },
}

local persistent
local run
local ui = {
    overlayVisible = true,
}

local runtime = {}

local function newFloorState(key)
    return {
        key = key,
        name = game:GetLevel():GetName(),
        stage = game:GetLevel():GetStage(),
        stageType = game:GetLevel():GetStageType(),
        generatedRooms = 0,
        layoutSize = nil,
        mapRooms = {},
        visitedRoomIds = {},
    }
end

local function newRunState(seed)
    return {
        seed = seed,
        floors = {},
        currentFloorKey = nil,
        spiderModGranted = false,
        spiderModGrantVersion = 1,
    }
end

local function migrateFloorState(key, source)
    local floor = newFloorState(key)
    if type(source) ~= "table" then return floor end

    floor.key = source.key or key
    floor.name = source.name or floor.name
    floor.stage = source.stage or floor.stage
    floor.stageType = source.stageType or floor.stageType
    floor.generatedRooms = tonumber(source.generatedRooms) or 0
    floor.layoutSize = source.layoutSize

    for roomId, visited in pairs(source.visitedRoomIds or {}) do
        if visited == true then floor.visitedRoomIds[tostring(roomId)] = true end
    end
    -- Schema 2 stored reliable physical visits in floor.rooms. Its mapRooms
    -- visited flag could be polluted by RoomDescriptor.VisitedCount, so do not
    -- migrate that flag directly.
    for roomId, roomRecord in pairs(source.rooms or {}) do
        if type(roomRecord) == "table" and roomRecord.visited == true then
            floor.visitedRoomIds[tostring(roomId)] = true
        end
    end

    for roomId, mapRoom in pairs(source.mapRooms or {}) do
        if type(mapRoom) == "table" then
            local id = tostring(roomId)
            floor.mapRooms[id] = {
                grid = mapRoom.grid,
                roomType = mapRoom.roomType,
                shape = mapRoom.shape,
                display = mapRoom.display,
                visited = floor.visitedRoomIds[id] == true,
            }
        end
    end
    return floor
end

local function newPersistentData()
    return {
        schema = SAVE_SCHEMA,
        preferences = { overlayVisible = true },
        activeRun = nil,
    }
end

local function normalizePersistentData(data)
    local normalized = newPersistentData()
    if type(data) ~= "table" then return normalized end

    local preferences = type(data.preferences) == "table" and data.preferences or {}
    if preferences.overlayVisible ~= nil then
        normalized.preferences.overlayVisible = preferences.overlayVisible == true
    elseif preferences.dashboardVisible ~= nil then
        normalized.preferences.overlayVisible = preferences.dashboardVisible == true
    end

    if type(data.activeRun) == "table" and data.activeRun.seed ~= nil then
        local migratedRun = newRunState(data.activeRun.seed)
        for key, floor in pairs(data.activeRun.floors or {}) do
            local floorKeyValue = tostring(key)
            migratedRun.floors[floorKeyValue] = migrateFloorState(floorKeyValue, floor)
        end
        migratedRun.currentFloorKey = data.activeRun.currentFloorKey
        -- Local development builds wrote spiderModGranted=false after silently
        -- granting the item, so a continued run could mistake that old copy for
        -- a genuine pickup. This legacy field/version combination was never in
        -- a published build; migrate it once and suppress the supplied robot.
        local legacySpiderModGrant = data.activeRun.spiderModGranted ~= nil
            and data.activeRun.spiderModGrantVersion == nil
        migratedRun.spiderModGranted = legacySpiderModGrant
            or data.activeRun.spiderModGranted == true
        migratedRun.spiderModGrantVersion = 1
        normalized.activeRun = migratedRun
    end
    return normalized
end

local function loadPersistentData()
    local data = nil
    if BeginnerLedger:HasData() then
        local ok, decoded = pcall(json.decode, BeginnerLedger:LoadData())
        if ok then
            data = decoded
        else
            Isaac.DebugString("[Sharingan] Save data could not be decoded; starting fresh records.")
        end
    end
    persistent = normalizePersistentData(data)
    ui.overlayVisible = persistent.preferences.overlayVisible
end

local function savePersistentData()
    if not persistent then return end
    persistent.activeRun = run
    persistent.preferences.overlayVisible = ui.overlayVisible
    local ok, encoded = pcall(json.encode, persistent)
    if ok then
        BeginnerLedger:SaveData(encoded)
    else
        Isaac.DebugString("[Sharingan] Failed to encode save data.")
    end
end

local function resetRuntime()
    runtime = {
        currentRoomId = nil,
        lastFloorKey = nil,
    }
end

local function ensureRunTables()
    run.floors = run.floors or {}
    run.spiderModGranted = run.spiderModGranted == true
    run.spiderModGrantVersion = 1
    for key, floor in pairs(run.floors) do
        run.floors[tostring(key)] = migrateFloorState(tostring(key), floor)
        if tostring(key) ~= key then run.floors[key] = nil end
    end
end

local function floorKey()
    return tostring(game:GetLevel():GetDungeonPlacementSeed())
end

local function currentFloor()
    if not run then return nil end
    local key = floorKey()
    if not run.floors[key] then
        run.floors[key] = newFloorState(key)
    end
    local floor = run.floors[key]
    floor.mapRooms = floor.mapRooms or {}
    floor.visitedRoomIds = floor.visitedRoomIds or {}
    run.currentFloorKey = key
    return floor
end

local function normalizedGridIndex(gridIndex)
    if not gridIndex or gridIndex < 0 then return nil end
    return gridIndex % MAP_GRID_SIZE
end

local ROOM_SHAPE_OFFSETS = {
    [RoomShape.ROOMSHAPE_1x1] = { { 0, 0 } },
    [RoomShape.ROOMSHAPE_IH] = { { 0, 0 } },
    [RoomShape.ROOMSHAPE_IV] = { { 0, 0 } },
    [RoomShape.ROOMSHAPE_1x2] = { { 0, 0 }, { 0, 1 } },
    [RoomShape.ROOMSHAPE_IIV] = { { 0, 0 }, { 0, 1 } },
    [RoomShape.ROOMSHAPE_2x1] = { { 0, 0 }, { 1, 0 } },
    [RoomShape.ROOMSHAPE_IIH] = { { 0, 0 }, { 1, 0 } },
    [RoomShape.ROOMSHAPE_2x2] = {
        { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 },
    },
    -- SafeGridIndex is the occupied top-right cell for LTL; for every other
    -- large room it is the top-left cell.
    [RoomShape.ROOMSHAPE_LTL] = { { 0, 0 }, { -1, 1 }, { 0, 1 } },
    [RoomShape.ROOMSHAPE_LTR] = { { 0, 0 }, { 0, 1 }, { 1, 1 } },
    [RoomShape.ROOMSHAPE_LBL] = { { 0, 0 }, { 1, 0 }, { 1, 1 } },
    [RoomShape.ROOMSHAPE_LBR] = { { 0, 0 }, { 1, 0 }, { 0, 1 } },
}

local function roomFootprintGrids(gridIndex, roomShape)
    local anchor = normalizedGridIndex(gridIndex)
    if not anchor then return {} end
    local anchorX = anchor % MAP_COLUMNS
    local anchorY = math.floor(anchor / MAP_COLUMNS)
    local offsets = ROOM_SHAPE_OFFSETS[roomShape]
        or ROOM_SHAPE_OFFSETS[RoomShape.ROOMSHAPE_1x1]
    local footprint = {}
    for _, offset in ipairs(offsets) do
        local x = anchorX + offset[1]
        local y = anchorY + offset[2]
        if x >= 0 and x < MAP_COLUMNS and y >= 0 and y < MAP_ROWS then
            footprint[#footprint + 1] = y * MAP_COLUMNS + x
        end
    end
    return footprint
end

local function refreshFloorLayout(floor)
    floor.generatedRooms = 0
    local rooms = game:GetLevel():GetRooms()
    floor.layoutSize = rooms.Size
    for index = 0, rooms.Size - 1 do
        local descriptor = rooms:Get(index)
        if descriptor and descriptor.Data then
            floor.generatedRooms = floor.generatedRooms + 1
            local listKey = tostring(descriptor.ListIndex)
            local existing = floor.mapRooms[listKey] or {}
            existing.grid = descriptor.SafeGridIndex
            existing.roomType = descriptor.Data.Type
            existing.shape = descriptor.Data.Shape
            existing.display = descriptor.DisplayFlags
            -- Only visits observed by MC_POST_NEW_ROOM turn markers gray.
            -- Descriptor.VisitedCount can be non-zero before physical entry.
            existing.visited = floor.visitedRoomIds[listKey] == true
            floor.mapRooms[listKey] = existing
        end
    end
end

local function roomIdFromDescriptor(descriptor)
    return tostring(descriptor.ListIndex)
end

local function visitCurrentRoom()
    if not run or game:GetNumPlayers() == 0 then return end
    local floor = currentFloor()
    local rooms = game:GetLevel():GetRooms()
    if floor.layoutSize ~= rooms.Size then
        refreshFloorLayout(floor)
    end

    local descriptor = game:GetLevel():GetCurrentRoomDesc()
    if not descriptor or not descriptor.Data then return end
    local roomId = roomIdFromDescriptor(descriptor)
    runtime.currentRoomId = roomId
    floor.visitedRoomIds[roomId] = true

    local mapRoom = floor.mapRooms[roomId] or {}
    mapRoom.grid = descriptor.SafeGridIndex
    mapRoom.roomType = descriptor.Data.Type
    mapRoom.shape = descriptor.Data.Shape
    mapRoom.display = descriptor.DisplayFlags
    mapRoom.visited = true
    floor.mapRooms[roomId] = mapRoom
end

local function rawKeyPressed(key)
    return Input.IsButtonPressed(key, 0) and not Input.IsButtonPressed(key % 32, 0)
end

local function keyboardShortcutTriggered()
    local shortcut = getConfiguredShortcut("KeyboardShortcut", DEFAULT_KEYBOARD_SHORTCUT)
    if shortcut ~= trackedKeyboardShortcut then
        keyboardShortcutPressed = false
        trackedKeyboardShortcut = shortcut
    end
    if shortcut < 0 then return false end
    local pressed = rawKeyPressed(shortcut)
    local triggered = pressed and not keyboardShortcutPressed
    keyboardShortcutPressed = pressed
    return triggered
end

local function controllerShortcutTriggered()
    local shortcut = getConfiguredShortcut("ControllerShortcut", DEFAULT_CONTROLLER_SHORTCUT)
    if shortcut ~= trackedControllerShortcut then
        controllerShortcutPressedByIndex = {}
        trackedControllerShortcut = shortcut
    end
    if shortcut < 0 then return false end

    local activeControllerIndexes = {}
    local triggered = false
    for index = 0, game:GetNumPlayers() - 1 do
        local controllerIndex = Isaac.GetPlayer(index).ControllerIndex
        if not activeControllerIndexes[controllerIndex] then
            local pressed = Input.IsButtonPressed(shortcut, controllerIndex)
            if pressed and not controllerShortcutPressedByIndex[controllerIndex] then
                triggered = true
            end
            controllerShortcutPressedByIndex[controllerIndex] = pressed
            activeControllerIndexes[controllerIndex] = true
        end
    end
    return triggered
end

local function updateOverlayControls()
    local keyboardToggle = keyboardShortcutTriggered()
    local controllerToggle = controllerShortcutTriggered()
    local toggleTriggered = keyboardToggle or controllerToggle

    if mcmLoaded and MCM.IsVisible then
        mcmWasVisible = true
        return
    end
    if mcmWasVisible then
        mcmWasVisible = false
        return
    end

    if toggleTriggered then
        ui.overlayVisible = not ui.overlayVisible
        if ui.overlayVisible then refreshFloorLayout(currentFloor()) end
        savePersistentData()
    end
end

local function synchronizeNativeSpiderMod()
    if not run or game:GetNumPlayers() == 0 then return end
    local player = Isaac.GetPlayer(0)
    local itemCount = player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_SPIDER_MOD,
        true
    )

    if itemCount == 0 then
        -- FirstTimePickingUp=false grants the real passive immediately without
        -- a pickup animation or transformation progress. Isaac then owns all
        -- Spider Mod rendering and familiar behavior.
        -- Set the ownership marker first because the familiar may initialize
        -- synchronously inside AddCollectible.
        run.spiderModGranted = true
        player:AddCollectible(
            CollectibleType.COLLECTIBLE_SPIDER_MOD,
            0,
            false
        )
    elseif run.spiderModGranted and itemCount > 1 then
        -- The player has now collected a genuine copy. Remove the one supplied
        -- by Sharingan without reducing the transformation progress earned by
        -- the real pickup. One native Spider Mod remains and owns the display.
        player:RemoveCollectible(
            CollectibleType.COLLECTIBLE_SPIDER_MOD,
            true,
            ActiveSlot.SLOT_PRIMARY,
            false
        )
        run.spiderModGranted = false
        -- The mod-supplied familiar is suppressed. Re-evaluate once so the
        -- genuinely collected Spider Mod can create its own visible familiar.
        player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
        player:EvaluateItems()
        savePersistentData()
    end
end

function BeginnerLedger:OnSpiderModFamiliarUpdate(familiar)
    if not run or not run.spiderModGranted or game:GetNumPlayers() == 0 then
        return
    end
    local owner = familiar.Player
    if owner and GetPtrHash(owner) == GetPtrHash(Isaac.GetPlayer(0)) then
        -- Native health bars are based on Spider Mod ownership. Removing the
        -- supplied familiar hides the robot and prevents its contact/drop
        -- behavior while leaving Isaac's native health display active.
        familiar.Visible = false
        familiar:Remove()
    end
end

function BeginnerLedger:OnGameStarted(isContinued)
    loadPersistentData()
    local seed = game:GetSeeds():GetStartSeed()
    if isContinued and persistent.activeRun and persistent.activeRun.seed == seed then
        run = persistent.activeRun
        ensureRunTables()
    else
        run = newRunState(seed)
    end

    resetRuntime()
    runtime.lastFloorKey = floorKey()
    visitCurrentRoom()
    synchronizeNativeSpiderMod()
    -- This first schema-3 save permanently drops legacy combat history.
    savePersistentData()
end

function BeginnerLedger:OnNewRoom()
    if not run then return end
    runtime.lastFloorKey = floorKey()
    visitCurrentRoom()
end

function BeginnerLedger:OnNewLevel()
    if not run then return end
    local floor = currentFloor()
    refreshFloorLayout(floor)
    savePersistentData()
end

function BeginnerLedger:OnUpdate()
    if not run or game:GetNumPlayers() == 0 then return end
    synchronizeNativeSpiderMod()
    updateOverlayControls()
end

function BeginnerLedger:OnGameEnd()
    if not run then return end
    persistent.activeRun = nil
    run = nil
    savePersistentData()
end

function BeginnerLedger:OnPreGameExit()
    if run then savePersistentData() end
end

local function renderLine(text, x, y, color, style)
    local c = color or { 1, 1, 1 }
    local useSmall = style == "small" or style == "cell"
        or (type(style) == "number" and style <= 0.60)
    local useTitle = style == "title" or (type(style) == "number" and style >= 0.75)
    local fonts = currentFonts()
    local font = useSmall and fonts.small or fonts.body
    local loaded = useSmall and fonts.smallLoaded or fonts.bodyLoaded
    local drawX = math.floor(x)
    local drawY = math.floor(y)

    if loaded then
        local shadow = KColor(0.02, 0.02, 0.03, 0.98)
        local foreground = KColor(c[1], c[2], c[3], c[4] or 1)
        -- Native-size UTF-8 text at integer coordinates stays pixel-sharp.
        font:DrawStringUTF8(text, drawX + 1, drawY + 1, shadow, 0, false)
        if useTitle then
            -- A second one-pixel-offset pass gives headings a crisp bold weight.
            font:DrawStringUTF8(text, drawX + 1, drawY, foreground, 0, false)
        end
        font:DrawStringUTF8(text, drawX, drawY, foreground, 0, false)
    else
        -- Repentance+ includes the extended fonts above; keep a safe fallback.
        Isaac.RenderText(text, drawX + 1, drawY + 1, 0, 0, 0, 1)
        Isaac.RenderText(text, drawX, drawY, c[1], c[2], c[3], c[4] or 1)
    end
end

local function textWidth(text, style)
    local useSmall = style == "small" or style == "cell"
    local fonts = currentFonts()
    local font = useSmall and fonts.small or fonts.body
    local loaded = useSmall and fonts.smallLoaded or fonts.bodyLoaded
    if loaded then
        return font:GetStringWidthUTF8(text)
    end
    return Isaac.GetTextWidth(text)
end

local function renderPanelFrame(x, y, requestedWidth, requestedHeight)
    local frameColor = { 0.42, 0.72, 0.86, 1 }
    local cornerWidth = math.max(1, textWidth("+", "small"))
    local dashWidth = math.max(1, textWidth("-", "small"))
    local dashCount = math.max(4, math.floor((requestedWidth - cornerWidth * 2) / dashWidth))
    local border = "+" .. string.rep("-", dashCount) .. "+"
    local actualWidth = textWidth(border, "small")
    local bottom = math.floor(y + requestedHeight)

    renderLine(border, x, y, frameColor, "small")
    renderLine(border, x, bottom, frameColor, "small")
    for lineY = math.floor(y + 10), bottom - 1, 10 do
        renderLine("|", x, lineY, frameColor, "small")
        renderLine("|", x + actualWidth - cornerWidth, lineY, frameColor, "small")
    end
    return actualWidth
end

-- Prefer proper box-drawing corners when the loaded font contains them. The
-- bundled Team Meat font can differ between Isaac releases, so keep an ASCII
-- outline as a safe fallback instead of displaying missing-glyph boxes.
local MAP_OUTLINE_UNICODE = {
    horizontal = "─",
    vertical = "│",
    topLeft = "┌",
    topRight = "┐",
    bottomLeft = "└",
    bottomRight = "┘",
    junction = "┼",
}

local MAP_OUTLINE_ASCII = {
    horizontal = "-",
    vertical = "|",
    topLeft = "+",
    topRight = "+",
    bottomLeft = "+",
    bottomRight = "+",
    junction = "+",
}

local resolvedMapOutlineGlyphs = nil

local function mapOutlineGlyphs()
    if resolvedMapOutlineGlyphs then return resolvedMapOutlineGlyphs end
    local width = textWidth(MAP_OUTLINE_UNICODE.topLeft, "cell")
    if width and width > 0 then
        resolvedMapOutlineGlyphs = MAP_OUTLINE_UNICODE
    else
        resolvedMapOutlineGlyphs = MAP_OUTLINE_ASCII
    end
    return resolvedMapOutlineGlyphs
end

local function mapEdgeKey(x, y)
    return tostring(x) .. ":" .. tostring(y)
end

local function addMapVertex(vertices, x, y)
    vertices[mapEdgeKey(x, y)] = { x = x, y = y }
end

local function mapVertexGlyph(glyphs, horizontalEdges, verticalEdges, x, y)
    local left = horizontalEdges[mapEdgeKey(x - 1, y)]
    local right = horizontalEdges[mapEdgeKey(x, y)]
    local up = verticalEdges[mapEdgeKey(x, y - 1)]
    local down = verticalEdges[mapEdgeKey(x, y)]

    if left and right and not up and not down then return glyphs.horizontal end
    if up and down and not left and not right then return glyphs.vertical end
    if right and down and not left and not up then return glyphs.topLeft end
    if left and down and not right and not up then return glyphs.topRight end
    if right and up and not left and not down then return glyphs.bottomLeft end
    if left and up and not right and not down then return glyphs.bottomRight end
    return glyphs.junction
end

local function renderRoomOutline(roomData, originX, originY)
    local cellSet = {}
    for _, grid in ipairs(roomData.grids) do
        cellSet[grid] = true
    end

    local horizontalEdges = {}
    local verticalEdges = {}
    local vertices = {}
    for _, grid in ipairs(roomData.grids) do
        local x = grid % MAP_COLUMNS
        local y = math.floor(grid / MAP_COLUMNS)
        if not cellSet[grid - MAP_COLUMNS] or y == 0 then
            horizontalEdges[mapEdgeKey(x, y)] = { x = x, y = y }
        end
        if not cellSet[grid + MAP_COLUMNS] or y == MAP_ROWS - 1 then
            horizontalEdges[mapEdgeKey(x, y + 1)] = { x = x, y = y + 1 }
        end
        if not cellSet[grid - 1] or x == 0 then
            verticalEdges[mapEdgeKey(x, y)] = { x = x, y = y }
        end
        if not cellSet[grid + 1] or x == MAP_COLUMNS - 1 then
            verticalEdges[mapEdgeKey(x + 1, y)] = { x = x + 1, y = y }
        end
    end

    for _, edge in pairs(horizontalEdges) do
        addMapVertex(vertices, edge.x, edge.y)
        addMapVertex(vertices, edge.x + 1, edge.y)
    end
    for _, edge in pairs(verticalEdges) do
        addMapVertex(vertices, edge.x, edge.y)
        addMapVertex(vertices, edge.x, edge.y + 1)
    end

    local glyphs = mapOutlineGlyphs()
    local horizontalWidth = math.max(1, textWidth(glyphs.horizontal, "cell"))
    local horizontalText = string.rep(
        glyphs.horizontal,
        math.max(1, math.ceil((MAP_CELL_SIZE - 4) / horizontalWidth))
    )
    local color = roomData.color

    for _, edge in pairs(horizontalEdges) do
        renderLine(
            horizontalText,
            originX + edge.x * MAP_CELL_SIZE + 2,
            originY + edge.y * MAP_CELL_SIZE - 5,
            color,
            "cell"
        )
    end
    for _, edge in pairs(verticalEdges) do
        renderLine(
            glyphs.vertical,
            originX + edge.x * MAP_CELL_SIZE - 2,
            originY + edge.y * MAP_CELL_SIZE,
            color,
            "cell"
        )
    end
    for _, vertex in pairs(vertices) do
        renderLine(
            mapVertexGlyph(
                glyphs,
                horizontalEdges,
                verticalEdges,
                vertex.x,
                vertex.y
            ),
            originX + vertex.x * MAP_CELL_SIZE - 2,
            originY + vertex.y * MAP_CELL_SIZE - 5,
            color,
            "cell"
        )
    end
end

local function renderSolidRectangle(x, y, width, height, color)
    if width <= 0 or height <= 0 then return end
    ROOM_FILL_SPRITE.Color = color
    ROOM_FILL_SPRITE.Scale = Vector(width, height)
    ROOM_FILL_SPRITE:Render(Vector(x, y), ZERO_VECTOR, ZERO_VECTOR)
end

-- Fill only the cells that belong to the room's real footprint. This makes
-- empty corners in L rooms visibly empty while preserving one connected
-- outline around large rooms. Scaling a solid one-pixel sprite to the cell keeps
-- the fill inside that cell instead of spilling into an adjacent empty space.
local function renderRoomFill(roomData, originX, originY)
    local fillColor = roomData.visited
        and ROOM_FILL_VISITED_SPRITE_COLOR
        or ROOM_FILL_UNVISITED_SPRITE_COLOR

    for _, grid in ipairs(roomData.grids) do
        local x = originX + (grid % MAP_COLUMNS) * MAP_CELL_SIZE + 1
        local y = originY + math.floor(grid / MAP_COLUMNS) * MAP_CELL_SIZE + 1
        renderSolidRectangle(
            math.floor(x),
            math.floor(y),
            MAP_CELL_SIZE - 2,
            MAP_CELL_SIZE - 2,
            fillColor
        )
    end

    ROOM_FILL_SPRITE.Scale = Vector(1, 1)
    ROOM_FILL_SPRITE.Color = DEFAULT_SPRITE_COLOR
end

local function renderMapCellLabel(text, cellX, cellY, color)
    local labelX = cellX + math.floor(
        (MAP_CELL_SIZE - textWidth(text, "cell")) / 2
    )
    renderLine(text, labelX, cellY + 1, color, "cell")
end

local function renderFloorMap()
    if not ui.overlayVisible or not run then return end
    local floor = currentFloor()
    local screenWidth = Isaac.GetScreenWidth()
    local originX = math.max(18, math.floor(screenWidth / 2 - 175))
    local originY = 48
    local toolbarX = originX + MAP_COLUMNS * MAP_CELL_SIZE + 22
    local descriptor = game:GetLevel():GetCurrentRoomDesc()
    local currentRoomId = descriptor and tostring(descriptor.ListIndex) or nil
    local generatedCells = {}
    local generatedRooms = {}
    for roomId, mapRoom in pairs(floor.mapRooms) do
        local specialRoom = SPECIAL_ROOM_BY_TYPE[mapRoom.roomType]
        if not specialRoom and mapRoom.roomType == RoomType.ROOM_BOSS then
            specialRoom = BOSS_ROOM_MAP_MARKER
        end
        local visited = mapRoom.visited == true
        local roomData = {
            roomId = roomId,
            grids = roomFootprintGrids(mapRoom.grid, mapRoom.shape),
            anchor = normalizedGridIndex(mapRoom.grid),
            specialRoom = specialRoom,
            visited = visited,
            color = specialRoom and (specialRoom == BOSS_ROOM_MAP_MARKER
                    and specialRoom.color
                    or (visited and VISITED_SPECIAL_ROOM_COLOR or specialRoom.color))
                or (roomId == currentRoomId and { 0.45, 1.00, 0.45 }
                    or { 0.62, 0.68, 0.72 }),
        }
        generatedRooms[#generatedRooms + 1] = roomData
        for _, grid in ipairs(roomData.grids) do
            if not generatedCells[grid] or roomId == currentRoomId then
                generatedCells[grid] = roomData
            end
        end
    end

    local mapPanelWidth = MAP_COLUMNS * MAP_CELL_SIZE + 205
    renderPanelFrame(
        originX - 10,
        24,
        mapPanelWidth,
        212
    )
    renderLine(tr("map.title"), originX, 32, { 1.00, 0.90, 0.35 }, "title")

    -- Empty cells are drawn first. Real room cells are filled next, then one
    -- connected perimeter is drawn around each footprint, so 2x2 and L rooms
    -- no longer look like separate 1x1 rooms or enclose ambiguous empty space.
    for row = 0, MAP_ROWS - 1 do
        for column = 0, MAP_COLUMNS - 1 do
            local grid = row * MAP_COLUMNS + column
            local x = originX + column * MAP_CELL_SIZE
            local y = originY + row * MAP_CELL_SIZE
            if not generatedCells[grid] then
                renderLine(".", x + 4, y + 2, { 0.30, 0.30, 0.30, 0.45 }, "cell")
            end
        end
    end

    for _, roomData in ipairs(generatedRooms) do
        renderRoomFill(roomData, originX, originY)
    end

    for _, roomData in ipairs(generatedRooms) do
        renderRoomOutline(roomData, originX, originY)
    end

    -- Automatic special-room digits, the map-only Boss marker, and the current
    -- room indicator appear once even when a room occupies several map cells.
    for _, roomData in ipairs(generatedRooms) do
        local specialRoom = roomData.specialRoom
        local x = roomData.anchor and originX
            + (roomData.anchor % MAP_COLUMNS) * MAP_CELL_SIZE or nil
        local y = roomData.anchor and originY
            + math.floor(roomData.anchor / MAP_COLUMNS) * MAP_CELL_SIZE or nil
        if specialRoom and x and y then
            renderMapCellLabel(specialRoom.code, x, y, roomData.color)
        elseif roomData.roomId == currentRoomId and x and y then
            renderMapCellLabel("@", x, y, { 0.45, 1.00, 0.45 })
        end
    end

    for index, specialRoom in ipairs(SPECIAL_ROOMS) do
        local legendColumn = math.floor((index - 1) / LEGEND_ROWS_PER_COLUMN)
        local legendRow = (index - 1) % LEGEND_ROWS_PER_COLUMN
        renderLine(
            specialRoom.code .. " " .. tr(specialRoom.labelKey),
            toolbarX + legendColumn * LEGEND_COLUMN_WIDTH,
            originY + legendRow * LEGEND_ROW_HEIGHT,
            specialRoom.color,
            "small"
        )
    end
    local helpY = originY + LEGEND_ROWS_PER_COLUMN * LEGEND_ROW_HEIGHT + 7
    renderLine(tr("map.visited"), toolbarX, helpY,
        VISITED_SPECIAL_ROOM_COLOR, "small")
    renderLine(tr("map.warning"), toolbarX, helpY + 12,
        { 1.00, 0.55, 0.55 }, "small")
end

function BeginnerLedger:OnRender()
    if not run or game:GetNumPlayers() == 0 then return end
    renderFloorMap()
end

BeginnerLedger:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, BeginnerLedger.OnGameStarted)
BeginnerLedger:AddCallback(ModCallbacks.MC_POST_GAME_END, BeginnerLedger.OnGameEnd)
BeginnerLedger:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, BeginnerLedger.OnPreGameExit)
BeginnerLedger:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, BeginnerLedger.OnNewRoom)
BeginnerLedger:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, BeginnerLedger.OnNewLevel)
BeginnerLedger:AddCallback(ModCallbacks.MC_POST_UPDATE, BeginnerLedger.OnUpdate)
BeginnerLedger:AddCallback(ModCallbacks.MC_POST_RENDER, BeginnerLedger.OnRender)
BeginnerLedger:AddCallback(
    ModCallbacks.MC_FAMILIAR_UPDATE,
    BeginnerLedger.OnSpiderModFamiliarUpdate,
    FamiliarVariant.SPIDER_MOD
)
