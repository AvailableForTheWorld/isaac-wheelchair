local mod = RegisterMod("假如我直接赢", 1)
local game = Game()
local pickupType = EntityType.ENTITY_PICKUP
local collectibleVariant = PickupVariant.PICKUP_COLLECTIBLE
local nullCollectible = CollectibleType.COLLECTIBLE_NULL
local collectibles = CollectibleType
local maxPoolRolls = 24
local samplingPool = false
local rules

local transformationTags = {
    ItemConfig.TAG_SYRINGE, ItemConfig.TAG_MOM, ItemConfig.TAG_GUPPY, ItemConfig.TAG_FLY,
    ItemConfig.TAG_BOB, ItemConfig.TAG_MUSHROOM, ItemConfig.TAG_BABY, ItemConfig.TAG_ANGEL,
    ItemConfig.TAG_DEVIL, ItemConfig.TAG_POOP, ItemConfig.TAG_BOOK, ItemConfig.TAG_SPIDER,
}

-- Super Bum, Stompy and Necromancer use specific items instead of transformation tags.
local fixedSetPieces = {
    [CollectibleType.COLLECTIBLE_BUM_FRIEND] = true,
    [CollectibleType.COLLECTIBLE_DARK_BUM] = true,
    [CollectibleType.COLLECTIBLE_KEY_BUM] = true,
    [CollectibleType.COLLECTIBLE_LEO] = true,
    [CollectibleType.COLLECTIBLE_NECRONOMICON] = true,
    [CollectibleType.COLLECTIBLE_MISSING_PAGE_2] = true,
}

local function isHighQuality(item)
    return item.Quality == 3 or item.Quality == 4
end

local function isOrdinaryCollectible(item)
    return item and not item.Hidden and not item:HasTags(ItemConfig.TAG_QUEST)
end

