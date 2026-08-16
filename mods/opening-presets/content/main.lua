local OpeningPresets = RegisterMod("Opening Presets", 1)
local game = Game()
local json = require("json")

local SAVE_SCHEMA = 3
local MAX_ITEM_COUNT = 99
local QUALITY_ORDER = { 4, 3, 2, 1, 0 }
local ITEM_COLUMNS = 3
local ITEM_ROWS = 5
local ITEMS_PER_BATCH = ITEM_COLUMNS * ITEM_ROWS

local ROW_QUALITY = 1
local ROW_BATCH = 2
local ROW_ITEM_FIRST = 3
local ROW_ITEM_LAST = ROW_ITEM_FIRST + ITEM_ROWS - 1
local ROW_ACTIONS = ROW_ITEM_LAST + 1

local PANEL_FONT = Font()
local SMALL_FONT = Font()
local panelFontLoaded = PANEL_FONT:Load("font/teammeatex/teammeatex12.fnt")
local smallFontLoaded = SMALL_FONT:Load("font/teammeatex/teammeatex10.fnt")

local C = CollectibleType
local CONTROLLER_SUBTRACT_BUTTON = 6 -- Reported as Y by Isaac for the user's layout.
local DEFAULT_KEYBOARD_SHORTCUT = Keyboard.KEY_F7
local DEFAULT_CONTROLLER_SHORTCUT = 14 -- Back/View button; configurable in MCM.
local MCM_CATEGORY = "Opening Presets"
local MCM_SUBCATEGORY = "Controls"

local mcmLoaded, MCM = pcall(require, "scripts.modconfig")
if mcmLoaded then
    local chinese = Options and Options.Language == "zh"
    MCM.SetCategoryInfo(
        MCM_CATEGORY,
        chinese and "配置开局预设面板的键盘和手柄快捷键。"
            or "Configure keyboard and controller shortcuts for the loadout panel."
    )
    MCM.AddTitle(MCM_CATEGORY, MCM_SUBCATEGORY, chinese and "面板快捷键" or "Panel shortcuts")
    MCM.AddKeyboardSetting(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        "KeyboardShortcut",
        DEFAULT_KEYBOARD_SHORTCUT,
        chinese and "键盘快捷键" or "Keyboard shortcut",
        true,
        chinese and "设置打开面板的键盘按键。" or "Choose the keyboard key that opens the panel."
    )
    MCM.AddControllerSetting(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        "ControllerShortcut",
        DEFAULT_CONTROLLER_SHORTCUT,
        chinese and "手柄快捷键" or "Controller shortcut",
        true,
        chinese and "设置打开面板的手柄按键。" or "Choose the controller button that opens the panel."
    )
end

local function configuredShortcut(attribute, defaultValue)
    if mcmLoaded and MCM.Config[MCM_CATEGORY]
        and type(MCM.Config[MCM_CATEGORY][attribute]) == "number" then
        return MCM.Config[MCM_CATEGORY][attribute]
    end
    return defaultValue
end

-- Quality is read from Isaac's ItemConfig. This list only controls the order
-- inside a quality: transformative and broadly powerful items come first;
-- every unlisted item follows alphabetically.
local POWER_ORDER = {
    C.COLLECTIBLE_DEATH_CERTIFICATE,
    C.COLLECTIBLE_R_KEY,
    C.COLLECTIBLE_GLITCHED_CROWN,
    C.COLLECTIBLE_SACRED_HEART,
    C.COLLECTIBLE_GODHEAD,
    C.COLLECTIBLE_C_SECTION,
    C.COLLECTIBLE_BRIMSTONE,
    C.COLLECTIBLE_MOMS_KNIFE,
    C.COLLECTIBLE_TECH_X,
    C.COLLECTIBLE_REVELATION,
    C.COLLECTIBLE_MEGA_MUSH,
    C.COLLECTIBLE_ROCK_BOTTOM,
    C.COLLECTIBLE_HAEMOLACRIA,
    C.COLLECTIBLE_POLYPHEMUS,
    C.COLLECTIBLE_MAGIC_MUSHROOM,
    C.COLLECTIBLE_CRICKETS_HEAD,
    C.COLLECTIBLE_MUTANT_SPIDER,
    C.COLLECTIBLE_20_20,
    C.COLLECTIBLE_EPIC_FETUS,
    C.COLLECTIBLE_DR_FETUS,
    C.COLLECTIBLE_PYROMANIAC,
    C.COLLECTIBLE_HOLY_MANTLE,
    C.COLLECTIBLE_DAMOCLES,
    C.COLLECTIBLE_TWISTED_PAIR,
    C.COLLECTIBLE_INCUBUS,
    C.COLLECTIBLE_CRICKETS_BODY,
    C.COLLECTIBLE_PROPTOSIS,
    C.COLLECTIBLE_STOP_WATCH,
    C.COLLECTIBLE_RED_KEY,
    C.COLLECTIBLE_BIRTHRIGHT,
}

