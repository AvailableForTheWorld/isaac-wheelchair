local EdenMode = RegisterMod("Eden Mode", 1)
local game = Game()
local json = require("json")

local SAVE_SCHEMA = 1
local RNG_SHIFT_INDEX = 35
local ACTIVE_ITEM_CHANCE = 0.40
local MAX_ITEM_SEARCH_ATTEMPTS = 80
local MAX_ACTIVE_ITEM_SEARCH_ATTEMPTS = 240
local DEFAULT_RANDOMIZE_STARTING_ACTIVE = true
local MCM_CATEGORY = "Eden Mode"
local MCM_SUBCATEGORY = "Starting items"

local C = CollectibleType
local P = PlayerType

-- Fixed-health characters rely on mechanics that standard red/soul health
-- mutations would break. Unknown modded player types are preserved as well.
local FIXED_HEALTH_PLAYER_TYPES = {
    [P.PLAYER_THELOST] = true,
    [P.PLAYER_KEEPER] = true,
    [P.PLAYER_THEFORGOTTEN] = true,
    [P.PLAYER_THESOUL] = true,
    [P.PLAYER_THELOST_B] = true,
    [P.PLAYER_KEEPER_B] = true,
    [P.PLAYER_THEFORGOTTEN_B] = true,
    [P.PLAYER_JACOB2_B] = true,
    [P.PLAYER_THESOUL_B] = true,
}
local SOUL_ONLY_HEALTH_PLAYER_TYPES = {
    [P.PLAYER_BLUEBABY] = true,
    [P.PLAYER_BLACKJUDAS] = true,
    [P.PLAYER_JUDAS_B] = true,
    [P.PLAYER_BLUEBABY_B] = true,
    [P.PLAYER_BETHANY_B] = true,
}
local RED_ONLY_HEALTH_PLAYER_TYPES = {
    [P.PLAYER_BETHANY] = true,
}

local mcmLoaded, MCM = pcall(require, "scripts.modconfig")
if mcmLoaded then
    local chinese = Options and Options.Language == "zh"
    MCM.SetCategoryInfo(
        MCM_CATEGORY,
        chinese and "配置伊甸模式如何处理角色的初始主动道具。初始血量会自动随机。"
            or "Configure starting active items. Starting health is randomized automatically."
    )
    MCM.AddTitle(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        chinese and "选择初始主动" or "Choose starting active"
    )
    MCM.AddText(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        chinese and "选中下方选项，然后按 左 / 右 切换。"
            or "Select the option below, then press Left / Right."
    )
    MCM.AddBooleanSetting(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        -- V2 uses a new MCM key so installations that stored the former
        -- Preserve default migrate to the new Replace default automatically.
        "RandomizeStartingActiveV2",
        DEFAULT_RANDOMIZE_STARTING_ACTIVE,
        chinese and "初始主动" or "Starting active",
        chinese and { [true] = "随机主动（默认）", [false] = "原版主动" }
            or { [true] = "Random active (default)", [false] = "Original active" },
        chinese and "选中后按左/右切换。随机主动会替换主主动栏；原版主动会保留角色自带道具。两种模式都会另外获得 0-3 个被动道具。仅对新配置生效，口袋主动始终保留。"
            or "Press Left/Right to switch. Random active replaces the primary slot; Original active keeps the character item. Both modes also grant 0-3 passive items. New profiles only; pocket actives are always preserved."
    )
    MCM.AddSpace(MCM_CATEGORY, MCM_SUBCATEGORY)
    MCM.AddText(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        chinese and "随机主动（默认）：替换主主动栏。"
            or "Random active (default): replace primary."
    )
    MCM.AddText(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        chinese and "原版主动：保留角色自带主动。"
            or "Original active: keep the character item."
    )
    MCM.AddText(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        chinese and "两种模式：另外随机获得 0-3 个被动道具。"
            or "Both modes: also roll 0-3 passive items."
    )
    MCM.AddText(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        chinese and "血量：随机红心 / 魂心 / 黑心 / 混合。"
            or "Health: random red/soul/black/mixed start."
    )
    MCM.AddText(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        chinese and "游魂、店主和遗骸保留其特殊血量机制。"
            or "Lost, Keeper, and Forgotten keep fixed health rules."
    )
    MCM.AddText(
        MCM_CATEGORY,
        MCM_SUBCATEGORY,
        chinese and "切换后，下一个新游戏 / 新配置生效。"
            or "Changes apply to the next new run/profile."
    )