local function buildRules()
    local available, locked, restricted = {}, {}, {}
    local setMembers = {}
    for _, tag in ipairs(transformationTags) do
        setMembers[tag] = {}
    end

    local config = Isaac.GetItemConfig()
    for itemId = 1, config:GetCollectibles().Size - 1 do
        local item = config:GetCollectible(itemId)
        if isOrdinaryCollectible(item) then
            local isAvailable = item:IsAvailable()
            local highQuality = isHighQuality(item)
            local isLocked = not isAvailable and item.AchievementID >= 0
            if highQuality then
                local pool = isAvailable and available or (isLocked and locked or restricted)
                pool[#pool + 1] = itemId
            end

            for _, tag in ipairs(transformationTags) do
                if item:HasTags(tag) then
                    local members = setMembers[tag]
                    members[#members + 1] = {
                        id = itemId,
                        quality = item.Quality,
                        available = isAvailable,
                        lockedHighQuality = isLocked and highQuality,
                    }
                end
            end
        end
    end

    local highQualityCount = #available + #locked
    local supplementLocked = #available * 3 < highQualityCount * 2
    local setPieces = {}
    for _, members in pairs(setMembers) do
        local qualities = {}
        for _, member in ipairs(members) do
            if member.available or (supplementLocked and member.lockedHighQuality) then
                qualities[#qualities + 1] = member.quality
            end
        end
        table.sort(qualities, function(a, b) return a > b end)
        -- Count different item IDs and keep every piece tied with the third-best quality.
        local cutoff = qualities[3] or 0
        for _, member in ipairs(members) do
            if member.quality >= cutoff and member.quality < 3 then
                setPieces[member.id] = true
            end
        end
    end

    return {
        setPieces = setPieces,
        locked = locked,
        supplementLocked = supplementLocked,
        highQualityCount = highQualityCount,
        fallback = #available > 0 and available or restricted,
    }
end

local function getRules()
    if not rules then rules = buildRules() end
    return rules
end

local function needsReplacement(itemId)
    if itemId <= nullCollectible then return false end
    local item = Isaac.GetItemConfig():GetCollectible(itemId)
    return item and not isHighQuality(item) and not item:HasTags(ItemConfig.TAG_QUEST)
        and not fixedSetPieces[itemId] and not getRules().setPieces[itemId]
end

local function findReplacement(poolType, seed)
    local rng = RNG()
    rng:SetSeed(seed == 0 and 1 or seed, 35)
    local currentRules = getRules()
    local locked = currentRules.locked
    if currentRules.supplementLocked and rng:RandomInt(currentRules.highQualityCount) < #locked then
        return locked[rng:RandomInt(#locked) + 1]
    end

    local config = Isaac.GetItemConfig()
    local pool = game:GetItemPool()
    if poolType == ItemPoolType.POOL_NULL then
        poolType = ItemPoolType.POOL_TREASURE
    end

    for _ = 1, maxPoolRolls do
        local rollSeed = rng:Next()
        -- These sample draws invoke the same callback without depleting the pool.
        samplingPool = true
        local itemId = pool:GetCollectible(poolType, false, rollSeed == 0 and 1 or rollSeed)
        samplingPool = false
        local item = itemId > nullCollectible and config:GetCollectible(itemId)
        if isOrdinaryCollectible(item) and isHighQuality(item) and item:IsAvailable() then
            return itemId
        end
    end

    local candidates = currentRules.fallback
    if #candidates > 0 then
        return candidates[rng:RandomInt(#candidates) + 1]
    end
end

local function onGetCollectible(_, itemId, poolType, _decrease, seed)
    if not samplingPool and needsReplacement(itemId) then
        return findReplacement(poolType, seed)
    end
end

local function replaceFromRoomPool(itemId, seed)
    if not needsReplacement(itemId) then return end
    local room = game:GetRoom()
    local poolType = game:GetItemPool():GetPoolForRoom(room:GetType(), room:GetSpawnSeed())
    return findReplacement(poolType, seed)
end

-- Explicit drops bypass item-pool selection. Upgrade their subtype before
-- the engine builds the pedestal and its native options.
local function onEntitySpawn(_, entityType, variant, subtype, _position, _velocity, _spawner, seed)
    if entityType ~= pickupType or variant ~= collectibleVariant then return end
    local itemId = replaceFromRoomPool(subtype, seed)
    if itemId then return { entityType, variant, itemId, seed } end
end

local function onRoomEntitySpawn(_, entityType, variant, subtype, _gridIndex, seed)
    if entityType ~= pickupType or variant ~= collectibleVariant then return end
    local itemId = replaceFromRoomPool(subtype, seed)
    if itemId then return { entityType, variant, itemId } end
end

local function playersCanRotatePedestals()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        local playerType = player:GetPlayerType()
        if playerType == PlayerType.PLAYER_ISAAC_B
            or (playerType == PlayerType.PLAYER_ISAAC and player:HasCollectible(collectibles.COLLECTIBLE_BIRTHRIGHT))
            or player:HasCollectible(collectibles.COLLECTIBLE_GLITCHED_CROWN)
            or player:HasCollectible(collectibles.COLLECTIBLE_BINGE_EATER) then
            return true
        end
    end
    return false
end

local function onPickupUpdate(_, pickup)
    -- Morph recreates the pedestal's options. Pool rolls have already been
    -- filtered, so do not touch a native cycle or its Binge Eater food slot.
    local data = pickup:GetData()
    if data.JustWinKeepCycle then return end
    if playersCanRotatePedestals() then
        data.JustWinKeepCycle = true
        return
    end

    if not needsReplacement(pickup.SubType) then return end
    if pickup.GetCollectibleCycle then
        local cycle = pickup:GetCollectibleCycle()
        if #cycle > 1 or (#cycle == 1 and cycle[1] ~= pickup.SubType) then return end
    end

    local itemId = replaceFromRoomPool(pickup.SubType, pickup.InitSeed)
    if not itemId then return end

    local price, shopItemId, autoUpdatePrice = pickup.Price, pickup.ShopItemId, pickup.AutoUpdatePrice
    local optionsIndex = pickup.OptionsPickupIndex
    local wait, timeout = pickup.Wait, pickup.Timeout
    pickup:Morph(pickupType, collectibleVariant, itemId, true, true, false)
    pickup.Price, pickup.ShopItemId, pickup.AutoUpdatePrice = price, shopItemId, autoUpdatePrice
    pickup.OptionsPickupIndex = optionsIndex
    pickup.Wait, pickup.Timeout = wait, timeout
    pickup.Touched = false
end

local function onSoulOfIsaac()
    for _, pickup in ipairs(Isaac.FindByType(pickupType, collectibleVariant)) do
        pickup:GetData().JustWinKeepCycle = true
    end
end

local function updateRoomPickups()
    for _, entity in ipairs(Isaac.FindByType(pickupType, collectibleVariant)) do
        onPickupUpdate(mod, entity:ToPickup())
    end
end

local function resetRules()
    rules = nil
end

local function onGameStarted()
    resetRules()
    updateRoomPickups()
end

mod:AddCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, onGetCollectible)
mod:AddCallback(ModCallbacks.MC_PRE_ENTITY_SPAWN, onEntitySpawn)
mod:AddCallback(ModCallbacks.MC_PRE_ROOM_ENTITY_SPAWN, onRoomEntitySpawn)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, updateRoomPickups)
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, onGameStarted)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, resetRules)
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, onPickupUpdate, collectibleVariant)
mod:AddCallback(ModCallbacks.MC_USE_CARD, onSoulOfIsaac, Card.CARD_SOUL_ISAAC)