local POWER_RANK = {}
for rank, itemId in ipairs(POWER_ORDER) do POWER_RANK[itemId] = rank end

local settings = {
    schema = SAVE_SCHEMA,
    itemCounts = {},
    activeRun = nil,
}
local runGrantedCounts = {}

local catalogByQuality = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }

local ui = {
    open = false,
    qualityIndex = 1,
    batch = 1,
    focusRow = ROW_ITEM_FIRST,
    column = 1,
    inputMode = "keyboard",
    inputDelay = 0,
    message = nil,
    messageFrames = 0,
}

local function addLegacyItems(counts, items)
    if type(items) ~= "table" then return end
    for _, itemId in ipairs(items) do
        if type(itemId) == "number" and itemId > 0 then
            local key = tostring(math.floor(itemId))
            counts[key] = math.max(1, tonumber(counts[key]) or 0)
        end
    end
end

local function normalizeCountMap(value)
    local result = {}
    if type(value) ~= "table" then return result end
    for itemKey, count in pairs(value) do
        local itemId = tonumber(itemKey)
        local normalizedCount = math.floor(tonumber(count) or 0)
        if itemId and itemId > 0 and normalizedCount > 0 then
            result[tostring(math.floor(itemId))] = math.min(MAX_ITEM_COUNT, normalizedCount)
        end
    end
    return result
end

local function loadSettings()
    settings = { schema = SAVE_SCHEMA, itemCounts = {}, activeRun = nil }
    if not OpeningPresets:HasData() then return end

    local ok, saved = pcall(json.decode, OpeningPresets:LoadData())
    if not ok or type(saved) ~= "table" then return end

    settings.itemCounts = normalizeCountMap(saved.itemCounts)
    -- Migrate the former common/per-character boolean selections into one
    -- universal count map without losing any previously selected item.
    addLegacyItems(settings.itemCounts, saved.commonItems)
    if type(saved.characterItems) == "table" then
        for _, itemIds in pairs(saved.characterItems) do addLegacyItems(settings.itemCounts, itemIds) end
    end
    if type(saved.activeRun) == "table" then
        settings.activeRun = {
            seed = tonumber(saved.activeRun.seed),
            grantedByPlayer = type(saved.activeRun.grantedByPlayer) == "table"
                and saved.activeRun.grantedByPlayer or {},
        }
    end
end

local function saveSettings()
    OpeningPresets:SaveData(json.encode(settings))
end

local function itemCount(itemId)
    return math.floor(tonumber(settings.itemCounts[tostring(itemId)]) or 0)
end

local function setItemCount(itemId, count)
    local key = tostring(itemId)
    local normalized = math.max(0, math.min(MAX_ITEM_COUNT, math.floor(count)))
    settings.itemCounts[key] = normalized > 0 and normalized or nil
    saveSettings()
end

local function selectedItemKinds()
    local count = 0
    for _, amount in pairs(settings.itemCounts) do
        if tonumber(amount) and tonumber(amount) > 0 then count = count + 1 end
    end
    return count
end

local function readableTokenName(token, itemId)
    if type(token) ~= "string" or token == "" then return "Item " .. tostring(itemId) end
    local cleaned = token:gsub("^#", ""):gsub("_NAME$", ""):gsub("_", " "):lower()
    cleaned = cleaned:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest
    end)
    return cleaned ~= "" and cleaned or ("Item " .. tostring(itemId))
end

local function isChineseLanguage()
    if EID and type(EID.getLanguage) == "function" then
        local ok, language = pcall(EID.getLanguage, EID)
        if ok then return language == "zh_cn" end
    end
    return Options and Options.Language == "zh"
end