end

local function randomizeStartingActiveEnabled()
    if mcmLoaded and type(MCM.Config) == "table"
        and type(MCM.Config[MCM_CATEGORY]) == "table"
        and type(MCM.Config[MCM_CATEGORY].RandomizeStartingActiveV2) == "boolean" then
        return MCM.Config[MCM_CATEGORY].RandomizeStartingActiveV2
    end
    return DEFAULT_RANDOMIZE_STARTING_ACTIVE
end

-- Regular, broadly useful pools keep the loadouts varied without making
-- Angel/Devil/Secret-room power items disproportionately common.
local ITEM_POOLS = {
    { id = ItemPoolType.POOL_TREASURE, weight = 65 },
    { id = ItemPoolType.POOL_BOSS, weight = 20 },
    { id = ItemPoolType.POOL_SHOP, weight = 10 },
    { id = ItemPoolType.POOL_LIBRARY, weight = 5 },
}

local ITEM_POOL_TOTAL_WEIGHT = 0
for _, entry in ipairs(ITEM_POOLS) do
    ITEM_POOL_TOTAL_WEIGHT = ITEM_POOL_TOTAL_WEIGHT + entry.weight
end

-- These ranges are deliberately relative to the character's fully evaluated
-- stats. Azazel remains Azazel, Keeper remains Keeper, and item synergies keep
-- working; Eden Mode only nudges the resulting values within bounded limits.
local STAT_RANGES = {
    damage = { 0.80, 1.20 },
    fireRate = { 0.85, 1.15 },
    shotSpeed = { 0.90, 1.10 },
    range = { 0.85, 1.15 },
    speed = { 0.90, 1.10 },
    luck = { -1.00, 1.00 },
}
local STAT_ORDER = { "damage", "fireRate", "shotSpeed", "range", "speed", "luck" }
local STAT_WEIGHTS = {
    damage = 0.28,
    fireRate = 0.25,
    shotSpeed = 0.10,
    range = 0.10,
    speed = 0.17,
    luck = 0.10,
}

local STAT_CACHE_FLAGS = CacheFlag.CACHE_DAMAGE
    | CacheFlag.CACHE_FIREDELAY
    | CacheFlag.CACHE_SHOTSPEED
    | CacheFlag.CACHE_RANGE
    | CacheFlag.CACHE_SPEED
    | CacheFlag.CACHE_LUCK

local state = {
    schema = SAVE_SCHEMA,
    runSeed = nil,
    profiles = {},
    taintedLazarusSlots = {},
}
local runReady = false
local runtimeInitialized = {}

local function freshState(runSeed)
    return {
        schema = SAVE_SCHEMA,
        runSeed = runSeed,
        profiles = {},
        taintedLazarusSlots = {},
    }
end

local function saveState()
    EdenMode:SaveData(json.encode(state))
end

local function loadState()
    state = freshState(nil)
    if not EdenMode:HasData() then return end

    local ok, saved = pcall(json.decode, EdenMode:LoadData())
    if not ok or type(saved) ~= "table" or saved.schema ~= SAVE_SCHEMA then return end
    if type(saved.profiles) ~= "table" then saved.profiles = {} end
    if type(saved.taintedLazarusSlots) ~= "table" then saved.taintedLazarusSlots = {} end
    state = saved
end

local function round(value, places)
    local scale = 10 ^ (places or 0)
    return math.floor(value * scale + 0.5) / scale
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function randomBetween(rng, minimum, maximum)
    return minimum + (maximum - minimum) * rng:RandomFloat()
end

local function preservedHealthProfile()
    return {
        kind = "preserved",
        randomized = false,
        maxRedHearts = 0,
        redHearts = 0,
        soulHearts = 0,
        blackHearts = 0,
    }
end

local function redHealthProfile(rng)
    local maxFullHearts = 1 + rng:RandomInt(4)
    local filledFullHearts = 1 + rng:RandomInt(maxFullHearts)
    return {
        kind = "red",
        randomized = true,
        maxRedHearts = maxFullHearts * 2,
        redHearts = filledFullHearts * 2,
        soulHearts = 0,
        blackHearts = 0,
    }
