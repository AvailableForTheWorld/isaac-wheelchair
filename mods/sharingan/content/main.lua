local BeginnerLedger = RegisterMod("Sharingan", 1)
local game = Game()
local json = require("json")
local itemConfig = Isaac.GetItemConfig()
local I18N = include("i18n")

local UI_FONTS = { en = { body = Font(), small = Font() } }

UI_FONTS.en.bodyLoaded = UI_FONTS.en.body:Load("font/teammeatex/teammeatex12.fnt")
UI_FONTS.en.smallLoaded = UI_FONTS.en.small:Load("font/teammeatex/teammeatex10.fnt")

local function currentFonts()
    return UI_FONTS[I18N.GetLanguage()] or UI_FONTS.en
end

local function tr(key)
    return I18N.Get(key)
end

local function trf(key, ...)
    return I18N.Format(key, ...)
end

local SAVE_SCHEMA = 2
local SAVE_INTERVAL = 300
local ACTIVE_ITEM_WINDOW_FRAMES = 150
local MAX_COLLECTIBLE_ID = CollectibleType.NUM_COLLECTIBLES or 733
local MAP_COLUMNS = 13
local MAP_ROWS = 13
local MAP_GRID_SIZE = MAP_COLUMNS * MAP_ROWS
local MAP_CELL_SIZE = 13
local LEGEND_ROWS_PER_COLUMN = 10
local LEGEND_COLUMN_WIDTH = 86
local LEGEND_ROW_HEIGHT = 13
local VISITED_SPECIAL_ROOM_COLOR = { 0.48, 0.50, 0.52 }

local DEFAULT_KEYBOARD_SHORTCUT = Keyboard.KEY_F6
local DEFAULT_CONTROLLER_SHORTCUT = 10 -- Controller.STICK_LEFT in MCM
local CONTROLLER_LEFT = 0 -- Controller.DPAD_LEFT in MCM
local CONTROLLER_RIGHT = 1 -- Controller.DPAD_RIGHT in MCM
local MCM_CATEGORY = "Sharingan"
local LEGACY_MCM_CATEGORY = "Beginner Ledger"
local MCM_SUBCATEGORY = "Controls"