local function collectibleName(config, itemId)
    -- Use EID's own Chinese data when EID is active in Chinese. EID.font is used
    -- by the renderer below, so these glyphs remain visible.
    if EID and type(EID.descriptions) == "table" and EID.DefaultLanguageCode then
        local languageCode = isChineseLanguage() and "zh_cn" or EID.DefaultLanguageCode
        local language = EID.descriptions[languageCode]
        local entry = language and language.collectibles and language.collectibles[itemId]
        local localizedName = type(entry) == "table" and entry[2] or nil
        if type(localizedName) == "string" and localizedName ~= "" then return localizedName end
    end
    return readableTokenName(config.Name, itemId)
end

local function buildCatalog()
    catalogByQuality = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
    local itemConfig = Isaac.GetItemConfig()
    for itemId = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
        local config = itemConfig:GetCollectible(itemId)
        if config ~= nil and not config.Hidden and config:IsCollectible() then
            local quality = tonumber(config.Quality)
            if catalogByQuality[quality] ~= nil then
                catalogByQuality[quality][#catalogByQuality[quality] + 1] = {
                    id = itemId,
                    name = collectibleName(config, itemId),
                    rank = POWER_RANK[itemId] or 10000,
                }
            end
        end
    end

    for _, quality in ipairs(QUALITY_ORDER) do
        table.sort(catalogByQuality[quality], function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            local aName = string.lower(a.name)
            local bName = string.lower(b.name)
            if aName ~= bName then return aName < bName end
            return a.id < b.id
        end)
    end
end

local function currentQuality()
    return QUALITY_ORDER[ui.qualityIndex]
end

local function currentCatalog()
    return catalogByQuality[currentQuality()] or {}
end