end


local function spiritHealthProfile(rng, kind)
    local fullHearts = 1 + rng:RandomInt(4)
    return {
        kind = kind,
        randomized = true,
        maxRedHearts = 0,
        redHearts = 0,
        soulHearts = kind == "soul" and fullHearts * 2 or 0,
        blackHearts = kind == "black" and fullHearts * 2 or 0,
    }
end

local function mixedHealthProfile(rng)
    local maxRedFullHearts = 1 + rng:RandomInt(3)
    local filledRedFullHearts = 1 + rng:RandomInt(maxRedFullHearts)
    local spiritFullHearts = 1 + rng:RandomInt(3)
    local blackFullHearts = rng:RandomInt(spiritFullHearts + 1)
    return {
        kind = "mixed",
        randomized = true,
        maxRedHearts = maxRedFullHearts * 2,
        redHearts = filledRedFullHearts * 2,
        soulHearts = (spiritFullHearts - blackFullHearts) * 2,
        blackHearts = blackFullHearts * 2,
    }
end


local function mixedSpiritHealthProfile(rng)
    local totalFullHearts = 2 + rng:RandomInt(3)
    local blackFullHearts = 1 + rng:RandomInt(totalFullHearts - 1)
    return {
        kind = "soul-black",
        randomized = true,
        maxRedHearts = 0,
        redHearts = 0,
        soulHearts = (totalFullHearts - blackFullHearts) * 2,
        blackHearts = blackFullHearts * 2,
    }
end

local function createHealthProfile(rng, playerType)
    if playerType < P.PLAYER_ISAAC or playerType >= P.NUM_PLAYER_TYPES
        or FIXED_HEALTH_PLAYER_TYPES[playerType] then
        return preservedHealthProfile()
    end
    if RED_ONLY_HEALTH_PLAYER_TYPES[playerType] then
        return redHealthProfile(rng)
    end
    if SOUL_ONLY_HEALTH_PLAYER_TYPES[playerType] then
        local roll = rng:RandomInt(3)
        if roll == 0 then return spiritHealthProfile(rng, "soul") end
        if roll == 1 then return spiritHealthProfile(rng, "black") end
        return mixedSpiritHealthProfile(rng)
    end

    local roll = rng:RandomInt(4)
    if roll == 0 then return redHealthProfile(rng) end
    if roll == 1 then return spiritHealthProfile(rng, "soul") end
    if roll == 2 then return spiritHealthProfile(rng, "black") end
    return mixedHealthProfile(rng)
end

local function statPowerScore(stats)
    local score = 0
    for _, stat in ipairs(STAT_ORDER) do
        local limits = STAT_RANGES[stat]
        local center = (limits[1] + limits[2]) / 2
        local halfRange = (limits[2] - limits[1]) / 2
        local statValue = tonumber(stats[stat]) or center
        local normalized = halfRange > 0 and (statValue - center) / halfRange or 0
        score = score + clamp(normalized, -1, 1) * STAT_WEIGHTS[stat]
    end
    return round(clamp(score, -1, 1), 3)
end

local function healthPowerScore(health)
    if type(health) ~= "table" or not health.randomized then return 0 end
    local maxRedHearts = tonumber(health.maxRedHearts) or 0
    local redHearts = tonumber(health.redHearts) or 0
    local soulHearts = tonumber(health.soulHearts) or 0
    local blackHearts = tonumber(health.blackHearts) or 0
    local filledHealth = redHearts + soulHearts + blackHearts
    local emptyRedCapacity = math.max(0, maxRedHearts - redHearts)
    local effectiveHealth = filledHealth + emptyRedCapacity * 0.25
    return round(clamp((effectiveHealth - 6) / 4, -1, 1), 3)
end

local function combinedPowerScore(statScore, healthScore)
    return round(clamp(statScore * 0.85 + healthScore * 0.15, -1, 1), 3)
end

local function playerIndex(player)
    local playerHash = GetPtrHash(player)
    for index = 0, game:GetNumPlayers() - 1 do
        local candidate = Isaac.GetPlayer(index)
        if candidate and GetPtrHash(candidate) == playerHash then return index end
    end
    return nil