local MCM_TRANSLATIONS = {
    en = {
        categoryInfo = "Configure how the Combat Report and floor map are opened.",
        title = "Overlay controls",
        keyboardShortcut = "Keyboard shortcut",
        keyboardHelp = "Press a keyboard key to open or close the overlay. Go back without choosing a key to unbind it.",
        controllerShortcut = "Controller shortcut",
        controllerHelp = "Press a controller button to open or close the overlay. Go back without choosing a button to unbind it.",
        navigation = "While open: Left = Floor Map, Right = Combat Report",
        defaults = "Defaults: F6 / Left Stick click",
    },
    zh = {
        categoryInfo = "配置战斗报告和楼层地图的打开方式。",
        title = "界面控制",
        keyboardShortcut = "键盘快捷键",
        keyboardHelp = "按下一个键盘按键，将其设为界面开关。不选择按键并返回即可解除绑定。",
        controllerShortcut = "手柄快捷键",
        controllerHelp = "按下一个手柄按键，将其设为界面开关。不选择按键并返回即可解除绑定。",
        navigation = "界面打开时：左键 = 楼层地图，右键 = 战斗报告",
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
    MCM.AddText(MCM_CATEGORY, MCM_SUBCATEGORY, text.navigation)
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

local PICKUP_CATEGORIES = { "heart", "coin", "key", "bomb", "battery" }

local CHEST_VARIANTS = {
    [PickupVariant.PICKUP_CHEST] = true,
    [PickupVariant.PICKUP_BOMBCHEST] = true,
    [PickupVariant.PICKUP_SPIKEDCHEST] = true,
    [PickupVariant.PICKUP_ETERNALCHEST] = true,
    [PickupVariant.PICKUP_MIMICCHEST] = true,
    [PickupVariant.PICKUP_OLDCHEST] = true,
    [PickupVariant.PICKUP_WOODENCHEST] = true,
    [PickupVariant.PICKUP_MEGACHEST] = true,
    [PickupVariant.PICKUP_HAUNTEDCHEST] = true,
    [PickupVariant.PICKUP_LOCKEDCHEST] = true,
    [PickupVariant.PICKUP_REDCHEST] = true,
}

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

-- Slot variants are not exposed as a vanilla Lua enum.
local SLOT_INFO = {
    [1] = { nameKey = "machine.slot", cost = "coin" },
    [2] = { nameKey = "machine.bloodDonation", cost = "health" },
    [3] = { nameKey = "machine.fortune", cost = "coin" },
    [4] = { nameKey = "machine.beggar", cost = "coin" },
    [5] = { nameKey = "machine.devilBeggar", cost = "health" },
    [6] = { nameKey = "machine.shellGame", cost = "coin" },
    [7] = { nameKey = "machine.keyMaster", cost = "key" },
    [8] = { nameKey = "machine.donation", cost = "coin" },
    [9] = { nameKey = "machine.bombBum", cost = "bomb" },
    [10] = { nameKey = "machine.restock", cost = "coin" },
    [11] = { nameKey = "machine.greedDonation", cost = "coin" },
    [12] = { nameKey = "machine.dressingTable", cost = nil },
    [13] = { nameKey = "machine.batteryBum", cost = "coin" },
    [14] = { nameKey = "machine.homeCloset", cost = nil },
    [15] = { nameKey = "machine.hellGame", cost = "health" },
    [16] = { nameKey = "machine.crane", cost = "coin" },
    [17] = { nameKey = "machine.confessional", cost = "health" },
    [18] = { nameKey = "machine.rottenBeggar", cost = "coin" },
}

local persistent
local run
local ui = {
    overlayVisible = true,
    view = "map",
}

local runtime = {}

local function newMachineStat()
    return {
        uses = 0,
        costs = { coin = 0, key = 0, bomb = 0, health = 0 },
        payouts = {
            heart = 0,
            coin = 0,
            key = 0,
            bomb = 0,
            battery = 0,
            chest = 0,
            item = 0,
            other = 0,
        },
    }
end

local function newPersistentData()
    return {
        schema = SAVE_SCHEMA,
        lifetime = {
            runs = 0,
            damageDealt = 0,
            enemiesDamaged = 0,
            enemiesKilled = 0,
            playerHits = 0,
            damageTaken = 0,
            hurtBy = {},
            damageByItem = {},
            itemHistory = {},
            machineStats = {},
        },
        preferences = {
            overlayVisible = true,
            view = "map",
        },
        activeRun = nil,
    }
end

local function normalizePersistentData(data)
    if type(data) ~= "table" then
        data = newPersistentData()
    end

    local previousSchema = tonumber(data.schema) or 0
    data.lifetime = data.lifetime or {}
    data.lifetime.runs = data.lifetime.runs or 0
    data.lifetime.damageDealt = data.lifetime.damageDealt or 0
    data.lifetime.enemiesDamaged = data.lifetime.enemiesDamaged or 0
    data.lifetime.enemiesKilled = data.lifetime.enemiesKilled or 0
    data.lifetime.playerHits = data.lifetime.playerHits or 0
    data.lifetime.damageTaken = data.lifetime.damageTaken or 0
    data.lifetime.hurtBy = data.lifetime.hurtBy or {}
    data.lifetime.damageByItem = data.lifetime.damageByItem or {}
    data.lifetime.itemHistory = data.lifetime.itemHistory or {}
    data.lifetime.machineStats = data.lifetime.machineStats or {}
    data.preferences = data.preferences or {}
    if data.preferences.overlayVisible == nil then
        if data.preferences.dashboardVisible == nil then
            data.preferences.overlayVisible = true
        else
            data.preferences.overlayVisible = data.preferences.dashboardVisible
        end
    end
    if previousSchema < 2 then
        data.preferences.view = "map"
    elseif data.preferences.view ~= "combat" then
        data.preferences.view = "map"
    end
    data.schema = SAVE_SCHEMA
    data.preferences.dashboardVisible = nil
    data.preferences.page = nil
    return data
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
    ui.view = persistent.preferences.view
end

local function savePersistentData()
    if not persistent then return end
    persistent.activeRun = run
    persistent.preferences.overlayVisible = ui.overlayVisible
    persistent.preferences.view = ui.view
    local ok, encoded = pcall(json.encode, persistent)
    if ok then
        BeginnerLedger:SaveData(encoded)
    else
        Isaac.DebugString("[Sharingan] Failed to encode save data.")
    end
end

local function resetRuntime()
    runtime = {
        keyStates = {},
        pendingPickups = {},
        preItemDps = {},
        pendingDps = {},
        playerResources = {},
        activeItemWindows = {},
        ownedItemByNormalizedName = {},
        recentSlotUses = {},
        playerHitFrames = {},
        controllerNavPressed = {},
        currentRoomId = nil,
        lastCollectibleTotal = nil,
        lastFloorKey = nil,
        lastSaveFrame = 0,
    }
end

local function newPickupCounters()
    local counters = {}
    for _, category in ipairs(PICKUP_CATEGORIES) do
        counters[category] = { seen = 0, collected = 0 }
    end
    return counters
end

local function newSpecialCounters()
    local counters = {}
    for _, special in ipairs(SPECIAL_ROOMS) do
        counters[special.key] = { total = 0, visited = 0 }
    end
    return counters
end

local function newFloorState(key)
    return {
        key = key,
        name = game:GetLevel():GetName(),
        stage = game:GetLevel():GetStage(),
        stageType = game:GetLevel():GetStageType(),
        generatedRooms = 0,
        roomsVisited = 0,
        roomsCleared = 0,
        roomsWithSpikes = 0,
        special = newSpecialCounters(),
        rooms = {},
        mapRooms = {},
        pickups = newPickupCounters(),
        seenPickupKeys = {},
        collectedPickupKeys = {},
        chests = { seen = 0, opened = 0 },
        items = { seen = 0, collected = 0 },
        tinted = { seen = 0, broken = 0 },
        tintedSeenKeys = {},
        tintedBrokenKeys = {},
        combat = {
            damageDealt = 0,
            enemiesDamaged = 0,
            enemiesKilled = 0,
            playerHits = 0,
            damageTaken = 0,
            hurtBy = {},
            damageByItem = {},
            damagedKeys = {},
            killedKeys = {},
        },
        machineStats = {},
        diceRoomsUsed = 0,
    }
end

local function newRunState(seed)
    return {
        seed = seed,
        floors = {},
        currentFloorKey = nil,
        damageDealt = 0,
        enemiesDamaged = 0,
        enemiesKilled = 0,
        playerHits = 0,
        damageTaken = 0,
        hurtBy = {},
        damageByItem = {},
        itemDpsGains = {},
        enemyDamagedKeys = {},
        enemyKilledKeys = {},
        heldItemCounts = {},
        knownItemIds = {},
        itemEvents = {},
        lastDps = 0,
        lastItemEvent = nil,
    }
end

local function ensureRunTables()
    run.floors = run.floors or {}
    run.enemyDamagedKeys = run.enemyDamagedKeys or {}
    run.enemyKilledKeys = run.enemyKilledKeys or {}
    run.heldItemCounts = run.heldItemCounts or {}
    run.knownItemIds = run.knownItemIds or {}
    run.itemEvents = run.itemEvents or {}
    run.damageDealt = run.damageDealt or 0
    run.enemiesDamaged = run.enemiesDamaged or 0
    run.enemiesKilled = run.enemiesKilled or 0
    run.playerHits = run.playerHits or 0
    run.damageTaken = run.damageTaken or 0
    run.hurtBy = run.hurtBy or {}
    run.damageByItem = run.damageByItem or {}
    run.itemDpsGains = run.itemDpsGains or {}
    for _, floor in pairs(run.floors) do
        -- Manual map annotations were removed in schema-compatible fashion.
        floor.markers = nil
        floor.combat = floor.combat or {}
        floor.combat.damageDealt = floor.combat.damageDealt or 0
        floor.combat.enemiesDamaged = floor.combat.enemiesDamaged or 0
        floor.combat.enemiesKilled = floor.combat.enemiesKilled or 0
        floor.combat.playerHits = floor.combat.playerHits or 0
        floor.combat.damageTaken = floor.combat.damageTaken or 0
        floor.combat.hurtBy = floor.combat.hurtBy or {}
        floor.combat.damageByItem = floor.combat.damageByItem or {}
        floor.combat.damagedKeys = floor.combat.damagedKeys or {}
        floor.combat.killedKeys = floor.combat.killedKeys or {}
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
    floor.combat = floor.combat or {}
    floor.combat.damageDealt = floor.combat.damageDealt or 0
    floor.combat.enemiesDamaged = floor.combat.enemiesDamaged or 0
    floor.combat.enemiesKilled = floor.combat.enemiesKilled or 0
    floor.combat.playerHits = floor.combat.playerHits or 0
    floor.combat.damageTaken = floor.combat.damageTaken or 0
    floor.combat.hurtBy = floor.combat.hurtBy or {}
    floor.combat.damageByItem = floor.combat.damageByItem or {}
    floor.combat.damagedKeys = floor.combat.damagedKeys or {}
    floor.combat.killedKeys = floor.combat.killedKeys or {}
    run.currentFloorKey = key
    return floor
end

local function itemName(itemId)
    if EID and type(EID.getObjectName) == "function" and type(EID.getLanguage) == "function" then
        local languageOk, eidLanguage = pcall(EID.getLanguage, EID)
        local expectedLanguage = I18N.GetLanguage() == "zh" and "zh_cn" or "en_us"
        if languageOk and eidLanguage == expectedLanguage then
            local nameOk, localizedName = pcall(EID.getObjectName, EID, 5, 100, itemId)
            if nameOk and type(localizedName) == "string" and localizedName ~= "" then
                return localizedName
            end
        end
    end
    local config = itemConfig:GetCollectible(itemId)
    if I18N.GetLanguage() == "en" and config and config.Name and config.Name ~= "" then
        if string.sub(config.Name, 1, 1) ~= "#" then
            return config.Name
        end
        local readable = string.gsub(config.Name, "^#", "")
        readable = string.gsub(readable, "_NAME$", "")
        readable = string.gsub(readable, "_", " ")
        readable = string.lower(readable)
        readable = string.gsub(readable, "(%a)([%w']*)", function(first, rest)
            return string.upper(first) .. rest
        end)
        if readable ~= "" then return readable end
    end
    return trf("item.fallback", itemId)
end

local function isOffensiveItem(itemId)
    local config = itemConfig:GetCollectible(itemId)
    return config ~= nil and config:HasTags(ItemConfig.TAG_OFFENSIVE)
end

local function itemHistory(itemId)
    local key = tostring(itemId)
    local history = persistent.lifetime.itemHistory[key]
    if not history then
        history = {
            id = itemId,
            name = itemName(itemId),
            offensive = isOffensiveItem(itemId),
            observations = 0,
            gainSum = 0,
            afterDpsSum = 0,
            damageWhileHeld = 0,
            activeUses = 0,
            activeDamage = 0,
            activeSeconds = 0,
        }
        persistent.lifetime.itemHistory[key] = history
    end
    history.id = history.id or itemId
    history.name = history.name or itemName(itemId)
    if history.offensive == nil then history.offensive = isOffensiveItem(itemId) end
    history.observations = history.observations or 0
    history.gainSum = history.gainSum or 0
    history.afterDpsSum = history.afterDpsSum or 0
    history.damageWhileHeld = history.damageWhileHeld or 0
    history.activeUses = history.activeUses or 0
    history.activeDamage = history.activeDamage or 0
    history.activeSeconds = history.activeSeconds or 0
    return history
end

local function machineStat(container, variant)
    local key = tostring(variant)
    if not container[key] then
        container[key] = newMachineStat()
    end
    local stat = container[key]
    stat.uses = stat.uses or 0
    stat.costs = stat.costs or {}
    stat.payouts = stat.payouts or {}
    for _, resource in ipairs({ "coin", "key", "bomb", "health" }) do
        stat.costs[resource] = stat.costs[resource] or 0
    end
    for _, category in ipairs({
        "heart", "coin", "key", "bomb", "battery", "chest", "item", "other",
    }) do
        stat.payouts[category] = stat.payouts[category] or 0
    end
    return stat
end

local function estimatedRawDps()
    local totalDps = 0
    local totalDamage = 0
    local totalTears = 0
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        local tearsPerSecond = 30 / math.max(0.25, player.MaxFireDelay + 1)
        totalDps = totalDps + player.Damage * tearsPerSecond
        totalDamage = totalDamage + player.Damage
        totalTears = totalTears + tearsPerSecond
    end
    return totalDps, totalDamage, totalTears
end

local function playerRawDps(player)
    local tearsPerSecond = 30 / math.max(0.25, player.MaxFireDelay + 1)
    return player.Damage * tearsPerSecond
end

local function resourceTotals()
    local totals = { coin = 0, key = 0, bomb = 0, health = 0 }
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        totals.coin = totals.coin + player:GetNumCoins()
        totals.key = totals.key + player:GetNumKeys()
        totals.bomb = totals.bomb + player:GetNumBombs()
        totals.health = totals.health + player:GetHearts() + player:GetSoulHearts()
            + player:GetBoneHearts() * 2 + player:GetEternalHearts()
    end
    return totals
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
    floor.special = newSpecialCounters()
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
            existing.visited = existing.visited or descriptor.VisitedCount > 0
            floor.mapRooms[listKey] = existing

            local special = SPECIAL_ROOM_BY_TYPE[descriptor.Data.Type]
            if special then
                floor.special[special.key].total = floor.special[special.key].total + 1
            end
        end
    end

    for _, roomRecord in pairs(floor.rooms) do
        if roomRecord.visited then
            local special = SPECIAL_ROOM_BY_TYPE[roomRecord.roomType]
            if special then
                floor.special[special.key].visited = floor.special[special.key].visited + 1
            end
        end
    end
end

local function roomIdFromDescriptor(descriptor)
    return tostring(descriptor.ListIndex)
end

local function copyKeySet(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function copyDamageSourceMap(source)
    local copy = {}
    for key, record in pairs(source or {}) do
        copy[key] = {
            name = record.name,
            hits = record.hits or 0,
            damage = record.damage or 0,
        }
    end
    return copy
end

local function copyDamageAttributionMap(source)
    local copy = {}
    for key, record in pairs(source or {}) do
        copy[key] = {
            itemId = record.itemId,
            name = record.name,
            damage = record.damage or 0,
            directDamage = record.directDamage or 0,
            deltaDamage = record.deltaDamage or 0,
        }
    end
    return copy
end

local function copyNumberMap(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = tonumber(value) or 0 end
    return copy
end

local function captureRoomCombatSnapshot(floor, roomId)
    runtime.roomCombatSnapshot = {
        floorKey = floor.key,
        roomId = roomId,
        run = {
            damageDealt = run.damageDealt,
            enemiesDamaged = run.enemiesDamaged,
            enemiesKilled = run.enemiesKilled,
            playerHits = run.playerHits,
            damageTaken = run.damageTaken,
            hurtBy = copyDamageSourceMap(run.hurtBy),
            damageByItem = copyDamageAttributionMap(run.damageByItem),
            itemDpsGains = copyNumberMap(run.itemDpsGains),
            enemyDamagedKeys = copyKeySet(run.enemyDamagedKeys),
            enemyKilledKeys = copyKeySet(run.enemyKilledKeys),
        },
        floor = {
            damageDealt = floor.combat.damageDealt,
            enemiesDamaged = floor.combat.enemiesDamaged,
            enemiesKilled = floor.combat.enemiesKilled,
            playerHits = floor.combat.playerHits,
            damageTaken = floor.combat.damageTaken,
            hurtBy = copyDamageSourceMap(floor.combat.hurtBy),
            damageByItem = copyDamageAttributionMap(floor.combat.damageByItem),
            damagedKeys = copyKeySet(floor.combat.damagedKeys),
            killedKeys = copyKeySet(floor.combat.killedKeys),
        },
        lifetime = {
            damageDealt = persistent.lifetime.damageDealt,
            enemiesDamaged = persistent.lifetime.enemiesDamaged,
            enemiesKilled = persistent.lifetime.enemiesKilled,
            playerHits = persistent.lifetime.playerHits,
            damageTaken = persistent.lifetime.damageTaken,
            hurtBy = copyDamageSourceMap(persistent.lifetime.hurtBy),
            damageByItem = copyDamageAttributionMap(persistent.lifetime.damageByItem),
        },
    }
end

local function restoreRoomCombatSnapshot()
    local snapshot = runtime.roomCombatSnapshot
    if not snapshot or not run then return false end
    local floor = run.floors[snapshot.floorKey]
    if not floor or not floor.combat then return false end

    run.damageDealt = snapshot.run.damageDealt
    run.enemiesDamaged = snapshot.run.enemiesDamaged
    run.enemiesKilled = snapshot.run.enemiesKilled
    run.playerHits = snapshot.run.playerHits
    run.damageTaken = snapshot.run.damageTaken
    -- The snapshot is consumed immediately below, so transfer its already
    -- detached tables instead of allocating and copying every record again.
    run.hurtBy = snapshot.run.hurtBy or {}
    run.damageByItem = snapshot.run.damageByItem or {}
    run.itemDpsGains = snapshot.run.itemDpsGains or {}
    run.enemyDamagedKeys = snapshot.run.enemyDamagedKeys or {}
    run.enemyKilledKeys = snapshot.run.enemyKilledKeys or {}

    floor.combat.damageDealt = snapshot.floor.damageDealt
    floor.combat.enemiesDamaged = snapshot.floor.enemiesDamaged
    floor.combat.enemiesKilled = snapshot.floor.enemiesKilled
    floor.combat.playerHits = snapshot.floor.playerHits
    floor.combat.damageTaken = snapshot.floor.damageTaken
    floor.combat.hurtBy = snapshot.floor.hurtBy or {}
    floor.combat.damageByItem = snapshot.floor.damageByItem or {}
    floor.combat.damagedKeys = snapshot.floor.damagedKeys or {}
    floor.combat.killedKeys = snapshot.floor.killedKeys or {}

    persistent.lifetime.damageDealt = snapshot.lifetime.damageDealt
    persistent.lifetime.enemiesDamaged = snapshot.lifetime.enemiesDamaged
    persistent.lifetime.enemiesKilled = snapshot.lifetime.enemiesKilled
    persistent.lifetime.playerHits = snapshot.lifetime.playerHits
    persistent.lifetime.damageTaken = snapshot.lifetime.damageTaken
    persistent.lifetime.hurtBy = snapshot.lifetime.hurtBy or {}
    persistent.lifetime.damageByItem = snapshot.lifetime.damageByItem or {}
    runtime.activeItemWindows = {}
    runtime.pendingDps = {}
    runtime.preItemDps = {}
    runtime.roomCombatSnapshot = nil
    return true
end

local function scanCurrentRoomGrid(floor, roomRecord)
    local room = game:GetRoom()
    local activeTinted = {}
    local hasSpikes = false

    for gridIndex = 0, room:GetGridSize() - 1 do
        local gridEntity = room:GetGridEntity(gridIndex)
        if gridEntity then
            local gridType = gridEntity:GetType()
            if gridType == GridEntityType.GRID_ROCKT or gridType == GridEntityType.GRID_ROCK_SS then
                local key = roomRecord.id .. ":" .. tostring(gridIndex)
                activeTinted[key] = true
                if not floor.tintedSeenKeys[key] then
                    floor.tintedSeenKeys[key] = true
                    floor.tinted.seen = floor.tinted.seen + 1
                end
            elseif gridType == GridEntityType.GRID_SPIKES
                or gridType == GridEntityType.GRID_SPIKES_ONOFF then
                hasSpikes = true
            end
        end
    end

    for key in pairs(roomRecord.activeTinted or {}) do
        if not activeTinted[key] and not floor.tintedBrokenKeys[key] then
            floor.tintedBrokenKeys[key] = true
            floor.tinted.broken = floor.tinted.broken + 1
        end
    end
    roomRecord.activeTinted = activeTinted

    if hasSpikes and not roomRecord.hasSpikes then
        roomRecord.hasSpikes = true
        floor.roomsWithSpikes = floor.roomsWithSpikes + 1
    end
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
    runtime.pendingPickups = {}

    local roomRecord = floor.rooms[roomId]
    if not roomRecord then
        roomRecord = {
            id = roomId,
            grid = descriptor.SafeGridIndex,
            roomType = descriptor.Data.Type,
            shape = descriptor.Data.Shape,
            visited = false,
            clear = false,
            hasSpikes = false,
            activeTinted = {},
            diceTriggered = false,
        }
        floor.rooms[roomId] = roomRecord
    end

    roomRecord.grid = descriptor.SafeGridIndex
    roomRecord.roomType = descriptor.Data.Type
    roomRecord.shape = descriptor.Data.Shape
    if not roomRecord.visited then
        roomRecord.visited = true
        floor.roomsVisited = floor.roomsVisited + 1
        local special = SPECIAL_ROOM_BY_TYPE[roomRecord.roomType]
        if special then
            floor.special[special.key].visited = floor.special[special.key].visited + 1
        end
    end

    local mapRoom = floor.mapRooms[roomId] or {}
    mapRoom.grid = descriptor.SafeGridIndex
    mapRoom.roomType = descriptor.Data.Type
    mapRoom.shape = descriptor.Data.Shape
    mapRoom.display = descriptor.DisplayFlags
    mapRoom.visited = true
    floor.mapRooms[roomId] = mapRoom

    scanCurrentRoomGrid(floor, roomRecord)
    runtime.playerResources = {}
    captureRoomCombatSnapshot(floor, roomId)
end

local function classifyPickup(pickup)
    if pickup.Variant == PickupVariant.PICKUP_HEART then return "heart" end
    if pickup.Variant == PickupVariant.PICKUP_COIN then return "coin" end
    if pickup.Variant == PickupVariant.PICKUP_KEY then return "key" end
    if pickup.Variant == PickupVariant.PICKUP_BOMB then return "bomb" end
    if pickup.Variant == PickupVariant.PICKUP_LIL_BATTERY then return "battery" end
    if pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then return "item" end
    if CHEST_VARIANTS[pickup.Variant] then return "chest" end
    return nil
end

local function pickupKey(pickup)
    return tostring(runtime.currentRoomId or "room") .. ":" .. tostring(pickup.InitSeed)
        .. ":" .. tostring(pickup.Variant)
end

local function recentSlotVariantForPickup(pickup)
    local spawner = pickup.SpawnerEntity
    if spawner and spawner.Type == EntityType.ENTITY_SLOT then
        return spawner.Variant
    end
    if pickup.SpawnerType == EntityType.ENTITY_SLOT then
        return pickup.SpawnerVariant
    end

    local frame = Isaac.GetFrameCount()
    local bestVariant = nil
    local bestDistance = 120
    for _, recent in ipairs(runtime.recentSlotUses) do
        if frame - recent.frame <= 45 then
            local dx = pickup.Position.X - recent.x
            local dy = pickup.Position.Y - recent.y
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance < bestDistance then
                bestDistance = distance
                bestVariant = recent.variant
            end
        end
    end
    return bestVariant
end

local function addMachinePayout(variant, category)
    if not SLOT_INFO[variant] or not run then return end
    local floor = currentFloor()
    local floorStat = machineStat(floor.machineStats, variant)
    local lifetimeStat = machineStat(persistent.lifetime.machineStats, variant)
    local payoutCategory = category or "other"
    if not floorStat.payouts[payoutCategory] then payoutCategory = "other" end
    floorStat.payouts[payoutCategory] = floorStat.payouts[payoutCategory] + 1
    lifetimeStat.payouts[payoutCategory] = lifetimeStat.payouts[payoutCategory] + 1
end

local function recordPickupSeen(pickup)
    if not run or not runtime.currentRoomId then return end
    local floor = currentFloor()
    local key = pickupKey(pickup)
    if floor.seenPickupKeys[key] then return end

    local category = classifyPickup(pickup)
    floor.seenPickupKeys[key] = true
    if category and floor.pickups[category] then
        floor.pickups[category].seen = floor.pickups[category].seen + 1
    elseif category == "chest" then
        floor.chests.seen = floor.chests.seen + 1
    elseif category == "item" and pickup.SubType > 0 then
        floor.items.seen = floor.items.seen + 1
        run.knownItemIds[tostring(pickup.SubType)] = true
    end

    local slotVariant = recentSlotVariantForPickup(pickup)
    if slotVariant then
        addMachinePayout(slotVariant, category)
    end
end

local function completePickupCollection(key, pending)
    local floor = currentFloor()
    if floor.collectedPickupKeys[key] then return end
    floor.collectedPickupKeys[key] = true

    if floor.pickups[pending.category] then
        floor.pickups[pending.category].collected = floor.pickups[pending.category].collected + 1
    elseif pending.category == "chest" then
        floor.chests.opened = floor.chests.opened + 1
    elseif pending.category == "item" then
        floor.items.collected = floor.items.collected + 1
    end
end

local function updatePendingPickups()
    if not next(runtime.pendingPickups) then return end
    local live = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local pickup = entity:ToPickup()
        if pickup then
            live[pickupKey(pickup)] = {
                touched = pickup.Touched,
                subtype = pickup.SubType,
            }
        end
    end

    local frame = Isaac.GetFrameCount()
    for key, pending in pairs(runtime.pendingPickups) do
        if pending.roomId ~= runtime.currentRoomId then
            runtime.pendingPickups[key] = nil
        else
            local current = live[key]
            local age = frame - pending.frame
            if (current and current.touched) or (not current and age >= 1 and age <= 20) then
                completePickupCollection(key, pending)
                runtime.pendingPickups[key] = nil
            elseif age > 20 then
                runtime.pendingPickups[key] = nil
            end
        end
    end
end

local function totalCollectibleCount()
    local total = 0
    for index = 0, game:GetNumPlayers() - 1 do
        total = total + Isaac.GetPlayer(index):GetCollectibleCount()
    end
    return total
end

local function ownedCollectibleCount(itemId)
    local total = 0
    for index = 0, game:GetNumPlayers() - 1 do
        total = total + Isaac.GetPlayer(index):GetCollectibleNum(itemId, true)
    end
    return total
end

local function normalizedIdentityName(value)
    value = string.lower(tostring(value or ""))
    return string.gsub(value, "[^%w]", "")
end

local function queueDpsObservation(itemId, count)
    local frame = Isaac.GetFrameCount()
    local key = tostring(itemId)
    local snapshot = runtime.preItemDps[key]
    local beforeDps = run.lastDps or estimatedRawDps()
    if snapshot and frame - snapshot.frame <= 30 then
        beforeDps = snapshot.dps
    end
    runtime.pendingDps[#runtime.pendingDps + 1] = {
        itemId = itemId,
        count = count,
        beforeDps = beforeDps,
        readyFrame = frame + 4,
    }
    runtime.preItemDps[key] = nil
end

local function scanHeldItems(initial, knownOnly)
    local newCounts = {}
    local ownedItemByNormalizedName = {}
    local function scanItem(itemId)
        local count = ownedCollectibleCount(itemId)
        if count > 0 then
            local key = tostring(itemId)
            newCounts[key] = count
            run.knownItemIds[key] = true
            local normalizedName = normalizedIdentityName(itemName(itemId))
            if normalizedName ~= "" then
                ownedItemByNormalizedName[normalizedName] = itemId
            end
            local previous = tonumber(run.heldItemCounts[key]) or 0
            if not initial and count > previous then
                queueDpsObservation(itemId, count - previous)
            end
        end
    end

    if knownOnly then
        for key in pairs(run.knownItemIds) do
            local itemId = tonumber(key)
            if itemId then scanItem(itemId) end
        end
    else
        for itemId = 1, MAX_COLLECTIBLE_ID - 1 do
            scanItem(itemId)
        end
        for key in pairs(run.knownItemIds) do
            local itemId = tonumber(key)
            if itemId and itemId >= MAX_COLLECTIBLE_ID then
                scanItem(itemId)
            end
        end
    end
    for key, previousCount in pairs(run.heldItemCounts) do
        local currentCount = newCounts[key] or 0
        previousCount = tonumber(previousCount) or 0
        if currentCount < previousCount and run.itemDpsGains[key] then
            if currentCount == 0 then
                run.itemDpsGains[key] = nil
            else
                run.itemDpsGains[key] = run.itemDpsGains[key]
                    * currentCount / math.max(1, previousCount)
            end
        end
    end
    run.heldItemCounts = newCounts
    runtime.ownedItemByNormalizedName = ownedItemByNormalizedName
end

local function finalizeDpsObservations()
    if #runtime.pendingDps == 0 then return end
    local frame = Isaac.GetFrameCount()
    local afterDps = estimatedRawDps()
    local remaining = {}

    for _, pending in ipairs(runtime.pendingDps) do
        if frame >= pending.readyFrame then
            local count = math.max(1, pending.count)
            local gain = (afterDps - pending.beforeDps) / count
            local history = itemHistory(pending.itemId)
            history.observations = history.observations + count
            history.gainSum = history.gainSum + gain * count
            history.afterDpsSum = history.afterDpsSum + afterDps * count
            if gain > 0 then
                local itemKey = tostring(pending.itemId)
                run.itemDpsGains[itemKey] = (run.itemDpsGains[itemKey] or 0)
                    + gain * count
            end

            local event = {
                itemId = pending.itemId,
                name = history.name,
                offensive = history.offensive,
                beforeDps = pending.beforeDps,
                afterDps = afterDps,
                gain = gain,
            }
            run.lastItemEvent = event
            run.itemEvents[#run.itemEvents + 1] = event
            while #run.itemEvents > 8 do
                table.remove(run.itemEvents, 1)
            end
        else
            remaining[#remaining + 1] = pending
        end
    end
    runtime.pendingDps = remaining
end

local function playerKey(player)
    return tostring(GetPtrHash(player))
end

local function finishActiveItemWindow(key, endFrame)
    local window = runtime.activeItemWindows[key]
    if not window then return end
    local durationFrames = math.max(1, math.min(endFrame, window.expires) - window.started)
    local history = itemHistory(window.itemId)
    history.activeUses = history.activeUses + 1
    history.activeDamage = history.activeDamage + window.damage
    history.activeSeconds = history.activeSeconds + durationFrames / 30
    runtime.activeItemWindows[key] = nil
end

local function updateActiveItemWindows()
    local frame = Isaac.GetFrameCount()
    local expired = {}
    for key, window in pairs(runtime.activeItemWindows) do
        if frame >= window.expires then
            expired[#expired + 1] = key
        end
    end
    for _, key in ipairs(expired) do
        finishActiveItemWindow(key, frame)
    end
end

local function sourceEntityChain(source)
    local entity = source and source.Entity or nil
    local visited = {}
    local chain = {}
    for _ = 1, 10 do
        if not entity then return chain end
        local hash = GetPtrHash(entity)
        if visited[hash] then return chain end
        visited[hash] = true
        chain[#chain + 1] = entity
        if entity.SpawnerEntity then
            entity = entity.SpawnerEntity
        elseif entity.Parent then
            entity = entity.Parent
        else
            return chain
        end
    end
    return chain
end

local function rootPlayerFromSource(source)
    for _, entity in ipairs(sourceEntityChain(source)) do
        local player = entity:ToPlayer()
        if player then return player end
        local familiar = entity:ToFamiliar()
        if familiar and familiar.Player then return familiar.Player end
    end
    return nil
end

local FAMILIAR_NAME_BY_VARIANT = {}
for enumName, variant in pairs(FamiliarVariant or {}) do
    if type(enumName) == "string" and type(variant) == "number" then
        local readableName = string.gsub(enumName, "^FAMILIAR_", "")
        FAMILIAR_NAME_BY_VARIANT[variant] = normalizedIdentityName(readableName)
    end
end

local WEAPON_ITEM_CANDIDATES = {
    { weapon = WeaponType.WEAPON_KNIFE, item = CollectibleType.COLLECTIBLE_MOMS_KNIFE },
    { weapon = WeaponType.WEAPON_TECH_X, item = CollectibleType.COLLECTIBLE_TECH_X },
    { weapon = WeaponType.WEAPON_BRIMSTONE, item = CollectibleType.COLLECTIBLE_BRIMSTONE },
    { weapon = WeaponType.WEAPON_BOMBS, item = CollectibleType.COLLECTIBLE_DR_FETUS },
    { weapon = WeaponType.WEAPON_ROCKETS, item = CollectibleType.COLLECTIBLE_EPIC_FETUS },
    { weapon = WeaponType.WEAPON_MONSTROS_LUNGS, item = CollectibleType.COLLECTIBLE_MONSTROS_LUNG },
    { weapon = WeaponType.WEAPON_LUDOVICO_TECHNIQUE, item = CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE },
    { weapon = WeaponType.WEAPON_LASER, item = CollectibleType.COLLECTIBLE_TECHNOLOGY },
    { weapon = WeaponType.WEAPON_SPIRIT_SWORD, item = CollectibleType.COLLECTIBLE_SPIRIT_SWORD },
    { weapon = WeaponType.WEAPON_FETUS, item = CollectibleType.COLLECTIBLE_C_SECTION },
}

local function playerOwnsItem(player, itemId)
    return type(itemId) == "number" and itemId > 0
        and player:GetCollectibleNum(itemId, true) > 0
end

local function playerUsesWeapon(player, weaponType)
    return type(weaponType) == "number" and player:HasWeaponType(weaponType)
end

local function familiarDamageItem(chain, player)
    for _, sourceEntity in ipairs(chain) do
        local familiar = sourceEntity:ToFamiliar()
        if familiar then
            local normalizedName = FAMILIAR_NAME_BY_VARIANT[familiar.Variant]
            local itemId = normalizedName
                and runtime.ownedItemByNormalizedName[normalizedName] or nil
            if playerOwnsItem(player, itemId) then return itemId end
        end
    end
    return nil
end

local function directDamageItem(source, player)
    local chain = sourceEntityChain(source)
    local familiarItem = familiarDamageItem(chain, player)
    if familiarItem then return familiarItem end

    local primary = chain[1]
    local knife = primary and primary:ToKnife() or nil
    if knife and playerOwnsItem(player, CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
        return CollectibleType.COLLECTIBLE_MOMS_KNIFE
    end

    local laser = primary and primary:ToLaser() or nil
    if laser then
        if laser:IsCircleLaser()
            and laser.SubType == 2
            and playerOwnsItem(player, CollectibleType.COLLECTIBLE_TECH_X) then
            return CollectibleType.COLLECTIBLE_TECH_X
        end
        if playerUsesWeapon(player, WeaponType.WEAPON_BRIMSTONE)
            and playerOwnsItem(player, CollectibleType.COLLECTIBLE_BRIMSTONE) then
            return CollectibleType.COLLECTIBLE_BRIMSTONE
        end
        if playerOwnsItem(player, CollectibleType.COLLECTIBLE_TECHNOLOGY_2) then
            return CollectibleType.COLLECTIBLE_TECHNOLOGY_2
        end
        if playerOwnsItem(player, CollectibleType.COLLECTIBLE_TECHNOLOGY_ZERO) then
            return CollectibleType.COLLECTIBLE_TECHNOLOGY_ZERO
        end
        if playerOwnsItem(player, CollectibleType.COLLECTIBLE_TECHNOLOGY) then
            return CollectibleType.COLLECTIBLE_TECHNOLOGY
        end
    end

    local tear = primary and primary:ToTear() or nil
    local bomb = primary and primary:ToBomb() or nil
    if (tear or bomb) and playerOwnsItem(player, CollectibleType.COLLECTIBLE_IPECAC) then
        return CollectibleType.COLLECTIBLE_IPECAC
    end
    if bomb and playerOwnsItem(player, CollectibleType.COLLECTIBLE_DR_FETUS) then
        return CollectibleType.COLLECTIBLE_DR_FETUS
    end

    for _, candidate in ipairs(WEAPON_ITEM_CANDIDATES) do
        if playerOwnsItem(player, candidate.item)
            and playerUsesWeapon(player, candidate.weapon) then
            return candidate.item
        end
    end

    -- Effects, lasers, and bombs created by an active item commonly point
    -- straight back to the player. Known passive weapons above take priority;
    -- ordinary tears and knives are never reassigned merely because a window is open.
    if not tear and not knife then
        local window = runtime.activeItemWindows[playerKey(player)]
        if window and Isaac.GetFrameCount() <= window.expires then
            return window.itemId
        end
    end
    return nil
end

local function addAttributedDamage(container, itemId, amount, kind)
    if amount <= 0 then return end
    local key = itemId and tostring(itemId) or "base"
    local record = container[key]
    if not record then
        record = {
            itemId = itemId,
            name = itemId and itemName(itemId) or tr("combat.baseAttack"),
            damage = 0,
            directDamage = 0,
            deltaDamage = 0,
        }
        container[key] = record
    end
    record.damage = (record.damage or 0) + amount
    if kind == "delta" then
        record.deltaDamage = (record.deltaDamage or 0) + amount
    else
        record.directDamage = (record.directDamage or 0) + amount
    end
end

local function addAttributedDamageEverywhere(floor, itemId, amount, kind)
    addAttributedDamage(run.damageByItem, itemId, amount, kind)
    addAttributedDamage(floor.combat.damageByItem, itemId, amount, kind)
    addAttributedDamage(persistent.lifetime.damageByItem, itemId, amount, kind)
end

local function attributePlayerDamage(floor, source, player, amount)
    local directItemId = directDamageItem(source, player)
    local rawDps = playerRawDps(player)
    local candidates = {}
    local totalGain = 0

    if rawDps > 0 then
        for key, observedGain in pairs(run.itemDpsGains or {}) do
            local itemId = tonumber(key)
            local gain = math.max(0, tonumber(observedGain) or 0)
            if gain > 0 and itemId ~= directItemId and playerOwnsItem(player, itemId) then
                candidates[#candidates + 1] = { itemId = itemId, gain = gain }
                totalGain = totalGain + gain
            end
        end
    end
    table.sort(candidates, function(left, right) return left.itemId < right.itemId end)

    local remaining = amount
    local scale = totalGain > rawDps and rawDps / totalGain or 1
    for _, candidate in ipairs(candidates) do
        local share = math.min(remaining, amount * candidate.gain / rawDps * scale)
        if share > 0 then
            addAttributedDamageEverywhere(floor, candidate.itemId, share, "delta")
            remaining = remaining - share
        end
    end

    if remaining > 0 then
        addAttributedDamageEverywhere(floor, directItemId, remaining, "direct")
        if directItemId then
            local window = runtime.activeItemWindows[playerKey(player)]
            if window and window.itemId == directItemId then
                window.damage = window.damage + remaining
            end
        end
    end
end

local ENTITY_TYPE_LABEL_OVERRIDES = {
    [EntityType.ENTITY_ATTACKFLY] = "Attack Fly",
    [EntityType.ENTITY_LARRYJR] = "Larry Jr.",
    [EntityType.ENTITY_BOOMFLY] = "Boom Fly",
    [EntityType.ENTITY_MRMAW] = "Mr. Maw",
    [EntityType.ENTITY_FLAMINGHOPPER] = "Flaming Hopper",
    [EntityType.ENTITY_BIGSPIDER] = "Big Spider",
    [EntityType.ENTITY_ETERNALFLY] = "Eternal Fly",
    [EntityType.ENTITY_DADDYLONGLEGS] = "Daddy Long Legs",
}

local ENTITY_TYPE_LABELS = {}
for enumName, entityType in pairs(EntityType) do
    if type(enumName) == "string" and type(entityType) == "number" then
        local label = string.gsub(enumName, "^ENTITY_", "")
        label = string.gsub(label, "_", " ")
        label = string.lower(label)
        label = string.gsub(label, "(%a)([%w']*)", function(first, rest)
            return string.upper(first) .. rest
        end)
        if not ENTITY_TYPE_LABELS[entityType]
            or #label < #ENTITY_TYPE_LABELS[entityType] then
            ENTITY_TYPE_LABELS[entityType] = label
        end
    end
end
for entityType, label in pairs(ENTITY_TYPE_LABEL_OVERRIDES) do
    ENTITY_TYPE_LABELS[entityType] = label
end

local function hasDamageFlag(flags, flag)
    return flags ~= nil and flag ~= nil and flag > 0
        and math.floor(flags / flag) % 2 == 1
end

local function hostileDamageOwner(source)
    local entity = source and source.Entity or nil
    local visited = {}
    for _ = 1, 10 do
        if not entity then return nil end
        local hash = GetPtrHash(entity)
        if visited[hash] then return nil end
        visited[hash] = true
        if entity:IsEnemy() and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            return entity
        end
        if entity.SpawnerEntity then
            entity = entity.SpawnerEntity
        elseif entity.Parent then
            entity = entity.Parent
        else
            return nil
        end
    end
    return nil
end

local function entityDamageSource(entity)
    local entityType = entity.Type or 0
    local variant = entity.Variant or 0
    local subtype = entity.SubType or 0
    local id = tostring(entityType) .. "." .. tostring(variant)
    if subtype ~= 0 then id = id .. "." .. tostring(subtype) end

    local label = ENTITY_TYPE_LABELS[entityType] or ("Entity " .. tostring(entityType))
    if entityType == EntityType.ENTITY_SLOT and SLOT_INFO[variant] then
        label = tr(SLOT_INFO[variant].nameKey)
    end
    return "entity:" .. id, label .. " [" .. id .. "]"
end

local ENVIRONMENT_DAMAGE_SOURCES = {
    { flag = DamageFlag.DAMAGE_SPIKES, key = "spikes", name = "Spikes" },
    { flag = DamageFlag.DAMAGE_CURSED_DOOR, key = "cursed-door", name = "Cursed Door" },
    { flag = DamageFlag.DAMAGE_CHEST, key = "spiked-chest", name = "Spiked Chest" },
    { flag = DamageFlag.DAMAGE_POOP, key = "red-poop", name = "Red Poop" },
    { flag = DamageFlag.DAMAGE_FIRE, key = "fire", name = "Fire" },
    { flag = DamageFlag.DAMAGE_ACID, key = "acid", name = "Acid / Creep" },
    { flag = DamageFlag.DAMAGE_EXPLOSION, key = "explosion", name = "Explosion" },
    { flag = DamageFlag.DAMAGE_LASER, key = "laser", name = "Laser" },
    { flag = DamageFlag.DAMAGE_DEVIL, key = "devil-deal", name = "Devil Deal" },
}

local function damageSourceIdentity(source, flags)
    local owner = hostileDamageOwner(source)
    if owner then return entityDamageSource(owner) end

    for _, environment in ipairs(ENVIRONMENT_DAMAGE_SOURCES) do
        if hasDamageFlag(flags, environment.flag) then
            return "environment:" .. environment.key, environment.name
        end
    end

    local sourceEntity = source and source.Entity or nil
    if sourceEntity then
        if sourceEntity:ToPlayer() then
            return "environment:self", "Self-inflicted"
        end
        return entityDamageSource(sourceEntity)
    end
    if source and source.Type and source.Type ~= 0 then
        local entityType = source.Type
        local variant = source.Variant or 0
        local id = tostring(entityType) .. "." .. tostring(variant)
        local label = ENTITY_TYPE_LABELS[entityType] or ("Entity " .. tostring(entityType))
        return "entity:" .. id, label .. " [" .. id .. "]"
    end
    return "environment:unknown", "Unknown source"
end

local function addDamageSource(container, key, name, amount)
    local record = container[key]
    if not record then
        record = { name = name, hits = 0, damage = 0 }
        container[key] = record
    end
    record.name = name
    record.hits = (record.hits or 0) + 1
    record.damage = (record.damage or 0) + amount
end

local function enemyKey(entity)
    return tostring(runtime.currentRoomId or "room") .. ":" .. tostring(entity.InitSeed)
end

local function addMachineUse(variant, resource, amount, slot)
    if not SLOT_INFO[variant] or amount <= 0 then return end
    local floor = currentFloor()
    local floorStat = machineStat(floor.machineStats, variant)
    local lifetimeStat = machineStat(persistent.lifetime.machineStats, variant)
    local uses = resource == "health" and 1 or amount
    floorStat.uses = floorStat.uses + uses
    lifetimeStat.uses = lifetimeStat.uses + uses
    floorStat.costs[resource] = floorStat.costs[resource] + amount
    lifetimeStat.costs[resource] = lifetimeStat.costs[resource] + amount

    runtime.recentSlotUses[#runtime.recentSlotUses + 1] = {
        variant = variant,
        x = slot.Position.X,
        y = slot.Position.Y,
        frame = Isaac.GetFrameCount(),
    }
    while #runtime.recentSlotUses > 12 do
        table.remove(runtime.recentSlotUses, 1)
    end
end

local function nearestPayableSlot(player, resource)
    local nearest = nil
    local nearestDistance = 64
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_SLOT, -1, -1, false, false)) do
        local info = SLOT_INFO[entity.Variant]
        if info and info.cost == resource and not entity:IsDead() then
            local distance = entity.Position:Distance(player.Position)
            if distance < nearestDistance then
                nearestDistance = distance
                nearest = entity
            end
        end
    end
    return nearest
end

local function playerResourceSnapshot(player)
    return {
        coin = player:GetNumCoins(),
        key = player:GetNumKeys(),
        bomb = player:GetNumBombs(),
        health = player:GetHearts() + player:GetSoulHearts()
            + player:GetBoneHearts() * 2 + player:GetEternalHearts(),
    }
end

local function updateMachinePayments()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        local key = playerKey(player)
        local current = playerResourceSnapshot(player)
        local previous = runtime.playerResources[key]
        if previous then
            for _, resource in ipairs({ "coin", "key", "bomb", "health" }) do
                local spent = previous[resource] - current[resource]
                if spent > 0 then
                    local slot = nearestPayableSlot(player, resource)
                    if slot then
                        addMachineUse(slot.Variant, resource, spent, slot)
                    end
                end
            end
        end
        runtime.playerResources[key] = current
    end
end

local function rawKeyPressed(key)
    return Input.IsButtonPressed(key, 0) and not Input.IsButtonPressed(key % 32, 0)
end

local function keyTriggered(key)
    local pressed = rawKeyPressed(key)
    local triggered = pressed and not runtime.keyStates[key]
    runtime.keyStates[key] = pressed
    return triggered
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

local function controllerNavigationTriggered()
    local activeControllerIndexes = {}
    local leftTriggered = false
    local rightTriggered = false
    for index = 0, game:GetNumPlayers() - 1 do
        local controllerIndex = Isaac.GetPlayer(index).ControllerIndex
        if not activeControllerIndexes[controllerIndex] then
            local state = runtime.controllerNavPressed[controllerIndex]
                or { left = false, right = false }
            local leftPressed = Input.IsButtonPressed(CONTROLLER_LEFT, controllerIndex)
            local rightPressed = Input.IsButtonPressed(CONTROLLER_RIGHT, controllerIndex)
            leftTriggered = leftTriggered or (leftPressed and not state.left)
            rightTriggered = rightTriggered or (rightPressed and not state.right)
            state.left = leftPressed
            state.right = rightPressed
            runtime.controllerNavPressed[controllerIndex] = state
            activeControllerIndexes[controllerIndex] = true
        end
    end
    return leftTriggered, rightTriggered
end

local function setOverlayView(view)
    ui.view = view
    if view == "map" then refreshFloorLayout(currentFloor()) end
end

local function updateOverlayControls()
    local keyboardToggle = keyboardShortcutTriggered()
    local controllerToggle = controllerShortcutTriggered()
    local toggleTriggered = keyboardToggle or controllerToggle
    local keyboardLeft = keyTriggered(Keyboard.KEY_LEFT)
    local keyboardRight = keyTriggered(Keyboard.KEY_RIGHT)
    local controllerLeft, controllerRight = controllerNavigationTriggered()

    if mcmLoaded and MCM.IsVisible then
        mcmWasVisible = true
        return
    end
    if mcmWasVisible then
        mcmWasVisible = false
        return
    end

    local changed = false
    if toggleTriggered then
        ui.overlayVisible = not ui.overlayVisible
        if ui.overlayVisible then setOverlayView("map") end
        changed = true
    elseif ui.overlayVisible and (keyboardLeft or controllerLeft) then
        setOverlayView("map")
        changed = true
    elseif ui.overlayVisible and (keyboardRight or controllerRight) then
        setOverlayView("combat")
        changed = true
    end

    if changed then savePersistentData() end
end

local function updateRoomState()
    local floor = currentFloor()
    local descriptor = game:GetLevel():GetCurrentRoomDesc()
    if not descriptor or not descriptor.Data then return end
    local roomId = roomIdFromDescriptor(descriptor)
    local roomRecord = floor.rooms[roomId]
    if not roomRecord then
        visitCurrentRoom()
        roomRecord = floor.rooms[roomId]
        if not roomRecord then return end
    end

    if descriptor.Clear and not roomRecord.clear then
        roomRecord.clear = true
        floor.roomsCleared = floor.roomsCleared + 1
    end

    if roomRecord.roomType == RoomType.ROOM_DICE
        and descriptor.PressurePlatesTriggered
        and not roomRecord.diceTriggered then
        roomRecord.diceTriggered = true
        floor.diceRoomsUsed = floor.diceRoomsUsed + 1
    end

    if Isaac.GetFrameCount() % 15 == 0 then
        scanCurrentRoomGrid(floor, roomRecord)
    end
end

local function floorSummary(floor)
    if not floor then return "" end
    return string.format(
        "%s: damage dealt %.1f, enemies hit %d, killed %d, damage taken %d hits / %.1f hearts",
        floor.name or "Floor",
        floor.combat.damageDealt or 0,
        floor.combat.enemiesDamaged or 0,
        floor.combat.enemiesKilled or 0,
        floor.combat.playerHits or 0,
        (floor.combat.damageTaken or 0) / 2
    )
end

function BeginnerLedger:OnGameStarted(isContinued)
    loadPersistentData()
    local seed = game:GetSeeds():GetStartSeed()
    if isContinued and persistent.activeRun and persistent.activeRun.seed == seed then
        run = persistent.activeRun
        ensureRunTables()
    else
        run = newRunState(seed)
        persistent.lifetime.runs = persistent.lifetime.runs + 1
    end

    resetRuntime()
    ui.view = "map"
    runtime.lastFloorKey = floorKey()
    run.lastDps = estimatedRawDps()
    scanHeldItems(true)
    runtime.lastCollectibleTotal = totalCollectibleCount()
    visitCurrentRoom()
    savePersistentData()
end

function BeginnerLedger:OnNewRoom()
    if not run then return end
    local newFloorKey = floorKey()
    if runtime.lastFloorKey and runtime.lastFloorKey ~= newFloorKey then
        local previousFloor = run.floors[runtime.lastFloorKey]
        Isaac.DebugString("[Sharingan] " .. floorSummary(previousFloor))
    end
    runtime.lastFloorKey = newFloorKey
    visitCurrentRoom()
end

function BeginnerLedger:OnNewLevel()
    if not run then return end
    local floor = currentFloor()
    refreshFloorLayout(floor)
    savePersistentData()
end

function BeginnerLedger:OnPickupUpdate(pickup)
    if not run then return end
    recordPickupSeen(pickup)
end

function BeginnerLedger:OnPickupCollision(pickup, collider)
    if not run or not collider:ToPlayer() then return nil end
    local category = classifyPickup(pickup)
    if not category then return nil end
    if category == "item" and pickup.SubType <= 0 then return nil end

    recordPickupSeen(pickup)
    local key = pickupKey(pickup)
    local floor = currentFloor()
    if not floor.collectedPickupKeys[key] then
        runtime.pendingPickups[key] = {
            category = category,
            itemId = category == "item" and pickup.SubType or nil,
            frame = Isaac.GetFrameCount(),
            roomId = runtime.currentRoomId,
        }
        if category == "item" then
            local itemKey = tostring(pickup.SubType)
            run.knownItemIds[itemKey] = true
            runtime.itemScanDueFrame = Isaac.GetFrameCount() + 4
            runtime.preItemDps[itemKey] = {
                dps = estimatedRawDps(),
                frame = Isaac.GetFrameCount(),
            }
        end
    end
    return nil
end

function BeginnerLedger:OnEntityTakeDamage(entity, amount, flags, source)
    if not run or amount <= 0 then return nil end
    local player = entity:ToPlayer()
    if player then
        if hasDamageFlag(flags, DamageFlag.DAMAGE_FAKE) then return nil end
        local hitKey = playerKey(player) .. ":" .. tostring(Isaac.GetFrameCount())
        if not runtime.playerHitFrames[hitKey] then
            runtime.playerHitFrames[hitKey] = true
            local floor = currentFloor()
            local sourceKey, sourceName = damageSourceIdentity(source, flags)
            run.playerHits = run.playerHits + 1
            run.damageTaken = run.damageTaken + amount
            addDamageSource(run.hurtBy, sourceKey, sourceName, amount)
            persistent.lifetime.playerHits = persistent.lifetime.playerHits + 1
            persistent.lifetime.damageTaken = persistent.lifetime.damageTaken + amount
            addDamageSource(persistent.lifetime.hurtBy, sourceKey, sourceName, amount)
            floor.combat.playerHits = floor.combat.playerHits + 1
            floor.combat.damageTaken = floor.combat.damageTaken + amount
            addDamageSource(floor.combat.hurtBy, sourceKey, sourceName, amount)
        end
        return nil
    end

    if not entity:IsEnemy() or entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
        return nil
    end
    local sourcePlayer = rootPlayerFromSource(source)
    if not sourcePlayer then return nil end

    local floor = currentFloor()
    local key = enemyKey(entity)
    run.damageDealt = run.damageDealt + amount
    floor.combat.damageDealt = floor.combat.damageDealt + amount
    persistent.lifetime.damageDealt = persistent.lifetime.damageDealt + amount
    attributePlayerDamage(floor, source, sourcePlayer, amount)

    if not run.enemyDamagedKeys[key] then
        run.enemyDamagedKeys[key] = true
        run.enemiesDamaged = run.enemiesDamaged + 1
        persistent.lifetime.enemiesDamaged = persistent.lifetime.enemiesDamaged + 1
    end
    if not floor.combat.damagedKeys[key] then
        floor.combat.damagedKeys[key] = true
        floor.combat.enemiesDamaged = floor.combat.enemiesDamaged + 1
    end

    return nil
end

function BeginnerLedger:OnEntityKill(entity)
    if not run or not entity:IsEnemy() then return end
    local key = enemyKey(entity)
    if not run.enemyDamagedKeys[key] or run.enemyKilledKeys[key] then return end
    run.enemyKilledKeys[key] = true
    run.enemiesKilled = run.enemiesKilled + 1
    persistent.lifetime.enemiesKilled = persistent.lifetime.enemiesKilled + 1

    local floor = currentFloor()
    if not floor.combat.killedKeys[key] then
        floor.combat.killedKeys[key] = true
        floor.combat.enemiesKilled = floor.combat.enemiesKilled + 1
    end
end

function BeginnerLedger:OnUseItem(itemId, rng, player)
    if not run or not player then return nil end
    local key = playerKey(player)
    if runtime.activeItemWindows[key] then
        finishActiveItemWindow(key, Isaac.GetFrameCount())
    end
    runtime.activeItemWindows[key] = {
        itemId = itemId,
        started = Isaac.GetFrameCount(),
        expires = Isaac.GetFrameCount() + ACTIVE_ITEM_WINDOW_FRAMES,
        damage = 0,
    }
    run.knownItemIds[tostring(itemId)] = true
    return nil
end

function BeginnerLedger:OnUpdate()
    if not run or game:GetNumPlayers() == 0 then return end
    local frame = Isaac.GetFrameCount()
    updateOverlayControls()
    updateRoomState()
    updatePendingPickups()
    local collectibleTotal = totalCollectibleCount()
    local forceItemScan = runtime.itemScanDueFrame ~= nil
        and frame >= runtime.itemScanDueFrame
    local rewindKnownOnly = runtime.rewindKnownItemScanUntilFrame ~= nil
        and frame <= runtime.rewindKnownItemScanUntilFrame
    if runtime.lastCollectibleTotal == nil then
        scanHeldItems(true)
        runtime.lastCollectibleTotal = collectibleTotal
    elseif collectibleTotal ~= runtime.lastCollectibleTotal or forceItemScan then
        scanHeldItems(false, rewindKnownOnly)
        runtime.lastCollectibleTotal = collectibleTotal
        runtime.itemScanDueFrame = nil
        runtime.rewindKnownItemScanUntilFrame = nil
    end
    if runtime.rewindKnownItemScanUntilFrame ~= nil
        and frame > runtime.rewindKnownItemScanUntilFrame then
        runtime.rewindKnownItemScanUntilFrame = nil
    end
    finalizeDpsObservations()
    updateActiveItemWindows()
    run.lastDps = estimatedRawDps()

    if frame - runtime.lastSaveFrame >= SAVE_INTERVAL then
        runtime.lastSaveFrame = frame
        savePersistentData()
    end
end

function BeginnerLedger:OnGameEnd()
    if not run then return end
    Isaac.DebugString(string.format(
        "[Sharingan] Run: damage dealt %.1f, enemies damaged %d, kills %d, damage taken %d hits / %.1f hearts",
        run.damageDealt,
        run.enemiesDamaged,
        run.enemiesKilled,
        run.playerHits,
        run.damageTaken / 2
    ))
    persistent.activeRun = nil
    run = nil
    savePersistentData()
end

function BeginnerLedger:OnPreGameExit()
    if run then
        savePersistentData()
    end
end

function BeginnerLedger:OnWheelchairPreRewind()
    local frame = Isaac.GetFrameCount()
    -- Rewind can temporarily change collectible totals. During the short
    -- restoration window, reconcile only items already observed this run and
    -- postpone periodic JSON serialization away from the transition frame.
    runtime.rewindKnownItemScanUntilFrame = frame + 30
    runtime.lastSaveFrame = frame
    if restoreRoomCombatSnapshot() then
        Isaac.DebugString("[Sharingan] Restored combat counters to room-entry state before rewind.")
    end
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

local function utf8Characters(text)
    local characters = {}
    for character in string.gmatch(text, "[%z\1-\127\194-\244][\128-\191]*") do
        characters[#characters + 1] = character
    end
    return characters
end

local function wrapText(text, maxWidth, style)
    if text == "" or textWidth(text, style) <= maxWidth then
        return { text }
    end

    local tokens = {}
    local separator = " "
    if I18N.GetLanguage() == "zh" then
        tokens = utf8Characters(text)
        separator = ""
    else
        for word in string.gmatch(text, "%S+") do
            tokens[#tokens + 1] = word
        end
    end

    local lines = {}
    local current = ""
    for _, token in ipairs(tokens) do
        local candidate = current == "" and token or current .. separator .. token
        if current ~= "" and textWidth(candidate, style) > maxWidth then
            lines[#lines + 1] = current
            current = token
        else
            current = candidate
        end
    end
    if current ~= "" then lines[#lines + 1] = current end
    return #lines > 0 and lines or { text }
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

local function makePageDrawer(x, y, maxWidth, maxY)
    local cursorY = y
    return function(text, color, style)
        local actualStyle = style or "small"
        local lineHeight = actualStyle == "title" and 14 or 11
        for _, wrapped in ipairs(wrapText(text, maxWidth, actualStyle)) do
            if cursorY + lineHeight > maxY then return end
            renderLine(wrapped, x, cursorY, color, actualStyle)
            cursorY = cursorY + lineHeight
        end
    end
end

local function sortedDamageSources(container)
    local rows = {}
    for _, record in pairs(container or {}) do
        rows[#rows + 1] = {
            name = record.name or tr("combat.unknownSource"),
            hits = record.hits or 0,
            damage = record.damage or 0,
        }
    end
    table.sort(rows, function(left, right)
        if left.hits ~= right.hits then return left.hits > right.hits end
        if left.damage ~= right.damage then return left.damage > right.damage end
        return string.lower(left.name) < string.lower(right.name)
    end)
    return rows
end

local function damageSourceRow(index, source, maxWidth)
    local prefix = tostring(index) .. ". "
    local suffix = trf("combat.hitCount", source.hits)
    local label = source.name
    local shortened = false
    while #label > 4 and textWidth(prefix .. label .. suffix, "small") > maxWidth do
        label = string.sub(label, 1, #label - 1)
        shortened = true
    end
    if shortened then
        while #label > 1 and textWidth(prefix .. label .. "..." .. suffix, "small") > maxWidth do
            label = string.sub(label, 1, #label - 1)
        end
        label = label .. "..."
    end
    return prefix .. label .. suffix
end

local function sortedItemDamage(container)
    local rows = {}
    for _, record in pairs(container or {}) do
        if type(record.itemId) == "number" and (record.damage or 0) > 0 then
            rows[#rows + 1] = {
                itemId = record.itemId,
                name = record.name or itemName(record.itemId),
                damage = record.damage or 0,
                directDamage = record.directDamage or 0,
                deltaDamage = record.deltaDamage or 0,
            }
        end
    end
    table.sort(rows, function(left, right)
        if left.damage ~= right.damage then return left.damage > right.damage end
        return string.lower(left.name) < string.lower(right.name)
    end)
    return rows
end

local function itemDamageRow(index, record, maxWidth)
    local prefix = tostring(index) .. ". "
    local suffix = trf("combat.itemDamageAmount", record.damage)
    local label = record.name
    local shortened = false
    while #label > 4 and textWidth(prefix .. label .. suffix, "small") > maxWidth do
        label = string.sub(label, 1, #label - 1)
        shortened = true
    end
    if shortened then
        while #label > 1 and textWidth(prefix .. label .. "..." .. suffix, "small") > maxWidth do
            label = string.sub(label, 1, #label - 1)
        end
        label = label .. "..."
    end
    return prefix .. label .. suffix
end

local function renderCombatPage(floor, x, y, maxWidth, maxY)
    local rawDps, damage, tears = estimatedRawDps()
    local draw = makePageDrawer(x, y, maxWidth, maxY)

    draw(trf("combat.summaryStats", rawDps, damage, tears), { 0.55, 1.00, 0.55 })
    draw(trf("combat.summaryScope", tr("combat.floor"), floor.combat.damageDealt,
        floor.combat.enemiesDamaged, floor.combat.enemiesKilled))
    draw(trf("combat.summaryScope", tr("combat.run"), run.damageDealt,
        run.enemiesDamaged, run.enemiesKilled))
    draw(trf("combat.summaryTaken", floor.combat.playerHits,
        floor.combat.damageTaken / 2, run.playerHits, run.damageTaken / 2),
        { 1.00, 0.62, 0.62 })

    draw(tr("combat.weaponTitle"), { 0.55, 0.80, 1.00 })
    local itemRows = sortedItemDamage(run.damageByItem)
    if #itemRows == 0 then
        draw(tr("combat.noItemDamage"), { 0.70, 0.70, 0.70 })
    else
        for index = 1, math.min(5, #itemRows) do
            draw(itemDamageRow(index, itemRows[index], maxWidth))
        end
    end

    draw(tr("combat.hurtByTitle"), { 1.00, 0.90, 0.35 })
    local sources = sortedDamageSources(floor.combat.hurtBy)
    if #sources == 0 then
        draw(tr("combat.noHurtSources"), { 0.70, 0.70, 0.70 })
    else
        for index = 1, math.min(5, #sources) do
            draw(damageSourceRow(index, sources[index], maxWidth))
        end
    end
end

local function renderDashboard()
    if not ui.overlayVisible or ui.view ~= "combat" or not run then return end
    local floor = currentFloor()
    local screenWidth = Isaac.GetScreenWidth()
    local screenHeight = Isaac.GetScreenHeight()
    local panelWidth = 204
    local panelHeight = math.min(206, screenHeight - 16)
    local frameX = math.max(8, screenWidth - panelWidth - 8)
    local frameY = math.floor((screenHeight - panelHeight) / 2)
    renderPanelFrame(frameX, frameY, panelWidth, panelHeight)
    renderLine(tr("combat.title"), frameX + 8, frameY + 5,
        { 1.00, 0.90, 0.35 }, "title")
    local hint = tr("combat.mapHint")
    renderLine(hint, frameX + panelWidth - textWidth(hint, "small") - 8,
        frameY + 5, { 0.55, 0.80, 1.00 }, "small")
    local x = frameX + 8
    local y = frameY + 22
    local contentWidth = panelWidth - 16
    local contentBottom = frameY + panelHeight - 7
    renderCombatPage(floor, x, y, contentWidth, contentBottom)
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

local function renderMapCellLabel(text, cellX, cellY, color)
    local labelX = cellX + math.floor(
        (MAP_CELL_SIZE - textWidth(text, "cell")) / 2
    )
    renderLine(text, labelX, cellY + 1, color, "cell")
end

local function renderFloorMap()
    if not ui.overlayVisible or ui.view ~= "map" or not run then return end
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
            color = specialRoom and (visited
                    and VISITED_SPECIAL_ROOM_COLOR or specialRoom.color)
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
    local combatHint = tr("map.combatHint")
    renderLine(
        combatHint,
        originX - 10 + mapPanelWidth - textWidth(combatHint, "small") - 8,
        32,
        { 0.55, 0.80, 1.00 },
        "small"
    )

    -- Empty cells are drawn first; one connected perimeter is then drawn around
    -- every real room, so 2x2 and L rooms no longer look like separate 1x1 rooms.
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
    renderDashboard()
    renderFloorMap()
end

function BeginnerLedger:OnPickupRender(pickup)
    if not run or (ui.overlayVisible and ui.view == "map") or pickup.Touched
        or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE
        or pickup.SubType <= 0 then
        return
    end

    local config = itemConfig:GetCollectible(pickup.SubType)
    if not config or not config:HasTags(ItemConfig.TAG_OFFENSIVE) then return end
    local history = persistent.lifetime.itemHistory[tostring(pickup.SubType)]
    local attributed = persistent.lifetime.damageByItem[tostring(pickup.SubType)]
    local prediction = tr("pedestal.noHistory")
    if history then
        if config.Type == ItemType.ITEM_ACTIVE and history.activeSeconds > 0 then
            prediction = trf("pedestal.active",
                history.activeDamage / history.activeSeconds,
                history.activeUses)
        elseif history.observations > 0 then
            prediction = trf("pedestal.passive",
                history.gainSum / history.observations,
                history.observations)
        end
    end

    local position = Isaac.WorldToScreen(pickup.Position)
    local predictionX = math.max(
        6,
        math.min(Isaac.GetScreenWidth() - textWidth(prediction, "small") - 6, position.X - 55)
    )
    renderLine(prediction, predictionX, position.Y - 36, { 0.55, 1.00, 0.55 }, "small")
    if attributed and attributed.damage > 0 then
        local historyText = trf("pedestal.history", attributed.damage)
        local historyX = math.max(
            6,
            math.min(Isaac.GetScreenWidth() - textWidth(historyText, "small") - 6, position.X - 55)
        )
        renderLine(
            historyText,
            historyX,
            position.Y - 24,
            { 0.70, 0.85, 1.00 },
            "small"
        )
    end
end

function BeginnerLedger:OnInputAction(entity, inputHook, buttonAction)
    if not run then return nil end
    if ui.overlayVisible and ui.view == "map" then
        if buttonAction == ButtonAction.ACTION_FULLSCREEN
            or buttonAction == ButtonAction.ACTION_CONSOLE then
            return nil
        end
        if inputHook == InputHook.GET_ACTION_VALUE then
            return 0
        end
        return false
    end

    return nil
end

BeginnerLedger:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, BeginnerLedger.OnGameStarted)
BeginnerLedger:AddCallback(ModCallbacks.MC_POST_GAME_END, BeginnerLedger.OnGameEnd)
BeginnerLedger:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, BeginnerLedger.OnPreGameExit)
BeginnerLedger:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, BeginnerLedger.OnNewRoom)
BeginnerLedger:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, BeginnerLedger.OnNewLevel)
BeginnerLedger:AddCallback(ModCallbacks.MC_POST_UPDATE, BeginnerLedger.OnUpdate)
BeginnerLedger:AddCallback(ModCallbacks.MC_POST_RENDER, BeginnerLedger.OnRender)
BeginnerLedger:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, BeginnerLedger.OnEntityTakeDamage)
BeginnerLedger:AddCallback(ModCallbacks.MC_POST_ENTITY_KILL, BeginnerLedger.OnEntityKill)
BeginnerLedger:AddCallback(ModCallbacks.MC_INPUT_ACTION, BeginnerLedger.OnInputAction)
BeginnerLedger:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, BeginnerLedger.OnPickupCollision)
BeginnerLedger:AddCallback(ModCallbacks.MC_USE_ITEM, BeginnerLedger.OnUseItem)
BeginnerLedger:AddCallback("WHEELCHAIR_PRE_REWIND", BeginnerLedger.OnWheelchairPreRewind)