local function batchCount()
    return math.max(1, math.ceil(#currentCatalog() / ITEMS_PER_BATCH))
end

local function normalizeBatch()
    ui.batch = math.max(1, math.min(ui.batch, batchCount()))
end

local function visibleItemIndex(row, column)
    if row < ROW_ITEM_FIRST or row > ROW_ITEM_LAST then return nil end
    return (ui.batch - 1) * ITEMS_PER_BATCH
        + (row - ROW_ITEM_FIRST) * ITEM_COLUMNS
        + column
end

local function focusedItem()
    local index = visibleItemIndex(ui.focusRow, ui.column)
    return index and currentCatalog()[index] or nil
end

local function itemIsAvailable(itemId)
    local config = Isaac.GetItemConfig():GetCollectible(itemId)
    return config ~= nil and not config.Hidden
end

local function initialCollectibleCharge(itemId)
    local config = Isaac.GetItemConfig():GetCollectible(itemId)
    if config ~= nil and config.Type == ItemType.ITEM_ACTIVE then
        return math.max(0, math.floor(tonumber(config.MaxCharges) or 0))
    end
    return 0
end

local function playerGrantedMap(playerIndex)
    local key = tostring(playerIndex)
    runGrantedCounts[key] = normalizeCountMap(runGrantedCounts[key])
    return runGrantedCounts[key]
end

local function grantConfiguredItems()
    local granted = 0
    for playerIndex = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(playerIndex)
        local tracked = playerGrantedMap(playerIndex)
        for itemKey, desiredCount in pairs(settings.itemCounts) do
            local itemId = tonumber(itemKey)
            local alreadyGranted = math.floor(tonumber(tracked[itemKey]) or 0)
            local missing = math.max(0, math.floor(desiredCount) - alreadyGranted)
            if itemId and itemIsAvailable(itemId) then
                for _ = 1, missing do
                    player:AddCollectible(itemId, initialCollectibleCharge(itemId), true)
                    granted = granted + 1
                    tracked[itemKey] = (tonumber(tracked[itemKey]) or 0) + 1
                end
            end
        end
    end
    settings.activeRun.grantedByPlayer = runGrantedCounts
    saveSettings()
    ui.open = false
    ui.message = granted > 0
        and ("Custom loadout applied: " .. tostring(granted) .. " item grants.")
        or "Configured copies were already applied."
    ui.messageFrames = 180
end

local function removeOneCopy(player, itemId)
    local before = player:GetCollectibleNum(itemId, true)
    if before <= 0 then return false end
    local slots = { ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_SECONDARY, ActiveSlot.SLOT_POCKET }
    for _, slot in ipairs(slots) do
        player:RemoveCollectible(itemId, true, slot, true)
        if player:GetCollectibleNum(itemId, true) < before then return true end
    end
    return false
end

local function clearAllAndRemoveGranted()
    local removed = 0
    for playerIndex = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(playerIndex)
        local tracked = playerGrantedMap(playerIndex)
        for itemKey, grantedCount in pairs(tracked) do
            local itemId = tonumber(itemKey)
            if itemId then
                for _ = 1, math.floor(tonumber(grantedCount) or 0) do
                    if removeOneCopy(player, itemId) then removed = removed + 1 end
                end
            end
        end
    end
    settings.itemCounts = {}
    runGrantedCounts = {}
    settings.activeRun.grantedByPlayer = runGrantedCounts
    saveSettings()
    ui.message = "Cleared settings and removed " .. tostring(removed) .. " granted copies."
    ui.messageFrames = 180
end

local function changeQuality(delta)
    ui.qualityIndex = ((ui.qualityIndex - 1 + delta) % #QUALITY_ORDER) + 1
    ui.batch = 1
end

local function changeBatch(delta)
    local count = batchCount()
    ui.batch = ((ui.batch - 1 + delta) % count) + 1
end

local function moveVertical(delta)
    ui.focusRow = ((ui.focusRow - 1 + delta) % ROW_ACTIONS) + 1
end

local function moveHorizontal(delta)
    if ui.focusRow == ROW_QUALITY then
        changeQuality(delta)
    elseif ui.focusRow == ROW_BATCH then
        changeBatch(delta)
    else
        ui.column = ((ui.column - 1 + delta) % ITEM_COLUMNS) + 1
    end
end

local function activateFocused()
    if ui.focusRow == ROW_QUALITY then
        changeQuality(1)
        return
    end
    if ui.focusRow == ROW_BATCH then
        changeBatch(1)
        return
    end
    if ui.focusRow >= ROW_ITEM_FIRST and ui.focusRow <= ROW_ITEM_LAST then
        local item = focusedItem()
        if item then setItemCount(item.id, itemCount(item.id) + 1) end
        return
    end

    if ui.column == 1 then
        clearAllAndRemoveGranted()
    elseif ui.column == 2 then
        if selectedItemKinds() == 0 then
            ui.message = "Custom loadout is empty."
            ui.messageFrames = 120
        else
            grantConfiguredItems()
        end
    else
        ui.open = false
    end
end

local function decrementFocusedItem()
    if ui.focusRow < ROW_ITEM_FIRST or ui.focusRow > ROW_ITEM_LAST then return end
    local item = focusedItem()
    if not item then return end

    local newCount = math.max(0, itemCount(item.id) - 1)
    setItemCount(item.id, newCount)
    local itemKey = tostring(item.id)
    for playerIndex = 0, game:GetNumPlayers() - 1 do
        local tracked = playerGrantedMap(playerIndex)
        local grantedCount = math.floor(tonumber(tracked[itemKey]) or 0)
        if grantedCount > newCount and removeOneCopy(Isaac.GetPlayer(playerIndex), item.id) then
            tracked[itemKey] = grantedCount - 1
            if tracked[itemKey] <= 0 then tracked[itemKey] = nil end
        end
    end
    settings.activeRun.grantedByPlayer = runGrantedCounts
    saveSettings()
end

local function actionTriggered(action)
    local controllers = {}
    for index = 0, game:GetNumPlayers() - 1 do
        controllers[Isaac.GetPlayer(index).ControllerIndex] = true
    end
    if next(controllers) == nil then controllers[0] = true end
    for controllerIndex in pairs(controllers) do
        if Input.IsActionTriggered(action, controllerIndex) then return true end
    end
    return false
end

local function controllerButtonTriggered(button)
    local controllers = {}
    for index = 0, game:GetNumPlayers() - 1 do
        controllers[Isaac.GetPlayer(index).ControllerIndex] = true
    end
    for controllerIndex in pairs(controllers) do
        if Input.IsButtonTriggered(button, controllerIndex) then return true end
    end
    return false
end

local function keyboardMenuInputTriggered()
    local keys = {
        Keyboard.KEY_UP, Keyboard.KEY_DOWN, Keyboard.KEY_LEFT, Keyboard.KEY_RIGHT,
        Keyboard.KEY_W, Keyboard.KEY_S, Keyboard.KEY_A, Keyboard.KEY_D,
        Keyboard.KEY_ENTER, Keyboard.KEY_BACKSPACE, Keyboard.KEY_ESCAPE,
    }
    for _, key in ipairs(keys) do
        if Input.IsButtonTriggered(key, 0) then return true end
    end
    return false
end

local function keyboardOpenShortcutTriggered()
    local shortcut = configuredShortcut("KeyboardShortcut", DEFAULT_KEYBOARD_SHORTCUT)
    if shortcut < 0 then return false end
    return Input.IsButtonTriggered(shortcut, 0)
        and not Input.IsButtonTriggered(shortcut % 32, 0)
end

local function controllerOpenShortcutTriggered()
    local shortcut = configuredShortcut("ControllerShortcut", DEFAULT_CONTROLLER_SHORTCUT)
    if shortcut < 0 then return false end
    return controllerButtonTriggered(shortcut)
end

local function processInput()
    local keyboardActivity = keyboardMenuInputTriggered()
    local up = actionTriggered(ButtonAction.ACTION_MENUUP)
    local down = actionTriggered(ButtonAction.ACTION_MENUDOWN)
    local left = actionTriggered(ButtonAction.ACTION_MENULEFT)
    local right = actionTriggered(ButtonAction.ACTION_MENURIGHT)
    local confirm = actionTriggered(ButtonAction.ACTION_MENUCONFIRM)
    local back = actionTriggered(ButtonAction.ACTION_MENUBACK)
    local keyboardSubtract = Input.IsButtonTriggered(Keyboard.KEY_BACKSPACE, 0)
    local controllerSubtract = controllerButtonTriggered(CONTROLLER_SUBTRACT_BUTTON)
    local anyAction = up or down or left or right or confirm or back
        or keyboardSubtract or controllerSubtract

    if keyboardActivity then
        ui.inputMode = "keyboard"
    elseif anyAction then
        ui.inputMode = "controller"
    end

    if up then moveVertical(-1) end
    if down then moveVertical(1) end
    if left then moveHorizontal(-1) end
    if right then moveHorizontal(1) end
    if confirm then activateFocused() end
    if keyboardSubtract or controllerSubtract then decrementFocusedItem() end
    if ui.open and back then ui.open = false end
end

local function renderText(font, text, x, y, color)
    if isChineseLanguage() and EID and EID.font and EID.font:IsLoaded() then
        -- EID's Chinese atlas is a pixel font. Fractional scaling and a second
        -- shadow pass blur its strokes, so draw one native-size pass at integer
        -- coordinates for crisp glyphs.
        EID.font:DrawStringUTF8(
            text,
            math.floor(x),
            math.floor(y),
            KColor(color[1], color[2], color[3], 1),
            0,
            false
        )
        return
    end

    local loaded = (font == PANEL_FONT and panelFontLoaded)
        or (font == SMALL_FONT and smallFontLoaded)
    local drawX = math.floor(x)
    local drawY = math.floor(y)
    if loaded then
        font:DrawStringUTF8(text, drawX + 1, drawY + 1, KColor(0.02, 0.02, 0.03, 0.98), 0, false)
        font:DrawStringUTF8(text, drawX, drawY, KColor(color[1], color[2], color[3], 1), 0, false)
    else
        Isaac.RenderText(text, drawX + 1, drawY + 1, 0.02, 0.02, 0.03, 0.98)
        Isaac.RenderText(text, drawX, drawY, color[1], color[2], color[3], 1)
    end
end

local function renderedTextWidth(text, font)
    if isChineseLanguage() and EID and EID.font and EID.font:IsLoaded() then
        return EID.font:GetStringWidthUTF8(text)
    end
    if font == PANEL_FONT and panelFontLoaded then return PANEL_FONT:GetStringWidthUTF8(text) end
    if font == SMALL_FONT and smallFontLoaded then return SMALL_FONT:GetStringWidthUTF8(text) end
    return Isaac.GetTextWidth(text)
end

local function centerText(text, panelX, panelWidth, y, color, font)
    local selectedFont = font or SMALL_FONT
    local width = renderedTextWidth(text, selectedFont)
    renderText(selectedFont, text, panelX + math.floor((panelWidth - width) / 2), y, color)
end

local function clippedName(name, maxWidth)
    if renderedTextWidth(name, SMALL_FONT) <= maxWidth then return name end
    -- Lua's byte-based string slicing can split a Chinese UTF-8 glyph. EID's
    -- compact Chinese names normally fit the cell; keep them intact.
    if isChineseLanguage() then return name end
    local suffix = "..."
    local length = #name
    while length > 1 do
        local candidate = name:sub(1, length) .. suffix
        if renderedTextWidth(candidate, SMALL_FONT) <= maxWidth then return candidate end
        length = length - 1
    end
    return suffix
end

local function rowPrefix(row, column)
    return ui.focusRow == row and ui.column == column and "> " or "  "
end

local function interfaceText()
    if isChineseLanguage() then
        return {
            title = "开局预设 - 自定义配置",
            subtitle = "三列 | 品质 4 到 0",
            quality = "品质",
            selected = "已选",
            group = "当前页",
            clear = "清空并移除",
            apply = "应用配置",
            close = "关闭 / 跳过",
            help = ui.inputMode == "controller"
                and "手柄 A: +1 | Y: -1 | B: 关闭"
                or "键盘 Enter: +1 | Backspace: -1 | Esc: 关闭",
        }
    end
    return {
        title = "OPENING PRESETS - CUSTOM LOADOUT",
        subtitle = "3 columns | Quality 4 to 0",
        quality = "Quality",
        selected = "Selected",
        group = "Current page",
        clear = "Clear + remove",
        apply = "Apply loadout",
        close = "Close / skip",
        help = ui.inputMode == "controller"
            and "Controller A: +1 | Y: -1 | B: close"
            or "Keyboard Enter: +1 | Backspace: -1 | Esc: close",
    }
end

local function renderBorder(panelX, panelWidth, topY, bottomY)
    local dashWidth = math.max(1, renderedTextWidth("-", SMALL_FONT))
    local horizontal = string.rep("-", math.max(1, math.floor((panelWidth + 12) / dashWidth)))
    local borderColor = { 0.58, 0.78, 1.0 }
    renderText(SMALL_FONT, horizontal, panelX - 6, topY - 7, borderColor)
    renderText(SMALL_FONT, horizontal, panelX - 6, bottomY, borderColor)
    local y = topY
    while y < bottomY do
        renderText(SMALL_FONT, "|", panelX - 7, y, borderColor)
        renderText(SMALL_FONT, "|", panelX + panelWidth + 4, y, borderColor)
        y = y + 7
    end
end

local function renderPanel()
    normalizeBatch()
    local screenWidth = Isaac.GetScreenWidth()
    -- Use exactly 60% of Isaac's logical HUD canvas and center the complete
    -- frame. This leaves the game's side information panels unobstructed.
    local panelWidth = math.floor(screenWidth * 0.60)
    local columnWidth = panelWidth / ITEM_COLUMNS
    local panelX = math.floor((screenWidth - panelWidth) / 2)
    local topY = 12
    local text = interfaceText()

    local borderBottomY = topY + 228
    renderBorder(panelX, panelWidth, topY, borderBottomY)
    centerText(text.title, panelX, panelWidth, topY, { 1.0, 0.85, 0.3 }, PANEL_FONT)
    centerText(text.subtitle, panelX, panelWidth, topY + 15, { 0.7, 0.8, 0.9 })

    local qualityText = text.quality .. ":  "
    for _, quality in ipairs(QUALITY_ORDER) do
        qualityText = qualityText .. (quality == currentQuality() and "[" .. quality .. "] " or tostring(quality) .. "  ")
    end
    renderText(
        SMALL_FONT,
        rowPrefix(ROW_QUALITY, ui.column) .. qualityText,
        panelX,
        topY + 34,
        ui.focusRow == ROW_QUALITY and { 1.0, 1.0, 0.55 } or { 0.85, 0.9, 1.0 }
    )

    renderText(
        SMALL_FONT,
        rowPrefix(ROW_BATCH, ui.column) .. text.group .. ": < " .. tostring(ui.batch) .. " / " .. tostring(batchCount()) .. " >   " .. text.selected .. ": " .. tostring(selectedItemKinds()),
        panelX,
        topY + 50,
        ui.focusRow == ROW_BATCH and { 1.0, 1.0, 0.55 } or { 0.75, 0.8, 0.9 }
    )

    local catalog = currentCatalog()
    for visibleRow = 0, ITEM_ROWS - 1 do
        for column = 1, ITEM_COLUMNS do
            local row = ROW_ITEM_FIRST + visibleRow
            local itemIndex = (ui.batch - 1) * ITEMS_PER_BATCH + visibleRow * ITEM_COLUMNS + column
            local item = catalog[itemIndex]
            if item then
                local count = itemCount(item.id)
                local enabled = count > 0
                local state = "[x" .. tostring(count) .. "] "
                local active = ui.focusRow == row and ui.column == column
                local itemX = panelX + (column - 1) * columnWidth
                local itemY = topY + 72 + visibleRow * 24
                renderText(
                    SMALL_FONT,
                    rowPrefix(row, column) .. state .. "#" .. tostring(item.id),
                    itemX,
                    itemY,
                    active and { 1.0, 1.0, 0.55 } or (enabled and { 0.55, 1.0, 0.55 } or { 0.9, 0.9, 0.9 })
                )
                renderText(
                    SMALL_FONT,
                    "    " .. clippedName(item.name, columnWidth - 12),
                    itemX,
                    itemY + 12,
                    active and { 1.0, 0.9, 0.45 } or { 0.82, 0.9, 1.0 }
                )
            end
        end
    end

    local actionY = topY + 207
    local actions = {
        { label = text.clear, color = { 1.0, 0.6, 0.5 } },
        { label = text.apply, color = { 0.55, 1.0, 0.55 } },
        { label = text.close, color = { 0.75, 0.8, 0.9 } },
    }
    for column, action in ipairs(actions) do
        local active = ui.focusRow == ROW_ACTIONS and ui.column == column
        renderText(
            SMALL_FONT,
            rowPrefix(ROW_ACTIONS, column) .. action.label,
            panelX + (column - 1) * columnWidth,
            actionY,
            active and { 1.0, 1.0, 0.55 } or action.color
        )
    end
    centerText(text.help, panelX, panelWidth, borderBottomY + 12, { 0.65, 0.7, 0.78 })
end

function OpeningPresets:OnGameStarted(isContinued)
    loadSettings()
    buildCatalog()
    local seed = game:GetSeeds():GetStartSeed()
    if isContinued and settings.activeRun and settings.activeRun.seed == seed then
        runGrantedCounts = settings.activeRun.grantedByPlayer or {}
    else
        runGrantedCounts = {}
    end
    settings.activeRun = { seed = seed, grantedByPlayer = runGrantedCounts }
    saveSettings()
    ui.open = not isContinued
    ui.qualityIndex = 1
    ui.batch = 1
    ui.focusRow = ROW_ITEM_FIRST
    ui.column = 1
    ui.inputDelay = ui.open and 30 or 0
    ui.message = nil
    ui.messageFrames = 0
    if ui.open then
        Isaac.DebugString("[Opening Presets] New run detected; opening centered custom panel.")
    else
        Isaac.DebugString("[Opening Presets] Continued run detected; panel available with F7.")
    end
end

function OpeningPresets:OnPreGameExit()
    if settings.activeRun then settings.activeRun.grantedByPlayer = runGrantedCounts end
    saveSettings()
    ui.open = false
end

function OpeningPresets:OnGameEnd()
    settings.activeRun = nil
    runGrantedCounts = {}
    saveSettings()
end

function OpeningPresets:OnRender()
    if game:GetNumPlayers() == 0 then return end
    local keyboardOpen = false
    local controllerOpen = false
    if not ui.open and not (mcmLoaded and MCM.IsVisible) then
        keyboardOpen = keyboardOpenShortcutTriggered()
        controllerOpen = controllerOpenShortcutTriggered()
    end
    if keyboardOpen or controllerOpen then
        if #catalogByQuality[4] == 0 then buildCatalog() end
        ui.open = true
        ui.inputMode = controllerOpen and "controller" or "keyboard"
        ui.inputDelay = 8
        ui.message = nil
        ui.messageFrames = 0
    end

    if ui.open then
        if ui.inputDelay > 0 then
            ui.inputDelay = ui.inputDelay - 1
        else
            processInput()
        end
        if ui.open then renderPanel() end
    elseif ui.messageFrames > 0 and ui.message then
        local screenWidth = Isaac.GetScreenWidth()
        local messageWidth = math.floor(screenWidth * 0.60)
        centerText(ui.message, math.floor((screenWidth - messageWidth) / 2), messageWidth, 36, { 0.65, 1.0, 0.65 }, PANEL_FONT)
        ui.messageFrames = ui.messageFrames - 1
    end
end

OpeningPresets:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, OpeningPresets.OnGameStarted)
OpeningPresets:AddCallback(ModCallbacks.MC_POST_GAME_END, OpeningPresets.OnGameEnd)
OpeningPresets:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, OpeningPresets.OnPreGameExit)
OpeningPresets:AddPriorityCallback(ModCallbacks.MC_POST_RENDER, CallbackPriority.LATE, OpeningPresets.OnRender)