end

local function profileIdentity(player, index)
    local playerType = player:GetPlayerType()
    local slotKey = tostring(index)
    local trackedForm = state.taintedLazarusSlots[slotKey]
    -- Tainted Lazarus has two genuinely separate inventories. The inactive
    -- form is unavailable to the vanilla Lua API, so initialize each form the
    -- first time it becomes active. Other form changes keep one profile.
    if trackedForm then
        if playerType == P.PLAYER_LAZARUS_B then
            trackedForm = "alive"
            state.taintedLazarusSlots[slotKey] = trackedForm
        elseif playerType == P.PLAYER_LAZARUS2_B then
            trackedForm = "dead"
            state.taintedLazarusSlots[slotKey] = trackedForm
        end
        if trackedForm == "dead" then
            return slotKey .. ":tainted-lazarus-dead", 211
        end
        return slotKey .. ":tainted-lazarus-alive", 101
    end
    return slotKey, 0
end

local function trackStartingTaintedLazarus(player, index)
    local slotKey = tostring(index)
    if state.taintedLazarusSlots[slotKey] or state.profiles[slotKey] then return end
    local playerType = player:GetPlayerType()
    if playerType == P.PLAYER_LAZARUS_B then
        state.taintedLazarusSlots[slotKey] = "alive"
    elseif playerType == P.PLAYER_LAZARUS2_B then
        state.taintedLazarusSlots[slotKey] = "dead"
    end
end

local function profileSeed(index, formSalt)
    local seedMixer = RNG()
    seedMixer:SetSeed(state.runSeed, RNG_SHIFT_INDEX)
    local mixedSeed = state.runSeed
    local iterations = (index + 1) * 17 + formSalt
    for _ = 1, iterations do mixedSeed = seedMixer:Next() end
    if mixedSeed == 0 then return 1 end
    return mixedSeed
end

local function itemProfileSeed(index, formSalt)
    local seedMixer = RNG()
    seedMixer:SetSeed(profileSeed(index, formSalt), RNG_SHIFT_INDEX)
    local mixedSeed = seedMixer:GetSeed()
    for _ = 1, 53 do mixedSeed = seedMixer:Next() end
    if mixedSeed == 0 then return 1 end
    return mixedSeed
end

local function createProfile(player, index, formSalt)
    local rng = RNG()
    rng:SetSeed(profileSeed(index, formSalt), RNG_SHIFT_INDEX)

    local stats = {}
    for _, stat in ipairs(STAT_ORDER) do
        local limits = STAT_RANGES[stat]
        stats[stat] = round(randomBetween(rng, limits[1], limits[2]), 3)
    end

    local itemSeed = itemProfileSeed(index, formSalt)
    local health = createHealthProfile(rng, player:GetPlayerType())
    local statScore = statPowerScore(stats)
    local healthScore = healthPowerScore(health)

    return {
        stats = stats,
        statScore = statScore,
        health = health,
        healthScore = healthScore,
        powerScore = combinedPowerScore(statScore, healthScore),
        healthApplied = false,
        itemSeed = itemSeed,
        passiveItemCount = itemSeed % 4,
        randomizeStartingActive = randomizeStartingActiveEnabled(),
        items = {},
        granted = false,
    }
end

local function weightedItemPool(rng)
    local roll = rng:RandomInt(ITEM_POOL_TOTAL_WEIGHT)
    local accumulated = 0
    for _, entry in ipairs(ITEM_POOLS) do
        accumulated = accumulated + entry.weight
        if roll < accumulated then return entry.id end
    end
    return ItemPoolType.POOL_TREASURE
end

local function collectibleConfig(itemId, wantActive, chosen)
    if not itemId or itemId <= C.COLLECTIBLE_NULL or chosen[itemId] then return nil end
    local config = Isaac.GetItemConfig():GetCollectible(itemId)
    if not config or config.Hidden or not config:IsAvailable() then return nil end

    if wantActive and config.Type == ItemType.ITEM_ACTIVE then return config end
    if not wantActive
        and (config.Type == ItemType.ITEM_PASSIVE or config.Type == ItemType.ITEM_FAMILIAR) then
        return config
    end
    return nil
end

local function findCollectible(rng, wantActive, chosen, desiredQuality)
    local itemPool = game:GetItemPool()
    local bestItemId = nil
    local bestPoolType = nil
    local bestDistance = math.huge
    local searchAttempts = wantActive
        and MAX_ACTIVE_ITEM_SEARCH_ATTEMPTS or MAX_ITEM_SEARCH_ATTEMPTS
    for _ = 1, searchAttempts do
        local poolType = weightedItemPool(rng)
        local itemSeed = rng:Next()
        if itemSeed == 0 then itemSeed = 1 end
        local itemId = itemPool:GetCollectible(
            poolType,
            false,
            itemSeed,
            C.COLLECTIBLE_NULL
        )
        local config = collectibleConfig(itemId, wantActive, chosen)
        if config then
            local distance = math.abs(config.Quality - desiredQuality)
            if distance < bestDistance then
                bestItemId = itemId
                bestPoolType = poolType
                bestDistance = distance
            end
            if distance == 0 then return itemId, poolType end
        end
    end
    return bestItemId, bestPoolType
end

local function desiredItemQuality(rng, statScore)
    -- A -1 score centers around quality 4; a +1 score centers around quality 1.
    -- Per-item jitter keeps profiles from becoming a rigid all-one-quality set.
    local inverseCenter = 2.5 - statScore * 1.5
    local jitter = randomBetween(rng, -0.75, 0.75)
    return clamp(math.floor(inverseCenter + jitter + 0.5), 0, 4)
end

local function availableActiveSlot(player)
    if player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == C.COLLECTIBLE_NULL then
        return ActiveSlot.SLOT_PRIMARY
    end
    if player:HasCollectible(C.COLLECTIBLE_SCHOOLBAG, true)
        and player:GetActiveItem(ActiveSlot.SLOT_SECONDARY) == C.COLLECTIBLE_NULL then
        return ActiveSlot.SLOT_SECONDARY
    end
    return nil
end

local function initialActiveCharge(itemId)
    local config = Isaac.GetItemConfig():GetCollectible(itemId)
    if config and config.Type == ItemType.ITEM_ACTIVE then
        if config.InitCharge and config.InitCharge >= 0 then return config.InitCharge end
        return math.max(0, config.MaxCharges or 0)
    end
    return 0
end

local function applyHealthProfile(player, profile)
    local health = profile.health
    if type(health) ~= "table" or not health.randomized then
        profile.healthApplied = true
        return
    end

    local maxRedHearts = clamp(math.floor(tonumber(health.maxRedHearts) or 0), 0, 8)
    local redHearts = clamp(math.floor(tonumber(health.redHearts) or 0), 0, maxRedHearts)
    local soulHearts = clamp(math.floor(tonumber(health.soulHearts) or 0), 0, 8)
    local blackHearts = clamp(
        math.floor(tonumber(health.blackHearts) or 0),
        0,
        8 - soulHearts
    )

    -- GetSoulHearts includes black hearts. Clear the spirit-health row first,
    -- then rebuild red containers and add soul/black hearts separately.
    local currentSoulHearts = player:GetSoulHearts()
    if currentSoulHearts > 0 then player:AddSoulHearts(-currentSoulHearts) end
    local currentMaxHearts = player:GetMaxHearts()
    if currentMaxHearts ~= maxRedHearts then
        player:AddMaxHearts(maxRedHearts - currentMaxHearts, true)
    end
    local currentRedHearts = player:GetHearts()
    if currentRedHearts ~= redHearts then
        player:AddHearts(redHearts - currentRedHearts)
    end
    if soulHearts > 0 then player:AddSoulHearts(soulHearts) end
    if blackHearts > 0 then player:AddBlackHearts(blackHearts) end

    profile.healthApplied = true
end

local function grantProfileItems(player, profile)
    local rng = RNG()
    rng:SetSeed(profile.itemSeed, RNG_SHIFT_INDEX)
    local chosen = {}
    local replaceStartingActive = profile.randomizeStartingActive == true
    local originalPrimaryActive = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
    if replaceStartingActive and originalPrimaryActive ~= C.COLLECTIBLE_NULL then
        -- Do not let "random" select the exact active it is supposed to replace.
        chosen[originalPrimaryActive] = true
    end

    profile.items = {}
    profile.replacedActiveId = nil

    -- Active and passive rolls are independent. Replace mode always attempts
    -- one active; Preserve mode keeps its optional empty-slot active roll.
    local activeSlot = replaceStartingActive
        and ActiveSlot.SLOT_PRIMARY or availableActiveSlot(player)
    local grantBonusActive = replaceStartingActive
        or (activeSlot ~= nil and rng:RandomFloat() < ACTIVE_ITEM_CHANCE)

    if grantBonusActive then
        local targetQuality = desiredItemQuality(rng, profile.powerScore)
        local itemId, poolType = findCollectible(
            rng,
            true,
            chosen,
            targetQuality
        )

        if itemId and replaceStartingActive then
            local currentPrimaryActive = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
            if currentPrimaryActive ~= C.COLLECTIBLE_NULL then
                player:RemoveCollectible(
                    currentPrimaryActive,
                    true,
                    ActiveSlot.SLOT_PRIMARY,
                    true
                )
            end
            if player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == C.COLLECTIBLE_NULL then
                activeSlot = ActiveSlot.SLOT_PRIMARY
                if currentPrimaryActive ~= C.COLLECTIBLE_NULL then
                    profile.replacedActiveId = currentPrimaryActive
                end
            else
                -- A protected or externally supplied active could not be
                -- removed. Preserve it and omit the bonus active; never turn
                -- this failure into a fourth passive item.
                itemId = nil
            end
        end

        if itemId and activeSlot ~= nil then
            local config = Isaac.GetItemConfig():GetCollectible(itemId)
            chosen[itemId] = true
            game:GetItemPool():RemoveCollectible(itemId)
            player:AddCollectible(itemId, initialActiveCharge(itemId), true, activeSlot)
            table.insert(profile.items, {
                id = itemId,
                pool = poolType,
                active = true,
                quality = config.Quality,
                targetQuality = targetQuality,
            })
        end
    end

    for _ = 1, profile.passiveItemCount do
        local targetQuality = desiredItemQuality(rng, profile.powerScore)
        local itemId, poolType = findCollectible(rng, false, chosen, targetQuality)
        if not itemId then break end

        local config = Isaac.GetItemConfig():GetCollectible(itemId)
        chosen[itemId] = true
        game:GetItemPool():RemoveCollectible(itemId)
        player:AddCollectible(itemId, 0, true)
        table.insert(profile.items, {
            id = itemId,
            pool = poolType,
            active = false,
            quality = config.Quality,
            targetQuality = targetQuality,
        })
    end

    profile.granted = true
end

local function profileForPlayer(player)
    if not runReady or not state.runSeed then return nil end
    local index = playerIndex(player)
    if index == nil then return nil end
    local key = profileIdentity(player, index)
    return state.profiles[key]
end

local function describeProfile(index, key, profile)
    local stats = profile.stats
    local health = profile.health or preservedHealthProfile()
    local itemDescriptions = {}
    for _, item in ipairs(profile.items) do
        table.insert(
            itemDescriptions,
            string.format("%d(Q%d%s)", item.id, item.quality or -1, item.active and ",A" or "")
        )
    end
    Isaac.DebugString(string.format(
        "[Eden Mode] Player %d (%s): active mode %s, replaced #%s; passives %d; health %s R%.1f/%.1f S%.1f B%.1f; power %+.3f (stats %+.3f, health %+.3f); damage x%.3f, tears x%.3f, shot speed x%.3f, range x%.3f, speed x%.3f, luck %+.3f; items [%s]",
        index,
        key,
        profile.randomizeStartingActive and "replace" or "preserve",
        tostring(profile.replacedActiveId or 0),
        profile.passiveItemCount,
        tostring(health.kind or "preserved"),
        (tonumber(health.redHearts) or 0) / 2,
        (tonumber(health.maxRedHearts) or 0) / 2,
        (tonumber(health.soulHearts) or 0) / 2,
        (tonumber(health.blackHearts) or 0) / 2,
        profile.powerScore,
        profile.statScore,
        profile.healthScore,
        stats.damage,
        stats.fireRate,
        stats.shotSpeed,
        stats.range,
        stats.speed,
        stats.luck,
        table.concat(itemDescriptions, ", ")
    ))
end

local function initializePlayer(player, index)
    trackStartingTaintedLazarus(player, index)
    local key, formSalt = profileIdentity(player, index)
    local runtimeKey = tostring(GetPtrHash(player)) .. ":" .. key
    if runtimeInitialized[runtimeKey] then return end

    local profile = state.profiles[key]
    if type(profile) ~= "table" or type(profile.stats) ~= "table" then
        profile = createProfile(player, index, formSalt)
        state.profiles[key] = profile
    end
    if type(profile.health) ~= "table" then
        -- Profiles saved by versions before randomized health have already
        -- granted their start; never rewrite health in the middle of that run.
        profile.health = preservedHealthProfile()
        profile.healthApplied = true
    else
        profile.healthApplied = profile.healthApplied == true
    end
    profile.randomizeStartingActive = profile.randomizeStartingActive == true
    profile.statScore = statPowerScore(profile.stats)
    profile.healthScore = healthPowerScore(profile.health)
    profile.powerScore = combinedPowerScore(profile.statScore, profile.healthScore)
    profile.itemSeed = math.floor(tonumber(profile.itemSeed) or itemProfileSeed(index, formSalt))
    if profile.itemSeed <= 0 then profile.itemSeed = itemProfileSeed(index, formSalt) end
    local savedPassiveItemCount = tonumber(profile.passiveItemCount)
    profile.passiveItemCount = clamp(
        math.floor(savedPassiveItemCount or (profile.itemSeed % 4)),
        0,
        3
    )
    profile.itemCount = nil

    runtimeInitialized[runtimeKey] = true
    if not profile.healthApplied then
        applyHealthProfile(player, profile)
    end
    if not profile.granted then
        grantProfileItems(player, profile)
        describeProfile(index, key, profile)
    end

    player:AddCacheFlags(STAT_CACHE_FLAGS)
    player:EvaluateItems()
    saveState()
end

function EdenMode:OnGameStarted(isContinued)
    loadState()
    local startSeed = game:GetSeeds():GetStartSeed()
    if not isContinued or state.runSeed ~= startSeed then
        state = freshState(startSeed)
    end
    runtimeInitialized = {}
    runReady = true
    saveState()
end

function EdenMode:OnPostUpdate()
    if not runReady or game:GetFrameCount() < 1 then return end
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if player then initializePlayer(player, index) end
    end
end

function EdenMode:OnEvaluateCache(player, flag)
    local profile = profileForPlayer(player)
    if not profile or type(profile.stats) ~= "table" then return end
    local stats = profile.stats

    if flag == CacheFlag.CACHE_DAMAGE then
        player.Damage = player.Damage * (stats.damage or 1)
    elseif flag == CacheFlag.CACHE_FIREDELAY then
        local firingInterval = player.MaxFireDelay + 1
        if firingInterval > 0 then
            player.MaxFireDelay = firingInterval / (stats.fireRate or 1) - 1
        end
    elseif flag == CacheFlag.CACHE_SHOTSPEED then
        player.ShotSpeed = player.ShotSpeed * (stats.shotSpeed or 1)
    elseif flag == CacheFlag.CACHE_RANGE then
        player.TearRange = player.TearRange * (stats.range or 1)
    elseif flag == CacheFlag.CACHE_SPEED then
        player.MoveSpeed = player.MoveSpeed * (stats.speed or 1)
    elseif flag == CacheFlag.CACHE_LUCK then
        player.Luck = player.Luck + (stats.luck or 0)
    end
end

function EdenMode:OnPreGameExit()
    if runReady then saveState() end
    runReady = false
end

function EdenMode:OnGameEnd()
    state = freshState(nil)
    runtimeInitialized = {}
    runReady = false
    saveState()
end

EdenMode:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, EdenMode.OnGameStarted)
EdenMode:AddCallback(ModCallbacks.MC_POST_UPDATE, EdenMode.OnPostUpdate)
EdenMode:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, EdenMode.OnEvaluateCache)
EdenMode:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, EdenMode.OnPreGameExit)
EdenMode:AddCallback(ModCallbacks.MC_POST_GAME_END, EdenMode.OnGameEnd)
